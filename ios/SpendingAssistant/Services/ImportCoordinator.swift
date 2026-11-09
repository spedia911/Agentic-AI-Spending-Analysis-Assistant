import Foundation
import Observation
import UniformTypeIdentifiers
import SpendingDomain

struct ImportJob {
    enum Payload {
        case image(Data, mimeType: String, sourceType: SourceType)
        case json(String, sourceType: SourceType)
        case retry(String)
        case repair(String, sourceId: String)
    }
    var name: String
    var load: @MainActor () async throws -> Payload
}

@MainActor @Observable
final class ImportCoordinator {
    let service: ImportPipelineService
    var isBusy = false
    var completed = 0
    var total = 0
    var outcomes: [ImportOutcome] = []
    var shareFailures: [ShareInboxItem] = []
    var shareMessage: String?
    private(set) var pendingDetails: [ScreenshotImportDetails] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var draining = false
    let inbox: URL?

    init(service: ImportPipelineService, inbox: URL? = ShareInboxService.inboxDirectory) {
        self.service = service; self.inbox = inbox
    }

    var summary: String {
        let imported = outcomes.filter { $0.status == .imported }.count
        let duplicate = outcomes.filter { $0.status == .alreadyImported }.count
        let failed = outcomes.filter { $0.status == .failed }.count
        let waiting = outcomes.filter { $0.status == .needsDetails }.count
        return "\(imported) imported · \(duplicate) already imported · \(failed) failed" + (waiting > 0 ? " · \(waiting) need details" : "")
    }

    @discardableResult
    func run(_ jobs: [ImportJob]) async -> [ImportOutcome] {
        guard !jobs.isEmpty else { return [] }
        if isBusy { await withCheckedContinuation { waiters.append($0) } } else { isBusy = true }
        completed = 0; total = jobs.count; outcomes = []
        let batchID = UUID()
        defer {
            if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
        }
        for job in jobs {
            let result: ImportOutcome
            do {
                switch try await job.load() {
                case let .image(data, mime, type):
                    result = await service.importImage(data: data, fileName: job.name, mimeType: mime, sourceType: type,
                        options: ScreenshotParseOptions(cardName: UserDefaults.standard.string(forKey: "importCardName"),
                            layout: ScreenshotLayout(rawValue: UserDefaults.standard.string(forKey: "importScreenshotLayout") ?? "") ?? .automatic,
                            observedMonthHint: UserDefaults.standard.string(forKey: "importStatementMonth").flatMap { $0.isEmpty ? nil : $0 }), requestDetails: true)
                case let .json(text, type):
                    result = await service.importAIJSON(text: text, fileName: job.name, sourceType: type)
                case let .retry(id): result = await service.retry(sourceId: id, requestDetails: true)
                case let .repair(text, id): result = await service.importAIJSON(text: text, fileName: job.name, attachingTo: id)
                }
            } catch { result = .failure(job.name, error) }
            var outcome = result
            if var details = result.details {
                details.batchID = batchID
                outcome.details = details
                enqueueDetails(details)
            }
            outcomes.append(outcome); completed += 1
        }
        return outcomes
    }

    func enqueueDetails(_ details: ScreenshotImportDetails) {
        guard !pendingDetails.contains(where: { $0.id == details.id }) else { return }
        pendingDetails.append(details)
    }

    func nextDetails() -> ScreenshotImportDetails? {
        guard !isBusy, !pendingDetails.isEmpty else { return nil }
        return pendingDetails.removeFirst()
    }

    func hasRemainingDates(in request: ScreenshotImportDetails) -> Bool {
        guard let batch = request.batchID else { return false }
        return pendingDetails.contains { $0.batchID == batch && $0.needsYear }
    }

    func hasRemainingAccounts(in request: ScreenshotImportDetails) -> Bool {
        guard let batch = request.batchID else { return false }
        return pendingDetails.contains { $0.batchID == batch && $0.needsAccount }
    }

    func updateSources(ids: Set<String>, period: String?, account: String?) async throws -> [ImportOutcome] {
        if isBusy { await withCheckedContinuation { waiters.append($0) } } else { isBusy = true }
        defer { if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() } }
        let results = try await service.applySourceBatch(ids: ids, period: period, account: account)
        for result in results {
            guard let id = result.source?.sourceDocumentId else { continue }
            if let index = pendingDetails.firstIndex(where: { $0.id == id }) {
                if var updated = result.details {
                    updated.batchID = pendingDetails[index].batchID
                    pendingDetails[index] = updated
                } else { pendingDetails.remove(at: index) }
            }
            replaceOutcome(result, sourceId: id)
        }
        return results
    }

    func finishDetails(_ request: ScreenshotImportDetails, account: String, month: String, fallbackDate: String?,
                       reusePeriod: Bool = false, reuseAccount: Bool = false) async -> ImportOutcome {
        if isBusy { await withCheckedContinuation { waiters.append($0) } } else { isBusy = true }
        defer { if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() } }
        let result = await service.completeScreenshotDetails(id: request.id, account: account, month: month, fallbackDate: fallbackDate)
        if result.status == .imported || result.status == .alreadyImported {
            replaceOutcome(result, sourceId: request.id)
            let sharedPeriod = reusePeriod && Normalizer.isValidStatementDateHint(month) ? month : nil
            let sharedAccount = reuseAccount && PrivacyRedactor.maskAccountLabel(account) != "Unknown account" ? account : nil
            if let batch = request.batchID, sharedPeriod != nil || sharedAccount != nil {
                let remaining = pendingDetails.filter {
                    $0.batchID == batch && (($0.needsYear && sharedPeriod != nil) || ($0.needsAccount && sharedAccount != nil))
                }
                for candidate in remaining {
                    var updated = await service.applySharedScreenshotDetails(period: sharedPeriod, account: sharedAccount, to: candidate)
                    if let index = pendingDetails.firstIndex(where: { $0.id == candidate.id }) {
                        if var details = updated.details {
                            details.batchID = batch
                            updated.details = details
                            pendingDetails[index] = details
                        } else {
                            pendingDetails.remove(at: index)
                        }
                    }
                    replaceOutcome(updated, sourceId: candidate.id)
                }
            }
        }
        return result
    }

    private func replaceOutcome(_ outcome: ImportOutcome, sourceId: String) {
        if let index = outcomes.firstIndex(where: { $0.source?.sourceDocumentId == sourceId }) {
            outcomes[index] = outcome
        }
    }

    func drainShareInbox() async {
        guard !draining else { return }
        draining = true; defer { draining = false }
        do {
            guard let inbox else { return }
            let items = try ShareInboxService.items(in: inbox)
            var results: [ImportOutcome] = []
            for item in items where item.error == nil {
                results += await processShare(item)
            }
            shareFailures = try ShareInboxService.items(in: inbox).filter { $0.error != nil }
            if !results.isEmpty {
                shareMessage = "From Share: \(results.filter { $0.status == .imported }.count) imported, \(results.filter { $0.status == .alreadyImported }.count) already imported, \(results.filter { $0.status == .failed }.count) failed." + (results.contains(where: { $0.status == .needsDetails }) ? " Some screenshots need details." : "")
            }
        } catch { shareMessage = PrivacyRedactor.safeErrorDetail(error) }
    }

    func retryShare(_ item: ShareInboxItem) async {
        _ = await processShare(item)
        refreshShareFailures()
    }

    private func processShare(_ item: ShareInboxItem) async -> [ImportOutcome] {
        let results = await run([ImportJob(name: item.url.lastPathComponent) {
            if ["txt", "json"].contains(item.url.pathExtension.lowercased()) {
                return .json(try String(contentsOf: item.url, encoding: .utf8), sourceType: .share)
            }
            let type = UTType(filenameExtension: item.url.pathExtension)
            return .image(try Data(contentsOf: item.url), mimeType: type?.preferredMIMEType ?? "image/jpeg", sourceType: .share)
        }])
        guard let result = results.first else { return [] }
        do {
            if result.status == .failed {
                try ShareInboxService.markFailed(item, message: result.error ?? "Import failed.")
            } else {
                try ShareInboxService.delete(item)
            }
        } catch { shareMessage = "Share handoff: " + PrivacyRedactor.safeErrorDetail(error) }
        return results
    }

    func deleteShare(_ item: ShareInboxItem) {
        do { try ShareInboxService.delete(item); refreshShareFailures() }
        catch { shareMessage = PrivacyRedactor.safeErrorDetail(error) }
    }

    private func refreshShareFailures() {
        do {
            if let inbox { shareFailures = try ShareInboxService.items(in: inbox).filter { $0.error != nil } }
        } catch { shareMessage = PrivacyRedactor.safeErrorDetail(error) }
    }
}

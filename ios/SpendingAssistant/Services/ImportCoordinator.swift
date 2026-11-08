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
        return "\(imported) imported · \(duplicate) already imported · \(failed) failed"
    }

    @discardableResult
    func run(_ jobs: [ImportJob]) async -> [ImportOutcome] {
        guard !jobs.isEmpty else { return [] }
        if isBusy { await withCheckedContinuation { waiters.append($0) } } else { isBusy = true }
        completed = 0; total = jobs.count; outcomes = []
        defer {
            if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
        }
        for job in jobs {
            let result: ImportOutcome
            do {
                switch try await job.load() {
                case let .image(data, mime, type):
                    result = await service.importImage(data: data, fileName: job.name, mimeType: mime, sourceType: type)
                case let .json(text, type):
                    result = await service.importAIJSON(text: text, fileName: job.name, sourceType: type)
                case let .retry(id): result = await service.retry(sourceId: id)
                case let .repair(text, id): result = await service.importAIJSON(text: text, fileName: job.name, attachingTo: id)
                }
            } catch { result = .failure(job.name, error) }
            outcomes.append(result); completed += 1
        }
        return outcomes
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
                shareMessage = "From Share: \(results.filter { $0.status == .imported }.count) imported, \(results.filter { $0.status == .alreadyImported }.count) already imported, \(results.filter { $0.status == .failed }.count) failed."
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

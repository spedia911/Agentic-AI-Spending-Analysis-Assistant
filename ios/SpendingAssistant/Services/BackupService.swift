import Foundation
import SwiftData
import SpendingDomain

@MainActor
struct BackupService {
    let store: LocalStore
    let files: SourceFileStore
    var journalURL: URL { files.directory.appendingPathComponent("restore-journal.json") }
    struct Journal: Codable { var operationId: String; var newPaths: [String]; var oldPaths: [String] }
    struct Preview {
        var records: BackupPayload
        var package: PortableBackup?
        var warning: String
    }
    func records() throws -> BackupPayload {
        let tx = try store.allTransactions(), assets = try store.allAssets(), reviews = try store.allReviews()
        let summaries = SummaryGenerator.generate(transactions: tx, assetSnapshots: assets.filter { Eligibility.asset($0, reviews: reviews, peers: assets).local })
        return BackupPayload(sourceDocuments: try store.allSources(), transactions: tx, assetSnapshots: assets,
            reviewItems: reviews, corrections: try store.allCorrections(), monthlySummaries: summaries.monthlySummaries,
            quarterlySummaries: summaries.quarterlySummaries, cashFlowSummaries: summaries.cashFlowSummaries,
            assetTrends: summaries.assetTrends, anomalies: try store.allAnomalies())
    }
    func export(includeOriginals: Bool) throws -> Data {
        let payload = try records()
        var attachments: [BackupAttachment] = []
        for source in payload.sourceDocuments {
            guard let path = source.localRelativePath else { attachments.append(.init(sourceId: source.id, status: ["omitted", "expired", "missing"].contains(source.originalFileStatus ?? "") ? source.originalFileStatus! : "unavailable")); continue }
            if source.imageDeletedAt != nil { attachments.append(.init(sourceId: source.id, status: "omitted")); continue }
            let exists = FileManager.default.fileExists(atPath: try files.url(path).path)
            guard exists else { attachments.append(.init(sourceId: source.id, status: source.originalFileStatus == "expired" ? "expired" : "missing")); continue }
            attachments.append(try .init(sourceId: source.id, status: includeOriginals ? "included" : "omitted", data: includeOriginals ? files.read(path) : nil))
        }
        var datasetId = ""
        try store.commit { datasetId = try store.dataset().datasetId }
        let backup = try PortableBackup(records: payload, accounts: store.allAccounts(), datasetId: datasetId, attachments: attachments)
        _ = try backup.validatedRecords()
        return try backup.encoded()
    }
    func preview(_ data: Data) throws -> Preview {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if object?["schemaVersion"] != nil {
            let package = try PortableBackup.decoder().decode(PortableBackup.self, from: data)
            let records = try package.validatedRecords()
            return Preview(records: records, package: package, warning: "Replaces this app’s dataset. Independently edited copies do not synchronize. \(package.attachments.filter { $0.status != "included" }.count) originals unavailable in this backup.")
        }
        var records = try PortableBackup.decoder().decode(BackupPayload.self, from: data)
        for i in records.transactions.indices { records.transactions[i].accountId = nil; records.transactions[i].currencyCode = nil }
        for i in records.assetSnapshots.indices { records.assetSnapshots[i].accountId = nil; records.assetSnapshots[i].currencyCode = nil }
        for i in records.sourceDocuments.indices {
            records.sourceDocuments[i].localRelativePath = nil
            records.sourceDocuments[i].importAccountId = nil
        }
        try PortableBackup.validate(records, accounts: [])
        return Preview(records: records, package: nil, warning: "Legacy backup: account/currency mapping required. Original files are unavailable. Replaces this app’s dataset.")
    }
    /// New immutable files are staged first. The journal and DB operation marker make crash recovery deterministic.
    func restore(_ preview: Preview) throws {
        try recover()
        var records = preview.records
        if let package = preview.package { records = try package.validatedRecords() }
        let operationId = UUID().uuidString
        let originals = Dictionary(uniqueKeysWithValues: (preview.package?.attachments ?? []).map { ($0.sourceId, $0) })
        var journal = Journal(operationId: operationId, newPaths: [], oldPaths: try store.allSources().compactMap(\.localRelativePath))
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        // Persist each intended path before writing bytes: recovery also covers interruption during a write.
        do {
            for i in records.sourceDocuments.indices {
                let source = records.sourceDocuments[i]
                records.sourceDocuments[i].localRelativePath = nil
                records.sourceDocuments[i].originalFileStatus = originals[source.id]?.status ?? "unavailable"
                if let data = originals[source.id]?.data {
                    let ext = URL(fileURLWithPath: source.fileName).pathExtension.filter { $0.isLetter || $0.isNumber }
                    let path = "restore-\(UUID().uuidString).\(ext.isEmpty ? "bin" : String(ext.prefix(10)))"
                    journal.newPaths.append(path)
                    try JSONEncoder().encode(journal).write(to: journalURL, options: [.atomic, .completeFileProtection])
                    try data.write(to: files.url(path), options: [.atomic, .completeFileProtection])
                    records.sourceDocuments[i].localRelativePath = path
                }
            }
            try JSONEncoder().encode(journal).write(to: journalURL, options: [.atomic, .completeFileProtection])
            try store.commit(rebuild: true) {
                // Individual deletions are staged and participate in ModelContext rollback.
                for row in try store.modelContext.fetch(FetchDescriptor<SDSourceDocument>()) { store.modelContext.delete(row) }
                for row in try store.modelContext.fetch(FetchDescriptor<SDTransaction>()) { store.modelContext.delete(row) }
                for row in try store.modelContext.fetch(FetchDescriptor<SDAssetSnapshot>()) { store.modelContext.delete(row) }
                for row in try store.modelContext.fetch(FetchDescriptor<SDReviewItem>()) { store.modelContext.delete(row) }
                for row in try store.modelContext.fetch(FetchDescriptor<SDCorrection>()) { store.modelContext.delete(row) }
                for row in try store.modelContext.fetch(FetchDescriptor<SDAccount>()) { store.modelContext.delete(row) }
                for row in records.sourceDocuments { store.modelContext.insert(SDSourceDocument(from: row)) }
                for row in records.transactions { store.modelContext.insert(SDTransaction(from: row)) }
                for row in records.assetSnapshots { store.modelContext.insert(SDAssetSnapshot(from: row)) }
                for row in records.reviewItems { store.modelContext.insert(SDReviewItem(from: row)) }
                for row in records.corrections { store.modelContext.insert(SDCorrection(from: row)) }
                for row in preview.package?.accounts ?? [] { store.modelContext.insert(SDAccount(id: row.id, label: row.label, currencyCode: row.currencyCode, preferredSpendingCurrency: row.preferredSpendingCurrency)) }
                let dataset = try store.dataset(); dataset.datasetId = preview.package?.datasetId ?? UUID().uuidString; dataset.restoredSnapshotId = operationId
            }
        } catch {
            try? recover()
            throw error
        }
        // Once committed, cleanup may be retried on next launch; never report a committed restore as rolled back.
        try? recover()
    }
    func recover() throws {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        let committed = try store.modelContext.fetch(FetchDescriptor<SDDataset>()).first?.restoredSnapshotId == journal.operationId
        let referenced = Set(try store.allSources().compactMap(\.localRelativePath))
        for path in committed ? journal.oldPaths : journal.newPaths where !referenced.contains(path) {
            let url = try files.url(path)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try FileManager.default.removeItem(at: journalURL)
    }
}

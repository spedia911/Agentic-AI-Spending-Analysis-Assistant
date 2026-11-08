import Foundation
import SwiftData
import SpendingDomain

@MainActor
final class LocalStore {
    let modelContext: ModelContext

    var beforeSave: (() throws -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        modelContext.autosaveEnabled = false
    }

    func upsert(source: SourceDocumentRecord) throws {
        let id = source.sourceDocumentId
        let descriptor = FetchDescriptor<SDSourceDocument>(predicate: #Predicate { $0.sourceDocumentId == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(source)
        } else {
            modelContext.insert(SDSourceDocument(from: source))
        }
    }

    func upsert(transaction: TransactionRecord) throws {
        let id = transaction.transactionId
        let descriptor = FetchDescriptor<SDTransaction>(predicate: #Predicate { $0.transactionId == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(transaction)
        } else {
            modelContext.insert(SDTransaction(from: transaction))
        }
    }

    func upsert(asset: AssetSnapshotRecord) throws {
        let id = asset.assetSnapshotId
        let descriptor = FetchDescriptor<SDAssetSnapshot>(predicate: #Predicate { $0.assetSnapshotId == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(asset)
        } else {
            modelContext.insert(SDAssetSnapshot(from: asset))
        }
    }

    func upsert(review: ReviewItemRecord) throws {
        let id = review.reviewItemId
        let descriptor = FetchDescriptor<SDReviewItem>(predicate: #Predicate { $0.reviewItemId == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(review)
        } else {
            modelContext.insert(SDReviewItem(from: review))
        }
    }

    func insert(correction: CorrectionRecord) throws {
        let id = correction.correctionId
        let descriptor = FetchDescriptor<SDCorrection>(predicate: #Predicate { $0.correctionId == id })
        if (try modelContext.fetch(descriptor).first) == nil {
            modelContext.insert(SDCorrection(from: correction))
        }
    }

    func replaceSummaries(_ result: SummaryResult, anomalies: [AnomalyRecord]) throws {
        // Bulk delete(model:) can reach the persistent store before save and cannot
        // participate in this rollback boundary. Stage individual deletions instead.
        for row in try modelContext.fetch(FetchDescriptor<SDMonthlySummary>()) { modelContext.delete(row) }
        for row in try modelContext.fetch(FetchDescriptor<SDCashFlowSummary>()) { modelContext.delete(row) }
        for row in try modelContext.fetch(FetchDescriptor<SDAnomaly>()) { modelContext.delete(row) }
        for row in result.monthlySummaries {
            modelContext.insert(SDMonthlySummary(from: row))
        }
        for row in result.cashFlowSummaries {
            modelContext.insert(SDCashFlowSummary(from: row))
        }
        for anomaly in anomalies {
            modelContext.insert(SDAnomaly(from: anomaly))
        }
    }

    func allSources() throws -> [SourceDocumentRecord] {
        try modelContext.fetch(FetchDescriptor<SDSourceDocument>()).map { $0.toRecord() }
    }

    func allTransactions() throws -> [TransactionRecord] {
        try modelContext.fetch(FetchDescriptor<SDTransaction>()).map { $0.toRecord() }
    }

    func allAssets() throws -> [AssetSnapshotRecord] {
        try modelContext.fetch(FetchDescriptor<SDAssetSnapshot>()).map { $0.toRecord() }
    }

    func allReviews() throws -> [ReviewItemRecord] {
        try modelContext.fetch(FetchDescriptor<SDReviewItem>()).map { $0.toRecord() }
    }

    func allCorrections() throws -> [CorrectionRecord] {
        try modelContext.fetch(FetchDescriptor<SDCorrection>()).map { $0.toRecord() }
    }

    func allMonthlySummaries() throws -> [MonthlySummaryRecord] {
        try modelContext.fetch(FetchDescriptor<SDMonthlySummary>()).map { $0.toRecord() }
    }

    func allCashFlows() throws -> [CashFlowSummaryRecord] {
        try modelContext.fetch(FetchDescriptor<SDCashFlowSummary>()).map { $0.toRecord() }
    }

    func allAnomalies() throws -> [AnomalyRecord] {
        try modelContext.fetch(FetchDescriptor<SDAnomaly>()).map { $0.toRecord() }
    }

    /// All UI and import writes use an explicit commit. No await occurs inside this boundary.
    func commit(rebuild: Bool = false, _ changes: () throws -> Void) throws {
        do {
            try changes()
            if rebuild { try rebuildDerived() }
            try beforeSave?()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func source(id: String) throws -> SourceDocumentRecord? {
        let descriptor = FetchDescriptor<SDSourceDocument>(predicate: #Predicate { $0.sourceDocumentId == id })
        return try modelContext.fetch(descriptor).first?.toRecord()
    }

    func source(fingerprint: String) throws -> SourceDocumentRecord? {
        // Prefer an already completed legacy source when historical duplicates exist.
        try allSources().filter {
            if $0.contentFingerprint == fingerprint { return true }
            guard let text = $0.importedJSON, let parsed = try? ExtractionJSONParser.parse(text) else { return false }
            return (try? ContentFingerprint.json(parsed)) == fingerprint
        }.sorted {
            if ($0.status == .processed) != ($1.status == .processed) { return $0.status == .processed }
            return ($0.createdTime, $0.sourceDocumentId) < ($1.createdTime, $1.sourceDocumentId)
        }.first
    }

    func hasRows(sourceId: String) throws -> Bool {
        try allTransactions().contains { $0.sourceDocumentId == sourceId }
            || allAssets().contains { $0.sourceDocumentId == sourceId }
    }

    func rebuildDerived() throws {
        let transactions = try allTransactions()
        let assets = try allAssets()
        let rebuilt = ProcessingPipeline.rebuildSummaries(transactions: transactions, assets: assets)
        try replaceSummaries(rebuilt.summaries, anomalies: rebuilt.anomalies)
    }
}

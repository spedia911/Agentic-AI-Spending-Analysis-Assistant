import Foundation
import SwiftData
import SpendingDomain

@MainActor
final class LocalStore {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func upsert(source: SourceDocumentRecord) {
        let id = source.sourceDocumentId
        let descriptor = FetchDescriptor<SDSourceDocument>(predicate: #Predicate { $0.sourceDocumentId == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.apply(source)
        } else {
            modelContext.insert(SDSourceDocument(from: source))
        }
    }

    func upsert(transaction: TransactionRecord) {
        let id = transaction.transactionId
        let descriptor = FetchDescriptor<SDTransaction>(predicate: #Predicate { $0.transactionId == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.apply(transaction)
        } else {
            modelContext.insert(SDTransaction(from: transaction))
        }
    }

    func upsert(asset: AssetSnapshotRecord) {
        let id = asset.assetSnapshotId
        let descriptor = FetchDescriptor<SDAssetSnapshot>(predicate: #Predicate { $0.assetSnapshotId == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.apply(asset)
        } else {
            modelContext.insert(SDAssetSnapshot(from: asset))
        }
    }

    func upsert(review: ReviewItemRecord) {
        let id = review.reviewItemId
        let descriptor = FetchDescriptor<SDReviewItem>(predicate: #Predicate { $0.reviewItemId == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.apply(review)
        } else {
            modelContext.insert(SDReviewItem(from: review))
        }
    }

    func insert(correction: CorrectionRecord) {
        let id = correction.correctionId
        let descriptor = FetchDescriptor<SDCorrection>(predicate: #Predicate { $0.correctionId == id })
        if (try? modelContext.fetch(descriptor).first) == nil {
            modelContext.insert(SDCorrection(from: correction))
        }
    }

    func replaceSummaries(_ result: SummaryResult, anomalies: [AnomalyRecord]) throws {
        try modelContext.delete(model: SDMonthlySummary.self)
        try modelContext.delete(model: SDCashFlowSummary.self)
        try modelContext.delete(model: SDAnomaly.self)
        for row in result.monthlySummaries {
            modelContext.insert(SDMonthlySummary(from: row))
        }
        for row in result.cashFlowSummaries {
            modelContext.insert(SDCashFlowSummary(from: row))
        }
        for anomaly in anomalies {
            modelContext.insert(SDAnomaly(from: anomaly))
        }
        try modelContext.save()
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

    func save() throws {
        try modelContext.save()
    }

    func rebuildDerived() throws {
        let transactions = try allTransactions()
        let assets = try allAssets()
        let rebuilt = ProcessingPipeline.rebuildSummaries(transactions: transactions, assets: assets)
        try replaceSummaries(rebuilt.summaries, anomalies: rebuilt.anomalies)
    }
}

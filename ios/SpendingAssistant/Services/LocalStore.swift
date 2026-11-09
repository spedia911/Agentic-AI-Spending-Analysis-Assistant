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
        let decisions = try allCorrections().filter { $0.targetType == .anomaly && $0.fieldName == "anomaly_status" }
        var statuses: [String: AnomalyStatus] = [:]
        for decision in decisions.sorted(by: { ($0.createdAt, $0.correctionId) < ($1.createdAt, $1.correctionId) }) {
            statuses[decision.targetId] = AnomalyStatus(rawValue: decision.newValue)
        }
        let anomalies = rebuilt.anomalies.map { value in
            var anomaly = value; anomaly.status = statuses[value.id] ?? value.status; return anomaly
        }
        try replaceSummaries(rebuilt.summaries, anomalies: anomalies)
    }
}

extension LocalStore {
    /// Delete dependent records in the same rollback boundary as totals.
    func deleteTransactions(ids: Set<String>) throws {
        try commit(rebuild: true) { try removeRows(ids: ids) }
    }

    func removeConfirmedDuplicates(keeping keepSource: String, removing removeSource: String, matches: [DuplicateBatchMatch]) throws {
        guard !matches.isEmpty else { return }
        let current = Dictionary(uniqueKeysWithValues: DuplicateBatch.matches(keeping: keepSource, removing: removeSource,
            transactions: try allTransactions()).map { ($0.id, $0) })
        guard Set(matches.map(\.id)).count == matches.count, matches.allSatisfy({ current[$0.id] == $0 }) else {
            throw BatchReviewError.matchesChanged
        }
        try commit(rebuild: true) {
            for match in matches {
                try insert(correction: CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                    targetId: match.remove.id, fieldName: "duplicate_removed", oldValue: match.remove.sourceDocumentId,
                    newValue: match.keep.id, applyFuture: false))
            }
            try removeRows(ids: Set(matches.map(\.id)))
        }
    }

    func markAnomalyGroupReviewed(_ type: AnomalyType, ids: Set<String>) throws {
        // Bulk "mark reviewed" stays blocked for duplicate charges — those need pair removal or
        // same-import comparison. Use resolveAnomalies for a specific duplicate after review.
        guard type != .duplicateCharge else { throw BatchReviewError.matchesChanged }
        try resolveAnomalies(ids: ids, type: type)
    }

    /// Resolve specific open anomalies after the user reviewed them (including duplicate charges).
    func resolveAnomalies(ids: Set<String>, type: AnomalyType? = nil) throws {
        let rows = try modelContext.fetch(FetchDescriptor<SDAnomaly>()).filter {
            ids.contains($0.anomalyId)
                && $0.statusRaw == AnomalyStatus.open.rawValue
                && (type == nil || $0.anomalyTypeRaw == type?.rawValue)
        }
        guard !rows.isEmpty else { return }
        try commit {
            for row in rows {
                try insert(correction: CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .anomaly,
                    targetId: row.anomalyId, fieldName: "anomaly_status", oldValue: row.statusRaw,
                    newValue: AnomalyStatus.resolved.rawValue, applyFuture: false))
                row.statusRaw = AnomalyStatus.resolved.rawValue
            }
        }
    }

    private func removeRows(ids: Set<String>) throws {
        let transactions = try modelContext.fetch(FetchDescriptor<SDTransaction>())
        let reviews = try modelContext.fetch(FetchDescriptor<SDReviewItem>())
        let pending = ReviewItemStatus.pending.rawValue
        let knownReviewIds = Set(reviews.filter { !ids.contains($0.targetId) }.map(\.reviewItemId))
        var changedTargets: Set<String> = []
        var pendingTargets: Set<String> = []
        for row in reviews {
            if ids.contains(row.targetId) { modelContext.delete(row) }
            else if row.statusRaw == pending, row.issueTypeRaw == ReviewIssueType.duplicateRisk.rawValue,
                    let field = row.fieldName, field.hasPrefix("duplicate:"),
                    ids.contains(String(field.dropFirst("duplicate:".count))) {
                row.statusRaw = ReviewItemStatus.resolved.rawValue
                row.userAnswer = "Matching transaction was deleted"
                row.resolvedAt = Date()
                changedTargets.insert(row.targetId)
            } else if row.statusRaw == pending && !row.toRecord().isAdvisory {
                pendingTargets.insert(row.targetId)
            }
        }
        let remaining = changedTargets.isEmpty ? [] : transactions.filter { !ids.contains($0.transactionId) }.map { $0.toRecord() }
        for row in transactions {
            if ids.contains(row.transactionId) { modelContext.delete(row) }
            else if changedTargets.contains(row.transactionId) {
                if row.validationStatusRaw != ValidationStatus.rejected.rawValue,
                   let replacement = Validator.validate([row.toRecord()], existingTransactions: remaining).reviewItems.first(where: { $0.issueType == .duplicateRisk }),
                   !knownReviewIds.contains(replacement.reviewItemId) {
                    modelContext.insert(SDReviewItem(from: replacement))
                    pendingTargets.insert(row.transactionId)
                }
                if !pendingTargets.contains(row.transactionId) {
                    if row.validationStatusRaw != ValidationStatus.rejected.rawValue { row.validationStatusRaw = ValidationStatus.valid.rawValue }
                    row.reviewStatusRaw = ReviewStatus.resolved.rawValue
                }
            }
        }
        // Correction history is retained for audit and remembered merchant rules.
    }

    func deleteSource(id: String) throws {
        try commit(rebuild: true) {
            let ids = Set(try allTransactions().filter { $0.sourceDocumentId == id }.map(\.transactionId))
                .union(try allAssets().filter { $0.sourceDocumentId == id }.map(\.assetSnapshotId)).union([id])
            try removeRows(ids: ids)
            for row in try modelContext.fetch(FetchDescriptor<SDAssetSnapshot>()) where row.sourceDocumentId == id { modelContext.delete(row) }
            for row in try modelContext.fetch(FetchDescriptor<SDSourceDocument>()) where row.sourceDocumentId == id { modelContext.delete(row) }
        }
    }
}

extension LocalStore {
    func deleteAsset(id: String) throws {
        try commit(rebuild: true) {
            for row in try modelContext.fetch(FetchDescriptor<SDAssetSnapshot>()) where row.assetSnapshotId == id { modelContext.delete(row) }
            for row in try modelContext.fetch(FetchDescriptor<SDReviewItem>()) where row.targetTypeRaw == ReviewTargetType.assetSnapshot.rawValue && row.targetId == id { modelContext.delete(row) }
        }
    }

    func saveReviewedAsset(_ asset: AssetSnapshotRecord) throws {
        try commit(rebuild: true) {
            guard let before = try allAssets().first(where: { $0.assetSnapshotId == asset.assetSnapshotId }) else { throw ReviewError.missingTarget }
            try upsert(asset: asset)
            let edits = [
                ("observed_date", before.observedDate, asset.observedDate),
                ("account_label", before.accountLabel, asset.accountLabel),
                ("balance", String(before.balance), String(asset.balance)),
                ("balance_type", before.balanceType.rawValue, asset.balanceType.rawValue)
            ]
            for (field, old, new) in edits where old != new {
                try insert(correction: CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .assetSnapshot,
                    targetId: asset.assetSnapshotId, fieldName: field, oldValue: old, newValue: new, applyFuture: false, createdAt: Date()))
            }
            for var review in try allReviews() where review.targetType == .assetSnapshot && review.targetId == asset.assetSnapshotId && review.status == .pending {
                review.status = .resolved
                review.resolvedAt = Date()
                review.userAnswer = "Balance checked against source"
                try upsert(review: review)
            }
        }
    }
}


extension LocalStore {
    /// Older builds marked advisory-only rows as required; preserve their evidence and issue history.
    func reconcileAdvisoryReviews() throws {
        let pending = try allReviews().filter { $0.targetType == .transaction && $0.status == .pending }
        let advisoryOnly = Set(pending.filter(\.isAdvisory).map(\.targetId))
            .subtracting(pending.filter { !$0.isAdvisory }.map(\.targetId))
        guard !advisoryOnly.isEmpty else { return }
        let legacy = try allTransactions().filter { advisoryOnly.contains($0.transactionId) && $0.validationStatus == .needsReview }
        guard !legacy.isEmpty else { return }
        try commit(rebuild: true) {
            for var transaction in legacy {
                transaction.validationStatus = .valid
                if transaction.reviewStatus == .pending { transaction.reviewStatus = .none }
                try upsert(transaction: transaction)
            }
        }
    }
}


enum BatchReviewError: LocalizedError {
    case matchesChanged
    var errorDescription: String? { "The matching transactions changed. Review the current matches before trying again." }
}

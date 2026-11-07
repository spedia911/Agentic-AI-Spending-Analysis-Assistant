import Foundation

public struct CorrectionApplication: Sendable {
    public var transactions: [TransactionRecord]
    public var reviewItems: [ReviewItemRecord]
    public var corrections: [CorrectionRecord]
    public var anomalies: [AnomalyRecord]

    public init(transactions: [TransactionRecord], reviewItems: [ReviewItemRecord], corrections: [CorrectionRecord], anomalies: [AnomalyRecord] = []) {
        self.transactions = transactions
        self.reviewItems = reviewItems
        self.corrections = corrections
        self.anomalies = anomalies
    }
}

public enum CorrectionApplier {
    public static func applyCategoryCorrection(
        transactionId: String,
        newCategory: SpendingCategory,
        remember: Bool,
        transactions: [TransactionRecord],
        reviewItems: [ReviewItemRecord],
        now: Date = Date()
    ) -> CorrectionApplication {
        var updatedTransactions = transactions
        var updatedReviews = reviewItems
        var newCorrections: [CorrectionRecord] = []

        guard let index = updatedTransactions.firstIndex(where: { $0.transactionId == transactionId }) else {
            return CorrectionApplication(transactions: transactions, reviewItems: reviewItems, corrections: [])
        }

        let old = updatedTransactions[index]
        updatedTransactions[index].category = newCategory
        updatedTransactions[index].categoryConfidence = 1
        updatedTransactions[index].validationStatus = .valid
        updatedTransactions[index].reviewStatus = .resolved
        updatedTransactions[index].updatedAt = now

        newCorrections.append(CorrectionRecord(
            correctionId: "corr_" + StableHash.make([transactionId, "category", newCategory.rawValue, now.timeIntervalSince1970]),
            targetType: .transaction,
            targetId: transactionId,
            fieldName: "category",
            oldValue: old.category.rawValue,
            newValue: newCategory.rawValue,
            applyFuture: remember,
            createdAt: now
        ))

        if remember {
            newCorrections.append(CorrectionRecord(
                correctionId: "corr_" + StableHash.make(["merchant_rule", old.merchantNormalized, newCategory.rawValue]),
                targetType: .merchantRule,
                targetId: old.merchantNormalized,
                fieldName: "category",
                oldValue: old.category.rawValue,
                newValue: newCategory.rawValue,
                applyFuture: true,
                createdAt: now
            ))
        }

        for i in updatedReviews.indices where updatedReviews[i].targetId == transactionId && updatedReviews[i].status == .pending {
            updatedReviews[i].status = .resolved
            updatedReviews[i].userAnswer = newCategory.rawValue
            updatedReviews[i].resolvedAt = now
        }

        return CorrectionApplication(transactions: updatedTransactions, reviewItems: updatedReviews, corrections: newCorrections)
    }

    public static func applyValidationStatus(
        transactionId: String,
        status: ValidationStatus,
        transactions: [TransactionRecord],
        reviewItems: [ReviewItemRecord],
        now: Date = Date()
    ) -> CorrectionApplication {
        var updatedTransactions = transactions
        var updatedReviews = reviewItems
        guard let index = updatedTransactions.firstIndex(where: { $0.transactionId == transactionId }) else {
            return CorrectionApplication(transactions: transactions, reviewItems: reviewItems, corrections: [])
        }
        let old = updatedTransactions[index].validationStatus
        updatedTransactions[index].validationStatus = status
        updatedTransactions[index].reviewStatus = .resolved
        updatedTransactions[index].updatedAt = now
        for i in updatedReviews.indices where updatedReviews[i].targetId == transactionId && updatedReviews[i].status == .pending {
            updatedReviews[i].status = .resolved
            updatedReviews[i].userAnswer = status.rawValue
            updatedReviews[i].resolvedAt = now
        }
        let correction = CorrectionRecord(
            correctionId: "corr_" + StableHash.make([transactionId, "validation_status", status.rawValue]),
            targetType: .transaction,
            targetId: transactionId,
            fieldName: "validation_status",
            oldValue: old.rawValue,
            newValue: status.rawValue,
            applyFuture: false,
            createdAt: now
        )
        return CorrectionApplication(transactions: updatedTransactions, reviewItems: updatedReviews, corrections: [correction])
    }

    public static func resolveAnomaly(
        anomalyId: String,
        status: AnomalyStatus,
        anomalies: [AnomalyRecord],
        now: Date = Date()
    ) -> (anomalies: [AnomalyRecord], correction: CorrectionRecord?) {
        var updated = anomalies
        guard let index = updated.firstIndex(where: { $0.anomalyId == anomalyId }) else {
            return (anomalies, nil)
        }
        let old = updated[index].status
        updated[index].status = status
        let correction = CorrectionRecord(
            correctionId: "corr_" + StableHash.make([anomalyId, "anomaly_status", status.rawValue]),
            targetType: .anomaly,
            targetId: anomalyId,
            fieldName: "anomaly_status",
            oldValue: old.rawValue,
            newValue: status.rawValue,
            applyFuture: false,
            createdAt: now
        )
        return (updated, correction)
    }
}

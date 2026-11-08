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
                correctionId: "corr_" + StableHash.make(["merchant_rule", old.merchantNormalized, newCategory.rawValue, now.timeIntervalSince1970, UUID().uuidString]),
                targetType: .merchantRule,
                targetId: old.merchantNormalized,
                fieldName: "category",
                oldValue: old.category.rawValue,
                newValue: newCategory.rawValue,
                applyFuture: true,
                createdAt: now
            ))
        }

        for i in updatedReviews.indices where updatedReviews[i].targetType == .transaction && updatedReviews[i].targetId == transactionId && updatedReviews[i].issueType == .unclearCategory && updatedReviews[i].status == .pending {
            updatedReviews[i].status = .resolved
            updatedReviews[i].userAnswer = newCategory.rawValue
            updatedReviews[i].resolvedAt = now
        }

        refreshStatus(&updatedTransactions[index], reviews: updatedReviews)
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
        guard status != .needsReview else {
            return CorrectionApplication(transactions: transactions, reviewItems: reviewItems, corrections: [])
        }
        let old = updatedTransactions[index].validationStatus
        // This compatibility entry point handles duplicate decisions only.
        for i in updatedReviews.indices where updatedReviews[i].targetType == .transaction && updatedReviews[i].targetId == transactionId && updatedReviews[i].status == .pending && (status == .rejected || updatedReviews[i].issueType == .duplicateRisk) {
            updatedReviews[i].status = .resolved
            updatedReviews[i].userAnswer = status.rawValue
            updatedReviews[i].resolvedAt = now
        }
        if status == .rejected { updatedTransactions[index].validationStatus = .rejected }
        refreshStatus(&updatedTransactions[index], reviews: updatedReviews)
        updatedTransactions[index].updatedAt = now
        let correction = CorrectionRecord(
            correctionId: "corr_" + UUID().uuidString,
            targetType: .transaction, targetId: transactionId, fieldName: "validation_status",
            oldValue: old.rawValue, newValue: status.rawValue, applyFuture: false, createdAt: now
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

public struct TransactionEdit: Sendable {
    public var date: String
    public var merchant: String
    public var amount: Double
    public var type: TransactionType
    public var account: String

    public init(date: String, merchant: String, amount: Double, type: TransactionType, account: String) {
        self.date = date; self.merchant = merchant; self.amount = amount; self.type = type; self.account = account
    }
}

public enum ReviewAction: Sendable {
    case category(SpendingCategory, remember: Bool)
    case edit(TransactionEdit)
    case confirm
    case duplicate(ValidationStatus)
}

public enum ReviewError: Error, LocalizedError {
    case invalidFields, missingTarget, unsupportedAction
    public var errorDescription: String? {
        switch self {
        case .invalidFields: return "Enter a real date (YYYY-MM-DD), a merchant, and a finite nonzero amount."
        case .missingTarget: return "The record for this review is unavailable."
        case .unsupportedAction: return "This action does not apply to this review."
        }
    }
}

extension CorrectionApplier {
    static func refreshStatus(_ transaction: inout TransactionRecord, reviews: [ReviewItemRecord]) {
        let pending = reviews.contains { $0.targetType == .transaction && $0.targetId == transaction.transactionId && $0.status == .pending }
        if transaction.validationStatus != .rejected { transaction.validationStatus = pending ? .needsReview : .valid }
        transaction.reviewStatus = pending ? .pending : .resolved
    }

    public static func apply(
        review: ReviewItemRecord, action: ReviewAction, transactions: [TransactionRecord],
        reviewItems: [ReviewItemRecord], now: Date = Date()
    ) throws -> CorrectionApplication {
        guard review.targetType == .transaction,
              let index = transactions.firstIndex(where: { $0.transactionId == review.targetId }) else { throw ReviewError.missingTarget }
        switch action {
        case let .category(category, remember):
            guard review.issueType == .unclearCategory, category != .uncategorized else { throw ReviewError.unsupportedAction }
            return applyCategoryCorrection(transactionId: review.targetId, newCategory: category, remember: remember, transactions: transactions, reviewItems: reviewItems, now: now)
        case let .duplicate(status):
            guard review.issueType == .duplicateRisk else { throw ReviewError.unsupportedAction }
            if status == .rejected {
                return applyValidationStatus(transactionId: review.targetId, status: status, transactions: transactions, reviewItems: reviewItems, now: now)
            }
            if status == .needsReview { return CorrectionApplication(transactions: transactions, reviewItems: reviewItems, corrections: []) }
            return try confirm(review: review, transactions: transactions, reviews: reviewItems, now: now)
        case .confirm:
            guard [.lowConfidence, .anomaly].contains(review.issueType) else { throw ReviewError.unsupportedAction }
            return try confirm(review: review, transactions: transactions, reviews: reviewItems, now: now)
        case let .edit(edit):
            guard Validator.isValidDate(edit.date), !edit.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  edit.merchant != "Unknown merchant", edit.amount.isFinite, edit.amount != 0 else { throw ReviewError.invalidFields }
            var updated = transactions
            let old = updated[index]
            updated[index].transactionDate = edit.date
            updated[index].observedMonth = String(edit.date.prefix(7))
            updated[index].merchantNormalized = Normalizer.normalizeMerchant(edit.merchant)
            updated[index].amount = edit.amount
            updated[index].transactionType = edit.type
            updated[index].accountLabel = PrivacyRedactor.maskAccountLabel(edit.account)
            updated[index].updatedAt = now
            let result = Validator.validate([updated[index]], context: ValidationContext(now: now), existingTransactions: transactions.filter { $0.transactionId != old.transactionId })
            var reviews = reviewItems
            let generatedIds = Set(result.reviewItems.map(\.reviewItemId))
            // Supersede legacy validation reviews as well as issues corrected by editing.
            for i in reviews.indices where reviews[i].targetType == .transaction && reviews[i].targetId == old.transactionId && reviews[i].issueType != .unclearCategory && reviews[i].status == .pending && !generatedIds.contains(reviews[i].reviewItemId) {
                reviews[i].status = .resolved; reviews[i].resolvedAt = now; reviews[i].userAnswer = "Corrected fields"
            }
            for generated in result.reviewItems {
                if let i = reviews.firstIndex(where: { $0.reviewItemId == generated.reviewItemId }) {
                    let fieldChanged: Bool
                    switch generated.fieldName {
                    case "transaction_date": fieldChanged = old.transactionDate != edit.date
                    case "amount": fieldChanged = old.amount != edit.amount || old.transactionType != edit.type
                    case let field? where field.hasPrefix("duplicate:"):
                        fieldChanged = old.transactionDate != edit.date || old.amount != edit.amount || old.merchantNormalized != edit.merchant
                    default: fieldChanged = false
                    }
                    if fieldChanged { reviews[i] = generated }
                } else { reviews.append(generated) }
            }
            // A changed merchant/type must be categorized again; never retain a stale category silently.
            if old.merchantNormalized != updated[index].merchantNormalized || old.transactionType != edit.type {
                for i in reviews.indices where reviews[i].targetId == old.transactionId && reviews[i].issueType == .unclearCategory && reviews[i].status == .pending {
                    reviews[i].status = .resolved; reviews[i].resolvedAt = now; reviews[i].userAnswer = "Merchant or type changed"
                }
                updated[index].category = .uncategorized
                updated[index].categoryConfidence = 0
                let categoryReview = ReviewItemRecord(
                    reviewItemId: "review_" + StableHash.make([old.transactionId, "category_edit", edit.merchant, edit.type.rawValue, now.timeIntervalSince1970]),
                    targetType: .transaction, targetId: old.transactionId, issueType: .unclearCategory, severity: .medium,
                    question: "Choose a category for \(edit.merchant)."
                )
                reviews.append(categoryReview)
            }
            refreshStatus(&updated[index], reviews: reviews)
            let changes: [(String, String, String)] = [
                ("transaction_date", old.transactionDate, edit.date),
                ("merchant", old.merchantNormalized, updated[index].merchantNormalized),
                ("amount", String(old.amount), String(edit.amount)),
                ("transaction_type", old.transactionType.rawValue, edit.type.rawValue),
                ("account_label", old.accountLabel, updated[index].accountLabel)
            ]
            let corrections = changes.filter { $0.1 != $0.2 }.map { field, before, after in
                CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction, targetId: old.transactionId,
                    fieldName: field, oldValue: before, newValue: after, applyFuture: false, createdAt: now)
            }
            return CorrectionApplication(transactions: updated, reviewItems: reviews, corrections: corrections)
        }
    }

    private static func confirm(review: ReviewItemRecord, transactions: [TransactionRecord], reviews: [ReviewItemRecord], now: Date) throws -> CorrectionApplication {
        guard let i = transactions.firstIndex(where: { $0.transactionId == review.targetId }),
              let r = reviews.firstIndex(where: { $0.reviewItemId == review.reviewItemId && $0.status == .pending }) else { throw ReviewError.missingTarget }
        var updated = transactions
        var items = reviews
        items[r].status = .resolved; items[r].resolvedAt = now; items[r].userAnswer = "Confirmed"
        refreshStatus(&updated[i], reviews: items)
        updated[i].updatedAt = now
        let correction = CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
            targetId: review.targetId, fieldName: "confirmed_review", oldValue: review.reviewItemId,
            newValue: "confirmed", applyFuture: false, createdAt: now)
        return CorrectionApplication(transactions: updated, reviewItems: items, corrections: [correction])
    }
}

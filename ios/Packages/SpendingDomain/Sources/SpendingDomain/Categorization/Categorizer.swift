import Foundation

public struct CategoryClassificationInput: Sendable {
    public var merchant: String
    public var amount: Double
    public var transactionType: TransactionType
    public var evidenceText: String

    public init(merchant: String, amount: Double, transactionType: TransactionType, evidenceText: String) {
        self.merchant = merchant
        self.amount = amount
        self.transactionType = transactionType
        self.evidenceText = evidenceText
    }
}

public struct CategoryClassificationDecision: Sendable {
    public var category: SpendingCategory
    public var confidence: Double
    public var reason: String

    public init(category: SpendingCategory, confidence: Double, reason: String) {
        self.category = category
        self.confidence = confidence
        self.reason = reason
    }
}

public protocol CategoryClassifier: Sendable {
    func classify(_ input: CategoryClassificationInput) async throws -> CategoryClassificationDecision
}

public struct CategorizationResult: Sendable {
    public var transactions: [TransactionRecord]
    public var reviewItems: [ReviewItemRecord]

    public init(transactions: [TransactionRecord], reviewItems: [ReviewItemRecord]) {
        self.transactions = transactions
        self.reviewItems = reviewItems
    }
}

public enum Categorizer {
    private struct Rule {
        var category: SpendingCategory
        var confidence: Double
        var reason: String
        var patterns: [String]
    }

    private struct Decision {
        var category: SpendingCategory
        var confidence: Double
        var reason: String
        var alternatives: [SpendingCategory]
        var needsReview: Bool
    }

    private static let ambiguousMerchants = [#"amazon"#, #"costco"#, #"walmart"#, #"target"#, #"paypal"#, #"venmo"#, #"apple"#]

    private static let rules: [Rule] = [
        Rule(category: .groceries, confidence: 0.95, reason: "Matched grocery merchant rule.", patterns: [#"trader joe"#, #"whole foods"#, #"safeway"#, #"kroger"#, #"h mart"#, #"aldi"#, #"grocery"#]),
        Rule(category: .dining, confidence: 0.94, reason: "Matched dining merchant rule.", patterns: [#"restaurant"#, #"cafe"#, #"coffee"#, #"starbucks"#, #"mcdonald"#, #"chipotle"#, #"doordash"#, #"ubereats"#]),
        Rule(category: .utilities, confidence: 0.94, reason: "Matched utility merchant rule.", patterns: [#"pge"#, #"pg&e"#, #"pacific gas"#, #"electric"#, #"water"#, #"gas utility"#, #"internet"#, #"comcast"#, #"xfinity"#, #"verizon"#, #"at&t"#]),
        Rule(category: .transportation, confidence: 0.93, reason: "Matched transportation merchant rule.", patterns: [#"uber"#, #"lyft"#, #"shell"#, #"chevron"#, #"exxon"#, #"parking"#, #"transit"#, #"metro"#]),
        Rule(category: .rent, confidence: 0.96, reason: "Matched rent merchant rule.", patterns: [#"rent"#, #"apartment"#, #"property management"#, #"landlord"#]),
        Rule(category: .subscriptions, confidence: 0.94, reason: "Matched subscription merchant rule.", patterns: [#"netflix"#, #"spotify"#, #"hulu"#, #"disney"#, #"youtube"#, #"openai"#, #"icloud"#, #"subscription"#]),
        Rule(category: .shopping, confidence: 0.78, reason: "Matched broad shopping merchant rule.", patterns: [#"amazon"#, #"costco"#, #"walmart"#, #"target"#, #"paypal"#, #"apple"#, #"etsy"#, #"best buy"#]),
        Rule(category: .healthcare, confidence: 0.95, reason: "Matched healthcare merchant rule.", patterns: [#"pharmacy"#, #"cvs"#, #"walgreens"#, #"doctor"#, #"clinic"#, #"hospital"#, #"dental"#]),
        Rule(category: .fees, confidence: 0.95, reason: "Matched fee rule.", patterns: [#"fee"#, #"interest charge"#, #"late payment"#])
    ]

    public static func isSpendingCategory(_ value: String) -> SpendingCategory? {
        SpendingCategory(rawValue: value.lowercased())
    }

    public static func categorize(
        _ transactions: [TransactionRecord],
        corrections: [CorrectionRecord] = [],
        lowConfidenceThreshold: Double = 0.75,
        now: Date = Date()
    ) -> CategorizationResult {
        let memory = merchantCorrectionMap(corrections)
        var reviews: [ReviewItemRecord] = []
        let categorized = transactions.map { transaction -> TransactionRecord in
            var decision = decideCategory(transaction, corrections: memory, threshold: lowConfidenceThreshold)
            decision.needsReview = decision.needsReview || decision.confidence < lowConfidenceThreshold
            let applied = apply(decision, to: transaction, now: now)
            if let review = applied.reviewItem { reviews.append(review) }
            return applied.transaction
        }
        return CategorizationResult(transactions: categorized, reviewItems: reviews)
    }

    public static func categorizeWithFallback(
        _ transactions: [TransactionRecord],
        corrections: [CorrectionRecord] = [],
        classifier: (any CategoryClassifier)? = nil,
        lowConfidenceThreshold: Double = 0.75,
        now: Date = Date()
    ) async -> CategorizationResult {
        let memory = merchantCorrectionMap(corrections)
        var reviews: [ReviewItemRecord] = []
        var categorized: [TransactionRecord] = []

        for transaction in transactions {
            var decision = decideCategory(transaction, corrections: memory, threshold: lowConfidenceThreshold)
            if let classifier, shouldUseClassifier(decision) {
                do {
                    let classified = try await classifier.classify(CategoryClassificationInput(
                        merchant: transaction.merchantNormalized.isEmpty ? transaction.merchantRaw : transaction.merchantNormalized,
                        amount: transaction.amount,
                        transactionType: transaction.transactionType,
                        evidenceText: transaction.evidenceText
                    ))
                    decision = Decision(
                        category: classified.category,
                        confidence: clamp(classified.confidence),
                        reason: "AI category fallback: \(classified.reason)",
                        alternatives: classified.category == .miscellaneous
                            ? [.shopping, .dining, .utilities, .miscellaneous]
                            : [classified.category, .miscellaneous],
                        needsReview: clamp(classified.confidence) < lowConfidenceThreshold
                    )
                } catch {
                    decision.reason += " AI fallback failed; routed to review."
                }
            }
            decision.needsReview = decision.needsReview || decision.confidence < lowConfidenceThreshold
            let applied = apply(decision, to: transaction, now: now)
            if let review = applied.reviewItem { reviews.append(review) }
            categorized.append(applied.transaction)
        }
        return CategorizationResult(transactions: categorized, reviewItems: reviews)
    }

    public static func parseClassifierResponse(_ text: String) throws -> CategoryClassificationDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end else {
            throw ExtractionError.decodeFailed("Category classifier did not return JSON.")
        }
        let slice = String(trimmed[start...end])
        guard let data = slice.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.decodeFailed("Category classifier JSON invalid.")
        }
        let rawCategory = (root["category"] as? String)?.lowercased() ?? ""
        guard let category = isSpendingCategory(rawCategory), category != .uncategorized else {
            throw ExtractionError.decodeFailed("Category classifier returned unsupported category.")
        }
        let confidence: Double
        if let number = root["confidence"] as? Double {
            confidence = clamp(number)
        } else if let number = root["confidence"] as? NSNumber {
            confidence = clamp(number.doubleValue)
        } else {
            confidence = 0
        }
        let reason = (root["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CategoryClassificationDecision(
            category: category,
            confidence: confidence,
            reason: (reason?.isEmpty == false ? String(reason!.prefix(180)) : "Model selected a category from the allowed list.")
        )
    }

    private static func merchantCorrectionMap(_ corrections: [CorrectionRecord]) -> [String: SpendingCategory] {
        var map: [String: SpendingCategory] = [:]
        for correction in corrections.sorted(by: { ($0.createdAt, $0.correctionId) < ($1.createdAt, $1.correctionId) }) {
            if correction.applyFuture,
               correction.targetType == .merchantRule,
               correction.fieldName == "category",
               let category = isSpendingCategory(correction.newValue),
               category != .uncategorized {
                map[ruleKey(target: correction.targetId)] = category
            }
        }
        return map
    }

    public static func ruleTarget(_ merchant: String, origin: TransactionOrigin?) -> String {
        guard let origin else { return merchant }
        return origin.rawValue + "|" + merchant
    }

    public static func scopedMerchantKey(_ merchant: String, origin: TransactionOrigin?) -> String {
        (origin?.rawValue ?? "other") + "|" + merchantKey(merchant)
    }

    public static func ruleKey(target: String) -> String {
        let parts = target.split(separator: "|", maxSplits: 1)
        if parts.count == 2, let origin = TransactionOrigin(rawValue: String(parts[0])) {
            return scopedMerchantKey(String(parts[1]), origin: origin)
        }
        return scopedMerchantKey(target, origin: nil)
    }

    public static func merchantKey(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func decideCategory(
        _ transaction: TransactionRecord,
        corrections: [String: SpendingCategory],
        threshold: Double
    ) -> Decision {
        let merchant = transaction.merchantNormalized.isEmpty ? transaction.merchantRaw : transaction.merchantNormalized
        if let correction = corrections[scopedMerchantKey(merchant, origin: transaction.origin)] {
            return Decision(category: correction, confidence: 0.99, reason: "Matched user correction memory.", alternatives: [], needsReview: false)
        }

        if let typed = categoryForTransactionType(transaction) { return typed }
        if transaction.origin == .card, matches(#"\b(annual fee|membership fee)\b"#, in: transaction.evidenceText) {
            return Decision(category: .fees, confidence: 0.96, reason: "Card statement lists a fee.", alternatives: [], needsReview: false)
        }

        for rule in rules {
            if rule.patterns.contains(where: { matches($0, in: merchant) }) {
                let ambiguous = ambiguousMerchants.contains(where: { matches($0, in: merchant) })
                return Decision(
                    category: rule.category,
                    confidence: rule.confidence,
                    reason: rule.reason,
                    alternatives: ambiguous ? [.groceries, .shopping, .miscellaneous] : [],
                    needsReview: ambiguous || rule.confidence < threshold
                )
            }
        }

        return Decision(
            category: .miscellaneous,
            confidence: 0.45,
            reason: "No deterministic category rule matched.",
            alternatives: [.groceries, .dining, .shopping, .utilities, .miscellaneous],
            needsReview: true
        )
    }

    private static func categoryForTransactionType(_ transaction: TransactionRecord) -> Decision? {
        switch transaction.transactionType {
        case .income:
            return Decision(category: .income, confidence: 0.98, reason: "Transaction type is income.", alternatives: [], needsReview: false)
        case .transfer:
            return Decision(category: .transfer, confidence: 0.94, reason: "Transaction type is transfer/payment.", alternatives: [], needsReview: false)
        case .payment:
            let text = transaction.merchantNormalized + " " + transaction.evidenceText
            if matches(#"transfer|zelle|venmo|cash app"#, in: text) || SpendingMath.isCardPayment(transaction) {
                return Decision(category: .transfer, confidence: 0.94, reason: "Payment appears to be an internal transfer or card payment.", alternatives: [], needsReview: false)
            }
            return nil
        case .fee:
            return Decision(category: .fees, confidence: 0.96, reason: "Transaction type is fee.", alternatives: [], needsReview: false)
        default:
            return nil
        }
    }

    private static func shouldUseClassifier(_ decision: Decision) -> Bool {
        decision.category == .miscellaneous && decision.reason == "No deterministic category rule matched."
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(1, max(0, value)) * 100).rounded() / 100
    }

    private static func apply(_ decision: Decision, to transaction: TransactionRecord, now: Date) -> (transaction: TransactionRecord, reviewItem: ReviewItemRecord?) {
        var updated = transaction
        updated.category = decision.category
        updated.categoryConfidence = decision.confidence
        updated.updatedAt = now
        // Type wins for income/transfer/fee; spending categories never stick on those rows.
        _ = TransactionClassification.normalize(&updated, prefer: .type)
        if decision.needsReview {
            updated.validationStatus = .needsReview
            updated.reviewStatus = .pending
            let review = ReviewItemRecord(
                reviewItemId: "review_" + StableHash.make([transaction.transactionId, "unclear_category", decision.category.rawValue]),
                targetType: .transaction,
                targetId: transaction.transactionId,
                issueType: .unclearCategory,
                severity: decision.confidence < 0.5 ? .medium : .low,
                question: "Is \"\(transaction.merchantNormalized)\" best categorized as \(decision.category.rawValue)?",
                suggestedOptions: (decision.alternatives.isEmpty ? [decision.category, .miscellaneous] : decision.alternatives).map(\.rawValue),
                createdAt: now
            )
            return (updated, review)
        }
        return (updated, nil)
    }
}

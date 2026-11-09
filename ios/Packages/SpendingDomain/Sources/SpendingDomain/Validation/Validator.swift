import Foundation

public struct ValidationContext: Sendable {
    public var now: Date
    public var today: String
    public var duplicateLookbackDays: Int

    public init(now: Date = Date(), today: String? = nil, duplicateLookbackDays: Int = 3) {
        self.now = now
        self.today = today ?? Self.formatter().string(from: now)
        self.duplicateLookbackDays = duplicateLookbackDays
    }

    static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

public struct ValidationResult: Sendable {
    public var transactions: [TransactionRecord]
    public var reviewItems: [ReviewItemRecord]
}

public enum Validator {
    public static func validate(
        _ transactions: [TransactionRecord],
        context: ValidationContext = ValidationContext(),
        existingTransactions: [TransactionRecord] = []
    ) -> ValidationResult {
        var reviews: [ReviewItemRecord] = []
        var updated: [TransactionRecord] = []
        var preceding = existingTransactions.filter { $0.validationStatus != .rejected }
        for transaction in transactions {
            var issues = transactionIssues(transaction, today: context.today)
            if let match = preceding.sorted(by: { $0.transactionId < $1.transactionId }).first(where: {
                $0.transactionId != transaction.transactionId && isPossibleDuplicate($0, transaction, days: context.duplicateLookbackDays)
            }) {
                issues.append(Issue(type: .duplicateRisk, field: "duplicate:\(match.transactionId)", severity: .high,
                    question: "This resembles another charge from \(match.merchantNormalized) on \(match.transactionDate). Are both real?",
                    options: ["valid", "rejected", "needs_review"]))
            }
            var copy = transaction
            if copy.validationStatus != .rejected {
                let hasRequiredIssue = issues.contains { $0.type != .lowConfidence }
                copy.validationStatus = hasRequiredIssue ? .needsReview : .valid
                copy.reviewStatus = hasRequiredIssue ? .pending : (copy.reviewStatus == .resolved ? .resolved : .none)
            }
            copy.updatedAt = context.now
            reviews += issues.map { issue in
                ReviewItemRecord(
                    reviewItemId: "review_" + StableHash.make([copy.transactionId, issue.type.rawValue, issue.field]),
                    targetType: .transaction, targetId: copy.transactionId, issueType: issue.type,
                    severity: issue.severity, question: issue.question, fieldName: issue.field,
                    suggestedOptions: issue.options, createdAt: context.now
                )
            }
            updated.append(copy)
            if copy.validationStatus != .rejected { preceding.append(copy) }
        }
        return ValidationResult(transactions: updated, reviewItems: reviews)
    }

    public static func isValidDate(_ value: String) -> Bool { parseDate(value) != nil }

    private struct Issue {
        var type: ReviewIssueType
        var field: String
        var severity: Severity
        var question: String
        var options: [String] = []
    }

    private static func transactionIssues(_ tx: TransactionRecord, today: String) -> [Issue] {
        var issues: [Issue] = []
        if let date = parseDate(tx.transactionDate) {
            if date > (parseDate(today) ?? .distantPast) {
                issues.append(Issue(type: .anomaly, field: "transaction_date", severity: .medium, question: "This date is in the future. Correct it or confirm it."))
            }
        } else {
            issues.append(Issue(type: .missingField, field: "transaction_date", severity: .high, question: "Add a valid transaction date for \(tx.merchantNormalized)."))
        }
        if tx.merchantNormalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tx.merchantNormalized == "Unknown merchant" {
            issues.append(Issue(type: .missingField, field: "merchant", severity: .high, question: "Identify the merchant."))
        }
        if !tx.amount.isFinite || tx.amount == 0 {
            issues.append(Issue(type: .missingField, field: "amount", severity: .high, question: "Enter a nonzero amount."))
        } else if abs(tx.amount) > 10000 && tx.transactionType == .expense {
            issues.append(Issue(type: .anomaly, field: "amount", severity: .medium, question: "This expense is unusually large. Correct it or confirm it."))
        }
        if tx.transactionType == .unknown {
            issues.append(Issue(type: .missingField, field: "transaction_type", severity: .medium, question: "Choose the transaction type. An unclassified credit is not counted as income."))
        }
        if tx.extractionConfidence < 0.75 {
            issues.append(Issue(type: .lowConfidence, field: "extraction", severity: .medium, question: "Check the extracted fields against the source before confirming."))
        }
        return issues
    }

    private static func isPossibleDuplicate(_ left: TransactionRecord, _ right: TransactionRecord, days: Int) -> Bool {
        func key(_ value: String) -> String {
            String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        guard !key(left.merchantNormalized).isEmpty,
              key(left.merchantNormalized) == key(right.merchantNormalized),
              abs(left.amount - right.amount) < 0.01,
              let a = parseDate(left.transactionDate), let b = parseDate(right.transactionDate) else { return false }
        return abs(a.timeIntervalSince(b)) <= Double(days) * 86_400
    }

    private static func parseDate(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = ValidationContext.formatter()
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
}

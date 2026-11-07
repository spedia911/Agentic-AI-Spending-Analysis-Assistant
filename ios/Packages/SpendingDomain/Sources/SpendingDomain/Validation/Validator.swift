import Foundation

public struct ValidationContext: Sendable {
    public var now: Date
    public var today: String
    public var duplicateLookbackDays: Int

    public init(now: Date = Date(), today: String? = nil, duplicateLookbackDays: Int = 3) {
        self.now = now
        if let today {
            self.today = today
        } else {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            self.today = formatter.string(from: now)
        }
        self.duplicateLookbackDays = duplicateLookbackDays
    }
}

public struct ValidationResult: Sendable {
    public var transactions: [TransactionRecord]
    public var reviewItems: [ReviewItemRecord]

    public init(transactions: [TransactionRecord], reviewItems: [ReviewItemRecord]) {
        self.transactions = transactions
        self.reviewItems = reviewItems
    }
}

public enum Validator {
    public static func validate(_ transactions: [TransactionRecord], context: ValidationContext = ValidationContext()) -> ValidationResult {
        var reviewItems: [ReviewItemRecord] = []
        var updated: [TransactionRecord] = []

        for transaction in transactions {
            let issues = transactionIssues(transaction, today: context.today)
            var copy = transaction
            if !issues.isEmpty {
                copy.validationStatus = .needsReview
                copy.reviewStatus = .pending
                copy.updatedAt = context.now
                for issue in issues {
                    reviewItems.append(makeReviewItem(transaction: copy, issue: issue, now: context.now))
                }
            }
            updated.append(copy)
        }

        let duplicates = duplicateIssues(updated, lookbackDays: context.duplicateLookbackDays)
        for (index, transaction) in updated.enumerated() {
            if let issues = duplicates[transaction.transactionId], !issues.isEmpty {
                updated[index].validationStatus = .needsReview
                updated[index].reviewStatus = .pending
                updated[index].updatedAt = context.now
                for issue in issues {
                    reviewItems.append(makeReviewItem(transaction: updated[index], issue: issue, now: context.now))
                }
            }
        }

        return ValidationResult(transactions: updated, reviewItems: reviewItems)
    }

    private struct Issue {
        var issueType: ReviewIssueType
        var severity: Severity
        var question: String
        var suggestedOptions: [String]
    }

    private static func makeReviewItem(transaction: TransactionRecord, issue: Issue, now: Date) -> ReviewItemRecord {
        ReviewItemRecord(
            reviewItemId: "review_" + StableHash.make([transaction.transactionId, issue.issueType.rawValue, issue.question]),
            targetType: .transaction,
            targetId: transaction.transactionId,
            issueType: issue.issueType,
            severity: issue.severity,
            question: issue.question,
            suggestedOptions: issue.suggestedOptions,
            createdAt: now
        )
    }

    private static func transactionIssues(_ transaction: TransactionRecord, today: String) -> [Issue] {
        var issues: [Issue] = []
        let parsedDate = parseIsoDate(transaction.transactionDate)

        if transaction.transactionDate.isEmpty || parsedDate == nil {
            issues.append(Issue(issueType: .missingField, severity: .high, question: "Please add or correct the transaction date for \"\(transaction.merchantNormalized)\".", suggestedOptions: []))
        } else if let parsedDate, parsedDate > (parseIsoDate(today) ?? Date.distantPast) {
            issues.append(Issue(issueType: .anomaly, severity: .medium, question: "This transaction date is in the future. Should it be corrected?", suggestedOptions: []))
        }

        if transaction.merchantNormalized.isEmpty || transaction.merchantNormalized == "Unknown merchant" {
            issues.append(Issue(issueType: .missingField, severity: .high, question: "Please identify the merchant for this transaction.", suggestedOptions: []))
        }

        if !transaction.amount.isFinite || transaction.amount == 0 {
            issues.append(Issue(issueType: .missingField, severity: .high, question: "Please confirm the amount for \"\(transaction.merchantNormalized)\".", suggestedOptions: []))
        } else if abs(transaction.amount) > 10000 && transaction.transactionType == .expense {
            issues.append(Issue(issueType: .anomaly, severity: .medium, question: "This expense is unusually large. Please confirm the amount and merchant.", suggestedOptions: []))
        }

        if transaction.extractionConfidence < 0.75 {
            issues.append(Issue(issueType: .lowConfidence, severity: .medium, question: "The extraction confidence is low for \"\(transaction.merchantNormalized)\". Please review it.", suggestedOptions: []))
        }
        return issues
    }

    private static func duplicateIssues(_ transactions: [TransactionRecord], lookbackDays: Int) -> [String: [Issue]] {
        var issuesById: [String: [Issue]] = [:]
        for i in 0..<transactions.count {
            for j in (i + 1)..<transactions.count {
                let left = transactions[i]
                let right = transactions[j]
                let sameMerchant = normalizeMerchantKey(left.merchantNormalized) == normalizeMerchantKey(right.merchantNormalized)
                let sameAmount = abs(left.amount - right.amount) < 0.01
                let dayDelta = daysBetween(left.transactionDate, right.transactionDate)
                let closeDate = dayDelta.map { $0 <= Double(lookbackDays) } ?? false
                guard sameMerchant && sameAmount && closeDate else { continue }
                if dayDelta == 0 {
                    let issue = Issue(
                        issueType: .duplicateRisk,
                        severity: .high,
                        question: "This matches another row for \(right.merchantNormalized) on \(right.transactionDate) with the same amount. Mark this row as a duplicate unless it is truly separate spending.",
                        suggestedOptions: ["rejected", "valid", "needs_review"]
                    )
                    issuesById[right.transactionId, default: []].append(issue)
                } else {
                    let issue = Issue(
                        issueType: .duplicateRisk,
                        severity: .medium,
                        question: "This looks like a possible duplicate charge for \(left.merchantNormalized) around \(left.transactionDate). Please confirm whether both rows are real.",
                        suggestedOptions: ["valid", "rejected", "needs_review"]
                    )
                    issuesById[right.transactionId, default: []].append(issue)
                }
            }
        }
        return issuesById
    }

    private static func normalizeMerchantKey(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }

    private static func parseIsoDate(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func daysBetween(_ a: String, _ b: String) -> Double? {
        guard let dateA = parseIsoDate(a), let dateB = parseIsoDate(b) else { return nil }
        return abs(dateA.timeIntervalSince(dateB)) / 86_400
    }
}

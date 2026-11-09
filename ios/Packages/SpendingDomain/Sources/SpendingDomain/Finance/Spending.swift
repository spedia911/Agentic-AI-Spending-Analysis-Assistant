import Foundation

public enum SpendingMath {
    private static let explicitSpending: Set<SpendingCategory> = [
        .groceries, .dining, .utilities, .transportation, .rent,
        .subscriptions, .shopping, .healthcare, .fees
    ]

    public static func isCardPayment(_ transaction: TransactionRecord) -> Bool {
        let text = [
            transaction.merchantNormalized,
            transaction.merchantRaw,
            transaction.evidenceText,
            transaction.category.rawValue
        ].joined(separator: " ")
        guard transaction.transactionType == .payment else { return false }
        let pattern = #"(?i)credit card|applecard|apple card|bilt payment|card payment|payment to card|card autopay|autopay.*card|chase card|amex|american express|capital one|citi card|discover card|visa payment|mastercard payment"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    public static func spendingAmount(_ transaction: TransactionRecord) -> Double {
        if isCardPayment(transaction) { return 0 }
        if isIncome(transaction) || transaction.transactionType == .refund || transaction.transactionType == .unknown {
            return 0
        }
        if transaction.category == .transfer { return 0 }
        if explicitSpending.contains(transaction.category) { return abs(transaction.amount) }
        if transaction.transactionType != .expense && transaction.transactionType != .fee { return 0 }
        return abs(transaction.amount)
    }

    /// Income totals follow transaction type after classification sync (`type` and `category` both income).
    public static func incomeAmount(_ transaction: TransactionRecord) -> Double {
        isIncome(transaction) ? abs(transaction.amount) : 0
    }

    public static func isIncome(_ transaction: TransactionRecord) -> Bool {
        // Prefer type; category alone is treated as income only while legacy rows are still unsynced.
        transaction.transactionType == .income || transaction.category == .income
    }

    public static func transferAmount(_ transaction: TransactionRecord) -> Double {
        if isCardPayment(transaction) { return abs(transaction.amount) }
        if isIncome(transaction) { return 0 }
        if explicitSpending.contains(transaction.category) { return 0 }
        if transaction.transactionType == .transfer || transaction.category == .transfer {
            return abs(transaction.amount)
        }
        return 0
    }
}

import Foundation

/// Keeps `transactionType` (cash-flow role) and `category` (purpose) from contradicting each other.
///
/// - **Type** answers: is this spending, income, a transfer, a fee, a refund, or a payment?
/// - **Category** answers: what kind of spending was it? (groceries, dining, …)
/// - Non-spending types lock a matching category (`income` → `income`, `transfer` → `transfer`, `fee` → `fees`).
/// - Spending categories are not valid on income/transfer rows.
public enum TransactionClassification {
    public enum Prefer: Sendable {
        /// Trust the type and adjust category (import, type picker).
        case type
        /// Trust the category and adjust type (category picker / merchant remember).
        case category
    }

    /// Purpose buckets for money that left as spending (or fee).
    public static let spendingPurposes: [SpendingCategory] = [
        .groceries, .dining, .utilities, .transportation, .rent,
        .subscriptions, .shopping, .healthcare, .fees, .miscellaneous
    ]

    public static func isSpendingPurpose(_ category: SpendingCategory) -> Bool {
        spendingPurposes.contains(category) || category == .uncategorized
    }

    /// Categories the user may pick for a given type.
    public static func allowedCategories(for type: TransactionType) -> [SpendingCategory] {
        switch type {
        case .income:
            return [.income]
        case .transfer:
            return [.transfer]
        case .fee:
            return [.fees]
        case .payment:
            // Card/bank payments may be internal transfers or bill payments that still count as spending.
            return [.transfer] + spendingPurposes + [.uncategorized]
        case .refund:
            return spendingPurposes + [.uncategorized]
        case .expense, .unknown:
            return spendingPurposes + [.uncategorized]
        }
    }

    public static func canonicalCategory(for type: TransactionType) -> SpendingCategory? {
        switch type {
        case .income: return .income
        case .transfer: return .transfer
        case .fee: return .fees
        case .expense, .payment, .refund, .unknown: return nil
        }
    }

    public static func impliedType(for category: SpendingCategory) -> TransactionType? {
        switch category {
        case .income: return .income
        case .transfer: return .transfer
        case .fees: return nil // fees may stay expense (service fee) or type fee
        default: return nil
        }
    }

    public static func isConsistent(type: TransactionType, category: SpendingCategory) -> Bool {
        allowedCategories(for: type).contains(category)
    }

    /// Returns a non-contradictory (type, category) pair.
    public static func normalize(
        type: TransactionType,
        category: SpendingCategory,
        prefer: Prefer = .type
    ) -> (type: TransactionType, category: SpendingCategory) {
        switch prefer {
        case .type:
            if let locked = canonicalCategory(for: type) {
                return (type, locked)
            }
            if type == .payment, category == .income {
                return (.payment, .uncategorized)
            }
            if allowedCategories(for: type).contains(category) {
                return (type, category)
            }
            // Spending type with income/transfer category → drop to uncategorized for review.
            if category == .income || category == .transfer {
                return (type, .uncategorized)
            }
            return (type, .uncategorized)

        case .category:
            if let implied = impliedType(for: category) {
                return (implied, category == .fees ? .fees : canonicalCategory(for: implied) ?? category)
            }
            if category == .fees {
                // Choosing Fees as purpose: keep fee type if already fee, otherwise expense.
                let nextType: TransactionType = (type == .fee) ? .fee : .expense
                return (nextType, .fees)
            }
            if isSpendingPurpose(category) {
                let nextType: TransactionType
                switch type {
                case .income, .transfer:
                    nextType = .expense
                case .fee:
                    nextType = category == .fees ? .fee : .expense
                default:
                    nextType = type == .unknown ? .expense : type
                }
                if allowedCategories(for: nextType).contains(category) {
                    return (nextType, category)
                }
                return (.expense, category)
            }
            return normalize(type: type, category: .uncategorized, prefer: .type)
        }
    }

    public static func normalize(_ transaction: inout TransactionRecord, prefer: Prefer = .type) -> Bool {
        let beforeType = transaction.transactionType
        let beforeCategory = transaction.category
        let normalized = normalize(type: beforeType, category: beforeCategory, prefer: prefer)
        transaction.transactionType = normalized.type
        transaction.category = normalized.category
        return beforeType != normalized.type || beforeCategory != normalized.category
    }
}

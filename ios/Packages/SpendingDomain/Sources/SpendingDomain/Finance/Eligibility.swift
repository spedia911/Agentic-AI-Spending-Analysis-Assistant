import Foundation

public struct AccountRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { accountId }
    public var accountId: String
    public var label: String
    public var currencyCode: String
    public var preferredSpendingCurrency: String?
    public var spendingCurrency: String { preferredSpendingCurrency ?? currencyCode }
    public init(accountId: String = UUID().uuidString, label: String, currencyCode: String, preferredSpendingCurrency: String? = nil) {
        self.accountId = accountId; self.label = label; self.currencyCode = currencyCode
        self.preferredSpendingCurrency = preferredSpendingCurrency
    }
}

public struct RecordEligibility: Codable, Sendable, Equatable {
    public var local: Bool
    public var desktop: Bool
    public var reasons: [String]
}

public enum Eligibility {
    public static func validCurrency(_ code: String?) -> Bool {
        guard let code else { return false }
        return Locale.commonISOCurrencyCodes.contains(code)
    }
    public static func mapped(_ account: String?, _ currency: String?) -> Bool {
        account.flatMap(UUID.init(uuidString:)) != nil && validCurrency(currency)
    }
    public static func transaction(_ row: TransactionRecord, reviews: [ReviewItemRecord] = []) -> RecordEligibility {
        var reasons: [String] = []
        if !validCurrency(row.billedCurrencyCode) { reasons.append("transaction_currency_unassigned") }
        if row.hasCurrencyConflict || (row.confirmedBilledCurrency != nil && !validCurrency(row.confirmedBilledCurrency)) { reasons.append("billed_currency_needs_review") }
        if row.validationStatus == .rejected { reasons.append("rejected") }
        if !row.amount.isFinite || row.amount == 0 { reasons.append("invalid_amount") }
        if !Validator.isValidDate(row.transactionDate) || row.observedMonth != String(row.transactionDate.prefix(7)) { reasons.append("invalid_date") }
        let local = reasons.isEmpty
        if !mapped(row.accountId, row.currencyCode) {
            reasons.append("account_or_currency_unmapped")
        } else if row.billedCurrencyCode != row.currencyCode {
            reasons.append("billed_currency_differs_from_account")
        }
        if row.validationStatus == .needsReview || row.reviewStatus == .pending || reviews.contains(where: {
            $0.targetType == .transaction && $0.targetId == row.id && $0.status == .pending && !$0.isAdvisory
        }) { reasons.append("mandatory_review_pending") }
        return RecordEligibility(local: local, desktop: reasons.isEmpty, reasons: reasons)
    }
    public static func asset(_ row: AssetSnapshotRecord, reviews: [ReviewItemRecord] = [], peers: [AssetSnapshotRecord] = []) -> RecordEligibility {
        var reasons: [String] = []
        if !mapped(row.accountId, row.currencyCode) { reasons.append("account_or_currency_unmapped") }
        if row.hasCurrencyConflict { reasons.append("balance_currency_needs_review") }
        if !row.balance.isFinite { reasons.append("invalid_amount") }
        if !Validator.isValidDate(row.observedDate) || row.observedMonth != String(row.observedDate.prefix(7)) { reasons.append("invalid_date") }
        if !row.balanceType.tracksAsAsset { reasons.append("not_an_asset_balance") }
        if reviews.contains(where: { $0.targetType == .assetSnapshot && $0.targetId == row.id && $0.status == .pending }) { reasons.append("balance_review_pending") }
        if peers.contains(where: { $0.id != row.id && $0.accountId == row.accountId && $0.currencyCode == row.currencyCode && $0.balanceType == row.balanceType && $0.observedDate == row.observedDate && $0.balance != row.balance }) { reasons.append("conflicting_balance") }
        return RecordEligibility(local: reasons.isEmpty, desktop: reasons.isEmpty, reasons: reasons)
    }
}

public struct SpendingClassification: Codable, Sendable, Equatable {
    public var grossSpending: Double
    public var refunds: Double
    public var netSpending: Double { grossSpending - refunds }
    public var income: Double
    public var internalTransfer: Double
    public var cardSettlement: Double
    public init(_ row: TransactionRecord) {
        grossSpending = SpendingMath.spendingAmount(row)
        refunds = row.transactionType == .refund ? abs(row.amount) : 0
        income = SpendingMath.incomeAmount(row)
        cardSettlement = SpendingMath.isCardPayment(row) ? abs(row.amount) : 0
        internalTransfer = cardSettlement == 0 ? SpendingMath.transferAmount(row) : 0
    }
}

import Foundation

/// Shared synthetic records for spending/export contract tests and desktop consumers.
public enum AuditFixtures {
    public static let usd = AccountRecord(accountId: "00000000-0000-0000-0000-000000000001", label: "Synthetic USD", currencyCode: "USD")
    public static let krw = AccountRecord(accountId: "00000000-0000-0000-0000-000000000002", label: "Synthetic KRW", currencyCode: "KRW")

    public static func transaction(
        id: String = "t1",
        account: AccountRecord = usd,
        amount: Double = -100,
        type: TransactionType = .expense,
        category: SpendingCategory = .groceries,
        merchant: String = "Synthetic Merchant",
        date: String = "2026-01-15",
        review: ReviewStatus = .resolved,
        validation: ValidationStatus = .valid
    ) -> TransactionRecord {
        TransactionRecord(
            transactionId: id, sourceDocumentId: "fixture_source", observedMonth: String(date.prefix(7)),
            transactionDate: date, merchantRaw: merchant, merchantNormalized: merchant, amount: amount,
            transactionType: type, accountLabel: account.label, accountId: account.id, currencyCode: account.currencyCode,
            category: category, extractionConfidence: 1, validationStatus: validation, reviewStatus: review,
            evidenceText: "\(merchant) \(amount)"
        )
    }

    public static func balance(
        id: String = "a1",
        account: AccountRecord = usd,
        date: String = "2026-01-31",
        value: Double = 500,
        type: BalanceType = .checking
    ) -> AssetSnapshotRecord {
        AssetSnapshotRecord(
            assetSnapshotId: id, sourceDocumentId: "fixture_source", observedMonth: String(date.prefix(7)),
            observedDate: date, accountLabel: account.label, accountId: account.id, currencyCode: account.currencyCode,
            balance: value, balanceType: type, confidence: 1, evidenceText: "Synthetic balance"
        )
    }

    /// Correction, rejection, pending, refund, rent, card settlement, and multi-currency rows for contract tests.
    public static func catalog() -> BackupPayload {
        BackupPayload(
            sourceDocuments: [
                SourceDocumentRecord(sourceDocumentId: "fixture_source", sourceType: .manual, fileName: "fixture.json", mimeType: "application/json")
            ],
            transactions: [
                transaction(id: "rent", amount: -1200, type: .payment, category: .rent, merchant: "Landlord"),
                transaction(id: "refund", amount: 40, type: .refund, category: .shopping, merchant: "Store refund"),
                transaction(id: "card_pay", amount: -500, type: .payment, category: .transfer, merchant: "Credit card payment"),
                transaction(id: "pending", amount: -12, merchant: "Cafe", review: .pending),
                transaction(id: "rejected", amount: -9, merchant: "Rejected", validation: .rejected),
                transaction(id: "kept", amount: -15, merchant: "Kept after sibling delete"),
                transaction(id: "krw_rent", account: krw, amount: -500_000, type: .payment, category: .rent, merchant: "KRW rent")
            ],
            assetSnapshots: [
                balance(id: "usd_jan", date: "2026-01-31", value: 500),
                balance(id: "usd_mar", date: "2026-03-31", value: 0)
            ],
            reviewItems: [
                ReviewItemRecord(reviewItemId: "rev_pending", targetType: .transaction, targetId: "pending",
                                 issueType: .unclearCategory, severity: .medium, question: "Confirm category")
            ],
            corrections: [
                CorrectionRecord(correctionId: "corr1", targetType: .transaction, targetId: "pending",
                                 fieldName: "category", oldValue: "miscellaneous", newValue: "dining", applyFuture: true)
            ],
            monthlySummaries: [], quarterlySummaries: [], cashFlowSummaries: [], assetTrends: [], anomalies: []
        )
    }
}

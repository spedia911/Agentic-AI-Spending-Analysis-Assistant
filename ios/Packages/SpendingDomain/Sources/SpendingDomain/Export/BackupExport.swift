import Foundation

public struct BackupPayload: Codable, Sendable {
    public var exportedAt: Date
    public var sourceDocuments: [SourceDocumentRecord]
    public var transactions: [TransactionRecord]
    public var assetSnapshots: [AssetSnapshotRecord]
    public var reviewItems: [ReviewItemRecord]
    public var corrections: [CorrectionRecord]
    public var monthlySummaries: [MonthlySummaryRecord]
    public var quarterlySummaries: [QuarterlySummaryRecord]
    public var cashFlowSummaries: [CashFlowSummaryRecord]
    public var assetTrends: [AssetTrendRecord]
    public var anomalies: [AnomalyRecord]

    public init(
        exportedAt: Date = Date(),
        sourceDocuments: [SourceDocumentRecord],
        transactions: [TransactionRecord],
        assetSnapshots: [AssetSnapshotRecord],
        reviewItems: [ReviewItemRecord],
        corrections: [CorrectionRecord],
        monthlySummaries: [MonthlySummaryRecord],
        quarterlySummaries: [QuarterlySummaryRecord],
        cashFlowSummaries: [CashFlowSummaryRecord],
        assetTrends: [AssetTrendRecord],
        anomalies: [AnomalyRecord]
    ) {
        self.exportedAt = exportedAt
        self.sourceDocuments = sourceDocuments
        self.transactions = transactions
        self.assetSnapshots = assetSnapshots
        self.reviewItems = reviewItems
        self.corrections = corrections
        self.monthlySummaries = monthlySummaries
        self.quarterlySummaries = quarterlySummaries
        self.cashFlowSummaries = cashFlowSummaries
        self.assetTrends = assetTrends
        self.anomalies = anomalies
    }
}

public enum BackupExporter {
    public static func jsonData(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public static func transactionsCSV(_ transactions: [TransactionRecord]) -> String {
        var lines = ["transaction_id,observed_month,transaction_date,merchant,amount,type,category,account_label"]
        for tx in transactions {
            let cols = [
                tx.transactionId,
                tx.observedMonth,
                tx.transactionDate,
                escape(tx.merchantNormalized),
                String(tx.amount),
                tx.transactionType.rawValue,
                tx.category.rawValue,
                escape(tx.accountLabel)
            ]
            lines.append(cols.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

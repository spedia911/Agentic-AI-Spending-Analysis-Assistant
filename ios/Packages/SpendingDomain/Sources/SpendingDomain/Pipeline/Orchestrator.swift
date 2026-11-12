import Foundation

public struct PipelineInput: Sendable {
    public var sourceDocumentId: String
    public var fileName: String
    public var extraction: ScreenshotExtractionResult
    public var existingTransactions: [TransactionRecord]
    public var corrections: [CorrectionRecord]
    public var existingAssets: [AssetSnapshotRecord]
    public var observedMonthHint: String?
    public var origin: TransactionOrigin?
    public var now: Date
    public var account: AccountRecord?
    public var defaultCurrency: String?

    public init(
        sourceDocumentId: String,
        fileName: String,
        extraction: ScreenshotExtractionResult,
        existingTransactions: [TransactionRecord] = [],
        corrections: [CorrectionRecord] = [],
        existingAssets: [AssetSnapshotRecord] = [],
        observedMonthHint: String? = nil,
        origin: TransactionOrigin? = nil,
        now: Date = Date(),
        account: AccountRecord? = nil,
        defaultCurrency: String? = nil
    ) {
        self.sourceDocumentId = sourceDocumentId
        self.fileName = fileName
        self.extraction = extraction
        self.existingTransactions = existingTransactions
        self.existingAssets = existingAssets
        self.corrections = corrections
        self.observedMonthHint = observedMonthHint
        self.origin = origin
        self.now = now
        self.account = account
        self.defaultCurrency = defaultCurrency
    }
}

public struct PipelineOutput: Sendable {
    public var transactions: [TransactionRecord]
    public var assetSnapshots: [AssetSnapshotRecord]
    public var reviewItems: [ReviewItemRecord]
    public var warnings: [String]

    public init(transactions: [TransactionRecord], assetSnapshots: [AssetSnapshotRecord], reviewItems: [ReviewItemRecord], warnings: [String]) {
        self.transactions = transactions
        self.assetSnapshots = assetSnapshots
        self.reviewItems = reviewItems
        self.warnings = warnings
    }
}

public enum ProcessingPipeline {
    /// Normalize → validate → categorize for one extraction result.
    public static func process(_ input: PipelineInput, classifier: (any CategoryClassifier)? = nil) async -> PipelineOutput {
        var extraction = input.extraction
        extraction.sourceDocumentId = input.sourceDocumentId

        let normalized = Normalizer.normalize(
            extraction: extraction,
            context: NormalizeContext(
                sourceDocumentId: input.sourceDocumentId,
                observedMonthHint: input.observedMonthHint,
                now: input.now
            )
        )

        let existingIds = Set(input.existingTransactions.map(\.transactionId))
        let existingAssetIds = Set(input.existingAssets.map(\.assetSnapshotId))
        let validated = Validator.validate(
            normalized.transactions.filter { !existingIds.contains($0.transactionId) }.map {
                var row = $0
                row.origin = input.origin
                row.assignAccount(input.account, defaultCurrency: input.defaultCurrency)
                return row
            },
            context: ValidationContext(now: input.now),
            existingTransactions: input.existingTransactions
        )

        let categorized = await Categorizer.categorizeWithFallback(
            validated.transactions,
            corrections: input.corrections,
            classifier: classifier,
            now: input.now
        )

        // Idempotent: drop incoming rows that already exist with same transactionId
        let newTransactions = categorized.transactions.filter { !existingIds.contains($0.transactionId) }

        let newAssets = normalized.assetSnapshots.filter { !existingAssetIds.contains($0.assetSnapshotId) }
        let assetIds = Set(newAssets.map(\.assetSnapshotId))
        let reviews = dedupeReviews(normalized.reviewItems.filter { assetIds.contains($0.targetId) } + validated.reviewItems + categorized.reviewItems)

        return PipelineOutput(
            transactions: newTransactions,
            assetSnapshots: newAssets,
            reviewItems: reviews,
            warnings: extraction.warnings
        )
    }

    public static func rebuildSummaries(
        transactions: [TransactionRecord],
        assets: [AssetSnapshotRecord],
        now: Date = Date()
    ) -> (summaries: SummaryResult, anomalies: [AnomalyRecord]) {
        let summaries = SummaryGenerator.generate(transactions: transactions, assetSnapshots: assets)
        let anomalies = Set(transactions.compactMap(\.billedCurrencyCode)).sorted().flatMap { code in AnomalyDetector.generate(
            transactions: transactions.filter { $0.billedCurrencyCode == code && Eligibility.transaction($0).local },
            monthlySummaries: summaries.monthlySummaries.filter { $0.currencyCode == code },
            assetTrends: summaries.assetTrends.filter { $0.currencyCode == code },
            context: AnomalyGenerationContext(now: now)
        )
        .map { row in var copy = row; copy.anomalyId += "_" + code; return copy }
        }
        return (summaries, anomalies)
    }

    private static func dedupeReviews(_ items: [ReviewItemRecord]) -> [ReviewItemRecord] {
        var seen = Set<String>()
        var result: [ReviewItemRecord] = []
        for item in items {
            if seen.insert(item.reviewItemId).inserted {
                result.append(item)
            }
        }
        return result
    }
}

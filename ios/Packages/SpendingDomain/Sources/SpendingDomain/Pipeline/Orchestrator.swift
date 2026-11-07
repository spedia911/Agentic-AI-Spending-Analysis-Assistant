import Foundation

public struct PipelineInput: Sendable {
    public var sourceDocumentId: String
    public var fileName: String
    public var extraction: ScreenshotExtractionResult
    public var existingTransactions: [TransactionRecord]
    public var corrections: [CorrectionRecord]
    public var observedMonthHint: String?
    public var now: Date

    public init(
        sourceDocumentId: String,
        fileName: String,
        extraction: ScreenshotExtractionResult,
        existingTransactions: [TransactionRecord] = [],
        corrections: [CorrectionRecord] = [],
        observedMonthHint: String? = nil,
        now: Date = Date()
    ) {
        self.sourceDocumentId = sourceDocumentId
        self.fileName = fileName
        self.extraction = extraction
        self.existingTransactions = existingTransactions
        self.corrections = corrections
        self.observedMonthHint = observedMonthHint
        self.now = now
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
        if extraction.sourceDocumentId.isEmpty {
            extraction.sourceDocumentId = input.sourceDocumentId
        }

        let normalized = Normalizer.normalize(
            extraction: extraction,
            context: NormalizeContext(
                sourceDocumentId: input.sourceDocumentId,
                observedMonthHint: input.observedMonthHint,
                now: input.now
            )
        )

        let validated = Validator.validate(
            normalized.transactions,
            context: ValidationContext(now: input.now)
        )

        let categorized = await Categorizer.categorizeWithFallback(
            validated.transactions,
            corrections: input.corrections,
            classifier: classifier,
            now: input.now
        )

        // Idempotent: drop incoming rows that already exist with same transactionId
        let existingIds = Set(input.existingTransactions.map(\.transactionId))
        let newTransactions = categorized.transactions.filter { !existingIds.contains($0.transactionId) }

        let reviews = dedupeReviews(normalized.reviewItems + validated.reviewItems + categorized.reviewItems)

        return PipelineOutput(
            transactions: newTransactions,
            assetSnapshots: normalized.assetSnapshots,
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
        let anomalies = AnomalyDetector.generate(
            transactions: transactions,
            monthlySummaries: summaries.monthlySummaries,
            assetTrends: summaries.assetTrends,
            context: AnomalyGenerationContext(now: now)
        )
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

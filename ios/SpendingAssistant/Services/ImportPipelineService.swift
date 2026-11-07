import Foundation
import SwiftData
import SpendingDomain

@MainActor
final class ImportPipelineService {
    private let store: LocalStore
    private let enableFoundationModels: Bool

    init(store: LocalStore, enableFoundationModels: Bool = true) {
        self.store = store
        self.enableFoundationModels = enableFoundationModels
    }

    func importImage(
        data: Data,
        fileName: String,
        mimeType: String,
        sourceType: SourceType
    ) async throws -> SourceDocumentRecord {
        let sourceId = "src_" + StableHash.make([UUID().uuidString, fileName])
        let relative = try SourceFileStore.saveImage(data: data, sourceDocumentId: sourceId, fileName: fileName)
        var source = SourceDocumentRecord(
            sourceDocumentId: sourceId,
            sourceType: sourceType,
            fileName: fileName,
            mimeType: mimeType,
            localRelativePath: relative,
            status: .pending
        )
        store.upsert(source: source)
        try store.save()

        do {
            let lines = try await VisionOCRService.recognizeLines(from: data)
            var extraction = HeuristicScreenshotParser.parse(
                sourceDocumentId: sourceId,
                fileName: fileName,
                lines: lines
            )
            extraction.rawText = lines.map(\.text).joined(separator: "\n")

            if extraction.transactions.isEmpty && extraction.assetSnapshots.isEmpty {
                let structurer = OnDeviceAIFactory.makeStructurer(enabled: enableFoundationModels)
                if let structured = try await structurer.structure(
                    ocrText: extraction.rawText,
                    sourceDocumentId: sourceId,
                    fileName: fileName
                ) {
                    extraction = structured
                    extraction.sourceDocumentId = sourceId
                }
            }

            try await persist(extraction: extraction, source: &source)
            return source
        } catch {
            source.status = .error
            source.errorSummary = PrivacyRedactor.safeErrorDetail(error)
            store.upsert(source: source)
            try store.save()
            throw error
        }
    }

    func importAIJSON(text: String, fileName: String = "ai-import.json") async throws -> SourceDocumentRecord {
        let parsed = try ExtractionJSONParser.parse(text)
        let sourceId = parsed.sourceDocumentId.isEmpty
            ? "src_" + StableHash.make([UUID().uuidString, "ai"])
            : parsed.sourceDocumentId
        var source = SourceDocumentRecord(
            sourceDocumentId: sourceId,
            sourceType: .aiImport,
            fileName: fileName,
            mimeType: "application/json",
            status: .pending,
            rawText: text
        )
        store.upsert(source: source)
        var extraction = parsed
        extraction.sourceDocumentId = sourceId
        try await persist(extraction: extraction, source: &source)
        return source
    }

    func seedDemo() throws {
        let seed = DemoSeed.make()
        for source in seed.sources { store.upsert(source: source) }
        for tx in seed.transactions { store.upsert(transaction: tx) }
        for asset in seed.assets { store.upsert(asset: asset) }
        for review in seed.reviews { store.upsert(review: review) }
        try store.save()
        try store.rebuildDerived()
    }

    func applyCategory(review: ReviewItemRecord, category: SpendingCategory, remember: Bool) throws {
        let applied = CorrectionApplier.applyCategoryCorrection(
            transactionId: review.targetId,
            newCategory: category,
            remember: remember,
            transactions: try store.allTransactions(),
            reviewItems: try store.allReviews()
        )
        for tx in applied.transactions { store.upsert(transaction: tx) }
        for item in applied.reviewItems { store.upsert(review: item) }
        for correction in applied.corrections { store.insert(correction: correction) }
        try store.save()
        try store.rebuildDerived()
    }

    private func persist(extraction: ScreenshotExtractionResult, source: inout SourceDocumentRecord) async throws {
        let corrections = try store.allCorrections()
        let existing = try store.allTransactions()
        let classifier = OnDeviceAIFactory.makeClassifier(enabled: enableFoundationModels)
        let output = await ProcessingPipeline.process(
            PipelineInput(
                sourceDocumentId: source.sourceDocumentId,
                fileName: source.fileName,
                extraction: extraction,
                existingTransactions: existing,
                corrections: corrections
            ),
            classifier: classifier
        )

        for tx in output.transactions { store.upsert(transaction: tx) }
        for asset in output.assetSnapshots { store.upsert(asset: asset) }
        for review in output.reviewItems { store.upsert(review: review) }

        source.status = .processed
        source.processedAt = Date()
        source.rawText = extraction.rawText
        source.errorSummary = output.warnings.isEmpty ? nil : PrivacyRedactor.maskSensitiveText(output.warnings.joined(separator: "; "))
        store.upsert(source: source)
        try store.save()
        try store.rebuildDerived()
    }
}

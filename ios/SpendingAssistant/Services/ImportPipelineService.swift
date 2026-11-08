import Foundation
import SwiftData
import SpendingDomain

struct ImportOutcome: Identifiable {
    enum Status { case imported, alreadyImported, failed }
    let id = UUID()
    var fileName: String
    var status: Status
    var source: SourceDocumentRecord?
    var error: String?

    static func failure(_ name: String, _ error: Error, source: SourceDocumentRecord? = nil) -> Self {
        Self(fileName: name, status: .failed, source: source, error: PrivacyRedactor.safeErrorDetail(error))
    }
}

enum ImportFailure: Error, LocalizedError {
    case missingImage, replacementHasRows, unavailableSource, emptyImage
    var errorDescription: String? {
        switch self {
        case .missingImage: return "The source image is unavailable or was removed by retention. Reimport the screenshot or attach AI JSON."
        case .replacementHasRows: return "This source already has extracted rows. Correct its transactions in Review."
        case .unavailableSource: return "The source is unavailable."
        case .emptyImage: return "No image data was received."
        }
    }
}

/// One shared service serializes imports across await points, including concurrent entry points.
@MainActor
final class ImportPipelineService {
    let store: LocalStore
    let files: SourceFileStore
    private let recognize: (Data) async throws -> [OCRLine]
    private let enableFoundationModels: () -> Bool
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(store: LocalStore, files: SourceFileStore = SourceFileStore(),
         enableFoundationModels: @escaping () -> Bool = { UserDefaults.standard.object(forKey: "enableFoundationModels") as? Bool ?? true },
         recognize: @escaping (Data) async throws -> [OCRLine] = VisionOCRService.recognizeLines) {
        self.store = store; self.files = files
        self.enableFoundationModels = enableFoundationModels; self.recognize = recognize
    }

    private func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }

    func importImage(data: Data, fileName: String, mimeType: String, sourceType: SourceType) async -> ImportOutcome {
        await acquire(); defer { release() }
        return await importImageUnlocked(data: data, fileName: fileName, mimeType: mimeType, sourceType: sourceType)
    }

    private func importImageUnlocked(data: Data, fileName: String, mimeType: String, sourceType: SourceType,
                                     retrySource: SourceDocumentRecord? = nil) async -> ImportOutcome {
        var source: SourceDocumentRecord?
        var newPath: String?
        do {
            guard !data.isEmpty else { throw ImportFailure.emptyImage }
            try backfillFingerprints()
            let fingerprint = ContentFingerprint.image(data)
            let existing = try retrySource ?? store.source(fingerprint: fingerprint)
            if let existing, existing.status == .processed {
                return ImportOutcome(fileName: fileName, status: .alreadyImported, source: existing)
            }
            var record = existing ?? SourceDocumentRecord(sourceDocumentId: "src_" + UUID().uuidString,
                sourceType: sourceType, fileName: fileName, mimeType: mimeType, contentFingerprint: fingerprint)
            source = record
            // Keep the source durable before invoking OCR; restore an expired image on reimport.
            if record.localRelativePath == nil || (try? files.read(record.localRelativePath!)) == nil {
                record.localRelativePath = try files.save(data: data, sourceId: record.sourceDocumentId, fileName: fileName)
                newPath = record.localRelativePath
            }
            record.contentFingerprint = fingerprint
            record.status = .pending; record.errorSummary = nil
            try store.commit { try store.upsert(source: record) }
            newPath = nil
            source = record
            let lines = try await recognize(data)
            record.rawText = lines.map(\.text).joined(separator: "\n")
            source = record
            var extraction = HeuristicScreenshotParser.parse(sourceDocumentId: record.sourceDocumentId, fileName: record.fileName, lines: lines)
            extraction.rawText = record.rawText ?? ""
            if extraction.transactions.isEmpty && extraction.assetSnapshots.isEmpty {
                // Optional enhancement failures must not discard the OCR evidence or fallback path.
                if let structured = try? await OnDeviceAIFactory.makeStructurer(enabled: enableFoundationModels()).structure(
                    ocrText: extraction.rawText, sourceDocumentId: record.sourceDocumentId, fileName: record.fileName) {
                    extraction = structured
                }
            }
            try await persist(extraction: extraction, source: &record)
            return ImportOutcome(fileName: fileName, status: .imported, source: record)
        } catch {
            if let newPath { try? files.remove(newPath) }
            return recordFailure(error, name: fileName, source: source)
        }
    }

    func importAIJSON(text: String, fileName: String = "ai-import.json", attachingTo sourceId: String? = nil,
                      sourceType: SourceType = .aiImport) async -> ImportOutcome {
        await acquire(); defer { release() }
        return await importJSONUnlocked(text: text, fileName: fileName, sourceId: sourceId, sourceType: sourceType)
    }

    private func importJSONUnlocked(text: String, fileName: String, sourceId: String?, sourceType: SourceType) async -> ImportOutcome {
        var source: SourceDocumentRecord?
        do {
            try backfillFingerprints()
            if let sourceId {
                guard let existing = try store.source(id: sourceId) else { throw ImportFailure.unavailableSource }
                guard try !store.hasRows(sourceId: sourceId), existing.status != .processed else { throw ImportFailure.replacementHasRows }
                source = existing
            }
            let parsed: ScreenshotExtractionResult
            do { parsed = try ExtractionJSONParser.parse(text) }
            catch {
                if source == nil {
                    source = try store.source(fingerprint: ContentFingerprint.invalidJSON(text))
                        ?? SourceDocumentRecord(sourceDocumentId: "src_" + UUID().uuidString, sourceType: sourceType,
                            fileName: fileName, mimeType: "application/json", contentFingerprint: ContentFingerprint.invalidJSON(text))
                }
                source?.importedJSON = text
                throw error
            }
            let fingerprint = try ContentFingerprint.json(parsed)
            if let existing = try store.source(fingerprint: fingerprint), existing.status == .processed {
                // Do not silently attach an already imported document to a different failed source.
                if sourceId != nil && sourceId != existing.sourceDocumentId { throw ImportFailure.replacementHasRows }
                return ImportOutcome(fileName: fileName, status: .alreadyImported, source: existing)
            }
            if source == nil {
                source = try store.source(fingerprint: fingerprint) ?? SourceDocumentRecord(
                    sourceDocumentId: "src_" + UUID().uuidString, sourceType: sourceType,
                    fileName: fileName, mimeType: "application/json", contentFingerprint: fingerprint)
            }
            var record = source!
            record.importedJSON = text
            if record.rawText == nil { record.rawText = parsed.rawText }
            // For an attached repair, preserve the screenshot fingerprint and OCR evidence.
            if record.localRelativePath == nil { record.contentFingerprint = fingerprint }
            source = record
            try await persist(extraction: parsed, source: &record)
            return ImportOutcome(fileName: fileName, status: .imported, source: record)
        } catch {
            // A disallowed replacement must never mutate a completed source.
            if case ImportFailure.replacementHasRows = error { return .failure(fileName, error) }
            return recordFailure(error, name: fileName, source: source)
        }
    }

    func retry(sourceId: String) async -> ImportOutcome {
        await acquire(); defer { release() }
        do {
            guard let source = try store.source(id: sourceId) else { throw ImportFailure.unavailableSource }
            if source.status == .processed { return ImportOutcome(fileName: source.fileName, status: .alreadyImported, source: source) }
            if let json = source.importedJSON ?? (source.mimeType == "application/json" ? source.rawText : nil) {
                return await importJSONUnlocked(text: json, fileName: source.fileName, sourceId: sourceId, sourceType: source.sourceType)
            }
            guard let relative = source.localRelativePath, let data = try? files.read(relative) else { throw ImportFailure.missingImage }
            return await importImageUnlocked(data: data, fileName: source.fileName, mimeType: source.mimeType, sourceType: source.sourceType, retrySource: source)
        } catch { return .failure("Retry", error) }
    }

    func backfillFingerprints() throws {
        let sources = try store.allSources()
        try store.commit {
            for var source in sources where source.contentFingerprint == nil {
                if let relative = source.localRelativePath, let data = try? files.read(relative) {
                    source.contentFingerprint = ContentFingerprint.image(data)
                } else if let text = source.importedJSON ?? source.rawText,
                          let parsed = try? ExtractionJSONParser.parse(text) {
                    source.contentFingerprint = try ContentFingerprint.json(parsed)
                    source.importedJSON = text
                }
                if source.contentFingerprint != nil { try store.upsert(source: source) }
            }
        }
    }

    private func recordFailure(_ error: Error, name: String, source: SourceDocumentRecord?) -> ImportOutcome {
        guard var record = source else { return .failure(name, error) }
        record.status = .error; record.errorSummary = PrivacyRedactor.safeErrorDetail(error)
        do {
            try store.commit {
                try store.upsert(source: record)
                try store.upsert(review: ReviewItemRecord(reviewItemId: "review_" + StableHash.make([record.sourceDocumentId, "source_error"]),
                    targetType: .sourceDocument, targetId: record.sourceDocumentId, issueType: .missingField, severity: .high,
                    question: "Import needs attention: \(record.errorSummary ?? "Unknown error")", fieldName: "extraction"))
            }
            return .failure(name, error, source: record)
        } catch {
            return .failure(name, error)
        }
    }

    private func persist(extraction: ScreenshotExtractionResult, source: inout SourceDocumentRecord) async throws {
        guard !extraction.transactions.isEmpty || !extraction.assetSnapshots.isEmpty else {
            if source.rawText == nil { source.rawText = extraction.rawText }
            throw ExtractionError.emptyResult
        }
        let output = await ProcessingPipeline.process(PipelineInput(sourceDocumentId: source.sourceDocumentId,
            fileName: source.fileName, extraction: extraction, existingTransactions: try store.allTransactions(),
            corrections: try store.allCorrections(), existingAssets: try store.allAssets()),
            classifier: OnDeviceAIFactory.makeClassifier(enabled: enableFoundationModels()))
        source.status = .processed; source.processedAt = Date(); source.modifiedTime = Date()
        if source.rawText == nil || source.rawText?.isEmpty == true { source.rawText = extraction.rawText }
        source.errorSummary = output.warnings.isEmpty ? nil : PrivacyRedactor.maskSensitiveText(output.warnings.joined(separator: "; "))
        let record = source
        try store.commit(rebuild: true) {
            for tx in output.transactions { try store.upsert(transaction: tx) }
            for asset in output.assetSnapshots { try store.upsert(asset: asset) }
            for review in output.reviewItems { try store.upsert(review: review) }
            for var review in try store.allReviews() where review.targetType == .sourceDocument && review.targetId == record.sourceDocumentId && review.status == .pending {
                review.status = .resolved; review.resolvedAt = Date(); review.userAnswer = "Import completed"
                try store.upsert(review: review)
            }
            try store.upsert(source: record)
        }
    }

    func seedDemo() throws {
        let seed = DemoSeed.make()
        try store.commit(rebuild: true) {
            for source in seed.sources where try store.source(id: source.sourceDocumentId) == nil { try store.upsert(source: source) }
            let ids = Set(try store.allTransactions().map(\.transactionId))
            let assetIds = Set(try store.allAssets().map(\.assetSnapshotId))
            for tx in seed.transactions where !ids.contains(tx.transactionId) { try store.upsert(transaction: tx) }
            for asset in seed.assets where !assetIds.contains(asset.assetSnapshotId) { try store.upsert(asset: asset) }
            let reviewIds = Set(try store.allReviews().map(\.reviewItemId))
            for review in seed.reviews where !reviewIds.contains(review.reviewItemId) { try store.upsert(review: review) }
        }
    }

    func apply(review: ReviewItemRecord, action: ReviewAction) throws {
        let applied = try CorrectionApplier.apply(review: review, action: action, transactions: store.allTransactions(), reviewItems: store.allReviews())
        try store.commit(rebuild: true) {
            for tx in applied.transactions { try store.upsert(transaction: tx) }
            for review in applied.reviewItems { try store.upsert(review: review) }
            for correction in applied.corrections { try store.insert(correction: correction) }
        }
    }
}

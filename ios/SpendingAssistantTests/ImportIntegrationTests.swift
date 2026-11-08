import XCTest
import SwiftData
import UIKit
import SpendingDomain
@testable import SpendingAssistant

@MainActor
final class ImportIntegrationTests: XCTestCase {
    private func setup(recognize: @escaping (Data) async throws -> [OCRLine] = { _ in
        [OCRLine(text: "01/01/2026 Novel shop $12.00")]
    }) throws -> (ModelContainer, LocalStore, ImportPipelineService, URL) {
        let container = try ModelContainer(for: SpendingPersistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LocalStore(modelContext: container.mainContext)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = ImportPipelineService(store: store, files: SourceFileStore(directory: root), enableFoundationModels: { false }, recognize: recognize)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (container, store, service, root)
    }

    private func json(id: String = "replace-me", merchant: String = "Novel shop", amount: String = "12.00") throws -> String {
        let extraction = ScreenshotExtractionResult(sourceDocumentId: id, rawText: "OCR evidence", transactions: [
            ExtractedTransactionCandidate(rowIndex: 0, dateText: "2026-01-01", merchantText: merchant, amountText: amount,
                transactionTypeHint: .expense, confidence: 0.9, evidenceText: "Original screenshot row")
        ])
        return String(decoding: try JSONEncoder().encode(extraction), as: UTF8.self)
    }

    func testIdenticalImageAcrossEntrypointsImportsOnceAndPreservesCorrections() async throws {
        let (container, store, service, _) = try setup()
        _ = container
        let first = await service.importImage(data: Data([1, 2]), fileName: "one.png", mimeType: "image/png", sourceType: .files)
        XCTAssertEqual(first.status, .imported)
        let category = try XCTUnwrap(store.allReviews().first { $0.issueType == .unclearCategory })
        try service.apply(review: category, action: .category(.dining, remember: true))
        let before = try store.allReviews()
        let second = await service.importImage(data: Data([1, 2]), fileName: "renamed.png", mimeType: "image/png", sourceType: .share)
        XCTAssertEqual(second.status, .alreadyImported)
        XCTAssertEqual(try store.allSources().count, 1)
        XCTAssertEqual(try store.allTransactions().count, 1)
        XCTAssertEqual(try store.allTransactions()[0].category, .dining)
        XCTAssertEqual(try store.allReviews(), before)
    }

    func testJSONReimportAndReusedExternalIDs() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let first = await service.importAIJSON(text: try json())
        let second = await service.importAIJSON(text: try json(id: "ignored"))
        let third = await service.importAIJSON(text: try json(merchant: "Different merchant"))
        XCTAssertEqual(first.status, .imported); XCTAssertEqual(second.status, .alreadyImported); XCTAssertEqual(third.status, .imported)
        XCTAssertEqual(try store.allSources().count, 2)
        XCTAssertEqual(try store.allTransactions().count, 2)
        XCTAssertNotEqual(first.source?.sourceDocumentId, "replace-me")
        XCTAssertNotEqual(first.source?.sourceDocumentId, third.source?.sourceDocumentId)
    }

    func testConcurrentImportsAreSerialized() async throws {
        var active = 0; var peak = 0
        let (container, store, service, _) = try setup { _ in
            active += 1; peak = max(peak, active)
            await Task.yield()
            active -= 1
            return [OCRLine(text: "01/01/2026 Safeway $12.00")]
        }; _ = container
        async let a = service.importImage(data: Data([1]), fileName: "a.png", mimeType: "image/png", sourceType: .photos)
        async let b = service.importImage(data: Data([1]), fileName: "b.png", mimeType: "image/png", sourceType: .share)
        let results = await [a, b]
        XCTAssertEqual(peak, 1)
        XCTAssertEqual(results.filter { $0.status == .imported }.count, 1)
        XCTAssertEqual(results.filter { $0.status == .alreadyImported }.count, 1)
        XCTAssertEqual(try store.allTransactions().count, 1)
    }

    func testBatchContinuesAfterLoadFailureAndReportsCounts() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let coordinator = ImportCoordinator(service: service, inbox: nil)
        let text = try json()
        let results = await coordinator.run([
            ImportJob(name: "failure") { throw ImportFailure.emptyImage },
            ImportJob(name: "valid") { .json(text, sourceType: .aiImport) },
            ImportJob(name: "repeat") { .json(text, sourceType: .aiImport) }
        ])
        XCTAssertEqual(results.map(\.status), [.failed, .imported, .alreadyImported])
        XCTAssertEqual(coordinator.completed, 3)
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertEqual(coordinator.summary, "1 imported · 1 already imported · 1 failed")
        XCTAssertEqual(try store.allSources().count, 1)
    }

    func testEmptyOCRPreservesEvidenceAndRepairUsesOriginalSource() async throws {
        let (container, store, service, _) = try setup { _ in [OCRLine(text: "unrecognized table heading")] }; _ = container
        let failed = await service.importImage(data: Data([1]), fileName: "test.png", mimeType: "image/png", sourceType: .files)
        XCTAssertEqual(failed.status, .failed)
        let source = try XCTUnwrap(store.allSources().first)
        XCTAssertEqual(source.rawText, "unrecognized table heading")
        XCTAssertEqual(source.status, .error)
        XCTAssertTrue(try store.allReviews().contains { $0.targetType == .sourceDocument && $0.status == .pending })
        let repaired = await service.importAIJSON(text: try json(), attachingTo: source.sourceDocumentId)
        XCTAssertEqual(repaired.status, .imported)
        XCTAssertEqual(try store.allSources().count, 1)
        XCTAssertEqual(try store.allTransactions()[0].sourceDocumentId, source.sourceDocumentId)
        XCTAssertEqual(try store.allSources()[0].rawText, source.rawText)
        XCTAssertFalse(try store.allReviews().contains { $0.targetType == .sourceDocument && $0.status == .pending })
        let disallowed = await service.importAIJSON(text: try json(merchant: "Other"), attachingTo: source.sourceDocumentId)
        XCTAssertEqual(disallowed.status, .failed)
        XCTAssertEqual(try store.allSources()[0].status, .processed)
    }

    func testRetryAfterOCRFailureReusesSource() async throws {
        var attempts = 0
        let (container, store, service, _) = try setup { _ in
            attempts += 1
            if attempts == 1 { throw ImportFailure.emptyImage }
            return [OCRLine(text: "01/01/2026 Safeway $12.00")]
        }; _ = container
        let failed = await service.importImage(data: Data([1]), fileName: "test.png", mimeType: "image/png", sourceType: .files)
        let id = try XCTUnwrap(failed.source?.sourceDocumentId)
        let retried = await service.retry(sourceId: id)
        XCTAssertEqual(retried.status, .imported)
        XCTAssertEqual(retried.source?.sourceDocumentId, id)
        XCTAssertEqual(try store.allSources().count, 1)
    }

    func testExpiredImageReturnsRecoveryGuidance() async throws {
        let (container, store, service, _) = try setup { _ in [] }; _ = container
        let result = await service.importImage(data: Data([1]), fileName: "test.png", mimeType: "image/png", sourceType: .files)
        let source = try XCTUnwrap(result.source)
        try service.files.remove(try XCTUnwrap(source.localRelativePath))
        let retry = await service.retry(sourceId: source.sourceDocumentId)
        XCTAssertEqual(retry.status, .failed)
        XCTAssertTrue(retry.error?.contains("Reimport") == true)
        XCTAssertEqual(try store.allSources().count, 1)
    }

    func testFailedShareStaysUntilExplicitRetryAndDoesNotAutoRetry() async throws {
        let (container, _, service, root) = try setup(); _ = container
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pending = root.appendingPathComponent("bad.json")
        try Data("not json".utf8).write(to: pending)
        let coordinator = ImportCoordinator(service: service, inbox: root)
        await coordinator.drainShareInbox()
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertEqual(coordinator.shareFailures.count, 1)
        let initial = coordinator.outcomes[0].id
        await coordinator.drainShareInbox()
        XCTAssertEqual(coordinator.outcomes[0].id, initial)
        try Data(try json().utf8).write(to: pending)
        await coordinator.retryShare(try XCTUnwrap(coordinator.shareFailures.first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertTrue(coordinator.shareFailures.isEmpty)
    }

    func testOverlappingShareDrainsAndDeletion() async throws {
        let (container, store, service, root) = try setup(); _ = container
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(try json().utf8).write(to: root.appendingPathComponent("good.json"))
        try Data("bad".utf8).write(to: root.appendingPathComponent("bad.json"))
        let coordinator = ImportCoordinator(service: service, inbox: root)
        async let a: Void = coordinator.drainShareInbox()
        async let b: Void = coordinator.drainShareInbox()
        _ = await (a, b)
        XCTAssertEqual(try store.allTransactions().count, 1)
        XCTAssertEqual(coordinator.shareFailures.count, 1)
        coordinator.deleteShare(try XCTUnwrap(coordinator.shareFailures.first))
        XCTAssertTrue(try ShareInboxService.items(in: root).isEmpty)
    }

    func testCommitFailureRollsBackRowsReviewsAndSummaries() async throws {
        let (container, store, service, _) = try setup(); _ = container
        try service.seedDemo()
        let transactions = try store.allTransactions()
        let reviews = try store.allReviews()
        let summaries = try store.allCashFlows()
        var saves = 0
        store.beforeSave = {
            saves += 1
            // Backfill is first; the import's rows and derived entities are in the next commit.
            if saves == 2 { throw ImportFailure.emptyImage }
        }
        let result = await service.importAIJSON(text: try json())
        store.beforeSave = nil
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(Set(try store.allTransactions().map(\.transactionId)), Set(transactions.map(\.transactionId)))
        XCTAssertEqual(try store.allReviews().filter { $0.targetType == .transaction }.count, reviews.count)
        XCTAssertEqual(try store.allCashFlows().map(\.netCashFlow).sorted(), summaries.map(\.netCashFlow).sorted())
        XCTAssertEqual(try store.allSources().first { $0.sourceDocumentId != "demo_source_001" }?.status, .error)
    }

    func testLegacyFingerprintBackfillPreservesIdentityAndRows() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let path = try service.files.save(data: Data([1]), sourceId: "legacy", fileName: "test.png")
        let old = SourceDocumentRecord(sourceDocumentId: "legacy", sourceType: .files, fileName: "legacy.png", mimeType: "image/png", localRelativePath: path, status: .processed)
        let legacyJSON = SourceDocumentRecord(sourceDocumentId: "old-json", sourceType: .aiImport, fileName: "old.json", mimeType: "application/json", status: .processed, rawText: try json())
        try store.commit { try store.upsert(source: old); try store.upsert(source: legacyJSON) }
        let repeated = await service.importImage(data: Data([1]), fileName: "repeat.png", mimeType: "image/png", sourceType: .photos)
        XCTAssertEqual(repeated.status, .alreadyImported)
        XCTAssertEqual(repeated.source?.sourceDocumentId, "legacy")
        let repeatedJSON = await service.importAIJSON(text: try json(id: "other"))
        XCTAssertEqual(repeatedJSON.source?.sourceDocumentId, "old-json")
        XCTAssertEqual(repeatedJSON.status, .alreadyImported)
        XCTAssertEqual(try store.allSources().count, 2)
        XCTAssertTrue(try store.allTransactions().isEmpty)
    }

    func testRealVisionOCRWithSyntheticScreenshot() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 300))
        let image = renderer.image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 300))
            ("01/01/2026 Safeway $12.00" as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }
        let lines = try await VisionOCRService.recognizeLines(from: try XCTUnwrap(image.pngData()))
        XCTAssertTrue(lines.contains { $0.text.contains("Safeway") })
        let parsed = HeuristicScreenshotParser.parse(sourceDocumentId: "synthetic", fileName: "card.png", lines: lines)
        XCTAssertEqual(parsed.transactions.count, 1)
    }
}

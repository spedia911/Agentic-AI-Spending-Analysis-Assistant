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
        store.readDefaultCurrency = { nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = ImportPipelineService(store: store, files: SourceFileStore(directory: root), enableFoundationModels: { false }, recognize: recognize)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (container, store, service, root)
    }

    private func mapAll(_ store: LocalStore) throws {
        if try store.allAccounts().isEmpty { try store.saveAccount(label: "Synthetic test account", currency: "USD") }
        let id = try XCTUnwrap(store.allAccounts().first?.id)
        try store.mapRecords(transactions: Set(store.allTransactions().map(\.id)), assets: Set(store.allAssets().map(\.id)), accountId: id)
    }

    func testRetentionRemovesOnlyExpiredStoredCopies() async throws {
        let (container, store, service, _) = try setup()
        _ = container
        let first = await service.importImage(data: Data([11, 19]), fileName: "Old.png", mimeType: "image/png", sourceType: .files)
        let second = await service.importImage(data: Data([12, 20]), fileName: "Recent.png", mimeType: "image/png", sourceType: .files)
        let oldPath = try XCTUnwrap(first.source?.localRelativePath)
        let recentPath = try XCTUnwrap(second.source?.localRelativePath)
        let oldURL = try service.files.url(oldPath)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-31 * 86_400)], ofItemAtPath: oldURL.path)
        let transactions = try store.allTransactions().map(\.id).sorted()
        XCTAssertEqual(try service.cleanupSources(retentionDays: 0), 0)
        XCTAssertEqual(try service.cleanupSources(retentionDays: 30), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try service.files.read(recentPath), Data([12, 20]))
        XCTAssertEqual(try store.allTransactions().map(\.id).sorted(), transactions)
        XCTAssertNotNil(try store.source(id: XCTUnwrap(first.source?.id))?.ocrLinesJSON)
    }

    func testDeleteTransactionsAndRollback() async throws {
        let (container, store, service, _) = try setup(); _ = container
        _ = await service.importAIJSON(text: try json())
        let tx = try XCTUnwrap(store.allTransactions().first)
        store.beforeSave = { throw ImportFailure.emptyImage }
        XCTAssertThrowsError(try store.deleteTransactions(ids: [tx.transactionId]))
        XCTAssertEqual(try store.allTransactions().count, 1)
        store.beforeSave = nil
        try store.deleteTransactions(ids: [tx.transactionId])
        XCTAssertTrue(try store.allTransactions().isEmpty)
        XCTAssertFalse(try store.allReviews().contains { $0.targetId == tx.transactionId })
        XCTAssertEqual(try store.allSources().count, 1)
        XCTAssertTrue(try store.allMonthlySummaries().isEmpty)
    }

    func testDeleteDuplicateMatchClearsSurvivingRowsDuplicateReview() throws {
        let (container, store, service, _) = try setup(); _ = container
        let edit = TransactionEdit(date: "2026-01-01", merchant: "Synthetic cafe", amount: -12, type: .expense, account: "Sample")
        try service.addManualTransaction(edit, category: .dining)
        let first = try XCTUnwrap(store.allTransactions().first)
        try service.addManualTransaction(edit, category: .dining)
        let review = try XCTUnwrap(store.allReviews().first { $0.issueType == .duplicateRisk })
        XCTAssertEqual(review.status, .pending)
        try store.deleteTransactions(ids: [first.transactionId])
        XCTAssertEqual(try store.allReviews().first { $0.reviewItemId == review.reviewItemId }?.status, .resolved)
        XCTAssertEqual(try store.allTransactions().first?.validationStatus, .valid)
    }

    func testDeleteEntireSourceAllowsReimport() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let result = await service.importImage(data: Data([22, 33]), fileName: "synthetic.png", mimeType: "image/png", sourceType: .files)
        let source = try XCTUnwrap(result.source)
        let path = try XCTUnwrap(source.localRelativePath)
        store.beforeSave = { throw ImportFailure.emptyImage }
        XCTAssertThrowsError(try service.deleteSource(id: source.sourceDocumentId))
        XCTAssertEqual(try service.files.read(path), Data([22, 33]))
        XCTAssertEqual(try store.allTransactions().count, 1)
        store.beforeSave = nil
        try service.deleteSource(id: source.sourceDocumentId)
        XCTAssertThrowsError(try service.files.read(path))
        XCTAssertTrue(try store.allSources().isEmpty)
        XCTAssertTrue(try store.allTransactions().isEmpty)
        XCTAssertTrue(try store.allReviews().isEmpty)
        let repeated = await service.importImage(data: Data([22, 33]), fileName: "synthetic.png", mimeType: "image/png", sourceType: .files)
        XCTAssertEqual(repeated.status, .imported)
    }

    func testUndoCategoryRestoresReviewAndMerchantMemory() async throws {
        let (container, store, service, _) = try setup(); _ = container
        _ = await service.importAIJSON(text: try json())
        let tx = try XCTUnwrap(store.allTransactions().first)
        let review = try XCTUnwrap(store.allReviews().first { $0.issueType == .unclearCategory })
        let snapshot = try service.reviewSnapshot(tx)
        try service.apply(review: review, action: .category(.dining, remember: true))
        XCTAssertEqual(try store.allTransactions().first?.category, .dining)
        try service.undoReview(snapshot)
        XCTAssertEqual(try store.allTransactions().first, tx)
        XCTAssertEqual(try store.allReviews(), snapshot.reviews)
        XCTAssertTrue(try store.allCorrections().isEmpty)
    }

    func testAdvisoryExtractionCanStayUncheckedWhenConfirmingTransaction() async throws {
        let (container, store, service, _) = try setup { _ in
            [OCRLine(text: "01/01/2026 Safeway $12.00")]
        }; _ = container
        let outcome = await service.importImage(data: Data([7, 1]), fileName: "test.png", mimeType: "image/png", sourceType: .files)
        XCTAssertEqual(outcome.status, .imported)
        try mapAll(store)
        let original = try XCTUnwrap(store.allTransactions().first)
        let advisory = try XCTUnwrap(store.allReviews().first(where: \.isAdvisory))
        XCTAssertEqual(original.validationStatus, .valid)
        XCTAssertEqual(try store.allCashFlows().first?.unresolvedCount, 0)

        var legacy = original
        legacy.validationStatus = .needsReview; legacy.reviewStatus = .pending
        try store.commit { try store.upsert(transaction: legacy) }
        try store.reconcileAdvisoryReviews()
        XCTAssertEqual(try store.allTransactions().first?.validationStatus, .valid)
        XCTAssertEqual(try store.allReviews().first { $0.reviewItemId == advisory.reviewItemId }?.status, .pending)

        let fields = TransactionEdit(date: original.transactionDate, merchant: original.merchantNormalized,
            amount: original.amount, type: original.transactionType, account: original.accountLabel)
        XCTAssertTrue(try service.editTransaction(id: original.transactionId, fields: fields, category: nil, confirm: true))
        let confirmed = try XCTUnwrap(store.allTransactions().first)
        XCTAssertEqual(confirmed.reviewStatus, .resolved)
        XCTAssertEqual(confirmed.extractionConfidence, original.extractionConfidence)
        XCTAssertEqual(confirmed.evidenceText, original.evidenceText)
        XCTAssertEqual(try store.allReviews().first { $0.reviewItemId == advisory.reviewItemId }?.status, .pending)
        XCTAssertFalse(try service.editTransaction(id: original.transactionId, fields: fields, category: nil, confirm: true))
    }

    func testUnifiedSaveRemembersCategoryAndLeavesMissingDateOpen() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let text = try json().replacingOccurrences(of: "2026-01-01", with: "")
        _ = await service.importAIJSON(text: text)
        let original = try XCTUnwrap(store.allTransactions().first)
        try service.editTransaction(id: original.transactionId, fields: TransactionEdit(
            date: original.transactionDate, merchant: original.merchantNormalized, amount: original.amount,
            type: original.transactionType, account: original.accountLabel), category: .dining, rememberCategory: true, confirm: true)
        XCTAssertEqual(try store.allTransactions().first?.category, .dining)
        XCTAssertTrue(try store.allReviews().contains { $0.issueType == .missingField && $0.status == .pending })
        XCTAssertTrue(try store.allCorrections().contains { $0.targetType == .merchantRule && $0.applyFuture })
    }

    func testBalanceEditResolvesOnlyItsReviewAndKeepsEvidence() throws {
        let (container, store, service, _) = try setup(); _ = container
        try service.seedDemo()
        var asset = try XCTUnwrap(store.allAssets().first)
        let evidence = asset.evidenceText
        let balanceReview = ReviewItemRecord(reviewItemId: "balance-review", targetType: .assetSnapshot,
            targetId: asset.assetSnapshotId, issueType: .missingField, severity: .medium, question: "Check balance")
        try store.commit { try store.upsert(review: balanceReview) }
        asset.balance = 3200
        try store.saveReviewedAsset(asset)
        let saved = try XCTUnwrap(store.allAssets().first { $0.assetSnapshotId == asset.assetSnapshotId })
        XCTAssertEqual(saved.balance, 3200)
        XCTAssertEqual(saved.evidenceText, evidence)
        XCTAssertEqual(try store.allReviews().first { $0.reviewItemId == balanceReview.reviewItemId }?.status, .resolved)
        XCTAssertTrue(try store.allReviews().contains { $0.targetType == .transaction && $0.status == .pending })
        try store.deleteAsset(id: asset.assetSnapshotId)
        XCTAssertFalse(try store.allReviews().contains { $0.reviewItemId == balanceReview.reviewItemId })
    }

    func testStatementPDFPersistsRowsBalanceAndFingerprint() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let lines = ["Oct 1 - Oct 31, 2026", "Simply Checking - 1234509876", "DATE DESCRIPTION CATEGORY AMOUNT BALANCE",
                     "Oct 1 Opening Balance $100.00", "Oct 2 Deposit from EXAMPLE EMPLOYER PAYROLL + $50.00 $150.00",
                     "Oct 31 Closing Balance $150.00"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            context.beginPage()
            for (i, row) in lines.enumerated() {
                (row as NSString).draw(at: CGPoint(x: 32, y: 40 + i * 24),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
        let first = await service.importImage(data: data, fileName: "synthetic.pdf", mimeType: "application/pdf", sourceType: .files)
        XCTAssertEqual(first.status, .imported, first.error ?? "")
        XCTAssertEqual(try store.allTransactions().first?.transactionType, .income)
        XCTAssertEqual(try store.allTransactions().first?.accountLabel, "Simply Checking *9876")
        XCTAssertEqual(try store.allAssets().first?.balance, 150)
        XCTAssertFalse(try store.allSources().first?.rawText?.contains("1234509876") ?? true)
        let repeatImport = await service.importImage(data: data, fileName: "renamed.pdf", mimeType: "application/pdf", sourceType: .files)
        XCTAssertEqual(repeatImport.status, .alreadyImported)
    }

    func testAccountAndMerchantPropagationWithScopedUndo() async throws {
        let (container, store, service, _) = try setup { _ in [
            OCRLine(text: "01/01/2026 Example Shop $12.00"),
            OCRLine(text: "01/02/2026 Unrelated Market $16.00")
        ] }; _ = container
        let image = await service.importImage(data: Data([8, 1]), fileName: "synthetic.png", mimeType: "image/png", sourceType: .files)
        let source = try XCTUnwrap(image.source)
        _ = await service.importAIJSON(text: try json(merchant: "EXAMPLE-SHOP", amount: "23.00"))
        let before = try store.allTransactions()
        let selected = try XCTUnwrap(before.first { $0.sourceDocumentId == source.sourceDocumentId && $0.merchantNormalized == "Example Shop" })
        let snapshot = try service.reviewSnapshot(selected, accountSource: true, merchant: selected.merchantNormalized)
        try service.editTransaction(id: selected.transactionId, fields: TransactionEdit(date: selected.transactionDate,
            merchant: selected.merchantNormalized, amount: selected.amount, type: selected.transactionType, account: "Example checking"),
            category: .shopping, rememberCategory: true, confirm: true, matchSourceAccount: true)
        let applied = try store.allTransactions()
        XCTAssertEqual(applied.filter { $0.sourceDocumentId == source.sourceDocumentId }.map(\.accountLabel), ["Example checking", "Example checking"])
        XCTAssertEqual(try store.source(id: source.sourceDocumentId)?.cardName, "Example checking")
        XCTAssertTrue(applied.filter { Categorizer.merchantKey($0.merchantNormalized) == "exampleshop" }.allSatisfy { $0.category == .shopping })
        XCTAssertNotEqual(applied.first { $0.merchantNormalized == "Unrelated Market" }?.category, .shopping)
        try service.undoReview(snapshot)
        XCTAssertEqual(try store.allTransactions().sorted { $0.id < $1.id }, before.sorted { $0.id < $1.id })
        XCTAssertNil(try store.source(id: source.sourceDocumentId)?.cardName)

        try service.setMerchantCategory("EXAMPLE-SHOP", category: .shopping)
        _ = await service.importAIJSON(text: try json(merchant: "example shop", amount: "55.00"))
        XCTAssertTrue(try store.allTransactions().filter { Categorizer.merchantKey($0.merchantNormalized) == "exampleshop" }.allSatisfy { $0.category == .shopping })
    }

    func testMissingScreenshotDetailsPauseAndResumeWithoutOriginalImage() async throws {
        let (container, store, service, _) = try setup { _ in [
            OCRLine(text: "09/30 Safeway $12.00"), OCRLine(text: "10/02 Safeway $15.00")
        ] }; _ = container
        let bytes = Data([99, 3, 7])
        let waiting = await service.importImage(data: bytes, fileName: "synthetic.png", mimeType: "image/png",
            sourceType: .files, requestDetails: true)
        XCTAssertEqual(waiting.status, .needsDetails)
        let request = try XCTUnwrap(waiting.details)
        XCTAssertTrue(request.needsYear)
        XCTAssertTrue(request.needsAccount)
        XCTAssertFalse(request.needsDate)
        XCTAssertTrue(try store.allTransactions().isEmpty)
        XCTAssertEqual(try store.source(id: request.id)?.status, .needsDetails)
        try service.deleteStoredImage(sourceId: request.id)
        XCTAssertTrue(try XCTUnwrap(service.detailsForSource(id: request.id)).needsYear)
        let completed = await service.completeScreenshotDetails(id: request.id, account: "Sample Checking",
            month: "2026", fallbackDate: nil)
        XCTAssertEqual(completed.status, .imported, completed.error ?? "")
        XCTAssertEqual(try store.allTransactions().map(\.transactionDate).sorted(), ["2026-09-30", "2026-10-02"])
        XCTAssertTrue(try store.allTransactions().allSatisfy { $0.accountLabel == "Sample Checking" })
        try mapAll(store)
        XCTAssertEqual(try store.allCashFlows().count, 2)
        let repeatImport = await service.importImage(data: bytes, fileName: "copy.png", mimeType: "image/png", sourceType: .files, requestDetails: true)
        XCTAssertEqual(repeatImport.status, .alreadyImported)
    }

    func testSourceYearRepairPreservesExplicitAndManuallyEditedDates() async throws {
        let (container, store, service, _) = try setup { _ in [
            OCRLine(text: "09/30 Safeway $12.00"), OCRLine(text: "10/02/2025 Safeway $15.00"),
            OCRLine(text: "10/03 Safeway $18.00")
        ] }; _ = container
        let result = await service.importImage(data: Data([9, 18]), fileName: "synthetic.png", mimeType: "image/png", sourceType: .files)
        let source = try XCTUnwrap(result.source)
        let manual = try XCTUnwrap(store.allTransactions().first { $0.amount == 18 })
        try service.editTransaction(id: manual.id, fields: TransactionEdit(date: "2024-10-03",
            merchant: manual.merchantNormalized, amount: manual.amount, type: manual.transactionType, account: manual.accountLabel), category: nil)
        let ids = Set(try store.allTransactions().map(\.id))
        try service.updateSourceOptions(id: source.id, cardName: "Sample Checking", layout: .generic, month: "2026")
        try service.updateSourceOptions(id: source.id, cardName: "Renamed Checking", layout: .generic, month: "2024")
        let rows = try store.allTransactions()
        XCTAssertEqual(Set(rows.map(\.id)), ids)
        XCTAssertEqual(rows.map(\.transactionDate).sorted(), ["2024-09-30", "2024-10-03", "2025-10-02"])
        XCTAssertTrue(rows.allSatisfy { $0.accountLabel == "Renamed Checking" })
        XCTAssertNil(try store.source(id: source.id)?.errorSummary)
        XCTAssertFalse(try store.allReviews().contains { $0.fieldName == "transaction_date" && $0.status == .pending })
        try mapAll(store)
        XCTAssertEqual(Set(try store.allCashFlows().map(\.month)), ["2024-09", "2024-10", "2025-10"])
    }

    func testUnreadableDateCanBeSuppliedExplicitly() async throws {
        let (container, store, service, _) = try setup { _ in [
            OCRLine(text: "Safeway", boundingBox: EvidenceRegion(x: 0.1, y: 0.3, width: 0.2, height: 0.02)),
            OCRLine(text: "$22.00", boundingBox: EvidenceRegion(x: 0.75, y: 0.3, width: 0.2, height: 0.02))
        ] }; _ = container
        let staged = await service.importImage(data: Data([8, 90]), fileName: "synthetic.png", mimeType: "image/png", sourceType: .files,
            options: .init(cardName: "Sample Checking"), requestDetails: true)
        let details = try XCTUnwrap(staged.details)
        XCTAssertTrue(details.needsDate)
        XCTAssertFalse(details.needsYear)
        XCTAssertFalse(details.needsAccount)
        let finished = await service.completeScreenshotDetails(id: details.id, account: "Sample Checking", month: "", fallbackDate: "2026-10-11")
        XCTAssertEqual(finished.status, .imported)
        XCTAssertEqual(try store.allTransactions().first?.transactionDate, "2026-10-11")
        XCTAssertNil(finished.source?.errorSummary)
    }

    func testBatchDateReuseKeepsAccountRequestsAndSkipsOtherBatches() async throws {
        let (container, store, service, _) = try setup { _ in [OCRLine(text: "10/02 Safeway $12.00")] }; _ = container
        let coordinator = ImportCoordinator(service: service, inbox: nil)
        let firstBatch = await coordinator.run((1...2).map { i in
            ImportJob(name: "Screenshot \(i).png") { .image(Data([UInt8(i), 35]), mimeType: "image/png", sourceType: .files) }
        })
        let first = try XCTUnwrap(coordinator.nextDetails())
        let second = try XCTUnwrap(firstBatch.last?.details)
        let other = await coordinator.run([ImportJob(name: "Another batch.png") {
            .image(Data([89, 35]), mimeType: "image/png", sourceType: .files)
        }])
        let unrelated = try XCTUnwrap(other.first?.details)
        XCTAssertTrue(coordinator.hasRemainingDates(in: first))
        let result = await coordinator.finishDetails(first, account: "Sample account", month: "2026-10",
            fallbackDate: nil, reusePeriod: true)
        XCTAssertEqual(result.status, .imported)
        XCTAssertEqual(try store.source(id: second.id)?.observedMonthHint, "2026-10")
        XCTAssertNil(try store.source(id: unrelated.id)?.observedMonthHint)
        let remaining = try XCTUnwrap(coordinator.nextDetails())
        XCTAssertEqual(remaining.id, second.id)
        XCTAssertFalse(remaining.needsYear)
        XCTAssertTrue(remaining.needsAccount)
        XCTAssertNil(try store.source(id: second.id)?.cardName)
    }

    func testMerchantCategoryStaysWithinStatementOriginOnExistingAndFutureRows() async throws {
        let (container, store, service, _) = try setup(); _ = container
        func sample(_ kind: ScreenshotKind, type: TransactionType, amount: String) throws -> String {
            let extraction = ScreenshotExtractionResult(sourceDocumentId: "synthetic", screenshotKind: kind, rawText: "", transactions: [
                ExtractedTransactionCandidate(rowIndex: 0, dateText: "2026-01-01", merchantText: "Example Card",
                    amountText: amount, transactionTypeHint: type, confidence: 0.95, evidenceText: "Example issuer")
            ])
            return String(decoding: try JSONEncoder().encode(extraction), as: UTF8.self)
        }
        _ = await service.importAIJSON(text: try sample(.bankActivity, type: .transfer, amount: "-100.00"))
        _ = await service.importAIJSON(text: try sample(.creditCard, type: .fee, amount: "-20.00"))
        try service.setMerchantCategory("EXAMPLE-CARD", origin: .bank, category: .transfer)
        try service.setMerchantCategory("Example Card", origin: .card, category: .fees)
        _ = await service.importAIJSON(text: try sample(.bankActivity, type: .expense, amount: "-102.00"))
        _ = await service.importAIJSON(text: try sample(.creditCard, type: .expense, amount: "-21.00"))
        let rows = try store.allTransactions()
        XCTAssertEqual(rows.filter { $0.origin == .bank }.map(\.category), [.transfer, .transfer])
        XCTAssertEqual(rows.filter { $0.origin == .card }.map(\.category), [.fees, .fees])
        XCTAssertEqual(rows.filter { $0.origin == .bank }.map(\.transactionType), [.transfer, .transfer])
        XCTAssertTrue(rows.filter { $0.origin == .card }.allSatisfy {
            TransactionClassification.isConsistent(type: $0.transactionType, category: $0.category)
        })
        XCTAssertEqual(Set(try store.allCorrections().filter { $0.targetType == .merchantRule }.map(\.targetId)),
            ["bank|EXAMPLE-CARD", "card|Example Card"])
    }

    func testBatchRemovalValidatesPreviewAndPreservesOriginals() throws {
        let (container, store, _, _) = try setup(); _ = container
        let seed = try XCTUnwrap(DemoSeed.make().transactions.first)
        func row(_ id: String, source: String, amount: Double) -> TransactionRecord {
            var tx = seed
            tx.transactionId = id; tx.sourceDocumentId = source; tx.amount = amount
            tx.transactionDate = "2026-01-01"; tx.observedMonth = "2026-01"
            return tx
        }
        let keep = row("keep", source: "original", amount: -42)
        let copy = row("copy", source: "overlap", amount: -42)
        let unique = row("unique", source: "overlap", amount: -18)
        try store.commit(rebuild: true) {
            for tx in [keep, copy, unique] { try store.upsert(transaction: tx) }
        }
        let matches = DuplicateBatch.matches(keeping: "original", removing: "overlap", transactions: try store.allTransactions())
        XCTAssertEqual(matches.map(\.id), ["copy"])
        store.beforeSave = { throw ImportFailure.emptyImage }
        XCTAssertThrowsError(try store.removeConfirmedDuplicates(keeping: "original", removing: "overlap", matches: matches))
        store.beforeSave = nil
        XCTAssertEqual(Set(try store.allTransactions().map(\.id)), ["keep", "copy", "unique"])
        XCTAssertTrue(try store.allCorrections().isEmpty)
        try store.removeConfirmedDuplicates(keeping: "original", removing: "overlap", matches: matches)
        XCTAssertEqual(Set(try store.allTransactions().map(\.id)), ["keep", "unique"])
        try mapAll(store)
        XCTAssertEqual(try store.allCashFlows().first?.spendingTotal, 60)
        XCTAssertEqual(try store.allCorrections().first { $0.fieldName == "duplicate_removed" }?.newValue, "keep")
        XCTAssertThrowsError(try store.removeConfirmedDuplicates(keeping: "original", removing: "overlap", matches: matches))
    }

    func testMarkingAnomalyGroupReviewedSurvivesRebuild() throws {
        let (container, store, _, _) = try setup(); _ = container
        var first = try XCTUnwrap(DemoSeed.make().transactions.first)
        first.transactionDate = "2026-01-01"; first.observedMonth = "2026-01"
        var third = first
        third.transactionId = "march"; third.transactionDate = "2026-03-01"; third.observedMonth = "2026-03"
        try store.commit(rebuild: true) { try store.upsert(transaction: first); try store.upsert(transaction: third) }
        let anomaly = try XCTUnwrap(store.allAnomalies().first { $0.anomalyType == .missingData })
        try store.markAnomalyGroupReviewed(.missingData, ids: [anomaly.id])
        try store.commit(rebuild: true) {}
        XCTAssertEqual(try store.allAnomalies().first { $0.id == anomaly.id }?.status, .resolved)
        XCTAssertEqual(try store.allTransactions().count, 2)
    }

    func testSourceBatchUpdatesSelectedSourcesAndFinishesStagedImports() async throws {
        let (container, store, service, _) = try setup { _ in [OCRLine(text: "10/02 Safeway $12.00")] }; _ = container
        let first = await service.importImage(data: Data([3, 9]), fileName: "one.png", mimeType: "image/png", sourceType: .files, requestDetails: true)
        let second = await service.importImage(data: Data([4, 9]), fileName: "two.png", mimeType: "image/png", sourceType: .files, requestDetails: true)
        let unselected = await service.importImage(data: Data([5, 9]), fileName: "three.png", mimeType: "image/png", sourceType: .files, requestDetails: true)
        let firstId = try XCTUnwrap(first.source?.id)
        let secondId = try XCTUnwrap(second.source?.id)
        let otherId = try XCTUnwrap(unselected.source?.id)
        let outcomes = try await service.applySourceBatch(ids: [firstId, secondId], period: "2026-10", account: "Sample checking")
        XCTAssertEqual(outcomes.map(\.status), [.imported, .imported])
        XCTAssertTrue(try store.allTransactions().allSatisfy { $0.transactionDate == "2026-10-02" && $0.accountLabel == "Sample checking" })
        XCTAssertEqual(try store.source(id: otherId)?.status, .needsDetails)
        XCTAssertNil(try store.source(id: otherId)?.observedMonthHint)
        store.beforeSave = { throw ImportFailure.emptyImage }
        do {
            _ = try await service.applySourceBatch(ids: [firstId, secondId], period: nil, account: "Should roll back")
            XCTFail("Expected save failure")
        } catch {}
        store.beforeSave = nil
        XCTAssertTrue(try store.allTransactions().allSatisfy { $0.accountLabel == "Sample checking" })
        XCTAssertEqual(try store.source(id: firstId)?.cardName, "Sample checking")
        XCTAssertEqual(try store.source(id: secondId)?.cardName, "Sample checking")
    }

    func testTransactionFiltersCombineAccountCategoryAndInclusiveRange() throws {
        var row = try XCTUnwrap(DemoSeed.make().transactions.first)
        row.origin = .bank; row.accountLabel = "Sample checking"; row.category = .groceries; row.transactionDate = "2026-04-30"
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        var filter = TransactionFilters(category: .groceries, accountType: .bank, account: "Sample checking",
            dateMode: .range, start: start, end: end)
        XCTAssertTrue(filter.includes(row))
        filter.accountType = .card
        XCTAssertFalse(filter.includes(row))
        filter.accountType = .bank
        filter.dateMode = .month; filter.month = "2026-03"
        XCTAssertFalse(filter.includes(row))
        filter.month = "2026-04"
        XCTAssertTrue(filter.includes(row))
        row.accountLabel = "Another account"
        XCTAssertFalse(filter.includes(row))
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
        try service.updateSourceOptions(id: source.sourceDocumentId, cardName: "Apple Card", layout: .appleCard, month: "2026-01")
        let repaired = await service.importAIJSON(text: try json(), attachingTo: source.sourceDocumentId)
        XCTAssertEqual(repaired.status, .imported)
        XCTAssertEqual(try store.allSources().count, 1)
        XCTAssertEqual(try store.allTransactions()[0].sourceDocumentId, source.sourceDocumentId)
        XCTAssertEqual(try store.allTransactions()[0].accountLabel, "Apple Card")
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
        var legacySource = source
        legacySource.ocrLinesJSON = nil
        try store.commit { try store.upsert(source: legacySource) }
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

extension ImportIntegrationTests {
    func testDeleteStoredImageKeepsTransactionsReviewsAndFingerprint() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let imported = await service.importImage(data: Data([9]), fileName: "a.png", mimeType: "image/png", sourceType: .files)
        let source = try XCTUnwrap(imported.source)
        let path = try XCTUnwrap(source.localRelativePath)
        let tx = try store.allTransactions()
        let reviews = try store.allReviews()
        try service.deleteStoredImage(sourceId: source.sourceDocumentId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try service.files.url(path).path))
        let saved = try XCTUnwrap(store.source(id: source.sourceDocumentId))
        XCTAssertNil(saved.localRelativePath)
        XCTAssertNotNil(saved.imageDeletedAt)
        XCTAssertEqual(saved.contentFingerprint, source.contentFingerprint)
        XCTAssertNotNil(saved.ocrLinesJSON)
        XCTAssertEqual(try store.allTransactions(), tx)
        XCTAssertEqual(try store.allReviews(), reviews)
        let repeatImport = await service.importImage(data: Data([9]), fileName: "other.png", mimeType: "image/png", sourceType: .photos)
        XCTAssertEqual(repeatImport.status, .alreadyImported)
    }
    func testCardLayoutAndMonthRepairFromSavedOCRWithoutImage() async throws {
        let (container, store, service, _) = try setup { _ in [
            OCRLine(text: "Transactions", boundingBox: EvidenceRegion(x: 0.3, y: 0.1, width: 0.3, height: 0.02)),
            OCRLine(text: "March 12", boundingBox: EvidenceRegion(x: 0.1, y: 0.5, width: 0.3, height: 0.02)),
            OCRLine(text: "NOVEL SHOP", boundingBox: EvidenceRegion(x: 0.1, y: 0.55, width: 0.4, height: 0.02)),
            OCRLine(text: "$12.34", boundingBox: EvidenceRegion(x: 0.75, y: 0.55, width: 0.2, height: 0.02))]
        }; _ = container
        // Persist a failed source with recoverable geometry, as in an older failed extraction.
        let source = SourceDocumentRecord(sourceDocumentId: "failed-layout", sourceType: .files,
            fileName: "a.png", mimeType: "image/png", status: .error,
            ocrLinesJSON: String(decoding: try JSONEncoder().encode([
                OCRLine(text: "Transactions", boundingBox: EvidenceRegion(x: 0.3, y: 0.1, width: 0.3, height: 0.02)),
                OCRLine(text: "March 12", boundingBox: EvidenceRegion(x: 0.1, y: 0.5, width: 0.3, height: 0.02)),
                OCRLine(text: "NOVEL SHOP", boundingBox: EvidenceRegion(x: 0.1, y: 0.55, width: 0.4, height: 0.02)),
                OCRLine(text: "$12.34", boundingBox: EvidenceRegion(x: 0.75, y: 0.55, width: 0.2, height: 0.02))]), as: UTF8.self))
        try store.commit { try store.upsert(source: source) }
        try service.updateSourceOptions(id: source.sourceDocumentId, cardName: "Capital One Venture X", layout: .capitalOne, month: "2026-03")
        let result = await service.retry(sourceId: source.sourceDocumentId)
        XCTAssertEqual(result.status, .imported)
        let row = try XCTUnwrap(store.allTransactions().first)
        XCTAssertEqual(row.transactionDate, "2026-03-12")
        XCTAssertEqual(row.accountLabel, "Capital One Venture X")
        XCTAssertEqual(row.amount, 12.34)
    }
    func testManualEntryAndCorrectionRebuildTotalsAndKeepStableIdentity() throws {
        let (container, store, service, _) = try setup(); _ = container
        try service.addManualTransaction(TransactionEdit(date: "2026-03-10", merchant: "MANUAL SHOP", amount: -25,
            type: .expense, account: "Card 123456789"), category: .shopping)
        let original = try XCTUnwrap(store.allTransactions().first)
        XCTAssertEqual(try store.allSources()[0].sourceType, .manual)
        try mapAll(store)
        XCTAssertEqual(try store.allCashFlows()[0].spendingTotal, 25)
        XCTAssertFalse(original.accountLabel.contains("123456789"))
        try service.editTransaction(id: original.transactionId,
            fields: TransactionEdit(date: "2026-03-11", merchant: "Corrected shop", amount: -35,
                type: .expense, account: "Apple Card"), category: .dining)
        let updated = try XCTUnwrap(store.allTransactions().first)
        XCTAssertEqual(updated.transactionId, original.transactionId)
        XCTAssertEqual(updated.evidenceText, original.evidenceText)
        XCTAssertEqual(updated.category, .dining)
        try mapAll(store)
        XCTAssertEqual(try store.allCashFlows()[0].spendingTotal, 35)
        XCTAssertFalse(try store.allCorrections().isEmpty)
        XCTAssertThrowsError(try service.addManualTransaction(TransactionEdit(date: "bad", merchant: "", amount: 0,
            type: .expense, account: ""), category: .shopping))
        XCTAssertEqual(try store.allTransactions().count, 1)
    }
    func testCardRenamePreservesRowIdentityAndMasksNumbers() async throws {
        let (container, store, service, _) = try setup(); _ = container
        let imported = await service.importAIJSON(text: try json())
        let source = try XCTUnwrap(imported.source)
        let before = try store.allTransactions()[0]
        try service.updateSourceOptions(id: source.sourceDocumentId, cardName: "Apple Card 123456789", layout: .appleCard, month: "2026-01")
        let after = try store.allTransactions()[0]
        XCTAssertEqual(before.transactionId, after.transactionId)
        XCTAssertEqual(before.amount, after.amount)
        XCTAssertFalse(after.accountLabel.contains("123456789"))
        XCTAssertEqual(try store.source(id: source.sourceDocumentId)?.screenshotLayout, ScreenshotLayout.appleCard.rawValue)
    }
}

extension ImportIntegrationTests {
    func testManualSourceCompletionKeepsTransactionReviewPending() async throws {
        let (container, store, service, _) = try setup { _ in [] }; _ = container
        let failed = await service.importImage(data: Data([7]), fileName: "empty.png", mimeType: "image/png", sourceType: .files)
        let id = try XCTUnwrap(failed.source?.sourceDocumentId)
        let fields = TransactionEdit(date: "2026-03-10", merchant: "Example shop", amount: -12, type: .expense, account: "Apple Card")
        try service.addManualTransaction(fields, category: .shopping, sourceId: id)
        try service.addManualTransaction(fields, category: .shopping, sourceId: id)
        XCTAssertTrue(try store.allReviews().contains { $0.targetType == .transaction && $0.issueType == .duplicateRisk && $0.status == .pending })
        try service.completeManualSource(id: id)
        XCTAssertEqual(try store.source(id: id)?.status, .processed)
        XCTAssertFalse(try store.allReviews().contains { $0.targetType == .sourceDocument && $0.status == .pending })
        XCTAssertTrue(try store.allReviews().contains { $0.targetType == .transaction && $0.issueType == .duplicateRisk && $0.status == .pending })
    }
}

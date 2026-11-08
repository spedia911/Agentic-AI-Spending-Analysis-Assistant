import XCTest
@testable import SpendingDomain

final class ReliabilityTests: XCTestCase {
    private var tx: TransactionRecord { DemoSeed.make().transactions[1] }

    func testJSONFingerprintIgnoresSuppliedIDAndFormatting() throws {
        let a = ScreenshotExtractionResult(sourceDocumentId: "replace-me", rawText: "first")
        var b = a; b.sourceDocumentId = "another-id"
        XCTAssertEqual(try ContentFingerprint.json(a), try ContentFingerprint.json(b))
        b.rawText = "different"
        XCTAssertNotEqual(try ContentFingerprint.json(a), try ContentFingerprint.json(b))
        XCTAssertNotEqual(ContentFingerprint.image(Data([1])), ContentFingerprint.image(Data([2])))
    }

    func testValidationHasOneIssuePerFieldAndStrictDates() {
        var value = tx; value.transactionDate = "2026-02-30"; value.amount = 0; value.extractionConfidence = 0.4
        let result = Validator.validate([value])
        XCTAssertEqual(result.reviewItems.count, 3)
        XCTAssertEqual(Set(result.reviewItems.map(\.reviewItemId)).count, 3)
        XCTAssertEqual(Set(result.reviewItems.compactMap(\.fieldName)), ["transaction_date", "amount", "extraction"])
        var renamed = value; renamed.merchantNormalized = "New name"
        XCTAssertEqual(result.reviewItems.map(\.reviewItemId), Validator.validate([renamed]).reviewItems.map(\.reviewItemId))
        XCTAssertFalse(Validator.isValidDate("2026-13-01"))
        XCTAssertTrue(Validator.isValidDate("2024-02-29"))
    }

    func testCategoryDoesNotResolveMissingDateOrExtraction() {
        var value = tx; value.transactionDate = ""; value.extractionConfidence = 0.4
        let validations = Validator.validate([value])
        let category = DemoSeed.make().reviews[0]
        let applied = CorrectionApplier.applyCategoryCorrection(transactionId: value.transactionId, newCategory: .dining,
            remember: true, transactions: [value], reviewItems: validations.reviewItems + [category])
        XCTAssertEqual(applied.transactions[0].validationStatus, .needsReview)
        XCTAssertEqual(applied.transactions[0].reviewStatus, .pending)
        XCTAssertEqual(applied.reviewItems.filter { $0.status == .pending }.count, 2)
        XCTAssertEqual(applied.reviewItems.first { $0.issueType == .unclearCategory }?.status, .resolved)
    }

    func testFieldEditsPreserveEvidenceAndCategoryReview() throws {
        var value = tx; value.transactionDate = ""; value.extractionConfidence = 0.4
        let category = DemoSeed.make().reviews[0]
        let reviewItems = Validator.validate([value]).reviewItems + [category]
        let edited = try CorrectionApplier.apply(review: reviewItems[0], action: .edit(TransactionEdit(
            date: "2026-01-15", merchant: value.merchantNormalized, amount: -21, type: value.transactionType, account: "Card 123456789")),
            transactions: [value], reviewItems: reviewItems)
        XCTAssertEqual(edited.transactions[0].transactionId, value.transactionId)
        XCTAssertEqual(edited.transactions[0].evidenceText, value.evidenceText)
        XCTAssertEqual(edited.transactions[0].extractionConfidence, value.extractionConfidence)
        XCTAssertEqual(edited.transactions[0].observedMonth, "2026-01")
        XCTAssertFalse(edited.transactions[0].accountLabel.contains("123456789"))
        XCTAssertEqual(edited.reviewItems.first { $0.issueType == .unclearCategory }?.status, .pending)
        XCTAssertEqual(edited.reviewItems.filter { $0.status == .pending && $0.issueType == .missingField }.count, 0)
        XCTAssertEqual(edited.reviewItems.first { $0.issueType == .lowConfidence }?.status, .pending)
    }

    func testConfirmationResolvesOnlySelectedIssueAndSurvivesUnrelatedEdit() throws {
        var value = tx; value.transactionDate = ""; value.extractionConfidence = 0.4
        let issues = Validator.validate([value]).reviewItems
        let low = issues.first { $0.issueType == .lowConfidence }!
        let confirmed = try CorrectionApplier.apply(review: low, action: .confirm, transactions: [value], reviewItems: issues)
        XCTAssertEqual(confirmed.transactions[0].validationStatus, .needsReview)
        let edited = try CorrectionApplier.apply(review: low,
            action: .edit(TransactionEdit(date: "2026-01-01", merchant: value.merchantNormalized, amount: value.amount, type: value.transactionType, account: value.accountLabel)),
            transactions: confirmed.transactions, reviewItems: confirmed.reviewItems)
        XCTAssertFalse(edited.reviewItems.contains { $0.status == .pending })
        XCTAssertEqual(edited.transactions[0].extractionConfidence, 0.4)
    }

    func testDuplicateChecksExistingRowsAndKeepsPendingUntilDecision() throws {
        var a = tx; a.transactionDate = "2026-01-01"
        var b = a; b.transactionId = "new-row"; b.sourceDocumentId = "another-source"
        let validated = Validator.validate([b], existingTransactions: [a])
        let duplicate = try XCTUnwrap(validated.reviewItems.first { $0.issueType == .duplicateRisk })
        let pending = try CorrectionApplier.apply(review: duplicate, action: .duplicate(.needsReview), transactions: [b], reviewItems: [duplicate])
        XCTAssertEqual(pending.reviewItems[0].status, .pending)
        let rejected = try CorrectionApplier.apply(review: duplicate, action: .duplicate(.rejected), transactions: [b], reviewItems: [duplicate])
        XCTAssertEqual(rejected.transactions[0].validationStatus, .rejected)
        XCTAssertTrue(SummaryGenerator.generateCashFlowSummaries(rejected.transactions).isEmpty)
        XCTAssertEqual(a.validationStatus, .needsReview) // Existing input was not mutated.
    }

    func testLatestMerchantCorrectionWinsRegardlessOfFetchOrder() {
        let earlier = Date(timeIntervalSince1970: 100)
        let a = CorrectionRecord(correctionId: "a", targetType: .merchantRule, targetId: tx.merchantNormalized,
            fieldName: "category", oldValue: "", newValue: "shopping", applyFuture: true, createdAt: earlier)
        var b = a; b.correctionId = "b"; b.newValue = "dining"; b.createdAt = earlier.addingTimeInterval(10)
        XCTAssertEqual(Categorizer.categorize([tx], corrections: [b, a]).transactions[0].category, .dining)
        XCTAssertEqual(Categorizer.categorize([tx], corrections: [a, b]).transactions[0].category, .dining)
        let first = CorrectionApplier.applyCategoryCorrection(transactionId: tx.transactionId, newCategory: .dining,
            remember: true, transactions: [tx], reviewItems: [], now: earlier)
        let later = CorrectionApplier.applyCategoryCorrection(transactionId: tx.transactionId, newCategory: .dining,
            remember: true, transactions: [tx], reviewItems: [], now: earlier.addingTimeInterval(100))
        XCTAssertNotEqual(first.corrections.last?.correctionId, later.corrections.last?.correctionId)
    }

    func testProvisionalTotalsIncludeUsablePendingAndExcludeInvalidAndRejected() {
        var pending = tx; pending.transactionDate = "2026-01-01"; pending.observedMonth = "2026-01"
        var rejected = pending; rejected.transactionId = "rejected"; rejected.validationStatus = .rejected
        var invalid = pending; invalid.transactionId = "invalid"; invalid.transactionDate = ""
        let totals = SummaryGenerator.generateCashFlowSummaries([pending, rejected, invalid])
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].transactionCount, 1)
        XCTAssertEqual(totals[0].unresolvedCount, 1)
        XCTAssertEqual(totals[0].completenessStatus, .partial)
        XCTAssertEqual(totals[0].spendingTotal, abs(pending.amount))
    }

    func testRepeatedPipelineProducesNoNewReviewsForExistingRows() async {
        let extraction = ScreenshotExtractionResult(sourceDocumentId: "external", transactions: [
            ExtractedTransactionCandidate(rowIndex: 0, dateText: "2026-01-01", merchantText: "Novel shop", amountText: "12.00", confidence: 0.4, evidenceText: "evidence")
        ])
        let first = await ProcessingPipeline.process(PipelineInput(sourceDocumentId: "local", fileName: "test", extraction: extraction))
        let second = await ProcessingPipeline.process(PipelineInput(sourceDocumentId: "local", fileName: "test", extraction: extraction, existingTransactions: first.transactions))
        XCTAssertTrue(second.transactions.isEmpty)
        XCTAssertTrue(second.reviewItems.isEmpty)
        XCTAssertEqual(first.transactions[0].sourceDocumentId, "local")
    }
}

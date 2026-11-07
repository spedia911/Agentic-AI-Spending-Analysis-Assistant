import XCTest
@testable import SpendingDomain

final class DomainTests: XCTestCase {
    func testNormalizeAmountAndDate() {
        XCTAssertEqual(Normalizer.normalizeAmountText("$12.34"), 12.34)
        XCTAssertEqual(Normalizer.normalizeAmountText("(12.34)"), -12.34)
        XCTAssertEqual(Normalizer.normalizeDateText("03/05/2026", observedMonthHint: "2026-03"), "2026-03-05")
        XCTAssertEqual(Normalizer.normalizeDateText("2026-11-07", observedMonthHint: nil), "2026-11-07")
    }

    func testMaskAccountLabelAndPrivacy() {
        XCTAssertEqual(PrivacyRedactor.maskAccountLabel("Chase 123456789"), "Chase *****6789")
        let masked = PrivacyRedactor.maskSensitiveText("token=abc123 api_key=secret email me@example.com 12345678")
        XCTAssertFalse(masked.contains("me@example.com"))
        XCTAssertTrue(masked.contains("[email]") || masked.contains("[secret]") || masked.contains("[number]"))
    }

    func testHeuristicParserFindsTransaction() {
        let lines = [
            OCRLine(text: "03/01 Starbucks Coffee $5.65"),
            OCRLine(text: "Checking balance: $1,200.00")
        ]
        let result = HeuristicScreenshotParser.parse(
            sourceDocumentId: "src1",
            fileName: "card.png",
            lines: lines
        )
        XCTAssertFalse(result.transactions.isEmpty)
        XCTAssertFalse(result.assetSnapshots.isEmpty)
        XCTAssertEqual(result.sourceDocumentId, "src1")
    }

    func testCategorizerUsesRulesAndMemory() {
        let tx = TransactionRecord(
            transactionId: "t1",
            sourceDocumentId: "s1",
            observedMonth: "2026-11",
            transactionDate: "2026-11-01",
            merchantRaw: "Trader Joe's",
            merchantNormalized: "Trader Joe's",
            amount: -20,
            transactionType: .expense,
            accountLabel: "Card *1111",
            extractionConfidence: 0.9,
            validationStatus: .valid,
            reviewStatus: .none,
            evidenceText: "Trader Joe's"
        )
        let result = Categorizer.categorize([tx])
        XCTAssertEqual(result.transactions.first?.category, .groceries)

        let correction = CorrectionRecord(
            correctionId: "c1",
            targetType: .merchantRule,
            targetId: "Blue Bottle",
            fieldName: "category",
            oldValue: "miscellaneous",
            newValue: "dining",
            applyFuture: true
        )
        let novel = TransactionRecord(
            transactionId: "t2",
            sourceDocumentId: "s1",
            observedMonth: "2026-11",
            transactionDate: "2026-11-02",
            merchantRaw: "Blue Bottle",
            merchantNormalized: "Blue Bottle",
            amount: -7,
            transactionType: .expense,
            accountLabel: "Card *1111",
            extractionConfidence: 0.9,
            validationStatus: .valid,
            reviewStatus: .none,
            evidenceText: "Blue Bottle"
        )
        let remembered = Categorizer.categorize([novel], corrections: [correction])
        XCTAssertEqual(remembered.transactions.first?.category, .dining)
        XCTAssertEqual(remembered.transactions.first?.categoryConfidence, 0.99)
    }

    func testValidationFlagsMissingDate() {
        let tx = TransactionRecord(
            transactionId: "t1",
            sourceDocumentId: "s1",
            observedMonth: "unknown",
            transactionDate: "",
            merchantRaw: "X",
            merchantNormalized: "X",
            amount: -10,
            transactionType: .expense,
            accountLabel: "A",
            extractionConfidence: 0.9,
            validationStatus: .valid,
            reviewStatus: .none,
            evidenceText: "X"
        )
        let result = Validator.validate([tx])
        XCTAssertEqual(result.transactions.first?.validationStatus, .needsReview)
        XCTAssertFalse(result.reviewItems.isEmpty)
    }

    func testSummariesAndCashFlow() {
        let seed = DemoSeed.make()
        let summaries = SummaryGenerator.generate(transactions: seed.transactions, assetSnapshots: seed.assets)
        XCTAssertFalse(summaries.monthlySummaries.isEmpty)
        XCTAssertFalse(summaries.cashFlowSummaries.isEmpty)
        XCTAssertFalse(summaries.assetTrends.isEmpty)
        let anomalies = AnomalyDetector.generate(
            transactions: seed.transactions,
            monthlySummaries: summaries.monthlySummaries,
            assetTrends: summaries.assetTrends
        )
        _ = anomalies
        let insights = DashboardInsightBuilder.build(DashboardSnapshot(
            sourceDocuments: seed.sources,
            reviewItems: seed.reviews,
            anomalies: anomalies,
            cashFlowSummaries: summaries.cashFlowSummaries,
            assetTrends: summaries.assetTrends
        ))
        XCTAssertFalse(insights.isEmpty)
    }

    func testAIJSONImportParses() throws {
        let json = """
        {
          "source_document_id": "abc",
          "screenshot_kind": "credit_card",
          "raw_text": "line",
          "extraction_confidence": 0.8,
          "transactions": [
            {
              "row_index": 0,
              "date_text": "2026-11-01",
              "merchant_text": "Safeway",
              "amount_text": "32.10",
              "account_source_text": "Chase 12345678",
              "transaction_type_hint": "expense",
              "confidence": 0.9,
              "evidence_text": "Safeway 32.10",
              "evidence_region": null
            }
          ],
          "asset_snapshots": [],
          "warnings": []
        }
        """
        let parsed = try ExtractionJSONParser.parse(json)
        XCTAssertEqual(parsed.transactions.count, 1)
        let normalized = Normalizer.normalize(
            extraction: parsed,
            context: NormalizeContext(sourceDocumentId: "abc", observedMonthHint: "2026-11")
        )
        XCTAssertEqual(normalized.transactions.first?.merchantNormalized, "Safeway")
        XCTAssertTrue(normalized.transactions.first?.accountLabel.contains("*") == true)
    }

    func testPipelineIdempotent() async {
        let extraction = HeuristicScreenshotParser.parse(
            sourceDocumentId: "src",
            fileName: "a.png",
            lines: [OCRLine(text: "11/01 Safeway $12.00")]
        )
        let first = await ProcessingPipeline.process(PipelineInput(
            sourceDocumentId: "src",
            fileName: "a.png",
            extraction: extraction
        ))
        let second = await ProcessingPipeline.process(PipelineInput(
            sourceDocumentId: "src",
            fileName: "a.png",
            extraction: extraction,
            existingTransactions: first.transactions
        ))
        XCTAssertFalse(first.transactions.isEmpty)
        XCTAssertTrue(second.transactions.isEmpty)
    }

    func testBackupExportCSV() {
        let seed = DemoSeed.make()
        let csv = BackupExporter.transactionsCSV(seed.transactions)
        XCTAssertTrue(csv.contains("transaction_id"))
        XCTAssertTrue(csv.contains("Trader Joe's") || csv.contains("\"Trader Joe's\""))
    }

    func testCorrectionRemember() {
        let seed = DemoSeed.make()
        let applied = CorrectionApplier.applyCategoryCorrection(
            transactionId: "txn_demo_2",
            newCategory: .dining,
            remember: true,
            transactions: seed.transactions,
            reviewItems: seed.reviews
        )
        XCTAssertEqual(applied.transactions.first(where: { $0.transactionId == "txn_demo_2" })?.category, .dining)
        XCTAssertTrue(applied.corrections.contains(where: { $0.targetType == .merchantRule }))
        XCTAssertEqual(applied.reviewItems.first?.status, .resolved)
    }
}

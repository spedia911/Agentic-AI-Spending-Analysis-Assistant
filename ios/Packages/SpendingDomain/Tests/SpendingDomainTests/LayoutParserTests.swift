import XCTest
@testable import SpendingDomain

final class LayoutParserTests: XCTestCase {
    private func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 0.5, confidence: Double = 1) -> OCRLine {
        OCRLine(text: text, boundingBox: EvidenceRegion(x: x, y: y, width: width, height: 0.018), confidence: confidence)
    }
    func testEmptyStoreCanRebuildSummariesAfterSourceSettingsChange() {
        let rebuilt = ProcessingPipeline.rebuildSummaries(transactions: [], assets: [])
        XCTAssertTrue(rebuilt.summaries.monthlySummaries.isEmpty)
        XCTAssertTrue(rebuilt.anomalies.isEmpty)
    }
    func testAppleCardMultilineRowsKeepDatesAmountsAndCard() {
        let lines = [line("March 2026", 0.1, 0.1),
            line("CORNER MARKET", 0.22, 0.22), line("$321.45", 0.75, 0.22, 0.15),
            line("Apple Pay", 0.22, 0.245), line("2%", 0.8, 0.245, 0.06), line("03/15/26", 0.22, 0.27),
            line("CITY CAFE", 0.22, 0.34), line("$42.10", 0.75, 0.34, 0.15),
            line("Example City, CA", 0.22, 0.365), line("03/14/26", 0.22, 0.39)]
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "test", fileName: "image", lines: lines)
        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions.map(\.dateText), ["2026-03-15", "2026-03-14"])
        XCTAssertEqual(result.transactions.map(\.amountText), ["$321.45", "$42.10"])
        XCTAssertEqual(result.transactions.map(\.merchantText), ["CORNER MARKET", "CITY CAFE"])
        XCTAssertEqual(result.transactions[0].accountSourceText, "Apple Card")
        XCTAssertNotNil(result.transactions[0].evidenceRegion)
    }
    func testCapitalOneDateHeadersRepeatAndScreenTotalIsExcluded() {
        let lines = [line("Transactions", 0.4, 0.09), line("March 2026", 0.04, 0.36),
            line("Total", 0.04, 0.43), line("$12,000.00", 0.55, 0.43),
            line("March 15", 0.04, 0.5), line("OFFICE SHOP", 0.04, 0.54), line("$1,234.56", 0.75, 0.54, 0.2),
            line("Merchandise • 2x miles", 0.04, 0.57),
            line("SECOND SHOP", 0.04, 0.64), line("$23.45", 0.75, 0.64, 0.2),
            line("March 12", 0.04, 0.72), line("STREAMING", 0.04, 0.76), line("$19.99", 0.75, 0.76, 0.2)]
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "test", fileName: "image", lines: lines,
            options: ScreenshotParseOptions(cardName: "Capital One Venture X"))
        XCTAssertEqual(result.transactions.count, 3)
        XCTAssertEqual(result.transactions.map(\.dateText), ["2026-03-15", "2026-03-15", "2026-03-12"])
        XCTAssertEqual(result.transactions[0].amountText, "$1,234.56")
        XCTAssertEqual(result.transactions[0].accountSourceText, "Capital One Venture X")
        XCTAssertFalse(result.transactions.contains { $0.amountText == "$12,000.00" })
    }
    func testMissingYearRemainsUncertainUntilMonthSupplied() {
        let lines = [line("Transactions", 0.4, 0.09), line("March 15", 0.04, 0.5),
            line("NOVEL SHOP", 0.04, 0.55), line("$12.34", 0.75, 0.55, 0.2)]
        let unknown = HeuristicScreenshotParser.parse(sourceDocumentId: "test", fileName: "a", lines: lines)
        XCTAssertEqual(unknown.transactions.count, 1)
        XCTAssertEqual(unknown.transactions[0].dateText, "March 15")
        XCTAssertFalse(unknown.warnings.isEmpty)
        let supplied = HeuristicScreenshotParser.parse(sourceDocumentId: "test", fileName: "a", lines: lines,
            options: ScreenshotParseOptions(layout: .capitalOne, observedMonthHint: "2025-03"))
        XCTAssertEqual(supplied.transactions[0].dateText, "2025-03-15")
    }
    func testStickyBlurredRowsAboveHeaderAreNotImported() {
        let lines = [line("OLD ROW", 0.22, 0.07), line("$88.00", 0.75, 0.07, 0.2),
            line("March 2026", 0.3, 0.1), line("NEW ROW", 0.22, 0.2), line("$7.50", 0.75, 0.2, 0.2),
            line("03/10/26", 0.22, 0.25), line("Apple Pay", 0.22, 0.23)]
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "test", fileName: "a", lines: lines)
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions[0].merchantText, "NEW ROW")
    }
    func testGenericAmountDoesNotConsumeNumericMerchantOrDate() {
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "test", fileName: "a", lines: [
            OCRLine(text: "2026-03-12 SHOP 1234 $12345.67")])
        XCTAssertEqual(result.transactions[0].merchantText, "SHOP 1234")
        XCTAssertEqual(result.transactions[0].amountText, "$12345.67")
        XCTAssertEqual(result.transactions[0].dateText, "2026-03-12")
    }
    func testLowConfidenceFragmentsAndRewardBadgesAreIgnored() {
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "test", fileName: "a", lines: [
            line("March 2026", 0.1, 0.1), line("BLURRED", 0.2, 0.2, confidence: 0.1),
            line("$20.00", 0.75, 0.2, 0.2, confidence: 0.1), line("2%", 0.8, 0.3, 0.1)])
        XCTAssertTrue(result.transactions.isEmpty)
    }
}

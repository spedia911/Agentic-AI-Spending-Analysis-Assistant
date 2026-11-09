import XCTest
@testable import SpendingDomain

final class MonthlyTrendTests: XCTestCase {
    func testRegressionUsesCalendarIntervalsAndDoesNotFillMissingMonths() throws {
        let series = [MonthlyPoint(month: "2025-11", value: 100), MonthlyPoint(month: "2026-01", value: 140), MonthlyPoint(month: "2026-02", value: 160)]
        let projected = try XCTUnwrap(MonthlyTrend.regression(series, futureMonths: 3).last)
        XCTAssertEqual(projected.month, "2026-05")
        XCTAssertEqual(projected.value, 220, accuracy: 0.001)
        XCTAssertTrue(MonthlyTrend.regression(Array(series.prefix(2)), futureMonths: 3).isEmpty)
    }

    func testYearOverYearUsesSameMonthAndHandlesZeroBaseline() throws {
        let series = [MonthlyPoint(month: "2025-02", value: 0), MonthlyPoint(month: "2025-12", value: -200),
                      MonthlyPoint(month: "2026-02", value: 100), MonthlyPoint(month: "2026-12", value: -100)]
        XCTAssertNil(MonthlyTrend.yearOverYear(series, month: "2025-12"))
        let increase = try XCTUnwrap(MonthlyTrend.yearOverYear(series, month: "2026-12"))
        XCTAssertEqual(increase.amount, 100)
        XCTAssertEqual(increase.fraction, 0.5)
        XCTAssertNil(MonthlyTrend.yearOverYear(series, month: "2026-02")?.fraction)
    }

    func testBankScreenshotRecognizesIncomeSeparatelyFromTransfers() {
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "bank", fileName: "synthetic.png", lines: [
            OCRLine(text: "01/03/2026 Payroll Credit +$1,200.00"),
            OCRLine(text: "01/04/2026 Zelle Transfer +$50.00"),
            OCRLine(text: "01/05/2026 Utility Payment -$60.00"),
            OCRLine(text: "01/06/2026 Unknown credit +$25.00"),
            OCRLine(text: "01/07/2026 Utility Autopay -$75.00"),
            OCRLine(text: "01/08/2026 Capital One Online PMT -$80.00")
        ], options: ScreenshotParseOptions(layout: .bankActivity))
        XCTAssertEqual(result.screenshotKind, .bankActivity)
        XCTAssertEqual(result.transactions.map(\.transactionTypeHint), [.income, .transfer, .expense, .unknown, .expense, .payment])
    }
}

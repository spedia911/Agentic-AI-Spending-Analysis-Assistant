import XCTest
@testable import SpendingDomain

final class BankImportTests: XCTestCase {
    func testStatementReconcilesPhysicalRowsAndSkipsPeriodAndBalanceLines() throws {
        let rows = [
            "Dec 28 - Jan 5, 2026", "Simply Checking - *1234", "DATE DESCRIPTION CATEGORY AMOUNT BALANCE",
            "Dec 28 Opening Balance $100.00", "Dec 30 Withdrawal from SAMPLE POWER - $20.00 $80.00",
            "Dec 28 - Jan 5, 2026", "DATE DESCRIPTION CATEGORY AMOUNT BALANCE",
            "+ $50.00 $130.00 | Jan 2 Deposit from EXAMPLE EMPLOYER PAYROLL",
            "$130.00 | Jan 5 Closing Balance"
        ]
        let result = try BankStatementParser.parse(sourceId: "synthetic", rows: rows)
        XCTAssertEqual(result.transactions.map(\.dateText), ["2025-12-30", "2026-01-02"])
        XCTAssertEqual(result.transactions.map(\.transactionTypeHint), [.expense, .income])
        XCTAssertEqual(result.transactions.last?.merchantText, "EXAMPLE EMPLOYER")
        XCTAssertEqual(result.assetSnapshots.first?.balanceText, "130.00")
        XCTAssertThrowsError(try BankStatementParser.parse(sourceId: "synthetic",
            rows: rows.map { $0.replacingOccurrences(of: "$80.00", with: "$81.00") }))
    }

    func testFilenameFillsMissingStatementDateAndAccountWithoutOverridingPrintedDetails() throws {
        let table = ["DATE DESCRIPTION CATEGORY AMOUNT BALANCE", "Oct 1 Opening Balance $100.00",
                     "Oct 2 Withdrawal from Example Store - $20.00 $80.00", "Oct 31 Closing Balance $80.00"]
        let fallback = try BankStatementParser.parse(sourceId: "synthetic", rows: table,
            fileName: "20261031-Sample Checking.pdf")
        XCTAssertEqual(fallback.transactions.first?.dateText, "2026-10-02")
        XCTAssertEqual(fallback.transactions.first?.accountSourceText, "Sample Checking")
        let printed = try BankStatementParser.parse(sourceId: "synthetic",
            rows: ["Oct 1 - Oct 31, 2025", "Example Savings - *1234"] + table, fileName: "20261031-Sample Checking.pdf")
        XCTAssertEqual(printed.transactions.first?.dateText, "2025-10-02")
        XCTAssertEqual(printed.transactions.first?.accountSourceText, "Example Savings *1234")
    }

    func testBankScreenUsesMerchantLineAndIgnoresRunningBalance() {
        func line(_ text: String, _ x: Double, _ y: Double, _ height: Double = 0.02) -> OCRLine {
            OCRLine(text: text, boundingBox: EvidenceRegion(x: x, y: y, width: 0.15, height: height))
        }
        let lines = [
            line("Transactions", 0.4, 0.08), line("Oct 2", 0.04, 0.21),
            line("Example employer", 0.04, 0.25), line("+$90.00", 0.73, 0.249),
            line("Direct Deposit", 0.04, 0.277, 0.013), line("$190.00", 0.73, 0.277, 0.013),
            line("Sample brokerage", 0.04, 0.35), line("$20.00", 0.75, 0.349),
            line("Transfer", 0.04, 0.377, 0.013), line("$170.00", 0.73, 0.377, 0.013),
            line("Sep 30", 0.04, 0.41), line("Utility company", 0.04, 0.45), line("$30.00", 0.75, 0.45),
            line("Transfer", 0.04, 0.477, 0.013), line("$200.00", 0.75, 0.477, 0.013),
            line("Obscured merchant", 0.04, 0.92), line("$900.00", 0.75, 0.92),
            line("Home", 0.1, 0.95), line("Offers", 0.72, 0.95)
        ]
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "synthetic", fileName: "image.png", lines: lines,
            options: .init(observedMonthHint: "2026-10"))
        XCTAssertEqual(result.screenshotKind, .bankActivity)
        XCTAssertEqual(result.transactions.map(\.amountText), ["+$90.00", "-$20.00", "-$30.00"])
        XCTAssertEqual(result.transactions.map(\.transactionTypeHint), [.income, .transfer, .expense])
        XCTAssertEqual(result.transactions.last?.dateText, "2026-09-30")
    }
}

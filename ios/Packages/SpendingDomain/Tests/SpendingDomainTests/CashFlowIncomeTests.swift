import XCTest
@testable import SpendingDomain

final class CashFlowIncomeTests: XCTestCase {
    func testCategoryIncomeIsNormalizedAndCounted() throws {
        let original = try XCTUnwrap(DemoSeed.make().transactions.first)
        func make(_ id: String, amount: Double, type: TransactionType, category: SpendingCategory) -> TransactionRecord {
            var row = original
            row.transactionId = id
            row.amount = amount
            row.transactionType = type
            row.category = category
            row.validationStatus = .valid
            row.reviewStatus = .resolved
            row.transactionDate = "2026-04-10"
            row.observedMonth = "2026-04"
            _ = TransactionClassification.normalize(&row, prefer: .category)
            return row
        }
        let rows = [
            make("pay1", amount: 2000, type: .expense, category: .income),
            make("pay2", amount: 500, type: .expense, category: .income),
            make("coffee", amount: -6, type: .expense, category: .dining)
        ]
        XCTAssertEqual(rows[0].transactionType, .income)
        XCTAssertEqual(rows[0].category, .income)
        let cash = SummaryGenerator.generateCashFlowSummaries(rows)
        let april = try XCTUnwrap(cash.first { $0.month == "2026-04" })
        XCTAssertEqual(april.incomeTotal, 2500)
        XCTAssertEqual(april.spendingTotal, 6)
        XCTAssertEqual(april.netCashFlow, 2494)
    }
}

import XCTest
@testable import SpendingDomain

final class TransactionClassificationTests: XCTestCase {
    func testIncomeTypeLocksIncomeCategory() {
        let normalized = TransactionClassification.normalize(type: .income, category: .dining, prefer: .type)
        XCTAssertEqual(normalized.type, .income)
        XCTAssertEqual(normalized.category, .income)
    }

    func testIncomeCategoryForcesIncomeType() {
        let normalized = TransactionClassification.normalize(type: .expense, category: .income, prefer: .category)
        XCTAssertEqual(normalized.type, .income)
        XCTAssertEqual(normalized.category, .income)
    }

    func testSpendingCategoryOnIncomeSwitchesToExpenseWhenPreferringCategory() {
        let normalized = TransactionClassification.normalize(type: .income, category: .groceries, prefer: .category)
        XCTAssertEqual(normalized.type, .expense)
        XCTAssertEqual(normalized.category, .groceries)
    }

    func testTransferAndFeeLocks() {
        let transfer = TransactionClassification.normalize(type: .transfer, category: .shopping, prefer: .type)
        XCTAssertEqual(transfer.type, .transfer)
        XCTAssertEqual(transfer.category, .transfer)
        let fee = TransactionClassification.normalize(type: .fee, category: .dining, prefer: .type)
        XCTAssertEqual(fee.type, .fee)
        XCTAssertEqual(fee.category, .fees)
    }

    func testCashFlowCountsSyncedIncomeRows() throws {
        let original = try XCTUnwrap(DemoSeed.make().transactions.first)
        func make(_ id: String, amount: Double) -> TransactionRecord {
            var row = original
            row.transactionId = id
            row.amount = amount
            row.transactionType = .expense
            row.category = .income
            row.validationStatus = .valid
            row.reviewStatus = .resolved
            row.transactionDate = "2026-04-10"
            row.observedMonth = "2026-04"
            _ = TransactionClassification.normalize(&row, prefer: .category)
            return row
        }
        let rows = [make("pay1", amount: 2000), make("pay2", amount: 500)]
        XCTAssertTrue(rows.allSatisfy { $0.transactionType == .income && $0.category == .income })
        let april = try XCTUnwrap(SummaryGenerator.generateCashFlowSummaries(rows).first { $0.month == "2026-04" })
        XCTAssertEqual(april.incomeTotal, 2500)
        XCTAssertEqual(april.spendingTotal, 0)
    }
}

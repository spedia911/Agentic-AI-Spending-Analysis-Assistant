import XCTest
@testable import SpendingDomain

final class AssetForwardFillTests: XCTestCase {
    func testCarriesRecentBalanceIntoNextMonthOnly() {
        let march = AssetSnapshotRecord(
            assetSnapshotId: "a1",
            sourceDocumentId: "s",
            observedMonth: "2026-03",
            observedDate: "2026-03-20",
            accountLabel: "Roth IRA", accountId: "00000000-0000-0000-0000-000000000001", currencyCode: "USD",
            balance: 10_000,
            balanceType: .rothIra,
            confidence: 1,
            evidenceText: "manual"
        )
        let filled = AssetForwardFill.monthlySeries(snapshots: [march], throughMonth: "2026-05", maxAgeDays: 31)
        XCTAssertEqual(filled.map(\.month), ["2026-03", "2026-04"])
        XCTAssertEqual(filled[0].balance, 10_000)
        XCTAssertFalse(filled[0].isForwardFilled)
        XCTAssertTrue(filled[1].isForwardFilled)
        XCTAssertEqual(filled[1].sourceDate, "2026-03-20")
        XCTAssertFalse(filled.contains { $0.month == "2026-05" })
    }

    func testBalanceTypeAliasesDecode() throws {
        let data = Data(#""roth""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BalanceType.self, from: data), .rothIra)
        let stock = Data(#""stock_account""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BalanceType.self, from: stock), .brokerage)
        let unknown = Data(#""mystery_account""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BalanceType.self, from: unknown), .unknown)
    }
}

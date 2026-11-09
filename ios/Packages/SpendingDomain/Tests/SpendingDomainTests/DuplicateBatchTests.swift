import XCTest
@testable import SpendingDomain

final class DuplicateBatchTests: XCTestCase {
    func testOnlyOneToOneExactCompatibleRowsMatch() throws {
        let original = try XCTUnwrap(DemoSeed.make().transactions.first)
        func make(_ id: String, _ source: String, _ amount: Double, _ day: String = "2026-01-01",
                  origin: TransactionOrigin = .bank) -> TransactionRecord {
            var row = original
            row.transactionId = id; row.sourceDocumentId = source; row.amount = amount; row.transactionDate = day; row.origin = origin
            return row
        }
        let rows = [
            make("keep", "a", -20), make("remove", "b", -20),
            make("repeat 1", "a", -30), make("repeat 2", "a", -30), make("ambiguous", "b", -30),
            make("different day 1", "a", -40), make("different day 2", "b", -40, "2026-01-02"),
            make("bank payment", "a", -50), make("card payment", "b", -50, origin: .card),
            make("other source", "c", -20)
        ]
        let pairs = DuplicateBatch.matches(keeping: "a", removing: "b", transactions: rows)
        XCTAssertEqual(pairs.map(\.id), ["remove"])
        XCTAssertEqual(pairs.map(\.keep.id), ["keep"])
        XCTAssertTrue(DuplicateBatch.matches(keeping: "a", removing: "a", transactions: rows).isEmpty)

        let january = DuplicateBatch.matches(
            keeping: "a",
            removing: "b",
            transactions: rows,
            filter: DuplicateMatchFilter(month: "2026-01")
        )
        XCTAssertEqual(january.map(\.id), ["remove"])

        let february = DuplicateBatch.matches(
            keeping: "a",
            removing: "b",
            transactions: rows,
            filter: DuplicateMatchFilter(month: "2026-02")
        )
        XCTAssertTrue(february.isEmpty)

        let suggestions = DuplicateBatch.suggestedPairs(transactions: rows)
        let ab = try XCTUnwrap(suggestions.first {
            Set([$0.keepSourceId, $0.removeSourceId]) == Set(["a", "b"])
        })
        XCTAssertEqual(ab.matchCount, 1)
        // Prefer keeping the source that already holds more rows.
        XCTAssertEqual(ab.keepSourceId, "a")
        XCTAssertEqual(ab.removeSourceId, "b")
        // Undirected: a→b and b→a are not both listed.
        XCTAssertEqual(suggestions.filter {
            Set([$0.keepSourceId, $0.removeSourceId]) == Set(["a", "b"])
        }.count, 1)
    }

    func testSameSourceDuplicateClassification() throws {
        let original = try XCTUnwrap(DemoSeed.make().transactions.first)
        func make(_ id: String, _ source: String, day: String) -> TransactionRecord {
            var row = original
            row.transactionId = id
            row.sourceDocumentId = source
            row.merchantNormalized = "Coffee Shop"
            row.amount = -4.5
            row.transactionDate = day
            return row
        }
        let sameSourceRows = [make("a1", "src", day: "2026-03-01"), make("a2", "src", day: "2026-03-02")]
        XCTAssertTrue(DuplicateBatch.isSameSourceDuplicate(relatedIds: ["a1", "a2"], transactions: sameSourceRows))

        let cross = [make("b1", "left", day: "2026-03-01"), make("b2", "right", day: "2026-03-01")]
        XCTAssertFalse(DuplicateBatch.isSameSourceDuplicate(relatedIds: ["b1", "b2"], transactions: cross))

        let anomaly = AnomalyRecord(
            anomalyId: "anomaly_same",
            anomalyType: .duplicateCharge,
            severity: .medium,
            month: "2026-03",
            relatedRecordIds: ["a1", "a2"],
            summary: "Possible duplicate",
            suggestedAction: "Compare"
        )
        let groups = DuplicateChargeGroup.from(anomalies: [anomaly], transactions: sameSourceRows)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].sameSource)
        XCTAssertEqual(groups[0].dates, ["2026-03-01", "2026-03-02"])
        XCTAssertEqual(groups[0].sourceDocumentId, "src")
    }
}

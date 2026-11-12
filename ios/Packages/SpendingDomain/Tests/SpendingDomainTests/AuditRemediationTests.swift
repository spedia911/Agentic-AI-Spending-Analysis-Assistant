import XCTest
@testable import SpendingDomain

final class AuditRemediationTests: XCTestCase {
    let account = AccountRecord(accountId: "00000000-0000-0000-0000-000000000001", label: "Synthetic", currencyCode: "USD")
    func row(_ id: String = "t", currency: String? = "USD") -> TransactionRecord {
        TransactionRecord(transactionId: id, sourceDocumentId: "s", observedMonth: "2026-01", transactionDate: "2026-01-15",
            merchantRaw: "Rent", merchantNormalized: "Rent", amount: -100, transactionType: .payment,
            accountLabel: "Synthetic", accountId: currency == nil ? nil : account.id, currencyCode: currency,
            category: .rent, extractionConfidence: 1, validationStatus: .valid, reviewStatus: .resolved, evidenceText: "Rent")
    }
    func payload(_ rows: [TransactionRecord] = [], assets: [AssetSnapshotRecord] = [], reviews: [ReviewItemRecord] = []) -> BackupPayload {
        BackupPayload(sourceDocuments: [.init(sourceDocumentId: "s", sourceType: .manual, fileName: "Synthetic", mimeType: "text/plain")],
            transactions: rows, assetSnapshots: assets, reviewItems: reviews, corrections: [], monthlySummaries: [], quarterlySummaries: [], cashFlowSummaries: [], assetTrends: [], anomalies: [])
    }
    func balance(_ id: String, date: String, value: Double) -> AssetSnapshotRecord {
        AssetSnapshotRecord(assetSnapshotId: id, sourceDocumentId: "s", observedMonth: String(date.prefix(7)), observedDate: date,
            accountLabel: account.label, accountId: account.id, currencyCode: account.currencyCode, balance: value, balanceType: .checking, confidence: 1, evidenceText: "Synthetic")
    }
    func testCurrenciesAndUnknownAreSeparated() throws {
        let result = SummaryGenerator.generateCashFlowSummaries([row(), row("krw", currency: "KRW"), row("unknown", currency: nil)])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.compactMap(\.currencyCode)), ["USD", "KRW"])
        XCTAssertTrue(result.allSatisfy { $0.spendingTotal == 100 && $0.transactionCount == 1 })
        XCTAssertFalse(Eligibility.transaction(row(currency: nil)).local)
    }
    func testGoldenSpendingAndEligibilityTransitions() {
        var rent = row()
        XCTAssertEqual(SpendingClassification(rent).grossSpending, 100)
        rent.reviewStatus = .pending
        XCTAssertTrue(Eligibility.transaction(rent).local); XCTAssertFalse(Eligibility.transaction(rent).desktop)
        rent.reviewStatus = .resolved; rent.validationStatus = .rejected
        XCTAssertFalse(Eligibility.transaction(rent).local)
        var card = row("card"); card.merchantRaw = "Credit card payment"
        XCTAssertEqual(SpendingClassification(card).cardSettlement, 100)
        XCTAssertEqual(SpendingClassification(card).grossSpending, 0)
        var refund = row("refund"); refund.transactionType = .refund
        XCTAssertEqual(SpendingClassification(refund).netSpending, -100)
        var transfer = row("transfer"); transfer.category = .transfer; transfer.transactionType = .transfer
        XCTAssertEqual(SpendingClassification(transfer).internalTransfer, 100)
        XCTAssertEqual(SpendingClassification(transfer).grossSpending, 0)
    }
    func testBalanceReviewsConflictsAndMissingMonths() throws {
        let a = balance("a", date: "2026-01-31", value: 500), b = balance("b", date: "2026-03-31", value: 0)
        let pending = ReviewItemRecord(reviewItemId: "r", targetType: .assetSnapshot, targetId: b.id, issueType: .lowConfidence, severity: .high, question: "Check")
        XCTAssertFalse(Eligibility.asset(b, reviews: [pending]).desktop)
        var conflict = b; conflict.assetSnapshotId = "c"; conflict.balance = 10
        XCTAssertFalse(Eligibility.asset(b, peers: [b, conflict]).local)
        let trends = SummaryGenerator.generateAssetTrends([a,b], transactions: [row()])
        XCTAssertNil(trends.last?.priorMonthBalance)
        XCTAssertEqual(trends.last?.previousObservationDate, "2026-01-31")
        XCTAssertEqual(trends.last?.previousObservationChange, -500)
        XCTAssertEqual(trends.last?.maintainabilityFlag, .unknown)
        XCTAssertEqual(trends.first?.relatedSpendingTotal, 100)
        var other = row(); other.accountId = UUID().uuidString
        XCTAssertNil(SummaryGenerator.generateAssetTrends([a], transactions: [other]).first?.relatedSpendingTotal)
        XCTAssertNil(trends.last?.monthlyChange)
    }
    func testSnapshotRoundTripIntegrityAndRejectionDeletion() throws {
        let p = payload([row()])
        let backup = try PortableBackup(records: p, accounts: [account], datasetId: UUID().uuidString, attachments: [.init(sourceId: "s", status: "omitted")])
        let decoded = try PortableBackup.decoder().decode(PortableBackup.self, from: backup.encoded())
        XCTAssertEqual(try decoded.validatedRecords().transactions.first?.id, "t")
        XCTAssertTrue(decoded.eligibility.transactions["t"]!.desktop)
        var rejected = row(); rejected.validationStatus = .rejected
        let next = try PortableBackup(records: payload([rejected]), accounts: [account], datasetId: backup.datasetId, attachments: backup.attachments)
        XCTAssertFalse(next.eligibility.transactions["t"]!.desktop)
        let deleted = try PortableBackup(records: payload(), accounts: [account], datasetId: backup.datasetId, attachments: backup.attachments)
        XCTAssertTrue(try deleted.validatedRecords().transactions.isEmpty)
        var corrupt = backup; corrupt.payload.append(0)
        XCTAssertThrowsError(try corrupt.validatedRecords())
        corrupt = backup; corrupt.complete = false
        XCTAssertThrowsError(try corrupt.validatedRecords())
        corrupt = backup; corrupt.schemaVersion = 99
        XCTAssertThrowsError(try corrupt.validatedRecords())
        let duplicates = try PortableBackup(records: payload([row(), row()]), accounts: [account], datasetId: backup.datasetId, attachments: backup.attachments)
        XCTAssertThrowsError(try duplicates.validatedRecords())
    }
    func testUnsafePathsReferencesAndOriginalChecksums() throws {
        var p = payload([row()]); p.sourceDocuments[0].localRelativePath = "../private"
        XCTAssertThrowsError(try PortableBackup.validate(p, accounts: [account]))
        p.sourceDocuments[0].localRelativePath = nil; p.transactions[0].sourceDocumentId = "missing"
        XCTAssertThrowsError(try PortableBackup.validate(p, accounts: [account]))
        p = payload([row()]); p.transactions[0].currencyCode = "KRW"
        XCTAssertThrowsError(try PortableBackup.validate(p, accounts: [account]))
        let attachment = BackupAttachment(sourceId: "s", status: "included", data: Data([1,2,3]))
        let backup = try PortableBackup(records: payload(), accounts: [], datasetId: UUID().uuidString, attachments: [attachment])
        XCTAssertNoThrow(try backup.validatedRecords())
        var badAttachment = attachment; badAttachment.sha256 = "bad"
        let invalid = try PortableBackup(records: payload(), accounts: [], datasetId: backup.datasetId, attachments: [badAttachment])
        XCTAssertThrowsError(try invalid.validatedRecords())
    }
    func testLegacyRecordsDecodeWithoutInventingCurrencyAndCSVIsSafe() throws {
        var p = payload([row(currency: nil)])
        let data = try BackupExporter.jsonData(p)
        let decoded = try PortableBackup.decoder().decode(BackupPayload.self, from: data)
        XCTAssertNil(decoded.transactions.first?.currencyCode)
        XCTAssertNil(decoded.transactions.first?.accountId)
        p.transactions[0].merchantNormalized = "=HYPERLINK(\"example\")"
        let csv = BackupExporter.transactionsCSV(p.transactions)
        XCTAssertTrue(csv.contains("account_id,currency,desktop_eligible"))
        XCTAssertTrue(csv.contains("'=HYPERLINK"))
        XCTAssertTrue(csv.contains("account_or_currency_unmapped"))
    }
    func testSharedAuditFixturesCoverContractCases() throws {
        let catalog = AuditFixtures.catalog()
        let byId = Dictionary(uniqueKeysWithValues: catalog.transactions.map { ($0.id, $0) })
        XCTAssertEqual(SpendingClassification(byId["rent"]!).grossSpending, 1200)
        XCTAssertEqual(SpendingClassification(byId["refund"]!).netSpending, -40)
        XCTAssertEqual(SpendingClassification(byId["card_pay"]!).cardSettlement, 500)
        XCTAssertEqual(SpendingClassification(byId["card_pay"]!).grossSpending, 0)
        XCTAssertTrue(Eligibility.transaction(byId["pending"]!).local)
        XCTAssertFalse(Eligibility.transaction(byId["pending"]!).desktop)
        XCTAssertFalse(Eligibility.transaction(byId["rejected"]!).local)
        let flows = SummaryGenerator.generateCashFlowSummaries(catalog.transactions)
        XCTAssertEqual(Set(flows.compactMap(\.currencyCode)), ["USD", "KRW"])
        let backup = try PortableBackup(records: catalog, accounts: [AuditFixtures.usd, AuditFixtures.krw],
                                        datasetId: UUID().uuidString, attachments: [.init(sourceId: "fixture_source", status: "omitted")])
        XCTAssertEqual(try backup.validatedRecords().transactions.count, catalog.transactions.count)
    }

    func testBilledCurrencyEvidenceDoesNotAssumeUSDOrUseOriginalCurrency() {
        XCTAssertEqual(CurrencyEvidence.read("Safeway | $12.00"), .unspecified)
        XCTAssertEqual(CurrencyEvidence.read("Billed amount USD $12.00 | Original amount ₩16,000"), .explicit("USD"))
        XCTAssertEqual(CurrencyEvidence.read("원거래 USD 12.00 청구금액 16,000원"), .explicit("KRW"))
        XCTAssertEqual(CurrencyEvidence.read("USD 12.00 | KRW 16,000"), .conflicting)
        XCTAssertEqual(CurrencyEvidence.read("Original amount KRW 16,000"), .unspecified)
        XCTAssertEqual(CurrencyEvidence.read("CA$12.00"), .explicit("CAD"))
        XCTAssertEqual(CurrencyEvidence.read("Original Joe’s USD 12.00"), .explicit("USD"))
    }

    func testOCRPrefersBilledAmountOverForeignAmount() throws {
        let result = HeuristicScreenshotParser.parse(sourceDocumentId: "s", fileName: "synthetic",
            lines: [OCRLine(text: "01/15/2026 Synthetic shop original amount USD 12.00 billed amount KRW 16,000")])
        let candidate = try XCTUnwrap(result.transactions.first)
        XCTAssertEqual(Normalizer.normalizeAmountText(candidate.amountText), 16000)
        XCTAssertEqual(candidate.merchantText, "Synthetic shop")
        XCTAssertEqual(CurrencyEvidence.read(candidate.evidenceText), .explicit("KRW"))
    }

    func testCurrencyCorrectionKeepsV1PairAndDesktopWithholdsDifferentBilledCurrency() throws {
        var transaction = row()
        transaction.evidenceText = "Billed amount KRW 16,000"
        XCTAssertFalse(Eligibility.transaction(transaction).local)
        transaction.confirmedBilledCurrency = "KRW"
        XCTAssertTrue(Eligibility.transaction(transaction).local)
        XCTAssertFalse(Eligibility.transaction(transaction).desktop)
        XCTAssertEqual(SummaryGenerator.generateCashFlowSummaries([transaction]).first?.currencyCode, "KRW")
        let snapshot = try PortableBackup(records: payload([transaction]), accounts: [account],
            datasetId: UUID().uuidString, attachments: [.init(sourceId: "s", status: "unavailable")])
        let roundTrip = try PortableBackup.decoder().decode(PortableBackup.self, from: snapshot.encoded())
        let restored = try XCTUnwrap(roundTrip.validatedRecords().transactions.first)
        XCTAssertEqual(restored.accountId, account.id)
        XCTAssertEqual(restored.currencyCode, "USD")
        XCTAssertEqual(restored.billedCurrencyCode, "KRW")
        XCTAssertEqual(roundTrip.eligibility.transactions[restored.id]?.reasons, ["billed_currency_differs_from_account"])
        transaction.confirmedBilledCurrency = "USD"
        XCTAssertTrue(Eligibility.transaction(transaction).desktop)
    }


    func testDefaultCurrencyAllowsLocalOnlySpendingAndHoldsConflicts() {
        var transaction = row()
        transaction.assignAccount(nil, defaultCurrency: "USD")
        transaction.evidenceText = "Safeway $12.00"
        XCTAssertTrue(Eligibility.transaction(transaction).local)
        XCTAssertFalse(Eligibility.transaction(transaction).desktop)
        transaction.evidenceText = "Billed amount KRW 16,000"
        XCTAssertFalse(Eligibility.transaction(transaction).local)
        transaction.confirmedBilledCurrency = "KRW"
        XCTAssertTrue(Eligibility.transaction(transaction).local)
        XCTAssertEqual(SummaryGenerator.generateCashFlowSummaries([transaction]).first?.currencyCode, "KRW")
    }

}

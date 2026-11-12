import XCTest
import SwiftData
import SpendingDomain
@testable import SpendingAssistant

@MainActor
final class BackupIntegrationTests: XCTestCase {
    func setup() throws -> (ModelContainer, LocalStore, ImportPipelineService, BackupService) {
        let container = try ModelContainer(for: SpendingPersistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LocalStore(modelContext: container.mainContext)
        store.readDefaultCurrency = { nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = SourceFileStore(directory: directory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let service = ImportPipelineService(store: store, files: files, enableFoundationModels: { false })
        return (container, store, service, BackupService(store: store, files: files))
    }
    func seed(_ store: LocalStore, _ service: ImportPipelineService) throws {
        try store.saveAccount(label: "Same label", currency: "USD")
        let account = try XCTUnwrap(store.allAccounts().first)
        try service.addManualTransaction(.init(date: "2026-01-15", merchant: "Synthetic rent", amount: -50, type: .payment, account: account.label), category: .rent, accountId: account.id)
    }
    func testReplaceRoundTripAndRollback() throws {
        let (container, store, pipeline, backup) = try setup(); _ = container
        try seed(store, pipeline)
        let original = try XCTUnwrap(store.allTransactions().first)
        let encoded = try backup.export(includeOriginals: false)
        let preview = try backup.preview(encoded)
        try store.deleteTransactions(ids: [original.id])
        try pipeline.addManualTransaction(.init(date: "2026-02-01", merchant: "Later row", amount: -5, type: .expense, account: "Unknown"), category: .shopping)
        let before = try store.allTransactions()
        store.beforeSave = { throw ImportFailure.emptyImage }
        XCTAssertThrowsError(try backup.restore(preview))
        XCTAssertEqual(try store.allTransactions(), before)
        store.beforeSave = nil
        try backup.restore(preview)
        XCTAssertEqual(try store.allTransactions().map(\.id), [original.id])
        XCTAssertEqual(try store.allCashFlows().first?.spendingTotal, 50)
        XCTAssertEqual(try store.dataset().datasetId, preview.package?.datasetId)
        try backup.restore(preview)
        XCTAssertEqual(try store.allTransactions().count, 1)
    }
    func testOriginalFilesAndInterruptedRecovery() throws {
        let (container, store, pipeline, backup) = try setup(); _ = container
        try seed(store, pipeline)
        var source = try XCTUnwrap(store.allSources().first)
        source.localRelativePath = try backup.files.save(data: Data([1,2,3]), sourceId: source.id, fileName: "synthetic.png")
        try store.commit { try store.upsert(source: source) }
        let preview = try backup.preview(backup.export(includeOriginals: true))
        try backup.restore(preview)
        let restored = try XCTUnwrap(store.allSources().first?.localRelativePath)
        XCTAssertEqual(try backup.files.read(restored), Data([1,2,3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try backup.files.url(source.localRelativePath!).path))
        let abandoned = try backup.files.save(data: Data([9]), sourceId: "abandoned", fileName: "x.png")
        let journal = BackupService.Journal(operationId: UUID().uuidString, newPaths: [abandoned], oldPaths: [restored])
        try JSONEncoder().encode(journal).write(to: backup.journalURL)
        try backup.recover()
        XCTAssertThrowsError(try backup.files.read(abandoned))
        XCTAssertEqual(try backup.files.read(restored), Data([1,2,3]))
    }
    func testLegacyRestoreRequiresMappingAndPreservesEvidence() throws {
        let (container, store, pipeline, backup) = try setup(); _ = container
        try seed(store, pipeline)
        let data = try BackupExporter.jsonData(backup.records())
        let preview = try backup.preview(data)
        XCTAssertNil(preview.package)
        try backup.restore(preview)
        XCTAssertNil(try store.allTransactions().first?.currencyCode)
        XCTAssertTrue(try store.allCashFlows().isEmpty)
        XCTAssertFalse(try XCTUnwrap(store.allTransactions().first?.evidenceText).isEmpty)
    }
    func testAccountRenameCollisionMappingAndCurrencySeparation() throws {
        let (container, store, pipeline, _) = try setup(); _ = container
        try seed(store, pipeline)
        let usd = try XCTUnwrap(store.allAccounts().first)
        try store.saveAccount(label: "Same label", currency: "KRW")
        let krw = try XCTUnwrap(store.allAccounts().first { $0.currencyCode == "KRW" })
        XCTAssertNotEqual(usd.id, krw.id)
        try pipeline.addManualTransaction(.init(date: "2026-01-15", merchant: "Other rent", amount: -5000, type: .expense, account: krw.label), category: .rent, accountId: krw.id)
        XCTAssertEqual(try store.allCashFlows().count, 2)
        let originalIds = Set(try store.allTransactions().map(\.id))
        try store.saveAccount(id: usd.id, label: "Renamed", currency: "USD")
        XCTAssertEqual(Set(try store.allTransactions().map(\.id)), originalIds)
        XCTAssertEqual(try store.allTransactions().first { $0.accountId == usd.id }?.accountLabel, "Renamed")
        try store.saveAccount(id: usd.id, label: "Renamed", currency: "KRW")
        XCTAssertEqual(try store.account(id: usd.id)?.spendingCurrency, "KRW")
        XCTAssertEqual(try store.allTransactions().first { $0.accountId == usd.id }?.billedCurrencyCode, "USD")
        try pipeline.addManualTransaction(.init(date: "2026-02-15", merchant: "New purchase", amount: -1000,
            type: .expense, account: "Renamed"), category: .shopping, accountId: usd.id)
        let newRow = try XCTUnwrap(store.allTransactions().first { $0.merchantRaw == "New purchase" })
        XCTAssertEqual(newRow.accountId, usd.id)
        XCTAssertEqual(newRow.currencyCode, "USD")
        XCTAssertEqual(newRow.billedCurrencyCode, "KRW")
        XCTAssertFalse(Eligibility.transaction(newRow).desktop)
    }
    func testImageImportPersistsExplicitAccountOnSourceAndRow() async throws {
        let (container, store, _, _) = try setup()
        _ = container
        try store.saveAccount(label: "Original", currency: "KRW")
        let account = try XCTUnwrap(store.allAccounts().first)
        let service = ImportPipelineService(store: store,
            files: SourceFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            enableFoundationModels: { false },
            recognize: { _ in [OCRLine(text: "01/01/2026 Safeway $12.00")] })
        defer { try? FileManager.default.removeItem(at: service.files.directory) }
        let result = await service.importImage(data: Data([1, 2]), fileName: "Synthetic.png", mimeType: "image/png",
            sourceType: .files, accountId: account.id)
        XCTAssertEqual(result.status, .imported)
        let row = try XCTUnwrap(store.allTransactions().first)
        XCTAssertEqual(row.accountId, account.id)
        XCTAssertEqual(row.currencyCode, "KRW")
        XCTAssertEqual(try store.allSources().first?.importAccountId, account.id)
    }

    func testUnmappedOrConflictingBalanceCannotBeConfirmed() throws {
        let (container, store, pipeline, _) = try setup(); _ = container
        try pipeline.addManualAsset(accountLabel: "Unmapped", observedDate: "2026-01-31", balance: 1, balanceType: .checking)
        let row = try XCTUnwrap(store.allAssets().first)
        XCTAssertThrowsError(try store.saveReviewedAsset(row))
    }
    func testExclusiveExportSerializesWithCoordinator() async throws {
        let (container, store, pipeline, backup) = try setup(); _ = container
        try seed(store, pipeline)
        let coordinator = ImportCoordinator(service: pipeline, inbox: nil)
        let first = try await coordinator.exclusive { try backup.export(includeOriginals: false) }
        let second = try await coordinator.exclusive { try backup.export(includeOriginals: false) }
        let a = try PortableBackup.decoder().decode(PortableBackup.self, from: first)
        let b = try PortableBackup.decoder().decode(PortableBackup.self, from: second)
        XCTAssertEqual(a.datasetId, b.datasetId)
        XCTAssertEqual(a.recordCounts["transactions"], b.recordCounts["transactions"])
        XCTAssertFalse(coordinator.isBusy)
    }

    func testSourceAccountChangesApplyOnlyToThatSourceAndExistingRowsOnlyWhenRequested() async throws {
        let (container, store, _, _) = try setup()
        _ = container
        let original = try store.saveAccount(label: "Original", currency: "USD")
        let updated = try store.saveAccount(label: "Updated", currency: "KRW")
        let service = ImportPipelineService(store: store,
            files: SourceFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            enableFoundationModels: { false },
            recognize: { _ in [OCRLine(text: "01/01/2026 Safeway $12.00")] })
        defer { try? FileManager.default.removeItem(at: service.files.directory) }
        let first = await service.importImage(data: Data([1, 2]), fileName: "First.png", mimeType: "image/png", sourceType: .files,
            requestDetails: true, accountId: original)
        let second = await service.importImage(data: Data([2, 3]), fileName: "Second.png", mimeType: "image/png", sourceType: .files,
            requestDetails: true, accountId: original)
        XCTAssertEqual(first.status, .imported)
        XCTAssertEqual(second.status, .imported)
        let sourceId = try XCTUnwrap(first.source?.id)
        let secondId = try XCTUnwrap(second.source?.id)
        XCTAssertEqual(try store.allCashFlows().first?.currencyCode, "USD")

        try service.updateSourceOptions(id: sourceId, cardName: "", layout: .generic, month: "",
            accountId: updated, applyAccountToRows: false)
        XCTAssertEqual(try store.source(id: sourceId)?.importAccountId, updated)
        XCTAssertTrue(try store.allTransactions().allSatisfy { $0.accountId == original })

        try service.updateSourceOptions(id: sourceId, cardName: "", layout: .generic, month: "", accountId: updated)
        XCTAssertEqual(try store.allTransactions().first { $0.sourceDocumentId == sourceId }?.currencyCode, "KRW")
        XCTAssertEqual(try store.allTransactions().first { $0.sourceDocumentId == secondId }?.accountId, original)
        XCTAssertEqual(try store.source(id: secondId)?.importAccountId, original)
    }


    func testDefaultCurrencyLetsScreenshotCountWithoutAccountAndKeepsHistoricalAssignments() async throws {
        let (container, store, _, backup) = try setup()
        _ = container
        let service = ImportPipelineService(store: store, files: backup.files, enableFoundationModels: { false },
            recognize: { _ in [OCRLine(text: "01/15/2026 Safeway $12.00")] })
        store.readDefaultCurrency = { "USD" }
        let outcome = await service.importImage(data: Data([9, 7]), fileName: "Synthetic.png", mimeType: "image/png",
            sourceType: .files, requestDetails: true)
        XCTAssertEqual(outcome.status, .imported)
        let row = try XCTUnwrap(store.allTransactions().first)
        XCTAssertNil(row.accountId)
        XCTAssertNil(row.currencyCode)
        XCTAssertEqual(row.billedCurrencyCode, "USD")
        XCTAssertEqual(try store.allCashFlows().first?.spendingTotal, 12)
        XCTAssertFalse(Eligibility.transaction(row).desktop)
        try store.applyDefaultCurrencyToUnassignedTransactions("KRW")
        XCTAssertEqual(try store.allTransactions().first?.billedCurrencyCode, "USD")
        let preview = try backup.preview(backup.export(includeOriginals: false))
        XCTAssertEqual(preview.records.transactions.first?.billedCurrencyCode, "USD")
    }

}

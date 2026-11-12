import SwiftUI
import SwiftData
import SpendingDomain

/// Shared by the app and in-memory integration tests.
enum SpendingPersistence {
    static var schema: Schema {
        Schema([SDAccount.self, SDDataset.self, SDSourceDocument.self, SDTransaction.self, SDAssetSnapshot.self, SDReviewItem.self,
                SDCorrection.self, SDMonthlySummary.self, SDCashFlowSummary.self, SDAnomaly.self])
    }
}

@main
struct SpendingAssistantApp: App {
    private let container: ModelContainer
    @State private var imports: ImportCoordinator

    init() {
        do {
            let inMemory = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                || NSClassFromString("XCTestCase") != nil
            let container = try ModelContainer(for: SpendingPersistence.schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: inMemory)])
            self.container = container
            let files = inMemory ? SourceFileStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("spending-ui-tests", isDirectory: true)) : SourceFileStore()
            ExportFile.cleanup()
            let service = ImportPipelineService(store: LocalStore(modelContext: container.mainContext), files: files)
            let args = ProcessInfo.processInfo.arguments
            let lockForUITest = args.contains("--ui-testing-lock") || args.contains("--ui-testing-lock-deny")
            // UI tests share the simulator defaults suite; always reset so lock does not leak across cases.
            if inMemory { UserDefaults.standard.set(lockForUITest, forKey: "appLockEnabled") }
            service.processingAllowed = inMemory ? !lockForUITest : !UserDefaults.standard.bool(forKey: "appLockEnabled")
            #if DEBUG
            if inMemory && args.contains("--ui-testing-fixture") {
                try service.seedDemo()
                if args.contains("--ui-testing-unresolved-confirmation") {
                    let issue = ReviewItemRecord(reviewItemId: "ui-test-duplicate", targetType: .transaction,
                        targetId: "txn_demo_2", issueType: .duplicateRisk, severity: .medium, question: "Check for a duplicate charge.")
                    try service.store.commit { try service.store.upsert(review: issue) }
                }
            }
            #endif
            // Hosted unit tests and UI tests must not drain the normal shared inbox.
            _imports = State(initialValue: ImportCoordinator(service: service,
                inbox: inMemory ? nil : ShareInboxService.inboxDirectory))
        } catch { fatalError("Could not create the local store.") }
    }

    var body: some Scene {
        WindowGroup { PrivacyRootView().environment(imports) }
            .modelContainer(container)
    }
}

import SwiftUI
import SwiftData
import SpendingDomain

/// Shared by the app and in-memory integration tests.
enum SpendingPersistence {
    static var schema: Schema {
        Schema([SDSourceDocument.self, SDTransaction.self, SDAssetSnapshot.self, SDReviewItem.self,
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
            let service = ImportPipelineService(store: LocalStore(modelContext: container.mainContext), files: files)
            #if DEBUG
            if inMemory && ProcessInfo.processInfo.arguments.contains("--ui-testing-fixture") {
                try service.seedDemo()
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-unresolved-confirmation") {
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
        WindowGroup { RootTabView().environment(imports) }
            .modelContainer(container)
    }
}

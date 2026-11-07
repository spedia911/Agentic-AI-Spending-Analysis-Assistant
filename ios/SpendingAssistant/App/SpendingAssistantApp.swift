import SwiftUI
import SwiftData

@main
struct SpendingAssistantApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SDSourceDocument.self,
            SDTransaction.self,
            SDAssetSnapshot.self,
            SDReviewItem.self,
            SDCorrection.self,
            SDMonthlySummary.self,
            SDCashFlowSummary.self,
            SDAnomaly.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}

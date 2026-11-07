import SwiftUI
import SwiftData

enum AppRoute: Hashable {
    case home, importTab, review, sources, settings
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("enableFoundationModels") private var enableFoundationModels = true
    @AppStorage("sourceImageRetentionDays") private var retentionDays = 30
    @State private var route: AppRoute = .home

    var body: some View {
        TabView(selection: $route) {
            HomeView()
                .tabItem { Label("Home", systemImage: "chart.bar.fill") }
                .tag(AppRoute.home)
            ImportView()
                .tabItem { Label("Import", systemImage: "square.and.arrow.down") }
                .tag(AppRoute.importTab)
            ReviewView()
                .tabItem { Label("Review", systemImage: "checklist") }
                .tag(AppRoute.review)
            SourcesView()
                .tabItem { Label("Sources", systemImage: "photo.on.rectangle") }
                .tag(AppRoute.sources)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRoute.settings)
        }
        .task {
            let store = LocalStore(modelContext: modelContext)
            let service = ImportPipelineService(store: store, enableFoundationModels: enableFoundationModels)
            _ = await ShareInboxService.drain(into: service)
            if let sources = try? store.allSources() {
                SourceFileStore.cleanup(retentionDays: retentionDays, sources: sources)
            }
        }
    }
}

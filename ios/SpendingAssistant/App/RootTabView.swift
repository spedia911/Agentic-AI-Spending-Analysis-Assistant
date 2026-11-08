import SwiftUI
import SwiftData
import SpendingDomain

enum AppRoute: Hashable {
    case home, importTab, review, sources, settings
}

struct RootTabView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.scenePhase) private var scenePhase
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
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await activate() } }
        }
        .onChange(of: retentionDays) { _, _ in cleanup() }
    }

    private func activate() async {
        await imports.drainShareInbox()
        do { try imports.service.backfillFingerprints() }
        catch { imports.shareMessage = "Source recovery: " + PrivacyRedactor.safeErrorDetail(error) }
        cleanup()
    }

    private func cleanup() {
        do { SourceFileStore.cleanup(retentionDays: retentionDays, sources: try imports.service.store.allSources()) }
        catch { imports.shareMessage = PrivacyRedactor.safeErrorDetail(error) }
    }
}

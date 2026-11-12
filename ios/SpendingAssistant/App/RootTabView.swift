import SwiftUI
import SwiftData
import SpendingDomain
#if DEBUG
import UIKit
#endif

enum AppRoute: Hashable {
    case home, importTab, review, sources, settings
}

struct RootTabView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sourceImageRetentionDays") private var retentionDays = 30
    @State private var route: AppRoute = .home
    @State private var details: ScreenshotImportDetails?

    var body: some View {
        TabView(selection: $route) {
            HomeView()
                .tabItem { Label { Text("Home") } icon: { FinanceIcon.dashboard.image } }
                .tag(AppRoute.home)
            ImportView()
                .tabItem { Label { Text("Import") } icon: { FinanceIcon.importReceipt.image } }
                .tag(AppRoute.importTab)
            ReviewView()
                .tabItem { Label { Text("Review") } icon: { FinanceIcon.review.image } }
                .tag(AppRoute.review)
            SourcesView()
                .tabItem { Label { Text("Sources") } icon: { FinanceIcon.report.image } }
                .tag(AppRoute.sources)
            SettingsView()
                .tabItem { Label { Text("Settings") } icon: { FinanceIcon.profile.image } }
                .tag(AppRoute.settings)
        }
        .sheet(item: $details, onDismiss: showNextDetails) { request in
            ScreenshotDetailsView(request: request)
        }
        .onChange(of: imports.pendingDetails.map(\.id)) { _, _ in showNextDetails() }
        .onChange(of: imports.isBusy) { _, busy in if !busy { showNextDetails() } }
        .task {
            await activate()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-screenshot-details"),
               imports.outcomes.isEmpty {
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 650, height: 220))
                let data = renderer.pngData { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 650, height: 220))
                    ("10/02 Safeway $12.00" as NSString).draw(at: CGPoint(x: 36, y: 100), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.black
                    ])
                }
                let result = await imports.service.importImage(data: data, fileName: "Synthetic screenshot.png",
                    mimeType: "image/png", sourceType: .files, requestDetails: true)
                imports.outcomes = [result]
                if let request = result.details { imports.enqueueDetails(request) }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await activate() } }
        }
    }

    private func showNextDetails() {
        guard details == nil else { return }
        details = imports.nextDetails()
    }

    private func activate() async {
        guard imports.service.processingAllowed else { return }
        do {
            try imports.service.backfillFingerprints()
            try imports.service.backfillTransactionOrigins()
            try imports.service.store.reconcileAdvisoryReviews()
            try imports.service.store.applyDefaultCurrencyToUnassignedTransactions(imports.service.store.defaultCurrency)
        }
        catch { imports.shareMessage = "Source recovery: " + PrivacyRedactor.safeErrorDetail(error) }
        cleanup()
    }

    private func cleanup() {
        guard imports.service.processingAllowed else { return }
        do { try imports.service.cleanupSources(retentionDays: retentionDays) }
        catch { imports.shareMessage = PrivacyRedactor.safeErrorDetail(error) }
    }
}

import SwiftUI
import SpendingDomain
import LocalAuthentication

@MainActor @Observable
final class AppPrivacy {
    var unlocked = false
    var authenticating = false
    private var context: LAContext?
    func lock() { unlocked = false; context?.invalidate(); context = nil; authenticating = false }
    func unlock(required: Bool) async {
        guard !authenticating else { return }
        guard required else { unlocked = true; return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-lock-deny") {
            unlocked = false
            return
        }
        #endif
        authenticating = true
        let context = LAContext(); self.context = context
        defer { if self.context === context { authenticating = false; self.context = nil } }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your local financial records")
            if self.context === context { unlocked = success }
        } catch { if self.context === context { unlocked = false } }
    }
}

struct PrivacyRootView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var required = false
    @State private var privacy = AppPrivacy()
    var body: some View {
        ZStack {
            if privacy.unlocked {
                RootTabView()
            }
            if !privacy.unlocked || scenePhase != .active {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack {
                    Image(systemName: "lock.fill")
                    Text("Spending Assistant")
                    Text("Content locked").font(.caption).foregroundStyle(.secondary)
                    if scenePhase == .active {
                        Button("Unlock") { Task { await authenticate() } }
                            .disabled(privacy.authenticating)
                            .accessibilityIdentifier("privacyUnlock")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("privacyCover")
            }
        }
        .background(PrivacyShield(covered: scenePhase != .active))
        .task { await authenticate() }
        .onChange(of: required) { _, _ in privacy.lock(); imports.service.processingAllowed = false; Task { await authenticate() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if required { privacy.lock() }
                imports.service.processingAllowed = false
            }
            if phase == .inactive { imports.service.processingAllowed = false }
            if phase == .active { Task { await authenticate() } }
        }
    }
    private func authenticate() async {
        guard scenePhase == .active else { return }
        if !privacy.unlocked { await privacy.unlock(required: required) }
        imports.service.processingAllowed = privacy.unlocked && scenePhase == .active
        guard imports.service.processingAllowed else { return }
        do {
            try BackupService(store: imports.service.store, files: imports.service.files).recover()
            await imports.drainShareInbox()
        } catch {
            imports.shareMessage = PrivacyRedactor.safeErrorDetail(error)
        }
    }
}


/// A separate non-key window also covers system share sheets and presented source evidence.
private struct PrivacyShield: UIViewRepresentable {
    var covered: Bool
    final class Coordinator { var window: UIWindow? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) {
        if context.coordinator.window == nil,
           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView:
                ZStack { Color(uiColor: .systemBackground).ignoresSafeArea(); Label("Spending Assistant", systemImage: "lock.fill") })
            context.coordinator.window = window
        }
        context.coordinator.window?.isHidden = !covered
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.window?.isHidden = true; coordinator.window = nil }
}

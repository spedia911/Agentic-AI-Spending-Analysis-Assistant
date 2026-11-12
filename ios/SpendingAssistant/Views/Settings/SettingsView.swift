import SwiftUI
import LocalAuthentication
import SpendingDomain

struct SettingsView: View {
    @Environment(ImportCoordinator.self) private var imports
    @AppStorage("sourceImageRetentionDays") private var retentionDays = 30
    @AppStorage("enableFoundationModels") private var enableFoundationModels = true
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("defaultCurrencyCode") private var defaultCurrency = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Export") {
                    NavigationLink { ExportDataView() } label: {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                }
                Section("Accounts & currency") {
                    CurrencySelector(title: "Default currency", selection: Binding(get: { defaultCurrency }, set: saveDefaultCurrency))
                        .disabled(imports.isBusy)
                    if !defaultCurrency.isEmpty { Button("Clear default currency") { defaultCurrency = "" } }
                    Text("Used for transactions without an account or an assigned currency. Changing it keeps currencies already assigned.").font(.caption)
                    NavigationLink("Manage accounts") { AccountsView() }
                }
                Section("Data safety") {
                    NavigationLink("Backup & restore") { BackupSettingsView() }
                    NavigationLink {
                        SourceRetentionSettingsView()
                    } label: {
                        LabeledContent("Source file retention", value: retentionDays == 0 ? "Keep indefinitely" : "\(retentionDays) days")
                    }
                    Toggle("Require Face ID / device passcode", isOn: Binding(get: { appLockEnabled }, set: setAppLock))
                    Text("When enabled, authenticate on launch and after leaving the app. App previews are always covered.").font(.caption)
                }
                Section("On-device AI") {
                    Toggle("Use Foundation Models when available", isOn: $enableFoundationModels)
                    Text(OnDeviceAIFactory.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let message {
                    Section { Text(message).font(.footnote) }
                }
                Section("About") {
                    HStack(spacing: 12) {
                        Image("BrandMark")
                            .resizable().scaledToFit().frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        Text("Local-first Spending Assistant v2")
                    }
                    Text("No Google Drive or Sheets dependency.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func saveDefaultCurrency(_ currency: String) {
        do {
            try imports.service.store.applyDefaultCurrencyToUnassignedTransactions(currency)
            defaultCurrency = currency
            message = nil
        } catch { message = PrivacyRedactor.safeErrorDetail(error) }
    }

    private func setAppLock(_ enabled: Bool) {
        if enabled, !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            message = "Set a device passcode before enabling app lock."
            return
        }
        appLockEnabled = enabled
        message = nil
    }

}

private struct SourceRetentionSettingsView: View {
    @Environment(ImportCoordinator.self) private var imports
    @AppStorage("sourceImageRetentionDays") private var retentionDays = 30
    @State private var confirmCleanup = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Stepper(retentionDays == 0 ? "Keep stored copies indefinitely" : "Keep stored copies for \(retentionDays) days",
                        value: $retentionDays, in: 0...365)
                Text("The app checks the age of its stored screenshot and PDF copies when you open it. Set this to 0 days to keep them indefinitely.")
                Text("Cleanup keeps extracted transactions, balances, OCR text, and reviews. Your originals in Photos or Files stay where they are.")
            }
            Section {
                Button("Remove expired copies now", role: .destructive) { confirmCleanup = true }
                    .disabled(retentionDays == 0 || imports.isBusy)
                if let message { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Source file retention")
        .confirmationDialog("Remove stored copies older than \(retentionDays) days?", isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("Remove expired copies", role: .destructive) {
                do {
                    let count = try imports.service.cleanupSources(retentionDays: retentionDays)
                    message = count == 0 ? "No stored copies had expired." : "Removed \(count) expired source copies."
                } catch { message = PrivacyRedactor.safeErrorDetail(error) }
            }
        }
    }
}

import SwiftUI
import SwiftData
import SpendingDomain

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("sourceImageRetentionDays") private var retentionDays = 30
    @AppStorage("enableFoundationModels") private var enableFoundationModels = true
    @State private var exportURL: URL?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("On-device AI") {
                    Toggle("Use Foundation Models when available", isOn: $enableFoundationModels)
                    Text(OnDeviceAIFactory.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Retention") {
                    Stepper("Keep source images \(retentionDays) days (0 = forever)", value: $retentionDays, in: 0...365)
                    Button("Run retention cleanup now") { cleanup() }
                }
                Section("Backup") {
                    Button("Export JSON backup") { exportBackup() }
                    if let exportURL {
                        ShareLink(item: exportURL) { Text("Share export file") }
                    }
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

    private func cleanup() {
        do {
            let store = LocalStore(modelContext: modelContext)
            let sources = try store.allSources()
            SourceFileStore.cleanup(retentionDays: retentionDays, sources: sources)
            message = "Retention cleanup finished."
        } catch {
            message = PrivacyRedactor.safeErrorDetail(error)
        }
    }

    private func exportBackup() {
        do {
            let store = LocalStore(modelContext: modelContext)
            let summaries = SummaryGenerator.generate(
                transactions: try store.allTransactions(),
                assetSnapshots: try store.allAssets()
            )
            let payload = BackupPayload(
                sourceDocuments: try store.allSources(),
                transactions: try store.allTransactions(),
                assetSnapshots: try store.allAssets(),
                reviewItems: try store.allReviews(),
                corrections: try store.allCorrections(),
                monthlySummaries: summaries.monthlySummaries,
                quarterlySummaries: summaries.quarterlySummaries,
                cashFlowSummaries: summaries.cashFlowSummaries,
                assetTrends: summaries.assetTrends,
                anomalies: try store.allAnomalies()
            )
            let data = try BackupExporter.jsonData(payload)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("spending-backup.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            message = "Backup ready to share."
        } catch {
            message = PrivacyRedactor.safeErrorDetail(error)
        }
    }
}

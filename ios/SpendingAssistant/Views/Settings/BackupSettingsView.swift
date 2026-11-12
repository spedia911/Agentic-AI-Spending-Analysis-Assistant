import SwiftUI
import UniformTypeIdentifiers
import SpendingDomain

struct BackupSettingsView: View {
    @Environment(ImportCoordinator.self) private var imports
    @State private var includeOriginals = false
    @State private var importing = false
    @State private var preview: BackupService.Preview?
    @State private var share: ExportFile?
    @State private var message: String?
    @State private var confirm = false
    @State private var exporting = false
    private var service: BackupService { BackupService(store: imports.service.store, files: imports.service.files) }
    var body: some View {
        Form {
            Section("Create a backup") {
                Text("Contains sensitive records and OCR evidence. Files you share are outside this app’s protection. Independently edited copies do not synchronize.")
                Toggle("Include retained images and PDFs", isOn: $includeOriginals)
                Button("Save backup file") { saveBackup() }
                    .accessibilityIdentifier("exportBackup")
            }
            Section("Restore") {
                Button("Choose backup to restore") { chooseBackup() }
                    .accessibilityIdentifier("chooseBackup")
                if let preview {
                    Text("\(preview.records.transactions.count) transactions · \(preview.records.assetSnapshots.count) balances · \(preview.records.sourceDocuments.count) sources")
                    Text("\(preview.records.reviewItems.count) reviews · \(preview.records.corrections.count) corrections · \(preview.package?.attachments.count ?? 0) attachment records")
                        .font(.caption)
                    Text(preview.warning)
                    Button("Replace local data…", role: .destructive) { confirm = true }
                        .accessibilityIdentifier("confirmRestorePreview")
                    Button("Cancel restore") { self.preview = nil }
                }
            }
            if let message { Text(message).accessibilityIdentifier("backupStatus") }
        }
        .navigationTitle("Backup & restore")
        .disabled(imports.isBusy || exporting)
        .confirmationDialog("Replace all local records with this backup?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Replace local data", role: .destructive) {
                guard let preview else { return }
                Task {
                    do {
                        try await imports.exclusive {
                            try service.restore(preview)
                        }
                        self.preview = nil
                        message = preview.package == nil
                            ? "Restore completed. Map accounts and currencies before totals are included."
                            : "Restore completed."
                    } catch { message = PrivacyRedactor.safeErrorDetail(error) }
                }
            }
            .accessibilityIdentifier("confirmReplaceBackup")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                preview = try service.preview(Data(contentsOf: url)); message = nil
            } catch { message = PrivacyRedactor.safeErrorDetail(error) }
        }
        .sheet(item: $share, onDismiss: { ExportFile.cleanup() }) { file in ExportShareSheet(url: file.url) }
    }
    private func chooseBackup() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-backup-preview") {
            do { preview = try service.preview(service.export(includeOriginals: false)) }
            catch { message = PrivacyRedactor.safeErrorDetail(error) }
            return
        }
        #endif
        importing = true
    }

    private func saveBackup() {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let data = try await imports.exclusive { try service.export(includeOriginals: includeOriginals) }
                share = try ExportFile(data: data, name: "spending-backup", extension: "json")
            } catch { message = PrivacyRedactor.safeErrorDetail(error) }
        }
    }
}

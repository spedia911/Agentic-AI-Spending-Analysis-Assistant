import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import SpendingDomain

struct ImportView: View {
    @Environment(ImportCoordinator.self) private var imports
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var aiJSON = ""
    @State private var message: String?
    @State private var showImporter = false
    @State private var showManual = false
    @State private var showManualAsset = false
    @State private var showJSON = false
    @State private var showSettings = false
    @AppStorage("importAccountId") private var accountId = ""
    @AppStorage("importCardName") private var cardName = ""
    @AppStorage("importScreenshotLayout") private var layout: ScreenshotLayout = .automatic
    @AppStorage("importStatementMonth") private var statementMonth = ""

    var body: some View {
        NavigationStack {
            Form {
                if !showJSON {
                    Section("Screenshots") {
                        AccountSelector(accountId: $accountId, suggestedName: cardName)
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                            Label("Choose from Photos", systemImage: "photo")
                        }
                        .onChange(of: pickerItems) { _, items in
                            guard !items.isEmpty else { return }
                            Task { await importPhotos(items) }
                        }
                        Button("Choose from Files (images or PDF)") { showImporter = true }
                        if layout != .automatic { Text(layout.title).font(.caption) }
                        Text("Choose the account for this batch. Change the layout under Import settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.disabled(imports.isBusy)

                } else {
                    Section("AI app JSON import") {
                        Text("Use an extraction prompt with ChatGPT, Claude, or Grok, then paste its JSON here. Balance-only JSON is supported.")
                            .font(.footnote)
                        Button("Copy transaction + balance prompt") {
                            UIPasteboard.general.string = ExtractionPrompts.mixedPrompt(sourceDocumentId: "replace-me", fileName: "screenshot.png")
                            message = "Mixed extraction prompt copied."
                        }
                        Button("Copy balances-only prompt") {
                            UIPasteboard.general.string = ExtractionPrompts.balancesPrompt(sourceDocumentId: "replace-me", fileName: "balances.png")
                            message = "Balances prompt copied."
                        }
                        TextEditor(text: $aiJSON).frame(height: 160).accessibilityIdentifier("aiJSONEditor")
                        Button("Import pasted JSON") {
                            let text = aiJSON
                            Task {
                                let results = await imports.run([ImportJob(name: "ai-import.json") { .json(text, sourceType: .aiImport) }])
                                if results.first?.status == .imported || results.first?.status == .alreadyImported { aiJSON = "" }
                            }
                        }.disabled(aiJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.disabled(imports.isBusy)
                }

                if imports.isBusy {
                    Section("Importing") {
                        ProgressView(value: Double(imports.completed), total: Double(max(imports.total, 1)))
                        Text("\(imports.completed) of \(imports.total) completed")
                    }
                }
                if !imports.outcomes.isEmpty {
                    Section("Latest batch") {
                        Text(imports.summary).accessibilityIdentifier("importSummary")
                        ForEach(imports.outcomes) { outcome in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(outcome.fileName)
                                Text(outcome.error ?? (outcome.status == .needsDetails ? "Waiting for details in Sources" : outcome.status == .alreadyImported ? "Already imported" : "Imported"))
                                    .font(.caption).foregroundStyle(outcome.status == .failed ? .orange : .secondary)
                            }
                        }
                    }
                }
                if let message { Section { Text(message) } }
                if let message = imports.shareMessage { Section("From Share") { Text(message) } }
                if !imports.shareFailures.isEmpty {
                    Section("Share items needing attention") {
                        ForEach(imports.shareFailures) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.url.lastPathComponent)
                                Text(item.error ?? "Import failed.").font(.caption).foregroundStyle(.orange)
                                HStack {
                                    Button("Retry") { Task { await imports.retryShare(item) } }
                                }.buttonStyle(.bordered).disabled(imports.isBusy)
                            }.recordActions("pending attachment", detail: "Removes this copy from the Share inbox.", edit: nil) {
                                imports.deleteShare(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import")
            .toolbar {
                Menu("Input type", systemImage: "square.and.pencil") {
                    Button("Screenshots", systemImage: "photo") { showJSON = false }
                    Button("Add transaction manually", systemImage: "plus") { showManual = true }
                    Button("Add balance manually", systemImage: "building.columns") { showManualAsset = true }
                    Button("Paste AI JSON", systemImage: "doc.text") { selectJSON() }
                }.accessibilityIdentifier("importInputType").disabled(imports.isBusy)
                Button("Import settings", systemImage: "ellipsis.circle") { showSettings = true }
                    .disabled(imports.isBusy)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    Form {
                        Section("Screenshot style") {
                            CardOptionsView(accountId: $accountId, showsAccount: false, cardName: $cardName, layout: $layout, month: $statementMonth)
                        }
                    }
                    .navigationTitle("Import settings")
                    .toolbar { Button("Done") { showSettings = false } }
                }
            }
            .sheet(isPresented: $showManual) { ManualTransactionView(initialCard: cardName, initialAccountId: accountId) }
            .sheet(isPresented: $showManualAsset) { ManualAssetView(initialAccountId: accountId) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
                switch result {
                case let .success(urls):
                    Task {
                        await imports.run(urls.map { url in
                            ImportJob(name: url.lastPathComponent) {
                                let scoped = url.startAccessingSecurityScopedResource()
                                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                                // Some picker URLs are already accessible and do not require a scope.
                                let data = try Data(contentsOf: url)
                                return .image(data, mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg", sourceType: .files)
                            }
                        })
                    }
                case let .failure(error): message = PrivacyRedactor.safeErrorDetail(error)
                }
            }
        }
    }

    private func selectJSON() {
        showJSON = true
        #if DEBUG
        if aiJSON.isEmpty, ProcessInfo.processInfo.arguments.contains("--ui-testing-fixture"),
           let url = Bundle.main.url(forResource: "sample-extraction", withExtension: "json") {
            aiJSON = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        #endif
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        await imports.run(items.enumerated().map { index, item in
            let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
            return ImportJob(name: "Photo \(index + 1).\(type?.preferredFilenameExtension ?? "jpg")") {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportFailure.emptyImage }
                return .image(data, mimeType: type?.preferredMIMEType ?? "image/jpeg", sourceType: .photos)
            }
        })
        pickerItems = []
    }
}

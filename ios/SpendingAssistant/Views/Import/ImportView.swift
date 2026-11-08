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

    var body: some View {
        NavigationStack {
            Form {
                if imports.isBusy {
                    Section("Importing") {
                        ProgressView(value: Double(imports.completed), total: Double(max(imports.total, 1)))
                        Text("\(imports.completed) of \(imports.total) completed")
                    }
                }
                Section("Screenshots") {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo")
                    }
                    .onChange(of: pickerItems) { _, items in
                        guard !items.isEmpty else { return }
                        Task { await importPhotos(items) }
                    }
                    Button("Choose from Files") { showImporter = true }
                    Text("Vision OCR runs on your device. Uncertain records go to Review; AI JSON can repair an unsuccessful extraction.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(imports.isBusy)

                Section("AI app JSON import") {
                    Text("Use the extraction prompt with ChatGPT, Claude, or Grok, then paste its JSON here.").font(.footnote)
                    Button("Copy extraction prompt") {
                        UIPasteboard.general.string = ExtractionPrompts.mixedPrompt(sourceDocumentId: "replace-me", fileName: "screenshot.png")
                        message = "Prompt copied."
                    }
                    TextEditor(text: $aiJSON).frame(height: 160).accessibilityIdentifier("aiJSONEditor")
                    Button("Import pasted JSON") {
                        let text = aiJSON
                        Task {
                            let results = await imports.run([ImportJob(name: "ai-import.json") { .json(text, sourceType: .aiImport) }])
                            if results.first?.status != .failed { aiJSON = "" }
                        }
                    }.disabled(aiJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Load sample JSON") {
                        if let url = Bundle.main.url(forResource: "sample-extraction", withExtension: "json") {
                            do { aiJSON = try String(contentsOf: url, encoding: .utf8) }
                            catch { message = PrivacyRedactor.safeErrorDetail(error) }
                        }
                    }
                }.disabled(imports.isBusy)

                if !imports.outcomes.isEmpty {
                    Section("Latest batch") {
                        Text(imports.summary).accessibilityIdentifier("importSummary")
                        ForEach(imports.outcomes) { outcome in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(outcome.fileName)
                                Text(outcome.error ?? (outcome.status == .alreadyImported ? "Already imported" : "Imported"))
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
                                    Button("Delete pending attachment", role: .destructive) { imports.deleteShare(item) }
                                }.buttonStyle(.bordered).disabled(imports.isBusy)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
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

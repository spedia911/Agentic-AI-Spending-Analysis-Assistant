import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import SpendingDomain

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("enableFoundationModels") private var enableFoundationModels = true

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var aiJSON = ""
    @State private var message: String?
    @State private var isBusy = false
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Screenshots") {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo")
                    }
                    .onChange(of: pickerItems) { _, items in
                        Task { await importPhotos(items) }
                    }
                    Button("Choose from Files") { showImporter = true }
                    Text("On-device Vision OCR runs first. Foundation Models structure incomplete OCR when available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("AI app JSON import") {
                    Text("Copy the extraction prompt into ChatGPT, Claude, or Grok, then paste the JSON here.")
                        .font(.footnote)
                    Button("Copy extraction prompt") {
                        UIPasteboard.general.string = ExtractionPrompts.mixedPrompt(
                            sourceDocumentId: "replace-me",
                            fileName: "screenshot.png"
                        )
                        message = "Prompt copied."
                    }
                    TextEditor(text: $aiJSON)
                        .frame(minHeight: 140)
                    Button("Import pasted JSON") {
                        Task { await importJSON() }
                    }
                    .disabled(aiJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                    if let sample = loadSampleJSON() {
                        Button("Load sample JSON") { aiJSON = sample }
                    }
                }

                if let message {
                    Section {
                        Text(message)
                    }
                }
            }
            .navigationTitle("Import")
            .disabled(isBusy)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                Task { await importFiles(result) }
            }
        }
    }

    private func service() -> ImportPipelineService {
        ImportPipelineService(store: LocalStore(modelContext: modelContext), enableFoundationModels: enableFoundationModels)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isBusy = true
        defer { isBusy = false; pickerItems = [] }
        do {
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let name = "photo-\(UUID().uuidString.prefix(8)).jpg"
                    _ = try await service().importImage(data: data, fileName: name, mimeType: "image/jpeg", sourceType: .photos)
                }
            }
            message = "Imported \(items.count) photo(s)."
        } catch {
            message = PrivacyRedactor.safeErrorDetail(error)
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let urls = try result.get()
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                _ = try await service().importImage(
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: "image/jpeg",
                    sourceType: .files
                )
            }
            message = "Imported \(urls.count) file(s)."
        } catch {
            message = PrivacyRedactor.safeErrorDetail(error)
        }
    }

    private func importJSON() async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await service().importAIJSON(text: aiJSON)
            message = "AI JSON imported."
            aiJSON = ""
        } catch {
            message = PrivacyRedactor.safeErrorDetail(error)
        }
    }

    private func loadSampleJSON() -> String? {
        Bundle.main.url(forResource: "sample-extraction", withExtension: "json")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

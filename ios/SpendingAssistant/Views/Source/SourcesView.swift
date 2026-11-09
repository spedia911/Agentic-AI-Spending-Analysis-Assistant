import SwiftUI
import SwiftData
import UIKit
import PDFKit
import SpendingDomain

struct SourcesView: View {
    @Environment(ImportCoordinator.self) private var imports
    @State private var editing: String?
    @Query(sort: \SDSourceDocument.createdTime, order: .reverse) private var sources: [SDSourceDocument]
    var body: some View {
        NavigationStack {
            List {
                if sources.contains(where: { $0.mimeType.hasPrefix("image/") || $0.mimeType == "application/pdf" }) {
                    NavigationLink("Edit multiple sources") { SourceBatchDetailsView() }
                }
                ForEach(sources, id: \.sourceDocumentId) { source in
                NavigationLink { SourceDetailView(source: source) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.fileName).font(.headline)
                        if let card = source.cardName { Text(card).font(.subheadline) }
                        Text("\(source.sourceTypeRaw.displayTitle) · \(source.statusRaw.displayTitle)").font(.caption).foregroundStyle(.secondary)
                        if let error = source.errorSummary { Text(error).font(.caption2).foregroundStyle(.orange) }
                    }
                }.recordActions("source and all its records", detail: RecordDestination.source(source.sourceDocumentId).deletionDetail,
                                edit: { editing = source.sourceDocumentId }) { try imports.service.deleteSource(id: source.sourceDocumentId) }
                }
            }
            .navigationTitle("Sources")
            .navigationDestination(item: $editing) { id in
                if let source = sources.first(where: { $0.sourceDocumentId == id }) { SourceDetailView(source: source) }
            }
        }
    }
}

struct SourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleteRecord = false
    @State private var editing: RecordDestination?
    @Environment(ImportCoordinator.self) private var imports
    let source: SDSourceDocument
    @Query private var transactions: [SDTransaction]
    @Query private var assets: [SDAssetSnapshot]
    @Query private var reviews: [SDReviewItem]
    @Query private var anomalies: [SDAnomaly]
    @State private var json = ""
    @State private var message: String?
    @State private var deleteImage = false
    @State private var showManual = false
    @State private var cardName = ""
    @State private var layout: ScreenshotLayout = .automatic
    @State private var month = ""

    private var isPDF: Bool { source.mimeType == "application/pdf" }
    private var related: [SDTransaction] { transactions.filter { $0.sourceDocumentId == source.sourceDocumentId } }
    private var relatedAssets: [SDAssetSnapshot] { assets.filter { $0.sourceDocumentId == source.sourceDocumentId } }
    private var targetIds: Set<String> { Set([source.sourceDocumentId] + related.map(\.transactionId) + relatedAssets.map(\.assetSnapshotId)) }

    var body: some View {
        List {
            if let message { Section { Text(message) } }
            Section {
                Button("Delete source and all its records", role: .destructive) { deleteRecord = true }.disabled(imports.isBusy)
            }
            Section("Source") {
                LabeledContent("Status", value: source.statusRaw.displayTitle)
                LabeledContent("Type", value: source.sourceTypeRaw.displayTitle)
                if let error = source.errorSummary { Text(error).foregroundStyle(.orange) }
                if let relative = source.localRelativePath {
                    if isPDF,
                       let document = PDFDocument(url: SourceFileStore.url(forRelativePath: relative)) {
                        NavigationLink("View original PDF") { StatementPDFPreview(document: document).navigationTitle("Statement PDF") }
                    } else if let data = try? Data(contentsOf: SourceFileStore.url(forRelativePath: relative)), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Text("Original file unavailable or removed by retention. Reimport it or attach AI JSON to recover a failed source.").font(.footnote)
                    }
                }
            }
            if source.imageDeletedAt != nil {
                Section { Text(isPDF ? "Stored PDF deleted. Transactions and extracted evidence are retained." : "Stored image deleted. Transactions and OCR evidence are retained. The original in Photos is unchanged.") }
            }
            if source.localRelativePath != nil {
                Section(isPDF ? "PDF storage" : "Image storage") {
                    Button(isPDF ? "Delete stored PDF" : "Delete stored image", role: .destructive) { deleteImage = true }.disabled(imports.isBusy)
                    Text("Removes only this app’s copy. Keeps transactions, account information, and extracted evidence.").font(.footnote)
                }
            }
            if source.statusRaw == ProcessingStatus.needsDetails.rawValue {
                Section {
                    Button("Finish import") {
                        do {
                            if let request = try imports.service.detailsForSource(id: source.sourceDocumentId) { imports.enqueueDetails(request) }
                        } catch { message = PrivacyRedactor.safeErrorDetail(error) }
                    }.disabled(imports.isBusy)
                    Text("The original and extracted text are saved. Add the missing details to import its transactions.").font(.footnote)
                }
            }
            Section("Account and date details") {
                    if isPDF { TextField("Account name", text: $cardName) }
                    else { CardOptionsView(cardName: $cardName, layout: $layout, month: $month) }
                    Button("Save source details") {
                        do {
                            try imports.service.updateSourceOptions(id: source.sourceDocumentId, cardName: cardName, layout: layout, month: month)
                            message = related.isEmpty ? "Details saved. Finish or retry import to use them."
                                : "Details saved. Account and matching yearless dates were updated where applicable."
                        } catch { message = PrivacyRedactor.safeErrorDetail(error) }
                    }.disabled(imports.isBusy)
            }
            Section("Manual correction") {
                Button("Add transaction for this source") { showManual = true }.disabled(imports.isBusy)
                Text("Open any transaction below to edit its date, merchant, amount, card, or category.").font(.footnote)
                if source.statusRaw != ProcessingStatus.processed.rawValue && !related.isEmpty && related.allSatisfy({ $0.transactionId.hasPrefix("txn_manual_") }) {
                    Button("Confirm all visible rows entered manually") {
                        do { try imports.service.completeManualSource(id: source.sourceDocumentId); message = "Manual transcription confirmed. Transaction reviews remain separate." }
                        catch { message = PrivacyRedactor.safeErrorDetail(error) }
                    }.disabled(imports.isBusy)
                    Text("Use this only after entering every visible row. This completes the source-level review without resolving transaction-level issues.").font(.footnote)
                }
            }
            if source.statusRaw != ProcessingStatus.processed.rawValue {
                Section("Recovery") {
                    Button("Retry import using saved OCR / image") {
                        Task { await imports.run([ImportJob(name: source.fileName) { .retry(source.sourceDocumentId) }]); message = imports.summary }
                    }.disabled(!related.isEmpty || !relatedAssets.isEmpty)
                    if related.isEmpty && relatedAssets.isEmpty {
                        Button("Copy extraction prompt") {
                            UIPasteboard.general.string = ExtractionPrompts.mixedPrompt(sourceDocumentId: source.sourceDocumentId, fileName: source.fileName)
                            message = "Prompt copied."
                        }
                        TextEditor(text: $json).frame(height: 160).accessibilityLabel("Replacement AI JSON")
                        Button("Attach replacement AI JSON") {
                            let text = json
                            Task { await imports.run([ImportJob(name: source.fileName) { .repair(text, sourceId: source.sourceDocumentId) }]); message = imports.summary }
                        }.disabled(json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.disabled(imports.isBusy)
            }
            if let raw = source.rawText, !raw.isEmpty { Section("Evidence and OCR text") { Text(raw).font(.footnote.monospaced()) } }
            Section("Transactions") {
                ForEach(related, id: \.transactionId) { tx in
                    let target = RecordDestination.transaction(tx.transactionId)
                    NavigationLink { TransactionDetailView(transactionId: tx.transactionId) } label: {
                        VStack(alignment: .leading) {
                            Text("\(tx.merchantNormalized) · \(tx.amount.formatted(.currency(code: "USD")))")
                            Text("\(tx.transactionDate) · \(tx.categoryRaw.displayTitle)").font(.caption)
                        }
                    }.recordActions(target.label, detail: target.deletionDetail, edit: { editing = target }) {
                        try target.delete(using: imports.service)
                    }
                }
            }
            Section("Balances") {
                ForEach(relatedAssets, id: \.assetSnapshotId) { asset in
                    let target = RecordDestination.asset(asset.assetSnapshotId)
                    NavigationLink { AssetEditor(asset: asset.toRecord()) } label: {
                        VStack(alignment: .leading) {
                            Text("\(asset.accountLabel) · \(asset.balance.formatted(.currency(code: "USD")))")
                            Text(asset.observedDate).font(.caption)
                        }
                    }.recordActions(target.label, detail: target.deletionDetail, edit: { editing = target }) {
                        try target.delete(using: imports.service)
                    }
                }
            }
            Section("Linked reviews") {
                ForEach(reviews.filter { targetIds.contains($0.targetId) }, id: \.reviewItemId) { review in
                    Text("\(review.statusRaw.displayTitle): \(review.question)").font(.footnote)
                }
            }
            Section("Linked anomalies") {
                ForEach(anomalies.filter { !$0.toRecord().relatedRecordIds.filter { targetIds.contains($0) }.isEmpty }, id: \.anomalyId) { anomaly in
                    Text(anomaly.summary).font(.footnote)
                }
            }
        }
        .navigationTitle(source.fileName)
        .navigationDestination(item: $editing) { target in
            switch target {
            case .transaction(let id): TransactionDetailView(transactionId: id)
            case .asset(let id):
                if let asset = relatedAssets.first(where: { $0.assetSnapshotId == id }) { AssetEditor(asset: asset.toRecord()) }
            case .source: EmptyView()
            }
        }
        .onAppear {
            cardName = source.cardName ?? ""
            layout = ScreenshotLayout(rawValue: source.screenshotLayout ?? "") ?? .automatic
            month = source.observedMonthHint ?? HeuristicScreenshotParser.statementMonth(source.rawText ?? "") ?? ""
        }
        .sheet(isPresented: $showManual) { ManualTransactionView(sourceId: source.sourceDocumentId, initialCard: source.cardName ?? "") }
        .alert("Delete entire source?", isPresented: $deleteRecord) {
            Button("Delete source", role: .destructive) {
                do { try imports.service.deleteSource(id: source.sourceDocumentId); dismiss() }
                catch { message = PrivacyRedactor.safeErrorDetail(error) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Permanently removes this source, its stored image, transactions, balances, and linked reviews. Totals update. Original Photos and correction history remain. You can import the source again afterward.") }
        .alert(isPDF ? "Delete stored PDF?" : "Delete stored image?", isPresented: $deleteImage) {
            Button(isPDF ? "Delete PDF" : "Delete image", role: .destructive) {
                do { try imports.service.deleteStoredImage(sourceId: source.sourceDocumentId); message = "Stored copy deleted. Extracted records kept." }
                catch { message = PrivacyRedactor.safeErrorDetail(error) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This permanently removes the app’s copy. Extracted records, evidence, and the original file are kept.") }
    }
}


private struct StatementPDFPreview: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

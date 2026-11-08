import SwiftUI
import SwiftData
import UIKit
import SpendingDomain

struct SourcesView: View {
    @Query(sort: \SDSourceDocument.createdTime, order: .reverse) private var sources: [SDSourceDocument]
    var body: some View {
        NavigationStack {
            List(sources, id: \.sourceDocumentId) { source in
                NavigationLink { SourceDetailView(source: source) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.fileName).font(.headline)
                        Text("\(source.sourceTypeRaw) · \(source.statusRaw)").font(.caption).foregroundStyle(.secondary)
                        if let error = source.errorSummary { Text(error).font(.caption2).foregroundStyle(.orange) }
                    }
                }
            }.navigationTitle("Sources")
        }
    }
}

struct SourceDetailView: View {
    @Environment(ImportCoordinator.self) private var imports
    let source: SDSourceDocument
    @Query private var transactions: [SDTransaction]
    @Query private var assets: [SDAssetSnapshot]
    @Query private var reviews: [SDReviewItem]
    @Query private var anomalies: [SDAnomaly]
    @State private var json = ""
    @State private var message: String?

    private var related: [SDTransaction] { transactions.filter { $0.sourceDocumentId == source.sourceDocumentId } }
    private var relatedAssets: [SDAssetSnapshot] { assets.filter { $0.sourceDocumentId == source.sourceDocumentId } }
    private var targetIds: Set<String> { Set([source.sourceDocumentId] + related.map(\.transactionId) + relatedAssets.map(\.assetSnapshotId)) }

    var body: some View {
        List {
            if let message { Section { Text(message) } }
            Section("Source") {
                LabeledContent("Status", value: source.statusRaw)
                LabeledContent("Type", value: source.sourceTypeRaw)
                if let error = source.errorSummary { Text(error).foregroundStyle(.orange) }
                if let relative = source.localRelativePath {
                    if let data = try? Data(contentsOf: SourceFileStore.url(forRelativePath: relative)), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Text("Image unavailable or removed by retention. Reimport the screenshot or attach AI JSON to recover a failed source.").font(.footnote)
                    }
                }
            }
            if source.statusRaw != ProcessingStatus.processed.rawValue {
                Section("Recovery") {
                    Button("Retry import") {
                        Task { await imports.run([ImportJob(name: source.fileName) { .retry(source.sourceDocumentId) }]); message = imports.summary }
                    }
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
            if let raw = source.rawText, !raw.isEmpty { Section("OCR / evidence text") { Text(raw).font(.footnote.monospaced()) } }
            Section("Transactions") {
                ForEach(related, id: \.transactionId) { tx in
                    NavigationLink { TransactionDetailView(transactionId: tx.transactionId) } label: {
                        VStack(alignment: .leading) {
                            Text("\(tx.merchantNormalized) · \(tx.amount.formatted(.currency(code: "USD")))")
                            Text("\(tx.transactionDate) · \(tx.categoryRaw)").font(.caption)
                        }
                    }
                }
            }
            Section("Balances") {
                ForEach(relatedAssets, id: \.assetSnapshotId) { asset in
                    VStack(alignment: .leading) {
                        Text("\(asset.accountLabel) · \(asset.balance.formatted(.currency(code: "USD")))")
                        Text(asset.evidenceText).font(.footnote)
                        Text("Balance editing is not available yet.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Linked reviews") {
                ForEach(reviews.filter { targetIds.contains($0.targetId) }, id: \.reviewItemId) { review in
                    Text("\(review.statusRaw): \(review.question)").font(.footnote)
                }
            }
            Section("Linked anomalies") {
                ForEach(anomalies.filter { !$0.toRecord().relatedRecordIds.filter { targetIds.contains($0) }.isEmpty }, id: \.anomalyId) { anomaly in
                    Text(anomaly.summary).font(.footnote)
                }
            }
        }.navigationTitle(source.fileName)
    }
}

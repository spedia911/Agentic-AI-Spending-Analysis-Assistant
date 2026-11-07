import SwiftUI
import SwiftData
import UIKit
import SpendingDomain

struct SourcesView: View {
    @Query(sort: \SDSourceDocument.createdTime, order: .reverse) private var sources: [SDSourceDocument]
    @Query private var transactions: [SDTransaction]

    var body: some View {
        NavigationStack {
            List(sources, id: \.sourceDocumentId) { source in
                NavigationLink {
                    SourceDetailView(source: source, related: transactions.filter { $0.sourceDocumentId == source.sourceDocumentId })
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.fileName).font(.headline)
                        Text("\(source.sourceTypeRaw) · \(source.statusRaw)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let error = source.errorSummary, !error.isEmpty {
                            Text(error).font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Sources")
        }
    }
}

struct SourceDetailView: View {
    let source: SDSourceDocument
    let related: [SDTransaction]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let relative = source.localRelativePath {
                    let url = SourceFileStore.url(forRelativePath: relative)
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                LabeledContent("Status", value: source.statusRaw)
                LabeledContent("Type", value: source.sourceTypeRaw)
                if let raw = source.rawText, !raw.isEmpty {
                    Text("Evidence text").font(.headline)
                    Text(raw).font(.footnote.monospaced())
                }
                Text("Transactions").font(.headline)
                ForEach(related, id: \.transactionId) { tx in
                    VStack(alignment: .leading) {
                        Text("\(tx.merchantNormalized) · \(tx.amount.formatted(.currency(code: "USD")))")
                        Text("\(tx.transactionDate) · \(tx.categoryRaw) · conf \(tx.extractionConfidence)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(source.fileName)
    }
}

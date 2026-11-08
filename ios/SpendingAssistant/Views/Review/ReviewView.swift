import SwiftUI
import SwiftData
import SpendingDomain

struct ReviewView: View {
    @Query private var reviews: [SDReviewItem]
    @Query private var sources: [SDSourceDocument]
    @Query private var assets: [SDAssetSnapshot]

    private var pending: [SDReviewItem] {
        reviews.filter { $0.statusRaw == ReviewItemStatus.pending.rawValue }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if pending.isEmpty { Text("No pending review items.").foregroundStyle(.secondary) }
                ForEach(pending, id: \.reviewItemId) { item in
                    if item.targetTypeRaw == ReviewTargetType.transaction.rawValue {
                        NavigationLink { TransactionDetailView(transactionId: item.targetId) } label: { ReviewLabel(item: item) }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ReviewLabel(item: item)
                            if item.targetTypeRaw == ReviewTargetType.assetSnapshot.rawValue {
                                Text("Balance editing is not available yet. This issue remains pending.").font(.footnote)
                            }
                            if let source = source(for: item) {
                                NavigationLink("Open source and recovery options") { SourceDetailView(source: source) }
                            } else { Text("Source evidence is unavailable.").font(.footnote) }
                        }
                    }
                }
            }.navigationTitle("Review")
        }
    }

    private func source(for item: SDReviewItem) -> SDSourceDocument? {
        let id = item.targetTypeRaw == ReviewTargetType.sourceDocument.rawValue ? item.targetId
            : assets.first(where: { $0.assetSnapshotId == item.targetId })?.sourceDocumentId
        return sources.first { $0.sourceDocumentId == id }
    }
}

private struct ReviewLabel: View {
    let item: SDReviewItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.question).font(.headline)
            Text("\(item.severityRaw) · \(item.issueTypeRaw.replacingOccurrences(of: "_", with: " "))")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct TransactionDetailView: View {
    let transactionId: String
    @Query private var transactions: [SDTransaction]
    @Query private var reviews: [SDReviewItem]
    @Query private var sources: [SDSourceDocument]

    var body: some View {
        if let transaction = transactions.first(where: { $0.transactionId == transactionId }) {
            TransactionEditor(transaction: transaction.toRecord(),
                reviews: reviews.filter { $0.targetTypeRaw == ReviewTargetType.transaction.rawValue && $0.targetId == transactionId && $0.statusRaw == ReviewItemStatus.pending.rawValue }.map { $0.toRecord() },
                source: sources.first { $0.sourceDocumentId == transaction.sourceDocumentId })
        } else { ContentUnavailableView("Transaction unavailable", systemImage: "doc.questionmark") }
    }
}

private struct TransactionEditor: View {
    @Environment(ImportCoordinator.self) private var imports
    let transaction: TransactionRecord
    let reviews: [ReviewItemRecord]
    let source: SDSourceDocument?
    @State private var date: String
    @State private var merchant: String
    @State private var amount: String
    @State private var type: TransactionType
    @State private var account: String
    @State private var remember = true
    @State private var message: String?

    init(transaction: TransactionRecord, reviews: [ReviewItemRecord], source: SDSourceDocument?) {
        self.transaction = transaction; self.reviews = reviews; self.source = source
        _date = State(initialValue: transaction.transactionDate)
        _merchant = State(initialValue: transaction.merchantNormalized)
        _amount = State(initialValue: String(transaction.amount))
        _type = State(initialValue: transaction.transactionType)
        _account = State(initialValue: transaction.accountLabel)
    }

    var body: some View {
        Form {
            if let message { Section { Text(message).accessibilityIdentifier("reviewStatus") } }
            Section("Transaction") {
                TextField("Date (YYYY-MM-DD)", text: $date).accessibilityIdentifier("transactionDate")
                TextField("Merchant", text: $merchant).accessibilityIdentifier("transactionMerchant")
                TextField("Signed amount", text: $amount).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("transactionAmount")
                Picker("Type", selection: $type) { ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Account label", text: $account)
                LabeledContent("Category", value: transaction.category.rawValue)
                LabeledContent("Validation", value: transaction.validationStatus.rawValue)
                Button("Save fields") { saveFields() }
            }
            ForEach(reviews) { review in
                Section(review.issueType.rawValue.replacingOccurrences(of: "_", with: " ")) {
                    Text(review.question)
                    switch review.issueType {
                    case .unclearCategory:
                        Toggle("Remember for similar merchants", isOn: $remember)
                        ForEach(SpendingCategory.allCases.filter { $0 != .uncategorized }, id: \.self) { category in
                            Button(category.rawValue) { apply(review, .category(category, remember: remember)) }
                        }
                    case .missingField:
                        Text("Correct the fields above, then tap Save fields.").font(.footnote)
                    case .lowConfidence, .anomaly:
                        Button("Confirm this issue") { apply(review, .confirm) }
                        Text("Save any field changes before confirming.").font(.footnote)
                    case .duplicateRisk:
                        Button("Both charges are real") { apply(review, .duplicate(.valid)) }
                        Button("Reject this duplicate", role: .destructive) { apply(review, .duplicate(.rejected)) }
                        Button("Keep pending") { apply(review, .duplicate(.needsReview)) }
                    }
                }
            }
            Section("Evidence") {
                Text(transaction.evidenceText).font(.footnote.monospaced())
                LabeledContent("Original extraction confidence", value: transaction.extractionConfidence.formatted())
                if let source { NavigationLink("Open source") { SourceDetailView(source: source) } }
            }
        }
        .disabled(imports.isBusy)
        .navigationTitle("Transaction")
    }

    private func saveFields() {
        guard let number = Double(amount.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            message = ReviewError.invalidFields.localizedDescription; return
        }
        let review = reviews.first ?? ReviewItemRecord(reviewItemId: "edit", targetType: .transaction,
            targetId: transaction.transactionId, issueType: .missingField, severity: .low, question: "Edit fields")
        apply(review, .edit(TransactionEdit(date: date.trimmingCharacters(in: .whitespacesAndNewlines), merchant: merchant,
            amount: number, type: type, account: account)))
    }

    private func apply(_ review: ReviewItemRecord, _ action: ReviewAction) {
        do {
            try imports.service.apply(review: review, action: action)
            message = "Saved. Other pending issues still need review."
        } catch { message = PrivacyRedactor.safeErrorDetail(error) }
    }
}

import SwiftUI
import SwiftData
import SpendingDomain

struct ReviewView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var reviews: [SDReviewItem]
    @Query private var transactions: [SDTransaction]
    @Query private var assets: [SDAssetSnapshot]
    @Query private var sources: [SDSourceDocument]
    @Query private var anomalies: [SDAnomaly]
    @State private var showReviewed = false
    @State private var lowestConfidence = true
    @AppStorage("showOptionalExtractionReviews") private var showOptional = false
    @State private var editing: RecordDestination?

    var body: some View {
        let txById = Dictionary(uniqueKeysWithValues: transactions.map { ($0.transactionId, $0) })
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.assetSnapshotId, $0) })
        let visible = reviews.filter {
            let pending = $0.statusRaw == ReviewItemStatus.pending.rawValue
            return pending != showReviewed && (!pending || showOptional || !$0.toRecord().isAdvisory)
        }.sorted { a, b in
            let confidenceA = confidence(for: a, transactions: txById, assets: assetsById)
            let confidenceB = confidence(for: b, transactions: txById, assets: assetsById)
            if lowestConfidence && !showReviewed && confidenceA != confidenceB { return confidenceA < confidenceB }
            return (showReviewed ? (a.resolvedAt ?? a.createdAt) : a.createdAt, a.reviewItemId)
                > (showReviewed ? (b.resolvedAt ?? b.createdAt) : b.createdAt, b.reviewItemId)
        }
        let pendingCategories = reviews.filter {
            $0.statusRaw == ReviewItemStatus.pending.rawValue
                && $0.issueTypeRaw == ReviewIssueType.unclearCategory.rawValue
        }.count
        let records = transactions.map { $0.toRecord() }
        let openDuplicatePairs = transactions.isEmpty ? 0 : DuplicateBatch.suggestedPairs(transactions: records).count
        let sameImportDuplicates = DuplicateChargeGroup.from(
            anomalies: anomalies.map { $0.toRecord() },
            transactions: records
        ).filter(\.sameSource).count

        NavigationStack {
            List {
                Section("Batch corrections") {
                    NavigationLink {
                        MerchantReviewView()
                    } label: {
                        LabeledContent("Merchant categories", value: pendingCategories > 0 ? "\(pendingCategories) open" : "Review")
                    }
                    NavigationLink {
                        BatchAnomalyReviewView()
                    } label: {
                        LabeledContent(
                            "Duplicates & anomalies",
                            value: duplicateBatchLabel(pairs: openDuplicatePairs, sameImport: sameImportDuplicates)
                        )
                    }
                    Text("Confirm merchant categories from the overview list, or resolve duplicates by import pair / same-import date comparison. Use the list below only for one-off fixes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Individual issues") {
                    Picker("Review status", selection: $showReviewed) {
                        Text("Unreviewed").tag(false); Text("Reviewed").tag(true)
                    }.pickerStyle(.segmented)
                    if visible.isEmpty {
                        Text(showReviewed ? "No completed review issues yet." : "No issues to review.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visible, id: \.reviewItemId) { item in
                        if let target = destination(for: item) {
                            NavigationLink(value: target) {
                                VStack(alignment: .leading) {
                                    if let tx = txById[item.targetId] {
                                        Text("\(tx.merchantNormalized) · \(tx.amount.formatted(.currency(code: "USD")))")
                                        Text("\(tx.transactionDate) · \(tx.transactionTypeRaw.displayTitle) · USD").font(.caption)
                                    } else if let asset = assetsById[item.targetId] {
                                        Text("\(asset.accountLabel) · \(asset.balance.formatted(.currency(code: "USD")))")
                                    }
                                    ReviewLabel(item: item)
                                    if showReviewed, let answer = item.userAnswer {
                                        Text(answer).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.recordActions(target.label, detail: target.deletionDetail, edit: { editing = target }) {
                                try target.delete(using: imports.service)
                            }
                        } else {
                            ReviewLabel(item: item)
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                Menu("Review options", systemImage: "ellipsis.circle") {
                    Picker("Sort by", selection: $lowestConfidence) {
                        Text("Lowest confidence first").tag(true); Text("Newest first").tag(false)
                    }.disabled(showReviewed)
                    Toggle("Show optional extraction checks", isOn: $showOptional).disabled(showReviewed)
                }
            }
            .navigationDestination(for: RecordDestination.self) { recordView($0) }
            .navigationDestination(item: $editing) { recordView($0) }
        }
    }

    private func duplicateBatchLabel(pairs: Int, sameImport: Int) -> String {
        if sameImport > 0 && pairs > 0 { return "\(sameImport) same-import · \(pairs) pairs" }
        if sameImport > 0 { return "\(sameImport) same-import" }
        if pairs > 0 { return "\(pairs) pairs" }
        return "Review"
    }

    private func confidence(for item: SDReviewItem, transactions: [String: SDTransaction], assets: [String: SDAssetSnapshot]) -> Double {
        if let transaction = transactions[item.targetId] {
            return item.issueTypeRaw == ReviewIssueType.unclearCategory.rawValue ? transaction.categoryConfidence : transaction.extractionConfidence
        }
        return assets[item.targetId]?.confidence ?? 0
    }

    private func destination(for item: SDReviewItem) -> RecordDestination? {
        switch ReviewTargetType(rawValue: item.targetTypeRaw) {
        case .transaction: return .transaction(item.targetId)
        case .assetSnapshot: return .asset(item.targetId)
        case .sourceDocument: return .source(item.targetId)
        case nil: return nil
        }
    }

    @ViewBuilder private func recordView(_ target: RecordDestination) -> some View {
        switch target {
        case .transaction(let id): TransactionDetailView(transactionId: id)
        case .asset(let id):
            if let asset = assets.first(where: { $0.assetSnapshotId == id }) { AssetEditor(asset: asset.toRecord()) }
        case .source(let id):
            if let source = sources.first(where: { $0.sourceDocumentId == id }) { SourceDetailView(source: source) }
        }
    }
}

private struct ReviewLabel: View {
    let item: SDReviewItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.question).font(.headline)
            Text(item.toRecord().isAdvisory ? "Optional · Low confidence" : "\(item.severityRaw.displayTitle) · \(item.issueTypeRaw.displayTitle)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct TransactionDetailView: View {
    let transactionId: String
    @Query private var transactions: [SDTransaction]
    @Query private var reviews: [SDReviewItem]
    @Query private var assets: [SDAssetSnapshot]
    @Query private var sources: [SDSourceDocument]

    var body: some View {
        if let transaction = transactions.first(where: { $0.transactionId == transactionId }) {
            TransactionEditor(transaction: transaction.toRecord(),
                reviews: reviews.filter { $0.targetTypeRaw == ReviewTargetType.transaction.rawValue && $0.targetId == transactionId && $0.statusRaw == ReviewItemStatus.pending.rawValue }.map { $0.toRecord() },
                knownAccounts: knownAccounts,
                sourceAccounts: Set(transactions.filter { $0.sourceDocumentId == transaction.sourceDocumentId }.map(\.accountLabel)),
                source: sources.first { $0.sourceDocumentId == transaction.sourceDocumentId })
        } else { ContentUnavailableView("Transaction unavailable", systemImage: "doc.questionmark") }
    }
    private var knownAccounts: [String] {
        let labels = sources.compactMap(\.cardName) + transactions.map(\.accountLabel) + assets.map(\.accountLabel)
        var seen: Set<String> = ["unknown account"]
        return labels.map { PrivacyRedactor.maskAccountLabel($0) }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

private struct TransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleteTransaction = false
    @State private var undoStack: [ReviewUndoSnapshot] = []
    @Environment(ImportCoordinator.self) private var imports
    let transaction: TransactionRecord
    let reviews: [ReviewItemRecord]
    let knownAccounts: [String]
    let sourceAccounts: Set<String>
    let source: SDSourceDocument?
    @State private var date: String
    @State private var merchant: String
    @State private var amount: String
    @FocusState private var amountFocused: Bool
    @State private var type: TransactionType
    @State private var account: String
    @State private var selectedCategory: SpendingCategory
    @State private var askRemember = false
    @State private var showDetails = false
    @State private var enterAccount = false
    @State private var matchScreenshotAccount = true
    @State private var message: String?

    init(transaction: TransactionRecord, reviews: [ReviewItemRecord], knownAccounts: [String], sourceAccounts: Set<String>, source: SDSourceDocument?) {
        self.transaction = transaction; self.reviews = reviews; self.knownAccounts = knownAccounts; self.sourceAccounts = sourceAccounts; self.source = source
        let normalized = TransactionClassification.normalize(
            type: transaction.transactionType,
            category: transaction.category,
            prefer: transaction.transactionType == .expense || transaction.transactionType == .unknown ? .category : .type
        )
        _date = State(initialValue: transaction.transactionDate)
        _merchant = State(initialValue: transaction.merchantNormalized)
        _amount = State(initialValue: String(transaction.amount))
        _type = State(initialValue: normalized.type)
        _account = State(initialValue: transaction.accountLabel)
        _selectedCategory = State(initialValue: normalized.category)
    }

    var body: some View {
        Form {
            Section("Transaction summary") {
                LabeledContent("Date") { TextField("YYYY-MM-DD", text: $date).multilineTextAlignment(.trailing).accessibilityIdentifier("transactionDate") }
                LabeledContent("Merchant") { TextField("Merchant", text: $merchant).multilineTextAlignment(.trailing).accessibilityIdentifier("transactionMerchant") }
                HStack {
                    Text("Amount")
                    TextField("Signed amount", text: $amount)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($amountFocused)
                        .accessibilityIdentifier("transactionAmount")
                    if amountFocused && !amount.isEmpty {
                        Button("Clear amount", systemImage: "xmark.circle.fill") { amount = "" }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("clearTransactionAmount")
                    }
                }
                LabeledContent("Currency", value: "USD")
                Picker("Type", selection: Binding(
                    get: { type },
                    set: { newType in
                        let normalized = TransactionClassification.normalize(type: newType, category: selectedCategory, prefer: .type)
                        type = normalized.type
                        selectedCategory = normalized.category
                    }
                )) {
                    ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue.displayTitle).tag($0) }
                }
                accountPicker
                if canMatchScreenshotAccount {
                    Toggle("Match account for this screenshot", isOn: $matchScreenshotAccount)
                    Text("Also updates the other transactions from this source.").font(.footnote).foregroundStyle(.secondary)
                }
                categoryPicker
                Text(classificationHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Review", value: requiredReviews.isEmpty ? (transaction.reviewStatus == .resolved ? "Confirmed" : "No required issues") : "\(requiredReviews.count) open")
                Button("Confirm") {
                    if categoryForConfirmation != nil { askRemember = true } else { confirm(remember: false) }
                }
                if let message { Text(message).font(.footnote).accessibilityIdentifier("reviewStatus") }
            }
            if !undoStack.isEmpty {
                Section {
                    Button("Undo last review or edit") {
                        guard let snapshot = undoStack.last else { return }
                        do {
                            try imports.service.undoReview(snapshot)
                            undoStack.removeLast()
                            date = snapshot.transaction.transactionDate; merchant = snapshot.transaction.merchantNormalized
                            amount = String(snapshot.transaction.amount); type = snapshot.transaction.transactionType
                            account = snapshot.transaction.accountLabel; selectedCategory = snapshot.transaction.category
                            message = "Restored previous values and review status, including remembered category changes."
                        } catch { message = PrivacyRedactor.safeErrorDetail(error) }
                    }
                    Text("Undo is available while this detail page stays open. You can also change the category in the summary at any time.").font(.footnote)
                }
            }
            ForEach(requiredReviews) { review in
                Section(review.issueType.rawValue.displayTitle) {
                    Text(review.question)
                    switch review.issueType {
                    case .unclearCategory:
                        Text("Review the suggested category or choose another, then tap Confirm.").font(.footnote)
                    case .missingField:
                        Text("Correct the required field above, then tap Confirm.").font(.footnote)
                    case .lowConfidence:
                        EmptyView()
                    case .anomaly:
                        Text("This transaction was flagged as unusual. Check the amount and source. Confirming accepts it as a real charge; it does not change its fields or category.").font(.footnote)
                        Button("Confirm unusual charge is correct") { apply(review, .confirm) }
                    case .duplicateRisk:
                        Button("Both charges are real") { apply(review, .duplicate(.valid)) }
                        Button("Reject this duplicate", role: .destructive) { apply(review, .duplicate(.rejected)) }
                        Text("Leave this open if you’re unsure. Rejecting excludes this row from totals but keeps it in Transactions.").font(.footnote)
                    }
                }
            }
            Section {
                Button("Delete transaction", role: .destructive) { deleteTransaction = true }
            }
        }
        .disabled(imports.isBusy)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Transaction")
        .toolbar {
            Menu("Transaction details", systemImage: "ellipsis.circle") {
                Button("Confidence and evidence") { showDetails = true }
            }.accessibilityIdentifier("transactionDetails")
        }
        .navigationDestination(isPresented: $showDetails) { evidenceDetails }
        .confirmationDialog(categoryForConfirmation.map { "Confirm category: \($0.rawValue.displayTitle)?" } ?? "Confirm category?",
                            isPresented: $askRemember, titleVisibility: .visible) {
            Button("Apply to merchant and remember") { confirm(remember: true) }
            Button("Confirm this transaction only") { confirm(remember: false) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Apply it to this transaction only, or update this merchant’s \(transaction.origin?.title.lowercased() ?? "other activity") transactions and remember it for that group.") }
        .alert("Delete transaction?", isPresented: $deleteTransaction) {
            Button("Delete", role: .destructive) {
                do { try imports.service.store.deleteTransactions(ids: [transaction.transactionId]); dismiss() }
                catch { message = PrivacyRedactor.safeErrorDetail(error) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Permanently removes this transaction and its reviews. Totals update. The source and correction history remain.") }
    }

    private var requiredReviews: [ReviewItemRecord] { reviews.filter { !$0.isAdvisory } }

    private enum AccountChoice: Hashable {
        case known(String), custom
    }

    @ViewBuilder private var accountPicker: some View {
        let unknown = "Unknown account"
        let choices = knownAccounts + (!enterAccount && !account.isEmpty && account != unknown && !knownAccounts.contains(account) ? [account] : [])
        Picker("Account", selection: Binding<AccountChoice>(
            get: { enterAccount ? .custom : .known(account.isEmpty ? unknown : account) },
            set: { choice in
                switch choice {
                case .known(let label): account = label; enterAccount = false
                case .custom:
                    if account == unknown { account = "" }
                    enterAccount = true
                }
            }
        )) {
            ForEach(choices, id: \.self) { Text($0).tag(AccountChoice.known($0)) }
            Text(unknown).tag(AccountChoice.known(unknown))
            Text("Enter account name").tag(AccountChoice.custom)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("transactionAccount")
        if enterAccount {
            TextField("Account name", text: $account)
                .accessibilityIdentifier("customTransactionAccount")
        }
    }

    private var evidenceDetails: some View {
        Form {
            Section("Extraction confidence") {
                LabeledContent("Original score", value: transaction.extractionConfidence.formatted(.percent.precision(.fractionLength(0))))
                Text("This score is a hint to check the extracted merchant, date, or amount. It is not a measured accuracy rate. Confirming a transaction does not retrain image import.").font(.footnote)
            }
            if let advisory = reviews.first(where: \.isAdvisory) {
                Section("Low confidence") {
                    Text("Optional: compare the transaction with its source when something looks off.").font(.footnote)
                    Button("Mark extraction checked") { apply(advisory, .confirm) }.disabled(imports.isBusy)
                }
            }
            Section("Evidence") {
                Text(transaction.evidenceText.isEmpty ? "No extraction evidence." : transaction.evidenceText)
                    .font(.footnote.monospaced())
                    .accessibilityIdentifier("transactionEvidenceText")
                if let source { NavigationLink("Open source") { SourceDetailView(source: source) } }
            }
        }.navigationTitle("Confidence and evidence")
    }

    private var categoryPicker: some View {
        let allowed = TransactionClassification.allowedCategories(for: type)
        return Picker("Category", selection: Binding(
            get: { selectedCategory },
            set: { newCategory in
                let normalized = TransactionClassification.normalize(type: type, category: newCategory, prefer: .category)
                type = normalized.type
                selectedCategory = normalized.category
            }
        )) {
            if allowed.contains(.uncategorized) || selectedCategory == .uncategorized {
                Text("Needs category").tag(SpendingCategory.uncategorized)
            }
            ForEach(allowed.filter { $0 != .uncategorized }, id: \.self) {
                Text($0.rawValue.displayTitle).tag($0)
            }
        }.pickerStyle(.menu).accessibilityIdentifier("transactionCategory")
    }

    private var classificationHint: String {
        switch type {
        case .income:
            return "Income type locks category to Income. Cash flow uses type, not spending categories."
        case .transfer:
            return "Transfers move money between your accounts and are excluded from spending."
        case .fee:
            return "Fee type locks category to Fees."
        case .payment:
            return "Payments can be a card payoff (Transfer) or a bill that still counts as spending."
        case .refund:
            return "Refunds reduce net cash outflow; pick a spending purpose only if you want attribution."
        case .expense, .unknown:
            return "Type is the cash-flow role. Category is the spending purpose (groceries, dining, …)."
        }
    }

    private var categoryForConfirmation: SpendingCategory? {
        guard selectedCategory != .uncategorized else { return nil }
        let needsCategory = requiredReviews.contains { $0.issueType == .unclearCategory }
        let merchantChanged = Normalizer.normalizeMerchant(merchant) != transaction.merchantNormalized
        return needsCategory || selectedCategory != transaction.category || merchantChanged || type != transaction.transactionType
            ? selectedCategory : nil
    }

    private var canMatchScreenshotAccount: Bool {
        let label = PrivacyRedactor.maskAccountLabel(account)
        return source?.mimeType.hasPrefix("image/") == true && label != "Unknown account"
            && (label != transaction.accountLabel || sourceAccounts.contains(where: { $0 != label }))
    }

    private func confirm(remember: Bool) {
        guard let number = Normalizer.normalizeAmountText(amount) else {
            message = ReviewError.invalidFields.localizedDescription; return
        }
        do {
            let match = canMatchScreenshotAccount && matchScreenshotAccount
            let snapshot = try imports.service.reviewSnapshot(transaction, accountSource: match,
                merchant: remember ? Normalizer.normalizeMerchant(merchant) : nil)
            let changed = try imports.service.editTransaction(id: transaction.transactionId,
                fields: TransactionEdit(date: date.trimmingCharacters(in: .whitespacesAndNewlines), merchant: merchant,
                    amount: number, type: type, account: PrivacyRedactor.maskAccountLabel(account)),
                category: categoryForConfirmation, rememberCategory: remember, confirm: true, matchSourceAccount: match)
            if changed { undoStack.append(snapshot) }
            dismiss()
        } catch { message = PrivacyRedactor.safeErrorDetail(error) }
    }

    private func apply(_ review: ReviewItemRecord, _ action: ReviewAction) {
        do {
            let snapshot = try imports.service.reviewSnapshot(transaction)
            try imports.service.apply(review: review, action: action)
            undoStack.append(snapshot)
            message = "Saved. Other pending issues still need review."
        } catch { message = PrivacyRedactor.safeErrorDetail(error) }
    }
}

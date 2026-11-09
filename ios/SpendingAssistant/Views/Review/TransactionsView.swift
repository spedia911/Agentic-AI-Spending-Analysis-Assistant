import SwiftUI
import SwiftData
import SpendingDomain

struct TransactionsView: View {
    private let spendingOnly: Bool
    @State private var filters: TransactionFilters
    @State private var showFilters = false

    init(month: String? = nil, category: SpendingCategory? = nil) {
        spendingOnly = month != nil
        _filters = State(initialValue: TransactionFilters(category: category, dateMode: month == nil ? .all : .month, month: month ?? ""))
    }
    @Query(sort: \SDTransaction.transactionDate, order: .reverse) private var transactions: [SDTransaction]
    @Environment(ImportCoordinator.self) private var imports
    @AppStorage("confirmedTransactionSwipeDelete") private var confirmedSwipe = false
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var deleting: Set<String> = []
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var query = ""
    @State private var adding = false
    @State private var editing: String?
    var body: some View {
        let visible = transactions.filter { tx in
            let row = tx.toRecord()
            return filters.includes(row)
                && (query.isEmpty || (row.merchantNormalized + " " + row.accountLabel).localizedCaseInsensitiveContains(query))
                && (!spendingOnly || (row.validationStatus != .rejected && row.amount.isFinite
                    && row.observedMonth == String(row.transactionDate.prefix(7))
                    && Validator.isValidDate(row.transactionDate) && SpendingMath.spendingAmount(row) > 0))
        }
        let visibleSelection = selected.intersection(visible.map(\.transactionId))
        List {
            if spendingOnly { Text("Spending transactions").font(.caption).foregroundStyle(.secondary) }
            if visible.isEmpty {
                Text(transactions.isEmpty ? "Import a screenshot or add your first transaction." : "No transactions match these filters.")
                    .foregroundStyle(.secondary)
            }
            ForEach(visible, id: \.transactionId) { tx in
                if selecting {
                    Button { if !selected.insert(tx.transactionId).inserted { selected.remove(tx.transactionId) } } label: {
                        HStack {
                            Image(systemName: selected.contains(tx.transactionId) ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                            rowDetails(tx)
                        }
                        .accessibilityAddTraits(selected.contains(tx.transactionId) ? .isSelected : [])
                    }
                } else {
                    NavigationLink { TransactionDetailView(transactionId: tx.transactionId) } label: {
                        rowDetails(tx)
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash") {
                            deleting = [tx.transactionId]
                            if confirmedSwipe { performDelete() } else { confirmDelete = true }
                        }.tint(.red)
                        Button("Edit", systemImage: "pencil") { editing = tx.transactionId }.tint(.blue)
                    }
                }
            }
        }
        .disabled(imports.isBusy)
        .alert("Delete transactions?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Permanently delete \(deleting.count) transaction(s) and their reviews. Totals will update. Sources and correction history remain. \(selecting ? "Bulk deletion always asks for confirmation." : "After this, tapping Delete on a swiped row will delete it immediately.")") }
        .alert("Deletion failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .navigationTitle("Transactions")
        .navigationDestination(item: $editing) { TransactionDetailView(transactionId: $0) }
        .searchable(text: $query, prompt: "Quick search merchant or account")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(selecting ? "Done" : "Select") { selecting.toggle(); selected = [] } }
            ToolbarItem(placement: .primaryAction) {
                if selecting {
                    Button("Delete selected (\(visibleSelection.count))", role: .destructive) { deleting = visibleSelection; confirmDelete = true }.disabled(visibleSelection.isEmpty)
                } else {
                    HStack {
                        Button(filters.isActive ? "Filters active" : "Filters", systemImage: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                            showFilters = true
                        }.accessibilityIdentifier("transactionFilters")
                        Button("Add transaction", systemImage: "plus") { adding = true }
                    }
                }
            } }
        .sheet(isPresented: $showFilters) {
            TransactionFiltersView(
                initial: filters,
                months: Array(Set(transactions.map(\.observedMonth).filter { Normalizer.isValidStatementDateHint($0) && $0.count == 7 })).sorted(by: >),
                accounts: Array(Set(transactions.map(\.accountLabel))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            ) {
                filters = $0
                selected = []
            }
        }
        .onChange(of: query) { _, _ in selected = [] }
        .sheet(isPresented: $adding) { ManualTransactionView() }
    }
    private func rowDetails(_ tx: SDTransaction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(tx.merchantNormalized); Spacer(); Text(tx.amount, format: .currency(code: "USD")) }
            Text("\(tx.transactionDate) · \(tx.accountLabel) · \(tx.categoryRaw.displayTitle)").font(.caption).foregroundStyle(.secondary)
            if tx.validationStatusRaw == ValidationStatus.rejected.rawValue { Text("Rejected — excluded from totals").font(.caption).foregroundStyle(.orange) }
        }
    }

    private func performDelete() {
        do {
            try imports.service.store.deleteTransactions(ids: deleting)
            if !selecting { confirmedSwipe = true }
            selected.subtract(deleting)
        } catch { self.error = PrivacyRedactor.safeErrorDetail(error) }
    }
}

import SwiftUI
import SwiftData
import SpendingDomain

private var merchantAssignableCategories: [SpendingCategory] {
    TransactionClassification.spendingPurposes + [.income, .transfer]
}

private struct MerchantGroup: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    let count: Int
    let origin: TransactionOrigin?
    let categories: [String]
    let needsReview: Bool
    let totalAmount: Double

    var estimatedCategory: SpendingCategory {
        if let raw = categories.first(where: { $0 != SpendingCategory.uncategorized.rawValue }),
           let category = SpendingCategory(rawValue: raw),
           category != .uncategorized {
            return category
        }
        return .miscellaneous
    }
}

struct MerchantReviewView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var transactions: [SDTransaction]
    @Query private var reviews: [SDReviewItem]
    @State private var search = ""
    @State private var pendingOnly = true
    @State private var drafts: [String: SpendingCategory] = [:]
    @State private var confirmKeys: Set<String> = []
    @State private var confirmBatch = false
    @State private var samplesGroup: MerchantGroup?
    @State private var message: String?

    var body: some View {
        let groups = merchantGroups()
        let ready = groups.filter { (drafts[$0.key] ?? $0.estimatedCategory) != .uncategorized }
        List {
            Section {
                Text("Pick a spending purpose (or Income / Transfer / Fees). Choosing Income or Transfer also updates transaction type so cash flow stays consistent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Only merchants needing review", isOn: $pendingOnly)
            }
            if let message { Text(message).font(.footnote) }

            if !ready.isEmpty {
                Section {
                    Button("Confirm categories for \(ready.count) merchants") {
                        confirmKeys = Set(ready.map(\.key))
                        confirmBatch = true
                    }
                    .disabled(imports.isBusy)
                }
            }

            Section(pendingOnly ? "Merchants needing a category" : "All merchants") {
                if groups.isEmpty {
                    Text(pendingOnly ? "No merchants need category review." : "No merchants yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    merchantRow(group)
                }
            }
        }
        .navigationTitle("Merchant categories")
        .searchable(text: $search, prompt: "Merchant name")
        .task(id: groups.map(\.key).joined(separator: "\u{1e}")) { seedDrafts(groups) }
        .navigationDestination(item: $samplesGroup) { group in
            MerchantCategoryDetailView(group: group, initialCategory: drafts[group.key] ?? group.estimatedCategory)
        }
        .confirmationDialog(
            confirmKeys.count == 1 ? "Confirm this merchant category?" : "Confirm \(confirmKeys.count) merchant categories?",
            isPresented: $confirmBatch,
            titleVisibility: .visible
        ) {
            Button("Apply and remember") {
                applyConfirmed(groups: groups)
            }
            Button("Cancel", role: .cancel) { confirmKeys = [] }
        } message: {
            Text("Updates every matching transaction and remembers the merchant → category mapping for future imports.")
        }
    }

    @ViewBuilder
    private func merchantRow(_ group: MerchantGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name).font(.headline)
                    Text("\(group.origin?.title ?? "Other activity") · \(group.count) transactions · \(group.totalAmount.formatted(.currency(code: "USD")))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if group.categories.count > 1 {
                        Text("Currently mixed: " + group.categories.map(\.displayTitle).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if group.needsReview {
                        Text("Suggested · needs confirm")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 8)
                Button("Samples") { samplesGroup = group }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

            HStack {
                Picker("Category", selection: Binding(
                    get: { drafts[group.key] ?? group.estimatedCategory },
                    set: { drafts[group.key] = $0 }
                )) {
                    ForEach(merchantAssignableCategories, id: \.self) { category in
                        Text(category.rawValue.displayTitle).tag(category)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("merchantOverviewCategory-\(group.key)")

                Button("Confirm") {
                    confirmKeys = [group.key]
                    confirmBatch = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("merchantConfirm-\(group.key)")
                .disabled(imports.isBusy || (drafts[group.key] ?? group.estimatedCategory) == .uncategorized)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.name)
    }

    private func seedDrafts(_ groups: [MerchantGroup]) {
        for group in groups where drafts[group.key] == nil {
            drafts[group.key] = group.estimatedCategory
        }
    }

    private func applyConfirmed(groups: [MerchantGroup]) {
        let payload: [(name: String, origin: TransactionOrigin?, category: SpendingCategory)] = groups.compactMap { group in
            guard confirmKeys.contains(group.key) else { return nil }
            let category = drafts[group.key] ?? group.estimatedCategory
            guard category != .uncategorized else { return nil }
            return (group.name, group.origin, category)
        }
        guard !payload.isEmpty else { return }
        do {
            let byCategory = Dictionary(grouping: payload, by: \.category)
            for (category, merchants) in byCategory {
                _ = try imports.service.setMerchantCategories(
                    merchants.map { (name: $0.name, origin: $0.origin) },
                    category: category
                )
            }
            message = "Confirmed \(payload.count) merchant \(payload.count == 1 ? "category" : "categories")."
            confirmKeys = []
        } catch {
            message = PrivacyRedactor.safeErrorDetail(error)
        }
    }

    private func merchantGroups() -> [MerchantGroup] {
        let pendingIds = Set(reviews.filter {
            $0.targetTypeRaw == ReviewTargetType.transaction.rawValue
                && $0.issueTypeRaw == ReviewIssueType.unclearCategory.rawValue
                && $0.statusRaw == ReviewItemStatus.pending.rawValue
        }.map(\.targetId))
        let grouped = Dictionary(grouping: transactions.filter {
            $0.validationStatusRaw != ValidationStatus.rejected.rawValue
                && $0.merchantNormalized != "Unknown merchant"
                && !Categorizer.merchantKey($0.merchantNormalized).isEmpty
        }) {
            Categorizer.scopedMerchantKey($0.merchantNormalized, origin: $0.originRaw.flatMap(TransactionOrigin.init(rawValue:)))
        }
        return grouped.keys.sorted().compactMap { key -> MerchantGroup? in
            guard let rows = grouped[key],
                  let name = rows.map(\.merchantNormalized).min(by: { $0.localizedStandardCompare($1) == .orderedAscending })
            else { return nil }
            let needsReview = rows.contains(where: { pendingIds.contains($0.transactionId) })
                || rows.contains(where: { $0.categoryRaw == SpendingCategory.uncategorized.rawValue })
            guard !pendingOnly || needsReview else { return nil }
            guard search.isEmpty || name.localizedCaseInsensitiveContains(search) else { return nil }
            let origin = rows.first?.originRaw.flatMap(TransactionOrigin.init(rawValue:))
            return MerchantGroup(
                key: key,
                name: name,
                count: rows.count,
                origin: origin,
                categories: Array(Set(rows.map(\.categoryRaw))).sorted(),
                needsReview: needsReview,
                totalAmount: rows.reduce(0) { $0 + abs($1.amount) }
            )
        }
    }
}

private struct MerchantCategoryDetailView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [SDTransaction]
    let group: MerchantGroup
    let initialCategory: SpendingCategory
    @State private var category: SpendingCategory = .miscellaneous
    @State private var confirm = false
    @State private var message: String?

    private var rows: [SDTransaction] {
        transactions.filter {
            $0.validationStatusRaw != ValidationStatus.rejected.rawValue
                && Categorizer.scopedMerchantKey(
                    $0.merchantNormalized,
                    origin: $0.originRaw.flatMap(TransactionOrigin.init(rawValue:))
                ) == group.key
        }
        .sorted { ($0.transactionDate, $0.transactionId) > ($1.transactionDate, $1.transactionId) }
    }

    var body: some View {
        List {
            Section("Merchant") {
                LabeledContent("Name", value: group.name)
                LabeledContent("Activity", value: group.origin?.title ?? "Other activity")
                LabeledContent("Transactions", value: "\(group.count)")
                Picker("Category", selection: $category) {
                    ForEach(merchantAssignableCategories, id: \.self) { value in
                        Text(value.rawValue.displayTitle).tag(value)
                    }
                }
                .accessibilityIdentifier("merchantBatchCategory")
                Button("Apply \(category.rawValue.displayTitle) to all \(group.count)") {
                    confirm = true
                }
                .disabled(imports.isBusy)
                if let message { Text(message).font(.footnote) }
            }
            Section("Sample transactions") {
                ForEach(rows.prefix(12), id: \.transactionId) { tx in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(tx.transactionDate) · \(tx.amount.formatted(.currency(code: "USD")))")
                        Text("\(tx.accountLabel) · \(tx.categoryRaw.displayTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Samples")
        .onAppear { category = initialCategory }
        .confirmationDialog(
            "Update merchant category?",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("Apply and remember") {
                do {
                    _ = try imports.service.setMerchantCategory(group.name, origin: group.origin, category: category)
                    message = "Updated \(group.name) to \(category.rawValue.displayTitle)."
                    dismiss()
                } catch {
                    message = PrivacyRedactor.safeErrorDetail(error)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apply \(category.rawValue.displayTitle) to \(group.count) transactions from \(group.name) in \(group.origin?.title.lowercased() ?? "other activity") and remember it for that group.")
        }
    }
}

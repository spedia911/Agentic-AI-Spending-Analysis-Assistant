import SwiftUI
import SwiftData
import SpendingDomain

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var reviews: [SDReviewItem]
    @AppStorage("enableFoundationModels") private var enableFoundationModels = true
    @State private var remember = true
    @State private var message: String?

    private var pending: [SDReviewItem] {
        reviews.filter { $0.statusRaw == ReviewItemStatus.pending.rawValue }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Remember category for similar merchants", isOn: $remember)
                if pending.isEmpty {
                    Text("No pending review items.")
                        .foregroundStyle(.secondary)
                }
                ForEach(pending, id: \.reviewItemId) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.question).font(.headline)
                        Text(item.issueTypeRaw.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let options = (try? JSONDecoder().decode([String].self, from: Data(item.suggestedOptionsJSON.utf8))) ?? []
                        FlowOptions(options: options.isEmpty ? SpendingCategory.allCases.filter { $0 != .uncategorized }.map(\.rawValue) : options) { option in
                            apply(item: item, option: option)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Review")
        }
    }

    private func apply(item: SDReviewItem, option: String) {
        do {
            let store = LocalStore(modelContext: modelContext)
            let service = ImportPipelineService(store: store, enableFoundationModels: enableFoundationModels)
            if let category = SpendingCategory(rawValue: option) {
                try service.applyCategory(review: item.toRecord(), category: category, remember: remember)
                message = "Saved \(option)."
            } else if let status = ValidationStatus(rawValue: option) {
                let applied = CorrectionApplier.applyValidationStatus(
                    transactionId: item.targetId,
                    status: status,
                    transactions: try store.allTransactions(),
                    reviewItems: try store.allReviews()
                )
                for tx in applied.transactions { store.upsert(transaction: tx) }
                for review in applied.reviewItems { store.upsert(review: review) }
                for correction in applied.corrections { store.insert(correction: correction) }
                try store.save()
                try store.rebuildDerived()
                message = "Updated validation to \(option)."
            } else {
                message = "Unsupported option."
            }
        } catch {
            message = PrivacyRedactor.safeErrorDetail(error)
        }
    }
}

private struct FlowOptions: View {
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        FlexibleWrap(options: options, onSelect: onSelect)
    }
}

private struct FlexibleWrap: View {
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(option) { onSelect(option) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

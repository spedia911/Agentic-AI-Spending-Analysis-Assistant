import SwiftUI
import SpendingDomain

extension View {
    func recordActions(_ name: String, detail: String, edit: (() -> Void)?, delete: @escaping () throws -> Void) -> some View {
        modifier(RecordRowActions(name: name, detail: detail, edit: edit, delete: delete))
    }
}

private struct RecordRowActions: ViewModifier {
    @Environment(ImportCoordinator.self) private var imports
    let name: String
    let detail: String
    let edit: (() -> Void)?
    let delete: () throws -> Void
    @State private var confirm = false
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .swipeActions(allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash") { confirm = true }.tint(.red).disabled(imports.isBusy)
                if let edit { Button("Edit", systemImage: "pencil", action: edit).tint(.blue) }
            }
            .alert("Delete \(name)?", isPresented: $confirm) {
                Button("Delete", role: .destructive) {
                    do { try delete() } catch { failure = PrivacyRedactor.safeErrorDetail(error) }
                }.disabled(imports.isBusy)
                Button("Cancel", role: .cancel) {}
            } message: { Text(detail) }
            .alert("Deletion failed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
    }
}

enum RecordDestination: Hashable {
    case transaction(String), source(String), asset(String)

    var label: String {
        switch self {
        case .transaction: "transaction"
        case .source: "source and all its records"
        case .asset: "balance snapshot"
        }
    }

    var deletionDetail: String {
        switch self {
        case .transaction: "Removes this transaction and its reviews. The source remains."
        case .source: "Removes the app’s image and evidence, linked transactions, balances, and reviews. The original in Photos remains."
        case .asset: "Removes this balance and its reviews from asset trends. The source remains."
        }
    }

    @MainActor func delete(using service: ImportPipelineService) throws {
        switch self {
        case .transaction(let id): try service.store.deleteTransactions(ids: [id])
        case .source(let id): try service.deleteSource(id: id)
        case .asset(let id): try service.store.deleteAsset(id: id)
        }
    }
}

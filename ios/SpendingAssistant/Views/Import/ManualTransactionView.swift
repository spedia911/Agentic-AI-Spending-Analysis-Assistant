import SwiftUI
import SpendingDomain

struct ManualTransactionView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.dismiss) private var dismiss
    var sourceId: String? = nil
    var initialCard: String = ""
    @State private var date = Date()
    @State private var merchant = ""
    @State private var amount = ""
    @State private var card = ""
    @State private var type: TransactionType = .expense
    @State private var category: SpendingCategory = .uncategorized
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Spending or activity") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Merchant", text: $merchant).accessibilityIdentifier("manualMerchant")
                    TextField("Amount", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("manualAmount")
                    Text("Enter a positive amount; the selected transaction type determines its sign.").font(.footnote)
                    Picker("Type", selection: Binding(
                        get: { type },
                        set: { newType in
                            let normalized = TransactionClassification.normalize(type: newType, category: category, prefer: .type)
                            type = normalized.type
                            category = normalized.category == .uncategorized && newType == .expense ? .uncategorized : normalized.category
                        }
                    )) {
                        ForEach(TransactionType.allCases.filter { $0 != .unknown }, id: \.self) { Text($0.rawValue.displayTitle).tag($0) }
                    }
                    TextField("Card / account", text: $card)
                    Picker("Category", selection: Binding(
                        get: { category },
                        set: { newCategory in
                            let normalized = TransactionClassification.normalize(type: type, category: newCategory, prefer: .category)
                            type = normalized.type
                            category = normalized.category
                        }
                    )) {
                        if TransactionClassification.allowedCategories(for: type).contains(.uncategorized) {
                            Text("Suggest a category").tag(SpendingCategory.uncategorized)
                        }
                        ForEach(TransactionClassification.allowedCategories(for: type).filter { $0 != .uncategorized }, id: \.self) {
                            Text($0.rawValue.displayTitle).tag($0)
                        }
                    }
                    Text("Type is income / expense / transfer. Category is only a spending purpose unless type is Income, Transfer, or Fee.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Button("Save transaction") { save() }.disabled(imports.isBusy)
                    .accessibilityIdentifier("saveManualTransaction")
            }
            .navigationTitle("Add transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(imports.isBusy) }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { card = initialCard }
        }
    }
    private func save() {
        guard let value = Normalizer.normalizeAmountText(amount), value.isFinite, value > 0 else {
            error = "Enter a positive amount."; return
        }
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        do {
            try imports.service.addManualTransaction(TransactionEdit(date: f.string(from: date), merchant: merchant,
                amount: type == .income || type == .refund ? value : -value, type: type, account: card), category: category, sourceId: sourceId)
            dismiss()
        } catch { self.error = PrivacyRedactor.safeErrorDetail(error) }
    }
}

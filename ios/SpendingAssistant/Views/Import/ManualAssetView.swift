import SwiftUI
import SpendingDomain

struct ManualAssetView: View {
    var initialAccountId = ""
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var amount = ""
    @State private var balanceType: BalanceType = .checking
    @State private var accountId = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account balance") {
                    DatePicker("Observed date", selection: $date, displayedComponents: .date)
                    AccountSelector(accountId: $accountId, forBalance: true)
                    TextField("Balance (selected currency)", text: $amount)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("manualAssetBalance")
                    Picker("Account type", selection: $balanceType) {
                        ForEach(BalanceType.allCases.filter { $0.tracksAsAsset }, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    Text("Balances are stored as assets. Sparse updates are carried forward for up to one month on the Home chart.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Button("Save balance") { save() }
                    .disabled(imports.isBusy || accountId.isEmpty)
                    .accessibilityIdentifier("saveManualAsset")
            }
            .navigationTitle("Add balance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(imports.isBusy || accountId.isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .task { accountId = initialAccountId }
        }
    }

    private func save() {
        guard let value = Normalizer.normalizeAmountText(amount), value.isFinite else {
            error = "Enter a valid balance amount."
            return
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        do {
            try imports.service.addManualAsset(
                accountLabel: "",
                observedDate: formatter.string(from: date),
                balance: value,
                balanceType: balanceType, accountId: accountId
            )
            dismiss()
        } catch {
            self.error = PrivacyRedactor.safeErrorDetail(error)
        }
    }
}

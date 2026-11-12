import SwiftUI
import SwiftData
import SpendingDomain

struct AssetEditor: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.dismiss) private var dismiss
    @Query private var sources: [SDSourceDocument]
    @Query private var accounts: [SDAccount]
    @State private var asset: AssetSnapshotRecord
    @State private var accountId: String
    @State private var amount: String
    @State private var confirmCurrency = false
    @State private var error: String?

    init(asset: AssetSnapshotRecord) {
        _asset = State(initialValue: asset)
        _accountId = State(initialValue: asset.accountId ?? "")
        _amount = State(initialValue: String(asset.balance))
    }

    var body: some View {
        Form {
            Section("Balance summary") {
                AccountSelector(accountId: $accountId, suggestedName: asset.accountLabel,
                                suggestedCurrency: CurrencyEvidence.read(asset.evidenceText).code, forBalance: true)
                if let account = accounts.first(where: { $0.accountId == accountId }),
                   asset.confirmedCurrencyCode != account.currencyCode,
                   asset.currencyEvidence.conflicts(with: account.currencyCode) {
                    Text("Check the source before confirming the balance currency.").font(.footnote)
                    Toggle("Confirm balance is in \(account.currencyCode)", isOn: $confirmCurrency)
                }
                if accountId.isEmpty {
                    Text("Unmapped balances stay out of valuations until you choose an account and currency.").font(.footnote).foregroundStyle(.secondary)
                }
                TextField("Date (YYYY-MM-DD)", text: $asset.observedDate)
                TextField("Balance (record currency)", text: $amount).keyboardType(.numbersAndPunctuation)
                Picker("Balance type", selection: $asset.balanceType) {
                    ForEach(BalanceType.allCases.filter { $0 != .unknown }, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Check the amount, date and account against the source before saving. Saving revalidates and completes this balance review.").font(.footnote)
                Button("Save reviewed balance") { save() }
            }
            Section("Evidence") {
                Text(asset.evidenceText)
                if let source = sources.first(where: { $0.sourceDocumentId == asset.sourceDocumentId }) {
                    NavigationLink("Open source") { SourceDetailView(source: source) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .disabled(imports.isBusy)
        .navigationTitle("Balance")
        .onChange(of: accountId) { _, _ in confirmCurrency = false }
    }

    private func save() {
        guard let value = Normalizer.normalizeAmountText(amount), value.isFinite,
              Validator.isValidDate(asset.observedDate), !accountId.isEmpty,
              asset.balanceType != .unknown,
              let account = accounts.first(where: { $0.accountId == accountId }) else {
            error = "Enter a valid date, mapped account, balance and balance type."
            return
        }
        asset.observedMonth = String(asset.observedDate.prefix(7))
        asset.balance = value
        asset.accountId = account.accountId
        asset.currencyCode = account.currencyCode
        asset.accountLabel = account.label
        if confirmCurrency { asset.confirmedCurrencyCode = account.currencyCode }
        do { try imports.service.store.saveReviewedAsset(asset); dismiss() }
        catch { self.error = PrivacyRedactor.safeErrorDetail(error) }
    }
}

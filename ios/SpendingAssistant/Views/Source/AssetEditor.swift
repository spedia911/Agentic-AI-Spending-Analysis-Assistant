import SwiftUI
import SwiftData
import SpendingDomain

struct AssetEditor: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.dismiss) private var dismiss
    @Query private var sources: [SDSourceDocument]
    @State private var asset: AssetSnapshotRecord
    @State private var amount: String
    @State private var error: String?

    init(asset: AssetSnapshotRecord) {
        _asset = State(initialValue: asset)
        _amount = State(initialValue: String(asset.balance))
    }

    var body: some View {
        Form {
            Section("Balance summary") {
                TextField("Account", text: $asset.accountLabel)
                TextField("Date (YYYY-MM-DD)", text: $asset.observedDate)
                TextField("Balance (USD)", text: $amount).keyboardType(.numbersAndPunctuation)
                Picker("Balance type", selection: $asset.balanceType) {
                    ForEach(BalanceType.allCases.filter { $0 != .unknown }, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Check the amount, date and account against the source before saving. Saving completes this balance review.").font(.footnote)
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
    }

    private func save() {
        guard let value = Normalizer.normalizeAmountText(amount), value.isFinite,
              Validator.isValidDate(asset.observedDate), !asset.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              asset.balanceType != .unknown else {
            error = "Enter a valid date, account, balance and balance type."
            return
        }
        asset.observedMonth = String(asset.observedDate.prefix(7))
        asset.balance = value
        asset.accountLabel = PrivacyRedactor.maskAccountLabel(asset.accountLabel)
        do { try imports.service.store.saveReviewedAsset(asset); dismiss() }
        catch { self.error = PrivacyRedactor.safeErrorDetail(error) }
    }
}

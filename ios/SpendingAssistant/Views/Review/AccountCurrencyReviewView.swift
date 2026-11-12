import SwiftUI
import SwiftData
import SpendingDomain

struct AccountCurrencyReviewView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var transactions: [SDTransaction]
    @Query private var assets: [SDAssetSnapshot]
    @Query private var sources: [SDSourceDocument]
    @Query private var accounts: [SDAccount]
    @AppStorage("defaultCurrencyCode") private var defaultCurrency = ""
    @State private var batchSource: String?
    @State private var destination = ""
    @State private var message: String?

    var body: some View {
        let rows = transactions.map { $0.toRecord() }.filter { $0.validationStatus != .rejected && (!Eligibility.validCurrency($0.billedCurrencyCode) || $0.hasCurrencyConflict) }
        let balances = assets.map { $0.toRecord() }.filter {
            !Eligibility.mapped($0.accountId, $0.currencyCode) || $0.hasCurrencyConflict
        }
        let groups = Set(rows.map(\.sourceDocumentId) + balances.map(\.sourceDocumentId)).sorted()
        List {
            if let message { Text(message).font(.footnote) }
            if groups.isEmpty {
                ContentUnavailableView("Accounts and currencies are up to date", systemImage: "checkmark.circle")
            }
            ForEach(groups, id: \.self) { id in
                let source = sources.first { $0.sourceDocumentId == id }
                let sourceRows = rows.filter { $0.sourceDocumentId == id }
                let sourceBalances = balances.filter { $0.sourceDocumentId == id }
                let unmappedRows = sourceRows.filter { $0.accountId == nil }
                let unmappedBalances = sourceBalances.filter { $0.accountId == nil }
                let count = unmappedRows.count + unmappedBalances.count
                Section(source?.fileName ?? "Source") {
                    ForEach(sourceRows) { row in
                        NavigationLink { TransactionDetailView(transactionId: row.id) } label: {
                            details(row.merchantNormalized, label: row.accountLabel, accountId: row.accountId, evidence: row.evidenceText,
                                    suggestion: suggestion(row.currencyEvidence, assigned: row.defaultBilledCurrency, accountId: row.accountId))
                        }
                    }
                    ForEach(sourceBalances) { row in
                        NavigationLink { AssetEditor(asset: row) } label: {
                            details("Balance", label: row.accountLabel, accountId: row.accountId, evidence: row.evidenceText,
                                    suggestion: suggestion(row.currencyEvidence, accountId: row.accountId))
                        }
                    }
                    if count > 1 {
                        if batchSource == id {
                            AccountSelector(accountId: $destination, suggestedName: source?.cardName ?? "",
                                            suggestedCurrency: CurrencyEvidence.read(source?.rawText ?? "").code, allowsUnmapped: false)
                            Button("Map \(count) unmapped records from this source") {
                                do {
                                    try imports.service.store.mapRecords(transactions: Set(unmappedRows.map(\.id)),
                                        assets: Set(unmappedBalances.map(\.id)), accountId: destination)
                                    batchSource = nil
                                } catch { message = PrivacyRedactor.safeErrorDetail(error) }
                            }.disabled(destination.isEmpty)
                            Button("Cancel", role: .cancel) { batchSource = nil }
                        } else {
                            Button("Choose account for \(count) unmapped records…") {
                                destination = source?.importAccountId ?? ""
                                batchSource = id
                            }
                        }
                    }
                }
            }
        }
        .disabled(imports.isBusy)
        .navigationTitle("Account & currency")
    }

    private func suggestion(_ evidence: CurrencyEvidence, assigned: String? = nil, accountId: String?) -> String {
        if evidence == .conflicting { return "Currency evidence conflicts. Check the billed amount." }
        if let code = evidence.code { return "Billed currency evidence: \(code)" }
        if let assigned { return "Assigned currency: \(assigned)" }
        if let account = accounts.first(where: { $0.accountId == accountId }) { return "Account currency: \(account.currencyCode)" }
        if !defaultCurrency.isEmpty { return "Default currency suggestion: \(defaultCurrency)" }
        return "Check the source for the billed currency."
    }

    private func details(_ title: String, label: String, accountId: String?, evidence: String, suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(accountId == nil ? "Unmapped · \(label)" : "Check billed currency · \(label)").font(.caption)
            Text(suggestion).font(.caption)
            if !evidence.isEmpty { Text(evidence).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
        }
    }
}

import SwiftUI
import SwiftData
import SpendingDomain

struct AccountSelector: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query(sort: \SDAccount.label) private var accounts: [SDAccount]
    @AppStorage("defaultCurrencyCode") private var defaultCurrency = ""
    @Binding var accountId: String
    var suggestedName = ""
    var suggestedCurrency: String?
    var allowsUnmapped = true
    var identifier = "accountCurrencyPicker"
    var forBalance = false
    @State private var creating = false
    @State private var label = ""
    @State private var currency = ""
    @State private var error: String?

    var body: some View {
        let selected = accounts.first { $0.accountId == accountId }
        Menu {
            ForEach(accounts, id: \.accountId) { row in
                Button("\(row.label) · \(displayCurrency(row))") { accountId = row.accountId }
            }
            Button("Create account…", systemImage: "plus") {
                label = PrivacyRedactor.maskAccountLabel(suggestedName.isEmpty ? selected?.label : suggestedName)
                if label == "Unknown account" { label = "" }
                currency = suggestedCurrency ?? selected.map(displayCurrency) ?? defaultCurrency
                error = nil
                creating = true
            }
            if allowsUnmapped, selected != nil {
                Button(forBalance || defaultCurrency.isEmpty ? "Leave unmapped" : "Use default currency") { accountId = "" }
            }
        } label: {
            LabeledContent("Account", value: selected.map { "\($0.label) · \(displayCurrency($0))" } ?? (forBalance || defaultCurrency.isEmpty ? "Choose account" : "Optional · \(defaultCurrency)"))
        }
        .accessibilityIdentifier(identifier)
        .sheet(isPresented: $creating) {
            NavigationStack {
                Form {
                    TextField("Account name", text: $label).accessibilityIdentifier("newAccountName")
                    CurrencySelector(title: "Account currency", selection: $currency)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle("New account")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creating = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create account") {
                            do {
                                accountId = try imports.service.store.saveAccount(label: label, currency: currency)
                                creating = false
                            } catch { self.error = PrivacyRedactor.safeErrorDetail(error) }
                        }
                        .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !Eligibility.validCurrency(currency) || imports.isBusy)
                    }
                }
            }
        }
    }
    private func displayCurrency(_ account: SDAccount) -> String {
        forBalance ? account.currencyCode : account.spendingCurrency
    }

}

struct CurrencySelector: View {
    var title: String
    @Binding var selection: String
    @AppStorage("recentCurrencyCodes") private var recentCodes = ""
    @State private var choosing = false
    @State private var search = ""
    private let codes = Locale.commonISOCurrencyCodes.sorted()
    private func name(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

    private var recentCurrencies: [String] {
        recentCodes.split(separator: ",").map { String($0) }
    }

    private var prominentCurrencies: [String] {
        ["USD", "KRW"] + recentCurrencies.filter { $0 != "USD" && $0 != "KRW" }
    }

    private var matchingCurrencies: [String] {
        guard !search.isEmpty else { return codes }
        return codes.filter { code in
            code.localizedCaseInsensitiveContains(search) || name(code).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Button {
            search = ""
            choosing = true
        } label: {
            LabeledContent(title, value: selection.isEmpty ? "Choose currency" : "\(selection) · \(name(selection))")
        }
        .accessibilityIdentifier("currencySelector")
        .sheet(isPresented: $choosing) {
            currencySheet
        }
    }

    private var currencySheet: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section("Common and recent") {
                        ForEach(prominentCurrencies, id: \.self) { choice($0) }
                    }
                }
                Section("Currencies") {
                    ForEach(matchingCurrencies, id: \.self) { choice($0) }
                }
            }
            .searchable(text: $search, prompt: "Currency code or name")
            .navigationTitle("Choose currency")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosing = false } } }
        }
    }

    private func choice(_ code: String) -> some View {
        Button("\(code) · \(name(code))") {
            selection = code
            let previous = recentCurrencies.filter { $0 != code }
            recentCodes = ([code] + previous).prefix(5).joined(separator: ",")
            choosing = false
        }
    }
}

struct AccountsView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var accounts: [SDAccount]
    @Query private var transactions: [SDTransaction]
    @Query private var assets: [SDAssetSnapshot]
    @Query private var sources: [SDSourceDocument]
    @State private var label = ""
    @State private var currency = ""
    @State private var message: String?
    @State private var selectedAccount = ""
    var transactionIds: Set<String>? = nil
    var assetIds: Set<String>? = nil
    private var selectedTransactions: [SDTransaction] { transactions.filter { transactionIds?.contains($0.transactionId) ?? ($0.accountId == nil) } }
    private var selectedAssets: [SDAssetSnapshot] { assets.filter { assetIds?.contains($0.assetSnapshotId) ?? ($0.accountId == nil) } }
    private var groups: [String] { Set(selectedTransactions.map { $0.sourceDocumentId + "|" + $0.accountLabel } + selectedAssets.map { $0.sourceDocumentId + "|" + $0.accountLabel }).sorted() }
    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(accounts, id: \.accountId) { row in
                    NavigationLink("\(row.label) · \(row.spendingCurrency)") { AccountRenameView(account: row) }
                }
                TextField("New account label", text: $label)
                CurrencySelector(title: "Currency", selection: $currency)
                Button("Create account") {
                    do { try imports.service.store.saveAccount(label: label, currency: currency); label = ""; message = "Account created." }
                    catch { message = PrivacyRedactor.safeErrorDetail(error) }
                }.disabled(label.isEmpty || currency.isEmpty)
            }
            Section("Map records explicitly") {
                Text("Legacy records are grouped by source and label. Choose an account after checking the evidence; matching labels do not establish identity. Unmapped records stay out of totals.")
                Picker("Destination account", selection: $selectedAccount) {
                    Text("Choose account").tag("")
                    ForEach(accounts, id: \.accountId) { Text("\($0.label) · \($0.currencyCode) · \($0.accountId.prefix(4))").tag($0.accountId) }
                }
                ForEach(groups, id: \.self) { key in
                    let tx = selectedTransactions.filter { $0.sourceDocumentId + "|" + $0.accountLabel == key }
                    let balances = selectedAssets.filter { $0.sourceDocumentId + "|" + $0.accountLabel == key }
                    let sourceId = tx.first?.sourceDocumentId ?? balances.first?.sourceDocumentId
                    VStack(alignment: .leading) {
                        Text(tx.first?.accountLabel ?? balances.first?.accountLabel ?? "Unknown")
                        Text(sources.first { $0.sourceDocumentId == sourceId }?.fileName ?? "Source").font(.caption)
                        Text("\(tx.count) transactions · \(balances.count) balances").font(.caption)
                        if let source = sources.first(where: { $0.sourceDocumentId == sourceId }) { NavigationLink("Inspect evidence") { SourceDetailView(source: source) } }
                        Button("Map these records") {
                            do { try imports.service.store.mapRecords(transactions: Set(tx.map(\.transactionId)), assets: Set(balances.map(\.assetSnapshotId)), accountId: selectedAccount); message = "Mapping saved." }
                            catch { message = PrivacyRedactor.safeErrorDetail(error) }
                        }.disabled(selectedAccount.isEmpty)
                    }
                }
            }
            if let message { Text(message) }
        }.navigationTitle("Accounts & currencies").disabled(imports.isBusy)
    }
}

private struct AccountRenameView: View {
    @Environment(ImportCoordinator.self) private var imports
    let account: SDAccount
    @State private var label = ""
    @State private var currency = ""
    @State private var message: String?

    var body: some View {
        Form {
            TextField("Label", text: $label)
            CurrencySelector(title: "Default spending currency", selection: $currency)
            LabeledContent("Balance currency", value: account.currencyCode)
            Text("The spending default applies to future transactions for this account. Existing transactions and balances keep their currencies. Desktop v1 excludes transactions billed in a currency different from the balance currency.").font(.footnote)
            Button("Save account") {
                do {
                    try imports.service.store.saveAccount(id: account.accountId, label: label, currency: currency)
                    message = "Account saved."
                } catch { message = PrivacyRedactor.safeErrorDetail(error) }
            }
            .disabled(imports.isBusy || !Eligibility.validCurrency(currency))
            if let message { Text(message) }
        }
        .onAppear { label = account.label; currency = account.spendingCurrency }
        .navigationTitle("Edit account")
    }
}

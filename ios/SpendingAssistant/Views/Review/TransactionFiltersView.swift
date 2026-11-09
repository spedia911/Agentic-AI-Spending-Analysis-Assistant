import SwiftUI
import SpendingDomain

struct TransactionFilters {
    enum AccountType: String, CaseIterable {
        case all = "All types", bank = "Bank statement", card = "Card statement", other = "Other activity"
    }
    enum DateMode: String, CaseIterable {
        case all = "All dates", year = "Year", month = "Month", range = "Date range"
    }

    var category: SpendingCategory?
    var accountType: AccountType = .all
    var account = ""
    var merchant = ""
    var dateMode: DateMode = .all
    var year = ""
    var month = ""
    var start = Date()
    var end = Date()

    var isActive: Bool {
        category != nil || accountType != .all || !account.isEmpty || !merchant.isEmpty || dateMode != .all
    }

    func includes(_ row: TransactionRecord) -> Bool {
        guard category == nil || row.category == category else { return false }
        guard account.isEmpty || row.accountLabel == account else { return false }
        if !merchant.isEmpty {
            let haystack = row.merchantNormalized + " " + row.merchantRaw
            if !haystack.localizedCaseInsensitiveContains(merchant) { return false }
        }
        switch accountType {
        case .all: break
        case .bank: if row.origin != .bank { return false }
        case .card: if row.origin != .card { return false }
        case .other: if row.origin != nil { return false }
        }
        switch dateMode {
        case .all: return true
        case .year:
            return Validator.isValidDate(row.transactionDate) && row.transactionDate.hasPrefix(year)
        case .month:
            return row.transactionDate.hasPrefix(month + "-") && Validator.isValidDate(row.transactionDate)
        case .range:
            guard Validator.isValidDate(row.transactionDate) else { return false }
            return (Self.day(start)...Self.day(max(start, end))).contains(row.transactionDate)
        }
    }

    private static func day(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

struct TransactionFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TransactionFilters
    let months: [String]
    let accounts: [String]
    let apply: (TransactionFilters) -> Void

    init(initial: TransactionFilters, months: [String], accounts: [String], apply: @escaping (TransactionFilters) -> Void) {
        _draft = State(initialValue: initial)
        self.months = months
        self.accounts = accounts
        self.apply = apply
    }

    private var years: [String] {
        Array(Set(months.compactMap { month -> String? in
            guard month.count >= 4 else { return nil }
            return String(month.prefix(4))
        })).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $draft.category) {
                    Text("All categories").tag(nil as SpendingCategory?)
                    ForEach(SpendingCategory.allCases, id: \.self) { value in
                        Text(value.rawValue.displayTitle).tag(Optional(value))
                    }
                }
                Picker("Account type", selection: $draft.accountType) {
                    ForEach(TransactionFilters.AccountType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Account name", selection: $draft.account) {
                    Text("All accounts").tag("")
                    ForEach(accounts, id: \.self) { Text($0).tag($0) }
                }
                TextField("Merchant name contains", text: $draft.merchant)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("transactionMerchantFilter")

                Section("Date") {
                    Picker("Filter by date", selection: $draft.dateMode) {
                        ForEach(TransactionFilters.DateMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if draft.dateMode == .year {
                        Picker("Year", selection: $draft.year) {
                            Text("Choose year").tag("")
                            ForEach(years, id: \.self) { Text($0).tag($0) }
                        }
                    } else if draft.dateMode == .month {
                        Picker("Month", selection: $draft.month) {
                            Text("Choose month").tag("")
                            ForEach(months, id: \.self) { Text($0).tag($0) }
                        }
                    } else if draft.dateMode == .range {
                        DatePicker("From", selection: $draft.start, displayedComponents: .date)
                        DatePicker("Through", selection: $draft.end, in: draft.start..., displayedComponents: .date)
                    }
                }
                Button("Clear filters") { draft = TransactionFilters() }
                    .disabled(!draft.isActive)
            }
            .navigationTitle("Filters")
            .onChange(of: draft.start) { _, start in if draft.end < start { draft.end = start } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply(draft); dismiss() }
                        .disabled(
                            (draft.dateMode == .month && draft.month.isEmpty)
                                || (draft.dateMode == .year && draft.year.isEmpty)
                        )
                }
            }
        }
    }
}

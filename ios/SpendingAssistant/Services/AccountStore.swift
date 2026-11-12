import Foundation
import SwiftData
import SpendingDomain

extension LocalStore {
    func allAccounts() throws -> [AccountRecord] { try modelContext.fetch(FetchDescriptor<SDAccount>()).map { $0.toRecord() } }
    func dataset() throws -> SDDataset {
        if let row = try modelContext.fetch(FetchDescriptor<SDDataset>()).first { return row }
        let row = SDDataset(); modelContext.insert(row); return row
    }
    func account(id: String?) throws -> AccountRecord? { try allAccounts().first { $0.id == id } }
    @discardableResult
    func saveAccount(id: String? = nil, label: String, currency: String) throws -> String {
        let label = PrivacyRedactor.maskAccountLabel(label)
        guard label != "Unknown account", Eligibility.validCurrency(currency) else { throw ReviewError.invalidFields }
        let savedId = id ?? UUID().uuidString
        try commit(rebuild: true) {
            if let id, let entry = try modelContext.fetch(FetchDescriptor<SDAccount>()).first(where: { $0.accountId == id }) {
                entry.preferredSpendingCurrency = currency == entry.currencyCode ? nil : currency
                entry.label = label
                for var row in try allTransactions() where row.accountId == id { row.accountLabel = label; try upsert(transaction: row) }
                for var row in try allAssets() where row.accountId == id { row.accountLabel = label; try upsert(asset: row) }
            } else { modelContext.insert(SDAccount(id: savedId, label: label, currencyCode: currency)) }
        }
        return savedId
    }
    /// Assign currency only to transactions that have never had one.
    func applyDefaultCurrencyToUnassignedTransactions(_ currency: String?) throws {
        guard let currency, Eligibility.validCurrency(currency) else { return }
        let rows = try allTransactions().filter {
            $0.accountId == nil && $0.billedCurrencyCode == nil && $0.validationStatus != .rejected
        }
        guard !rows.isEmpty else { return }
        try commit(rebuild: true) {
            for var row in rows {
                row.assumedCurrencyCode = currency
                try upsert(transaction: row)
            }
        }
    }

    func mapRecords(transactions ids: Set<String>, assets assetIds: Set<String>, accountId: String) throws {
        guard let account = try account(id: accountId) else { throw ReviewError.invalidFields }
        try commit(rebuild: true) {
            for var row in try allTransactions() where ids.contains(row.id) && (row.accountId != account.id || row.currencyCode != account.currencyCode) {
                try insert(correction: CorrectionRecord(correctionId: UUID().uuidString, targetType: .transaction, targetId: row.id,
                    fieldName: "account_id", oldValue: row.accountId ?? "", newValue: account.id, applyFuture: false))
                row.assignAccount(account, defaultCurrency: nil)
                try upsert(transaction: row)
            }
            for var row in try allAssets() where assetIds.contains(row.id) && (row.accountId != account.id || row.currencyCode != account.currencyCode) {
                try insert(correction: CorrectionRecord(correctionId: UUID().uuidString, targetType: .assetSnapshot, targetId: row.id,
                    fieldName: "account_id", oldValue: row.accountId ?? "", newValue: account.id, applyFuture: false))
                row.accountId = account.id; row.currencyCode = account.currencyCode; row.accountLabel = account.label
                try upsert(asset: row)
            }
        }
    }
}

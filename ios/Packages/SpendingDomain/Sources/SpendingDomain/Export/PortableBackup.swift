import Foundation
import CryptoKit

public enum BackupError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(reason) = self { return "Backup: " + reason }; return nil }
}

public struct BackupAttachment: Codable, Sendable {
    public var sourceId: String
    public var status: String // included, omitted, expired, missing, unavailable
    public var data: Data?
    public var sha256: String?
    public init(sourceId: String, status: String, data: Data? = nil) {
        self.sourceId = sourceId; self.status = status; self.data = data
        sha256 = data.map(PortableBackup.hash)
    }
}

public struct ExportEligibility: Codable, Sendable {
    public var transactions: [String: RecordEligibility]
    public var balances: [String: RecordEligibility]
    public var spending: [String: SpendingClassification]
}

/// Complete local snapshot. Payload is encoded separately so its byte-level hash is portable.
public struct PortableBackup: Codable, Sendable {
    public var schemaVersion: Int
    public var datasetId: String
    public var snapshotId: String
    public var generatedAt: Date
    public var complete: Bool
    public var recordCounts: [String: Int]
    public var payload: Data
    public var payloadSHA256: String
    public var accounts: [AccountRecord]
    public var attachments: [BackupAttachment]
    public var eligibility: ExportEligibility
    public var manifestSHA256: String

    public init(records: BackupPayload, accounts: [AccountRecord], datasetId: String, attachments: [BackupAttachment]) throws {
        schemaVersion = 1; self.datasetId = datasetId; snapshotId = UUID().uuidString
        generatedAt = records.exportedAt; complete = true
        recordCounts = Self.counts(records)
        payload = try BackupExporter.jsonData(records); payloadSHA256 = Self.hash(payload)
        self.accounts = accounts; self.attachments = attachments
        eligibility = Self.eligibility(records)
        manifestSHA256 = ""
        manifestSHA256 = try digestManifest()
    }

    public static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    public static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
    public func encoded() throws -> Data { try Self.encoder().encode(self) }
    private func digestManifest() throws -> String {
        var copy = self; copy.manifestSHA256 = ""
        return Self.hash(try Self.encoder().encode(copy))
    }
    public static func counts(_ p: BackupPayload) -> [String: Int] {
        ["sources": p.sourceDocuments.count, "transactions": p.transactions.count, "balances": p.assetSnapshots.count,
         "reviews": p.reviewItems.count, "corrections": p.corrections.count]
    }
    public static func eligibility(_ p: BackupPayload) -> ExportEligibility {
        ExportEligibility(transactions: Dictionary(p.transactions.map { ($0.id, Eligibility.transaction($0, reviews: p.reviewItems)) }, uniquingKeysWith: { a, _ in a }),
            balances: Dictionary(p.assetSnapshots.map { ($0.id, Eligibility.asset($0, reviews: p.reviewItems, peers: p.assetSnapshots)) }, uniquingKeysWith: { a, _ in a }),
            spending: Dictionary(p.transactions.filter { $0.amount.isFinite }.map { ($0.id, SpendingClassification($0)) }, uniquingKeysWith: { a, _ in a }))
    }
    public func validatedRecords() throws -> BackupPayload {
        guard schemaVersion == 1, complete, UUID(uuidString: datasetId) != nil, UUID(uuidString: snapshotId) != nil else { throw BackupError.invalid("Unsupported version or incomplete snapshot.") }
        guard Self.hash(payload) == payloadSHA256, try digestManifest() == manifestSHA256 else { throw BackupError.invalid("Integrity check failed.") }
        let records = try Self.decoder().decode(BackupPayload.self, from: payload)
        guard recordCounts == Self.counts(records) else { throw BackupError.invalid("Record counts differ.") }
        try Self.validate(records, accounts: accounts)
        try Self.unique(attachments.map(\.sourceId))
        guard Set(attachments.map(\.sourceId)) == Set(records.sourceDocuments.map(\.id)) else { throw BackupError.invalid("Source manifest is incomplete.") }
        for item in attachments {
            guard ["included", "omitted", "expired", "missing", "unavailable"].contains(item.status) else { throw BackupError.invalid("Unknown attachment status.") }
            if item.status == "included" {
                guard let data = item.data, item.sha256 == Self.hash(data) else { throw BackupError.invalid("Source file checksum failed.") }
            } else if item.data != nil || item.sha256 != nil { throw BackupError.invalid("Unexpected source bytes.") }
        }
        // Recompute eligibility at restore; never trust producer flags over records/reviews.
        return records
    }
    private static func unique(_ ids: [String]) throws {
        guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else { throw BackupError.invalid("Duplicate or empty record identifiers.") }
    }
    public static func validate(_ p: BackupPayload, accounts: [AccountRecord]) throws {
        try unique(p.sourceDocuments.map(\.id)); try unique(p.transactions.map(\.id)); try unique(p.assetSnapshots.map(\.id))
        try unique(p.reviewItems.map(\.id)); try unique(p.corrections.map(\.id)); try unique(accounts.map(\.id))
        let sources = Set(p.sourceDocuments.map(\.id)), transactions = Set(p.transactions.map(\.id)), assets = Set(p.assetSnapshots.map(\.id))
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        guard accounts.allSatisfy({ Eligibility.mapped($0.id, $0.currencyCode) && !$0.label.isEmpty && ($0.preferredSpendingCurrency == nil || Eligibility.validCurrency($0.preferredSpendingCurrency)) }) else { throw BackupError.invalid("Invalid account.") }
        for source in p.sourceDocuments {
            if let accountId = source.importAccountId, accountMap[accountId] == nil { throw BackupError.invalid("Missing source account reference.") }
            if let path = source.localRelativePath, path.isEmpty || path != (path as NSString).lastPathComponent || path == "." || path == ".." || path.contains("\\") { throw BackupError.invalid("Unsafe source path.") }
        }
        func check(_ source: String, _ account: String?, _ currency: String?) throws {
            guard sources.contains(source) else { throw BackupError.invalid("Missing source reference.") }
            if let account {
                guard let entry = accountMap[account], currency == entry.currencyCode else { throw BackupError.invalid("Missing account or currency mismatch.") }
            } else if currency != nil { throw BackupError.invalid("Currency without account mapping.") }
        }
        for row in p.transactions {
            try check(row.sourceDocumentId, row.accountId, row.currencyCode)
            guard row.amount.isFinite else { throw BackupError.invalid("Non-finite amount.") }
            for code in [row.confirmedBilledCurrency, row.assumedCurrencyCode].compactMap({ $0 }) {
                guard Eligibility.validCurrency(code) else { throw BackupError.invalid("Invalid billed currency.") }
            }
        }
        for row in p.assetSnapshots { try check(row.sourceDocumentId, row.accountId, row.currencyCode); guard row.balance.isFinite else { throw BackupError.invalid("Non-finite balance.") } }
        for review in p.reviewItems {
            let ids = review.targetType == .transaction ? transactions : review.targetType == .assetSnapshot ? assets : sources
            guard ids.contains(review.targetId) else { throw BackupError.invalid("Missing review target.") }
        }
        // Corrections can intentionally reference deleted records: they are immutable audit history.
    }
}

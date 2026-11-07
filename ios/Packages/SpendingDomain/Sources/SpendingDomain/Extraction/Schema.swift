import Foundation

public struct ExtractedTransactionCandidate: Codable, Sendable, Equatable {
    public var rowIndex: Int
    public var dateText: String?
    public var merchantText: String?
    public var amountText: String?
    public var accountSourceText: String?
    public var transactionTypeHint: TransactionType
    public var confidence: Double
    public var evidenceText: String
    public var evidenceRegion: EvidenceRegion?

    public init(
        rowIndex: Int,
        dateText: String? = nil,
        merchantText: String? = nil,
        amountText: String? = nil,
        accountSourceText: String? = nil,
        transactionTypeHint: TransactionType = .unknown,
        confidence: Double = 0.5,
        evidenceText: String,
        evidenceRegion: EvidenceRegion? = nil
    ) {
        self.rowIndex = rowIndex
        self.dateText = dateText
        self.merchantText = merchantText
        self.amountText = amountText
        self.accountSourceText = accountSourceText
        self.transactionTypeHint = transactionTypeHint
        self.confidence = confidence
        self.evidenceText = evidenceText
        self.evidenceRegion = evidenceRegion
    }

    enum CodingKeys: String, CodingKey {
        case rowIndex = "row_index"
        case dateText = "date_text"
        case merchantText = "merchant_text"
        case amountText = "amount_text"
        case accountSourceText = "account_source_text"
        case transactionTypeHint = "transaction_type_hint"
        case confidence
        case evidenceText = "evidence_text"
        case evidenceRegion = "evidence_region"
    }
}

public struct ExtractedAssetSnapshotCandidate: Codable, Sendable, Equatable {
    public var rowIndex: Int
    public var accountLabelText: String?
    public var balanceText: String?
    public var balanceTypeHint: BalanceType
    public var observedDateText: String?
    public var confidence: Double
    public var evidenceText: String
    public var evidenceRegion: EvidenceRegion?

    public init(
        rowIndex: Int,
        accountLabelText: String? = nil,
        balanceText: String? = nil,
        balanceTypeHint: BalanceType = .unknown,
        observedDateText: String? = nil,
        confidence: Double = 0.5,
        evidenceText: String,
        evidenceRegion: EvidenceRegion? = nil
    ) {
        self.rowIndex = rowIndex
        self.accountLabelText = accountLabelText
        self.balanceText = balanceText
        self.balanceTypeHint = balanceTypeHint
        self.observedDateText = observedDateText
        self.confidence = confidence
        self.evidenceText = evidenceText
        self.evidenceRegion = evidenceRegion
    }

    enum CodingKeys: String, CodingKey {
        case rowIndex = "row_index"
        case accountLabelText = "account_label_text"
        case balanceText = "balance_text"
        case balanceTypeHint = "balance_type_hint"
        case observedDateText = "observed_date_text"
        case confidence
        case evidenceText = "evidence_text"
        case evidenceRegion = "evidence_region"
    }
}

public struct ScreenshotExtractionResult: Codable, Sendable, Equatable {
    public var sourceDocumentId: String
    public var screenshotKind: ScreenshotKind
    public var rawText: String
    public var extractionConfidence: Double
    public var transactions: [ExtractedTransactionCandidate]
    public var assetSnapshots: [ExtractedAssetSnapshotCandidate]
    public var warnings: [String]

    public init(
        sourceDocumentId: String,
        screenshotKind: ScreenshotKind = .unknown,
        rawText: String = "",
        extractionConfidence: Double = 0.5,
        transactions: [ExtractedTransactionCandidate] = [],
        assetSnapshots: [ExtractedAssetSnapshotCandidate] = [],
        warnings: [String] = []
    ) {
        self.sourceDocumentId = sourceDocumentId
        self.screenshotKind = screenshotKind
        self.rawText = rawText
        self.extractionConfidence = extractionConfidence
        self.transactions = transactions
        self.assetSnapshots = assetSnapshots
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case sourceDocumentId = "source_document_id"
        case screenshotKind = "screenshot_kind"
        case rawText = "raw_text"
        case extractionConfidence = "extraction_confidence"
        case transactions
        case assetSnapshots = "asset_snapshots"
        case warnings
    }
}

public enum ExtractionJSONParser {
    public static func parse(_ text: String) throws -> ScreenshotExtractionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") , start <= end {
            jsonText = String(trimmed[start...end])
        } else {
            jsonText = trimmed
        }
        guard let data = jsonText.data(using: .utf8) else {
            throw ExtractionError.invalidEncoding
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ScreenshotExtractionResult.self, from: data)
        } catch {
            throw ExtractionError.decodeFailed(PrivacyRedactor.maskSensitiveText(String(describing: error)))
        }
    }
}

public enum ExtractionError: Error, LocalizedError {
    case invalidEncoding
    case decodeFailed(String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "AI import text was not valid UTF-8."
        case .decodeFailed(let detail): return "AI import JSON could not be parsed: \(detail)"
        case .emptyResult: return "Extraction produced no transactions or balances."
        }
    }
}

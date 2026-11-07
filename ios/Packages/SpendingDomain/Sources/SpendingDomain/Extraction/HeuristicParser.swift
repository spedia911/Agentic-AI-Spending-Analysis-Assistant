import Foundation

public struct OCRLine: Sendable, Equatable {
    public var text: String
    public var boundingBox: EvidenceRegion?

    public init(text: String, boundingBox: EvidenceRegion? = nil) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Deterministic parser that turns OCR lines into extraction candidates.
public enum HeuristicScreenshotParser {
    public static func parse(
        sourceDocumentId: String,
        fileName: String,
        lines: [OCRLine]
    ) -> ScreenshotExtractionResult {
        let rawText = lines.map(\.text).joined(separator: "\n")
        var transactions: [ExtractedTransactionCandidate] = []
        var assets: [ExtractedAssetSnapshotCandidate] = []
        var warnings: [String] = []

        let amountPattern = #"[$€£]?\s*-?\(?\d{1,3}(?:,\d{3})*(?:\.\d{2})\)?(?:\s*CR)?"#
        let datePattern = #"\b(?:\d{1,2}/\d{1,2}(?:/\d{2,4})?|20\d{2}[-/]\d{1,2}[-/]\d{1,2}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2})\b"#

        for (index, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let balance = detectBalance(text) {
                assets.append(ExtractedAssetSnapshotCandidate(
                    rowIndex: assets.count,
                    accountLabelText: balance.account,
                    balanceText: balance.amount,
                    balanceTypeHint: balance.type,
                    observedDateText: firstMatch(datePattern, in: text),
                    confidence: 0.7,
                    evidenceText: text,
                    evidenceRegion: line.boundingBox
                ))
                continue
            }

            guard let amount = firstMatch(amountPattern, in: text),
                  let date = firstMatch(datePattern, in: text) else {
                continue
            }

            var merchant = text
            if let amountRange = merchant.range(of: amount) {
                merchant.removeSubrange(amountRange)
            }
            if let dateRange = merchant.range(of: date) {
                merchant.removeSubrange(dateRange)
            }
            merchant = merchant.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

            let typeHint: TransactionType
            if text.range(of: #"(?i)\brefund|credit\b"#, options: .regularExpression) != nil {
                typeHint = .refund
            } else if text.range(of: #"(?i)\bdeposit|payroll|direct dep\b"#, options: .regularExpression) != nil {
                typeHint = .income
            } else if text.range(of: #"(?i)\btransfer|zelle|payment\b"#, options: .regularExpression) != nil {
                typeHint = .transfer
            } else {
                typeHint = .expense
            }

            transactions.append(ExtractedTransactionCandidate(
                rowIndex: transactions.count,
                dateText: date,
                merchantText: merchant.isEmpty ? "Unknown merchant" : merchant,
                amountText: amount,
                accountSourceText: nil,
                transactionTypeHint: typeHint,
                confidence: merchant.isEmpty ? 0.55 : 0.72,
                evidenceText: text,
                evidenceRegion: line.boundingBox
            ))

            _ = index
        }

        if transactions.isEmpty && assets.isEmpty {
            warnings.append("Heuristic parser found no transaction or balance rows; try Foundation Models or AI JSON import.")
        }

        let kind: ScreenshotKind
        if !assets.isEmpty && !transactions.isEmpty {
            kind = .mixed
        } else if !assets.isEmpty {
            kind = .bankActivity
        } else if fileName.lowercased().contains("bank") {
            kind = .bankActivity
        } else if fileName.lowercased().contains("card") || fileName.lowercased().contains("credit") {
            kind = .creditCard
        } else {
            kind = transactions.isEmpty ? .unknown : .creditCard
        }

        let confidence = transactions.isEmpty && assets.isEmpty ? 0.2 : 0.7
        return ScreenshotExtractionResult(
            sourceDocumentId: sourceDocumentId,
            screenshotKind: kind,
            rawText: rawText,
            extractionConfidence: confidence,
            transactions: transactions,
            assetSnapshots: assets,
            warnings: warnings
        )
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let swift = Range(match.range, in: text) else { return nil }
        return String(text[swift])
    }

    private static func detectBalance(_ text: String) -> (account: String, amount: String, type: BalanceType)? {
        guard text.range(of: #"(?i)balance|available credit|available"#, options: .regularExpression) != nil else { return nil }
        guard let amount = firstMatch(#"[$€£]?\s*-?\(?\d{1,3}(?:,\d{3})*(?:\.\d{2})\)?"#, in: text) else { return nil }
        let type: BalanceType
        if text.range(of: #"(?i)saving"#, options: .regularExpression) != nil {
            type = .savings
        } else if text.range(of: #"(?i)available credit"#, options: .regularExpression) != nil {
            type = .creditAvailable
        } else if text.range(of: #"(?i)credit"#, options: .regularExpression) != nil {
            type = .creditBalance
        } else if text.range(of: #"(?i)checking|current"#, options: .regularExpression) != nil {
            type = .checking
        } else {
            type = .unknown
        }
        let account = text.split(separator: ":").first.map(String.init) ?? "Account"
        return (account.trimmingCharacters(in: .whitespacesAndNewlines), amount, type)
    }
}

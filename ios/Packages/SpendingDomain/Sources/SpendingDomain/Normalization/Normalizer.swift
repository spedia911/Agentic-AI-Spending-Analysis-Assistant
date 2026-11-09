import Foundation

public struct NormalizeContext: Sendable {
    public var sourceDocumentId: String
    public var observedMonthHint: String?
    public var now: Date

    public init(sourceDocumentId: String, observedMonthHint: String? = nil, now: Date = Date()) {
        self.sourceDocumentId = sourceDocumentId
        self.observedMonthHint = observedMonthHint
        self.now = now
    }
}

public struct NormalizedExtractionOutput: Sendable {
    public var transactions: [TransactionRecord]
    public var assetSnapshots: [AssetSnapshotRecord]
    public var reviewItems: [ReviewItemRecord]

    public init(transactions: [TransactionRecord], assetSnapshots: [AssetSnapshotRecord], reviewItems: [ReviewItemRecord]) {
        self.transactions = transactions
        self.assetSnapshots = assetSnapshots
        self.reviewItems = reviewItems
    }
}

public enum Normalizer {
    public static func normalizeAmountText(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isParenthesesNegative = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        let hasNegativeSign = trimmed.contains("-") || trimmed.range(of: #"\bCR\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let numericChars = trimmed.replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
        guard let numeric = Double(numericChars) else { return nil }
        return (isParenthesesNegative || hasNegativeSign) ? -numeric : numeric
    }

    public static func isValidStatementDateHint(_ value: String) -> Bool {
        Validator.isValidDate(value + (value.count == 4 ? "-01-01" : "-01"))
    }

    public static func normalizeDateText(_ value: String?, observedMonthHint: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = trimmed.range(of: #"\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b"#, options: .regularExpression) {
            let parts = String(trimmed[match]).replacingOccurrences(of: "/", with: "-").split(separator: "-")
            if parts.count == 3 {
                let year = String(parts[0])
                let month = String(parts[1]).padLeft(to: 2, with: "0")
                let day = String(parts[2]).padLeft(to: 2, with: "0")
                return "\(year)-\(month)-\(day)"
            }
        }

        let monthNames = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
        if let regex = try? NSRegularExpression(pattern: #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s+(20\d{2}))?\b"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges >= 3,
           let monthRange = Range(match.range(at: 1), in: trimmed),
           let dayRange = Range(match.range(at: 2), in: trimmed) {
            let mon = String(trimmed[monthRange]).prefix(3).lowercased()
            if let idx = monthNames.firstIndex(of: String(mon)) {
                let explicitYear = Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]) }
                guard let year = explicitYear ?? observedMonthHint.map({ String($0.prefix(4)) }) else { return nil }
                let month = String(idx + 1).padLeft(to: 2, with: "0")
                let day = String(trimmed[dayRange]).padLeft(to: 2, with: "0")
                return "\(year)-\(month)-\(day)"
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges >= 3,
           let monthRange = Range(match.range(at: 1), in: trimmed),
           let dayRange = Range(match.range(at: 2), in: trimmed) {
            let month = String(trimmed[monthRange]).padLeft(to: 2, with: "0")
            let day = String(trimmed[dayRange]).padLeft(to: 2, with: "0")
            var year: String?
            if match.numberOfRanges >= 4, let yearRange = Range(match.range(at: 3), in: trimmed), !yearRange.isEmpty {
                let yearText = String(trimmed[yearRange])
                year = yearText.count == 2 ? "20\(yearText)" : yearText
            } else if let observedMonthHint {
                year = String(observedMonthHint.prefix(4))
            }
            if let year { return "\(year)-\(month)-\(day)" }
        }

        return nil
    }

    public static func observedMonthFromDate(_ date: String?, fallback: String?) -> String {
        if let date, date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return String(date.prefix(7))
        }
        return fallback.flatMap { $0.count == 7 ? $0 : nil } ?? "unknown"
    }

    public static func normalizeMerchant(_ value: String?) -> String {
        guard let value else { return "Unknown merchant" }
        let cleaned = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Unknown merchant" : cleaned
    }

    public static func normalize(
        extraction: ScreenshotExtractionResult,
        context: NormalizeContext
    ) -> NormalizedExtractionOutput {
        var transactions: [TransactionRecord] = []
        var assets: [AssetSnapshotRecord] = []
        var reviews: [ReviewItemRecord] = []

        for candidate in extraction.transactions {
            let result = normalizeTransactionCandidate(candidate, context: context)
            transactions.append(result.transaction)
            reviews.append(contentsOf: result.reviewItems)
        }
        for candidate in extraction.assetSnapshots {
            let result = normalizeAssetSnapshotCandidate(candidate, context: context)
            assets.append(result.assetSnapshot)
            reviews.append(contentsOf: result.reviewItems)
        }
        return NormalizedExtractionOutput(transactions: transactions, assetSnapshots: assets, reviewItems: reviews)
    }

    public static func normalizeTransactionCandidate(
        _ candidate: ExtractedTransactionCandidate,
        context: NormalizeContext
    ) -> (transaction: TransactionRecord, reviewItems: [ReviewItemRecord]) {
        let date = normalizeDateText(candidate.dateText, observedMonthHint: context.observedMonthHint)
        let amount = normalizeAmountText(candidate.amountText)
        let merchant = normalizeMerchant(candidate.merchantText)
        let observedMonth = observedMonthFromDate(date, fallback: context.observedMonthHint)
        let transactionId = "txn_" + StableHash.make([
            context.sourceDocumentId, candidate.rowIndex, date, merchant, amount as Any?
        ])

        var reasons: [String] = []
        if date == nil { reasons.append("missing_date") }
        if candidate.merchantText == nil || candidate.merchantText?.isEmpty == true { reasons.append("missing_merchant") }
        if amount == nil { reasons.append("missing_amount") }

        let transaction = TransactionRecord(
            transactionId: transactionId,
            sourceDocumentId: context.sourceDocumentId,
            observedMonth: observedMonth,
            transactionDate: date ?? "",
            merchantRaw: candidate.merchantText ?? "",
            merchantNormalized: merchant,
            amount: amount ?? 0,
            transactionType: candidate.transactionTypeHint,
            accountLabel: PrivacyRedactor.maskAccountLabel(candidate.accountSourceText),
            category: .uncategorized,
            categoryConfidence: 0,
            extractionConfidence: candidate.confidence,
            validationStatus: reasons.isEmpty ? .valid : .needsReview,
            reviewStatus: reasons.isEmpty ? .none : .pending,
            evidenceText: candidate.evidenceText,
            evidenceRegion: serializeRegion(candidate.evidenceRegion),
            createdAt: context.now,
            updatedAt: context.now
        )

        // Validator is the sole owner of transaction validation reviews.
        return (transaction, [])
    }

    public static func normalizeAssetSnapshotCandidate(
        _ candidate: ExtractedAssetSnapshotCandidate,
        context: NormalizeContext
    ) -> (assetSnapshot: AssetSnapshotRecord, reviewItems: [ReviewItemRecord]) {
        let observedDate = normalizeDateText(candidate.observedDateText, observedMonthHint: context.observedMonthHint)
        let balance = normalizeAmountText(candidate.balanceText)
        let accountLabel = PrivacyRedactor.maskAccountLabel(candidate.accountLabelText)
        let observedMonth = observedMonthFromDate(observedDate, fallback: context.observedMonthHint)
        let assetSnapshotId = "asset_" + StableHash.make([
            context.sourceDocumentId, candidate.rowIndex, accountLabel, balance as Any?, observedDate
        ])

        let needsReview = observedDate == nil || balance == nil || candidate.accountLabelText == nil || candidate.confidence < 0.75
        let snapshot = AssetSnapshotRecord(
            assetSnapshotId: assetSnapshotId,
            sourceDocumentId: context.sourceDocumentId,
            observedMonth: observedMonth,
            observedDate: observedDate ?? "",
            accountLabel: accountLabel,
            balance: balance ?? 0,
            balanceType: candidate.balanceTypeHint,
            confidence: candidate.confidence,
            evidenceText: candidate.evidenceText,
            evidenceRegion: serializeRegion(candidate.evidenceRegion),
            createdAt: context.now
        )

        var reviews: [ReviewItemRecord] = []
        if needsReview {
            reviews.append(ReviewItemRecord(
                reviewItemId: "review_" + StableHash.make([assetSnapshotId, "missing_field"]),
                targetType: .assetSnapshot,
                targetId: assetSnapshotId,
                issueType: .missingField,
                severity: .medium,
                question: "Please review asset snapshot for \(accountLabel).",
                createdAt: context.now
            ))
        }
        return (snapshot, reviews)
    }

    private static func serializeRegion(_ region: EvidenceRegion?) -> String? {
        guard let region else { return nil }
        let payload: [String: Double] = [
            "x": (region.x * 10000).rounded() / 10000,
            "y": (region.y * 10000).rounded() / 10000,
            "width": (region.width * 10000).rounded() / 10000,
            "height": (region.height * 10000).rounded() / 10000
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}

private extension String {
    func padLeft(to length: Int, with pad: Character) -> String {
        if count >= length { return self }
        return String(repeating: pad, count: length - count) + self
    }
}

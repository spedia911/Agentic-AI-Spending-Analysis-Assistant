import Foundation

public struct DuplicateBatchMatch: Identifiable, Equatable, Sendable {
    public var id: String { remove.transactionId }
    public let keep: TransactionRecord
    public let remove: TransactionRecord
}

public struct DuplicateSourcePair: Identifiable, Equatable, Sendable {
    public var id: String { keepSourceId + "|" + removeSourceId }
    public let keepSourceId: String
    public let removeSourceId: String
    public let matchCount: Int

    public init(keepSourceId: String, removeSourceId: String, matchCount: Int) {
        self.keepSourceId = keepSourceId
        self.removeSourceId = removeSourceId
        self.matchCount = matchCount
    }
}

public struct DuplicateMatchFilter: Equatable, Sendable {
    public var year: String = ""
    public var month: String = ""
    public var account: String = ""

    public init(year: String = "", month: String = "", account: String = "") {
        self.year = year
        self.month = month
        self.account = account
    }

    public var isActive: Bool { !year.isEmpty || !month.isEmpty || !account.isEmpty }

    public func includes(_ match: DuplicateBatchMatch) -> Bool {
        let date = match.keep.transactionDate
        if !year.isEmpty, !date.hasPrefix(year) { return false }
        if !month.isEmpty, !date.hasPrefix(month) { return false }
        if !account.isEmpty {
            let keepAccount = match.keep.accountLabel
            let removeAccount = match.remove.accountLabel
            if keepAccount != account && removeAccount != account { return false }
        }
        return true
    }
}

public enum DuplicateBatch {
    private struct Key: Hashable {
        let date: String
        let merchant: String
        let cents: Int
        let type: TransactionType
    }

    /// Only pair unique exact rows from the two explicitly selected sources.
    /// Repeated identical charges in either source need individual review.
    public static func matches(keeping keepSource: String, removing removeSource: String,
                               transactions: [TransactionRecord],
                               filter: DuplicateMatchFilter = DuplicateMatchFilter()) -> [DuplicateBatchMatch] {
        guard keepSource != removeSource else { return [] }
        func groups(_ source: String) -> [Key: [TransactionRecord]] {
            var result: [Key: [TransactionRecord]] = [:]
            for row in transactions where row.sourceDocumentId == source && row.validationStatus != .rejected {
                guard row.amount.isFinite, abs(row.amount) < 1_000_000_000, row.amount != 0,
                      Validator.isValidDate(row.transactionDate), row.transactionType != .unknown else { continue }
                let merchant = Categorizer.merchantKey(row.merchantNormalized)
                guard !merchant.isEmpty, merchant != "unknownmerchant" else { continue }
                let key = Key(date: row.transactionDate, merchant: merchant, cents: Int((row.amount * 100).rounded()), type: row.transactionType)
                result[key, default: []].append(row)
            }
            return result
        }

        let left = groups(keepSource)
        let right = groups(removeSource)
        return left.compactMap { key, rows -> DuplicateBatchMatch? in
            guard rows.count == 1, let keep = rows.first, let candidates = right[key], candidates.count == 1,
                  let remove = candidates.first,
                  keep.accountId == remove.accountId, keep.billedCurrencyCode == remove.billedCurrencyCode,
                  keep.origin == nil || remove.origin == nil || keep.origin == remove.origin else { return nil }
            return DuplicateBatchMatch(keep: keep, remove: remove)
        }.filter(filter.includes).sorted {
            ($0.keep.transactionDate, $0.keep.merchantNormalized, $0.id) < ($1.keep.transactionDate, $1.keep.merchantNormalized, $1.id)
        }
    }

    /// Suggest undirected source pairs that already have unambiguous cross-source matches.
    /// Prefer keeping the source that currently holds more non-rejected transactions.
    public static func suggestedPairs(transactions: [TransactionRecord], limit: Int = 12) -> [DuplicateSourcePair] {
        let usable = transactions.filter { $0.validationStatus != .rejected }
        let sources = Array(Set(usable.map(\.sourceDocumentId))).sorted()
        guard sources.count >= 2 else { return [] }
        var counts: [String: Int] = [:]
        for row in usable { counts[row.sourceDocumentId, default: 0] += 1 }

        var pairs: [DuplicateSourcePair] = []
        for i in 0..<sources.count {
            for j in (i + 1)..<sources.count {
                let left = sources[i]
                let right = sources[j]
                let matchCount = matches(keeping: left, removing: right, transactions: transactions).count
                guard matchCount > 0 else { continue }
                let keepLeft = (counts[left] ?? 0) >= (counts[right] ?? 0)
                pairs.append(DuplicateSourcePair(
                    keepSourceId: keepLeft ? left : right,
                    removeSourceId: keepLeft ? right : left,
                    matchCount: matchCount
                ))
            }
        }
        return pairs.sorted { ($0.matchCount, $0.id) > ($1.matchCount, $1.id) }.prefix(limit).map { $0 }
    }

    /// True when every related transaction lives in the same import (or only one still exists).
    public static func isSameSourceDuplicate(relatedIds: [String], transactions: [TransactionRecord]) -> Bool {
        let related = Set(relatedIds)
        let sources = Set(transactions.filter { related.contains($0.transactionId) }.map(\.sourceDocumentId))
        return sources.count <= 1
    }
}

public struct DuplicateChargeGroup: Identifiable, Equatable, Sendable {
    public var id: String { anomalyId }
    public let anomalyId: String
    public let summary: String
    public let month: String
    public let relatedRecordIds: [String]
    public let sameSource: Bool
    public let sourceDocumentId: String?
    public let dates: [String]
    public let merchant: String
    public let amountLabel: String

    public init(
        anomalyId: String,
        summary: String,
        month: String,
        relatedRecordIds: [String],
        sameSource: Bool,
        sourceDocumentId: String?,
        dates: [String],
        merchant: String,
        amountLabel: String
    ) {
        self.anomalyId = anomalyId
        self.summary = summary
        self.month = month
        self.relatedRecordIds = relatedRecordIds
        self.sameSource = sameSource
        self.sourceDocumentId = sourceDocumentId
        self.dates = dates
        self.merchant = merchant
        self.amountLabel = amountLabel
    }

    public static func from(anomalies: [AnomalyRecord], transactions: [TransactionRecord]) -> [DuplicateChargeGroup] {
        let byId = Dictionary(uniqueKeysWithValues: transactions.map { ($0.transactionId, $0) })
        return anomalies
            .filter { $0.anomalyType == .duplicateCharge && $0.status == .open }
            .compactMap { anomaly -> DuplicateChargeGroup? in
                let rows = anomaly.relatedRecordIds.compactMap { byId[$0] }
                    .sorted { ($0.transactionDate, $0.transactionId) < ($1.transactionDate, $1.transactionId) }
                guard !rows.isEmpty else { return nil }
                let sources = Set(rows.map(\.sourceDocumentId))
                let sameSource = sources.count <= 1
                let merchant = rows.first?.merchantNormalized ?? "Unknown merchant"
                let amount = rows.first.map { String(format: "%.2f", abs($0.amount)) } ?? ""
                return DuplicateChargeGroup(
                    anomalyId: anomaly.anomalyId,
                    summary: anomaly.summary,
                    month: anomaly.month,
                    relatedRecordIds: anomaly.relatedRecordIds,
                    sameSource: sameSource,
                    sourceDocumentId: sameSource ? sources.first : nil,
                    dates: rows.map(\.transactionDate),
                    merchant: merchant,
                    amountLabel: amount
                )
            }
            .sorted {
                ($0.dates.first ?? "", $0.merchant, $0.anomalyId) < ($1.dates.first ?? "", $1.merchant, $1.anomalyId)
            }
    }
}

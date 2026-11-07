import Foundation

public struct AnomalyGenerationContext: Sendable {
    public var now: Date
    public var spendingSpikeRatio: Double
    public var duplicateLookbackDays: Int

    public init(now: Date = Date(), spendingSpikeRatio: Double = 2, duplicateLookbackDays: Int = 3) {
        self.now = now
        self.spendingSpikeRatio = spendingSpikeRatio
        self.duplicateLookbackDays = duplicateLookbackDays
    }
}

public enum AnomalyDetector {
    public static func generate(
        transactions: [TransactionRecord],
        monthlySummaries: [MonthlySummaryRecord],
        assetTrends: [AssetTrendRecord],
        context: AnomalyGenerationContext = AnomalyGenerationContext()
    ) -> [AnomalyRecord] {
        detectDuplicateChargeAnomalies(transactions, now: context.now, lookbackDays: context.duplicateLookbackDays)
            + detectSpendingSpikeAnomalies(monthlySummaries, now: context.now, ratio: context.spendingSpikeRatio)
            + detectBalanceDropAnomalies(assetTrends, now: context.now)
            + detectMissingMonthAnomalies(monthlySummaries, now: context.now)
    }

    public static func detectDuplicateChargeAnomalies(_ transactions: [TransactionRecord], now: Date, lookbackDays: Int) -> [AnomalyRecord] {
        var anomalies: [AnomalyRecord] = []
        let usable = transactions.filter { $0.validationStatus != .rejected }
        for i in 0..<usable.count {
            for j in (i + 1)..<usable.count {
                let left = usable[i]
                let right = usable[j]
                let distance = dateDistanceDays(left.transactionDate, right.transactionDate)
                if merchantKey(left.merchantNormalized) == merchantKey(right.merchantNormalized),
                   abs(left.amount - right.amount) < 0.01,
                   let distance,
                   distance <= Double(lookbackDays) {
                    anomalies.append(makeAnomaly(
                        type: .duplicateCharge,
                        severity: .medium,
                        month: left.observedMonth.isEmpty ? right.observedMonth : left.observedMonth,
                        related: [left.transactionId, right.transactionId],
                        summary: "Possible duplicate charge at \(left.merchantNormalized) for \(String(format: "%.2f", abs(left.amount))).",
                        action: "Review both transactions and mark one as duplicate if only one charge is real.",
                        now: now
                    ))
                }
            }
        }
        return anomalies
    }

    public static func detectSpendingSpikeAnomalies(_ monthlySummaries: [MonthlySummaryRecord], now: Date, ratio: Double) -> [AnomalyRecord] {
        var byCategory: [String: [MonthlySummaryRecord]] = [:]
        for row in monthlySummaries {
            byCategory[row.category, default: []].append(row)
        }
        var anomalies: [AnomalyRecord] = []
        for (category, rows) in byCategory {
            let sorted = rows.sorted { $0.month < $1.month }
            for i in 1..<sorted.count {
                let prior = sorted[i - 1]
                let current = sorted[i]
                if prior.totalAmount > 0 && current.totalAmount / prior.totalAmount >= ratio {
                    anomalies.append(makeAnomaly(
                        type: .spendingSpike,
                        severity: current.totalAmount / prior.totalAmount >= ratio * 1.5 ? .high : .medium,
                        month: current.month,
                        related: ["\(current.month):\(category)"],
                        summary: "\(category) spending increased from \(String(format: "%.2f", prior.totalAmount)) to \(String(format: "%.2f", current.totalAmount)).",
                        action: "Review the largest \(category) transactions for this month.",
                        now: now
                    ))
                }
            }
        }
        return anomalies
    }

    public static func detectBalanceDropAnomalies(_ assetTrends: [AssetTrendRecord], now: Date) -> [AnomalyRecord] {
        assetTrends
            .filter { $0.maintainabilityFlag == .watch || $0.maintainabilityFlag == .concern }
            .map {
                makeAnomaly(
                    type: .balanceDrop,
                    severity: $0.maintainabilityFlag == .concern ? .high : .medium,
                    month: $0.month,
                    related: ["\($0.month):\($0.accountLabel)"],
                    summary: "\($0.accountLabel) balance changed by \(String(format: "%.2f", $0.monthlyChange)) while spending was \(String(format: "%.2f", $0.relatedSpendingTotal)).",
                    action: "Check whether this balance drop is expected and whether spending should be adjusted.",
                    now: now
                )
            }
    }

    public static func detectMissingMonthAnomalies(_ monthlySummaries: [MonthlySummaryRecord], now: Date) -> [AnomalyRecord] {
        let months = Array(Set(monthlySummaries.map(\.month))).sorted()
        var anomalies: [AnomalyRecord] = []
        for i in 1..<months.count {
            guard let expected = nextMonth(months[i - 1]) else { continue }
            if months[i] != expected {
                anomalies.append(makeAnomaly(
                    type: .missingData,
                    severity: .low,
                    month: expected,
                    related: [],
                    summary: "No monthly summary rows were found for \(expected).",
                    action: "Confirm whether screenshots for this month are missing or still unprocessed.",
                    now: now
                ))
            }
        }
        return anomalies
    }

    private static func makeAnomaly(type: AnomalyType, severity: Severity, month: String, related: [String], summary: String, action: String, now: Date) -> AnomalyRecord {
        AnomalyRecord(
            anomalyId: "anomaly_" + StableHash.make([type.rawValue, month, summary, related.joined(separator: ",")]),
            anomalyType: type,
            severity: severity,
            month: month,
            relatedRecordIds: related,
            summary: summary,
            suggestedAction: action,
            status: .open,
            createdAt: now
        )
    }

    private static func merchantKey(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }

    private static func dateDistanceDays(_ left: String, _ right: String) -> Double? {
        guard let a = parse(left), let b = parse(right) else { return nil }
        return abs(a.timeIntervalSince(b)) / 86_400
    }

    private static func parse(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func nextMonth(_ month: String) -> String? {
        guard let year = Int(month.prefix(4)), let monthIndex = Int(month.dropFirst(5).prefix(2)) else { return nil }
        var y = year
        var m = monthIndex + 1
        if m > 12 { m = 1; y += 1 }
        return String(format: "%04d-%02d", y, m)
    }
}

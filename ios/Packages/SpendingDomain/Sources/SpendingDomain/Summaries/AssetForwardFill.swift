import Foundation

public struct ForwardFilledBalance: Equatable, Sendable {
    public let month: String
    public let balance: Double
    public let sourceDate: String
    public let isForwardFilled: Bool

    public init(month: String, balance: Double, sourceDate: String, isForwardFilled: Bool) {
        self.month = month
        self.balance = balance
        self.sourceDate = sourceDate
        self.isForwardFilled = isForwardFilled
    }
}

/// Carry sparse balance observations into nearby months for dashboard trends.
public enum AssetForwardFill {
    /// For each calendar month through `throughMonth`, use the latest snapshot on/before that month's
    /// end whose observation is still within `maxAgeDays` of the month start (default: one month).
    public static func monthlySeries(
        snapshots: [AssetSnapshotRecord],
        throughMonth: String,
        maxAgeDays: Int = 31
    ) -> [ForwardFilledBalance] {
        let usable = snapshots.filter {
            $0.balanceType.tracksAsAsset
                && Validator.isValidDate($0.observedDate)
                && $0.balance.isFinite
                && Normalizer.isValidStatementDateHint($0.observedMonth)
        }.sorted { ($0.observedDate, $0.createdAt, $0.assetSnapshotId) < ($1.observedDate, $1.createdAt, $1.assetSnapshotId) }
        guard let first = usable.first, let end = normalizeMonth(throughMonth) else { return [] }
        var months: [String] = []
        var cursor = first.observedMonth
        while cursor <= end {
            months.append(cursor)
            guard let next = nextMonth(cursor) else { break }
            cursor = next
        }

        return months.compactMap { month -> ForwardFilledBalance? in
            guard let monthStart = parseDay("\(month)-01"),
                  let monthEnd = endOfMonth(month) else { return nil }
            let windowStart = Calendar(identifier: .gregorian).date(byAdding: .day, value: -maxAgeDays, to: monthStart) ?? monthStart
            let candidates = usable.filter {
                guard let day = parseDay($0.observedDate) else { return false }
                return day <= monthEnd && day >= windowStart
            }
            guard let best = candidates.last else { return nil }
            return ForwardFilledBalance(
                month: month,
                balance: best.balance,
                sourceDate: best.observedDate,
                isForwardFilled: String(best.observedDate.prefix(7)) != month
            )
        }
    }

    private static func normalizeMonth(_ month: String) -> String? {
        guard Normalizer.isValidStatementDateHint(month), month.count == 7 else { return nil }
        return month
    }

    private static func nextMonth(_ month: String) -> String? {
        guard let year = Int(month.prefix(4)), let monthIndex = Int(month.dropFirst(5).prefix(2)) else { return nil }
        var y = year
        var m = monthIndex + 1
        if m > 12 { m = 1; y += 1 }
        return String(format: "%04d-%02d", y, m)
    }

    private static func endOfMonth(_ month: String) -> Date? {
        guard let start = parseDay("\(month)-01") else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard let next = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: next)
    }

    private static func parseDay(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

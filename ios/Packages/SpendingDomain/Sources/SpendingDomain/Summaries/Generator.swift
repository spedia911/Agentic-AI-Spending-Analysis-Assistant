import Foundation

public struct SummaryResult: Sendable {
    public var monthlySummaries: [MonthlySummaryRecord]
    public var quarterlySummaries: [QuarterlySummaryRecord]
    public var cashFlowSummaries: [CashFlowSummaryRecord]
    public var assetTrends: [AssetTrendRecord]

    public init(monthlySummaries: [MonthlySummaryRecord], quarterlySummaries: [QuarterlySummaryRecord], cashFlowSummaries: [CashFlowSummaryRecord], assetTrends: [AssetTrendRecord]) {
        self.monthlySummaries = monthlySummaries
        self.quarterlySummaries = quarterlySummaries
        self.cashFlowSummaries = cashFlowSummaries
        self.assetTrends = assetTrends
    }
}

public enum SummaryGenerator {
    public static func generateCashFlowSummaries(_ rows: [TransactionRecord]) -> [CashFlowSummaryRecord] {
        Dictionary(grouping: rows.filter { Eligibility.transaction($0).local }, by: { $0.billedCurrencyCode! }).sorted { $0.key < $1.key }.flatMap { code, rows in
            generateCashFlowSummariesOne(rows).map { row in var result = row; result.currencyCode = code; return result }
        }
    }


    public static func generateQuarterlySummaries(_ rows: [MonthlySummaryRecord]) -> [QuarterlySummaryRecord] {
        Dictionary(grouping: rows.filter { Eligibility.validCurrency($0.currencyCode) }, by: { $0.currencyCode! }).sorted { $0.key < $1.key }.flatMap { code, rows in
            generateQuarterlySummariesOne(rows).map { row in var result = row; result.currencyCode = code; return result }
        }
    }


    public static func generateMonthlySummaries(_ rows: [TransactionRecord]) -> [MonthlySummaryRecord] {
        Dictionary(grouping: rows.filter { Eligibility.transaction($0).local }, by: { $0.billedCurrencyCode! }).sorted { $0.key < $1.key }.flatMap { code, rows in
            generateMonthlySummariesOne(rows).map { row in var result = row; result.currencyCode = code; return result }
        }
    }


    public static func generate(transactions: [TransactionRecord], assetSnapshots: [AssetSnapshotRecord]) -> SummaryResult {
        let monthly = generateMonthlySummaries(transactions)
        return SummaryResult(
            monthlySummaries: monthly,
            quarterlySummaries: generateQuarterlySummaries(monthly),
            cashFlowSummaries: generateCashFlowSummaries(transactions),
            assetTrends: generateAssetTrends(assetSnapshots, transactions: transactions)
        )
    }

    private static func generateMonthlySummariesOne(_ transactions: [TransactionRecord]) -> [MonthlySummaryRecord] {
        struct Agg { var total = 0.0; var count = 0; var reviewed = 0; var unresolved = 0 }
        var grouped: [String: Agg] = [:]
        for transaction in transactions.filter(isUsable) {
            let key = transaction.observedMonth + "|" + transaction.category.rawValue
            var current = grouped[key] ?? Agg()
            current.total += summaryAmount(transaction)
            current.count += 1
            if transaction.reviewStatus == .resolved { current.reviewed += 1 }
            if transaction.reviewStatus == .pending { current.unresolved += 1 }
            grouped[key] = current
        }

        var rows: [MonthlySummaryRecord] = grouped.map { key, value in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return MonthlySummaryRecord(
                month: parts[0],
                category: parts.count > 1 ? parts[1] : "miscellaneous",
                totalAmount: round2(value.total),
                transactionCount: value.count,
                reviewedCount: value.reviewed,
                unresolvedCount: value.unresolved,
                monthOverMonthDelta: nil,
                completenessStatus: value.unresolved > 0 ? .partial : .unknown
            )
        }

        let totals = Dictionary(uniqueKeysWithValues: rows.map { ($0.month + "|" + $0.category, $0.totalAmount) })
        rows = rows.map { row in
            var copy = row
            let priorKey = previousMonth(row.month) + "|" + row.category
            if let prior = totals[priorKey] {
                copy.monthOverMonthDelta = round2(row.totalAmount - prior)
            }
            return copy
        }
        return rows.sorted { ($0.month + $0.category) < ($1.month + $1.category) }
    }

    private static func generateQuarterlySummariesOne(_ monthly: [MonthlySummaryRecord]) -> [QuarterlySummaryRecord] {
        struct Agg { var total = 0.0; var count = 0; var partial = false }
        var grouped: [String: Agg] = [:]
        for row in monthly {
            let quarter = quarterForMonth(row.month)
            let key = quarter + "|" + row.category
            var current = grouped[key] ?? Agg()
            current.total += row.totalAmount
            current.count += row.transactionCount
            current.partial = current.partial || row.completenessStatus != .complete
            grouped[key] = current
        }
        var rows: [QuarterlySummaryRecord] = grouped.map { key, value in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return QuarterlySummaryRecord(
                quarter: parts[0],
                category: parts.count > 1 ? parts[1] : "miscellaneous",
                totalAmount: round2(value.total),
                transactionCount: value.count,
                quarterOverQuarterDelta: nil,
                completenessStatus: value.partial ? .partial : .complete
            )
        }
        let totals = Dictionary(uniqueKeysWithValues: rows.map { ($0.quarter + "|" + $0.category, $0.totalAmount) })
        rows = rows.map { row in
            var copy = row
            if let prior = totals[previousQuarter(row.quarter) + "|" + row.category] {
                copy.quarterOverQuarterDelta = round2(row.totalAmount - prior)
            }
            return copy
        }
        return rows.sorted { ($0.quarter + $0.category) < ($1.quarter + $1.category) }
    }

    private static func generateCashFlowSummariesOne(_ transactions: [TransactionRecord]) -> [CashFlowSummaryRecord] {
        struct Agg {
            var spending = 0.0; var income = 0.0; var refund = 0.0; var transfer = 0.0
            var payment = 0.0; var fee = 0.0; var count = 0; var unresolved = 0
        }
        var grouped: [String: Agg] = [:]
        for transaction in transactions.filter(isUsable) {
            var current = grouped[transaction.observedMonth] ?? Agg()
            current.spending += SpendingMath.spendingAmount(transaction)
            current.income += SpendingMath.incomeAmount(transaction)
            current.refund += transaction.transactionType == .refund ? abs(transaction.amount) : 0
            current.transfer += SpendingMath.transferAmount(transaction)
            if transaction.transactionType == .payment,
               SpendingMath.spendingAmount(transaction) == 0,
               SpendingMath.transferAmount(transaction) == 0 {
                current.payment += abs(transaction.amount)
            }
            if transaction.transactionType == .fee || transaction.category == .fees {
                current.fee += abs(transaction.amount)
            }
            current.count += 1
            if transaction.reviewStatus == .pending || transaction.validationStatus == .needsReview {
                current.unresolved += 1
            }
            grouped[transaction.observedMonth] = current
        }
        return grouped.keys.sorted().compactMap { month -> CashFlowSummaryRecord? in
            guard let row = grouped[month] else { return nil }
            return CashFlowSummaryRecord(
                month: month,
                spendingTotal: round2(row.spending),
                incomeTotal: round2(row.income),
                refundTotal: round2(row.refund),
                transferTotal: round2(row.transfer),
                paymentTotal: round2(row.payment),
                feeTotal: round2(row.fee),
                netCashFlow: round2(row.income + row.refund - row.spending),
                transactionCount: row.count,
                unresolvedCount: row.unresolved,
                completenessStatus: row.unresolved > 0 ? .partial : .unknown
            )
        }
    }

    public static func generateAssetTrends(_ snapshots: [AssetSnapshotRecord], transactions: [TransactionRecord]) -> [AssetTrendRecord] {
        let eligible = snapshots.filter { Eligibility.asset($0, peers: snapshots).local }
        let groups = Dictionary(grouping: eligible) { [$0.accountId!, $0.balanceType.rawValue, $0.currencyCode!].joined(separator: "|") }
        return groups.keys.sorted().flatMap { key -> [AssetTrendRecord] in
            let months = Dictionary(grouping: groups[key]!, by: \.observedMonth)
            let ordered = months.keys.sorted().compactMap { month in
                months[month]?.sorted { ($0.observedDate, $0.createdAt, $0.id) < ($1.observedDate, $1.createdAt, $1.id) }.last
            }
            return ordered.enumerated().map { index, row in
                let prior = index > 0 ? ordered[index - 1] : nil
                let truePrior = prior.flatMap { $0.observedMonth == previousMonth(row.observedMonth) ? $0 : nil }
                let activity = transactions.filter { Eligibility.transaction($0).local && $0.accountId == row.accountId && $0.billedCurrencyCode == row.currencyCode && $0.observedMonth == row.observedMonth }
                let spending = activity.isEmpty ? nil : round2(activity.reduce(0) { $0 + SpendingMath.spendingAmount($1) })
                var result = AssetTrendRecord(month: row.observedMonth, accountLabel: row.accountLabel,
                    endingBalance: row.balance, priorMonthBalance: truePrior?.balance,
                    monthlyChange: truePrior.map { round2(row.balance - $0.balance) },
                    relatedSpendingTotal: spending, maintainabilityFlag: .unknown, currencyCode: row.currencyCode)
                result.accountId = row.accountId
                result.previousObservationDate = prior?.observedDate
                result.previousObservationChange = prior.map { round2(row.balance - $0.balance) }
                return result
            }
        }
    }

    private static func isUsable(_ transaction: TransactionRecord) -> Bool {
        transaction.validationStatus != .rejected && Validator.isValidDate(transaction.transactionDate)
            && transaction.amount.isFinite && transaction.amount != 0
            && transaction.observedMonth == String(transaction.transactionDate.prefix(7))
    }

    private static func summaryAmount(_ transaction: TransactionRecord) -> Double {
        if SpendingMath.spendingAmount(transaction) > 0
            || SpendingMath.isIncome(transaction)
            || transaction.transactionType == .refund {
            return abs(transaction.amount)
        }
        return 0
    }

    private static func quarterForMonth(_ month: String) -> String {
        let monthNumber = Int(month.dropFirst(5).prefix(2)) ?? 1
        let quarter = Int(ceil(Double(monthNumber) / 3.0))
        return String(month.prefix(4)) + "-Q\(quarter)"
    }

    private static func previousMonth(_ month: String) -> String {
        guard let year = Int(month.prefix(4)), let monthIndex = Int(month.dropFirst(5).prefix(2)) else { return month }
        var y = year
        var m = monthIndex - 1
        if m <= 0 { m = 12; y -= 1 }
        return String(format: "%04d-%02d", y, m)
    }

    private static func previousQuarter(_ quarter: String) -> String {
        let parts = quarter.split(separator: "-Q")
        guard parts.count == 2, let year = Int(parts[0]), let q = Int(parts[1]) else { return quarter }
        if q > 1 { return "\(year)-Q\(q - 1)" }
        return "\(year - 1)-Q4"
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

import SwiftUI
import SwiftData
import Charts
import SpendingDomain

struct HomeView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var cashFlows: [SDCashFlowSummary]
    @Query private var anomalies: [SDAnomaly]
    @Query private var reviews: [SDReviewItem]
    @Query private var sources: [SDSourceDocument]
    @Query private var transactions: [SDTransaction]

    @Query private var assets: [SDAssetSnapshot]
    @State private var month: String?
    @State private var category: SpendingCategory?
    @State private var account: AssetAccount?

    private var months: [String] {
        Set(cashFlows.map(\.month) + assets.filter { Validator.isValidDate($0.observedDate) }.map(\.observedMonth)).sorted(by: >)
    }

    private var activeMonth: String? { month.flatMap { months.contains($0) ? $0 : nil } ?? months.first }
    private var spending: [TransactionRecord] {
        transactions.map { $0.toRecord() }.filter {
            $0.validationStatus != .rejected && $0.observedMonth == activeMonth
                && $0.amount.isFinite && $0.observedMonth == String($0.transactionDate.prefix(7))
                && Validator.isValidDate($0.transactionDate) && SpendingMath.spendingAmount($0) > 0
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let message = imports.shareMessage {
                        Text(message).font(.footnote).accessibilityIdentifier("shareImportStatus")
                    }
                    if transactions.contains(where: { $0.validationStatusRaw == ValidationStatus.needsReview.rawValue || $0.reviewStatusRaw == ReviewStatus.pending.rawValue }) {
                        Text("Provisional totals include usable transactions awaiting review. Rejected rows are excluded.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("provisionalTotals")
                    }
                    NavigationLink("View and correct transactions") { TransactionsView() }
                        .buttonStyle(.bordered)
                    filtersSection
                    categoryChartSection
                    cashFlowSection
                    assetSection
                    insightsSection
                    anomaliesSection
                }
                .padding()
            }
            .navigationTitle("Spending")
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        }
    }

    private var insightsSection: some View {
        let snapshot = DashboardSnapshot(
            sourceDocuments: sources.map { $0.toRecord() },
            reviewItems: reviews.map { $0.toRecord() },
            anomalies: anomalies.map { $0.toRecord() },
            cashFlowSummaries: cashFlows.map { $0.toRecord() },
            assetTrends: []
        )
        let insights = DashboardInsightBuilder.build(snapshot)
        return VStack(alignment: .leading, spacing: 12) {
            Label { Text("Next best actions") } icon: { FinanceIcon.trend.image }
                .font(.title2.weight(.semibold))
            ForEach(insights) { insight in
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title).font(.headline)
                    Text(insight.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading) {
            if !months.isEmpty {
                HStack {
                    Picker("Month", selection: Binding(get: { activeMonth }, set: { month = $0 })) {
                        ForEach(months, id: \.self) { Text($0).tag(Optional($0)) }
                    }.accessibilityIdentifier("dashboardMonth")
                    Spacer()
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(nil as SpendingCategory?)
                        ForEach(SpendingCategory.allCases, id: \.self) { Text($0.rawValue.displayTitle).tag(Optional($0)) }
                    }.accessibilityIdentifier("dashboardCategory")
                }.pickerStyle(.menu)
                Text("Month selects the spending summary and the end of recorded history. Category filters spending only.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var cashFlowSection: some View {
        let rows = cashFlows.filter { $0.month <= (activeMonth ?? "") }.sorted { $0.month < $1.month }
        let series = rows.map { MonthlyPoint(month: $0.month, value: $0.netCashFlow) }
        return VStack(alignment: .leading, spacing: 8) {
            Label { Text("Cash flow") } icon: { FinanceIcon.cashFlow.image }.font(.title2.weight(.semibold))
            if let row = rows.first(where: { $0.month == activeMonth }) {
                LabeledContent("Net cash flow", value: usd(row.netCashFlow))
                LabeledContent("Income", value: usd(row.incomeTotal))
                LabeledContent("Spending", value: usd(row.spendingTotal))
                yearOverYear(series, month: row.month)
            } else { Text("No cash flow for this month.").foregroundStyle(.secondary) }
            if !series.isEmpty {
                trendChart(series, comparison: MonthlyTrend.regression(series), comparisonName: "Linear trend")
                Text("Income and refunds minus spending. Card repayments and transfers classified as non-spending are excluded. Missing months have no observations.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var categoryChartSection: some View {
        let rows = spending.filter { category == nil || $0.category == category }
        let totals = Dictionary(grouping: rows, by: \.category).mapValues { $0.reduce(0) { $0 + SpendingMath.spendingAmount($1) } }
        return VStack(alignment: .leading, spacing: 8) {
            Label { Text("Spending by category") } icon: { FinanceIcon.categories.image }.font(.title2.weight(.semibold))
            if totals.isEmpty { Text("No spending matches these filters.").foregroundStyle(.secondary) }
            else {
                LabeledContent("Total", value: usd(totals.values.reduce(0, +)))
                Chart(totals.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { key in
                    BarMark(x: .value("Spending (USD)", totals[key, default: 0]), y: .value("Category", key.rawValue.displayTitle))
                        .foregroundStyle(CategoryColors.color(for: key))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { AxisValueLabel().foregroundStyle(.primary) }
                }
                .chartLegend(.hidden)
                .frame(height: max(110, CGFloat(totals.count * 35)))
                NavigationLink("View matching transactions") { TransactionsView(month: activeMonth, category: category) }
            }
        }
    }

    private var assetSection: some View {
        let pendingAssetIds = Set(reviews.filter { $0.targetTypeRaw == ReviewTargetType.assetSnapshot.rawValue && $0.statusRaw == ReviewItemStatus.pending.rawValue }.map(\.targetId))
        let eligible = assets.map { $0.toRecord() }.filter {
            $0.balanceType.tracksAsAsset && Validator.isValidDate($0.observedDate)
                && !pendingAssetIds.contains($0.assetSnapshotId) && $0.balance.isFinite
                && $0.observedMonth <= (activeMonth ?? "9999-12")
        }
        let grouped = Dictionary(grouping: eligible) { AssetAccount(label: $0.accountLabel, type: $0.balanceType) }
        let keys = grouped.keys.sorted { ($0.label, $0.type.rawValue) < ($1.label, $1.type.rawValue) }
        let current = account.flatMap { keys.contains($0) ? $0 : nil } ?? keys.first
        let balances = current.flatMap { grouped[$0] } ?? []
        let filled = AssetForwardFill.monthlySeries(
            snapshots: balances,
            throughMonth: activeMonth ?? balances.map(\.observedMonth).max() ?? ""
        )
        let series = filled.map { MonthlyPoint(month: $0.month, value: $0.balance) }
        let projection = MonthlyTrend.regression(series, futureMonths: 3)
        let latestFill = filled.last
        return VStack(alignment: .leading, spacing: 8) {
            Text("Asset trends").font(.title2.weight(.semibold))
            if let last = series.last, let latestFill {
                Picker("Account", selection: Binding(get: { current }, set: { account = $0 })) {
                    ForEach(keys, id: \.self) { Text("\($0.label) (\($0.type.title))").tag(Optional($0)) }
                }.pickerStyle(.menu)
                LabeledContent(
                    latestFill.isForwardFilled
                        ? "Balance as of \(latestFill.month) (carried from \(latestFill.sourceDate))"
                        : "Latest recorded balance (\(last.month))",
                    value: usd(last.value)
                )
                yearOverYear(series, month: last.month)
                trendChart(series, comparison: projection, comparisonName: "Projected balance")
                if let endpoint = projection.last {
                    LabeledContent("Projected balance (\(endpoint.month))", value: usd(endpoint.value))
                    Text("Sparse balances are carried forward up to one month. Credit lines are excluded. Projection uses a linear fit when three months are available.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Add balances from three different months to see a projection. Infrequent updates are forward-filled for up to one month.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Import or enter checking, savings, retirement, HSA, or brokerage balances to see asset history.")
                    .foregroundStyle(.secondary)
                NavigationLink("Add balance manually") { ManualAssetView() }
            }
        }
    }

    private func usd(_ amount: Double) -> String { amount.formatted(.currency(code: "USD")) }

    @ViewBuilder private func yearOverYear(_ series: [MonthlyPoint], month: String) -> some View {
        if let change = MonthlyTrend.yearOverYear(series, month: month) {
            LabeledContent("Year over year", value: usd(change.amount) + (change.fraction.map { " (\($0.formatted(.percent.precision(.fractionLength(1)))))" } ?? ""))
        } else { Text("Year over year: no record for the same month last year.").font(.caption).foregroundStyle(.secondary) }
    }

    private func chartDate(_ month: String) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: Int(month.prefix(4)), month: Int(month.suffix(2)), day: 1)) ?? .distantPast
    }

    private func trendChart(_ observed: [MonthlyPoint], comparison: [MonthlyPoint], comparisonName: String) -> some View {
        Chart {
            ForEach(observed, id: \.month) { point in
                LineMark(x: .value("Month", chartDate(point.month)), y: .value("USD", point.value), series: .value("Series", "Recorded"))
                    .foregroundStyle(by: .value("Series", "Recorded"))
                PointMark(x: .value("Month", chartDate(point.month)), y: .value("USD", point.value))
                    .foregroundStyle(by: .value("Series", "Recorded"))
            }
            ForEach(comparison, id: \.month) { point in
                LineMark(x: .value("Month", chartDate(point.month)), y: .value("USD", point.value), series: .value("Series", comparisonName))
                    .foregroundStyle(by: .value("Series", comparisonName)).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)) } }
        .frame(height: 220)
    }

    private struct AssetAccount: Hashable { var label: String; var type: BalanceType }

    private var anomaliesSection: some View {
        let open = anomalies.filter { $0.statusRaw == AnomalyStatus.open.rawValue }
        let duplicateGroups = DuplicateChargeGroup.from(
            anomalies: open.map { $0.toRecord() },
            transactions: transactions.map { $0.toRecord() }
        )
        let sameImport = duplicateGroups.filter(\.sameSource).count
        let crossPairs = DuplicateBatch.suggestedPairs(transactions: transactions.map { $0.toRecord() }).count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Anomalies")
                .font(.title2.weight(.semibold))
            NavigationLink("Review duplicates & anomalies") { BatchAnomalyReviewView() }
            if open.isEmpty {
                Text("No open anomalies.")
                    .foregroundStyle(.secondary)
            } else {
                if sameImport > 0 && crossPairs == 0 {
                    Text("\(sameImport) same-import duplicate \(sameImport == 1 ? "alert" : "alerts") — compare charges by date inside the import.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if sameImport > 0 {
                    Text("\(sameImport) same-import and \(crossPairs) overlapping-import duplicate paths — compare dates or remove copy imports.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if crossPairs > 0 {
                    Text("\(crossPairs) overlapping import \(crossPairs == 1 ? "pair" : "pairs") — pick which import to keep and remove matching copies.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if duplicateGroups.count > 0 {
                    Text("\(duplicateGroups.count) duplicate \(duplicateGroups.count == 1 ? "alert" : "alerts") — open Review to compare the related charges.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(open.prefix(5), id: \.anomalyId) { anomaly in
                    VStack(alignment: .leading) {
                        Text(anomaly.summary).font(.subheadline)
                        Text("\(anomaly.anomalyTypeRaw.displayTitle) · \(anomaly.suggestedAction)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

}

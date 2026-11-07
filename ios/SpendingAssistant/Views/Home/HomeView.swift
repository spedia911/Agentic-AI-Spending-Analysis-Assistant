import SwiftUI
import SwiftData
import Charts
import SpendingDomain

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var monthly: [SDMonthlySummary]
    @Query private var cashFlows: [SDCashFlowSummary]
    @Query private var anomalies: [SDAnomaly]
    @Query private var reviews: [SDReviewItem]
    @Query private var sources: [SDSourceDocument]
    @Query private var transactions: [SDTransaction]

    @AppStorage("enableFoundationModels") private var enableFoundationModels = true
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    insightsSection
                    cashFlowSection
                    categoryChartSection
                    anomaliesSection

                    Button("Seed demo data") {
                        seedDemo()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Spending")
            .background(
                LinearGradient(
                    colors: [Color(red: 0.93, green: 0.96, blue: 0.94), Color(red: 0.86, green: 0.91, blue: 0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
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
            Text("Next best actions")
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

    private var cashFlowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cash flow")
                .font(.title2.weight(.semibold))
            if cashFlows.isEmpty {
                Text("No cash-flow summaries yet. Import a screenshot or seed demo data.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cashFlows.sorted { $0.month > $1.month }.prefix(3), id: \.month) { row in
                    HStack {
                        Text(row.month)
                        Spacer()
                        Text(row.netCashFlow, format: .currency(code: "USD"))
                            .foregroundStyle(row.netCashFlow >= 0 ? Color.primary : Color.red)
                    }
                    Text("Spending \(row.spendingTotal.formatted(.currency(code: "USD"))) · Income \(row.incomeTotal.formatted(.currency(code: "USD")))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(transactions.count) transactions tracked")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryChartSection: some View {
        let latestMonth = monthly.map(\.month).sorted().last
        let rows = monthly.filter { $0.month == latestMonth }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Categories \(latestMonth ?? "")")
                .font(.title2.weight(.semibold))
            if rows.isEmpty {
                Text("No category totals yet.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(rows, id: \.category) { row in
                    SectorMark(
                        angle: .value("Amount", abs(row.totalAmount)),
                        innerRadius: .ratio(0.55)
                    )
                    .foregroundStyle(by: .value("Category", row.category))
                }
                .frame(height: 220)
            }
        }
    }

    private var anomaliesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anomalies")
                .font(.title2.weight(.semibold))
            let open = anomalies.filter { $0.statusRaw == AnomalyStatus.open.rawValue }
            if open.isEmpty {
                Text("No open anomalies.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(open.prefix(5), id: \.anomalyId) { anomaly in
                    VStack(alignment: .leading) {
                        Text(anomaly.summary).font(.subheadline)
                        Text(anomaly.suggestedAction).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func seedDemo() {
        do {
            let store = LocalStore(modelContext: modelContext)
            let service = ImportPipelineService(store: store, enableFoundationModels: enableFoundationModels)
            try service.seedDemo()
            statusMessage = "Demo data loaded."
        } catch {
            statusMessage = PrivacyRedactor.safeErrorDetail(error)
        }
    }
}

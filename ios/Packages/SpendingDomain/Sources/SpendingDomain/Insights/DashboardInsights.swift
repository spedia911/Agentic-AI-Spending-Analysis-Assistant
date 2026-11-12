import Foundation

public struct DashboardSnapshot: Sendable {
    public var sourceDocuments: [SourceDocumentRecord]
    public var reviewItems: [ReviewItemRecord]
    public var anomalies: [AnomalyRecord]
    public var cashFlowSummaries: [CashFlowSummaryRecord]
    public var assetTrends: [AssetTrendRecord]

    public init(
        sourceDocuments: [SourceDocumentRecord],
        reviewItems: [ReviewItemRecord],
        anomalies: [AnomalyRecord],
        cashFlowSummaries: [CashFlowSummaryRecord],
        assetTrends: [AssetTrendRecord]
    ) {
        self.sourceDocuments = sourceDocuments
        self.reviewItems = reviewItems
        self.anomalies = anomalies
        self.cashFlowSummaries = cashFlowSummaries
        self.assetTrends = assetTrends
    }
}

public enum DashboardInsightBuilder {
    private static let priorityOrder: [InsightPriority: Int] = [
        .critical: 0, .high: 1, .medium: 2, .low: 3, .info: 4
    ]

    public static func build(_ data: DashboardSnapshot) -> [DashboardInsight] {
        var insights: [DashboardInsight] = []
        let sourceErrors = data.sourceDocuments.filter { $0.status == .error }
        let pendingReviews = data.reviewItems.filter { $0.status == .pending && !$0.isAdvisory }
        let openAnomalies = data.anomalies.filter { $0.status == .open }
        let latestFlow = data.cashFlowSummaries.sorted { $0.month > $1.month }.first

        if !sourceErrors.isEmpty {
            insights.append(DashboardInsight(
                insightId: "source-errors",
                priority: .critical,
                title: "Retry failed source files",
                detail: sourceErrors.count == 1
                    ? "One screenshot failed processing. Open its evidence page, check the masked message, then retry or ignore it."
                    : "\(sourceErrors.count) screenshots failed processing. Review sources, then retry or ignore failed files.",
                actionLabel: "Review sources",
                actionRoute: "sources"
            ))
        }

        if !pendingReviews.isEmpty {
            let high = pendingReviews.filter { $0.severity == .high }.count
            let medium = pendingReviews.filter { $0.severity == .medium }.count
            let low = pendingReviews.filter { $0.severity == .low }.count
            let parts = [
                high > 0 ? "\(high) high" : nil,
                medium > 0 ? "\(medium) medium" : nil,
                low > 0 ? "\(low) low" : nil
            ].compactMap { $0 }
            let highest = pendingReviews.min { priorityOrder[severityPriority($0.severity)]! < priorityOrder[severityPriority($1.severity)]! }
            insights.append(DashboardInsight(
                insightId: "pending-reviews",
                priority: highest.map { severityPriority($0.severity) } ?? .medium,
                title: "Resolve pending review items",
                detail: parts.joined(separator: ", ") + " review items need a decision before summaries are fully trusted.",
                actionLabel: "Open review",
                actionRoute: "review"
            ))
        }

        if !openAnomalies.isEmpty {
            let example = openAnomalies.min { priorityOrder[severityPriority($0.severity)]! < priorityOrder[severityPriority($1.severity)]! } ?? openAnomalies[0]
            insights.append(DashboardInsight(
                insightId: "open-anomalies",
                priority: severityPriority(example.severity),
                title: "Investigate open anomalies",
                detail: example.summary,
                actionLabel: "View anomalies",
                actionRoute: "home"
            ))
        }

        if let latestFlow, latestFlow.netCashFlow < 0 {
            insights.append(DashboardInsight(
                insightId: "negative-cash-flow",
                priority: .high,
                title: "Negative cash flow in \(latestFlow.month)",
                detail: "Net cash flow is \(String(format: "%.2f", latestFlow.netCashFlow)). Review spending and income for that month.",
                actionLabel: "Open cash flow",
                actionRoute: "home"
            ))
        }

        if insights.isEmpty {
            insights.append(DashboardInsight(
                insightId: "all-clear",
                priority: .info,
                title: "No urgent actions",
                detail: "Import a screenshot or paste AI extraction JSON to refresh your monthly review.",
                actionLabel: "Import",
                actionRoute: "import"
            ))
        }

        return insights.sorted { priorityOrder[$0.priority]! < priorityOrder[$1.priority]! }
    }

    private static func severityPriority(_ severity: Severity) -> InsightPriority {
        switch severity {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

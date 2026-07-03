import type { Anomaly, AssetTrend, CashFlowSummary, ReviewItem } from '../../types/domain';
import type { DashboardData } from './data';

export type DashboardInsightPriority = 'critical' | 'high' | 'medium' | 'low' | 'info';

export interface DashboardInsight {
  insight_id: string;
  priority: DashboardInsightPriority;
  title: string;
  detail: string;
  action_label: string;
  action_href: string;
}

const PRIORITY_ORDER: Record<DashboardInsightPriority, number> = {
  critical: 0,
  high: 1,
  medium: 2,
  low: 3,
  info: 4,
};

function safeMonth(value: string | null | undefined): string {
  return value && value.trim() ? value : 'unknown month';
}

function latestCashFlow(rows: CashFlowSummary[]): CashFlowSummary | undefined {
  return [...rows].sort((a, b) => safeMonth(b.month).localeCompare(safeMonth(a.month)))[0];
}

function latestConcern(trends: AssetTrend[]): AssetTrend | undefined {
  return [...trends]
    .filter((trend) => trend.maintainability_flag === 'concern')
    .sort((a, b) => safeMonth(b.month).localeCompare(safeMonth(a.month)))[0];
}

function severityPriority(severity: ReviewItem['severity'] | Anomaly['severity']): DashboardInsightPriority {
  if (severity === 'high') return 'high';
  if (severity === 'medium') return 'medium';
  return 'low';
}

function countBySeverity(items: Array<{ severity: ReviewItem['severity'] | Anomaly['severity'] }>) {
  return {
    high: items.filter((item) => item.severity === 'high').length,
    medium: items.filter((item) => item.severity === 'medium').length,
    low: items.filter((item) => item.severity === 'low').length,
  };
}

function highestSeverity<T extends { severity: ReviewItem['severity'] | Anomaly['severity'] }>(items: T[]): T | undefined {
  return [...items].sort((a, b) => PRIORITY_ORDER[severityPriority(a.severity)] - PRIORITY_ORDER[severityPriority(b.severity)])[0];
}

export function buildDashboardInsights(data: DashboardData, userEmail: string): DashboardInsight[] {
  const emailParam = '?email=' + encodeURIComponent(userEmail);
  const insights: DashboardInsight[] = [];
  const sourceErrors = data.sourceDocuments.filter((source) => source.status === 'error');
  const pendingReviews = data.reviewItems.filter((item) => item.status === 'pending');
  const openAnomalies = data.anomalies.filter((item) => item.status === 'open');
  const latestFlow = latestCashFlow(data.cashFlowSummaries);
  const concern = latestConcern(data.assetTrends);

  if (sourceErrors.length > 0) {
    insights.push({
      insight_id: 'source-errors',
      priority: 'critical',
      title: 'Retry failed source files',
      detail:
        sourceErrors.length === 1
          ? 'One screenshot failed processing. Open its evidence page, check the masked message, then retry or ignore it.'
          : sourceErrors.length + ' screenshots failed processing. Review the source-file audit, then retry or ignore the failed files.',
      action_label: 'Review sources',
      action_href: emailParam + '#source-file-audit',
    });
  }

  if (pendingReviews.length > 0) {
    const counts = countBySeverity(pendingReviews);
    const highest = highestSeverity(pendingReviews);
    const detailParts = [
      counts.high > 0 ? counts.high + ' high' : null,
      counts.medium > 0 ? counts.medium + ' medium' : null,
      counts.low > 0 ? counts.low + ' low' : null,
    ].filter(Boolean);
    insights.push({
      insight_id: 'pending-reviews',
      priority: highest ? severityPriority(highest.severity) : 'medium',
      title: 'Resolve pending review items',
      detail: detailParts.join(', ') + ' review items need a decision before summaries are fully trusted.',
      action_label: 'Open review',
      action_href: '/review' + emailParam,
    });
  }

  if (openAnomalies.length > 0) {
    const highest = highestSeverity(openAnomalies);
    const example = highest ?? openAnomalies[0];
    insights.push({
      insight_id: 'open-anomalies',
      priority: highest ? severityPriority(highest.severity) : 'medium',
      title: 'Investigate open anomalies',
      detail:
        openAnomalies.length === 1
          ? example.summary + ' Suggested action: ' + example.suggested_action
          : openAnomalies.length + ' anomalies are open. Start with: ' + example.summary,
      action_label: 'Review anomalies',
      action_href: emailParam + '#anomaly-review',
    });
  }

  if (latestFlow && latestFlow.net_cash_flow < 0) {
    insights.push({
      insight_id: 'negative-cash-flow-' + latestFlow.month,
      priority: latestFlow.unresolved_count > 0 ? 'medium' : 'low',
      title: 'Check negative net cash flow',
      detail:
        safeMonth(latestFlow.month) +
        ' shows spending above income and refunds. Confirm unresolved rows first, then inspect the largest categories in Spending Explorer.',
      action_label: 'Inspect spending',
      action_href: emailParam + '#spending-explorer',
    });
  }

  if (concern) {
    insights.push({
      insight_id: 'asset-concern-' + concern.month + '-' + concern.account_label,
      priority: 'medium',
      title: 'Review balance pressure',
      detail:
        safeMonth(concern.month) +
        ' has a balance concern for ' +
        concern.account_label +
        '. Compare the balance change against related spending before marking the month complete.',
      action_label: 'View assets',
      action_href: emailParam + '#asset-trends',
    });
  }

  if (insights.length === 0) {
    insights.push({
      insight_id: 'all-clear',
      priority: 'info',
      title: data.transactions.length === 0 ? 'Add or seed financial screenshots' : 'No urgent follow-up',
      detail:
        data.transactions.length === 0
          ? 'Run the Drive workflow or seed demo data to populate transactions, reviews, anomalies, and summaries.'
          : 'There are no failed files, pending reviews, open anomalies, negative latest cash flow, or asset concerns in the current sheet data.',
      action_label: data.transactions.length === 0 ? 'Run workflow' : 'Refresh summaries',
      action_href: emailParam + '#action-center',
    });
  }

  return insights
    .sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority] || a.title.localeCompare(b.title))
    .slice(0, 5);
}

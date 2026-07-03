import { expect, it } from 'vitest';
import { buildDashboardInsights } from './insights';
import type { DashboardData } from './data';
import type { Anomaly, AssetTrend, CashFlowSummary, ReviewItem, SourceDocument, Transaction } from '../../types/domain';

function baseData(overrides: Partial<DashboardData> = {}): DashboardData {
  return {
    sheetId: 'sheet-123',
    transactions: [],
    assetSnapshots: [],
    sourceDocuments: [],
    monthlySummaries: [],
    quarterlySummaries: [],
    assetTrends: [],
    cashFlowSummaries: [],
    reviewItems: [],
    anomalies: [],
    runs: [],
    ...overrides,
  };
}

function review(id: string, severity: ReviewItem['severity']): ReviewItem {
  return {
    review_item_id: id,
    target_type: 'transaction',
    target_id: 'txn-1',
    issue_type: 'unclear_category',
    severity,
    question: 'Which category should this use?',
    suggested_options: ['shopping'],
    status: 'pending',
    user_answer: null,
    created_at: '2026-06-01T00:00:00Z',
    resolved_at: null,
  };
}

function anomaly(id: string, severity: Anomaly['severity']): Anomaly {
  return {
    anomaly_id: id,
    anomaly_type: 'duplicate_charge',
    severity,
    month: '2026-06',
    related_record_ids: ['txn-1', 'txn-2'],
    summary: 'Possible duplicate charge at Demo Merchant',
    suggested_action: 'Review both rows.',
    status: 'open',
    created_at: '2026-06-01T00:00:00Z',
  };
}

function cashFlow(month: string, netCashFlow: number, unresolvedCount = 0): CashFlowSummary {
  return {
    month,
    spending_total: 500,
    income_total: 300,
    refund_total: 0,
    transfer_total: 0,
    payment_total: 0,
    fee_total: 0,
    net_cash_flow: netCashFlow,
    transaction_count: 4,
    unresolved_count: unresolvedCount,
    completeness_status: 'partial',
  };
}

it('prioritizes source errors ahead of review and anomaly work', () => {
  const source: SourceDocument = {
    source_document_id: 'source-1',
    source_type: 'drive',
    file_name: 'bank.png',
    mime_type: 'image/png',
    created_time: '2026-06-01T00:00:00Z',
    modified_time: '2026-06-01T00:00:00Z',
    processed_at: null,
    status: 'error',
    error_summary: 'Processing failed',
  };

  const insights = buildDashboardInsights(
    baseData({
      sourceDocuments: [source],
      reviewItems: [review('review-1', 'high')],
      anomalies: [anomaly('anomaly-1', 'high')],
    }),
    'user@example.com'
  );

  expect(insights.map((insight) => insight.insight_id)).toEqual(['source-errors', 'open-anomalies', 'pending-reviews']);
  expect(insights[0].priority).toBe('critical');
});

it('creates cash-flow and asset-pressure actions from summaries', () => {
  const trend: AssetTrend = {
    month: '2026-06',
    account_label: 'Checking *1234',
    ending_balance: 1000,
    prior_month_balance: 1600,
    monthly_change: -600,
    related_spending_total: 900,
    maintainability_flag: 'concern',
  };

  const insights = buildDashboardInsights(
    baseData({
      cashFlowSummaries: [cashFlow('2026-06', -250, 1)],
      assetTrends: [trend],
    }),
    'user@example.com'
  );

  expect(insights.map((insight) => insight.insight_id)).toEqual(['negative-cash-flow-2026-06', 'asset-concern-2026-06-Checking *1234']);
  expect(insights[1].detail).toContain('Checking *1234');
});

it('returns an all-clear action when there is data but no urgent issue', () => {
  const transaction: Transaction = {
    transaction_id: 'txn-1',
    source_document_id: 'source-1',
    observed_month: '2026-06',
    transaction_date: '2026-06-01',
    merchant_raw: 'Demo',
    merchant_normalized: 'Demo',
    amount: 20,
    transaction_type: 'expense',
    account_label: 'Card *1234',
    category: 'shopping',
    category_confidence: 0.9,
    extraction_confidence: 0.9,
    validation_status: 'valid',
    review_status: 'none',
    evidence_text: 'Demo',
    created_at: '2026-06-01T00:00:00Z',
    updated_at: '2026-06-01T00:00:00Z',
  };

  const insights = buildDashboardInsights(baseData({ transactions: [transaction], cashFlowSummaries: [cashFlow('2026-06', 100)] }), 'user@example.com');

  expect(insights).toEqual([
    expect.objectContaining({
      insight_id: 'all-clear',
      title: 'No urgent follow-up',
    }),
  ]);
});

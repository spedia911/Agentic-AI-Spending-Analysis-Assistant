import { describe, expect, it } from 'vitest';
import { generateAssetTrends, generateMonthlySummaries, generateQuarterlySummaries } from './generator';
import type { AssetSnapshot, Transaction } from '../../types/domain';

function transaction(overrides: Partial<Transaction>): Transaction {
  return {
    transaction_id: 'txn-' + Math.random(),
    source_document_id: 'source-1',
    observed_month: '2026-06',
    transaction_date: '2026-06-12',
    merchant_raw: 'Trader Joes',
    merchant_normalized: 'Trader Joes',
    amount: 42.19,
    transaction_type: 'expense',
    account_label: 'Visa *1234',
    category: 'groceries',
    category_confidence: 0.95,
    extraction_confidence: 0.9,
    validation_status: 'valid',
    review_status: 'none',
    evidence_text: 'evidence',
    created_at: '2026-06-29T10:00:00Z',
    updated_at: '2026-06-29T10:00:00Z',
    ...overrides,
  };
}

function snapshot(overrides: Partial<AssetSnapshot>): AssetSnapshot {
  return {
    asset_snapshot_id: 'asset-' + Math.random(),
    source_document_id: 'source-1',
    observed_month: '2026-06',
    observed_date: '2026-06-30',
    account_label: 'Checking *1234',
    balance: 1000,
    balance_type: 'checking',
    confidence: 0.9,
    evidence_text: 'balance',
    created_at: '2026-06-29T10:00:00Z',
    ...overrides,
  };
}

describe('summary generation', () => {
  it('groups monthly summaries and computes month-over-month deltas', () => {
    const monthly = generateMonthlySummaries([
      transaction({ observed_month: '2026-05', transaction_date: '2026-05-10', amount: 20 }),
      transaction({ observed_month: '2026-06', transaction_date: '2026-06-10', amount: 50 }),
      transaction({ observed_month: '2026-06', transaction_date: '2026-06-11', amount: 10, review_status: 'pending' }),
      transaction({ observed_month: '2026-06', transaction_date: '2026-06-12', amount: 999, validation_status: 'rejected' }),
    ]);

    const june = monthly.find((row) => row.month === '2026-06' && row.category === 'groceries');
    expect(june).toMatchObject({
      total_amount: 60,
      transaction_count: 2,
      unresolved_count: 1,
      month_over_month_delta: 40,
      completeness_status: 'partial',
    });
  });

  it('builds quarterly summaries from monthly rows', () => {
    const quarterly = generateQuarterlySummaries([
      {
        month: '2026-04',
        category: 'groceries',
        total_amount: 30,
        transaction_count: 1,
        reviewed_count: 0,
        unresolved_count: 0,
        month_over_month_delta: null,
        completeness_status: 'unknown',
      },
      {
        month: '2026-05',
        category: 'groceries',
        total_amount: 70,
        transaction_count: 2,
        reviewed_count: 0,
        unresolved_count: 0,
        month_over_month_delta: 40,
        completeness_status: 'unknown',
      },
    ]);

    expect(quarterly[0]).toMatchObject({
      quarter: '2026-Q2',
      category: 'groceries',
      total_amount: 100,
      transaction_count: 3,
    });
  });

  it('generates asset trend maintainability flags', () => {
    const trends = generateAssetTrends(
      [
        snapshot({ observed_month: '2026-05', observed_date: '2026-05-31', balance: 2000 }),
        snapshot({ observed_month: '2026-06', observed_date: '2026-06-30', balance: 1500 }),
      ],
      [transaction({ observed_month: '2026-06', amount: 1200 })]
    );

    expect(trends[0].maintainability_flag).toBe('unknown');
    expect(trends[1]).toMatchObject({
      monthly_change: -500,
      related_spending_total: 1200,
      maintainability_flag: 'concern',
    });
  });
});

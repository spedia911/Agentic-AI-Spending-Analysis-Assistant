import { describe, expect, it } from 'vitest';
import { generateAnomalies } from './detector';
import type { AssetTrend, MonthlySummary, Transaction } from '../../types/domain';

function transaction(overrides: Partial<Transaction>): Transaction {
  return {
    transaction_id: 'txn-1',
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

function monthly(month: string, total: number): MonthlySummary {
  return {
    month,
    category: 'groceries',
    total_amount: total,
    transaction_count: 1,
    reviewed_count: 0,
    unresolved_count: 0,
    month_over_month_delta: null,
    completeness_status: 'unknown',
  };
}

function trend(flag: AssetTrend['maintainability_flag']): AssetTrend {
  return {
    month: '2026-06',
    account_label: 'Checking *1234',
    ending_balance: 1200,
    prior_month_balance: 2000,
    monthly_change: -800,
    related_spending_total: 1800,
    maintainability_flag: flag,
  };
}

describe('generateAnomalies', () => {
  it('detects duplicate charges, spending spikes, balance drops, and missing months', () => {
    const anomalies = generateAnomalies(
      [
        transaction({ transaction_id: 'txn-a', transaction_date: '2026-06-12' }),
        transaction({ transaction_id: 'txn-b', transaction_date: '2026-06-13' }),
      ],
      [monthly('2026-04', 20), monthly('2026-06', 100)],
      [trend('concern')],
      { now: '2026-06-29T10:00:00Z', spendingSpikeRatio: 2 }
    );

    expect(anomalies.map((item) => item.anomaly_type)).toEqual(
      expect.arrayContaining(['duplicate_charge', 'spending_spike', 'balance_drop', 'missing_data'])
    );
    expect(anomalies.every((item) => item.status === 'open')).toBe(true);
  });
});

import { describe, expect, it } from 'vitest';
import { validateTransactions } from './validator';
import type { Transaction } from '../../types/domain';

function transaction(overrides: Partial<Transaction> = {}): Transaction {
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
    category: 'uncategorized',
    category_confidence: 0,
    extraction_confidence: 0.9,
    validation_status: 'valid',
    review_status: 'none',
    evidence_text: 'Jun 12 Trader Joes $42.19',
    created_at: '2026-06-29T10:00:00Z',
    updated_at: '2026-06-29T10:00:00Z',
    ...overrides,
  };
}

describe('validateTransactions', () => {
  it('leaves clean transactions valid', () => {
    const result = validateTransactions([transaction()], {
      now: '2026-06-29T10:00:00Z',
      today: '2026-06-29',
    });

    expect(result.transactions[0].validation_status).toBe('valid');
    expect(result.reviewItems).toEqual([]);
  });

  it('routes missing fields and future dates to review', () => {
    const result = validateTransactions(
      [
        transaction({
          transaction_id: 'txn-missing',
          transaction_date: '2026-07-15',
          merchant_normalized: 'Unknown merchant',
          amount: 0,
          extraction_confidence: 0.4,
        }),
      ],
      { now: '2026-06-29T10:00:00Z', today: '2026-06-29' }
    );

    expect(result.transactions[0].validation_status).toBe('needs_review');
    expect(result.transactions[0].review_status).toBe('pending');
    expect(result.reviewItems.map((item) => item.issue_type)).toEqual(
      expect.arrayContaining(['missing_field', 'anomaly', 'low_confidence'])
    );
  });

  it('flags duplicate-looking transactions within the lookback window', () => {
    const result = validateTransactions(
      [
        transaction({ transaction_id: 'txn-a', transaction_date: '2026-06-12' }),
        transaction({ transaction_id: 'txn-b', transaction_date: '2026-06-13' }),
      ],
      { now: '2026-06-29T10:00:00Z', today: '2026-06-29', duplicateLookbackDays: 3 }
    );

    expect(result.transactions.every((item) => item.validation_status === 'needs_review')).toBe(true);
    expect(result.reviewItems.filter((item) => item.issue_type === 'duplicate_risk')).toHaveLength(2);
    expect(result.reviewItems[0].suggested_options[0]).toBe('needs_review');
  });

  it('defaults exact same-date same-amount duplicates to a single duplicate candidate', () => {
    const result = validateTransactions(
      [
        transaction({ transaction_id: 'txn-a', transaction_date: '2026-06-12' }),
        transaction({ transaction_id: 'txn-b', transaction_date: '2026-06-12' }),
      ],
      { now: '2026-06-29T10:00:00Z', today: '2026-06-29', duplicateLookbackDays: 3 }
    );

    const duplicateReviews = result.reviewItems.filter((item) => item.issue_type === 'duplicate_risk');
    expect(duplicateReviews).toHaveLength(1);
    expect(duplicateReviews[0]).toMatchObject({
      target_id: 'txn-b',
      severity: 'high',
      suggested_options: ['rejected', 'valid', 'needs_review'],
    });
    expect(result.transactions.find((item) => item.transaction_id === 'txn-a')?.validation_status).toBe('valid');
    expect(result.transactions.find((item) => item.transaction_id === 'txn-b')?.validation_status).toBe('needs_review');
  });
});

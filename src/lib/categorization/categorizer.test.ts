import { describe, expect, it } from 'vitest';
import { categorizeTransactions, categorizeTransactionsWithFallback } from './categorizer';
import type { Correction, Transaction } from '../../types/domain';

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

describe('categorizeTransactions', () => {
  it('categorizes common merchants with high confidence', () => {
    const result = categorizeTransactions([transaction()], { now: '2026-06-29T10:00:00Z' });

    expect(result.transactions[0]).toMatchObject({
      category: 'groceries',
      category_confidence: 0.95,
      review_status: 'none',
    });
    expect(result.reviewItems).toEqual([]);
  });

  it('routes ambiguous broad merchants to review', () => {
    const result = categorizeTransactions(
      [transaction({ merchant_raw: 'Amazon Marketplace', merchant_normalized: 'Amazon Marketplace' })],
      { now: '2026-06-29T10:00:00Z' }
    );

    expect(result.transactions[0].category).toBe('shopping');
    expect(result.transactions[0].review_status).toBe('pending');
    expect(result.reviewItems[0]).toMatchObject({
      issue_type: 'unclear_category',
      suggested_options: ['groceries', 'shopping', 'miscellaneous'],
    });
  });

  it('uses correction memory for future merchant categorization', () => {
    const corrections: Correction[] = [
      {
        correction_id: 'correction-1',
        target_type: 'merchant_rule',
        target_id: 'amazon marketplace',
        field_name: 'category',
        old_value: 'shopping',
        new_value: 'groceries',
        apply_future: true,
        created_at: '2026-06-29T10:00:00Z',
      },
    ];

    const result = categorizeTransactions(
      [transaction({ merchant_raw: 'Amazon Marketplace', merchant_normalized: 'Amazon Marketplace' })],
      { corrections, now: '2026-06-29T10:00:00Z' }
    );

    expect(result.transactions[0].category).toBe('groceries');
    expect(result.transactions[0].category_confidence).toBe(0.99);
    expect(result.reviewItems).toEqual([]);
  });

  it('falls unknown merchants back to miscellaneous review', () => {
    const result = categorizeTransactions(
      [transaction({ merchant_raw: 'Mystery Vendor', merchant_normalized: 'Mystery Vendor' })],
      { now: '2026-06-29T10:00:00Z' }
    );

    expect(result.transactions[0].category).toBe('miscellaneous');
    expect(result.transactions[0].validation_status).toBe('needs_review');
    expect(result.reviewItems[0].suggested_options).toContain('shopping');
  });

  it('uses AI fallback for unknown merchants when a classifier is available', async () => {
    const classifier = {
      classify: async () => ({ category: 'healthcare' as const, confidence: 0.86, reason: 'Model inferred healthcare from evidence text.' }),
    };

    const result = await categorizeTransactionsWithFallback(
      [transaction({ merchant_raw: 'Bluebird Services', merchant_normalized: 'Bluebird Services' })],
      { classifier, now: '2026-06-29T10:00:00Z' }
    );

    expect(result.transactions[0]).toMatchObject({
      category: 'healthcare',
      category_confidence: 0.86,
      review_status: 'none',
    });
    expect(result.reviewItems).toEqual([]);
  });

  it('keeps unknown merchants in review when AI fallback fails', async () => {
    const classifier = {
      classify: async () => {
        throw new Error('model unavailable');
      },
    };

    const result = await categorizeTransactionsWithFallback(
      [transaction({ merchant_raw: 'Mystery Vendor', merchant_normalized: 'Mystery Vendor' })],
      { classifier, now: '2026-06-29T10:00:00Z' }
    );

    expect(result.transactions[0].category).toBe('miscellaneous');
    expect(result.transactions[0].review_status).toBe('pending');
    expect(result.reviewItems[0].issue_type).toBe('unclear_category');
  });

  it('categorizes income and transfers from transaction type', () => {
    const result = categorizeTransactions([
      transaction({ transaction_id: 'income-1', transaction_type: 'income', merchant_normalized: 'Payroll' }),
      transaction({ transaction_id: 'transfer-1', transaction_type: 'payment', merchant_normalized: 'Credit Card Payment' }),
    ]);

    expect(result.transactions.map((item) => item.category)).toEqual(['income', 'transfer']);
  });

  it('categorizes bank bill payments as spending when the merchant is a biller', () => {
    const result = categorizeTransactions([
      transaction({
        transaction_id: 'pge-1',
        transaction_type: 'payment',
        merchant_raw: 'PG&E WEB PAYMENT',
        merchant_normalized: 'PG&E',
        account_label: 'Checking *1234',
      }),
      transaction({
        transaction_id: 'rent-1',
        transaction_type: 'payment',
        merchant_raw: 'Apartment Rent',
        merchant_normalized: 'Apartment Rent',
        account_label: 'Checking *1234',
      }),
    ]);

    expect(result.transactions.map((item) => item.category)).toEqual(['utilities', 'rent']);
  });
});

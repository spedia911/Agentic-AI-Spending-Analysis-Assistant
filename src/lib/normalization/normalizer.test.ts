import { describe, expect, it } from 'vitest';
import {
  maskAccountLabel,
  normalizeAmountText,
  normalizeDateText,
  normalizeExtractionCandidates,
  normalizeTransactionCandidate,
} from './normalizer';
import type { ExtractedTransactionCandidate } from '../extraction';

const context = {
  sourceDocumentId: 'drive-file-1',
  observedMonthHint: '2026-06',
  now: '2026-06-29T10:00:00Z',
};

describe('normalization helpers', () => {
  it('normalizes amount text', () => {
    expect(normalizeAmountText('$42.19')).toBe(42.19);
    expect(normalizeAmountText('-$12.00')).toBe(-12);
    expect(normalizeAmountText('($7.50)')).toBe(-7.5);
    expect(normalizeAmountText(null)).toBeNull();
  });

  it('normalizes common date text with month hints', () => {
    expect(normalizeDateText('2026/06/12')).toBe('2026-06-12');
    expect(normalizeDateText('Jun 5', '2026-06')).toBe('2026-06-05');
    expect(normalizeDateText('6/7', '2026-06')).toBe('2026-06-07');
    expect(normalizeDateText('unclear')).toBeNull();
  });

  it('masks long account identifiers', () => {
    expect(maskAccountLabel('Checking 123456789')).toBe('Checking *****6789');
    expect(maskAccountLabel(null)).toBe('Unknown account');
  });
});

describe('normalizeTransactionCandidate', () => {
  it('creates a stable transaction row from an extracted candidate', () => {
    const candidate: ExtractedTransactionCandidate = {
      row_index: 0,
      date_text: 'Jun 12',
      merchant_text: 'Trader Joes',
      amount_text: '$42.19',
      account_source_text: 'Visa 123456789',
      transaction_type_hint: 'expense',
      confidence: 0.93,
      evidence_text: 'Jun 12 Trader Joes $42.19',
    };

    const result = normalizeTransactionCandidate(candidate, context);

    expect(result.transaction).toMatchObject({
      source_document_id: 'drive-file-1',
      observed_month: '2026-06',
      transaction_date: '2026-06-12',
      merchant_normalized: 'Trader Joes',
      amount: 42.19,
      account_label: 'Visa *****6789',
      validation_status: 'valid',
      review_status: 'none',
    });
    expect(result.transaction.transaction_id).toMatch(/^txn_/);
    expect(result.reviewItems).toEqual([]);
  });

  it('routes missing or low-confidence fields to review', () => {
    const candidate: ExtractedTransactionCandidate = {
      row_index: 1,
      date_text: null,
      merchant_text: null,
      amount_text: null,
      account_source_text: null,
      transaction_type_hint: 'unknown',
      confidence: 0.4,
      evidence_text: 'blurred row',
    };

    const result = normalizeTransactionCandidate(candidate, context);

    expect(result.transaction.validation_status).toBe('needs_review');
    expect(result.transaction.review_status).toBe('pending');
    expect(result.reviewItems.length).toBeGreaterThanOrEqual(3);
    expect(result.reviewItems.map((item) => item.issue_type)).toContain('missing_field');
    expect(result.reviewItems.map((item) => item.issue_type)).toContain('low_confidence');
  });
});

describe('normalizeExtractionCandidates', () => {
  it('normalizes transaction and asset candidates together', () => {
    const output = normalizeExtractionCandidates(
      [
        {
          row_index: 0,
          date_text: '6/12',
          merchant_text: 'Payroll',
          amount_text: '$1000.00',
          account_source_text: 'Checking 123456789',
          transaction_type_hint: 'income',
          confidence: 0.9,
          evidence_text: 'Payroll $1000.00',
        },
      ],
      [
        {
          row_index: 0,
          account_label_text: 'Checking 123456789',
          balance_text: '$5,432.10',
          balance_type_hint: 'checking',
          observed_date_text: '6/30',
          confidence: 0.88,
          evidence_text: 'Available balance $5,432.10',
        },
      ],
      context
    );

    expect(output.transactions).toHaveLength(1);
    expect(output.assetSnapshots).toHaveLength(1);
    expect(output.assetSnapshots[0].balance).toBe(5432.1);
    expect(output.reviewItems).toEqual([]);
  });
});

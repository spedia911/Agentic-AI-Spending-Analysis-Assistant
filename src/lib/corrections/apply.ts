import crypto from 'crypto';
import { getEnv } from '../env';
import { initializeSpreadsheet, readRows, upsertRows } from '../google/sheets';
import { refreshSummaryTabs, type RefreshSummariesResult } from '../orchestrator/summarize';
import type { Correction, ReviewItem, Transaction } from '../../types/domain';

export interface ApplyReviewCorrectionInput {
  reviewItemId: string;
  fieldName: Correction['field_name'];
  newValue: string;
  applyFuture?: boolean;
  now?: string;
}

export interface ApplyReviewCorrectionResult {
  sheetId: string;
  transactionUpdated: boolean;
  reviewResolved: boolean;
  correctionsWritten: number;
  summaries: RefreshSummariesResult;
}

function stableHash(parts: Array<string | number | null | undefined>): string {
  return crypto
    .createHash('sha256')
    .update(parts.map((part) => String(part ?? '')).join('|'))
    .digest('hex')
    .slice(0, 16);
}

function normalizeMerchantKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, ' ').trim().replace(/\s+/g, ' ');
}

function applyTransactionField(transaction: Transaction, fieldName: Correction['field_name'], newValue: string, now: string): Transaction {
  if (fieldName === 'category') {
    return {
      ...transaction,
      category: newValue,
      category_confidence: 1,
      validation_status: transaction.validation_status === 'rejected' ? 'rejected' : 'valid',
      review_status: 'resolved',
      updated_at: now,
    };
  }

  if (fieldName === 'merchant_normalized') {
    return {
      ...transaction,
      merchant_normalized: newValue,
      review_status: 'resolved',
      updated_at: now,
    };
  }

  if (fieldName === 'amount') {
    const amount = Number(newValue);
    if (Number.isNaN(amount)) {
      throw new Error('Amount correction must be numeric.');
    }
    return {
      ...transaction,
      amount,
      review_status: 'resolved',
      updated_at: now,
    };
  }

  if (fieldName === 'date') {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(newValue)) {
      throw new Error('Date correction must use YYYY-MM-DD format.');
    }
    return {
      ...transaction,
      transaction_date: newValue,
      observed_month: newValue.slice(0, 7),
      review_status: 'resolved',
      updated_at: now,
    };
  }

  return transaction;
}

function oldValueForField(transaction: Transaction, fieldName: Correction['field_name']): string {
  if (fieldName === 'category') return transaction.category;
  if (fieldName === 'merchant_normalized') return transaction.merchant_normalized;
  if (fieldName === 'amount') return String(transaction.amount);
  if (fieldName === 'date') return transaction.transaction_date;
  return '';
}

export async function applyReviewCorrection(input: ApplyReviewCorrectionInput): Promise<ApplyReviewCorrectionResult> {
  const env = getEnv();
  const now = input.now ?? new Date().toISOString();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const reviewItems = await readRows<ReviewItem>(sheetId, 'ReviewQueue');
  const transactions = await readRows<Transaction>(sheetId, 'Transactions');
  const existingCorrections = await readRows<Correction>(sheetId, 'Corrections');

  const review = reviewItems.find((item) => item.review_item_id === input.reviewItemId);
  if (!review) {
    throw new Error('Review item not found: ' + input.reviewItemId);
  }
  if (review.target_type !== 'transaction') {
    throw new Error('Only transaction review corrections are supported in this workflow.');
  }

  const transaction = transactions.find((item) => item.transaction_id === review.target_id);
  if (!transaction) {
    throw new Error('Transaction not found for review item: ' + review.target_id);
  }

  const updatedTransaction = applyTransactionField(transaction, input.fieldName, input.newValue, now);
  const resolvedReview: ReviewItem = {
    ...review,
    status: 'resolved',
    user_answer: input.newValue,
    resolved_at: now,
  };

  const correction: Correction = {
    correction_id: 'correction_' + stableHash([review.review_item_id, input.fieldName, input.newValue]),
    target_type: 'transaction',
    target_id: transaction.transaction_id,
    field_name: input.fieldName,
    old_value: oldValueForField(transaction, input.fieldName),
    new_value: input.newValue,
    apply_future: input.applyFuture ?? false,
    created_at: now,
  };

  const correctionRows: Correction[] = [correction];
  if (input.applyFuture && input.fieldName === 'category') {
    correctionRows.push({
      correction_id: 'correction_' + stableHash(['merchant_rule', transaction.merchant_normalized, input.newValue]),
      target_type: 'merchant_rule',
      target_id: normalizeMerchantKey(transaction.merchant_normalized),
      field_name: 'category',
      old_value: transaction.category,
      new_value: input.newValue,
      apply_future: true,
      created_at: now,
    });
  }

  await upsertRows<Transaction>(sheetId, 'Transactions', 'transaction_id', [updatedTransaction]);
  await upsertRows<ReviewItem>(sheetId, 'ReviewQueue', 'review_item_id', [resolvedReview]);
  await upsertRows<Correction>(sheetId, 'Corrections', 'correction_id', [...existingCorrections, ...correctionRows]);
  const summaries = await refreshSummaryTabs();

  return {
    sheetId,
    transactionUpdated: true,
    reviewResolved: true,
    correctionsWritten: correctionRows.length,
    summaries,
  };
}

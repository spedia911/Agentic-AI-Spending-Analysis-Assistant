import crypto from 'crypto';
import { getEnv } from '../env';
import { initializeSpreadsheet, readRows, upsertRows } from '../google/sheets';
import { refreshSummaryTabs, type RefreshSummariesResult } from '../orchestrator/summarize';
import type { AssetSnapshot, Correction, ReviewItem, Transaction } from '../../types/domain';

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

export interface BatchCorrectionInput {
  reviewItemId?: string;
  transactionId?: string;
  fieldName: Correction['field_name'];
  newValue: string;
  applyFuture?: boolean;
}

export interface ApplyBatchCorrectionsInput {
  corrections: BatchCorrectionInput[];
  now?: string;
}

export interface ApplyBatchCorrectionsResult {
  sheetId: string;
  transactionsUpdated: number;
  assetSnapshotsUpdated: number;
  reviewsResolved: number;
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

  if (fieldName === 'observed_month') {
    if (!/^\d{4}-\d{2}$/.test(newValue)) {
      throw new Error('Month correction must use YYYY-MM format.');
    }
    return {
      ...transaction,
      observed_month: newValue,
      review_status: 'resolved',
      updated_at: now,
    };
  }

  if (fieldName === 'transaction_type') {
    if (!['expense', 'income', 'transfer', 'payment', 'fee', 'refund', 'unknown'].includes(newValue)) {
      throw new Error('Transaction type correction is not supported: ' + newValue);
    }
    return {
      ...transaction,
      transaction_type: newValue as Transaction['transaction_type'],
      review_status: 'resolved',
      updated_at: now,
    };
  }

  if (fieldName === 'validation_status') {
    if (!['valid', 'needs_review', 'rejected'].includes(newValue)) {
      throw new Error('Validation status correction is not supported: ' + newValue);
    }
    return {
      ...transaction,
      validation_status: newValue as Transaction['validation_status'],
      review_status: newValue === 'needs_review' ? 'pending' : 'resolved',
      updated_at: now,
    };
  }

  return transaction;
}

function applyAssetSnapshotField(assetSnapshot: AssetSnapshot, fieldName: Correction['field_name'], newValue: string): AssetSnapshot {
  if (fieldName === 'observed_month') {
    if (!/^\d{4}-\d{2}$/.test(newValue)) {
      throw new Error('Month correction must use YYYY-MM format.');
    }
    return { ...assetSnapshot, observed_month: newValue };
  }

  if (fieldName === 'observed_date' || fieldName === 'date') {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(newValue)) {
      throw new Error('Asset snapshot date correction must use YYYY-MM-DD format.');
    }
    return { ...assetSnapshot, observed_date: newValue, observed_month: newValue.slice(0, 7) };
  }

  if (fieldName === 'balance') {
    const balance = Number(newValue);
    if (Number.isNaN(balance)) {
      throw new Error('Balance correction must be numeric.');
    }
    return { ...assetSnapshot, balance };
  }

  if (fieldName === 'account_label') {
    return { ...assetSnapshot, account_label: newValue };
  }

  if (fieldName === 'balance_type') {
    if (!['checking', 'savings', 'credit_available', 'credit_balance', 'unknown'].includes(newValue)) {
      throw new Error('Balance type correction is not supported: ' + newValue);
    }
    return { ...assetSnapshot, balance_type: newValue as AssetSnapshot['balance_type'] };
  }

  if (fieldName === 'review_status') {
    return assetSnapshot;
  }

  throw new Error('Correction field is not supported for asset snapshots: ' + fieldName);
}

function oldTransactionValueForField(transaction: Transaction, fieldName: Correction['field_name']): string {
  if (fieldName === 'category') return transaction.category;
  if (fieldName === 'merchant_normalized') return transaction.merchant_normalized;
  if (fieldName === 'amount') return String(transaction.amount);
  if (fieldName === 'date') return transaction.transaction_date;
  if (fieldName === 'observed_month') return transaction.observed_month;
  if (fieldName === 'transaction_type') return transaction.transaction_type;
  if (fieldName === 'validation_status') return transaction.validation_status;
  return '';
}

function oldAssetSnapshotValueForField(assetSnapshot: AssetSnapshot, fieldName: Correction['field_name']): string {
  if (fieldName === 'observed_month') return assetSnapshot.observed_month;
  if (fieldName === 'observed_date' || fieldName === 'date') return assetSnapshot.observed_date;
  if (fieldName === 'balance') return String(assetSnapshot.balance);
  if (fieldName === 'account_label') return assetSnapshot.account_label;
  if (fieldName === 'balance_type') return assetSnapshot.balance_type;
  if (fieldName === 'review_status') return 'pending';
  return '';
}

export async function applyBatchCorrections(input: ApplyBatchCorrectionsInput): Promise<ApplyBatchCorrectionsResult> {
  const env = getEnv();
  const now = input.now ?? new Date().toISOString();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const reviewItems = await readRows<ReviewItem>(sheetId, 'ReviewQueue');
  const transactions = await readRows<Transaction>(sheetId, 'Transactions');
  const assetSnapshots = await readRows<AssetSnapshot>(sheetId, 'AssetSnapshots');
  const transactionById = new Map(transactions.map((transaction) => [transaction.transaction_id, transaction]));
  const assetSnapshotById = new Map(assetSnapshots.map((assetSnapshot) => [assetSnapshot.asset_snapshot_id, assetSnapshot]));
  const reviewById = new Map(reviewItems.map((review) => [review.review_item_id, review]));
  const updatedTransactions = new Map<string, Transaction>();
  const updatedAssetSnapshots = new Map<string, AssetSnapshot>();
  const resolvedReviews = new Map<string, ReviewItem>();
  const correctionRows: Correction[] = [];

  for (const item of input.corrections) {
    const review = item.reviewItemId ? reviewById.get(item.reviewItemId) : null;
    if (item.reviewItemId && !review) {
      throw new Error('Review item not found: ' + item.reviewItemId);
    }
    if (review && review.target_type !== 'transaction' && review.target_type !== 'asset_snapshot') {
      throw new Error('Only transaction and asset snapshot review corrections are supported in this workflow.');
    }

    const targetType: Correction['target_type'] = review?.target_type === 'asset_snapshot' ? 'asset_snapshot' : 'transaction';
    const targetId = item.transactionId ?? review?.target_id;
    if (!targetId) {
      throw new Error('Correction must include a transactionId or reviewItemId.');
    }

    let oldValue = '';
    if (targetType === 'transaction') {
      const currentTransaction = updatedTransactions.get(targetId) ?? transactionById.get(targetId);
      if (!currentTransaction) {
        throw new Error('Transaction not found for correction: ' + targetId);
      }

      const updatedTransaction = applyTransactionField(currentTransaction, item.fieldName, item.newValue, now);
      updatedTransactions.set(targetId, updatedTransaction);
      oldValue = oldTransactionValueForField(currentTransaction, item.fieldName);
    } else {
      const currentAssetSnapshot = updatedAssetSnapshots.get(targetId) ?? assetSnapshotById.get(targetId);
      if (!currentAssetSnapshot) {
        throw new Error('Asset snapshot not found for correction: ' + targetId);
      }

      const updatedAssetSnapshot = applyAssetSnapshotField(currentAssetSnapshot, item.fieldName, item.newValue);
      updatedAssetSnapshots.set(targetId, updatedAssetSnapshot);
      oldValue = oldAssetSnapshotValueForField(currentAssetSnapshot, item.fieldName);
    }

    if (review) {
      resolvedReviews.set(review.review_item_id, {
        ...review,
        status: item.fieldName === 'review_status' && item.newValue === 'ignored' ? 'ignored' : 'resolved',
        user_answer: item.newValue,
        resolved_at: now,
      });
    }

    correctionRows.push({
      correction_id: 'correction_' + stableHash([item.reviewItemId ?? targetId, item.fieldName, item.newValue]),
      target_type: targetType,
      target_id: targetId,
      field_name: item.fieldName,
      old_value: oldValue,
      new_value: item.newValue,
      apply_future: item.applyFuture ?? false,
      created_at: now,
    });

    if (targetType === 'transaction' && item.applyFuture && item.fieldName === 'category') {
      const currentTransaction = updatedTransactions.get(targetId) ?? transactionById.get(targetId);
      if (!currentTransaction) {
        throw new Error('Transaction not found for future correction: ' + targetId);
      }
      correctionRows.push({
        correction_id: 'correction_' + stableHash(['merchant_rule', currentTransaction.merchant_normalized, item.newValue]),
        target_type: 'merchant_rule',
        target_id: normalizeMerchantKey(currentTransaction.merchant_normalized),
        field_name: 'category',
        old_value: currentTransaction.category,
        new_value: item.newValue,
        apply_future: true,
        created_at: now,
      });
    }
  }

  if (updatedTransactions.size > 0) {
    await upsertRows<Transaction>(sheetId, 'Transactions', 'transaction_id', Array.from(updatedTransactions.values()));
  }
  if (updatedAssetSnapshots.size > 0) {
    await upsertRows<AssetSnapshot>(sheetId, 'AssetSnapshots', 'asset_snapshot_id', Array.from(updatedAssetSnapshots.values()));
  }
  if (resolvedReviews.size > 0) {
    await upsertRows<ReviewItem>(sheetId, 'ReviewQueue', 'review_item_id', Array.from(resolvedReviews.values()));
  }
  await upsertRows<Correction>(sheetId, 'Corrections', 'correction_id', correctionRows);
  const summaries = await refreshSummaryTabs();

  return {
    sheetId,
    transactionsUpdated: updatedTransactions.size,
    assetSnapshotsUpdated: updatedAssetSnapshots.size,
    reviewsResolved: resolvedReviews.size,
    correctionsWritten: correctionRows.length,
    summaries,
  };
}

export async function applyReviewCorrection(input: ApplyReviewCorrectionInput): Promise<ApplyReviewCorrectionResult> {
  const result = await applyBatchCorrections({
    corrections: [
      {
        reviewItemId: input.reviewItemId,
        fieldName: input.fieldName,
        newValue: input.newValue,
        applyFuture: input.applyFuture,
      },
    ],
    now: input.now,
  });

  return {
    sheetId: result.sheetId,
    transactionUpdated: result.transactionsUpdated > 0,
    reviewResolved: result.reviewsResolved > 0,
    correctionsWritten: result.correctionsWritten,
    summaries: result.summaries,
  };
}

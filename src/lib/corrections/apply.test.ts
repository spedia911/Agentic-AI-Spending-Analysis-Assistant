import { beforeEach, describe, expect, it, vi } from 'vitest';
import { applyBatchCorrections, applyReviewCorrection } from './apply';
import type { AssetSnapshot, ReviewItem, SourceDocument, Transaction } from '../../types/domain';

const mocks = vi.hoisted(() => ({
  initializeSpreadsheet: vi.fn(),
  readRows: vi.fn(),
  refreshSummaryTabs: vi.fn(),
  upsertRows: vi.fn(),
}));

vi.mock('../env', () => ({
  getEnv: vi.fn(() => ({
    GOOGLE_SHEET_ID: 'sheet-123',
    GOOGLE_DRIVE_FOLDER_ID: 'folder-123',
    GOOGLE_SERVICE_ACCOUNT_KEY: '{}',
    AI_PROVIDER: 'gemini',
    AI_API_KEY: 'key',
    SINGLE_USER_EMAIL: 'user@example.com',
    LOW_CONFIDENCE_THRESHOLD: 0.75,
    TIMEZONE: 'America/Los_Angeles',
    SOURCE_IMAGE_RETENTION_DAYS: 30,
    NODE_ENV: 'test',
  })),
}));

vi.mock('../google/sheets', () => ({
  initializeSpreadsheet: mocks.initializeSpreadsheet,
  readRows: mocks.readRows,
  upsertRows: mocks.upsertRows,
}));

vi.mock('../orchestrator/summarize', () => ({
  refreshSummaryTabs: mocks.refreshSummaryTabs,
}));

const transaction: Transaction = {
  transaction_id: 'txn-1',
  source_document_id: 'source-1',
  observed_month: '2026-06',
  transaction_date: '2026-06-12',
  merchant_raw: 'Amazon Marketplace',
  merchant_normalized: 'Amazon Marketplace',
  amount: 42.19,
  transaction_type: 'expense',
  account_label: 'Visa *1234',
  category: 'shopping',
  category_confidence: 0.78,
  extraction_confidence: 0.9,
  validation_status: 'needs_review',
  review_status: 'pending',
  evidence_text: 'Amazon Marketplace $42.19',
  created_at: '2026-06-29T10:00:00Z',
  updated_at: '2026-06-29T10:00:00Z',
};

const review: ReviewItem = {
  review_item_id: 'review-1',
  target_type: 'transaction',
  target_id: 'txn-1',
  issue_type: 'unclear_category',
  severity: 'low',
  question: 'Is Amazon groceries?',
  suggested_options: ['groceries', 'shopping'],
  status: 'pending',
  user_answer: null,
  created_at: '2026-06-29T10:00:00Z',
  resolved_at: null,
};

const assetSnapshot: AssetSnapshot = {
  asset_snapshot_id: 'asset-1',
  source_document_id: 'source-1',
  observed_month: '2026-06',
  observed_date: '2026-06-30',
  account_label: 'Card Balance',
  balance: 1234.56,
  balance_type: 'credit_balance',
  confidence: 0.62,
  evidence_text: 'Card Balance $1,234.56',
  created_at: '2026-06-29T10:00:00Z',
};

const assetReview: ReviewItem = {
  review_item_id: 'review-asset-1',
  target_type: 'asset_snapshot',
  target_id: 'asset-1',
  issue_type: 'low_confidence',
  severity: 'medium',
  question: 'Please review the balance snapshot for Card Balance.',
  suggested_options: [],
  status: 'pending',
  user_answer: null,
  created_at: '2026-06-29T10:00:00Z',
  resolved_at: null,
};

const sourceDocument: SourceDocument = {
  source_document_id: 'source-1',
  source_type: 'drive',
  file_name: 'june-card.png',
  mime_type: 'image/png',
  created_time: '2026-06-29T10:00:00Z',
  modified_time: '2026-06-29T10:00:00Z',
  processed_at: '2026-06-29T10:00:00Z',
  status: 'error',
  error_summary: 'Processing failed.',
};

const sourceReview: ReviewItem = {
  review_item_id: 'review-source-1',
  target_type: 'source_document',
  target_id: 'source-1',
  issue_type: 'anomaly',
  severity: 'high',
  question: 'This source failed processing. Retry it?',
  suggested_options: ['pending', 'skipped'],
  status: 'pending',
  user_answer: null,
  created_at: '2026-06-29T10:00:00Z',
  resolved_at: null,
};

describe('applyReviewCorrection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.initializeSpreadsheet.mockReset();
    mocks.readRows.mockReset();
    mocks.upsertRows.mockReset();
    mocks.refreshSummaryTabs.mockReset();
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readRows
      .mockResolvedValueOnce([review])
      .mockResolvedValueOnce([transaction])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);
    mocks.upsertRows.mockResolvedValue(undefined);
    mocks.refreshSummaryTabs.mockResolvedValue({
      sheetId: 'sheet-123',
      monthlyRowsWritten: 2,
      quarterlyRowsWritten: 1,
      assetTrendRowsWritten: 1,
      anomaliesWritten: 1,
    });
  });

  it('updates a transaction category, resolves review, and writes merchant memory', async () => {
    const result = await applyReviewCorrection({
      reviewItemId: 'review-1',
      fieldName: 'category',
      newValue: 'groceries',
      applyFuture: true,
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.correctionsWritten).toBe(2);
    expect(result.summaries.monthlyRowsWritten).toBe(2);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Transactions',
      'transaction_id',
      [expect.objectContaining({ category: 'groceries', category_confidence: 1, review_status: 'resolved' })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'ReviewQueue',
      'review_item_id',
      [expect.objectContaining({ status: 'resolved', user_answer: 'groceries' })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Corrections',
      'correction_id',
      expect.arrayContaining([
        expect.objectContaining({ target_type: 'transaction', target_id: 'txn-1', new_value: 'groceries' }),
        expect.objectContaining({ target_type: 'merchant_rule', target_id: 'amazon marketplace', apply_future: true }),
      ])
    );
    expect(mocks.refreshSummaryTabs).toHaveBeenCalledOnce();
  });

  it('rejects nonnumeric amount corrections', async () => {
    await expect(
      applyReviewCorrection({
        reviewItemId: 'review-1',
        fieldName: 'amount',
        newValue: 'not a number',
      })
    ).rejects.toThrow('Amount correction must be numeric.');
  });

  it('updates transaction type corrections for spend versus income fixes', async () => {
    const result = await applyReviewCorrection({
      reviewItemId: 'review-1',
      fieldName: 'transaction_type',
      newValue: 'income',
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.transactionUpdated).toBe(true);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Transactions',
      'transaction_id',
      [expect.objectContaining({ transaction_type: 'income', review_status: 'resolved' })]
    );
  });

  it('applies multiple corrections and refreshes summaries once', async () => {
    const secondTransaction = {
      ...transaction,
      transaction_id: 'txn-2',
      merchant_normalized: 'Trader Joes',
      category: 'groceries',
    };
    const secondReview = {
      ...review,
      review_item_id: 'review-2',
      target_id: 'txn-2',
      question: 'Is Trader Joes dining?',
    };
    mocks.readRows.mockReset();
    mocks.readRows
      .mockResolvedValueOnce([review, secondReview])
      .mockResolvedValueOnce([transaction, secondTransaction])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);

    const result = await applyBatchCorrections({
      corrections: [
        { reviewItemId: 'review-1', fieldName: 'category', newValue: 'shopping' },
        { reviewItemId: 'review-2', fieldName: 'category', newValue: 'dining' },
      ],
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.transactionsUpdated).toBe(2);
    expect(result.reviewsResolved).toBe(2);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Transactions',
      'transaction_id',
      expect.arrayContaining([
        expect.objectContaining({ transaction_id: 'txn-1', category: 'shopping' }),
        expect.objectContaining({ transaction_id: 'txn-2', category: 'dining' }),
      ])
    );
    expect(mocks.refreshSummaryTabs).toHaveBeenCalledOnce();
  });

  it('updates observed month without requiring an exact date', async () => {
    const result = await applyBatchCorrections({
      corrections: [
        { transactionId: 'txn-1', fieldName: 'observed_month', newValue: '2026-07' },
      ],
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.transactionsUpdated).toBe(1);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Transactions',
      'transaction_id',
      [expect.objectContaining({ observed_month: '2026-07', transaction_date: '2026-06-12' })]
    );
  });

  it('marks a duplicate transaction as rejected so summaries exclude it', async () => {
    const result = await applyBatchCorrections({
      corrections: [
        { reviewItemId: 'review-1', fieldName: 'validation_status', newValue: 'rejected' },
      ],
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.transactionsUpdated).toBe(1);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Transactions',
      'transaction_id',
      [expect.objectContaining({ validation_status: 'rejected', review_status: 'resolved' })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'ReviewQueue',
      'review_item_id',
      [expect.objectContaining({ status: 'resolved', user_answer: 'rejected' })]
    );
  });

  it('resolves an asset snapshot review without forcing Sheet-only handling', async () => {
    mocks.readRows.mockReset();
    mocks.readRows
      .mockResolvedValueOnce([assetReview])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([assetSnapshot])
      .mockResolvedValueOnce([]);

    const result = await applyBatchCorrections({
      corrections: [
        { reviewItemId: 'review-asset-1', fieldName: 'review_status', newValue: 'resolved' },
      ],
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.assetSnapshotsUpdated).toBe(1);
    expect(result.reviewsResolved).toBe(1);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'AssetSnapshots',
      'asset_snapshot_id',
      [expect.objectContaining({ asset_snapshot_id: 'asset-1', balance: 1234.56 })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'ReviewQueue',
      'review_item_id',
      [expect.objectContaining({ status: 'resolved', user_answer: 'resolved' })]
    );
  });

  it('updates asset snapshot balance details from the review page', async () => {
    mocks.readRows.mockReset();
    mocks.readRows
      .mockResolvedValueOnce([assetReview])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([assetSnapshot])
      .mockResolvedValueOnce([]);

    const result = await applyBatchCorrections({
      corrections: [
        { reviewItemId: 'review-asset-1', fieldName: 'balance', newValue: '987.65' },
      ],
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.assetSnapshotsUpdated).toBe(1);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'AssetSnapshots',
      'asset_snapshot_id',
      [expect.objectContaining({ balance: 987.65 })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Corrections',
      'correction_id',
      [expect.objectContaining({ target_type: 'asset_snapshot', field_name: 'balance', old_value: '1234.56', new_value: '987.65' })]
    );
  });

  it('updates a source document review so failed files can be retried from the review page', async () => {
    mocks.readRows.mockReset();
    mocks.readRows
      .mockResolvedValueOnce([sourceReview])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([sourceDocument]);

    const result = await applyBatchCorrections({
      corrections: [
        { reviewItemId: 'review-source-1', fieldName: 'source_status', newValue: 'pending' },
      ],
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.sourceDocumentsUpdated).toBe(1);
    expect(result.reviewsResolved).toBe(1);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'SourceDocuments',
      'source_document_id',
      [expect.objectContaining({ source_document_id: 'source-1', status: 'pending', error_summary: null })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Corrections',
      'correction_id',
      [expect.objectContaining({ target_type: 'source_document', field_name: 'source_status', old_value: 'error', new_value: 'pending' })]
    );
  });
});

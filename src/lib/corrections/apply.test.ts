import { beforeEach, describe, expect, it, vi } from 'vitest';
import { applyReviewCorrection } from './apply';
import type { ReviewItem, Transaction } from '../../types/domain';

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

describe('applyReviewCorrection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readRows
      .mockResolvedValueOnce([review])
      .mockResolvedValueOnce([transaction])
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
});

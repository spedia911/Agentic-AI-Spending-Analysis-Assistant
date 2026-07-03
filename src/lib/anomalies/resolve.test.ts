import { beforeEach, describe, expect, it, vi } from 'vitest';
import { resolveAnomaly } from './resolve';
import type { Anomaly, Transaction } from '../../types/domain';

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

const anomaly: Anomaly = {
  anomaly_id: 'anomaly-1',
  anomaly_type: 'duplicate_charge',
  severity: 'medium',
  month: '2026-06',
  related_record_ids: ['txn-1', 'txn-2'],
  summary: 'Possible duplicate charge.',
  suggested_action: 'Review both rows.',
  status: 'open',
  created_at: '2026-06-29T10:00:00Z',
};

const transaction: Transaction = {
  transaction_id: 'txn-2',
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
  validation_status: 'valid',
  review_status: 'none',
  evidence_text: 'Amazon Marketplace $42.19',
  created_at: '2026-06-29T10:00:00Z',
  updated_at: '2026-06-29T10:00:00Z',
};

describe('resolveAnomaly', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readRows.mockReset();
    mocks.upsertRows.mockResolvedValue(undefined);
    mocks.refreshSummaryTabs.mockResolvedValue({
      sheetId: 'sheet-123',
      monthlyRowsWritten: 2,
      quarterlyRowsWritten: 1,
      assetTrendRowsWritten: 1,
      anomaliesWritten: 0,
    });
  });

  it('ignores an anomaly and writes an audit correction', async () => {
    mocks.readRows.mockResolvedValueOnce([anomaly]);

    const result = await resolveAnomaly({
      anomalyId: 'anomaly-1',
      decision: 'ignored',
      now: '2026-06-29T11:00:00Z',
    });

    expect(result).toMatchObject({
      anomalyUpdated: true,
      transactionUpdated: false,
      correctionsWritten: 1,
      summaries: null,
    });
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Anomalies',
      'anomaly_id',
      [expect.objectContaining({ anomaly_id: 'anomaly-1', status: 'ignored' })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Corrections',
      'correction_id',
      [expect.objectContaining({ target_type: 'anomaly', field_name: 'anomaly_status', old_value: 'open', new_value: 'ignored' })]
    );
    expect(mocks.refreshSummaryTabs).not.toHaveBeenCalled();
  });

  it('marks one duplicate transaction as rejected and refreshes summaries', async () => {
    mocks.readRows
      .mockResolvedValueOnce([anomaly])
      .mockResolvedValueOnce([transaction]);

    const result = await resolveAnomaly({
      anomalyId: 'anomaly-1',
      decision: 'mark_duplicate',
      duplicateTransactionId: 'txn-2',
      now: '2026-06-29T11:00:00Z',
    });

    expect(result.transactionUpdated).toBe(true);
    expect(result.correctionsWritten).toBe(2);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Transactions',
      'transaction_id',
      [expect.objectContaining({ transaction_id: 'txn-2', validation_status: 'rejected', review_status: 'resolved' })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Corrections',
      'correction_id',
      expect.arrayContaining([
        expect.objectContaining({ target_type: 'anomaly', field_name: 'anomaly_status', new_value: 'resolved' }),
        expect.objectContaining({ target_type: 'transaction', field_name: 'validation_status', old_value: 'valid', new_value: 'rejected' }),
      ])
    );
    expect(mocks.refreshSummaryTabs).toHaveBeenCalledOnce();
  });

  it('rejects duplicate decisions for unrelated transaction IDs', async () => {
    mocks.readRows.mockResolvedValueOnce([anomaly]);

    await expect(
      resolveAnomaly({
        anomalyId: 'anomaly-1',
        decision: 'mark_duplicate',
        duplicateTransactionId: 'txn-9',
      })
    ).rejects.toThrow('Selected transaction is not related to this anomaly.');
  });
});

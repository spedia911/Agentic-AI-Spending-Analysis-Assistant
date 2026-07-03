import { beforeEach, describe, expect, it, vi } from 'vitest';
import { preserveAnomalyDecisions, refreshSummaryTabs } from './summarize';
import type { Anomaly, AssetSnapshot, Transaction } from '../../types/domain';

const mocks = vi.hoisted(() => ({
  initializeSpreadsheet: vi.fn(),
  readRows: vi.fn(),
  replaceRows: vi.fn(),
}));

vi.mock('../env', () => ({
  getEnv: vi.fn(() => ({
    GOOGLE_DRIVE_FOLDER_ID: 'folder-123',
    GOOGLE_SHEET_ID: 'sheet-123',
    GOOGLE_SERVICE_ACCOUNT_KEY: '{}',
    AI_PROVIDER: 'gemini',
    AI_MODEL: 'gemini-test',
    AI_API_KEY: 'key-xyz',
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
  replaceRows: mocks.replaceRows,
}));

function anomaly(id: string, status: Anomaly['status']): Anomaly {
  return {
    anomaly_id: id,
    anomaly_type: 'duplicate_charge',
    severity: 'medium',
    month: '2026-06',
    related_record_ids: ['txn-1', 'txn-2'],
    summary: 'Possible duplicate charge.',
    suggested_action: 'Review both rows.',
    status,
    created_at: '2026-06-29T10:00:00Z',
  };
}

describe('preserveAnomalyDecisions', () => {
  it('keeps resolved and ignored decisions when anomalies are regenerated', () => {
    const generated = [
      { ...anomaly('anomaly-1', 'open'), created_at: '2026-06-30T10:00:00Z' },
      anomaly('anomaly-2', 'open'),
    ];
    const existing = [
      anomaly('anomaly-1', 'ignored'),
      anomaly('unrelated', 'resolved'),
    ];

    expect(preserveAnomalyDecisions(generated, existing)).toEqual([
      expect.objectContaining({ anomaly_id: 'anomaly-1', status: 'ignored', created_at: '2026-06-29T10:00:00Z' }),
      expect.objectContaining({ anomaly_id: 'anomaly-2', status: 'open' }),
    ]);
  });
});

function transaction(overrides: Partial<Transaction>): Transaction {
  return {
    transaction_id: 'txn-1',
    source_document_id: 'source-1',
    observed_month: '2026-06',
    transaction_date: '2026-06-12',
    merchant_raw: 'Trader Joes',
    merchant_normalized: 'Trader Joes',
    amount: 42,
    transaction_type: 'expense',
    account_label: 'Visa *1234',
    category: 'groceries',
    category_confidence: 0.95,
    extraction_confidence: 0.9,
    validation_status: 'valid',
    review_status: 'none',
    evidence_text: 'Trader Joes $42',
    created_at: '2026-06-29T10:00:00Z',
    updated_at: '2026-06-29T10:00:00Z',
    ...overrides,
  };
}

function assetSnapshot(overrides: Partial<AssetSnapshot>): AssetSnapshot {
  return {
    asset_snapshot_id: 'asset-1',
    source_document_id: 'source-1',
    observed_month: '2026-06',
    observed_date: '2026-06-30',
    account_label: 'Checking *1234',
    balance: 1000,
    balance_type: 'checking',
    confidence: 0.9,
    evidence_text: 'Balance $1000',
    created_at: '2026-06-29T10:00:00Z',
    ...overrides,
  };
}

describe('refreshSummaryTabs', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.replaceRows.mockResolvedValue(undefined);
  });

  it('writes generated category, cash-flow, asset trend, and anomaly tabs', async () => {
    mocks.readRows
      .mockResolvedValueOnce([
        transaction({ amount: 100, category: 'groceries' }),
        transaction({ amount: 2500, transaction_type: 'income', category: 'income' }),
      ])
      .mockResolvedValueOnce([assetSnapshot({ balance: 2000 })])
      .mockResolvedValueOnce([]);

    const result = await refreshSummaryTabs();

    expect(result).toMatchObject({
      sheetId: 'sheet-123',
      monthlyRowsWritten: 2,
      quarterlyRowsWritten: 2,
      cashFlowRowsWritten: 1,
      assetTrendRowsWritten: 1,
    });
    expect(mocks.replaceRows).toHaveBeenCalledWith('sheet-123', 'CashFlowSummary', [
      expect.objectContaining({
        month: '2026-06',
        spending_total: 100,
        income_total: 2500,
        net_cash_flow: 2400,
      }),
    ]);
  });
});

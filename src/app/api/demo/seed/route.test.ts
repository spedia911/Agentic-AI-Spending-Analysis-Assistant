import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  getEnv: vi.fn(),
  initializeSpreadsheet: vi.fn(),
  refreshSummaryTabs: vi.fn(),
  upsertRows: vi.fn(),
}));

vi.mock('../../../../lib/env', () => ({
  getEnv: mocks.getEnv,
}));

vi.mock('../../../../lib/google/sheets', () => ({
  initializeSpreadsheet: mocks.initializeSpreadsheet,
  upsertRows: mocks.upsertRows,
}));

vi.mock('../../../../lib/orchestrator/summarize', () => ({
  refreshSummaryTabs: mocks.refreshSummaryTabs,
}));

import { POST } from './route';

describe('demo seed route', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getEnv.mockReturnValue({ GOOGLE_SHEET_ID: 'configured-sheet' });
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.refreshSummaryTabs.mockResolvedValue({ monthlySummaries: 2, anomalies: 2 });
  });

  it('writes sanitized demo rows and refreshes generated summaries', async () => {
    const response = await POST();
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(mocks.initializeSpreadsheet).toHaveBeenCalledWith('configured-sheet');
    expect(mocks.upsertRows).toHaveBeenCalledTimes(4);
    expect(mocks.refreshSummaryTabs).toHaveBeenCalledTimes(1);
    expect(body).toEqual({
      sheetId: 'sheet-123',
      sourceDocuments: 2,
      transactions: 6,
      assetSnapshots: 2,
      reviewItems: 1,
      summaries: { monthlySummaries: 2, anomalies: 2 },
    });

    const transactionCall = mocks.upsertRows.mock.calls.find((call) => call[1] === 'Transactions');
    expect(transactionCall?.[2]).toBe('transaction_id');
    expect(transactionCall?.[3]).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          merchant_normalized: 'Amazon Marketplace',
          review_status: 'pending',
          evidence_text: 'Demo sanitized evidence for Amazon Marketplace',
        }),
      ])
    );

    const sourceCall = mocks.upsertRows.mock.calls.find((call) => call[1] === 'SourceDocuments');
    expect(sourceCall?.[3]).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          source_type: 'upload',
          file_name: 'demo-credit-card-screenshot.png',
          status: 'processed',
        }),
      ])
    );
  });

  it('returns an error response when demo seeding fails', async () => {
    mocks.initializeSpreadsheet.mockRejectedValue(new Error('sheet unavailable'));

    const response = await POST();
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(body).toEqual({
      error: 'Demo seed failed',
      detail: 'sheet unavailable',
    });
  });
});

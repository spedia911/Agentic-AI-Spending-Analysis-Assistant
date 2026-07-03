import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SnapshotReviewStage } from './snapshot-review';

const mocks = vi.hoisted(() => ({
  getEnv: vi.fn(),
  initializeSpreadsheet: vi.fn(),
  readFile: vi.fn(),
  rm: vi.fn(),
  upsertRows: vi.fn(),
  writeFile: vi.fn(),
  mkdir: vi.fn(),
  refreshSummaryTabs: vi.fn(),
}));

vi.mock('fs/promises', () => ({
  default: {
    mkdir: mocks.mkdir,
    readFile: mocks.readFile,
    rm: mocks.rm,
    writeFile: mocks.writeFile,
  },
}));

vi.mock('../env', () => ({
  getEnv: mocks.getEnv,
}));

vi.mock('../google/sheets', () => ({
  initializeSpreadsheet: mocks.initializeSpreadsheet,
  readRows: vi.fn(),
  upsertRows: mocks.upsertRows,
}));

vi.mock('../orchestrator/summarize', () => ({
  refreshSummaryTabs: mocks.refreshSummaryTabs,
}));

import { commitSnapshotReviewStage, updateSnapshotReviewStage } from './snapshot-review';

const stage: SnapshotReviewStage = {
  stageId: 'stage-123',
  createdAt: '2026-06-01T00:00:00Z',
  updatedAt: '2026-06-01T00:00:00Z',
  snapshots: [
    {
      selected: true,
      source: {
        source_document_id: 'source-1',
        source_type: 'drive',
        file_name: 'card.png',
        mime_type: 'image/png',
        created_time: '2026-06-01T00:00:00Z',
        modified_time: '2026-06-01T00:00:00Z',
        processed_at: null,
        status: 'pending',
        error_summary: null,
      },
      transactions: [
        {
          transaction_id: 'txn-1',
          source_document_id: 'source-1',
          observed_month: '2026-06',
          transaction_date: '2026-06-02',
          merchant_raw: 'Demo Merchant',
          merchant_normalized: 'Demo Merchant',
          amount: 10,
          transaction_type: 'expense',
          account_label: 'Demo *1234',
          category: 'shopping',
          category_confidence: 0.7,
          extraction_confidence: 0.9,
          validation_status: 'needs_review',
          review_status: 'pending',
          evidence_text: 'Demo evidence',
          created_at: '2026-06-01T00:00:00Z',
          updated_at: '2026-06-01T00:00:00Z',
        },
      ],
      assetSnapshots: [
        {
          asset_snapshot_id: 'asset-1',
          source_document_id: 'source-1',
          observed_month: '2026-06',
          observed_date: '2026-06-02',
          account_label: 'Checking *1234',
          balance: 2000,
          balance_type: 'checking',
          confidence: 0.9,
          evidence_text: 'Balance evidence',
          created_at: '2026-06-01T00:00:00Z',
        },
      ],
      reviewItems: [
        {
          review_item_id: 'review-1',
          target_type: 'transaction',
          target_id: 'txn-1',
          issue_type: 'low_confidence',
          severity: 'medium',
          question: 'Review this transaction?',
          suggested_options: ['shopping', 'miscellaneous'],
          status: 'pending',
          user_answer: null,
          created_at: '2026-06-01T00:00:00Z',
          resolved_at: null,
        },
      ],
    },
  ],
};

function stageWithExcludedSnapshot(): SnapshotReviewStage {
  const clone = JSON.parse(JSON.stringify(stage)) as SnapshotReviewStage;
  const excluded = JSON.parse(JSON.stringify(clone.snapshots[0])) as SnapshotReviewStage['snapshots'][number];
  excluded.selected = false;
  excluded.source.source_document_id = 'source-2';
  excluded.source.file_name = 'old-card.png';
  excluded.transactions[0].transaction_id = 'txn-2';
  excluded.transactions[0].source_document_id = 'source-2';
  excluded.assetSnapshots[0].asset_snapshot_id = 'asset-2';
  excluded.assetSnapshots[0].source_document_id = 'source-2';
  excluded.reviewItems[0].review_item_id = 'review-2';
  excluded.reviewItems[0].target_id = 'txn-2';
  clone.snapshots.push(excluded);
  return clone;
}

describe('snapshot review staging', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getEnv.mockReturnValue({ GOOGLE_SHEET_ID: 'configured-sheet' });
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readFile.mockResolvedValue(JSON.stringify(stage));
    mocks.refreshSummaryTabs.mockResolvedValue({ anomaliesWritten: 0 });
  });

  it('updates staged transaction edits without writing to Sheets', async () => {
    const updated = await updateSnapshotReviewStage({
      stageId: 'stage-123',
      snapshots: [{ source_document_id: 'source-1', selected: false }],
      transactions: [{ transaction_id: 'txn-1', category: 'groceries', amount: 12.5 }],
    });

    expect(updated.snapshots[0].selected).toBe(false);
    expect(updated.snapshots[0].transactions[0]).toEqual(
      expect.objectContaining({
        amount: 12.5,
        category: 'groceries',
      })
    );
    expect(mocks.upsertRows).not.toHaveBeenCalled();
    expect(mocks.writeFile).toHaveBeenCalledWith(
      expect.stringContaining('snapshot-review-stage.json'),
      expect.stringContaining('"selected": false'),
      'utf-8'
    );
  });

  it('commits staged rows to Sheets, refreshes summaries, and clears the private stage file', async () => {
    const result = await commitSnapshotReviewStage('stage-123');

    expect(result).toEqual({
      sheetId: 'sheet-123',
      transactionsWritten: 1,
      assetSnapshotsWritten: 1,
      reviewItemsWritten: 1,
    });
    expect(mocks.initializeSpreadsheet).toHaveBeenCalledWith('configured-sheet');
    expect(mocks.upsertRows).toHaveBeenCalledTimes(4);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'SourceDocuments',
      'source_document_id',
      [expect.objectContaining({ source_document_id: 'source-1', status: 'processed', processed_at: expect.any(String) })]
    );
    expect(mocks.refreshSummaryTabs).toHaveBeenCalledTimes(1);
    expect(mocks.rm).toHaveBeenCalledWith(expect.stringContaining('snapshot-review-stage.json'), { force: true });
  });

  it('commits only snapshots selected by the reviewer', async () => {
    mocks.readFile.mockResolvedValue(JSON.stringify(stageWithExcludedSnapshot()));

    const result = await commitSnapshotReviewStage('stage-123');

    expect(result).toEqual({
      sheetId: 'sheet-123',
      transactionsWritten: 1,
      assetSnapshotsWritten: 1,
      reviewItemsWritten: 1,
    });
    const sourceUpsert = mocks.upsertRows.mock.calls.find((call) => call[1] === 'SourceDocuments');
    const transactionUpsert = mocks.upsertRows.mock.calls.find((call) => call[1] === 'Transactions');
    const assetUpsert = mocks.upsertRows.mock.calls.find((call) => call[1] === 'AssetSnapshots');
    const reviewUpsert = mocks.upsertRows.mock.calls.find((call) => call[1] === 'ReviewQueue');

    expect(sourceUpsert?.[3]).toHaveLength(1);
    expect(sourceUpsert?.[3][0]).toEqual(expect.objectContaining({ source_document_id: 'source-1' }));
    expect(transactionUpsert?.[3]).toHaveLength(1);
    expect(transactionUpsert?.[3][0]).toEqual(expect.objectContaining({ transaction_id: 'txn-1' }));
    expect(assetUpsert?.[3]).toHaveLength(1);
    expect(assetUpsert?.[3][0]).toEqual(expect.objectContaining({ asset_snapshot_id: 'asset-1' }));
    expect(reviewUpsert?.[3]).toHaveLength(1);
    expect(reviewUpsert?.[3][0]).toEqual(expect.objectContaining({ review_item_id: 'review-1' }));
  });

  it('rejects stale stage IDs before writing anything', async () => {
    await expect(commitSnapshotReviewStage('wrong-stage')).rejects.toThrow('Snapshot review stage not found. Import snapshots again.');

    expect(mocks.initializeSpreadsheet).not.toHaveBeenCalled();
    expect(mocks.upsertRows).not.toHaveBeenCalled();
    expect(mocks.rm).not.toHaveBeenCalled();
  });
});

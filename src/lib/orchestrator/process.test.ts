import { beforeEach, describe, expect, it, vi } from 'vitest';
import { inferExtractionMode, runPendingExtractionProcessing, sourceDocumentCachePath } from './process';
import type { SourceDocument } from '../../types/domain';
import type { VisionModelAdapter } from '../extraction';

const mocks = vi.hoisted(() => ({
  initializeSpreadsheet: vi.fn(),
  readRows: vi.fn(),
  upsertRows: vi.fn(),
  readFile: vi.fn(),
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
  upsertRows: mocks.upsertRows,
}));

vi.mock('fs/promises', () => ({
  default: {
    readFile: mocks.readFile,
  },
  readFile: mocks.readFile,
}));

const pendingSource: SourceDocument = {
  source_document_id: 'file-1',
  source_type: 'drive',
  file_name: 'June Card.png',
  mime_type: 'image/png',
  created_time: '2026-06-01T10:00:00Z',
  modified_time: '2026-06-01T10:00:00Z',
  processed_at: null,
  status: 'pending',
  error_summary: null,
};

const modelOutput = {
  source_document_id: 'file-1',
  screenshot_kind: 'credit_card',
  raw_text: 'Jun 12 Trader Joes $42.19',
  extraction_confidence: 0.9,
  transactions: [
    {
      row_index: 0,
      date_text: 'Jun 12',
      merchant_text: 'Trader Joes',
      amount_text: '$42.19',
      account_source_text: 'Visa 123456789',
      transaction_type_hint: 'expense',
      confidence: 0.92,
      evidence_text: 'Jun 12 Trader Joes $42.19',
    },
  ],
  asset_snapshots: [],
  warnings: [],
};

describe('processing helpers', () => {
  it('infers extraction mode from source names and cache paths', () => {
    expect(inferExtractionMode({ file_name: 'checking activity.png' })).toBe('bank_activity');
    expect(inferExtractionMode({ file_name: 'visa card.png' })).toBe('credit_card');
    expect(inferExtractionMode({ file_name: 'screenshot.png' })).toBe('mixed');
    expect(sourceDocumentCachePath(pendingSource, 'cache')).toContain('file-1-June_Card.png');
  });
});

describe('runPendingExtractionProcessing', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readRows.mockResolvedValueOnce([pendingSource]);
    mocks.readRows.mockResolvedValueOnce([]);
    mocks.upsertRows.mockResolvedValue(undefined);
    mocks.readFile.mockResolvedValue(Buffer.from('image-bytes'));
  });

  it('extracts, normalizes, writes downstream rows, and marks source processed', async () => {
    const model: VisionModelAdapter = {
      extractJson: vi.fn().mockResolvedValue(JSON.stringify(modelOutput)),
    };

    const result = await runPendingExtractionProcessing({
      model,
      localCacheDir: 'cache',
      now: '2026-06-29T10:00:00Z',
    });

    expect(result).toMatchObject({
      sourcesProcessed: 1,
      sourcesErrored: 0,
      transactionsWritten: 1,
      assetSnapshotsWritten: 0,
      reviewItemsWritten: 0,
    });
    expect(model.extractJson).toHaveBeenCalledWith(
      expect.objectContaining({
        prompt: expect.stringContaining('credit card screenshot'),
        image: expect.objectContaining({ mimeType: 'image/png' }),
      })
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'Transactions',
      'transaction_id',
      [expect.objectContaining({ merchant_normalized: 'Trader Joes', amount: 42.19, category: 'groceries' })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'SourceDocuments',
      'source_document_id',
      [expect.objectContaining({ source_document_id: 'file-1', status: 'processed' })]
    );
  });

  it('marks a source error when cached image reading fails', async () => {
    mocks.readFile.mockRejectedValueOnce(new Error('file missing 123456789'));

    const result = await runPendingExtractionProcessing({
      model: { extractJson: vi.fn() },
      localCacheDir: 'cache',
      now: '2026-06-29T10:00:00Z',
    });

    expect(result.sourcesErrored).toBe(1);
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'SourceDocuments',
      'source_document_id',
      [expect.objectContaining({ status: 'error', error_summary: expect.stringContaining('[number]') })]
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith('sheet-123', 'Transactions', 'transaction_id', []);
  });
});

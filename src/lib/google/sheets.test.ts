import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  initializeSpreadsheet,
  mapSheetRow,
  readTabRows,
  replaceTabRows,
  serializeSheetRow,
  SHEET_SCHEMAS,
  upsertTabRows,
} from './sheets';

vi.mock('./auth', () => ({
  getGoogleAuthClient: vi.fn(() => ({
    email: 'mock-sa@example.com',
  })),
}));

const mockSpreadsheetsGet = vi.fn();
const mockSpreadsheetsCreate = vi.fn();
const mockSpreadsheetsBatchUpdate = vi.fn();
const mockValuesGet = vi.fn();
const mockValuesUpdate = vi.fn();
const mockValuesClear = vi.fn();

vi.mock('googleapis', () => ({
  google: {
    sheets: () => ({
      spreadsheets: {
        get: mockSpreadsheetsGet,
        create: mockSpreadsheetsCreate,
        batchUpdate: mockSpreadsheetsBatchUpdate,
        values: {
          get: mockValuesGet,
          update: mockValuesUpdate,
          clear: mockValuesClear,
        },
      },
    }),
  },
}));

describe('Google Sheets foundation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockValuesClear.mockResolvedValue({});
    mockValuesUpdate.mockResolvedValue({});
    mockSpreadsheetsBatchUpdate.mockResolvedValue({});
  });

  describe('initializeSpreadsheet', () => {
    it('creates missing MVP tabs and writes headers only when needed', async () => {
      mockSpreadsheetsGet.mockResolvedValueOnce({
        data: {
          spreadsheetId: 'sheet-123',
          sheets: [{ properties: { title: 'SourceDocuments' } }],
        },
      });
      mockValuesGet.mockResolvedValue({ data: { values: [] } });

      const finalId = await initializeSpreadsheet('sheet-123');

      expect(finalId).toBe('sheet-123');
      expect(mockSpreadsheetsBatchUpdate).toHaveBeenCalledWith({
        spreadsheetId: 'sheet-123',
        requestBody: {
          requests: expect.arrayContaining([
            { addSheet: { properties: { title: 'Transactions' } } },
            { addSheet: { properties: { title: 'Runs' } } },
          ]),
        },
      });
      expect(mockValuesUpdate).toHaveBeenCalledWith(
        expect.objectContaining({
          range: 'SourceDocuments!A1:I1',
          requestBody: { values: [SHEET_SCHEMAS.SourceDocuments] },
        })
      );
    });

    it('reports an actionable error when the configured sheet cannot be opened', async () => {
      mockSpreadsheetsGet.mockRejectedValueOnce(new Error('not found'));

      await expect(initializeSpreadsheet('missing-sheet')).rejects.toThrow(
        'Unable to open GOOGLE_SHEET_ID "missing-sheet". Confirm the ID is correct and share the Sheet with the configured Google service account as Editor.'
      );
      expect(mockSpreadsheetsCreate).not.toHaveBeenCalled();
    });

    it('creates a new spreadsheet only for the local mock placeholder', async () => {
      mockSpreadsheetsCreate.mockResolvedValueOnce({
        data: {
          spreadsheetId: 'new-sheet-456',
          sheets: [],
        },
      });
      mockValuesGet.mockResolvedValue({ data: { values: [] } });

      await expect(initializeSpreadsheet('mock-google-sheet-id-abc')).resolves.toBe('new-sheet-456');
      expect(mockSpreadsheetsCreate).toHaveBeenCalledWith({
        requestBody: {
          properties: { title: 'Agentic Spending Analysis Dashboard' },
        },
      });
    });
  });

  describe('row mapping', () => {
    it('maps sheet rows with numbers, booleans, JSON arrays, and missing cells', () => {
      const correction = mapSheetRow(
        'Corrections',
        ['correction_id', 'target_type', 'target_id', 'field_name', 'old_value', 'new_value', 'apply_future'],
        ['correction-1', 'merchant_rule', 'merchant-1', 'category', 'shopping', 'groceries', 'TRUE']
      );

      expect(correction.apply_future).toBe(true);
      expect(correction.created_at).toBeNull();

      const review = mapSheetRow(
        'ReviewQueue',
        ['review_item_id', 'suggested_options'],
        ['review-1', '["groceries","shopping"]']
      );

      expect(review.suggested_options).toEqual(['groceries', 'shopping']);

      const transaction = mapSheetRow(
        'Transactions',
        ['transaction_id', 'amount', 'category_confidence'],
        ['txn-1', '-42.19', '0.81']
      );

      expect(transaction.amount).toBe(-42.19);
      expect(transaction.category_confidence).toBe(0.81);
    });

    it('serializes rows using stable schema order', () => {
      const row = serializeSheetRow('ReviewQueue', {
        review_item_id: 'review-1',
        target_type: 'transaction',
        target_id: 'txn-1',
        issue_type: 'unclear_category',
        severity: 'medium',
        question: 'Which category fits?',
        suggested_options: ['groceries', 'shopping'],
        status: 'pending',
        user_answer: null,
        created_at: '2026-06-29T10:00:00Z',
        resolved_at: null,
      });

      expect(row).toEqual([
        'review-1',
        'transaction',
        'txn-1',
        'unclear_category',
        'medium',
        'Which category fits?',
        '["groceries","shopping"]',
        'pending',
        '',
        '2026-06-29T10:00:00Z',
        '',
      ]);
    });
  });

  describe('readTabRows', () => {
    it('reads typed tab rows from the sheet range', async () => {
      mockValuesGet.mockResolvedValueOnce({
        data: {
          values: [
            ['source_document_id', 'source_type', 'file_name', 'status'],
            ['file-1', 'drive', 'cc_june.png', 'pending'],
          ],
        },
      });

      const rows = await readTabRows('sheet-123', 'SourceDocuments');

      expect(mockValuesGet).toHaveBeenCalledWith({
        spreadsheetId: 'sheet-123',
        range: 'SourceDocuments!A:I',
      });
      expect(rows[0]).toMatchObject({
        source_document_id: 'file-1',
        source_type: 'drive',
        file_name: 'cc_june.png',
        status: 'pending',
      });
    });
  });


  describe('replaceTabRows', () => {
    it('replaces generated summary rows without collapsing repeated months', async () => {
      await replaceTabRows('sheet-123', 'MonthlySummary', [
        {
          month: '2026-06',
          category: 'groceries',
          total_amount: 100,
          transaction_count: 2,
          reviewed_count: 0,
          unresolved_count: 0,
          month_over_month_delta: null,
          completeness_status: 'unknown',
        },
        {
          month: '2026-06',
          category: 'dining',
          total_amount: 50,
          transaction_count: 1,
          reviewed_count: 0,
          unresolved_count: 0,
          month_over_month_delta: null,
          completeness_status: 'unknown',
        },
      ]);

      expect(mockValuesClear).toHaveBeenCalledWith({
        spreadsheetId: 'sheet-123',
        range: 'MonthlySummary!A2:H10000',
      });
      expect(mockValuesUpdate).toHaveBeenCalledWith({
        spreadsheetId: 'sheet-123',
        range: 'MonthlySummary!A2:H3',
        valueInputOption: 'RAW',
        requestBody: {
          values: [
            ['2026-06', 'groceries', 100, 2, 0, 0, '', 'unknown'],
            ['2026-06', 'dining', 50, 1, 0, 0, '', 'unknown'],
          ],
        },
      });
    });
  });

  describe('upsertTabRows', () => {
    it('updates existing rows and appends new rows without duplicating stable IDs', async () => {
      mockValuesGet.mockResolvedValueOnce({
        data: {
          values: [
            SHEET_SCHEMAS.SourceDocuments,
            ['file-1', 'drive', 'cc_june.png', 'image/png', '', '', '', 'pending', ''],
          ],
        },
      });

      await upsertTabRows('sheet-123', 'SourceDocuments', [
        {
          source_document_id: 'file-1',
          source_type: 'drive',
          file_name: 'cc_june.png',
          status: 'processed',
          processed_at: '2026-06-29T10:00:00Z',
        },
        {
          source_document_id: 'file-2',
          source_type: 'drive',
          file_name: 'bank_july.png',
          mime_type: 'image/png',
          created_time: '2026-06-29T09:00:00Z',
          modified_time: '2026-06-29T09:00:00Z',
          processed_at: null,
          status: 'pending',
          error_summary: null,
        },
      ]);

      expect(mockValuesClear).toHaveBeenCalledWith({
        spreadsheetId: 'sheet-123',
        range: 'SourceDocuments!A2:I10000',
      });
      expect(mockValuesUpdate).toHaveBeenCalledWith({
        spreadsheetId: 'sheet-123',
        range: 'SourceDocuments!A2:I3',
        valueInputOption: 'RAW',
        requestBody: {
          values: [
            ['file-1', 'drive', 'cc_june.png', 'image/png', '', '', '2026-06-29T10:00:00Z', 'processed', ''],
            ['file-2', 'drive', 'bank_july.png', 'image/png', '2026-06-29T09:00:00Z', '2026-06-29T09:00:00Z', '', 'pending', ''],
          ],
        },
      });
    });

    it('rejects rows without the stable key column', async () => {
      mockValuesGet.mockResolvedValueOnce({ data: { values: [SHEET_SCHEMAS.SourceDocuments] } });

      await expect(
        upsertTabRows('sheet-123', 'SourceDocuments', [{ source_type: 'drive' }])
      ).rejects.toThrow('Cannot upsert into SourceDocuments without key column source_document_id');
    });
  });
});

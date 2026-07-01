import { google, type sheets_v4 } from 'googleapis';
import fs from 'fs';
import path from 'path';
import { getGoogleAuthClient } from './auth';
import type {
  Anomaly,
  AssetSnapshot,
  AssetTrend,
  Correction,
  MonthlySummary,
  QuarterlySummary,
  ReviewItem,
  RunState,
  SourceDocument,
  Transaction,
} from '../../types/domain';

export const SHEET_SCHEMAS = {
  SourceDocuments: [
    'source_document_id',
    'source_type',
    'file_name',
    'mime_type',
    'created_time',
    'modified_time',
    'processed_at',
    'status',
    'error_summary',
  ],
  Transactions: [
    'transaction_id',
    'source_document_id',
    'observed_month',
    'transaction_date',
    'merchant_raw',
    'merchant_normalized',
    'amount',
    'transaction_type',
    'account_label',
    'category',
    'category_confidence',
    'extraction_confidence',
    'validation_status',
    'review_status',
    'evidence_text',
    'created_at',
    'updated_at',
  ],
  AssetSnapshots: [
    'asset_snapshot_id',
    'source_document_id',
    'observed_month',
    'observed_date',
    'account_label',
    'balance',
    'balance_type',
    'confidence',
    'evidence_text',
    'created_at',
  ],
  ReviewQueue: [
    'review_item_id',
    'target_type',
    'target_id',
    'issue_type',
    'severity',
    'question',
    'suggested_options',
    'status',
    'user_answer',
    'created_at',
    'resolved_at',
  ],
  Corrections: [
    'correction_id',
    'target_type',
    'target_id',
    'field_name',
    'old_value',
    'new_value',
    'apply_future',
    'created_at',
  ],
  MonthlySummary: [
    'month',
    'category',
    'total_amount',
    'transaction_count',
    'reviewed_count',
    'unresolved_count',
    'month_over_month_delta',
    'completeness_status',
  ],
  QuarterlySummary: [
    'quarter',
    'category',
    'total_amount',
    'transaction_count',
    'quarter_over_quarter_delta',
    'completeness_status',
  ],
  AssetTrends: [
    'month',
    'account_label',
    'ending_balance',
    'prior_month_balance',
    'monthly_change',
    'related_spending_total',
    'maintainability_flag',
  ],
  Anomalies: [
    'anomaly_id',
    'anomaly_type',
    'severity',
    'month',
    'related_record_ids',
    'summary',
    'suggested_action',
    'status',
    'created_at',
  ],
  Runs: [
    'run_id',
    'started_at',
    'finished_at',
    'status',
    'files_seen',
    'files_processed',
    'transactions_created',
    'review_items_created',
    'anomalies_created',
    'error_summary',
  ],
} as const;

export type TabName = keyof typeof SHEET_SCHEMAS;

export interface SheetRowsByTab {
  SourceDocuments: SourceDocument;
  Transactions: Transaction;
  AssetSnapshots: AssetSnapshot;
  ReviewQueue: ReviewItem;
  Corrections: Correction;
  MonthlySummary: MonthlySummary;
  QuarterlySummary: QuarterlySummary;
  AssetTrends: AssetTrend;
  Anomalies: Anomaly;
  Runs: RunState;
}

const DEFAULT_KEY_COLUMNS = {
  SourceDocuments: 'source_document_id',
  Transactions: 'transaction_id',
  AssetSnapshots: 'asset_snapshot_id',
  ReviewQueue: 'review_item_id',
  Corrections: 'correction_id',
  MonthlySummary: 'month',
  QuarterlySummary: 'quarter',
  AssetTrends: 'month',
  Anomalies: 'anomaly_id',
  Runs: 'run_id',
} as const satisfies { [K in TabName]: keyof SheetRowsByTab[K] };

const NUMBER_COLUMNS = new Set([
  'amount',
  'balance',
  'category_confidence',
  'extraction_confidence',
  'confidence',
  'month_over_month_delta',
  'quarter_over_quarter_delta',
  'ending_balance',
  'prior_month_balance',
  'monthly_change',
  'related_spending_total',
  'total_amount',
  'transaction_count',
  'reviewed_count',
  'unresolved_count',
  'files_seen',
  'files_processed',
  'transactions_created',
  'review_items_created',
  'anomalies_created',
]);

const BOOLEAN_COLUMNS = new Set(['apply_future']);
const JSON_ARRAY_COLUMNS = new Set(['suggested_options', 'related_record_ids']);

function updateLocalEnvSheetId(sheetId: string) {
  if (process.env.NODE_ENV === 'test' || process.env.VITEST) {
    process.env.GOOGLE_SHEET_ID = sheetId;
    return;
  }

  const envPath = path.resolve(process.cwd(), '.env');
  if (fs.existsSync(envPath)) {
    let content = fs.readFileSync(envPath, 'utf-8');
    const regex = /^GOOGLE_SHEET_ID=.*$/m;
    if (regex.test(content)) {
      content = content.replace(regex, 'GOOGLE_SHEET_ID=' + sheetId);
    } else {
      content += '\nGOOGLE_SHEET_ID=' + sheetId;
    }
    fs.writeFileSync(envPath, content, 'utf-8');
    process.env.GOOGLE_SHEET_ID = sheetId;
  }
}

function columnLetter(columnCount: number): string {
  let dividend = columnCount;
  let columnName = '';
  while (dividend > 0) {
    const modulo = (dividend - 1) % 26;
    columnName = String.fromCharCode(65 + modulo) + columnName;
    dividend = Math.floor((dividend - modulo) / 26);
  }
  return columnName;
}

function headerRange(tabName: TabName): string {
  return tabName + '!A1:' + columnLetter(SHEET_SCHEMAS[tabName].length) + '1';
}

function tableRange(tabName: TabName): string {
  return tabName + '!A:' + columnLetter(SHEET_SCHEMAS[tabName].length);
}

function dataRange(tabName: TabName, rowCount: number): string {
  return tabName + '!A2:' + columnLetter(SHEET_SCHEMAS[tabName].length) + String(rowCount + 1);
}

function parseCellValue(header: string, value: unknown): unknown {
  if (value === undefined || value === null || value === '') {
    return null;
  }

  if (NUMBER_COLUMNS.has(header)) {
    const numericValue = Number(value);
    return Number.isNaN(numericValue) ? null : numericValue;
  }

  if (BOOLEAN_COLUMNS.has(header)) {
    return value === true || value === 'TRUE' || value === 'true';
  }

  if (JSON_ARRAY_COLUMNS.has(header)) {
    if (Array.isArray(value)) {
      return value;
    }
    try {
      const parsed = JSON.parse(String(value));
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return String(value)
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean);
    }
  }

  return value;
}

function serializeCellValue(value: unknown): string | number {
  if (value === null || value === undefined) {
    return '';
  }
  if (typeof value === 'boolean') {
    return value ? 'TRUE' : 'FALSE';
  }
  if (Array.isArray(value) || typeof value === 'object') {
    return JSON.stringify(value);
  }
  if (typeof value === 'number') {
    return value;
  }
  return String(value);
}

export function mapSheetRow<Tab extends TabName>(tabName: Tab, fileHeaders: string[], row: unknown[]): SheetRowsByTab[Tab] {
  const obj: Record<string, unknown> = {};
  for (const header of SHEET_SCHEMAS[tabName]) {
    const colIndex = fileHeaders.indexOf(header);
    const rawValue = colIndex >= 0 && colIndex < row.length ? row[colIndex] : null;
    obj[header] = parseCellValue(header, rawValue);
  }
  return obj as unknown as SheetRowsByTab[Tab];
}

export function serializeSheetRow<Tab extends TabName>(tabName: Tab, row: Partial<SheetRowsByTab[Tab]>): Array<string | number> {
  return SHEET_SCHEMAS[tabName].map((header) => serializeCellValue(row[header as keyof SheetRowsByTab[Tab]]));
}

export async function initializeSpreadsheet(sheetId: string): Promise<string> {
  const auth = getGoogleAuthClient();
  const sheets = google.sheets({ version: 'v4', auth });

  let targetSheetId = sheetId;
  let spreadsheetMetadata: sheets_v4.Schema$Spreadsheet | null = null;
  let configuredSheetError: Error | null = null;

  if (targetSheetId && targetSheetId !== 'mock-google-sheet-id-abc') {
    try {
      const response = await sheets.spreadsheets.get({ spreadsheetId: targetSheetId });
      spreadsheetMetadata = response.data;
      console.log('[Sheets] Connected to existing spreadsheet: ' + targetSheetId);
    } catch (err) {
      configuredSheetError = err as Error;
      console.warn('[Sheets] Failed to fetch configured spreadsheet: ' + configuredSheetError.message);
    }
  }

  if (targetSheetId && targetSheetId !== 'mock-google-sheet-id-abc' && !spreadsheetMetadata) {
    throw new Error(
      'Unable to open GOOGLE_SHEET_ID "' +
        targetSheetId +
        '". Confirm the ID is correct and share the Sheet with the configured Google service account as Editor. Google reported: ' +
        (configuredSheetError?.message ?? 'unknown access error')
    );
  }

  if (!spreadsheetMetadata) {
    try {
      const createResponse = await sheets.spreadsheets.create({
        requestBody: {
          properties: {
            title: 'Agentic Spending Analysis Dashboard',
          },
        },
      });
      targetSheetId = createResponse.data.spreadsheetId!;
      spreadsheetMetadata = createResponse.data;
      console.log('[Sheets] Created spreadsheet: ' + targetSheetId);
      updateLocalEnvSheetId(targetSheetId);
    } catch (err) {
      throw new Error('Failed to create spreadsheet: ' + (err as Error).message);
    }
  }

  const existingTabs = new Set(
    spreadsheetMetadata.sheets?.map((sheet) => sheet.properties?.title).filter(Boolean) || []
  );

  const addSheetRequests = (Object.keys(SHEET_SCHEMAS) as TabName[])
    .filter((tabName) => !existingTabs.has(tabName))
    .map((tabName) => ({
      addSheet: {
        properties: {
          title: tabName,
        },
      },
    }));

  if (addSheetRequests.length > 0) {
    await sheets.spreadsheets.batchUpdate({
      spreadsheetId: targetSheetId,
      requestBody: { requests: addSheetRequests },
    });
  }

  for (const tabName of Object.keys(SHEET_SCHEMAS) as TabName[]) {
    const headers = [...SHEET_SCHEMAS[tabName]];
    const range = headerRange(tabName);
    let currentHeaderRow: unknown[] = [];

    try {
      const headerCheck = await sheets.spreadsheets.values.get({
        spreadsheetId: targetSheetId,
        range,
      });
      currentHeaderRow = headerCheck.data.values?.[0] || [];
    } catch {
      currentHeaderRow = [];
    }

    const headerMatches =
      currentHeaderRow.length === headers.length &&
      headers.every((header, index) => currentHeaderRow[index] === header);

    if (!headerMatches) {
      await sheets.spreadsheets.values.update({
        spreadsheetId: targetSheetId,
        range,
        valueInputOption: 'RAW',
        requestBody: { values: [headers] },
      });
    }
  }

  return targetSheetId;
}

export async function readTabRows<Tab extends TabName>(sheetId: string, tabName: Tab): Promise<SheetRowsByTab[Tab][]> {
  const auth = getGoogleAuthClient();
  const sheets = google.sheets({ version: 'v4', auth });
  const response = await sheets.spreadsheets.values.get({
    spreadsheetId: sheetId,
    range: tableRange(tabName),
  });

  const rawValues = response.data.values;
  if (!rawValues || rawValues.length <= 1) {
    return [];
  }

  const fileHeaders = rawValues[0].map(String);
  return rawValues.slice(1).map((row) => mapSheetRow(tabName, fileHeaders, row));
}

export async function readRows<T>(sheetId: string, tabName: TabName): Promise<T[]> {
  return readTabRows(sheetId, tabName) as Promise<T[]>;
}

export async function replaceTabRows<Tab extends TabName>(
  sheetId: string,
  tabName: Tab,
  rows: Array<Partial<SheetRowsByTab[Tab]>>
): Promise<void> {
  const auth = getGoogleAuthClient();
  const sheets = google.sheets({ version: 'v4', auth });
  const finalRows2D = rows.map((row) => serializeSheetRow(tabName, row));

  await sheets.spreadsheets.values.clear({
    spreadsheetId: sheetId,
    range: tabName + '!A2:' + columnLetter(SHEET_SCHEMAS[tabName].length) + '10000',
  });

  if (finalRows2D.length === 0) return;

  await sheets.spreadsheets.values.update({
    spreadsheetId: sheetId,
    range: dataRange(tabName, finalRows2D.length),
    valueInputOption: 'RAW',
    requestBody: { values: finalRows2D },
  });
}

export async function replaceRows<T extends object>(
  sheetId: string,
  tabName: TabName,
  rows: T[]
): Promise<void> {
  await replaceTabRows(sheetId, tabName, rows as Array<Partial<SheetRowsByTab[TabName]>>);
}

export async function upsertTabRows<Tab extends TabName>(
  sheetId: string,
  tabName: Tab,
  newOrUpdatedRows: Array<Partial<SheetRowsByTab[Tab]>>,
  keyColumn?: keyof SheetRowsByTab[Tab]
): Promise<void> {
  if (newOrUpdatedRows.length === 0) return;
  const stableKeyColumn = (keyColumn ?? DEFAULT_KEY_COLUMNS[tabName]) as keyof SheetRowsByTab[Tab];

  const auth = getGoogleAuthClient();
  const sheets = google.sheets({ version: 'v4', auth });
  const currentRows = await readTabRows(sheetId, tabName);
  const rowMap = new Map<string, Partial<SheetRowsByTab[Tab]>>();

  for (const row of currentRows) {
    const key = row[stableKeyColumn];
    if (key !== null && key !== undefined && String(key).trim() !== '') {
      rowMap.set(String(key), row);
    }
  }

  for (const row of newOrUpdatedRows) {
    const key = row[stableKeyColumn];
    if (key === null || key === undefined || String(key).trim() === '') {
      throw new Error('Cannot upsert into ' + tabName + ' without key column ' + String(stableKeyColumn));
    }
    rowMap.set(String(key), { ...rowMap.get(String(key)), ...row });
  }

  const finalRows2D = Array.from(rowMap.values()).map((row) => serializeSheetRow(tabName, row));

  await sheets.spreadsheets.values.clear({
    spreadsheetId: sheetId,
    range: tabName + '!A2:' + columnLetter(SHEET_SCHEMAS[tabName].length) + '10000',
  });

  if (finalRows2D.length === 0) return;

  await sheets.spreadsheets.values.update({
    spreadsheetId: sheetId,
    range: dataRange(tabName, finalRows2D.length),
    valueInputOption: 'RAW',
    requestBody: { values: finalRows2D },
  });

  console.log('[Sheets] Upserted ' + newOrUpdatedRows.length + ' rows in ' + tabName + '.');
}

export async function upsertRows<T extends object>(
  sheetId: string,
  tabName: TabName,
  keyColumn: keyof T,
  newOrUpdatedRows: T[]
): Promise<void> {
  await upsertTabRows(
    sheetId,
    tabName,
    newOrUpdatedRows as Array<Partial<SheetRowsByTab[typeof tabName]>>,
    keyColumn as unknown as keyof SheetRowsByTab[TabName]
  );
}

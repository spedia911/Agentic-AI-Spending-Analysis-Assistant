import path from 'path';
import fs from 'fs/promises';
import { getEnv } from '../env';
import { createVisionModelAdapter, extractScreenshot, type ExtractionPromptMode, type VisionModelAdapter } from '../extraction';
import { categorizeTransactionsWithFallback, createCategoryClassifier } from '../categorization';
import { normalizeExtractionCandidates } from '../normalization';
import { validateTransactions } from '../validation';
import { initializeSpreadsheet, readRows, upsertRows } from '../google/sheets';
import type { AssetSnapshot, Correction, ReviewItem, SourceDocument, Transaction } from '../../types/domain';

export interface ProcessPendingOptions {
  forceReprocess?: boolean;
  maxDocuments?: number;
  model?: VisionModelAdapter;
  localCacheDir?: string;
  now?: string;
}

export interface ProcessPendingResult {
  sheetId: string;
  sourcesProcessed: number;
  sourcesErrored: number;
  transactionsWritten: number;
  assetSnapshotsWritten: number;
  reviewItemsWritten: number;
}

function maskSensitiveText(value: string): string {
  return value
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email]')
    .replace(/\b\d{5,}\b/g, '[number]')
    .slice(0, 240);
}

export function sourceDocumentCachePath(source: SourceDocument, localCacheDir = path.join(process.cwd(), 'data', 'private')): string {
  const sanitizedName = source.file_name.replace(/[^a-zA-Z0-9.-]/g, '_');
  return path.join(localCacheDir, source.source_document_id + '-' + sanitizedName);
}

export function inferExtractionMode(source: Pick<SourceDocument, 'file_name'>): ExtractionPromptMode {
  const name = source.file_name.toLowerCase();
  if (/bank|checking|savings|deposit|balance|activity/.test(name)) {
    return 'bank_activity';
  }
  if (/card|visa|mastercard|amex|discover|chase|capital_one|statement/.test(name)) {
    return 'credit_card';
  }
  return 'mixed';
}

function observedMonthHint(source: SourceDocument): string | undefined {
  const value = source.created_time || source.modified_time;
  return /^\d{4}-\d{2}/.test(value) ? value.slice(0, 7) : undefined;
}

function shouldProcess(source: SourceDocument, forceReprocess: boolean): boolean {
  if (source.status === 'pending' || source.status === 'error') return true;
  return forceReprocess && source.status === 'processed';
}

export async function runPendingExtractionProcessing(options: ProcessPendingOptions = {}): Promise<ProcessPendingResult> {
  const env = getEnv();
  const now = options.now ?? new Date().toISOString();
  const activeSheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const sourceDocuments = await readRows<SourceDocument>(activeSheetId, 'SourceDocuments');
  const corrections = await readRows<Correction>(activeSheetId, 'Corrections');
  const candidates = sourceDocuments
    .filter((source) => shouldProcess(source, options.forceReprocess ?? false))
    .slice(0, options.maxDocuments ?? sourceDocuments.length);

  const model = options.model ?? createVisionModelAdapter(env);
  const sourceUpdates: SourceDocument[] = [];
  const transactions: Transaction[] = [];
  const assetSnapshots: AssetSnapshot[] = [];
  const reviewItems: ReviewItem[] = [];

  for (const source of candidates) {
    try {
      const imageBytes = await fs.readFile(sourceDocumentCachePath(source, options.localCacheDir));
      const extraction = await extractScreenshot(
        {
          sourceDocumentId: source.source_document_id,
          fileName: source.file_name,
          mimeType: source.mime_type,
          imageBytes,
        },
        model,
        { mode: inferExtractionMode(source) }
      );

      const normalized = normalizeExtractionCandidates(extraction.transactions, extraction.asset_snapshots, {
        sourceDocumentId: source.source_document_id,
        observedMonthHint: observedMonthHint(source),
        now,
      });

      transactions.push(...normalized.transactions);
      assetSnapshots.push(...normalized.assetSnapshots);
      reviewItems.push(...normalized.reviewItems);
      sourceUpdates.push({
        ...source,
        processed_at: now,
        status: 'processed',
        error_summary: extraction.warnings.length > 0 ? extraction.warnings.map(maskSensitiveText).join('; ') : null,
      });
    } catch (error) {
      sourceUpdates.push({
        ...source,
        processed_at: now,
        status: 'error',
        error_summary: 'Processing failed: ' + maskSensitiveText((error as Error).message),
      });
    }
  }

  const categorization = await categorizeTransactionsWithFallback(transactions, {
    corrections,
    lowConfidenceThreshold: env.LOW_CONFIDENCE_THRESHOLD,
    now,
    classifier: createCategoryClassifier(env),
  });
  reviewItems.push(...categorization.reviewItems);

  const validation = validateTransactions(categorization.transactions, { now });
  reviewItems.push(...validation.reviewItems);

  await upsertRows<SourceDocument>(activeSheetId, 'SourceDocuments', 'source_document_id', sourceUpdates);
  await upsertRows<Transaction>(activeSheetId, 'Transactions', 'transaction_id', validation.transactions);
  await upsertRows<AssetSnapshot>(activeSheetId, 'AssetSnapshots', 'asset_snapshot_id', assetSnapshots);
  await upsertRows<ReviewItem>(activeSheetId, 'ReviewQueue', 'review_item_id', reviewItems);

  return {
    sheetId: activeSheetId,
    sourcesProcessed: sourceUpdates.filter((source) => source.status === 'processed').length,
    sourcesErrored: sourceUpdates.filter((source) => source.status === 'error').length,
    transactionsWritten: validation.transactions.length,
    assetSnapshotsWritten: assetSnapshots.length,
    reviewItemsWritten: reviewItems.length,
  };
}

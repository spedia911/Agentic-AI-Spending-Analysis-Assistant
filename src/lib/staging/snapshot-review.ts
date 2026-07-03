import fs from 'fs/promises';
import path from 'path';
import { getEnv } from '../env';
import { createCategoryClassifier, categorizeTransactionsWithFallback } from '../categorization';
import { createVisionModelAdapter, extractScreenshot } from '../extraction';
import { downloadDriveFile, isSupportedDriveImage, listDriveFolderFiles } from '../google/drive';
import { initializeSpreadsheet, readRows, upsertRows } from '../google/sheets';
import { normalizeExtractionCandidates } from '../normalization';
import { refreshSummaryTabs } from '../orchestrator/summarize';
import { inferExtractionMode } from '../orchestrator/process';
import { validateTransactions } from '../validation';
import type { AssetSnapshot, Correction, ReviewItem, SourceDocument, Transaction } from '../../types/domain';

export interface StagedSnapshot {
  source: SourceDocument;
  transactions: Transaction[];
  assetSnapshots: AssetSnapshot[];
  reviewItems: ReviewItem[];
  selected: boolean;
}

export interface SnapshotReviewStage {
  stageId: string;
  createdAt: string;
  updatedAt: string;
  snapshots: StagedSnapshot[];
}

export interface StageImportOptions {
  forceReimport?: boolean;
  maxFiles?: number;
}

export interface StageUpdateInput {
  stageId: string;
  transactions: Array<Partial<Transaction> & { transaction_id: string }>;
  snapshots?: Array<{ source_document_id: string; selected: boolean }>;
}

const STAGE_FILE = path.join(process.cwd(), 'data', 'private', 'snapshot-review-stage.json');

function stageId(now: string) {
  return 'stage_' + now.replace(/[^0-9]/g, '').slice(0, 14);
}

function observedMonthHint(source: SourceDocument): string | undefined {
  const value = source.created_time || source.modified_time;
  return /^\d{4}-\d{2}/.test(value) ? value.slice(0, 7) : undefined;
}

function toSourceDocument(file: { id: string; name: string; mimeType: string; createdTime: string; modifiedTime: string }): SourceDocument {
  return {
    source_document_id: file.id,
    source_type: 'drive',
    file_name: file.name,
    mime_type: file.mimeType,
    created_time: file.createdTime,
    modified_time: file.modifiedTime,
    processed_at: null,
    status: 'pending',
    error_summary: null,
  };
}

async function writeStage(stage: SnapshotReviewStage) {
  await fs.mkdir(path.dirname(STAGE_FILE), { recursive: true });
  await fs.writeFile(STAGE_FILE, JSON.stringify(stage, null, 2), 'utf-8');
}

export async function readSnapshotReviewStage(): Promise<SnapshotReviewStage | null> {
  try {
    const content = await fs.readFile(STAGE_FILE, 'utf-8');
    return JSON.parse(content) as SnapshotReviewStage;
  } catch {
    return null;
  }
}

export async function importSnapshotsForReview(options: StageImportOptions = {}): Promise<SnapshotReviewStage> {
  const env = getEnv();
  const now = new Date().toISOString();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const knownSources = await readRows<SourceDocument>(sheetId, 'SourceDocuments');
  const knownById = new Map(knownSources.map((source) => [source.source_document_id, source]));
  const corrections = await readRows<Correction>(sheetId, 'Corrections');
  const files = (await listDriveFolderFiles(env.GOOGLE_DRIVE_FOLDER_ID))
    .filter((file) => isSupportedDriveImage(file.mimeType))
    .filter((file) => options.forceReimport || knownById.get(file.id)?.status !== 'processed')
    .slice(0, options.maxFiles ?? 5);

  const model = createVisionModelAdapter(env);
  const snapshots: StagedSnapshot[] = [];

  for (const file of files) {
    const source = toSourceDocument(file);
    const sanitizedName = file.name.replace(/[^a-zA-Z0-9.-]/g, '_');
    const localPath = path.join(process.cwd(), 'data', 'private', file.id + '-' + sanitizedName);
    await downloadDriveFile(file.id, localPath);
    const imageBytes = await fs.readFile(localPath);
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
    const categorization = await categorizeTransactionsWithFallback(normalized.transactions, {
      corrections,
      classifier: createCategoryClassifier(env),
      lowConfidenceThreshold: env.LOW_CONFIDENCE_THRESHOLD,
      now,
    });
    const validation = validateTransactions(categorization.transactions, { now });

    snapshots.push({
      source: {
        ...source,
        error_summary: extraction.warnings.length > 0 ? extraction.warnings.join('; ').slice(0, 240) : null,
      },
      transactions: validation.transactions,
      assetSnapshots: normalized.assetSnapshots,
      reviewItems: [...normalized.reviewItems, ...categorization.reviewItems, ...validation.reviewItems],
      selected: true,
    });
  }

  const stage: SnapshotReviewStage = {
    stageId: stageId(now),
    createdAt: now,
    updatedAt: now,
    snapshots,
  };
  await writeStage(stage);
  return stage;
}

export async function updateSnapshotReviewStage(input: StageUpdateInput): Promise<SnapshotReviewStage> {
  const stage = await readSnapshotReviewStage();
  if (!stage || stage.stageId !== input.stageId) {
    throw new Error('Snapshot review stage not found. Import snapshots again.');
  }

  const updates = new Map(input.transactions.map((transaction) => [transaction.transaction_id, transaction]));
  const snapshotSelectionUpdates = new Map(input.snapshots?.map((snapshot) => [snapshot.source_document_id, snapshot.selected]) ?? []);
  const snapshots = stage.snapshots.map((snapshot) => ({
    ...snapshot,
    selected: snapshotSelectionUpdates.get(snapshot.source.source_document_id) ?? snapshot.selected,
    transactions: snapshot.transactions.map((transaction) => {
      const update = updates.get(transaction.transaction_id);
      if (!update) return transaction;
      return {
        ...transaction,
        ...update,
        updated_at: new Date().toISOString(),
      };
    }),
  }));
  const updated = { ...stage, snapshots, updatedAt: new Date().toISOString() };
  await writeStage(updated);
  return updated;
}

export async function commitSnapshotReviewStage(stageIdToCommit: string): Promise<{ sheetId: string; transactionsWritten: number; assetSnapshotsWritten: number; reviewItemsWritten: number }> {
  const env = getEnv();
  const stage = await readSnapshotReviewStage();
  if (!stage || stage.stageId !== stageIdToCommit) {
    throw new Error('Snapshot review stage not found. Import snapshots again.');
  }

  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const now = new Date().toISOString();
  const selectedSnapshots = stage.snapshots.filter((snapshot) => snapshot.selected !== false);
  const sources = selectedSnapshots.map((snapshot) => ({
    ...snapshot.source,
    status: 'processed' as const,
    processed_at: now,
  }));
  const transactions = selectedSnapshots.flatMap((snapshot) => snapshot.transactions);
  const assetSnapshots = selectedSnapshots.flatMap((snapshot) => snapshot.assetSnapshots);
  const reviewItems = selectedSnapshots.flatMap((snapshot) => snapshot.reviewItems);

  await upsertRows<SourceDocument>(sheetId, 'SourceDocuments', 'source_document_id', sources);
  await upsertRows<Transaction>(sheetId, 'Transactions', 'transaction_id', transactions);
  await upsertRows<AssetSnapshot>(sheetId, 'AssetSnapshots', 'asset_snapshot_id', assetSnapshots);
  await upsertRows<ReviewItem>(sheetId, 'ReviewQueue', 'review_item_id', reviewItems);
  await refreshSummaryTabs();
  await fs.rm(STAGE_FILE, { force: true });

  return {
    sheetId,
    transactionsWritten: transactions.length,
    assetSnapshotsWritten: assetSnapshots.length,
    reviewItemsWritten: reviewItems.length,
  };
}

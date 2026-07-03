import path from 'path';
import fs from 'fs/promises';
import { getEnv } from '../env';
import { downloadDriveFile, isSupportedDriveImage, listDriveFolderFiles } from '../google/drive';
import { initializeSpreadsheet, readRows, upsertRows } from '../google/sheets';
import { maskSensitiveText } from '../privacy/redact';
import { SourceDocument } from '../../types/domain';

export interface IngestOptions {
  forceReprocess?: boolean;
}

export interface IngestResult {
  sheetId: string;
  filesSeen: number;
  cacheFilesRemoved: number;
  newDocuments: SourceDocument[];
  skippedDocuments: SourceDocument[];
  errorDocuments: SourceDocument[];
}

async function cleanupPrivateCache(localCacheDir: string, retentionDays: number, now: Date): Promise<number> {
  const resolvedCacheDir = path.resolve(localCacheDir);
  const expectedCacheDir = path.resolve(process.cwd(), 'data', 'private');
  if (resolvedCacheDir !== expectedCacheDir) {
    throw new Error('Refusing to clean unexpected cache directory: ' + resolvedCacheDir);
  }

  await fs.mkdir(resolvedCacheDir, { recursive: true });
  const cutoffMs = now.getTime() - retentionDays * 24 * 60 * 60 * 1000;
  const entries = await fs.readdir(resolvedCacheDir, { withFileTypes: true });
  let removed = 0;

  for (const entry of entries) {
    if (!entry.isFile()) continue;
    const filePath = path.join(resolvedCacheDir, entry.name);
    const stat = await fs.stat(filePath);
    if (stat.mtime.getTime() < cutoffMs) {
      await fs.unlink(filePath);
      removed += 1;
    }
  }

  return removed;
}

function toSourceDocument(
  file: { id: string; name: string; mimeType: string; createdTime: string; modifiedTime: string },
  status: SourceDocument['status'],
  processedAt: string | null,
  errorSummary: string | null
): SourceDocument {
  return {
    source_document_id: file.id,
    source_type: 'drive',
    file_name: file.name,
    mime_type: file.mimeType,
    created_time: file.createdTime,
    modified_time: file.modifiedTime,
    processed_at: processedAt,
    status,
    error_summary: errorSummary,
  };
}

/**
 * Orchestrates the screenshot ingestion phase.
 * 1. Initializes the spreadsheet tabs and headers.
 * 2. Fetches previously processed files from the SourceDocuments sheet.
 * 3. Scans the Drive folder and marks unsupported files as skipped.
 * 4. Downloads new supported screenshots to the local private cache folder.
 * 5. Writes SourceDocuments rows with stable, rerunnable IDs.
 */
export async function runIngestion(options: IngestOptions = {}): Promise<IngestResult> {
  const env = getEnv();
  const forceReprocess = options.forceReprocess ?? false;

  console.log('[Orchestrator] Starting ingestion orchestration...');
  const activeSheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);

  console.log('[Orchestrator] Loading known source documents...');
  const knownDocs = await readRows<SourceDocument>(activeSheetId, 'SourceDocuments');
  const knownDocsById = new Map(knownDocs.map((doc) => [doc.source_document_id, doc]));

  const driveFiles = await listDriveFolderFiles(env.GOOGLE_DRIVE_FOLDER_ID);
  console.log('[Orchestrator] Found ' + driveFiles.length + ' files in the configured Drive folder.');

  const newDocsToIngest: SourceDocument[] = [];
  const skippedDocs: SourceDocument[] = [];
  const errorDocs: SourceDocument[] = [];
  const localCacheDir = path.join(process.cwd(), 'data', 'private');
  const nowDate = new Date();
  const now = nowDate.toISOString();
  const cacheFilesRemoved = await cleanupPrivateCache(localCacheDir, env.SOURCE_IMAGE_RETENTION_DAYS, nowDate);

  for (const file of driveFiles) {
    const knownDoc = knownDocsById.get(file.id);

    if (!isSupportedDriveImage(file.mimeType)) {
      if (!knownDoc || forceReprocess) {
        skippedDocs.push(
          toSourceDocument(
            file,
            'skipped',
            now,
            'Unsupported file type: ' + maskSensitiveText(file.mimeType || 'unknown')
          )
        );
      }
      continue;
    }

    if (!forceReprocess && (knownDoc?.status === 'processed' || knownDoc?.status === 'pending')) {
      console.log('[Orchestrator] Skipping known screenshot: ' + maskSensitiveText(file.name));
      continue;
    }

    const sanitizedName = file.name.replace(/[^a-zA-Z0-9.-]/g, '_');
    const localPath = path.join(localCacheDir, file.id + '-' + sanitizedName);

    try {
      await downloadDriveFile(file.id, localPath);
      newDocsToIngest.push(toSourceDocument(file, 'pending', null, null));
    } catch (err) {
      const errorSummary = 'Ingestion failed: ' + maskSensitiveText((err as Error).message);
      console.error('[Orchestrator] ' + errorSummary);
      errorDocs.push(toSourceDocument(file, 'error', now, errorSummary));
    }
  }

  const sourceDocumentUpdates = [...newDocsToIngest, ...skippedDocs, ...errorDocs];
  if (sourceDocumentUpdates.length > 0) {
    console.log('[Orchestrator] Writing ' + sourceDocumentUpdates.length + ' SourceDocuments updates.');
    await upsertRows<SourceDocument>(
      activeSheetId,
      'SourceDocuments',
      'source_document_id',
      sourceDocumentUpdates
    );
  } else {
    console.log('[Orchestrator] No SourceDocuments updates needed.');
  }

  return {
    sheetId: activeSheetId,
    filesSeen: driveFiles.length,
    cacheFilesRemoved,
    newDocuments: newDocsToIngest,
    skippedDocuments: skippedDocs,
    errorDocuments: errorDocs,
  };
}

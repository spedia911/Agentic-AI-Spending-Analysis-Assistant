import fs from 'fs/promises';
import path from 'path';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { runIngestion } from './ingest';

const mocks = vi.hoisted(() => ({
  downloadDriveFile: vi.fn(),
  initializeSpreadsheet: vi.fn(),
  listDriveFolderFiles: vi.fn(),
  readRows: vi.fn(),
  upsertRows: vi.fn(),
}));

vi.mock('../env', () => ({
  getEnv: vi.fn(() => ({
    GOOGLE_DRIVE_FOLDER_ID: 'folder-123',
    GOOGLE_SHEET_ID: 'sheet-123',
    AI_API_KEY: 'key-xyz',
    SINGLE_USER_EMAIL: 'user@example.com',
    SOURCE_IMAGE_RETENTION_DAYS: 30,
  })),
}));

vi.mock('../google/drive', () => ({
  downloadDriveFile: mocks.downloadDriveFile,
  isSupportedDriveImage: (mimeType: string) => ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'].includes(mimeType),
  listDriveFolderFiles: mocks.listDriveFolderFiles,
}));

vi.mock('../google/sheets', () => ({
  initializeSpreadsheet: mocks.initializeSpreadsheet,
  readRows: mocks.readRows,
  upsertRows: mocks.upsertRows,
}));

const imageFile = {
  id: 'file-image-1',
  name: 'June Card.png',
  mimeType: 'image/png',
  createdTime: '2026-06-01T10:00:00Z',
  modifiedTime: '2026-06-01T10:00:00Z',
};

const unsupportedFile = {
  id: 'file-pdf-1',
  name: 'statement.pdf',
  mimeType: 'application/pdf',
  createdTime: '2026-06-01T10:00:00Z',
  modifiedTime: '2026-06-01T10:00:00Z',
};

describe('runIngestion', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readRows.mockResolvedValue([]);
    mocks.downloadDriveFile.mockResolvedValue(undefined);
    mocks.upsertRows.mockResolvedValue(undefined);
  });

  it('downloads supported new screenshots and records unsupported files as skipped', async () => {
    mocks.listDriveFolderFiles.mockResolvedValue([imageFile, unsupportedFile]);

    const result = await runIngestion();

    expect(result.filesSeen).toBe(2);
    expect(result.cacheFilesRemoved).toBe(0);
    expect(result.newDocuments).toHaveLength(1);
    expect(result.skippedDocuments).toHaveLength(1);
    expect(mocks.downloadDriveFile).toHaveBeenCalledWith(
      'file-image-1',
      expect.stringContaining('file-image-1-June_Card.png')
    );
    expect(mocks.upsertRows).toHaveBeenCalledWith(
      'sheet-123',
      'SourceDocuments',
      'source_document_id',
      expect.arrayContaining([
        expect.objectContaining({ source_document_id: 'file-image-1', status: 'pending' }),
        expect.objectContaining({ source_document_id: 'file-pdf-1', status: 'skipped' }),
      ])
    );
  });

  it('does not download screenshots already pending or processed', async () => {
    mocks.listDriveFolderFiles.mockResolvedValue([imageFile]);
    mocks.readRows.mockResolvedValue([
      {
        source_document_id: 'file-image-1',
        source_type: 'drive',
        file_name: 'June Card.png',
        mime_type: 'image/png',
        created_time: imageFile.createdTime,
        modified_time: imageFile.modifiedTime,
        processed_at: null,
        status: 'pending',
        error_summary: null,
      },
    ]);

    const result = await runIngestion();

    expect(result.filesSeen).toBe(1);
    expect(result.newDocuments).toHaveLength(0);
    expect(mocks.downloadDriveFile).not.toHaveBeenCalled();
    expect(mocks.upsertRows).not.toHaveBeenCalled();
  });

  it('force reprocess downloads a known screenshot again', async () => {
    mocks.listDriveFolderFiles.mockResolvedValue([imageFile]);
    mocks.readRows.mockResolvedValue([
      {
        source_document_id: 'file-image-1',
        source_type: 'drive',
        file_name: 'June Card.png',
        mime_type: 'image/png',
        created_time: imageFile.createdTime,
        modified_time: imageFile.modifiedTime,
        processed_at: '2026-06-02T10:00:00Z',
        status: 'processed',
        error_summary: null,
      },
    ]);

    const result = await runIngestion({ forceReprocess: true });

    expect(result.filesSeen).toBe(1);
    expect(result.newDocuments).toHaveLength(1);
    expect(mocks.downloadDriveFile).toHaveBeenCalledOnce();
    expect(mocks.upsertRows).toHaveBeenCalledOnce();
  });
  it('removes expired private cache files according to retention settings', async () => {
    mocks.listDriveFolderFiles.mockResolvedValue([]);
    const cacheDir = path.join(process.cwd(), 'data', 'private');
    await fs.mkdir(cacheDir, { recursive: true });
    const expiredPath = path.join(cacheDir, 'expired-demo.png');
    const freshPath = path.join(cacheDir, 'fresh-demo.png');
    await fs.writeFile(expiredPath, 'expired');
    await fs.writeFile(freshPath, 'fresh');
    const expiredDate = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000);
    await fs.utimes(expiredPath, expiredDate, expiredDate);

    const result = await runIngestion();

    expect(result.cacheFilesRemoved).toBeGreaterThanOrEqual(1);
    await expect(fs.stat(expiredPath)).rejects.toThrow();
    await expect(fs.stat(freshPath)).resolves.toBeTruthy();
    await fs.rm(freshPath, { force: true });
  });
});

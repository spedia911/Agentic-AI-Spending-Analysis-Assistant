import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { getCachedSourceImage, sourceDocumentCachePath, sourceDocumentDriveUrl } from './cache';
import type { SourceDocument } from '../../types/domain';

const source: SourceDocument = {
  source_document_id: 'drive/file:1',
  source_type: 'drive',
  file_name: 'June Card #1.png',
  mime_type: 'image/png',
  created_time: '2026-06-01T10:00:00Z',
  modified_time: '2026-06-01T10:00:00Z',
  processed_at: null,
  status: 'pending',
  error_summary: null,
};

describe('source evidence cache helpers', () => {
  it('builds a cache path without unsafe path segments', () => {
    expect(sourceDocumentCachePath(source, 'cache')).toBe(path.join('cache', 'drive_file_1-June_Card__1.png'));
  });

  it('builds a Google Drive handoff URL from the source id', () => {
    expect(sourceDocumentDriveUrl('drive-file-1')).toBe('https://drive.google.com/file/d/drive-file-1/view');
  });

  it('reports cached image availability without treating missing files as errors', async () => {
    const cacheDir = await fs.mkdtemp(path.join(os.tmpdir(), 'source-cache-'));
    const imagePath = sourceDocumentCachePath(source, cacheDir);

    await expect(getCachedSourceImage(source, cacheDir)).resolves.toMatchObject({ exists: false, path: imagePath });

    await fs.writeFile(imagePath, Buffer.from('image-bytes'));
    await expect(getCachedSourceImage(source, cacheDir)).resolves.toMatchObject({ exists: true, mimeType: 'image/png' });

    await fs.rm(cacheDir, { recursive: true, force: true });
  });
});

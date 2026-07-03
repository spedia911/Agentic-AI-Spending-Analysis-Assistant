import fs from 'fs/promises';
import path from 'path';
import type { SourceDocument } from '../../types/domain';

export const DEFAULT_SOURCE_CACHE_DIR = path.join(process.cwd(), 'data', 'private');

function sanitizeCacheSegment(value: string, fallback: string) {
  const sanitized = value.replace(/[^a-zA-Z0-9._-]/g, '_');
  return sanitized || fallback;
}

export function sourceDocumentCachePath(source: Pick<SourceDocument, 'source_document_id' | 'file_name'>, localCacheDir = DEFAULT_SOURCE_CACHE_DIR): string {
  const sourceId = sanitizeCacheSegment(source.source_document_id, 'source');
  const fileName = sanitizeCacheSegment(source.file_name, 'screenshot');
  return path.join(localCacheDir, sourceId + '-' + fileName);
}

export function sourceDocumentDriveUrl(sourceDocumentId: string): string {
  return 'https://drive.google.com/file/d/' + encodeURIComponent(sourceDocumentId) + '/view';
}

export async function getCachedSourceImage(
  source: Pick<SourceDocument, 'source_document_id' | 'file_name' | 'mime_type'>,
  localCacheDir = DEFAULT_SOURCE_CACHE_DIR
): Promise<{ exists: boolean; path: string; mimeType: string }> {
  const imagePath = sourceDocumentCachePath(source, localCacheDir);
  if (!source.mime_type.startsWith('image/')) {
    return { exists: false, path: imagePath, mimeType: source.mime_type };
  }

  try {
    const stats = await fs.stat(imagePath);
    return { exists: stats.isFile(), path: imagePath, mimeType: source.mime_type };
  } catch {
    return { exists: false, path: imagePath, mimeType: source.mime_type };
  }
}

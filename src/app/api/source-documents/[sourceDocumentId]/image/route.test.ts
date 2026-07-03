import { NextRequest } from 'next/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  getEnv: vi.fn(),
  initializeSpreadsheet: vi.fn(),
  readRows: vi.fn(),
  getCachedSourceImage: vi.fn(),
  readFile: vi.fn(),
}));

vi.mock('../../../../../lib/env', () => ({
  getEnv: mocks.getEnv,
}));

vi.mock('../../../../../lib/google/sheets', () => ({
  initializeSpreadsheet: mocks.initializeSpreadsheet,
  readRows: mocks.readRows,
}));

vi.mock('../../../../../lib/source-evidence/cache', () => ({
  getCachedSourceImage: mocks.getCachedSourceImage,
}));

vi.mock('fs/promises', () => ({
  default: {
    readFile: mocks.readFile,
  },
}));

import { GET } from './route';
import type { SourceDocument } from '../../../../../types/domain';

const source: SourceDocument = {
  source_document_id: 'source-1',
  source_type: 'drive',
  file_name: 'card.png',
  mime_type: 'image/png',
  created_time: '2026-06-01T00:00:00Z',
  modified_time: '2026-06-01T00:00:00Z',
  processed_at: '2026-06-01T00:01:00Z',
  status: 'processed',
  error_summary: null,
};

function request(email?: string) {
  const url = email
    ? 'http://localhost/api/source-documents/source-1/image?email=' + encodeURIComponent(email)
    : 'http://localhost/api/source-documents/source-1/image';
  return new NextRequest(url);
}

function params(sourceDocumentId = 'source-1') {
  return { params: Promise.resolve({ sourceDocumentId }) };
}

describe('source document cached image route', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getEnv.mockReturnValue({ GOOGLE_SHEET_ID: 'sheet-config', SINGLE_USER_EMAIL: 'user@example.com' });
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readRows.mockResolvedValue([source]);
    mocks.getCachedSourceImage.mockResolvedValue({ exists: true, path: '/private/cache/card.png', mimeType: 'image/png' });
    mocks.readFile.mockResolvedValue(Buffer.from('image-bytes'));
  });

  it('rejects requests without the configured user email before reading Sheets', async () => {
    const response = await GET(request('other@example.com'), params());

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({ error: 'Unauthorized' });
    expect(mocks.initializeSpreadsheet).not.toHaveBeenCalled();
    expect(mocks.readRows).not.toHaveBeenCalled();
  });

  it('returns not found when the source document is not in Sheets', async () => {
    mocks.readRows.mockResolvedValue([]);

    const response = await GET(request('USER@example.com'), params('missing-source'));

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({ error: 'Source document not found' });
  });

  it('returns not found when the private cached preview is unavailable', async () => {
    mocks.getCachedSourceImage.mockResolvedValue({ exists: false, path: '/private/cache/card.png', mimeType: 'image/png' });

    const response = await GET(request('user@example.com'), params());

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({ error: 'Cached source image not available' });
    expect(mocks.readFile).not.toHaveBeenCalled();
  });

  it('serves cached image bytes with private no-store headers', async () => {
    const response = await GET(request('user@example.com'), params());

    expect(response.status).toBe(200);
    expect(response.headers.get('Cache-Control')).toBe('private, no-store');
    expect(response.headers.get('Content-Type')).toBe('image/png');
    expect(Buffer.from(await response.arrayBuffer()).toString('utf8')).toBe('image-bytes');
    expect(mocks.readFile).toHaveBeenCalledWith('/private/cache/card.png');
  });

  it('returns a sanitized error when the Sheet read fails', async () => {
    mocks.readRows.mockRejectedValue(new Error('403 folder not shared with person@example.com and api_key=AIzaSyExampleSecretValue1234567890'));

    const response = await GET(request('user@example.com'), params());

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: 'Source image failed',
      detail: '403 folder not shared with [email] and api_key=[secret]',
    });
  });

  it('returns a sanitized error when cached file reading fails', async () => {
    mocks.readFile.mockRejectedValue(new Error('ENOENT for account 1234567890'));

    const response = await GET(request('user@example.com'), params());

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: 'Source image failed',
      detail: 'ENOENT for account [number]',
    });
  });
});

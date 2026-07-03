import { describe, expect, it, vi } from 'vitest';
import { runSetupHealthCheck } from './health';
import type { Env } from '../env';

const env: Env = {
  GOOGLE_DRIVE_FOLDER_ID: 'folder-123',
  GOOGLE_SHEET_ID: 'sheet-123',
  GOOGLE_SERVICE_ACCOUNT_KEY: '{"client_email":"sa@example.com","private_key":"key"}',
  GOOGLE_OAUTH_CLIENT_ID: undefined,
  GOOGLE_OAUTH_CLIENT_SECRET: undefined,
  GOOGLE_REDIRECT_URI: 'http://localhost:3000/api/auth/google/callback',
  AI_PROVIDER: 'gemini',
  AI_MODEL: 'gemini-2.5-flash',
  AI_API_KEY: 'ai-key',
  SINGLE_USER_EMAIL: 'user@example.com',
  LOW_CONFIDENCE_THRESHOLD: 0.75,
  TIMEZONE: 'America/Los_Angeles',
  SOURCE_IMAGE_RETENTION_DAYS: 30,
  NODE_ENV: 'test',
};

describe('runSetupHealthCheck', () => {
  it('reports ok when env, Drive, Sheets, and AI config are ready', async () => {
    const report = await runSetupHealthCheck({
      env,
      now: '2026-06-29T10:00:00Z',
      listDriveFolderFiles: vi.fn(async () => [
        { id: 'file-1', name: 'card.png', mimeType: 'image/png', createdTime: '2026-06-01T00:00:00Z', modifiedTime: '2026-06-01T00:00:00Z' },
        { id: 'file-2', name: 'notes.txt', mimeType: 'text/plain', createdTime: '2026-06-01T00:00:00Z', modifiedTime: '2026-06-01T00:00:00Z' },
      ]),
      initializeSpreadsheet: vi.fn(async () => 'sheet-123'),
    });

    expect(report.status).toBe('ok');
    expect(report.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'drive', status: 'ok', detail: '1 unsupported file(s) will be skipped.' }),
        expect.objectContaining({ id: 'sheets', status: 'ok' }),
        expect.objectContaining({ id: 'ai', status: 'ok' }),
      ])
    );
  });

  it('returns an environment error without calling external checks when env parsing fails', async () => {
    const listDriveFolderFiles = vi.fn();
    const initializeSpreadsheet = vi.fn();

    const report = await runSetupHealthCheck({
      rawEnv: {
        GOOGLE_SHEET_ID: 'sheet-123',
        AI_API_KEY: 'ai-key',
        SINGLE_USER_EMAIL: 'user@example.com',
      },
      listDriveFolderFiles,
      initializeSpreadsheet,
    });

    expect(report.status).toBe('error');
    expect(report.items).toEqual([
      expect.objectContaining({ id: 'env', status: 'error' }),
    ]);
    expect(listDriveFolderFiles).not.toHaveBeenCalled();
    expect(initializeSpreadsheet).not.toHaveBeenCalled();
  });

  it('surfaces Drive failures and unsupported AI provider readiness', async () => {
    const report = await runSetupHealthCheck({
      env: {
        ...env,
        AI_PROVIDER: 'anthropic',
        AI_MODEL: 'claude-sonnet-4-5',
      },
      listDriveFolderFiles: vi.fn(async () => {
        throw new Error('403 folder not shared with user@example.com');
      }),
      initializeSpreadsheet: vi.fn(async () => 'sheet-123'),
    });

    expect(report.status).toBe('error');
    expect(report.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'drive', status: 'error', detail: '403 folder not shared with [email]' }),
        expect.objectContaining({ id: 'ai', status: 'error' }),
      ])
    );
  });
});

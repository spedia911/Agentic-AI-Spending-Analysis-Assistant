import { describe, it, expect } from 'vitest';
import { parseEnv } from './env';

describe('parseEnv', () => {
  const baseValidEnv = {
    GOOGLE_DRIVE_FOLDER_ID: 'folder-123',
    GOOGLE_SHEET_ID: 'sheet-123',
    AI_API_KEY: 'api-key-xyz',
    SINGLE_USER_EMAIL: 'user@example.com',
  };

  it('successfully parses with service account config', () => {
    const env = {
      ...baseValidEnv,
      GOOGLE_SERVICE_ACCOUNT_KEY: '{"type": "service_account"}',
    };
    const parsed = parseEnv(env);
    expect(parsed.GOOGLE_DRIVE_FOLDER_ID).toBe('folder-123');
    expect(parsed.GOOGLE_SERVICE_ACCOUNT_KEY).toBe('{"type": "service_account"}');
    expect(parsed.LOW_CONFIDENCE_THRESHOLD).toBe(0.75); // Default value
  });

  it('successfully parses with OAuth config', () => {
    const env = {
      ...baseValidEnv,
      GOOGLE_OAUTH_CLIENT_ID: 'client-id',
      GOOGLE_OAUTH_CLIENT_SECRET: 'client-secret',
    };
    const parsed = parseEnv(env);
    expect(parsed.GOOGLE_OAUTH_CLIENT_ID).toBe('client-id');
    expect(parsed.GOOGLE_OAUTH_CLIENT_SECRET).toBe('client-secret');
  });

  it('fails validation when drive folder ID is missing', () => {
    const env = {
      GOOGLE_SHEET_ID: 'sheet-123',
      GOOGLE_SERVICE_ACCOUNT_KEY: 'key',
      AI_API_KEY: 'api-key',
      SINGLE_USER_EMAIL: 'user@example.com',
    };
    expect(() => parseEnv(env)).toThrow('Invalid environment variables');
  });

  it('fails validation when email is invalid', () => {
    const env = {
      ...baseValidEnv,
      GOOGLE_SERVICE_ACCOUNT_KEY: 'key',
      SINGLE_USER_EMAIL: 'not-an-email',
    };
    expect(() => parseEnv(env)).toThrow('Invalid environment variables');
  });

  it('fails validation when both service account and OAuth are missing', () => {
    const env = {
      ...baseValidEnv,
    };
    expect(() => parseEnv(env)).toThrow('Invalid credentials configuration');
  });
});

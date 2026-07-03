import { describe, expect, it, vi } from 'vitest';
import { createVisionModelAdapter, GeminiVisionAdapter, OpenAIVisionAdapter } from './adapters';

const input = {
  prompt: 'extract json',
  image: {
    mimeType: 'image/png',
    bytesBase64: 'abc123',
  },
};

function okResponse(body: unknown) {
  return {
    ok: true,
    status: 200,
    text: vi.fn().mockResolvedValue(JSON.stringify(body)),
    json: vi.fn().mockResolvedValue(body),
  };
}

describe('OpenAIVisionAdapter', () => {
  it('posts an image and returns output text', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(okResponse({ output_text: '{"ok":true}' }));
    const adapter = new OpenAIVisionAdapter('key-123', 'gpt-test', fetchImpl);

    await expect(adapter.extractJson(input)).resolves.toBe('{"ok":true}');

    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.openai.com/v1/responses',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({ Authorization: 'Bearer key-123' }),
      })
    );
    const requestBody = JSON.parse(fetchImpl.mock.calls[0][1].body as string);
    expect(requestBody.model).toBe('gpt-test');
    expect(requestBody.input[0].content[1].image_url).toBe('data:image/png;base64,abc123');
  });
});

describe('GeminiVisionAdapter', () => {
  it('posts inline image data and returns candidate text', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(
      okResponse({ candidates: [{ content: { parts: [{ text: '{"ok":true}' }] } }] })
    );
    const adapter = new GeminiVisionAdapter('key-123', 'gemini-test', fetchImpl);

    await expect(adapter.extractJson(input)).resolves.toBe('{"ok":true}');

    expect(fetchImpl.mock.calls[0][0]).toContain('models/gemini-test:generateContent');
    const requestBody = JSON.parse(fetchImpl.mock.calls[0][1].body as string);
    expect(requestBody.contents[0].parts[1].inlineData).toEqual({
      mimeType: 'image/png',
      data: 'abc123',
    });
  });
});

describe('createVisionModelAdapter', () => {
  it('selects the configured provider', () => {
    const openai = createVisionModelAdapter({
      AI_PROVIDER: 'openai',
      AI_API_KEY: 'key',
      AI_MODEL: 'gpt-test',
      GOOGLE_DRIVE_FOLDER_ID: 'folder',
      GOOGLE_SHEET_ID: 'sheet',
      SINGLE_USER_EMAIL: 'user@example.com',
      LOW_CONFIDENCE_THRESHOLD: 0.75,
      TIMEZONE: 'America/Los_Angeles',
      SOURCE_IMAGE_RETENTION_DAYS: 30,
      NODE_ENV: 'test',
      GOOGLE_REDIRECT_URI: 'http://localhost:3000/api/auth/google/callback',
    });

    expect(openai).toBeInstanceOf(OpenAIVisionAdapter);
  });

  it('uses the shared Gemini default model when AI_MODEL is blank', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(
      okResponse({ candidates: [{ content: { parts: [{ text: '{"ok":true}' }] } }] })
    );
    const adapter = createVisionModelAdapter({
      AI_PROVIDER: 'gemini',
      AI_API_KEY: 'key',
      AI_MODEL: undefined,
      GOOGLE_DRIVE_FOLDER_ID: 'folder',
      GOOGLE_SHEET_ID: 'sheet',
      SINGLE_USER_EMAIL: 'user@example.com',
      LOW_CONFIDENCE_THRESHOLD: 0.75,
      TIMEZONE: 'America/Los_Angeles',
      SOURCE_IMAGE_RETENTION_DAYS: 30,
      NODE_ENV: 'test',
      GOOGLE_REDIRECT_URI: 'http://localhost:3000/api/auth/google/callback',
    }, fetchImpl);

    await adapter.extractJson(input);

    expect(fetchImpl.mock.calls[0][0]).toContain('models/gemini-2.5-flash:generateContent');
  });
});

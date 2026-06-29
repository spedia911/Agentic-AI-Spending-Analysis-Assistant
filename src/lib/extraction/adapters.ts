import { getEnv, type Env } from '../env';
import type { VisionModelAdapter } from './schema';

interface FetchLikeResponse {
  ok: boolean;
  status: number;
  text(): Promise<string>;
  json(): Promise<unknown>;
}

type FetchLike = (url: string, init: RequestInit) => Promise<FetchLikeResponse>;

function getFetch(fetchImpl?: FetchLike): FetchLike {
  return fetchImpl ?? (fetch as unknown as FetchLike);
}

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
}

function extractOpenAIText(response: unknown): string {
  const root = asObject(response);
  if (typeof root.output_text === 'string') {
    return root.output_text;
  }

  const output = Array.isArray(root.output) ? root.output : [];
  const textParts: string[] = [];
  for (const item of output) {
    const itemObj = asObject(item);
    const content = Array.isArray(itemObj.content) ? itemObj.content : [];
    for (const contentItem of content) {
      const contentObj = asObject(contentItem);
      if (typeof contentObj.text === 'string') {
        textParts.push(contentObj.text);
      }
    }
  }

  if (textParts.length > 0) {
    return textParts.join('\n');
  }

  throw new Error('OpenAI response did not include text output.');
}

function extractGeminiText(response: unknown): string {
  const root = asObject(response);
  const candidates = Array.isArray(root.candidates) ? root.candidates : [];
  const parts: string[] = [];

  for (const candidate of candidates) {
    const content = asObject(asObject(candidate).content);
    const candidateParts = Array.isArray(content.parts) ? content.parts : [];
    for (const part of candidateParts) {
      const partObj = asObject(part);
      if (typeof partObj.text === 'string') {
        parts.push(partObj.text);
      }
    }
  }

  if (parts.length > 0) {
    return parts.join('\n');
  }

  throw new Error('Gemini response did not include text output.');
}

export class OpenAIVisionAdapter implements VisionModelAdapter {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
    private readonly fetchImpl?: FetchLike
  ) {}

  async extractJson(input: Parameters<VisionModelAdapter['extractJson']>[0]): Promise<string> {
    const response = await getFetch(this.fetchImpl)('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + this.apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: this.model,
        input: [
          {
            role: 'user',
            content: [
              { type: 'input_text', text: input.prompt },
              {
                type: 'input_image',
                image_url: 'data:' + input.image.mimeType + ';base64,' + input.image.bytesBase64,
              },
            ],
          },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error('OpenAI extraction request failed with status ' + response.status + ': ' + (await response.text()));
    }

    return extractOpenAIText(await response.json());
  }
}

export class GeminiVisionAdapter implements VisionModelAdapter {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
    private readonly fetchImpl?: FetchLike
  ) {}

  async extractJson(input: Parameters<VisionModelAdapter['extractJson']>[0]): Promise<string> {
    const endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/' +
      encodeURIComponent(this.model) +
      ':generateContent?key=' +
      encodeURIComponent(this.apiKey);

    const response = await getFetch(this.fetchImpl)(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            role: 'user',
            parts: [
              { text: input.prompt },
              {
                inlineData: {
                  mimeType: input.image.mimeType,
                  data: input.image.bytesBase64,
                },
              },
            ],
          },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error('Gemini extraction request failed with status ' + response.status + ': ' + (await response.text()));
    }

    return extractGeminiText(await response.json());
  }
}

export function createVisionModelAdapter(env: Env = getEnv(), fetchImpl?: FetchLike): VisionModelAdapter {
  if (env.AI_PROVIDER === 'openai') {
    return new OpenAIVisionAdapter(env.AI_API_KEY, env.AI_MODEL || 'gpt-4.1-mini', fetchImpl);
  }

  if (env.AI_PROVIDER === 'gemini') {
    return new GeminiVisionAdapter(env.AI_API_KEY, env.AI_MODEL || 'gemini-1.5-flash', fetchImpl);
  }

  throw new Error('AI provider "' + env.AI_PROVIDER + '" is configured but no vision adapter is implemented yet.');
}

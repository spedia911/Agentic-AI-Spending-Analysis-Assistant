import { screenshotExtractionResultSchema, type ScreenshotExtractionResult } from './schema';

function stripCodeFence(value: string): string {
  const trimmed = value.trim();
  if (trimmed.startsWith('```')) {
    return trimmed.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();
  }
  return trimmed;
}

function extractJsonObject(value: string): string {
  const unfenced = stripCodeFence(value);
  const firstBrace = unfenced.indexOf('{');
  const lastBrace = unfenced.lastIndexOf('}');
  if (firstBrace === -1 || lastBrace === -1 || lastBrace <= firstBrace) {
    throw new Error('Model response did not contain a JSON object.');
  }
  return unfenced.slice(firstBrace, lastBrace + 1);
}

export function parseExtractionJson(rawModelOutput: string, expectedSourceDocumentId: string): ScreenshotExtractionResult {
  let parsed: unknown;
  try {
    parsed = JSON.parse(extractJsonObject(rawModelOutput));
  } catch (error) {
    throw new Error('Invalid extraction JSON: ' + (error as Error).message);
  }

  const result = screenshotExtractionResultSchema.safeParse(parsed);
  if (!result.success) {
    const issues = result.error.issues
      .map((issue) => issue.path.join('.') + ' ' + issue.message)
      .join('; ');
    throw new Error('Extraction JSON failed schema validation: ' + issues);
  }

  if (result.data.source_document_id !== expectedSourceDocumentId) {
    return {
      ...result.data,
      source_document_id: expectedSourceDocumentId,
      warnings: [
        ...result.data.warnings,
        'Model returned a mismatched source document ID; corrected during parsing.',
      ],
    };
  }

  return result.data;
}

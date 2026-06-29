import {
  buildBankActivityExtractionPrompt,
  buildCreditCardExtractionPrompt,
  buildMixedScreenshotExtractionPrompt,
} from './prompts';
import { parseExtractionJson } from './parser';
import type { ExtractionSourceImage, ScreenshotExtractionResult, VisionModelAdapter } from './schema';

export type ExtractionPromptMode = 'credit_card' | 'bank_activity' | 'mixed';

export interface ExtractScreenshotOptions {
  mode?: ExtractionPromptMode;
}

function buildPrompt(source: ExtractionSourceImage, mode: ExtractionPromptMode): string {
  if (mode === 'credit_card') {
    return buildCreditCardExtractionPrompt(source);
  }
  if (mode === 'bank_activity') {
    return buildBankActivityExtractionPrompt(source);
  }
  return buildMixedScreenshotExtractionPrompt(source);
}

export async function extractScreenshot(
  source: ExtractionSourceImage,
  model: VisionModelAdapter,
  options: ExtractScreenshotOptions = {}
): Promise<ScreenshotExtractionResult> {
  const mode = options.mode ?? 'mixed';
  const prompt = buildPrompt(source, mode);
  const rawModelOutput = await model.extractJson({
    prompt,
    image: {
      mimeType: source.mimeType,
      bytesBase64: source.imageBytes.toString('base64'),
    },
  });

  return parseExtractionJson(rawModelOutput, source.sourceDocumentId);
}

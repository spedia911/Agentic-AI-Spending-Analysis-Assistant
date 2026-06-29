import { describe, expect, it, vi } from 'vitest';
import { parseExtractionJson } from './parser';
import { buildBankActivityExtractionPrompt, buildCreditCardExtractionPrompt } from './prompts';
import { extractScreenshot } from './service';
import type { ExtractionSourceImage, VisionModelAdapter } from './schema';

const source: ExtractionSourceImage = {
  sourceDocumentId: 'drive-file-1',
  fileName: 'june-card.png',
  mimeType: 'image/png',
  imageBytes: Buffer.from('fake-image-bytes'),
};

const validExtraction = {
  source_document_id: 'drive-file-1',
  screenshot_kind: 'credit_card',
  raw_text: 'Jun 12 Trader Joes $42.19',
  extraction_confidence: 0.91,
  transactions: [
    {
      row_index: 0,
      date_text: 'Jun 12',
      merchant_text: 'Trader Joes',
      amount_text: '$42.19',
      account_source_text: 'Visa *1234',
      transaction_type_hint: 'expense',
      confidence: 0.93,
      evidence_text: 'Jun 12 Trader Joes $42.19',
    },
  ],
  asset_snapshots: [],
  warnings: [],
};

describe('extraction prompts', () => {
  it('builds strict credit card and bank prompts with source context', () => {
    const cardPrompt = buildCreditCardExtractionPrompt(source);
    const bankPrompt = buildBankActivityExtractionPrompt(source);

    expect(cardPrompt).toContain('credit card screenshot');
    expect(cardPrompt).toContain('Source document ID: drive-file-1');
    expect(cardPrompt).toContain('Return only valid JSON');
    expect(bankPrompt).toContain('bank activity and visible balance');
    expect(bankPrompt).toContain('asset_snapshots');
  });
});

describe('parseExtractionJson', () => {
  it('parses fenced JSON and validates candidate rows', () => {
    const parsed = parseExtractionJson('```json\n' + JSON.stringify(validExtraction) + '\n```', 'drive-file-1');

    expect(parsed.screenshot_kind).toBe('credit_card');
    expect(parsed.transactions).toHaveLength(1);
    expect(parsed.transactions[0].merchant_text).toBe('Trader Joes');
    expect(parsed.transactions[0].confidence).toBe(0.93);
  });

  it('corrects mismatched source document IDs and preserves a warning', () => {
    const parsed = parseExtractionJson(
      JSON.stringify({ ...validExtraction, source_document_id: 'wrong-id' }),
      'drive-file-1'
    );

    expect(parsed.source_document_id).toBe('drive-file-1');
    expect(parsed.warnings).toContain('Model returned a mismatched source document ID; corrected during parsing.');
  });

  it('throws a useful error for invalid model output', () => {
    expect(() => parseExtractionJson('not json', 'drive-file-1')).toThrow('Invalid extraction JSON');
  });
});

describe('extractScreenshot', () => {
  it('sends image bytes and prompt to a model adapter', async () => {
    const model: VisionModelAdapter = {
      extractJson: vi.fn().mockResolvedValue(JSON.stringify(validExtraction)),
    };

    const result = await extractScreenshot(source, model, { mode: 'credit_card' });

    expect(result.transactions[0].amount_text).toBe('$42.19');
    expect(model.extractJson).toHaveBeenCalledWith({
      prompt: expect.stringContaining('credit card screenshot'),
      image: {
        mimeType: 'image/png',
        bytesBase64: Buffer.from('fake-image-bytes').toString('base64'),
      },
    });
  });
});

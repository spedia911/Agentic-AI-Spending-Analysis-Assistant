import { z } from 'zod';

const confidenceSchema = z.coerce.number().min(0).max(1).default(0.5);
const evidenceRegionSchema = z.object({
  x: z.coerce.number().min(0).max(1),
  y: z.coerce.number().min(0).max(1),
  width: z.coerce.number().min(0).max(1),
  height: z.coerce.number().min(0).max(1),
});

export const extractedTransactionCandidateSchema = z.object({
  row_index: z.coerce.number().int().nonnegative(),
  date_text: z.string().nullable().default(null),
  merchant_text: z.string().nullable().default(null),
  amount_text: z.string().nullable().default(null),
  account_source_text: z.string().nullable().default(null),
  transaction_type_hint: z.enum(['expense', 'income', 'transfer', 'payment', 'fee', 'refund', 'unknown']).default('unknown'),
  confidence: confidenceSchema,
  evidence_text: z.string().min(1),
  evidence_region: evidenceRegionSchema.nullable().optional(),
});

export const extractedAssetSnapshotCandidateSchema = z.object({
  row_index: z.coerce.number().int().nonnegative(),
  account_label_text: z.string().nullable().default(null),
  balance_text: z.string().nullable().default(null),
  balance_type_hint: z.enum(['checking', 'savings', 'credit_available', 'credit_balance', 'unknown']).default('unknown'),
  observed_date_text: z.string().nullable().default(null),
  confidence: confidenceSchema,
  evidence_text: z.string().min(1),
  evidence_region: evidenceRegionSchema.nullable().optional(),
});

export const screenshotExtractionResultSchema = z.object({
  source_document_id: z.string().min(1),
  screenshot_kind: z.enum(['credit_card', 'bank_activity', 'mixed', 'unknown']).default('unknown'),
  raw_text: z.string().default(''),
  extraction_confidence: confidenceSchema,
  transactions: z.array(extractedTransactionCandidateSchema).default([]),
  asset_snapshots: z.array(extractedAssetSnapshotCandidateSchema).default([]),
  warnings: z.array(z.string()).default([]),
});

export type ExtractedTransactionCandidate = z.infer<typeof extractedTransactionCandidateSchema>;
export type ExtractedAssetSnapshotCandidate = z.infer<typeof extractedAssetSnapshotCandidateSchema>;
export type ScreenshotExtractionResult = z.infer<typeof screenshotExtractionResultSchema>;

export interface ExtractionSourceImage {
  sourceDocumentId: string;
  fileName: string;
  mimeType: string;
  imageBytes: Buffer;
}

export interface VisionModelAdapter {
  extractJson(input: {
    prompt: string;
    image: {
      mimeType: string;
      bytesBase64: string;
    };
  }): Promise<string>;
}

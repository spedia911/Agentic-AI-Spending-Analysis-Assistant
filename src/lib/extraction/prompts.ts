import type { ExtractionSourceImage } from './schema';

const STRICT_JSON_CONTRACT = [
  'Return only valid JSON. Do not wrap it in markdown. Do not include commentary.',
  'The JSON object must match this shape exactly:',
  '{',
  '  "source_document_id": "string",',
  '  "screenshot_kind": "credit_card" | "bank_activity" | "mixed" | "unknown",',
  '  "raw_text": "all readable text, preserving line breaks when useful",',
  '  "extraction_confidence": 0.0,',
  '  "transactions": [',
  '    {',
  '      "row_index": 0,',
  '      "date_text": "visible date or null",',
  '      "merchant_text": "merchant or description or null",',
  '      "amount_text": "visible signed or unsigned amount or null",',
  '      "account_source_text": "visible account label/source or null",',
  '      "transaction_type_hint": "expense" | "income" | "transfer" | "payment" | "fee" | "refund" | "unknown",',
  '      "confidence": 0.0,',
  '      "evidence_text": "short exact nearby text that supports this row"',
  '    }',
  '  ],',
  '  "asset_snapshots": [',
  '    {',
  '      "row_index": 0,',
  '      "account_label_text": "visible account label or null",',
  '      "balance_text": "visible balance amount or null",',
  '      "balance_type_hint": "checking" | "savings" | "credit_available" | "credit_balance" | "unknown",',
  '      "observed_date_text": "visible date or inferred period text or null",',
  '      "confidence": 0.0,',
  '      "evidence_text": "short exact nearby text that supports this balance"',
  '    }',
  '  ],',
  '  "warnings": ["non-sensitive issue summary"]',
  '}',
].join('\n');

export function buildCreditCardExtractionPrompt(source: Pick<ExtractionSourceImage, 'sourceDocumentId' | 'fileName'>): string {
  return [
    'You are extracting credit card screenshot data for a personal spending analysis assistant.',
    'Focus on visible transaction rows: date, merchant/description, amount, account/source label, and row evidence.',
    'If a required field is unclear, keep the row and set the unclear field to null with lower confidence.',
    'Do not infer merchants or dates that are not visible. Preserve ambiguous evidence for human review.',
    'Use transaction_type_hint="payment" for credit-card payments and "refund" for credits/refunds when visible.',
    'Source document ID: ' + source.sourceDocumentId,
    'File name: ' + source.fileName,
    STRICT_JSON_CONTRACT,
  ].join('\n\n');
}

export function buildBankActivityExtractionPrompt(source: Pick<ExtractionSourceImage, 'sourceDocumentId' | 'fileName'>): string {
  return [
    'You are extracting bank activity and visible balance data for a personal spending analysis assistant.',
    'Focus on activity rows plus any visible checking, savings, credit balance, or available credit snapshots.',
    'If rows include deposits, payments, transfers, or fees, use the best transaction_type_hint from visible labels.',
    'For bank outflows to billers such as rent, utilities, PG&E, internet, or subscriptions, keep the merchant/description text so categorization can count them as spending.',
    'If an account balance is visible, create an asset_snapshots item even when no activity rows are visible.',
    'Do not expose full account numbers; copy only masked labels when visible.',
    'Source document ID: ' + source.sourceDocumentId,
    'File name: ' + source.fileName,
    STRICT_JSON_CONTRACT,
  ].join('\n\n');
}

export function buildMixedScreenshotExtractionPrompt(source: Pick<ExtractionSourceImage, 'sourceDocumentId' | 'fileName'>): string {
  return [
    'You are extracting financial screenshot data for a personal spending analysis assistant.',
    'The screenshot may contain credit card transactions, bank activity, balances, or a mix of these.',
    'Extract all visible transaction rows and all visible asset/balance snapshots.',
    'If the screenshot type is clear, set screenshot_kind accordingly; otherwise use mixed or unknown.',
    'Source document ID: ' + source.sourceDocumentId,
    'File name: ' + source.fileName,
    STRICT_JSON_CONTRACT,
  ].join('\n\n');
}

import crypto from 'crypto';
import type { AssetSnapshot, ReviewItem, Transaction } from '../../types/domain';
import type { ExtractedAssetSnapshotCandidate, ExtractedTransactionCandidate } from '../extraction';

export interface NormalizeContext {
  sourceDocumentId: string;
  observedMonthHint?: string;
  now?: string;
}

export interface NormalizedExtractionOutput {
  transactions: Transaction[];
  assetSnapshots: AssetSnapshot[];
  reviewItems: ReviewItem[];
}

function stableHash(parts: Array<string | number | null | undefined>): string {
  return crypto
    .createHash('sha256')
    .update(parts.map((part) => String(part ?? '')).join('|'))
    .digest('hex')
    .slice(0, 16);
}

export function normalizeAmountText(value: string | null): number | null {
  if (!value) return null;
  const trimmed = value.trim();
  const isParenthesesNegative = /^\(.+\)$/.test(trimmed);
  const hasNegativeSign = trimmed.includes('-') || /\bCR\b/i.test(trimmed);
  const numeric = Number(trimmed.replace(/[^0-9.]/g, ''));
  if (Number.isNaN(numeric)) return null;
  return isParenthesesNegative || hasNegativeSign ? -numeric : numeric;
}

export function normalizeDateText(value: string | null, observedMonthHint?: string): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  const isoMatch = trimmed.match(/\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b/);
  if (isoMatch) {
    const [, year, month, day] = isoMatch;
    return year + '-' + month.padStart(2, '0') + '-' + day.padStart(2, '0');
  }

  const monthDayMatch = trimmed.match(/\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})\b/i);
  if (monthDayMatch && observedMonthHint) {
    const year = observedMonthHint.slice(0, 4);
    const monthNames = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    const month = String(monthNames.indexOf(monthDayMatch[1].slice(0, 3).toLowerCase()) + 1).padStart(2, '0');
    return year + '-' + month + '-' + monthDayMatch[2].padStart(2, '0');
  }

  const slashMatch = trimmed.match(/\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/);
  if (slashMatch) {
    const [, month, day, yearText] = slashMatch;
    const year = yearText
      ? yearText.length === 2
        ? '20' + yearText
        : yearText
      : observedMonthHint?.slice(0, 4);
    if (!year) return null;
    return year + '-' + month.padStart(2, '0') + '-' + day.padStart(2, '0');
  }

  return null;
}

export function observedMonthFromDate(date: string | null, fallback?: string): string {
  if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return date.slice(0, 7);
  }
  return fallback ?? 'unknown';
}

export function normalizeMerchant(value: string | null): string {
  if (!value) return 'Unknown merchant';
  return value.replace(/\s+/g, ' ').trim();
}

export function maskAccountLabel(value: string | null): string {
  if (!value) return 'Unknown account';
  return value
    .replace(/\b\d{5,}\b/g, (match) => '*'.repeat(Math.max(0, match.length - 4)) + match.slice(-4))
    .replace(/\s+/g, ' ')
    .trim();
}

function transactionReviewReasons(candidate: ExtractedTransactionCandidate, date: string | null, amount: number | null): string[] {
  const reasons: string[] = [];
  if (!date) reasons.push('missing_date');
  if (!candidate.merchant_text) reasons.push('missing_merchant');
  if (amount === null) reasons.push('missing_amount');
  if (candidate.confidence < 0.75) reasons.push('low_extraction_confidence');
  return reasons;
}

function createReviewItem(targetId: string, issueType: ReviewItem['issue_type'], question: string, now: string): ReviewItem {
  return {
    review_item_id: 'review_' + stableHash([targetId, issueType]),
    target_type: 'transaction',
    target_id: targetId,
    issue_type: issueType,
    severity: issueType === 'missing_field' ? 'high' : 'medium',
    question,
    suggested_options: [],
    status: 'pending',
    user_answer: null,
    created_at: now,
    resolved_at: null,
  };
}

function serializeEvidenceRegion(region: ExtractedTransactionCandidate['evidence_region'] | ExtractedAssetSnapshotCandidate['evidence_region']): string | null {
  if (!region) return null;
  return JSON.stringify({
    x: Number(region.x.toFixed(4)),
    y: Number(region.y.toFixed(4)),
    width: Number(region.width.toFixed(4)),
    height: Number(region.height.toFixed(4)),
  });
}

export function normalizeTransactionCandidate(
  candidate: ExtractedTransactionCandidate,
  context: NormalizeContext
): { transaction: Transaction; reviewItems: ReviewItem[] } {
  const now = context.now ?? new Date().toISOString();
  const date = normalizeDateText(candidate.date_text, context.observedMonthHint);
  const amount = normalizeAmountText(candidate.amount_text);
  const merchant = normalizeMerchant(candidate.merchant_text);
  const observedMonth = observedMonthFromDate(date, context.observedMonthHint);
  const transactionId = 'txn_' + stableHash([
    context.sourceDocumentId,
    candidate.row_index,
    date,
    merchant,
    amount,
  ]);
  const reasons = transactionReviewReasons(candidate, date, amount);

  const transaction: Transaction = {
    transaction_id: transactionId,
    source_document_id: context.sourceDocumentId,
    observed_month: observedMonth,
    transaction_date: date ?? '',
    merchant_raw: candidate.merchant_text ?? '',
    merchant_normalized: merchant,
    amount: amount ?? 0,
    transaction_type: candidate.transaction_type_hint,
    account_label: maskAccountLabel(candidate.account_source_text),
    category: 'uncategorized',
    category_confidence: 0,
    extraction_confidence: candidate.confidence,
    validation_status: reasons.length > 0 ? 'needs_review' : 'valid',
    review_status: reasons.length > 0 ? 'pending' : 'none',
    evidence_text: candidate.evidence_text,
    evidence_region: serializeEvidenceRegion(candidate.evidence_region),
    created_at: now,
    updated_at: now,
  };

  const reviewItems = reasons.map((reason) =>
    createReviewItem(
      transactionId,
      reason === 'low_extraction_confidence' ? 'low_confidence' : 'missing_field',
      'Please review transaction "' + merchant + '" because of ' + reason.replace(/_/g, ' ') + '.',
      now
    )
  );

  return { transaction, reviewItems };
}

export function normalizeAssetSnapshotCandidate(
  candidate: ExtractedAssetSnapshotCandidate,
  context: NormalizeContext
): { assetSnapshot: AssetSnapshot; reviewItems: ReviewItem[] } {
  const now = context.now ?? new Date().toISOString();
  const observedDate = normalizeDateText(candidate.observed_date_text, context.observedMonthHint);
  const balance = normalizeAmountText(candidate.balance_text);
  const accountLabel = maskAccountLabel(candidate.account_label_text);
  const observedMonth = observedMonthFromDate(observedDate, context.observedMonthHint);
  const assetSnapshotId = 'asset_' + stableHash([
    context.sourceDocumentId,
    candidate.row_index,
    accountLabel,
    balance,
    observedDate,
  ]);

  const needsReview = !observedDate || balance === null || !candidate.account_label_text || candidate.confidence < 0.75;
  const assetSnapshot: AssetSnapshot = {
    asset_snapshot_id: assetSnapshotId,
    source_document_id: context.sourceDocumentId,
    observed_month: observedMonth,
    observed_date: observedDate ?? '',
    account_label: accountLabel,
    balance: balance ?? 0,
    balance_type: candidate.balance_type_hint,
    confidence: candidate.confidence,
    evidence_text: candidate.evidence_text,
    evidence_region: serializeEvidenceRegion(candidate.evidence_region),
    created_at: now,
  };

  const reviewItems: ReviewItem[] = needsReview
    ? [
        {
          review_item_id: 'review_' + stableHash([assetSnapshotId, 'missing_field']),
          target_type: 'asset_snapshot',
          target_id: assetSnapshotId,
          issue_type: candidate.confidence < 0.75 ? 'low_confidence' : 'missing_field',
          severity: balance === null ? 'high' : 'medium',
          question: 'Please review the balance snapshot for ' + accountLabel + '.',
          suggested_options: [],
          status: 'pending',
          user_answer: null,
          created_at: now,
          resolved_at: null,
        },
      ]
    : [];

  return { assetSnapshot, reviewItems };
}

export function normalizeExtractionCandidates(
  transactions: ExtractedTransactionCandidate[],
  assetSnapshots: ExtractedAssetSnapshotCandidate[],
  context: NormalizeContext
): NormalizedExtractionOutput {
  const normalizedTransactions = transactions.map((candidate) => normalizeTransactionCandidate(candidate, context));
  const normalizedAssets = assetSnapshots.map((candidate) => normalizeAssetSnapshotCandidate(candidate, context));

  return {
    transactions: normalizedTransactions.map((item) => item.transaction),
    assetSnapshots: normalizedAssets.map((item) => item.assetSnapshot),
    reviewItems: [
      ...normalizedTransactions.flatMap((item) => item.reviewItems),
      ...normalizedAssets.flatMap((item) => item.reviewItems),
    ],
  };
}

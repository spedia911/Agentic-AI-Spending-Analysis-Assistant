import crypto from 'crypto';
import type { Env } from '../env';
import type { Correction, ReviewItem, Transaction } from '../../types/domain';
import { isCardPayment } from '../finance/spending';

export type SpendingCategory =
  | 'groceries'
  | 'dining'
  | 'utilities'
  | 'transportation'
  | 'rent'
  | 'subscriptions'
  | 'shopping'
  | 'healthcare'
  | 'transfer'
  | 'income'
  | 'fees'
  | 'miscellaneous';

export interface CategoryClassificationInput {
  merchant: string;
  amount: number;
  transactionType: Transaction['transaction_type'];
  evidenceText: string;
}

export interface CategoryClassificationDecision {
  category: SpendingCategory;
  confidence: number;
  reason: string;
}

export interface CategoryClassifier {
  classify(input: CategoryClassificationInput): Promise<CategoryClassificationDecision>;
}

export interface CategorizationContext {
  corrections?: Correction[];
  lowConfidenceThreshold?: number;
  now?: string;
}

export interface CategorizationWithFallbackContext extends CategorizationContext {
  classifier?: CategoryClassifier | null;
}

export interface CategorizationResult {
  transactions: Transaction[];
  reviewItems: ReviewItem[];
}

type CategoryRule = {
  category: SpendingCategory;
  confidence: number;
  reason: string;
  patterns: RegExp[];
};

type CategoryDecision = {
  category: SpendingCategory;
  confidence: number;
  reason: string;
  alternatives: SpendingCategory[];
  needsReview: boolean;
};

const AMBIGUOUS_MERCHANTS = [/amazon/i, /costco/i, /walmart/i, /target/i, /paypal/i, /venmo/i, /apple/i];

const RULES: CategoryRule[] = [
  { category: 'groceries', confidence: 0.95, reason: 'Matched grocery merchant rule.', patterns: [/trader joe/i, /whole foods/i, /safeway/i, /kroger/i, /h mart/i, /aldi/i, /grocery/i] },
  { category: 'dining', confidence: 0.94, reason: 'Matched dining merchant rule.', patterns: [/restaurant/i, /cafe/i, /coffee/i, /starbucks/i, /mcdonald/i, /chipotle/i, /doordash/i, /ubereats/i] },
  { category: 'utilities', confidence: 0.94, reason: 'Matched utility merchant rule.', patterns: [/pge/i, /pg&e/i, /pacific gas/i, /electric/i, /water/i, /gas utility/i, /internet/i, /comcast/i, /xfinity/i, /verizon/i, /at&t/i] },
  { category: 'transportation', confidence: 0.93, reason: 'Matched transportation merchant rule.', patterns: [/uber/i, /lyft/i, /shell/i, /chevron/i, /exxon/i, /parking/i, /transit/i, /metro/i] },
  { category: 'rent', confidence: 0.96, reason: 'Matched rent merchant rule.', patterns: [/rent/i, /apartment/i, /property management/i, /landlord/i] },
  { category: 'subscriptions', confidence: 0.94, reason: 'Matched subscription merchant rule.', patterns: [/netflix/i, /spotify/i, /hulu/i, /disney/i, /youtube/i, /openai/i, /icloud/i, /subscription/i] },
  { category: 'shopping', confidence: 0.78, reason: 'Matched broad shopping merchant rule.', patterns: [/amazon/i, /costco/i, /walmart/i, /target/i, /paypal/i, /apple/i, /etsy/i, /best buy/i] },
  { category: 'healthcare', confidence: 0.95, reason: 'Matched healthcare merchant rule.', patterns: [/pharmacy/i, /cvs/i, /walgreens/i, /doctor/i, /clinic/i, /hospital/i, /dental/i] },
  { category: 'fees', confidence: 0.95, reason: 'Matched fee rule.', patterns: [/fee/i, /interest charge/i, /late payment/i] },
];

function stableHash(parts: Array<string | number | null | undefined>): string {
  return crypto
    .createHash('sha256')
    .update(parts.map((part) => String(part ?? '')).join('|'))
    .digest('hex')
    .slice(0, 16);
}

function normalizeKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function merchantCorrectionMap(corrections: Correction[]): Map<string, SpendingCategory> {
  const map = new Map<string, SpendingCategory>();
  for (const correction of corrections) {
    if (
      correction.apply_future &&
      correction.target_type === 'merchant_rule' &&
      correction.field_name === 'category' &&
      isSpendingCategory(correction.new_value)
    ) {
      map.set(normalizeKey(correction.target_id), correction.new_value);
    }
  }
  return map;
}

export function isSpendingCategory(value: string): value is SpendingCategory {
  return [
    'groceries',
    'dining',
    'utilities',
    'transportation',
    'rent',
    'subscriptions',
    'shopping',
    'healthcare',
    'transfer',
    'income',
    'fees',
    'miscellaneous',
  ].includes(value);
}

function categoryForTransactionType(transaction: Transaction): CategoryDecision | null {
  if (transaction.transaction_type === 'income') {
    return { category: 'income', confidence: 0.98, reason: 'Transaction type is income.', alternatives: [], needsReview: false };
  }
  if (transaction.transaction_type === 'transfer') {
    return { category: 'transfer', confidence: 0.94, reason: 'Transaction type is transfer/payment.', alternatives: [], needsReview: false };
  }
  if (transaction.transaction_type === 'payment' && (/transfer|zelle|venmo|cash app/i.test(transaction.merchant_normalized + ' ' + transaction.evidence_text) || isCardPayment(transaction))) {
    return { category: 'transfer', confidence: 0.94, reason: 'Payment appears to be an internal transfer or card payment.', alternatives: [], needsReview: false };
  }
  if (transaction.transaction_type === 'fee') {
    return { category: 'fees', confidence: 0.96, reason: 'Transaction type is fee.', alternatives: [], needsReview: false };
  }
  return null;
}

function shouldUseClassifier(decision: CategoryDecision): boolean {
  return decision.category === 'miscellaneous' && decision.reason === 'No deterministic category rule matched.';
}

function clampConfidence(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, Number(value.toFixed(2))));
}

function classifierDecision(decision: CategoryClassificationDecision, threshold: number): CategoryDecision {
  const confidence = clampConfidence(decision.confidence);
  return {
    category: decision.category,
    confidence,
    reason: 'AI category fallback: ' + decision.reason,
    alternatives: decision.category === 'miscellaneous' ? ['shopping', 'dining', 'utilities', 'miscellaneous'] : [decision.category, 'miscellaneous'],
    needsReview: confidence < threshold,
  };
}

function decideCategory(transaction: Transaction, corrections: Map<string, SpendingCategory>, threshold: number): CategoryDecision {
  const typeDecision = categoryForTransactionType(transaction);
  if (typeDecision) return typeDecision;

  const merchant = transaction.merchant_normalized || transaction.merchant_raw;
  const merchantKey = normalizeKey(merchant);
  const correction = corrections.get(merchantKey);
  if (correction) {
    return { category: correction, confidence: 0.99, reason: 'Matched user correction memory.', alternatives: [], needsReview: false };
  }

  for (const rule of RULES) {
    if (rule.patterns.some((pattern) => pattern.test(merchant))) {
      const ambiguous = AMBIGUOUS_MERCHANTS.some((pattern) => pattern.test(merchant));
      const needsReview = ambiguous || rule.confidence < threshold;
      return {
        category: rule.category,
        confidence: rule.confidence,
        reason: rule.reason,
        alternatives: ambiguous ? ['groceries', 'shopping', 'miscellaneous'] : [],
        needsReview,
      };
    }
  }

  return {
    category: 'miscellaneous',
    confidence: 0.45,
    reason: 'No deterministic category rule matched.',
    alternatives: ['groceries', 'dining', 'shopping', 'utilities', 'miscellaneous'],
    needsReview: true,
  };
}

function makeCategoryReviewItem(transaction: Transaction, decision: CategoryDecision, now: string): ReviewItem {
  return {
    review_item_id: 'review_' + stableHash([transaction.transaction_id, 'unclear_category', decision.category]),
    target_type: 'transaction',
    target_id: transaction.transaction_id,
    issue_type: 'unclear_category',
    severity: decision.confidence < 0.5 ? 'medium' : 'low',
    question:
      'Is "' +
      transaction.merchant_normalized +
      '" best categorized as ' +
      decision.category +
      '?',
    suggested_options: decision.alternatives.length > 0 ? decision.alternatives : [decision.category, 'miscellaneous'],
    status: 'pending',
    user_answer: null,
    created_at: now,
    resolved_at: null,
  };
}

function applyCategoryDecision(transaction: Transaction, decision: CategoryDecision, now: string): { transaction: Transaction; reviewItem: ReviewItem | null } {
  const needsReview = decision.needsReview;
  const updated: Transaction = {
    ...transaction,
    category: decision.category,
    category_confidence: decision.confidence,
    validation_status: needsReview ? 'needs_review' : transaction.validation_status,
    review_status: needsReview ? 'pending' : transaction.review_status,
    updated_at: now,
  };

  return {
    transaction: updated,
    reviewItem: needsReview ? makeCategoryReviewItem(updated, decision, now) : null,
  };
}

export function categorizeTransactions(transactions: Transaction[], context: CategorizationContext = {}): CategorizationResult {
  const now = context.now ?? new Date().toISOString();
  const threshold = context.lowConfidenceThreshold ?? 0.75;
  const corrections = merchantCorrectionMap(context.corrections ?? []);
  const reviewItems: ReviewItem[] = [];

  const categorized = transactions.map((transaction) => {
    const decision = decideCategory(transaction, corrections, threshold);
    decision.needsReview = decision.needsReview || decision.confidence < threshold;
    const applied = applyCategoryDecision(transaction, decision, now);
    if (applied.reviewItem) reviewItems.push(applied.reviewItem);
    return applied.transaction;
  });

  return { transactions: categorized, reviewItems };
}

export async function categorizeTransactionsWithFallback(
  transactions: Transaction[],
  context: CategorizationWithFallbackContext = {}
): Promise<CategorizationResult> {
  const now = context.now ?? new Date().toISOString();
  const threshold = context.lowConfidenceThreshold ?? 0.75;
  const corrections = merchantCorrectionMap(context.corrections ?? []);
  const reviewItems: ReviewItem[] = [];
  const categorized: Transaction[] = [];

  for (const transaction of transactions) {
    let decision = decideCategory(transaction, corrections, threshold);
    if (context.classifier && shouldUseClassifier(decision)) {
      try {
        const classified = await context.classifier.classify({
          merchant: transaction.merchant_normalized || transaction.merchant_raw,
          amount: transaction.amount,
          transactionType: transaction.transaction_type,
          evidenceText: transaction.evidence_text,
        });
        decision = classifierDecision(classified, threshold);
      } catch {
        decision = { ...decision, reason: decision.reason + ' AI fallback failed; routed to review.' };
      }
    }

    decision.needsReview = decision.needsReview || decision.confidence < threshold;
    const applied = applyCategoryDecision(transaction, decision, now);
    if (applied.reviewItem) reviewItems.push(applied.reviewItem);
    categorized.push(applied.transaction);
  }

  return { transactions: categorized, reviewItems };
}
function parseClassifierResponse(value: unknown): CategoryClassificationDecision {
  const root = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  const rawCategory = typeof root.category === 'string' ? root.category.toLowerCase() : '';
  if (!isSpendingCategory(rawCategory)) {
    throw new Error('Category classifier returned unsupported category.');
  }
  return {
    category: rawCategory,
    confidence: clampConfidence(typeof root.confidence === 'number' ? root.confidence : Number(root.confidence)),
    reason:
      typeof root.reason === 'string' && root.reason.trim()
        ? root.reason.trim().slice(0, 180)
        : 'Model selected a category from the allowed list.',
  };
}

function extractJsonObject(text: string): unknown {
  const trimmed = text.trim();
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end === -1 || end < start) throw new Error('Category classifier did not return JSON.');
  return JSON.parse(trimmed.slice(start, end + 1));
}

function classificationPrompt(input: CategoryClassificationInput): string {
  return [
    'Classify this personal finance transaction into exactly one allowed category.',
    'Allowed categories: groceries, dining, utilities, transportation, rent, subscriptions, shopping, healthcare, transfer, income, fees, miscellaneous.',
    'Return only JSON with keys category, confidence, reason.',
    'Merchant: ' + input.merchant,
    'Amount: ' + input.amount,
    'Transaction type: ' + input.transactionType,
    'Evidence: ' + input.evidenceText.slice(0, 500),
  ].join(String.fromCharCode(10));
}

class OpenAICategoryClassifier implements CategoryClassifier {
  constructor(private readonly apiKey: string, private readonly model: string) {}

  async classify(input: CategoryClassificationInput): Promise<CategoryClassificationDecision> {
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + this.apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: this.model,
        input: [{ role: 'user', content: [{ type: 'input_text', text: classificationPrompt(input) }] }],
      }),
    });
    if (!response.ok) throw new Error('OpenAI category classification failed with status ' + response.status);
    const body = (await response.json()) as Record<string, unknown>;
    const outputText = typeof body.output_text === 'string' ? body.output_text : JSON.stringify(body);
    return parseClassifierResponse(extractJsonObject(outputText));
  }
}

class GeminiCategoryClassifier implements CategoryClassifier {
  constructor(private readonly apiKey: string, private readonly model: string) {}

  async classify(input: CategoryClassificationInput): Promise<CategoryClassificationDecision> {
    const endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/' +
      encodeURIComponent(this.model) +
      ':generateContent?key=' +
      encodeURIComponent(this.apiKey);
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: classificationPrompt(input) }] }] }),
    });
    if (!response.ok) throw new Error('Gemini category classification failed with status ' + response.status);
    const body = (await response.json()) as Record<string, unknown>;
    const candidates = Array.isArray(body.candidates) ? body.candidates : [];
    const first = candidates[0] && typeof candidates[0] === 'object' ? (candidates[0] as Record<string, unknown>) : {};
    const content = first.content && typeof first.content === 'object' ? (first.content as Record<string, unknown>) : {};
    const parts = Array.isArray(content.parts) ? content.parts : [];
    const firstPart = parts[0] && typeof parts[0] === 'object' ? (parts[0] as Record<string, unknown>) : {};
    const outputText = typeof firstPart.text === 'string' ? firstPart.text : JSON.stringify(body);
    return parseClassifierResponse(extractJsonObject(outputText));
  }
}

export function createCategoryClassifier(env: Env): CategoryClassifier | null {
  if (env.AI_PROVIDER === 'openai') {
    return new OpenAICategoryClassifier(env.AI_API_KEY, env.AI_MODEL || 'gpt-4.1-mini');
  }
  if (env.AI_PROVIDER === 'gemini') {
    return new GeminiCategoryClassifier(env.AI_API_KEY, env.AI_MODEL || 'gemini-1.5-flash');
  }
  return null;
}

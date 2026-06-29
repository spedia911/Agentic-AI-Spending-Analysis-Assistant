import crypto from 'crypto';
import type { ReviewItem, Transaction } from '../../types/domain';

export interface ValidationContext {
  now?: string;
  today?: string;
  duplicateLookbackDays?: number;
}

export interface ValidationResult {
  transactions: Transaction[];
  reviewItems: ReviewItem[];
}

type ValidationIssue = {
  issueType: ReviewItem['issue_type'];
  severity: ReviewItem['severity'];
  question: string;
  suggestedOptions?: string[];
};

function stableHash(parts: Array<string | number | null | undefined>): string {
  return crypto
    .createHash('sha256')
    .update(parts.map((part) => String(part ?? '')).join('|'))
    .digest('hex')
    .slice(0, 16);
}

function normalizeMerchantKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function parseIsoDate(value: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(value + 'T00:00:00Z');
  return Number.isNaN(date.getTime()) ? null : date;
}

function daysBetween(a: string, b: string): number | null {
  const dateA = parseIsoDate(a);
  const dateB = parseIsoDate(b);
  if (!dateA || !dateB) return null;
  return Math.abs(dateA.getTime() - dateB.getTime()) / 86_400_000;
}

function makeReviewItem(transaction: Transaction, issue: ValidationIssue, now: string): ReviewItem {
  return {
    review_item_id: 'review_' + stableHash([transaction.transaction_id, issue.issueType, issue.question]),
    target_type: 'transaction',
    target_id: transaction.transaction_id,
    issue_type: issue.issueType,
    severity: issue.severity,
    question: issue.question,
    suggested_options: issue.suggestedOptions ?? [],
    status: 'pending',
    user_answer: null,
    created_at: now,
    resolved_at: null,
  };
}

function transactionIssues(transaction: Transaction, today: string): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const parsedDate = parseIsoDate(transaction.transaction_date);

  if (!transaction.transaction_date || !parsedDate) {
    issues.push({
      issueType: 'missing_field',
      severity: 'high',
      question: 'Please add or correct the transaction date for "' + transaction.merchant_normalized + '".',
    });
  } else if (parsedDate.getTime() > new Date(today + 'T00:00:00Z').getTime()) {
    issues.push({
      issueType: 'anomaly',
      severity: 'medium',
      question: 'This transaction date is in the future. Should it be corrected?',
    });
  }

  if (!transaction.merchant_normalized || transaction.merchant_normalized === 'Unknown merchant') {
    issues.push({
      issueType: 'missing_field',
      severity: 'high',
      question: 'Please identify the merchant for this transaction.',
    });
  }

  if (!Number.isFinite(transaction.amount) || transaction.amount === 0) {
    issues.push({
      issueType: 'missing_field',
      severity: 'high',
      question: 'Please confirm the amount for "' + transaction.merchant_normalized + '".',
    });
  } else if (Math.abs(transaction.amount) > 10000 && transaction.transaction_type === 'expense') {
    issues.push({
      issueType: 'anomaly',
      severity: 'medium',
      question: 'This expense is unusually large. Please confirm the amount and merchant.',
    });
  }

  if (transaction.extraction_confidence < 0.75) {
    issues.push({
      issueType: 'low_confidence',
      severity: 'medium',
      question: 'The extraction confidence is low for "' + transaction.merchant_normalized + '". Please review it.',
    });
  }

  return issues;
}

function duplicateIssues(transactions: Transaction[], lookbackDays: number): Map<string, ValidationIssue[]> {
  const issuesById = new Map<string, ValidationIssue[]>();

  for (let i = 0; i < transactions.length; i++) {
    for (let j = i + 1; j < transactions.length; j++) {
      const left = transactions[i];
      const right = transactions[j];
      const sameMerchant = normalizeMerchantKey(left.merchant_normalized) === normalizeMerchantKey(right.merchant_normalized);
      const sameAmount = Math.abs(left.amount - right.amount) < 0.01;
      const dayDelta = daysBetween(left.transaction_date, right.transaction_date);
      const closeDate = dayDelta !== null && dayDelta <= lookbackDays;

      if (sameMerchant && sameAmount && closeDate) {
        const issue: ValidationIssue = {
          issueType: 'duplicate_risk',
          severity: 'medium',
          question:
            'This looks like a duplicate charge for ' +
            left.merchant_normalized +
            ' around ' +
            left.transaction_date +
            '. Please confirm whether both rows are real.',
          suggestedOptions: ['both_are_real', 'duplicate_remove_one', 'needs_more_review'],
        };
        issuesById.set(left.transaction_id, [...(issuesById.get(left.transaction_id) ?? []), issue]);
        issuesById.set(right.transaction_id, [...(issuesById.get(right.transaction_id) ?? []), issue]);
      }
    }
  }

  return issuesById;
}

export function validateTransactions(transactions: Transaction[], context: ValidationContext = {}): ValidationResult {
  const now = context.now ?? new Date().toISOString();
  const today = context.today ?? now.slice(0, 10);
  const duplicateMap = duplicateIssues(transactions, context.duplicateLookbackDays ?? 3);
  const reviewItems: ReviewItem[] = [];

  const validatedTransactions = transactions.map((transaction) => {
    const issues = [
      ...transactionIssues(transaction, today),
      ...(duplicateMap.get(transaction.transaction_id) ?? []),
    ];
    const hasIssues = issues.length > 0;

    reviewItems.push(...issues.map((issue) => makeReviewItem(transaction, issue, now)));

    return {
      ...transaction,
      validation_status: hasIssues ? 'needs_review' : transaction.validation_status,
      review_status: hasIssues ? 'pending' : transaction.review_status,
      updated_at: now,
    } satisfies Transaction;
  });

  return {
    transactions: validatedTransactions,
    reviewItems,
  };
}

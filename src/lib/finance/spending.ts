import type { Transaction } from '../../types/domain';

const EXPLICIT_SPENDING_CATEGORIES = new Set([
  'groceries',
  'dining',
  'utilities',
  'transportation',
  'rent',
  'subscriptions',
  'shopping',
  'healthcare',
  'fees',
]);

export function isCardPayment(transaction: Pick<Transaction, 'merchant_normalized' | 'merchant_raw' | 'evidence_text' | 'transaction_type' | 'category'>): boolean {
  const text = [
    transaction.merchant_normalized,
    transaction.merchant_raw,
    transaction.evidence_text,
    transaction.category,
  ].join(' ');

  return (
    transaction.transaction_type === 'payment' &&
    /credit card|card payment|payment to card|card autopay|autopay.*card|chase card|amex|american express|capital one|citi card|discover card|visa payment|mastercard payment/i.test(text)
  );
}

export function spendingAmount(transaction: Pick<Transaction, 'amount' | 'transaction_type' | 'category' | 'merchant_normalized' | 'merchant_raw' | 'evidence_text'>): number {
  if (isCardPayment(transaction)) return 0;
  if (EXPLICIT_SPENDING_CATEGORIES.has(transaction.category)) return Math.abs(transaction.amount);
  if (
    transaction.transaction_type !== 'expense' &&
    transaction.transaction_type !== 'fee' &&
    !(transaction.transaction_type === 'payment' && transaction.category !== 'transfer')
  ) {
    return 0;
  }
  return Math.abs(transaction.amount);
}

export function transferAmount(transaction: Pick<Transaction, 'amount' | 'transaction_type' | 'category' | 'merchant_normalized' | 'merchant_raw' | 'evidence_text'>): number {
  if (transaction.transaction_type === 'transfer' || isCardPayment(transaction)) return Math.abs(transaction.amount);
  if (transaction.transaction_type === 'payment' && transaction.category === 'transfer') return Math.abs(transaction.amount);
  return 0;
}

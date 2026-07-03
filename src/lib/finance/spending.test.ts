import { describe, expect, it } from 'vitest';
import { spendingAmount, transferAmount } from './spending';
import type { Transaction } from '../../types/domain';

function transaction(overrides: Partial<Transaction>): Transaction {
  return {
    transaction_id: 'txn-1',
    source_document_id: 'source-1',
    observed_month: '2026-06',
    transaction_date: '2026-06-12',
    merchant_raw: 'Merchant',
    merchant_normalized: 'Merchant',
    amount: 100,
    transaction_type: 'expense',
    account_label: 'Account *1234',
    category: 'miscellaneous',
    category_confidence: 0.9,
    extraction_confidence: 0.9,
    validation_status: 'valid',
    review_status: 'none',
    evidence_text: 'Merchant $100.00',
    created_at: '2026-06-12T10:00:00Z',
    updated_at: '2026-06-12T10:00:00Z',
    ...overrides,
  };
}

describe('cash-flow amount helpers', () => {
  it('counts credit card charges as spending regardless of source sign', () => {
    expect(spendingAmount(transaction({ amount: 42.19, transaction_type: 'expense', category: 'groceries' }))).toBe(42.19);
    expect(spendingAmount(transaction({ amount: -42.19, transaction_type: 'expense', category: 'groceries' }))).toBe(42.19);
  });

  it('does not count refunds as spending even when the merchant category is spend-like', () => {
    const refund = transaction({
      amount: -24.5,
      transaction_type: 'refund',
      category: 'shopping',
      merchant_normalized: 'Target Return',
      evidence_text: 'TARGET RETURN CR -24.50',
    });

    expect(spendingAmount(refund)).toBe(0);
    expect(transferAmount(refund)).toBe(0);
  });

  it('keeps bank deposits out of spending and transfer totals', () => {
    const deposit = transaction({
      amount: 2500,
      transaction_type: 'income',
      category: 'income',
      merchant_normalized: 'Payroll Deposit',
      evidence_text: 'PAYROLL DEP 2500.00',
    });

    expect(spendingAmount(deposit)).toBe(0);
    expect(transferAmount(deposit)).toBe(0);
  });

  it('counts credit card payments as transfers, not spending', () => {
    const cardPayment = transaction({
      amount: -850,
      transaction_type: 'payment',
      category: 'miscellaneous',
      merchant_raw: 'CHASE CREDIT CARD PAYMENT',
      merchant_normalized: 'Chase Credit Card Payment',
      evidence_text: 'CHASE CREDIT CARD PAYMENT -850.00',
    });

    expect(spendingAmount(cardPayment)).toBe(0);
    expect(transferAmount(cardPayment)).toBe(850);
  });

  it('counts bill payments and bank withdrawals as spending when category evidence supports it', () => {
    const utilityPayment = transaction({
      amount: -160,
      transaction_type: 'payment',
      category: 'utilities',
      merchant_raw: 'PG&E WEB PAYMENT',
      merchant_normalized: 'PG&E',
      evidence_text: 'PG&E WEB PAYMENT -160.00',
    });
    const atmFee = transaction({
      amount: -3,
      transaction_type: 'fee',
      category: 'fees',
      merchant_raw: 'ATM WITHDRAWAL FEE',
      merchant_normalized: 'ATM Fee',
      evidence_text: 'ATM WITHDRAWAL FEE -3.00',
    });

    expect(spendingAmount(utilityPayment)).toBe(160);
    expect(transferAmount(utilityPayment)).toBe(0);
    expect(spendingAmount(atmFee)).toBe(3);
    expect(transferAmount(atmFee)).toBe(0);
  });

  it('keeps unclassified payment rows out of spending until evidence or correction supports a spending category', () => {
    const unknownPayment = transaction({
      amount: -75,
      transaction_type: 'payment',
      category: 'miscellaneous',
      merchant_normalized: 'Unknown Payment',
      evidence_text: 'ONLINE PAYMENT -75.00',
    });

    expect(spendingAmount(unknownPayment)).toBe(0);
    expect(transferAmount(unknownPayment)).toBe(0);
  });

  it('keeps internal transfers separate unless the user corrected them to spending', () => {
    const savingsTransfer = transaction({
      amount: -400,
      transaction_type: 'transfer',
      category: 'transfer',
      merchant_normalized: 'Savings Transfer',
      evidence_text: 'ONLINE TRANSFER TO SAVINGS -400.00',
    });
    const rentTransfer = transaction({
      amount: -2100,
      transaction_type: 'transfer',
      category: 'rent',
      merchant_normalized: 'Monthly rent transfer',
      evidence_text: 'MONTHLY RENT TRANSFER -2100.00',
    });

    expect(spendingAmount(savingsTransfer)).toBe(0);
    expect(transferAmount(savingsTransfer)).toBe(400);
    expect(spendingAmount(rentTransfer)).toBe(2100);
    expect(transferAmount(rentTransfer)).toBe(0);
  });
});

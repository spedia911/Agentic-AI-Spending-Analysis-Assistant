import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Anomaly, ReviewItem, Transaction } from '../../types/domain';

const mocks = vi.hoisted(() => ({
  getEnv: vi.fn(),
  initializeSpreadsheet: vi.fn(),
  readRows: vi.fn(),
}));

vi.mock('../env', () => ({
  getEnv: mocks.getEnv,
}));

vi.mock('../google/sheets', () => ({
  initializeSpreadsheet: mocks.initializeSpreadsheet,
  readRows: mocks.readRows,
}));

import { canViewDashboard, loadDashboardData } from './data';

function transaction(id: string, category: string): Transaction {
  return {
    transaction_id: id,
    source_document_id: 'source-1',
    observed_month: '2026-06',
    transaction_date: '2026-06-01',
    merchant_raw: 'Demo',
    merchant_normalized: 'Demo',
    amount: 10,
    transaction_type: 'expense',
    account_label: 'Demo *1234',
    category,
    category_confidence: 0.9,
    extraction_confidence: 0.9,
    validation_status: 'valid',
    review_status: 'none',
    evidence_text: 'Demo evidence',
    created_at: '2026-06-01T00:00:00Z',
    updated_at: '2026-06-01T00:00:00Z',
  };
}

function review(id: string, status: ReviewItem['status']): ReviewItem {
  return {
    review_item_id: id,
    target_type: 'transaction',
    target_id: 'txn-1',
    issue_type: 'low_confidence',
    severity: 'medium',
    question: 'Review this row?',
    suggested_options: ['yes', 'no'],
    status,
    user_answer: null,
    created_at: '2026-06-01T00:00:00Z',
    resolved_at: null,
  };
}

function anomaly(id: string, status: Anomaly['status']): Anomaly {
  return {
    anomaly_id: id,
    anomaly_type: 'spending_spike',
    severity: 'medium',
    month: '2026-06',
    related_record_ids: ['txn-1'],
    summary: 'Demo anomaly',
    suggested_action: 'Review it.',
    status,
    created_at: '2026-06-01T00:00:00Z',
  };
}

describe('dashboard data loading', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getEnv.mockReturnValue({ GOOGLE_SHEET_ID: 'configured-sheet' });
    mocks.initializeSpreadsheet.mockResolvedValue('sheet-123');
    mocks.readRows.mockImplementation(async (_sheetId: string, tabName: string) => {
      if (tabName === 'Transactions') return [transaction('txn-1', 'duplicate_remove_one'), transaction('txn-2', '')];
      if (tabName === 'MonthlySummary') return [{ month: '2026-06', category: 'duplicate_remove_one' }];
      if (tabName === 'QuarterlySummary') return [{ quarter: '2026-Q2', category: '' }];
      if (tabName === 'ReviewQueue') return [review('review-1', 'pending'), review('review-2', 'resolved')];
      if (tabName === 'Anomalies') return [anomaly('anomaly-1', 'open'), anomaly('anomaly-2', 'ignored')];
      return [];
    });
  });

  it('gates dashboard access to the configured single-user email', () => {
    expect(canViewDashboard('User@Example.com', 'user@example.com')).toBe(true);
    expect(canViewDashboard('other@example.com', 'user@example.com')).toBe(false);
    expect(canViewDashboard(undefined, 'user@example.com')).toBe(false);
  });

  it('loads dashboard rows from Sheets and keeps only active review/anomaly work', async () => {
    const data = await loadDashboardData();

    expect(mocks.initializeSpreadsheet).toHaveBeenCalledWith('configured-sheet');
    expect(mocks.readRows).toHaveBeenCalledTimes(10);
    expect(data.sheetId).toBe('sheet-123');
    expect(data.transactions.map((row) => row.category)).toEqual(['miscellaneous', 'miscellaneous']);
    expect(data.monthlySummaries[0].category).toBe('miscellaneous');
    expect(data.quarterlySummaries[0].category).toBe('miscellaneous');
    expect(data.reviewItems.map((row) => row.review_item_id)).toEqual(['review-1']);
    expect(data.anomalies.map((row) => row.anomaly_id)).toEqual(['anomaly-1']);
  });
});

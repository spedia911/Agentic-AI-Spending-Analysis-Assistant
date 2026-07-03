import type { AssetSnapshot, AssetTrend, CashFlowSummary, MonthlySummary, QuarterlySummary, Transaction } from '../../types/domain';
import { spendingAmount, transferAmount } from '../finance/spending';

export interface SummaryResult {
  monthlySummaries: MonthlySummary[];
  quarterlySummaries: QuarterlySummary[];
  cashFlowSummaries: CashFlowSummary[];
  assetTrends: AssetTrend[];
}

function quarterForMonth(month: string): string {
  const monthNumber = Number(month.slice(5, 7));
  const quarter = Math.ceil(monthNumber / 3);
  return month.slice(0, 4) + '-Q' + quarter;
}

function expenseAmount(transaction: Transaction): number {
  return spendingAmount(transaction);
}

function summaryAmount(transaction: Transaction): number {
  if (
    spendingAmount(transaction) > 0 ||
    transaction.transaction_type === 'income' ||
    transaction.transaction_type === 'refund'
  ) {
    return Math.abs(transaction.amount);
  }
  return 0;
}

function incomeAmount(transaction: Transaction): number {
  return transaction.transaction_type === 'income' ? Math.abs(transaction.amount) : 0;
}

function refundAmount(transaction: Transaction): number {
  return transaction.transaction_type === 'refund' ? Math.abs(transaction.amount) : 0;
}

function feeAmount(transaction: Transaction): number {
  return transaction.transaction_type === 'fee' || transaction.category === 'fees' ? Math.abs(transaction.amount) : 0;
}

function unclassifiedPaymentAmount(transaction: Transaction): number {
  if (transaction.transaction_type !== 'payment') return 0;
  if (spendingAmount(transaction) > 0 || transferAmount(transaction) > 0) return 0;
  return Math.abs(transaction.amount);
}

function isUsableTransaction(transaction: Transaction): boolean {
  return transaction.validation_status !== 'rejected' && !!transaction.observed_month && transaction.observed_month !== 'unknown';
}

function previousMonth(month: string): string {
  const year = Number(month.slice(0, 4));
  const monthIndex = Number(month.slice(5, 7)) - 1;
  const date = new Date(Date.UTC(year, monthIndex - 1, 1));
  return date.toISOString().slice(0, 7);
}

function previousQuarter(quarter: string): string {
  const [yearText, quarterText] = quarter.split('-Q');
  const year = Number(yearText);
  const q = Number(quarterText);
  if (q > 1) return year + '-Q' + (q - 1);
  return year - 1 + '-Q4';
}

export function generateMonthlySummaries(transactions: Transaction[]): MonthlySummary[] {
  const grouped = new Map<string, { total: number; count: number; reviewed: number; unresolved: number }>();

  for (const transaction of transactions.filter(isUsableTransaction)) {
    const key = transaction.observed_month + '|' + transaction.category;
    const current = grouped.get(key) ?? { total: 0, count: 0, reviewed: 0, unresolved: 0 };
    current.total += summaryAmount(transaction);
    current.count += 1;
    if (transaction.review_status === 'resolved') current.reviewed += 1;
    if (transaction.review_status === 'pending') current.unresolved += 1;
    grouped.set(key, current);
  }

  const rows = Array.from(grouped.entries()).map(([key, value]) => {
    const [month, category] = key.split('|');
    return {
      month,
      category,
      total_amount: Number(value.total.toFixed(2)),
      transaction_count: value.count,
      reviewed_count: value.reviewed,
      unresolved_count: value.unresolved,
      month_over_month_delta: null,
      completeness_status: value.unresolved > 0 ? 'partial' : 'unknown',
    } satisfies MonthlySummary;
  });

  const totalsByKey = new Map(rows.map((row) => [row.month + '|' + row.category, row.total_amount]));
  return rows
    .map((row) => {
      const prior = totalsByKey.get(previousMonth(row.month) + '|' + row.category);
      return {
        ...row,
        month_over_month_delta: prior === undefined ? null : Number((row.total_amount - prior).toFixed(2)),
      };
    })
    .sort((a, b) => (a.month + a.category).localeCompare(b.month + b.category));
}

export function generateQuarterlySummaries(monthlySummaries: MonthlySummary[]): QuarterlySummary[] {
  const grouped = new Map<string, { total: number; count: number; partial: boolean }>();

  for (const row of monthlySummaries) {
    const quarter = quarterForMonth(row.month);
    const key = quarter + '|' + row.category;
    const current = grouped.get(key) ?? { total: 0, count: 0, partial: false };
    current.total += row.total_amount;
    current.count += row.transaction_count;
    current.partial = current.partial || row.completeness_status !== 'complete';
    grouped.set(key, current);
  }

  const rows = Array.from(grouped.entries()).map(([key, value]) => {
    const [quarter, category] = key.split('|');
    return {
      quarter,
      category,
      total_amount: Number(value.total.toFixed(2)),
      transaction_count: value.count,
      quarter_over_quarter_delta: null,
      completeness_status: value.partial ? 'partial' : 'complete',
    } satisfies QuarterlySummary;
  });

  const totalsByKey = new Map(rows.map((row) => [row.quarter + '|' + row.category, row.total_amount]));
  return rows
    .map((row) => {
      const prior = totalsByKey.get(previousQuarter(row.quarter) + '|' + row.category);
      return {
        ...row,
        quarter_over_quarter_delta: prior === undefined ? null : Number((row.total_amount - prior).toFixed(2)),
      };
    })
    .sort((a, b) => (a.quarter + a.category).localeCompare(b.quarter + b.category));
}

export function generateCashFlowSummaries(transactions: Transaction[]): CashFlowSummary[] {
  const grouped = new Map<string, Omit<CashFlowSummary, 'net_cash_flow' | 'completeness_status'>>();

  for (const transaction of transactions.filter(isUsableTransaction)) {
    const month = transaction.observed_month;
    const current = grouped.get(month) ?? {
      month,
      spending_total: 0,
      income_total: 0,
      refund_total: 0,
      transfer_total: 0,
      payment_total: 0,
      fee_total: 0,
      transaction_count: 0,
      unresolved_count: 0,
    };

    current.spending_total += spendingAmount(transaction);
    current.income_total += incomeAmount(transaction);
    current.refund_total += refundAmount(transaction);
    current.transfer_total += transferAmount(transaction);
    current.payment_total += unclassifiedPaymentAmount(transaction);
    current.fee_total += feeAmount(transaction);
    current.transaction_count += 1;
    if (transaction.review_status === 'pending' || transaction.validation_status === 'needs_review') current.unresolved_count += 1;
    grouped.set(month, current);
  }

  return Array.from(grouped.values())
    .map((row) => ({
      ...row,
      spending_total: Number(row.spending_total.toFixed(2)),
      income_total: Number(row.income_total.toFixed(2)),
      refund_total: Number(row.refund_total.toFixed(2)),
      transfer_total: Number(row.transfer_total.toFixed(2)),
      payment_total: Number(row.payment_total.toFixed(2)),
      fee_total: Number(row.fee_total.toFixed(2)),
      net_cash_flow: Number((row.income_total + row.refund_total - row.spending_total).toFixed(2)),
      completeness_status: row.unresolved_count > 0 ? 'partial' : 'unknown',
    }) satisfies CashFlowSummary)
    .sort((a, b) => a.month.localeCompare(b.month));
}

export function generateAssetTrends(assetSnapshots: AssetSnapshot[], transactions: Transaction[]): AssetTrend[] {
  const latestByAccountMonth = new Map<string, AssetSnapshot>();

  for (const snapshot of assetSnapshots) {
    if (!snapshot.observed_month || snapshot.observed_month === 'unknown') continue;
    const key = snapshot.account_label + '|' + snapshot.observed_month;
    const current = latestByAccountMonth.get(key);
    if (!current || snapshot.observed_date >= current.observed_date) {
      latestByAccountMonth.set(key, snapshot);
    }
  }

  const monthlySpending = new Map<string, number>();
  for (const transaction of transactions.filter(isUsableTransaction)) {
    monthlySpending.set(
      transaction.observed_month,
      (monthlySpending.get(transaction.observed_month) ?? 0) + expenseAmount(transaction)
    );
  }

  const snapshots = Array.from(latestByAccountMonth.values()).sort((a, b) =>
    (a.account_label + a.observed_month).localeCompare(b.account_label + b.observed_month)
  );
  const priorByAccount = new Map<string, AssetSnapshot>();

  return snapshots.map((snapshot) => {
    const prior = priorByAccount.get(snapshot.account_label);
    priorByAccount.set(snapshot.account_label, snapshot);
    const monthlyChange = prior ? Number((snapshot.balance - prior.balance).toFixed(2)) : 0;
    const spending = Number((monthlySpending.get(snapshot.observed_month) ?? 0).toFixed(2));
    const flag: AssetTrend['maintainability_flag'] = !prior
      ? 'unknown'
      : spending > 0 && monthlyChange < 0
        ? spending > Math.abs(monthlyChange) * 2
          ? 'concern'
          : 'watch'
        : 'ok';

    return {
      month: snapshot.observed_month,
      account_label: snapshot.account_label,
      ending_balance: snapshot.balance,
      prior_month_balance: prior ? prior.balance : null,
      monthly_change: monthlyChange,
      related_spending_total: spending,
      maintainability_flag: flag,
    } satisfies AssetTrend;
  });
}

export function generateSummaries(transactions: Transaction[], assetSnapshots: AssetSnapshot[]): SummaryResult {
  const monthlySummaries = generateMonthlySummaries(transactions);
  return {
    monthlySummaries,
    quarterlySummaries: generateQuarterlySummaries(monthlySummaries),
    cashFlowSummaries: generateCashFlowSummaries(transactions),
    assetTrends: generateAssetTrends(assetSnapshots, transactions),
  };
}

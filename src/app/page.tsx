import { getEnv } from '../lib/env';
import { canViewDashboard, loadDashboardData } from '../lib/dashboard';
import DashboardActions from './dashboard-actions';
import SpendingExplorer, { type SpendingExplorerRow } from './spending-explorer';
import styles from './page.module.css';
import type { Transaction } from '../types/domain';
import { spendingAmount, transferAmount } from '../lib/finance/spending';

export const dynamic = 'force-dynamic';

function currency(value: number | null | undefined) {
  if (value === null || value === undefined) return '-';
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function chartWidth(value: number, max: number) {
  if (max <= 0) return '0%';
  return Math.max(6, Math.round((Math.abs(value) / max) * 100)) + '%';
}

function moneyIn(transaction: Transaction) {
  if (transaction.transaction_type !== 'income' && transaction.transaction_type !== 'refund') return 0;
  return Math.abs(transaction.amount);
}

function moneyOut(transaction: Transaction) {
  return spendingAmount(transaction);
}

function safeText(value: string | null | undefined, fallback = 'unknown') {
  return value && value.trim() ? value : fallback;
}

function statusCounts(values: Array<string | null | undefined>): Array<{ label: string; total: number }> {
  const counts = new Map<string, number>();
  for (const value of values) {
    const label = safeText(value);
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return Array.from(counts.entries()).map(([label, total]) => ({ label, total }));
}

export default async function Home({ searchParams }: { searchParams?: Promise<{ email?: string }> }) {
  const env = getEnv();
  const params = await searchParams;
  const email = params?.email;

  if (!canViewDashboard(email, env.SINGLE_USER_EMAIL)) {
    return (
      <main className={styles.pageShell}>
        <section className={styles.accessPanel}>
          <h1>Spending Analysis</h1>
          <p>Enter the configured user email as a query parameter to view the dashboard.</p>
          <code>?email={env.SINGLE_USER_EMAIL}</code>
        </section>
      </main>
    );
  }

  let data;
  try {
    data = await loadDashboardData();
  } catch (error) {
    return (
      <main className={styles.pageShell}>
        <section className={styles.accessPanel}>
          <p className={styles.eyebrow}>Dashboard unavailable</p>
          <h1>Spending Analysis</h1>
          <p>Unable to read the configured Google Sheet. Check the environment settings and Google access, then refresh the page.</p>
          <code>{error instanceof Error ? error.message : 'Unknown dashboard error'}</code>
        </section>
      </main>
    );
  }

  const latestMonths = [...data.monthlySummaries].sort((a, b) => safeText(b.month, '').localeCompare(safeText(a.month, ''))).slice(0, 8);
  const latestQuarters = [...data.quarterlySummaries].sort((a, b) => safeText(b.quarter, '').localeCompare(safeText(a.quarter, ''))).slice(0, 8);
  const latestAssets = [...data.assetTrends].sort((a, b) => safeText(b.month, '').localeCompare(safeText(a.month, ''))).slice(0, 8);
  const latestRun = [...data.runs].sort((a, b) => safeText(b.started_at, '').localeCompare(safeText(a.started_at, '')))[0];
  const latestMonth =
    [...data.transactions.map((transaction) => transaction.observed_month), ...data.monthlySummaries.map((row) => row.month)]
      .filter((month) => month && month !== 'unknown')
      .sort()
      .at(-1) ?? latestMonths[0]?.month;
  const currentTransactions = latestMonth
    ? data.transactions.filter((transaction) => transaction.observed_month === latestMonth && transaction.validation_status !== 'rejected')
    : [];
  const currentMonthSpend = Number(currentTransactions.reduce((sum, transaction) => sum + moneyOut(transaction), 0).toFixed(2));
  const currentMonthIncome = Number(currentTransactions.reduce((sum, transaction) => sum + moneyIn(transaction), 0).toFixed(2));
  const currentMonthTransfers = Number(currentTransactions.reduce((sum, transaction) => sum + transferAmount(transaction), 0).toFixed(2));
  const netCashFlow = Number((currentMonthIncome - currentMonthSpend).toFixed(2));
  const sourceStatusRows = statusCounts(data.sourceDocuments.map((source) => source.status));

  const concernCount = data.assetTrends.filter((row) => row.maintainability_flag === 'concern').length;
  const spendingRows: SpendingExplorerRow[] = data.transactions
    .filter((transaction) => transaction.validation_status !== 'rejected' && spendingAmount(transaction) > 0)
    .map((transaction) => ({
      transaction_id: transaction.transaction_id,
      observed_month: transaction.observed_month,
      transaction_date: transaction.transaction_date,
      merchant_normalized: transaction.merchant_normalized,
      amount: transaction.amount,
      spending_amount: spendingAmount(transaction),
      transaction_type: transaction.transaction_type,
      account_label: transaction.account_label,
      category: transaction.category,
      evidence_text: transaction.evidence_text,
    }));
  const monthlyChartRows = Array.from(
    data.transactions.reduce((map, transaction) => {
      if (transaction.validation_status === 'rejected' || !transaction.observed_month || transaction.observed_month === 'unknown') return map;
      return map.set(transaction.observed_month, (map.get(transaction.observed_month) ?? 0) + moneyOut(transaction));
    }, new Map<string, number>())
  )
    .map(([label, total]) => ({ label, total: Number(total.toFixed(2)) }))
    .sort((a, b) => a.label.localeCompare(b.label))
    .slice(-6);
  const quarterlyChartRows = Array.from(
    data.transactions.reduce((map, transaction) => {
      if (transaction.validation_status === 'rejected' || !transaction.observed_month || !/^\d{4}-\d{2}$/.test(transaction.observed_month)) return map;
      const month = Number(transaction.observed_month.slice(5, 7));
      const quarter = transaction.observed_month.slice(0, 4) + '-Q' + Math.ceil(month / 3);
      return map.set(quarter, (map.get(quarter) ?? 0) + moneyOut(transaction));
    }, new Map<string, number>())
  )
    .map(([label, total]) => ({ label, total: Number(total.toFixed(2)) }))
    .sort((a, b) => a.label.localeCompare(b.label))
    .slice(-6);
  const assetChartRows = [...data.assetTrends]
    .sort((a, b) => (a.account_label + a.month).localeCompare(b.account_label + b.month))
    .slice(-6)
    .map((row) => ({ label: row.month + ' ' + row.account_label, total: row.ending_balance, change: row.monthly_change, flag: row.maintainability_flag }));
  const maxMonthly = Math.max(0, ...monthlyChartRows.map((row) => row.total));
  const maxQuarterly = Math.max(0, ...quarterlyChartRows.map((row) => row.total));
  const maxAsset = Math.max(0, ...assetChartRows.map((row) => row.total));

  return (
    <main className={styles.pageShell}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>Single-user finance assistant</p>
          <h1>Spending Analysis</h1>
        </div>
        <div className={styles.sheetId}>Sheet {data.sheetId}</div>
      </header>

      <DashboardActions
        importHref={'/import?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL)}
        pendingReviews={data.reviewItems}
        reviewHref={'/review?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL)}
      />

      <section className={styles.metrics}>
        <div className={styles.metric}>
          <span>{latestMonth ?? 'Current'} Spend</span>
          <strong>{currency(currentMonthSpend)}</strong>
        </div>
        <div className={styles.metric}>
          <span>{latestMonth ?? 'Current'} Income</span>
          <strong>{currency(currentMonthIncome)}</strong>
        </div>
        <div className={styles.metric}>
          <span>Net Cash Flow</span>
          <strong>{currency(netCashFlow)}</strong>
        </div>
        <div className={styles.metric}>
          <span>Transfers/Card Payments</span>
          <strong>{currency(currentMonthTransfers)}</strong>
        </div>
      </section>

      <section className={styles.metrics}>
        <div className={styles.metric}>
          <span>Spending Rows</span>
          <strong>{spendingRows.length}</strong>
        </div>
        <div className={styles.metric}>
          <span>Processed Files</span>
          <strong>{latestRun ? latestRun.files_processed : 0}</strong>
        </div>
        <div className={styles.metric}>
          <span>Asset Concerns</span>
          <strong>{concernCount}</strong>
        </div>
        <div className={styles.metric}>
          <span>Source Statuses</span>
          <strong>{sourceStatusRows.length}</strong>
        </div>
      </section>

      <section className={styles.panel}>
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Run and source health</p>
            <h2>Latest processing status</h2>
          </div>
          <span>{latestRun ? latestRun.status : 'No runs yet'}</span>
        </div>
        <div className={styles.statusGrid}>
          <div>
            <strong>{latestRun ? latestRun.files_seen : 0}</strong>
            <span>Files seen</span>
          </div>
          <div>
            <strong>{latestRun ? latestRun.files_processed : 0}</strong>
            <span>Files processed</span>
          </div>
          <div>
            <strong>{latestRun ? latestRun.transactions_created : data.transactions.length}</strong>
            <span>Transactions</span>
          </div>
          <div>
            <strong>{latestRun ? latestRun.review_items_created : data.reviewItems.length}</strong>
            <span>Rows flagged</span>
          </div>
        </div>
        <div className={styles.statusPills}>
          {sourceStatusRows.length === 0 ? <span>No source files registered yet.</span> : sourceStatusRows.map((row) => (
            <span key={row.label}>{row.label}: {row.total}</span>
          ))}
        </div>
        {latestRun?.error_summary ? <p className={styles.mutedText}>{latestRun.error_summary}</p> : null}
      </section>

      <SpendingExplorer defaultMonth={latestMonth} rows={spendingRows} />

      <section className={styles.gridTwo}>
        <div className={styles.panel}>
          <h2>Monthly Spending</h2>
          <div className={styles.chartStack} aria-label="Monthly spending chart">
            {monthlyChartRows.length === 0 ? <p>No monthly chart data yet.</p> : monthlyChartRows.map((row) => (
              <div className={styles.chartRow} key={row.label}>
                <span>{row.label}</span>
                <div className={styles.barTrack}><div className={styles.barFill} style={{ width: chartWidth(row.total, maxMonthly) }} /></div>
                <strong>{currency(row.total)}</strong>
              </div>
            ))}
          </div>
        </div>

        <div className={styles.panel}>
          <h2>Quarterly Spending</h2>
          <div className={styles.chartStack} aria-label="Quarterly spending chart">
            {quarterlyChartRows.length === 0 ? <p>No quarterly chart data yet.</p> : quarterlyChartRows.map((row) => (
              <div className={styles.chartRow} key={row.label}>
                <span>{row.label}</span>
                <div className={styles.barTrack}><div className={styles.barFillAlt} style={{ width: chartWidth(row.total, maxQuarterly) }} /></div>
                <strong>{currency(row.total)}</strong>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className={styles.panel}>
        <h2>Asset Trend Chart</h2>
        <div className={styles.chartStack} aria-label="Asset balance chart">
          {assetChartRows.length === 0 ? <p>No asset chart data yet.</p> : assetChartRows.map((row) => (
            <div className={styles.chartRow} key={row.label}>
              <span>{row.label}</span>
              <div className={styles.barTrack}><div className={row.flag === 'concern' ? styles.barFillConcern : styles.barFillAsset} style={{ width: chartWidth(row.total, maxAsset) }} /></div>
              <strong>{currency(row.total)} ({currency(row.change)})</strong>
            </div>
          ))}
        </div>
      </section>

      <section className={styles.gridTwo}>
        <div className={styles.panel}>
          <h2>Quarterly Trends</h2>
          <table className={styles.dataTable}>
            <thead><tr><th>Quarter</th><th>Category</th><th>Total</th><th>Delta</th></tr></thead>
            <tbody>
              {latestQuarters.length === 0 ? <tr><td colSpan={4}>No quarterly summaries yet.</td></tr> : latestQuarters.map((row) => (
                <tr key={row.quarter + row.category}>
                  <td>{row.quarter}</td><td>{row.category}</td><td>{currency(row.total_amount)}</td><td>{currency(row.quarter_over_quarter_delta)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className={styles.panel}>
          <h2>Asset Trends</h2>
          <table className={styles.dataTable}>
            <thead><tr><th>Month</th><th>Account</th><th>Ending</th><th>Change</th><th>Spending</th><th>Flag</th></tr></thead>
            <tbody>
              {latestAssets.length === 0 ? <tr><td colSpan={6}>No asset snapshots yet.</td></tr> : latestAssets.map((row) => (
                <tr key={row.month + row.account_label}>
                  <td>{row.month}</td><td>{row.account_label}</td><td>{currency(row.ending_balance)}</td><td>{currency(row.monthly_change)}</td><td>{currency(row.related_spending_total)}</td><td>{row.maintainability_flag}</td>
                </tr>
            ))}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}

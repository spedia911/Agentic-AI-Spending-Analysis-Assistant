import Link from 'next/link';
import { getEnv } from '../lib/env';
import { buildDashboardInsights, canViewDashboard, loadDashboardData } from '../lib/dashboard';
import { safeErrorDetail } from '../lib/privacy/redact';
import AnomalyCenter from './anomaly-center';
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
          <code>?email=your_configured_email@example.com</code>
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
          <code>{safeErrorDetail(error, 'Unknown dashboard error')}</code>
        </section>
      </main>
    );
  }

  const latestMonths = [...data.monthlySummaries].sort((a, b) => safeText(b.month, '').localeCompare(safeText(a.month, ''))).slice(0, 8);
  const latestQuarters = [...data.quarterlySummaries].sort((a, b) => safeText(b.quarter, '').localeCompare(safeText(a.quarter, ''))).slice(0, 8);
  const latestCashFlow = [...data.cashFlowSummaries].sort((a, b) => safeText(b.month, '').localeCompare(safeText(a.month, ''))).slice(0, 8);
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
  const currentMonthUnresolved = Number(
    currentTransactions
      .filter((transaction) => transaction.review_status === 'pending' || transaction.validation_status === 'needs_review')
      .reduce((sum, transaction) => sum + Math.abs(transaction.amount), 0)
      .toFixed(2)
  );
  const netCashFlow = Number((currentMonthIncome - currentMonthSpend).toFixed(2));
  const sourceStatusRows = statusCounts(data.sourceDocuments.map((source) => source.status));
  const latestSources = [...data.sourceDocuments]
    .sort((a, b) =>
      safeText(b.processed_at ?? b.modified_time ?? b.created_time, '').localeCompare(safeText(a.processed_at ?? a.modified_time ?? a.created_time, ''))
    )
    .slice(0, 8);
  const insights = buildDashboardInsights(data, env.SINGLE_USER_EMAIL);

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
          <p className={styles.eyebrow}>Private finance review</p>
          <h1>Agentic Spending Dashboard</h1>
          <p className={styles.headerLead}>
            Screenshot-derived transactions, cash flow, anomalies, and source evidence from Google Sheets.
          </p>
        </div>
        <div className={styles.sheetId}>Sheets-backed results</div>
      </header>

      <section className={styles.safetyNotice}>
        <strong>Review-only assistant</strong>
        <p>
          This dashboard helps reconcile screenshots against Sheets. It is not financial advice, does not initiate payments, and does not move money.
          Verify source evidence before relying on a correction or anomaly decision.
        </p>
      </section>

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
          <span>Unresolved Amount</span>
          <strong>{currency(currentMonthUnresolved)}</strong>
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
          <span>Open Anomalies</span>
          <strong>{data.anomalies.length}</strong>
        </div>
      </section>

      <section className={styles.panel} id="next-best-actions">
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Action-oriented summary</p>
            <h2>Next best actions</h2>
          </div>
          <span>{insights.length} signals</span>
        </div>
        <div className={styles.insightList}>
          {insights.map((insight) => (
            <article className={styles.insightItem} data-priority={insight.priority} key={insight.insight_id}>
              <div>
                <span>{insight.priority}</span>
                <h3>{insight.title}</h3>
                <p>{insight.detail}</p>
              </div>
              <Link className={styles.secondaryLink} href={insight.action_href}>
                {insight.action_label}
              </Link>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.panel} id="source-file-audit">
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

      <AnomalyCenter
        anomalies={data.anomalies}
        assetTrends={data.assetTrends}
        sourceDocuments={data.sourceDocuments}
        transactions={data.transactions}
        userEmail={env.SINGLE_USER_EMAIL}
      />

      <section className={styles.panel}>
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Source file audit</p>
            <h2>Recent Drive files</h2>
            <p className={styles.mutedText}>The workflow analyzes files in the configured Drive folder. Keep only the screenshots you want reviewed in that folder.</p>
          </div>
          <span>{data.sourceDocuments.length} tracked</span>
        </div>
        <table className={styles.dataTable}>
          <thead><tr><th>File</th><th>Status</th><th>Processed</th><th>Modified</th><th>Message</th></tr></thead>
          <tbody>
            {latestSources.length === 0 ? <tr><td colSpan={5}>No source files registered yet.</td></tr> : latestSources.map((source) => (
              <tr key={source.source_document_id}>
                <td>
                  <Link className={styles.tableLink} href={'/source/' + encodeURIComponent(source.source_document_id) + '?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL)}>
                    {source.file_name}
                  </Link>
                </td>
                <td>{source.status}</td>
                <td>{safeText(source.processed_at, '-')}</td>
                <td>{safeText(source.modified_time, '-')}</td>
                <td>{safeText(source.error_summary, '-')}</td>
              </tr>
            ))}
          </tbody>
        </table>
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

      <section className={styles.panel} id="asset-trends">
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Generated cash-flow output</p>
            <h2>Monthly money movement</h2>
          </div>
          <span>{latestCashFlow.length} months</span>
        </div>
        <table className={styles.dataTable}>
          <thead><tr><th>Month</th><th>Spending</th><th>Income</th><th>Refunds</th><th>Transfers/Card Payments</th><th>Other Payments</th><th>Fees</th><th>Net</th><th>Status</th></tr></thead>
          <tbody>
            {latestCashFlow.length === 0 ? <tr><td colSpan={9}>No cash-flow summary rows yet. Refresh summaries after processing transactions.</td></tr> : latestCashFlow.map((row) => (
              <tr key={row.month}>
                <td>{row.month}</td>
                <td>{currency(row.spending_total)}</td>
                <td>{currency(row.income_total)}</td>
                <td>{currency(row.refund_total)}</td>
                <td>{currency(row.transfer_total)}</td>
                <td>{currency(row.payment_total)}</td>
                <td>{currency(row.fee_total)}</td>
                <td>{currency(row.net_cash_flow)}</td>
                <td>{row.completeness_status}</td>
              </tr>
            ))}
          </tbody>
        </table>
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

      <DashboardActions
        importHref={'/import?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL)}
        pendingReviews={data.reviewItems}
        reviewHref={'/review?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL)}
      />
    </main>
  );
}

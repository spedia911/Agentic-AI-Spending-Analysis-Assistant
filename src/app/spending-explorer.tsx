'use client';

import { useMemo, useState } from 'react';
import styles from './page.module.css';

export interface SpendingExplorerRow {
  transaction_id: string;
  observed_month: string;
  transaction_date: string;
  merchant_normalized: string;
  amount: number;
  spending_amount: number;
  transaction_type: string;
  account_label: string;
  category: string;
  evidence_text: string;
}

interface SpendingExplorerProps {
  defaultMonth?: string;
  rows: SpendingExplorerRow[];
}

const PIE_COLORS = ['#2f6f5e', '#2563eb', '#b42318', '#7a5af8', '#b54708', '#027a48', '#344054', '#0e7490', '#a15c07', '#6941c6'];
const CATEGORY_OPTIONS = ['groceries', 'dining', 'utilities', 'transportation', 'rent', 'subscriptions', 'shopping', 'healthcare', 'transfer', 'income', 'fees', 'miscellaneous'];

function money(value: number) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function safeText(value: string | null | undefined, fallback = 'unknown') {
  return value && value.trim() ? value : fallback;
}

export default function SpendingExplorer({ defaultMonth, rows }: SpendingExplorerProps) {
  const [localRows, setLocalRows] = useState(rows);
  const [busyTransactionId, setBusyTransactionId] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const months = useMemo(() => Array.from(new Set(localRows.map((row) => safeText(row.observed_month)))).sort().reverse(), [localRows]);
  const [month, setMonth] = useState(defaultMonth && months.includes(defaultMonth) ? defaultMonth : months[0] ?? 'all');
  const [category, setCategory] = useState('all');

  const monthRows = useMemo(
    () => localRows.filter((row) => month === 'all' || row.observed_month === month),
    [month, localRows]
  );

  const categoryRows = useMemo(() => {
    const totals = new Map<string, { category: string; total: number; count: number }>();
    for (const row of monthRows) {
      const key = safeText(row.category, 'miscellaneous');
      const current = totals.get(key) ?? { category: key, total: 0, count: 0 };
      current.total += row.spending_amount;
      current.count += 1;
      totals.set(key, current);
    }
    return Array.from(totals.values())
      .map((row) => ({ ...row, total: Number(row.total.toFixed(2)) }))
      .sort((a, b) => b.total - a.total);
  }, [monthRows]);

  const categories = useMemo(() => categoryRows.map((row) => row.category), [categoryRows]);
  const correctionCategories = useMemo(
    () => Array.from(new Set([...CATEGORY_OPTIONS, ...localRows.map((row) => safeText(row.category, 'miscellaneous'))])).sort(),
    [localRows]
  );
  const filteredRows = useMemo(
    () => monthRows
      .filter((row) => category === 'all' || row.category === category)
      .sort((a, b) => safeText(b.transaction_date, '').localeCompare(safeText(a.transaction_date, ''))),
    [category, monthRows]
  );
  const total = Number(categoryRows.reduce((sum, row) => sum + row.total, 0).toFixed(2));
  const pieGradient = categoryRows.length === 0
    ? '#eef2f6'
    : categoryRows.reduce<{ cursor: number; parts: string[] }>((state, row, index) => {
      const start = state.cursor;
      const size = total > 0 ? (row.total / total) * 100 : 0;
      const end = start + size;
      const color = PIE_COLORS[index % PIE_COLORS.length];
      state.parts.push(color + ' ' + start.toFixed(2) + '% ' + end.toFixed(2) + '%');
      state.cursor = end;
      return state;
    }, { cursor: 0, parts: [] }).parts.join(', ');

  async function applyCategory(row: SpendingExplorerRow, newCategory: string) {
    setBusyTransactionId(row.transaction_id);
    setMessage('Updating category...');
    try {
      const response = await fetch('/api/corrections/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          corrections: [{ transactionId: row.transaction_id, fieldName: 'category', newValue: newCategory }],
        }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Category update failed.');
      setLocalRows((current) => current.map((item) => item.transaction_id === row.transaction_id ? { ...item, category: newCategory } : item));
      setMessage('Category updated. Summaries refreshed.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Category update failed.');
    } finally {
      setBusyTransactionId(null);
    }
  }

  async function removeTransaction(row: SpendingExplorerRow) {
    setBusyTransactionId(row.transaction_id);
    setMessage('Removing transaction from spending analysis...');
    try {
      const response = await fetch('/api/corrections/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          corrections: [{ transactionId: row.transaction_id, fieldName: 'validation_status', newValue: 'rejected' }],
        }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Remove failed.');
      setLocalRows((current) => current.filter((item) => item.transaction_id !== row.transaction_id));
      setMessage('Transaction removed from spending analysis. Summaries refreshed.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Remove failed.');
    } finally {
      setBusyTransactionId(null);
    }
  }

  return (
    <section className={styles.panel} id="spending-explorer">
      <div className={styles.sectionHeader}>
        <div>
          <p className={styles.eyebrow}>Spending explorer</p>
          <h2>Monthly categories and transactions</h2>
        </div>
        <span>{money(total)}</span>
      </div>

      <div className={styles.explorerFilters}>
        <label>
          Month
          <select value={month} onChange={(event) => {
            setMonth(event.target.value);
            setCategory('all');
          }}>
            <option value="all">All months</option>
            {months.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </label>
        <label>
          Category
          <select value={category} onChange={(event) => setCategory(event.target.value)}>
            <option value="all">All categories</option>
            {categories.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </label>
      </div>
      {message ? <p className={styles.statusMessage}>{message}</p> : null}

      <div className={styles.explorerGrid}>
        <div className={styles.pieWrap}>
          <div
            aria-label="Monthly spending by category"
            className={styles.pieChart}
            style={{ background: categoryRows.length === 0 ? '#eef2f6' : 'conic-gradient(' + pieGradient + ')' }}
          >
            <span>{money(total)}</span>
          </div>
        </div>
        <div className={styles.categoryLegend}>
          {categoryRows.length === 0 ? <p className={styles.mutedText}>No spending rows for this filter.</p> : categoryRows.map((row, index) => (
            <button
              className={category === row.category ? styles.activeLegendItem : ''}
              key={row.category}
              onClick={() => setCategory(category === row.category ? 'all' : row.category)}
              type="button"
            >
              <i style={{ background: PIE_COLORS[index % PIE_COLORS.length] }} />
              <span>{row.category}</span>
              <strong>{money(row.total)}</strong>
              <small>{row.count} rows</small>
            </button>
          ))}
        </div>
      </div>

      <h3 className={styles.tableHeading}>Spending summary</h3>
      <table className={styles.dataTable}>
        <thead><tr><th>Month</th><th>Category</th><th>Total</th><th>Rows</th></tr></thead>
        <tbody>
          {categoryRows.length === 0 ? <tr><td colSpan={4}>No category totals for this filter.</td></tr> : categoryRows.map((row) => (
            <tr key={row.category}>
              <td>{month === 'all' ? 'All' : month}</td>
              <td>{row.category}</td>
              <td>{money(row.total)}</td>
              <td>{row.count}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <h3 className={styles.tableHeading}>Transactions</h3>
      <table className={styles.dataTable}>
        <thead><tr><th>Date</th><th>Month</th><th>Category</th><th>Merchant</th><th>Account</th><th>Amount</th><th>Actions</th></tr></thead>
        <tbody>
          {filteredRows.length === 0 ? <tr><td colSpan={7}>No spending transactions for this filter.</td></tr> : filteredRows.map((row) => (
            <tr key={row.transaction_id}>
              <td>{safeText(row.transaction_date, 'missing date')}</td>
              <td>{safeText(row.observed_month)}</td>
              <td>
                <select
                  className={styles.tableInput}
                  disabled={busyTransactionId === row.transaction_id}
                  value={safeText(row.category, 'miscellaneous')}
                  onChange={(event) => applyCategory(row, event.target.value)}
                >
                  {correctionCategories.map((item) => <option key={item} value={item}>{item}</option>)}
                </select>
              </td>
              <td>{safeText(row.merchant_normalized, 'Unknown merchant')}</td>
              <td>{safeText(row.account_label, 'Unknown account')}</td>
              <td>{money(row.spending_amount)}</td>
              <td>
                <button
                  className={styles.tableActionButton}
                  disabled={busyTransactionId === row.transaction_id}
                  onClick={() => removeTransaction(row)}
                  type="button"
                >
                  {busyTransactionId === row.transaction_id ? 'Working...' : 'Remove'}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

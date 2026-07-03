'use client';

import { useMemo, useState } from 'react';
import styles from '../page.module.css';
import type { SnapshotReviewStage } from '../../lib/staging/snapshot-review';
import type { Transaction } from '../../types/domain';

interface ImportReviewClientProps {
  initialStage: SnapshotReviewStage | null;
}

const CATEGORIES = ['groceries', 'dining', 'utilities', 'transportation', 'rent', 'subscriptions', 'shopping', 'healthcare', 'transfer', 'income', 'fees', 'miscellaneous'];
const TYPES: Transaction['transaction_type'][] = ['expense', 'income', 'transfer', 'payment', 'fee', 'refund', 'unknown'];
type StagedSnapshot = SnapshotReviewStage['snapshots'][number];

function money(value: number) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function allTransactions(stage: SnapshotReviewStage | null) {
  return stage?.snapshots.flatMap((snapshot) => snapshot.transactions.map((transaction) => ({ ...transaction, file_name: snapshot.source.file_name }))) ?? [];
}

export default function ImportReviewClient({ initialStage }: ImportReviewClientProps) {
  const [stage, setStage] = useState<SnapshotReviewStage | null>(initialStage);
  const [drafts, setDrafts] = useState<Record<string, Partial<Transaction>>>({});
  const [snapshotDrafts, setSnapshotDrafts] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState<'import' | 'save' | 'commit' | null>(null);
  const [message, setMessage] = useState('');
  const rows = useMemo(() => allTransactions(stage), [stage]);
  const selectedSnapshots = useMemo(
    () => stage?.snapshots.filter((snapshot) => snapshotDrafts[snapshot.source.source_document_id] ?? snapshot.selected !== false) ?? [],
    [snapshotDrafts, stage]
  );
  const selectedRows = useMemo(() => selectedSnapshots.reduce((total, snapshot) => total + snapshot.transactions.length, 0), [selectedSnapshots]);
  const hasPendingStageChanges = Object.keys(drafts).length > 0 || Object.keys(snapshotDrafts).length > 0;
  const categoryOptions = useMemo(() => {
    const stagedCategories = rows.map((row) => String(drafts[row.transaction_id]?.category ?? row.category ?? '')).filter(Boolean);
    return Array.from(new Set([...CATEGORIES, ...stagedCategories])).sort();
  }, [drafts, rows]);

  function valueFor<T extends keyof Transaction>(transaction: Transaction, field: T): Transaction[T] {
    return (drafts[transaction.transaction_id]?.[field] as Transaction[T] | undefined) ?? transaction[field];
  }

  function updateDraft(transactionId: string, patch: Partial<Transaction>) {
    setDrafts((current) => ({
      ...current,
      [transactionId]: { ...current[transactionId], ...patch },
    }));
  }

  function isSnapshotSelected(snapshot: StagedSnapshot) {
    return snapshotDrafts[snapshot.source.source_document_id] ?? snapshot.selected !== false;
  }

  function updateSnapshotSelection(sourceDocumentId: string, selected: boolean) {
    setSnapshotDrafts((current) => ({
      ...current,
      [sourceDocumentId]: selected,
    }));
  }

  async function importSnapshots() {
    setBusy('import');
    setMessage('Importing snapshots from Drive. This may take a moment...');
    try {
      const response = await fetch('/api/staging/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ maxFiles: 5 }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Import failed.');
      setStage(body.stage);
      setDrafts({});
      setSnapshotDrafts({});
      setMessage('Imported ' + (body.stage?.snapshots?.length ?? 0) + ' snapshot(s). Review before committing.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Import failed.');
    } finally {
      setBusy(null);
    }
  }

  async function saveDrafts(): Promise<boolean> {
    if (!stage) return false;
    setBusy('save');
    setMessage('Saving staged corrections...');
    try {
      const response = await fetch('/api/staging/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          stageId: stage.stageId,
          snapshots: Object.entries(snapshotDrafts).map(([source_document_id, selected]) => ({ source_document_id, selected })),
          transactions: Object.entries(drafts).map(([transaction_id, draft]) => ({ transaction_id, ...draft })),
        }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Save failed.');
      setStage(body.stage);
      setDrafts({});
      setSnapshotDrafts({});
      setMessage('Saved staged corrections. Nothing has been written to Google Sheets yet.');
      return true;
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Save failed.');
      return false;
    } finally {
      setBusy(null);
    }
  }

  async function commitToSheet() {
    if (!stage) return;
    if (selectedSnapshots.length === 0) {
      setMessage('Select at least one snapshot before committing to Google Sheets.');
      return;
    }
    setBusy('commit');
    setMessage('Committing reviewed rows to Google Sheets...');
    try {
      if (hasPendingStageChanges) {
        const saved = await saveDrafts();
        if (!saved) return;
        setBusy('commit');
        setMessage('Committing reviewed rows to Google Sheets...');
      }
      const response = await fetch('/api/staging/commit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ stageId: stage.stageId }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Commit failed.');
      setStage(null);
      setDrafts({});
      setSnapshotDrafts({});
      setMessage('Committed ' + body.transactionsWritten + ' transactions from ' + selectedSnapshots.length + ' snapshot(s) to Google Sheets and refreshed summaries.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Commit failed.');
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <section className={styles.actionCenter}>
        <div>
          <p className={styles.eyebrow}>Import and review</p>
          <h2>Review extracted spending before logging</h2>
          <p>Import screenshots from the configured Drive folder, correct categories or amounts, then commit approved rows to Google Sheets.</p>
        </div>
        <div className={styles.actionButtons}>
          <button disabled={busy !== null} onClick={importSnapshots} type="button">
            {busy === 'import' ? 'Importing...' : 'Import snapshots'}
          </button>
          <button disabled={!stage || !hasPendingStageChanges || busy !== null} onClick={() => void saveDrafts()} type="button">
            {busy === 'save' ? 'Saving...' : 'Save staged edits'}
          </button>
          <button disabled={!stage || selectedSnapshots.length === 0 || busy !== null} onClick={commitToSheet} type="button">
            {busy === 'commit' ? 'Committing...' : 'Commit to Sheet'}
          </button>
        </div>
        {message ? <p className={styles.statusMessage}>{message}</p> : null}
      </section>

      <section className={styles.panel}>
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Staged extraction</p>
            <h2>Spending rows and categories</h2>
            <p className={styles.mutedText}>Rows are grouped by snapshot. Use the category dropdown for common categories, or type a custom category name.</p>
          </div>
          <span>{selectedRows} of {rows.length} rows selected</span>
        </div>
        <datalist id="category-options">
          {categoryOptions.map((category) => <option key={category} value={category} />)}
        </datalist>
        {!stage || rows.length === 0 ? (
          <p className={styles.mutedText}>No staged spendings yet. Import snapshots to start.</p>
        ) : stage.snapshots.map((snapshot) => {
          const selected = isSnapshotSelected(snapshot);
          return (
            <section className={styles.snapshotGroup} data-selected={selected ? 'true' : 'false'} key={snapshot.source.source_document_id}>
              <div className={styles.snapshotHeader}>
                <div>
                  <strong>{snapshot.source.file_name}</strong>
                  <span>{snapshot.transactions.length} rows</span>
                  <label className={styles.checkboxLabel}>
                    <input
                      checked={selected}
                      onChange={(event) => updateSnapshotSelection(snapshot.source.source_document_id, event.target.checked)}
                      type="checkbox"
                    />
                    Include
                  </label>
                </div>
                {!selected ? <small>Excluded from commit.</small> : snapshot.source.error_summary ? <small>{snapshot.source.error_summary}</small> : null}
              </div>
              <table className={styles.dataTable}>
                <thead>
                  <tr><th>Month</th><th>Date</th><th>Merchant</th><th>Amount</th><th>Type</th><th>Category</th><th>Evidence</th></tr>
                </thead>
                <tbody>
                  {snapshot.transactions.map((row) => (
                    <tr key={row.transaction_id}>
                      <td><input className={styles.tableInput} disabled={!selected} value={valueFor(row, 'observed_month')} onChange={(event) => updateDraft(row.transaction_id, { observed_month: event.target.value })} /></td>
                      <td><input className={styles.tableInput} disabled={!selected} value={valueFor(row, 'transaction_date')} onChange={(event) => updateDraft(row.transaction_id, { transaction_date: event.target.value })} /></td>
                      <td><input className={styles.tableInput} disabled={!selected} value={valueFor(row, 'merchant_normalized')} onChange={(event) => updateDraft(row.transaction_id, { merchant_normalized: event.target.value })} /></td>
                      <td><input className={styles.tableInput} disabled={!selected} value={String(valueFor(row, 'amount'))} onChange={(event) => updateDraft(row.transaction_id, { amount: Number(event.target.value) })} /></td>
                      <td>
                        <select className={styles.tableInput} disabled={!selected} value={valueFor(row, 'transaction_type')} onChange={(event) => updateDraft(row.transaction_id, { transaction_type: event.target.value as Transaction['transaction_type'] })}>
                          {TYPES.map((type) => <option key={type} value={type}>{type}</option>)}
                        </select>
                      </td>
                      <td>
                        <div className={styles.categoryEditor}>
                          <select
                            className={styles.tableInput}
                            disabled={!selected}
                            value={categoryOptions.includes(String(valueFor(row, 'category'))) ? String(valueFor(row, 'category')) : ''}
                            onChange={(event) => {
                              if (event.target.value) updateDraft(row.transaction_id, { category: event.target.value });
                            }}
                          >
                            <option value="">Custom</option>
                            {categoryOptions.map((category) => <option key={category} value={category}>{category}</option>)}
                          </select>
                          <input
                            className={styles.tableInput}
                            disabled={!selected}
                            list="category-options"
                            value={valueFor(row, 'category')}
                            onChange={(event) => updateDraft(row.transaction_id, { category: event.target.value })}
                          />
                        </div>
                      </td>
                      <td title={row.evidence_text}>{row.evidence_text || money(row.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </section>
          );
        })}
      </section>
    </>
  );
}

'use client';

import { useMemo, useState } from 'react';
import styles from '../page.module.css';
import type { AssetSnapshot, Correction, ReviewItem, Transaction } from '../../types/domain';

type CorrectionField = Correction['field_name'];

type DraftCorrection = {
  fieldName: CorrectionField;
  newValue: string;
  applyFuture: boolean;
};

type SeverityFilter = 'all' | ReviewItem['severity'];

const SEVERITY_ORDER: ReviewItem['severity'][] = ['high', 'medium', 'low'];

const CATEGORY_OPTIONS = [
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
];

const TYPE_OPTIONS: Transaction['transaction_type'][] = ['expense', 'income', 'transfer', 'payment', 'fee', 'refund', 'unknown'];
const BALANCE_TYPE_OPTIONS: AssetSnapshot['balance_type'][] = ['checking', 'savings', 'credit_available', 'credit_balance', 'unknown'];
const VALIDATION_OPTIONS: Array<{ value: Transaction['validation_status']; label: string }> = [
  { value: 'rejected', label: 'Duplicate - exclude from spending' },
  { value: 'valid', label: 'Keep as real spending' },
  { value: 'needs_review', label: 'Needs more review' },
];
const REVIEW_STATUS_OPTIONS = [
  { value: 'resolved', label: 'Keep this snapshot' },
  { value: 'ignored', label: 'Ignore this review' },
];

interface ReviewWorkbenchProps {
  assetSnapshots: AssetSnapshot[];
  pendingReviews: ReviewItem[];
  transactions: Transaction[];
}

function safeText(value: string | null | undefined, fallback = '') {
  return value && value.trim() ? value : fallback;
}

function money(value: number | null | undefined) {
  if (value === null || value === undefined) return '-';
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function suggestedField(review: ReviewItem): CorrectionField {
  if (review.target_type === 'asset_snapshot') return 'review_status';
  const question = safeText(review.question).toLowerCase();
  if (review.issue_type === 'duplicate_risk') return 'validation_status';
  if (review.issue_type === 'unclear_category') return 'category';
  if (question.includes('month')) return 'observed_month';
  if (question.includes('date')) return 'date';
  if (question.includes('amount')) return 'amount';
  if (question.includes('merchant')) return 'merchant_normalized';
  if (question.includes('type') || question.includes('income') || question.includes('expense')) return 'transaction_type';
  return 'category';
}

function defaultValue(
  review: ReviewItem,
  transaction: Transaction | undefined,
  assetSnapshot: AssetSnapshot | undefined,
  fieldName: CorrectionField
) {
  const options = cleanSuggestedOptions(review.suggested_options);
  if (options.length > 0 && fieldName === 'category') return options[0];
  if (review.target_type === 'asset_snapshot') {
    if (fieldName === 'review_status') return 'resolved';
    if (!assetSnapshot) return '';
    if (fieldName === 'observed_month') return safeText(assetSnapshot.observed_month);
    if (fieldName === 'observed_date' || fieldName === 'date') return safeText(assetSnapshot.observed_date);
    if (fieldName === 'balance') return Number.isFinite(assetSnapshot.balance) ? String(assetSnapshot.balance) : '';
    if (fieldName === 'account_label') return safeText(assetSnapshot.account_label);
    if (fieldName === 'balance_type') return safeText(assetSnapshot.balance_type, 'unknown');
  }
  if (!transaction) return '';
  if (fieldName === 'category') return transaction.category === 'uncategorized' ? '' : safeText(transaction.category);
  if (fieldName === 'date') return safeText(transaction.transaction_date);
  if (fieldName === 'observed_month') return safeText(transaction.observed_month);
  if (fieldName === 'amount') return Number.isFinite(transaction.amount) ? String(transaction.amount) : '';
  if (fieldName === 'merchant_normalized') return safeText(transaction.merchant_normalized);
  if (fieldName === 'transaction_type') return safeText(transaction.transaction_type, 'unknown');
  if (fieldName === 'validation_status') {
    return safeText(review.question).toLowerCase().includes('matches another row') ? 'rejected' : safeText(transaction.validation_status, 'needs_review');
  }
  return '';
}

function cleanSuggestedOptions(options: string[] | null | undefined) {
  return (Array.isArray(options) ? options : []).filter((option) => option !== 'duplicate_remove_one');
}

function inputForDraft(
  draft: DraftCorrection,
  options: string[],
  onChange: (newValue: string) => void
) {
  if (draft.fieldName === 'category') {
    const categoryOptions = Array.from(new Set([...options, ...CATEGORY_OPTIONS]));
    return (
      <select value={draft.newValue} onChange={(event) => onChange(event.target.value)}>
        {categoryOptions.map((option) => <option key={option} value={option}>{option}</option>)}
      </select>
    );
  }

  if (draft.fieldName === 'transaction_type') {
    return (
      <select value={draft.newValue} onChange={(event) => onChange(event.target.value)}>
        {TYPE_OPTIONS.map((option) => <option key={option} value={option}>{option}</option>)}
      </select>
    );
  }

  if (draft.fieldName === 'validation_status') {
    return (
      <select value={draft.newValue} onChange={(event) => onChange(event.target.value)}>
        {VALIDATION_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
    );
  }

  if (draft.fieldName === 'balance_type') {
    return (
      <select value={draft.newValue} onChange={(event) => onChange(event.target.value)}>
        {BALANCE_TYPE_OPTIONS.map((option) => <option key={option} value={option}>{option}</option>)}
      </select>
    );
  }

  if (draft.fieldName === 'review_status') {
    return (
      <select value={draft.newValue} onChange={(event) => onChange(event.target.value)}>
        {REVIEW_STATUS_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
    );
  }

  return (
    <input
      type={draft.fieldName === 'date' || draft.fieldName === 'observed_date' ? 'date' : draft.fieldName === 'observed_month' ? 'month' : 'text'}
      value={draft.newValue}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

export default function ReviewWorkbench({ assetSnapshots, pendingReviews, transactions }: ReviewWorkbenchProps) {
  const [selectedReviews, setSelectedReviews] = useState<Record<string, boolean>>({});
  const [reviewDrafts, setReviewDrafts] = useState<Record<string, DraftCorrection>>({});
  const [selectedTransactions, setSelectedTransactions] = useState<Record<string, boolean>>({});
  const [transactionDrafts, setTransactionDrafts] = useState<Record<string, DraftCorrection>>({});
  const [monthFilter, setMonthFilter] = useState<string>('all');
  const [bulkMonth, setBulkMonth] = useState<string>('');
  const [severityFilter, setSeverityFilter] = useState<SeverityFilter>('all');
  const [collapsedSeverity, setCollapsedSeverity] = useState<Record<ReviewItem['severity'], boolean>>({
    high: false,
    medium: false,
    low: false,
  });
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [resolvedReviewIds, setResolvedReviewIds] = useState<Record<string, boolean>>({});

  const transactionById = useMemo(() => new Map(transactions.map((transaction) => [transaction.transaction_id, transaction])), [transactions]);
  const assetSnapshotById = useMemo(() => new Map(assetSnapshots.map((assetSnapshot) => [assetSnapshot.asset_snapshot_id, assetSnapshot])), [assetSnapshots]);
  const activeReviews = pendingReviews.filter((review) => !resolvedReviewIds[review.review_item_id]);
  const filteredReviews = activeReviews.filter((review) => severityFilter === 'all' || review.severity === severityFilter);
  const groupedReviews = SEVERITY_ORDER.map((severity) => ({
    severity,
    reviews: filteredReviews.filter((review) => review.severity === severity),
    total: activeReviews.filter((review) => review.severity === severity).length,
  })).filter((group) => group.total > 0 || severityFilter === group.severity);
  const months = Array.from(new Set(transactions.map((transaction) => safeText(transaction.observed_month, 'unknown')))).sort();
  const visibleTransactions = transactions.filter((transaction) => monthFilter === 'all' || safeText(transaction.observed_month, 'unknown') === monthFilter);

  function draftForReview(review: ReviewItem): DraftCorrection {
    const current = reviewDrafts[review.review_item_id];
    if (current) return current;
    const transaction = transactionById.get(review.target_id);
    const assetSnapshot = assetSnapshotById.get(review.target_id);
    const suggested = suggestedField(review);
    const fieldName = suggested === 'date' && transaction?.observed_month ? 'observed_month' : suggested;
    return {
      fieldName,
      newValue: defaultValue(review, transaction, assetSnapshot, fieldName),
      applyFuture: false,
    };
  }

  function isSupportedReview(review: ReviewItem) {
    return (
      (review.target_type === 'transaction' && transactionById.has(review.target_id)) ||
      (review.target_type === 'asset_snapshot' && assetSnapshotById.has(review.target_id))
    );
  }

  function updateReviewDraft(review: ReviewItem, patch: Partial<DraftCorrection>) {
    setReviewDrafts((current) => {
      const transaction = transactionById.get(review.target_id);
      const assetSnapshot = assetSnapshotById.get(review.target_id);
      const previous = current[review.review_item_id] ?? draftForReview(review);
      const fieldName = patch.fieldName ?? previous.fieldName;
      const resetValue = patch.fieldName && patch.fieldName !== previous.fieldName;
      return {
        ...current,
        [review.review_item_id]: {
          ...previous,
          ...patch,
          fieldName,
          newValue: resetValue ? defaultValue(review, transaction, assetSnapshot, fieldName) : patch.newValue ?? previous.newValue,
        },
      };
    });
  }

  function updateTransactionDraft(transaction: Transaction, patch: Partial<DraftCorrection>) {
    setTransactionDrafts((current) => {
      const previous = current[transaction.transaction_id] ?? {
        fieldName: 'observed_month' as CorrectionField,
        newValue: safeText(transaction.observed_month),
        applyFuture: false,
      };
      return {
        ...current,
        [transaction.transaction_id]: { ...previous, ...patch },
      };
    });
  }

  function selectVisibleTransactions(selected: boolean) {
    setSelectedTransactions((current) => {
      const next = { ...current };
      for (const transaction of visibleTransactions) next[transaction.transaction_id] = selected;
      return next;
    });
  }

  function fillSelectedMonth() {
    if (!bulkMonth) {
      setMessage('Choose a month before filling selected rows.');
      return;
    }
    for (const transaction of transactions) {
      if (selectedTransactions[transaction.transaction_id]) {
        updateTransactionDraft(transaction, { fieldName: 'observed_month', newValue: bulkMonth });
      }
    }
    setMessage('Month filled for selected rows. Apply batch corrections when ready.');
  }

  async function applyBatch() {
    const reviewCorrections = activeReviews
      .filter((review) => selectedReviews[review.review_item_id] && isSupportedReview(review))
      .map((review) => {
        const draft = draftForReview(review);
        return {
          reviewItemId: review.review_item_id,
          fieldName: draft.fieldName,
          newValue: draft.newValue,
          applyFuture: draft.applyFuture,
        };
      });

    const transactionCorrections = transactions
      .filter((transaction) => selectedTransactions[transaction.transaction_id] && transactionDrafts[transaction.transaction_id]?.newValue)
      .map((transaction) => ({
        transactionId: transaction.transaction_id,
        fieldName: transactionDrafts[transaction.transaction_id].fieldName,
        newValue: transactionDrafts[transaction.transaction_id].newValue,
        applyFuture: transactionDrafts[transaction.transaction_id].applyFuture,
      }));

    const corrections = [...reviewCorrections, ...transactionCorrections].filter((correction) => correction.newValue.trim());
    if (corrections.length === 0) {
      setMessage('Select at least one row with a correction before applying.');
      return;
    }

    setBusy(true);
    setMessage('Applying ' + corrections.length + ' corrections...');
    try {
      const response = await fetch('/api/corrections/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ corrections }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Batch correction failed.');
      setResolvedReviewIds((current) => {
        const next = { ...current };
        for (const correction of reviewCorrections) next[correction.reviewItemId] = true;
        return next;
      });
      setSelectedReviews({});
      setSelectedTransactions({});
      setTransactionDrafts({});
      setMessage('Batch applied. Summaries refreshed once for the whole batch.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Batch correction failed.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <section className={styles.actionCenter}>
        <div>
          <p className={styles.eyebrow}>Batch correction queue</p>
          <h2>Apply many corrections together</h2>
          <p>Select the rows you want to apply, adjust each correction, then submit one batch.</p>
        </div>
        <div className={styles.actionButtons}>
          <button type="button" onClick={() => {
            const selected: Record<string, boolean> = {};
            for (const review of filteredReviews) {
              if (isSupportedReview(review)) selected[review.review_item_id] = true;
            }
            setSelectedReviews(selected);
          }}>
            Select visible reviews
          </button>
          <button type="button" disabled={busy} onClick={applyBatch}>
            {busy ? 'Applying...' : 'Apply selected'}
          </button>
        </div>
        {message ? <p className={styles.statusMessage}>{message}</p> : null}
      </section>

      <section className={styles.panel}>
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Pending reviews</p>
            <h2>Separate corrections by transaction</h2>
          </div>
          <span>{filteredReviews.length} visible / {activeReviews.length} open</span>
        </div>
        <div className={styles.severityControls}>
          {(['all', ...SEVERITY_ORDER] as SeverityFilter[]).map((severity) => (
            <button
              aria-pressed={severityFilter === severity}
              className={severityFilter === severity ? styles.activeFilter : ''}
              key={severity}
              onClick={() => setSeverityFilter(severity)}
              type="button"
            >
              {severity === 'all' ? 'All' : severity.charAt(0).toUpperCase() + severity.slice(1)}
            </button>
          ))}
        </div>
        <div className={styles.reviewTable}>
          {activeReviews.length === 0 ? <p className={styles.mutedText}>No pending reviews.</p> : groupedReviews.map((group) => (
            <section className={styles.severityGroup} key={group.severity}>
              <button
                className={styles.severityHeader}
                onClick={() => setCollapsedSeverity((current) => ({ ...current, [group.severity]: !current[group.severity] }))}
                type="button"
              >
                <strong>{group.severity.charAt(0).toUpperCase() + group.severity.slice(1)} severity</strong>
                <span>{group.total} open</span>
              </button>
              {collapsedSeverity[group.severity] ? null : group.reviews.length === 0 ? (
                <p className={styles.mutedText}>No {group.severity} severity reviews in this filter.</p>
              ) : group.reviews.map((review) => {
            const transaction = transactionById.get(review.target_id);
            const assetSnapshot = assetSnapshotById.get(review.target_id);
            const draft = draftForReview(review);
            const options = cleanSuggestedOptions(review.suggested_options);
            const canApply = isSupportedReview(review);

            return (
              <article className={styles.reviewRow} key={review.review_item_id}>
                <label className={styles.rowCheckbox}>
                  <input
                    disabled={!canApply}
                    checked={selectedReviews[review.review_item_id] === true}
                    onChange={(event) => setSelectedReviews((current) => ({ ...current, [review.review_item_id]: event.target.checked }))}
                    type="checkbox"
                  />
                </label>
                <div className={styles.rowMain}>
                  <strong>{transaction ? transaction.merchant_normalized : assetSnapshot ? assetSnapshot.account_label : review.target_type}</strong>
                  <span>{review.question}</span>
                  {transaction ? (
                    <small>
                      {safeText(transaction.transaction_date, 'missing date')} | {safeText(transaction.observed_month, 'unknown month')} | {money(transaction.amount)} | {safeText(transaction.account_label)}
                    </small>
                  ) : null}
                  {assetSnapshot ? (
                    <small>
                      {safeText(assetSnapshot.observed_date, 'missing date')} | {safeText(assetSnapshot.observed_month, 'unknown month')} | {money(assetSnapshot.balance)} | {assetSnapshot.balance_type} | confidence {Math.round(assetSnapshot.confidence * 100)}%
                    </small>
                  ) : null}
                  {transaction?.evidence_text ? <blockquote className={styles.evidence}>{transaction.evidence_text}</blockquote> : null}
                  {assetSnapshot?.evidence_text ? <blockquote className={styles.evidence}>{assetSnapshot.evidence_text}</blockquote> : null}
                </div>
                {canApply ? (
                  <div className={styles.rowControls}>
                    <select value={draft.fieldName} onChange={(event) => updateReviewDraft(review, { fieldName: event.target.value as CorrectionField })}>
                      {review.target_type === 'asset_snapshot' ? (
                        <>
                          <option value="review_status">Review decision</option>
                          <option value="observed_month">Month only</option>
                          <option value="observed_date">Exact date</option>
                          <option value="balance">Balance</option>
                          <option value="account_label">Account label</option>
                          <option value="balance_type">Balance type</option>
                        </>
                      ) : (
                        <>
                          <option value="category">Category</option>
                          <option value="observed_month">Month only</option>
                          <option value="date">Exact date</option>
                          <option value="amount">Amount</option>
                          <option value="merchant_normalized">Merchant</option>
                          <option value="transaction_type">Type</option>
                          <option value="validation_status">Duplicate decision</option>
                        </>
                      )}
                    </select>
                    {inputForDraft(draft, options, (newValue) => updateReviewDraft(review, { newValue }))}
                    {draft.fieldName === 'category' ? (
                      <label className={styles.checkboxLabel}>
                        <input
                          checked={draft.applyFuture}
                          onChange={(event) => updateReviewDraft(review, { applyFuture: event.target.checked })}
                          type="checkbox"
                        />
                        Apply to future similar merchants
                      </label>
                    ) : null}
                  </div>
                ) : (
                  <p className={styles.mutedText}>This review type is visible here but still needs manual handling in the Sheet.</p>
                )}
              </article>
            );
              })}
            </section>
          ))}
        </div>
      </section>

      <section className={styles.panel}>
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Month batch tool</p>
            <h2>Set monthly spend without exact dates</h2>
          </div>
          <span>{visibleTransactions.length} visible</span>
        </div>
        <div className={styles.monthTools}>
          <label>
            View month
            <select value={monthFilter} onChange={(event) => setMonthFilter(event.target.value)}>
              <option value="all">All months</option>
              {months.map((month) => <option key={month} value={month}>{month}</option>)}
            </select>
          </label>
          <label>
            Set selected to
            <input type="month" value={bulkMonth} onChange={(event) => setBulkMonth(event.target.value)} />
          </label>
          <button type="button" onClick={() => selectVisibleTransactions(true)}>Select visible</button>
          <button type="button" onClick={() => selectVisibleTransactions(false)}>Clear visible</button>
          <button type="button" onClick={fillSelectedMonth}>Fill selected month</button>
        </div>
        <div className={styles.transactionList}>
          {visibleTransactions.map((transaction) => {
            const draft = transactionDrafts[transaction.transaction_id];
            return (
              <article className={styles.transactionRow} key={transaction.transaction_id}>
                <label className={styles.rowCheckbox}>
                  <input
                    checked={selectedTransactions[transaction.transaction_id] === true}
                    onChange={(event) => setSelectedTransactions((current) => ({ ...current, [transaction.transaction_id]: event.target.checked }))}
                    type="checkbox"
                  />
                </label>
                <div className={styles.rowMain}>
                  <strong>{safeText(transaction.merchant_normalized, 'Unknown merchant')}</strong>
                  <small>
                    {safeText(transaction.transaction_date, 'missing date')} | {safeText(transaction.observed_month, 'unknown month')} | {money(transaction.amount)} | {transaction.transaction_type} | {transaction.category}
                  </small>
                </div>
                <div className={styles.rowControls}>
                  <select
                    value={draft?.fieldName ?? 'observed_month'}
                    onChange={(event) => updateTransactionDraft(transaction, { fieldName: event.target.value as CorrectionField })}
                  >
                    <option value="observed_month">Month only</option>
                    <option value="date">Exact date</option>
                    <option value="category">Category</option>
                    <option value="transaction_type">Type</option>
                  </select>
                  {inputForDraft(draft ?? { fieldName: 'observed_month', newValue: safeText(transaction.observed_month), applyFuture: false }, [], (newValue) =>
                    updateTransactionDraft(transaction, { newValue })
                  )}
                </div>
              </article>
            );
          })}
        </div>
      </section>
    </>
  );
}

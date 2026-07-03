'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import styles from './page.module.css';
import type { Anomaly, AssetTrend, SourceDocument, Transaction } from '../types/domain';

interface AnomalyCenterProps {
  anomalies: Anomaly[];
  assetTrends: AssetTrend[];
  sourceDocuments: SourceDocument[];
  transactions: Transaction[];
  userEmail: string;
}

type AnomalyDecision = 'resolved' | 'ignored' | 'mark_duplicate';

const SEVERITY_ORDER: Anomaly['severity'][] = ['high', 'medium', 'low'];

function money(value: number | null | undefined) {
  if (value === null || value === undefined) return '-';
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function safeText(value: string | null | undefined, fallback = 'unknown') {
  return value && value.trim() ? value : fallback;
}

function anomalyTypeLabel(value: Anomaly['anomaly_type']) {
  return value.replace(/_/g, ' ');
}

function sourceEvidenceHref(sourceDocumentId: string, userEmail: string) {
  return '/source/' + encodeURIComponent(sourceDocumentId) + '?email=' + encodeURIComponent(userEmail);
}

export default function AnomalyCenter({ anomalies, assetTrends, sourceDocuments, transactions, userEmail }: AnomalyCenterProps) {
  const [localAnomalies, setLocalAnomalies] = useState(anomalies);
  const [busyAnomalyId, setBusyAnomalyId] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const transactionById = useMemo(() => new Map(transactions.map((transaction) => [transaction.transaction_id, transaction])), [transactions]);
  const assetTrendByKey = useMemo(() => new Map(assetTrends.map((trend) => [trend.month + ':' + trend.account_label, trend])), [assetTrends]);
  const sourceById = useMemo(() => new Map(sourceDocuments.map((source) => [source.source_document_id, source])), [sourceDocuments]);
  const visibleAnomalies = useMemo(() => {
    return [...localAnomalies].sort((a, b) => {
      const severityDelta = SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity);
      return severityDelta || safeText(b.month, '').localeCompare(safeText(a.month, ''));
    });
  }, [localAnomalies]);

  async function resolve(anomaly: Anomaly, decision: AnomalyDecision, duplicateTransactionId?: string) {
    setBusyAnomalyId(anomaly.anomaly_id);
    setMessage('Saving anomaly decision...');
    try {
      const response = await fetch('/api/anomalies/resolve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          anomalyId: anomaly.anomaly_id,
          decision,
          duplicateTransactionId,
        }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof body.detail === 'string' ? body.detail : 'Anomaly update failed.');
      setLocalAnomalies((current) => current.filter((item) => item.anomaly_id !== anomaly.anomaly_id));
      setMessage(decision === 'mark_duplicate' ? 'Duplicate decision saved. Summaries refreshed.' : 'Anomaly decision saved.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Anomaly update failed.');
    } finally {
      setBusyAnomalyId(null);
    }
  }

  return (
    <section className={styles.panel} id="anomaly-review">
      <div className={styles.sectionHeader}>
        <div>
          <p className={styles.eyebrow}>Anomaly review</p>
          <h2>Open spending and balance checks</h2>
        </div>
        <span>{visibleAnomalies.length} open</span>
      </div>
      {message ? <p className={styles.statusMessage}>{message}</p> : null}
      {visibleAnomalies.length === 0 ? (
        <p className={styles.mutedText}>No open anomalies. New checks will appear after summaries refresh.</p>
      ) : (
        <div className={styles.anomalyList}>
          {visibleAnomalies.map((anomaly) => {
            const relatedTransactions = anomaly.related_record_ids
              .map((id) => transactionById.get(id))
              .filter((transaction): transaction is Transaction => transaction !== undefined);
            const relatedAssetTrends = anomaly.related_record_ids
              .map((id) => assetTrendByKey.get(id))
              .filter((trend): trend is AssetTrend => trend !== undefined);
            const unresolvedIds = anomaly.related_record_ids.filter((id) => !transactionById.has(id) && !assetTrendByKey.has(id));
            const isDuplicate = anomaly.anomaly_type === 'duplicate_charge' && relatedTransactions.length > 1;

            return (
              <article className={styles.anomalyCard} key={anomaly.anomaly_id}>
                <div className={styles.anomalyHeader}>
                  <div>
                    <strong>{anomalyTypeLabel(anomaly.anomaly_type)}</strong>
                    <span>{anomaly.month} | {anomaly.severity} severity</span>
                  </div>
                  <span>{anomaly.status}</span>
                </div>
                <p>{anomaly.summary}</p>
                <p className={styles.mutedText}>{anomaly.suggested_action}</p>

                {relatedTransactions.length > 0 ? (
                  <div className={styles.relatedRecords}>
                    {relatedTransactions.map((transaction, index) => {
                      const source = sourceById.get(transaction.source_document_id);
                      return (
                        <div key={transaction.transaction_id}>
                          <strong>{safeText(transaction.merchant_normalized, 'Unknown merchant')}</strong>
                          <span>
                            {safeText(transaction.transaction_date, 'missing date')} | {money(transaction.amount)} | {transaction.category} |{' '}
                            <Link className={styles.tableLink} href={sourceEvidenceHref(transaction.source_document_id, userEmail)}>
                              {source?.file_name ?? transaction.source_document_id}
                            </Link>
                          </span>
                          {transaction.evidence_text ? <small>{transaction.evidence_text}</small> : null}
                          {isDuplicate ? (
                            <button
                              className={styles.inlineDangerButton}
                              disabled={busyAnomalyId === anomaly.anomaly_id}
                              onClick={() => resolve(anomaly, 'mark_duplicate', transaction.transaction_id)}
                              type="button"
                            >
                              {busyAnomalyId === anomaly.anomaly_id ? 'Working...' : 'Exclude row ' + (index + 1)}
                            </button>
                          ) : null}
                        </div>
                      );
                    })}
                  </div>
                ) : null}

                {relatedAssetTrends.length > 0 ? (
                  <div className={styles.relatedRecords}>
                    {relatedAssetTrends.map((trend) => (
                      <div key={trend.month + trend.account_label}>
                        <strong>{trend.account_label}</strong>
                        <span>{trend.month} | ending {money(trend.ending_balance)} | change {money(trend.monthly_change)} | spending {money(trend.related_spending_total)}</span>
                      </div>
                    ))}
                  </div>
                ) : null}

                {unresolvedIds.length > 0 ? (
                  <p className={styles.mutedText}>Related summary keys: {unresolvedIds.join(', ')}</p>
                ) : null}

                <div className={styles.anomalyActions}>
                  {isDuplicate ? (
                    <button disabled={busyAnomalyId === anomaly.anomaly_id} onClick={() => resolve(anomaly, 'ignored')} type="button">
                      Keep both
                    </button>
                  ) : null}
                  <button disabled={busyAnomalyId === anomaly.anomaly_id} onClick={() => resolve(anomaly, 'resolved')} type="button">
                    Mark reviewed
                  </button>
                  <button disabled={busyAnomalyId === anomaly.anomaly_id} onClick={() => resolve(anomaly, 'ignored')} type="button">
                    Ignore
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}

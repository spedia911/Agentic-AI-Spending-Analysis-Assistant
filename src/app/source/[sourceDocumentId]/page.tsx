import Image from 'next/image';
import Link from 'next/link';
import { getEnv } from '../../../lib/env';
import { canViewDashboard, loadDashboardData } from '../../../lib/dashboard';
import { safeErrorDetail } from '../../../lib/privacy/redact';
import { getCachedSourceImage, sourceDocumentDriveUrl } from '../../../lib/source-evidence/cache';
import styles from '../../page.module.css';
import type { AssetSnapshot, Transaction } from '../../../types/domain';

export const dynamic = 'force-dynamic';

type EvidenceOverlay = {
  id: string;
  label: string;
  kind: 'transaction' | 'asset';
  x: number;
  y: number;
  width: number;
  height: number;
};

function safeText(value: string | null | undefined, fallback = 'unknown') {
  return value && value.trim() ? value : fallback;
}

function currency(value: number | null | undefined) {
  if (value === null || value === undefined) return '-';
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function confidence(value: number | null | undefined) {
  if (value === null || value === undefined || !Number.isFinite(value)) return '-';
  return Math.round(value * 100) + '%';
}

function transactionLabel(transaction: Transaction) {
  return safeText(transaction.transaction_date, 'missing date') + ' | ' + currency(transaction.amount) + ' | ' + transaction.transaction_type;
}

function assetLabel(assetSnapshot: AssetSnapshot) {
  return safeText(assetSnapshot.observed_date, 'missing date') + ' | ' + currency(assetSnapshot.balance) + ' | ' + assetSnapshot.balance_type;
}

function parseEvidenceRegion(value: string | null | undefined): Pick<EvidenceOverlay, 'x' | 'y' | 'width' | 'height'> | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as Record<string, unknown>;
    const x = Number(parsed.x);
    const y = Number(parsed.y);
    const width = Number(parsed.width);
    const height = Number(parsed.height);
    if (![x, y, width, height].every(Number.isFinite)) return null;
    if (x < 0 || y < 0 || width <= 0 || height <= 0 || x + width > 1 || y + height > 1) return null;
    return { x, y, width, height };
  } catch {
    return null;
  }
}

function evidenceOverlays(transactions: Transaction[], assetSnapshots: AssetSnapshot[]): EvidenceOverlay[] {
  const transactionOverlays = transactions.flatMap((transaction) => {
    const region = parseEvidenceRegion(transaction.evidence_region);
    return region
      ? [{
          id: transaction.transaction_id,
          label: safeText(transaction.merchant_normalized, 'Transaction') + ' ' + currency(transaction.amount),
          kind: 'transaction' as const,
          ...region,
        }]
      : [];
  });
  const assetOverlays = assetSnapshots.flatMap((assetSnapshot) => {
    const region = parseEvidenceRegion(assetSnapshot.evidence_region);
    return region
      ? [{
          id: assetSnapshot.asset_snapshot_id,
          label: assetSnapshot.account_label + ' ' + currency(assetSnapshot.balance),
          kind: 'asset' as const,
          ...region,
        }]
      : [];
  });
  return [...transactionOverlays, ...assetOverlays].slice(0, 12);
}

export default async function SourceEvidencePage({
  params,
  searchParams,
}: {
  params: Promise<{ sourceDocumentId: string }>;
  searchParams?: Promise<{ email?: string }>;
}) {
  const env = getEnv();
  const resolvedParams = await params;
  const resolvedSearchParams = await searchParams;
  const email = resolvedSearchParams?.email;

  if (!canViewDashboard(email, env.SINGLE_USER_EMAIL)) {
    return (
      <main className={styles.pageShell}>
        <section className={styles.accessPanel}>
          <h1>Source Evidence</h1>
          <p>Enter the configured user email as a query parameter to view source evidence.</p>
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
          <p className={styles.eyebrow}>Source evidence unavailable</p>
          <h1>Source Evidence</h1>
          <p>Unable to read the configured Google Sheet. Check the Sheet ID and sharing, then refresh this page.</p>
          <code>{safeErrorDetail(error, 'Unknown source evidence error')}</code>
        </section>
      </main>
    );
  }

  const source = data.sourceDocuments.find((item) => item.source_document_id === resolvedParams.sourceDocumentId);
  const dashboardHref = '/?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL);
  const reviewHref = '/review?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL);

  if (!source) {
    return (
      <main className={styles.pageShell}>
        <section className={styles.accessPanel}>
          <p className={styles.eyebrow}>Source not found</p>
          <h1>Source Evidence</h1>
          <p>The requested source file is not present in the configured Sheet.</p>
          <Link className={styles.secondaryLink} href={dashboardHref}>Back to dashboard</Link>
        </section>
      </main>
    );
  }

  const sourceTransactions = data.transactions.filter((transaction) => transaction.source_document_id === source.source_document_id);
  const sourceAssets = data.assetSnapshots.filter((assetSnapshot) => assetSnapshot.source_document_id === source.source_document_id);
  const sourceRecordIds = new Set([
    ...sourceTransactions.map((transaction) => transaction.transaction_id),
    ...sourceAssets.map((assetSnapshot) => assetSnapshot.asset_snapshot_id),
    source.source_document_id,
  ]);
  const sourceReviews = data.reviewItems.filter((review) => sourceRecordIds.has(review.target_id));
  const sourceAnomalies = data.anomalies.filter((anomaly) => anomaly.related_record_ids.some((recordId) => sourceRecordIds.has(recordId)));
  const cachedImage = await getCachedSourceImage(source);
  const overlays = evidenceOverlays(sourceTransactions, sourceAssets);
  const sourceImageSrc =
    '/api/source-documents/' + encodeURIComponent(source.source_document_id) + '/image?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL);

  return (
    <main className={styles.pageShell}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>Source evidence</p>
          <h1>{source.file_name}</h1>
        </div>
        <div className={styles.sourceActions}>
          <Link className={styles.secondaryLink} href={dashboardHref}>Dashboard</Link>
          <Link className={styles.secondaryLink} href={reviewHref}>Review</Link>
        </div>
      </header>

      <section className={`${styles.panel} ${styles.sourceHero}`}>
        <div className={styles.sourcePreview}>
          {cachedImage.exists ? (
            <div className={styles.sourcePreviewFrame}>
              <Image
                alt={'Cached screenshot preview for ' + source.file_name}
                className={styles.sourcePreviewImage}
                height={1400}
                src={sourceImageSrc}
                unoptimized
                width={1000}
              />
              {overlays.map((overlay) => (
                <div
                  className={overlay.kind === 'asset' ? styles.evidenceOverlayAsset : styles.evidenceOverlay}
                  key={overlay.id}
                  style={{
                    left: String(overlay.x * 100) + '%',
                    top: String(overlay.y * 100) + '%',
                    width: String(overlay.width * 100) + '%',
                    height: String(overlay.height * 100) + '%',
                  }}
                  title={overlay.label}
                >
                  <span>{overlay.label}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className={styles.previewEmpty}>
              <strong>Cached screenshot not available</strong>
              <span>Use the Drive file link to inspect the original source.</span>
            </div>
          )}
        </div>
        <div className={styles.sourceMeta}>
          <div className={styles.sourceMetaGrid}>
            <div><span>Status</span><strong>{source.status}</strong></div>
            <div><span>Type</span><strong>{source.mime_type}</strong></div>
            <div><span>Created</span><strong>{safeText(source.created_time, '-')}</strong></div>
            <div><span>Modified</span><strong>{safeText(source.modified_time, '-')}</strong></div>
            <div><span>Processed</span><strong>{safeText(source.processed_at, '-')}</strong></div>
            <div><span>Rows linked</span><strong>{sourceTransactions.length + sourceAssets.length}</strong></div>
          </div>
          {cachedImage.exists && overlays.length === 0 ? <p className={styles.mutedText}>No coordinate hints were stored for this source yet.</p> : null}
          {overlays.length > 0 ? <p className={styles.mutedText}>Highlighted boxes come from optional extraction coordinate hints.</p> : null}
          <p className={styles.mutedText}>{safeText(source.error_summary, 'No masked processing message recorded.')}</p>
          <a className={styles.primaryLink} href={sourceDocumentDriveUrl(source.source_document_id)} rel="noreferrer" target="_blank">
            Open Drive file
          </a>
        </div>
      </section>

      <section className={styles.panel}>
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Extracted rows</p>
            <h2>Transactions from this source</h2>
          </div>
          <span>{sourceTransactions.length} rows</span>
        </div>
        <table className={styles.dataTable}>
          <thead><tr><th>Date</th><th>Merchant</th><th>Amount</th><th>Type</th><th>Category</th><th>Confidence</th><th>Evidence</th></tr></thead>
          <tbody>
            {sourceTransactions.length === 0 ? <tr><td colSpan={7}>No transactions linked to this source.</td></tr> : sourceTransactions.map((transaction) => (
              <tr key={transaction.transaction_id}>
                <td>{safeText(transaction.transaction_date, '-')}</td>
                <td>{safeText(transaction.merchant_normalized, safeText(transaction.merchant_raw, 'Unknown merchant'))}</td>
                <td>{currency(transaction.amount)}</td>
                <td>{transaction.transaction_type}</td>
                <td>{transaction.category}</td>
                <td>{confidence(Math.min(transaction.category_confidence, transaction.extraction_confidence))}</td>
                <td className={styles.evidenceCell}>{safeText(transaction.evidence_text, '-')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className={styles.gridTwo}>
        <div className={styles.panel}>
          <div className={styles.sectionHeader}>
            <div>
              <p className={styles.eyebrow}>Balance evidence</p>
              <h2>Asset snapshots</h2>
            </div>
            <span>{sourceAssets.length} rows</span>
          </div>
          <div className={styles.stack}>
            {sourceAssets.length === 0 ? <p>No asset snapshots linked to this source.</p> : sourceAssets.map((assetSnapshot) => (
              <article className={styles.item} key={assetSnapshot.asset_snapshot_id}>
                <strong>{assetSnapshot.account_label}</strong>
                <p>{assetLabel(assetSnapshot)}</p>
                <small>{confidence(assetSnapshot.confidence)} confidence</small>
                {assetSnapshot.evidence_text ? <blockquote className={styles.evidence}>{assetSnapshot.evidence_text}</blockquote> : null}
              </article>
            ))}
          </div>
        </div>

        <div className={styles.panel}>
          <div className={styles.sectionHeader}>
            <div>
              <p className={styles.eyebrow}>Open follow-up</p>
              <h2>Reviews and anomalies</h2>
            </div>
            <span>{sourceReviews.length + sourceAnomalies.length} open</span>
          </div>
          <div className={styles.stack}>
            {sourceReviews.length === 0 && sourceAnomalies.length === 0 ? <p>No open reviews or anomalies tied to this source.</p> : null}
            {sourceReviews.map((review) => (
              <article className={styles.item} key={review.review_item_id}>
                <strong>{review.severity} {review.issue_type}</strong>
                <p>{review.question}</p>
                <small>{review.target_type} | {review.status}</small>
              </article>
            ))}
            {sourceAnomalies.map((anomaly) => (
              <article className={styles.item} key={anomaly.anomaly_id}>
                <strong>{anomaly.severity} {anomaly.anomaly_type}</strong>
                <p>{anomaly.summary}</p>
                <small>{anomaly.suggested_action}</small>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className={styles.panel}>
        <div className={styles.sectionHeader}>
          <div>
            <p className={styles.eyebrow}>Audit hints</p>
            <h2>Row labels</h2>
          </div>
          <span>{sourceRecordIds.size - 1} records</span>
        </div>
        <div className={styles.relatedRecords}>
          {sourceTransactions.map((transaction) => (
            <div key={transaction.transaction_id}>
              <strong>{safeText(transaction.merchant_normalized, 'Unknown merchant')}</strong>
              <span>{transactionLabel(transaction)}</span>
              <small>{transaction.transaction_id}</small>
            </div>
          ))}
          {sourceAssets.map((assetSnapshot) => (
            <div key={assetSnapshot.asset_snapshot_id}>
              <strong>{assetSnapshot.account_label}</strong>
              <span>{assetLabel(assetSnapshot)}</span>
              <small>{assetSnapshot.asset_snapshot_id}</small>
            </div>
          ))}
          {sourceTransactions.length === 0 && sourceAssets.length === 0 ? <p className={styles.mutedText}>No extracted records are linked to this source yet.</p> : null}
        </div>
      </section>
    </main>
  );
}

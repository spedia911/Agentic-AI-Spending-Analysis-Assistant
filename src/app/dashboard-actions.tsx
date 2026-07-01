'use client';

import { useMemo, useState } from 'react';
import styles from './page.module.css';
import type { ReviewItem } from '../types/domain';

type WorkflowAction = 'seed' | 'refresh' | 'run' | 'force';

interface DashboardActionsProps {
  pendingReviews: ReviewItem[];
  importHref?: string;
  reviewHref?: string;
  workflowDisabled?: boolean;
}

function actionLabel(action: WorkflowAction): string {
  if (action === 'seed') return 'Seed demo data';
  if (action === 'refresh') return 'Refresh summaries';
  if (action === 'force') return 'Force reprocess';
  return 'Run Drive workflow';
}

function endpointForAction(action: WorkflowAction): { url: string; body?: unknown } {
  if (action === 'seed') return { url: '/api/demo/seed' };
  if (action === 'refresh') return { url: '/api/summaries/refresh' };
  if (action === 'force') return { url: '/api/workflow/run', body: { forceReprocess: true } };
  return { url: '/api/workflow/run', body: {} };
}

export default function DashboardActions({ pendingReviews, importHref, reviewHref, workflowDisabled }: DashboardActionsProps) {
  const [busyAction, setBusyAction] = useState<WorkflowAction | null>(null);
  const [message, setMessage] = useState<string>('');
  const severityCounts = useMemo(() => {
    return pendingReviews.reduce(
      (counts, review) => ({ ...counts, [review.severity]: counts[review.severity] + 1 }),
      { high: 0, medium: 0, low: 0 }
    );
  }, [pendingReviews]);

  async function runAction(action: WorkflowAction) {
    setBusyAction(action);
    setMessage(actionLabel(action) + ' started...');
    const endpoint = endpointForAction(action);
    try {
      const response = await fetch(endpoint.url, {
        method: 'POST',
        headers: endpoint.body ? { 'Content-Type': 'application/json' } : undefined,
        body: endpoint.body ? JSON.stringify(endpoint.body) : undefined,
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(typeof body.detail === 'string' ? body.detail : 'Request failed.');
      }
      setMessage(actionLabel(action) + ' finished. Refreshing dashboard...');
      window.location.reload();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Action failed.');
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <>
      <section className={styles.actionCenter}>
        <div>
          <p className={styles.eyebrow}>Action center</p>
          <h2>What should happen next?</h2>
          <p>Run the workflow, refresh generated summaries, or seed safe demo rows without leaving the dashboard.</p>
        </div>
        <div className={styles.actionButtons}>
          {importHref ? <a className={styles.primaryLink} href={importHref}>Import snapshots</a> : null}
          {reviewHref ? <a className={styles.primaryLink} href={reviewHref}>Review corrections</a> : null}
          {(['run', 'refresh', 'seed', 'force'] as WorkflowAction[]).map((action) => (
            <button
              disabled={busyAction !== null || (workflowDisabled && (action === 'run' || action === 'force'))}
              key={action}
              onClick={() => runAction(action)}
              type="button"
            >
              {busyAction === action ? 'Working...' : actionLabel(action)}
            </button>
          ))}
        </div>
        {message ? <p className={styles.statusMessage}>{message}</p> : null}
      </section>

      {pendingReviews.length > 0 ? (
        <section className={styles.reviewNotice}>
          <div>
            <p className={styles.eyebrow}>Needs review</p>
            <h2>{pendingReviews.length} corrections need attention</h2>
            <p>
              Some rows may affect spending totals, duplicates, or category confidence. Open the review page to resolve them in a focused workflow.
            </p>
          </div>
          <div className={styles.noticeStats}>
            <span>High {severityCounts.high}</span>
            <span>Medium {severityCounts.medium}</span>
            <span>Low {severityCounts.low}</span>
          </div>
          {reviewHref ? <a className={styles.primaryLink} href={reviewHref}>Open review page</a> : null}
        </section>
      ) : null}
    </>
  );
}

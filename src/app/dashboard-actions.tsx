'use client';

import { useMemo, useState } from 'react';
import styles from './page.module.css';
import type { ReviewItem } from '../types/domain';

type WorkflowAction = 'seed' | 'refresh' | 'run' | 'force';

type SetupHealthItem = {
  id: string;
  label: string;
  status: 'ok' | 'warning' | 'error';
  message: string;
  detail?: string;
};

type SetupHealthReport = {
  status: 'ok' | 'warning' | 'error';
  checkedAt: string;
  items: SetupHealthItem[];
};

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

function limitedWorkflowBody(forceReprocess: boolean, maxDocuments: string) {
  const parsedLimit = Number(maxDocuments);
  const body: { forceReprocess?: boolean; maxDocuments?: number } = forceReprocess ? { forceReprocess: true } : {};
  if (Number.isInteger(parsedLimit) && parsedLimit > 0) {
    body.maxDocuments = parsedLimit;
  }
  return body;
}

function endpointForAction(action: WorkflowAction, maxDocuments: string): { url: string; body?: unknown } {
  if (action === 'seed') return { url: '/api/demo/seed' };
  if (action === 'refresh') return { url: '/api/summaries/refresh' };
  if (action === 'force') return { url: '/api/workflow/run', body: limitedWorkflowBody(true, maxDocuments) };
  return { url: '/api/workflow/run', body: limitedWorkflowBody(false, maxDocuments) };
}

export default function DashboardActions({ pendingReviews, importHref, reviewHref, workflowDisabled }: DashboardActionsProps) {
  const [busyAction, setBusyAction] = useState<WorkflowAction | null>(null);
  const [healthBusy, setHealthBusy] = useState(false);
  const [healthReport, setHealthReport] = useState<SetupHealthReport | null>(null);
  const [confirmingForce, setConfirmingForce] = useState(false);
  const [maxDocuments, setMaxDocuments] = useState('5');
  const [message, setMessage] = useState<string>('');
  const severityCounts = useMemo(() => {
    return pendingReviews.reduce(
      (counts, review) => ({ ...counts, [review.severity]: counts[review.severity] + 1 }),
      { high: 0, medium: 0, low: 0 }
    );
  }, [pendingReviews]);

  async function runAction(action: WorkflowAction) {
    if (action === 'force' && !confirmingForce) {
      setConfirmingForce(true);
      setMessage('Force reprocess will rerun files already known in the Drive folder. Click Confirm force reprocess to continue.');
      return;
    }
    setConfirmingForce(false);
    setBusyAction(action);
    setMessage(actionLabel(action) + ' started...');
    const endpoint = endpointForAction(action, maxDocuments);
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

  async function testSetup() {
    setHealthBusy(true);
    setMessage('Testing setup connections...');
    try {
      const response = await fetch('/api/setup/health');
      const body = await response.json().catch(() => null);
      if (!body || !Array.isArray(body.items)) {
        throw new Error('Setup health check returned an unexpected response.');
      }
      setHealthReport(body);
      setMessage(body.status === 'ok' ? 'Setup looks ready.' : 'Setup check found items to review.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Setup health check failed.');
    } finally {
      setHealthBusy(false);
    }
  }

  return (
    <>
      <section className={styles.actionCenter} id="action-center">
        <div>
          <p className={styles.eyebrow}>Action center</p>
          <h2>What should happen next?</h2>
          <p>Run the workflow, refresh generated summaries, or seed safe demo rows without leaving the dashboard.</p>
        </div>
        <div className={styles.actionButtons}>
          {importHref ? <a className={styles.primaryLink} href={importHref}>Import snapshots</a> : null}
          {reviewHref ? <a className={styles.primaryLink} href={reviewHref}>Review corrections</a> : null}
          <label className={styles.runLimitControl}>
            Files this run
            <input
              min="1"
              max="50"
              onChange={(event) => setMaxDocuments(event.target.value)}
              placeholder="All pending"
              type="number"
              value={maxDocuments}
            />
          </label>
          <button disabled={busyAction !== null || healthBusy} onClick={testSetup} type="button">
            {healthBusy ? 'Testing...' : 'Test setup'}
          </button>
          {(['run', 'refresh', 'seed', 'force'] as WorkflowAction[]).map((action) => (
            <button
              disabled={healthBusy || busyAction !== null || (workflowDisabled && (action === 'run' || action === 'force'))}
              key={action}
              onClick={() => runAction(action)}
              type="button"
            >
              {busyAction === action ? 'Working...' : confirmingForce && action === 'force' ? 'Confirm force reprocess' : actionLabel(action)}
            </button>
          ))}
        </div>
        {message ? <p className={styles.statusMessage}>{message}</p> : null}
        {healthReport ? (
          <div className={styles.healthChecklist}>
            <div className={styles.healthSummary}>
              <strong>Setup health: {healthReport.status}</strong>
              <span>{new Date(healthReport.checkedAt).toLocaleString()}</span>
            </div>
            {healthReport.items.map((healthItem) => (
              <div className={styles.healthItem} data-status={healthItem.status} key={healthItem.id}>
                <strong>{healthItem.label}</strong>
                <span>{healthItem.status}</span>
                <p>{healthItem.message}</p>
                {healthItem.detail ? <small>{healthItem.detail}</small> : null}
              </div>
            ))}
          </div>
        ) : null}
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

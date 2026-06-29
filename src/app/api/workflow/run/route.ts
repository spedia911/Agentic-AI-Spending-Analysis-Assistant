import { NextRequest, NextResponse } from 'next/server';
import { getEnv } from '../../../../lib/env';
import { initializeSpreadsheet, upsertRows } from '../../../../lib/google/sheets';
import { runIngestion } from '../../../../lib/orchestrator/ingest';
import { runPendingExtractionProcessing } from '../../../../lib/orchestrator/process';
import { refreshSummaryTabs } from '../../../../lib/orchestrator/summarize';
import type { RunState } from '../../../../types/domain';

function runId(startedAt: string): string {
  return 'run_' + startedAt.replace(/[^0-9]/g, '').slice(0, 14);
}

function maskError(value: string): string {
  return value
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email]')
    .replace(/\b\d{5,}\b/g, '[number]')
    .slice(0, 240);
}

export async function POST(request: NextRequest) {
  const startedAt = new Date().toISOString();
  const id = runId(startedAt);
  let sheetId: string | null = null;

  try {
    const env = getEnv();
    sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
    const body = await request.json().catch(() => ({}));
    const ingestion = await runIngestion({ forceReprocess: body.forceReprocess === true });
    const processing = await runPendingExtractionProcessing({
      forceReprocess: body.forceReprocess === true,
      maxDocuments: typeof body.maxDocuments === 'number' ? body.maxDocuments : undefined,
    });
    const summaries = await refreshSummaryTabs();
    const finishedAt = new Date().toISOString();
    const run: RunState = {
      run_id: id,
      started_at: startedAt,
      finished_at: finishedAt,
      status: processing.sourcesErrored > 0 ? 'partial_success' : 'success',
      files_seen: ingestion.filesSeen,
      files_processed: processing.sourcesProcessed,
      transactions_created: processing.transactionsWritten,
      review_items_created: processing.reviewItemsWritten,
      anomalies_created: summaries.anomaliesWritten,
      error_summary: processing.sourcesErrored > 0 ? String(processing.sourcesErrored) + ' source document(s) failed processing.' : null,
    };
    await upsertRows<RunState>(sheetId, 'Runs', 'run_id', [run]);

    return NextResponse.json({ ingestion, processing, summaries, run });
  } catch (error) {
    const detail = error instanceof Error ? error.message : 'Unknown error';
    if (sheetId) {
      const failedRun: RunState = {
        run_id: id,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        status: 'failed',
        files_seen: 0,
        files_processed: 0,
        transactions_created: 0,
        review_items_created: 0,
        anomalies_created: 0,
        error_summary: maskError(detail),
      };
      await upsertRows<RunState>(sheetId, 'Runs', 'run_id', [failedRun]).catch(() => undefined);
    }

    return NextResponse.json(
      {
        error: 'Workflow run failed',
        detail: maskError(detail),
      },
      { status: 500 }
    );
  }
}

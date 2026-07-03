import { NextRequest, NextResponse } from 'next/server';
import { runPendingExtractionProcessing } from '../../../lib/orchestrator/process';
import { safeErrorDetail } from '../../../lib/privacy/redact';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const result = await runPendingExtractionProcessing({
      forceReprocess: body.forceReprocess === true,
      maxDocuments: typeof body.maxDocuments === 'number' ? body.maxDocuments : undefined,
    });

    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Processing run failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

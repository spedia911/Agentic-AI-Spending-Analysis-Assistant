import { NextRequest, NextResponse } from 'next/server';
import { runIngestion } from '../../../lib/orchestrator/ingest';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const result = await runIngestion({ forceReprocess: body.forceReprocess === true });

    return NextResponse.json({
      sheetId: result.sheetId,
      newDocuments: result.newDocuments.length,
      skippedDocuments: result.skippedDocuments.length,
      errorDocuments: result.errorDocuments.length,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Ingestion run failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

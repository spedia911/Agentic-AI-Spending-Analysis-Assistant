import { NextResponse } from 'next/server';
import { refreshSummaryTabs } from '../../../../lib/orchestrator/summarize';

export async function POST() {
  try {
    return NextResponse.json(await refreshSummaryTabs());
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Summary refresh failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

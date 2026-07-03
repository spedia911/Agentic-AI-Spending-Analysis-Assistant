import { NextResponse } from 'next/server';
import { refreshSummaryTabs } from '../../../../lib/orchestrator/summarize';
import { safeErrorDetail } from '../../../../lib/privacy/redact';

export async function POST() {
  try {
    return NextResponse.json(await refreshSummaryTabs());
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Summary refresh failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

import { NextResponse } from 'next/server';
import { clearDashboardDataCache } from '../../../../lib/dashboard/data';
import { refreshSummaryTabs } from '../../../../lib/orchestrator/summarize';
import { safeErrorDetail } from '../../../../lib/privacy/redact';

export async function POST() {
  try {
    const result = await refreshSummaryTabs();
    clearDashboardDataCache();
    return NextResponse.json(result);
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

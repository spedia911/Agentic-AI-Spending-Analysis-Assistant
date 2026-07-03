import { NextRequest, NextResponse } from 'next/server';
import { resolveAnomaly, type AnomalyResolutionDecision } from '../../../../lib/anomalies';
import { clearDashboardDataCache } from '../../../../lib/dashboard/data';
import { safeErrorDetail } from '../../../../lib/privacy/redact';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const decision = String(body.decision ?? '') as AnomalyResolutionDecision;
    const result = await resolveAnomaly({
      anomalyId: String(body.anomalyId ?? ''),
      decision,
      duplicateTransactionId: typeof body.duplicateTransactionId === 'string' ? body.duplicateTransactionId : undefined,
    });
    clearDashboardDataCache();

    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Anomaly resolution failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

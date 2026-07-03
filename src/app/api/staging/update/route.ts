import { NextRequest, NextResponse } from 'next/server';
import { updateSnapshotReviewStage } from '../../../../lib/staging/snapshot-review';
import { safeErrorDetail } from '../../../../lib/privacy/redact';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const stage = await updateSnapshotReviewStage({
      stageId: String(body.stageId ?? ''),
      snapshots: Array.isArray(body.snapshots) ? body.snapshots : [],
      transactions: Array.isArray(body.transactions) ? body.transactions : [],
    });
    return NextResponse.json({ stage });
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Snapshot review update failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

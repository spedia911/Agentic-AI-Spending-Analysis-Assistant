import { NextRequest, NextResponse } from 'next/server';
import { commitSnapshotReviewStage } from '../../../../lib/staging/snapshot-review';
import { safeErrorDetail } from '../../../../lib/privacy/redact';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const result = await commitSnapshotReviewStage(String(body.stageId ?? ''));
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Snapshot review commit failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

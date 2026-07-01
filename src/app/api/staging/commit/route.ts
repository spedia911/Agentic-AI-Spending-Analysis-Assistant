import { NextRequest, NextResponse } from 'next/server';
import { commitSnapshotReviewStage } from '../../../../lib/staging/snapshot-review';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const result = await commitSnapshotReviewStage(String(body.stageId ?? ''));
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Snapshot review commit failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

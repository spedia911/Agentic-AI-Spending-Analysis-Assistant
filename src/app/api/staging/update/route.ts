import { NextRequest, NextResponse } from 'next/server';
import { updateSnapshotReviewStage } from '../../../../lib/staging/snapshot-review';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const stage = await updateSnapshotReviewStage({
      stageId: String(body.stageId ?? ''),
      transactions: Array.isArray(body.transactions) ? body.transactions : [],
    });
    return NextResponse.json({ stage });
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Snapshot review update failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

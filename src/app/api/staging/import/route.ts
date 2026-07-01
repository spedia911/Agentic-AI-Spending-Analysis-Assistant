import { NextRequest, NextResponse } from 'next/server';
import { importSnapshotsForReview, readSnapshotReviewStage } from '../../../../lib/staging/snapshot-review';

export async function GET() {
  const stage = await readSnapshotReviewStage();
  return NextResponse.json({ stage });
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const stage = await importSnapshotsForReview({
      forceReimport: body.forceReimport === true,
      maxFiles: typeof body.maxFiles === 'number' ? body.maxFiles : undefined,
    });
    return NextResponse.json({ stage });
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Snapshot import failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

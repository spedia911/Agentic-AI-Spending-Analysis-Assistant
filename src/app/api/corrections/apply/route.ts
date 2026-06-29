import { NextRequest, NextResponse } from 'next/server';
import { applyReviewCorrection } from '../../../../lib/corrections';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const result = await applyReviewCorrection({
      reviewItemId: body.reviewItemId,
      fieldName: body.fieldName,
      newValue: body.newValue,
      applyFuture: body.applyFuture === true,
    });

    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Correction application failed',
        detail: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

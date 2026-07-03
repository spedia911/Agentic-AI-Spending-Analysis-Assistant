import { NextRequest, NextResponse } from 'next/server';
import { applyReviewCorrection } from '../../../../lib/corrections';
import { safeErrorDetail } from '../../../../lib/privacy/redact';

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
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

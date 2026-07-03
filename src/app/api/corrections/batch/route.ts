import { NextRequest, NextResponse } from 'next/server';
import { applyBatchCorrections } from '../../../../lib/corrections';
import { safeErrorDetail } from '../../../../lib/privacy/redact';

type BatchCorrectionRequestItem = {
  reviewItemId?: unknown;
  transactionId?: unknown;
  fieldName?: unknown;
  newValue?: unknown;
  applyFuture?: unknown;
};

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const corrections = Array.isArray(body.corrections) ? body.corrections : [];

    if (corrections.length === 0) {
      return NextResponse.json(
        {
          error: 'No corrections selected',
          detail: 'Select at least one correction before applying.',
        },
        { status: 400 }
      );
    }

    const result = await applyBatchCorrections({
      corrections: corrections.map((item: BatchCorrectionRequestItem) => ({
        reviewItemId: typeof item.reviewItemId === 'string' ? item.reviewItemId : undefined,
        transactionId: typeof item.transactionId === 'string' ? item.transactionId : undefined,
        fieldName: item.fieldName,
        newValue: String(item.newValue ?? ''),
        applyFuture: item.applyFuture === true,
      })),
    });

    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Batch correction failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

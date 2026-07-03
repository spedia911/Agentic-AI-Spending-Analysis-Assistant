import { NextResponse } from 'next/server';
import { runSetupHealthCheck } from '../../../../lib/setup';

export async function GET() {
  const report = await runSetupHealthCheck();
  return NextResponse.json(report, { status: report.status === 'error' ? 500 : 200 });
}

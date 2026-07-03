import fs from 'fs/promises';
import { NextRequest } from 'next/server';
import { canViewDashboard } from '../../../../../lib/dashboard';
import { getEnv } from '../../../../../lib/env';
import { initializeSpreadsheet, readRows } from '../../../../../lib/google/sheets';
import { safeErrorDetail } from '../../../../../lib/privacy/redact';
import { getCachedSourceImage } from '../../../../../lib/source-evidence/cache';
import type { SourceDocument } from '../../../../../types/domain';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest, { params }: { params: Promise<{ sourceDocumentId: string }> }) {
  const env = getEnv();
  const email = request.nextUrl.searchParams.get('email') ?? undefined;
  if (!canViewDashboard(email, env.SINGLE_USER_EMAIL)) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const { sourceDocumentId } = await params;
    const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
    const sourceDocuments = await readRows<SourceDocument>(sheetId, 'SourceDocuments');
    const source = sourceDocuments.find((item) => item.source_document_id === sourceDocumentId);

    if (!source) {
      return Response.json({ error: 'Source document not found' }, { status: 404 });
    }

    const cached = await getCachedSourceImage(source);
    if (!cached.exists) {
      return Response.json({ error: 'Cached source image not available' }, { status: 404 });
    }

    const bytes = await fs.readFile(cached.path);
    return new Response(new Uint8Array(bytes), {
      headers: {
        'Cache-Control': 'private, no-store',
        'Content-Type': cached.mimeType,
      },
    });
  } catch (error) {
    return Response.json(
      {
        error: 'Source image failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

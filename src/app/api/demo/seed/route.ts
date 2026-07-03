import { NextResponse } from 'next/server';
import { getEnv } from '../../../../lib/env';
import { initializeSpreadsheet, upsertRows } from '../../../../lib/google/sheets';
import { refreshSummaryTabs } from '../../../../lib/orchestrator/summarize';
import { safeErrorDetail } from '../../../../lib/privacy/redact';
import type { AssetSnapshot, ReviewItem, SourceDocument, Transaction } from '../../../../types/domain';

const now = '2026-06-29T10:00:00Z';

function transaction(id: string, month: string, day: string, merchant: string, amount: number, category: string): Transaction {
  return {
    transaction_id: id,
    source_document_id: 'demo-source-1',
    observed_month: month,
    transaction_date: month + '-' + day,
    merchant_raw: merchant,
    merchant_normalized: merchant,
    amount,
    transaction_type: 'expense',
    account_label: 'Demo Visa *1234',
    category,
    category_confidence: 0.95,
    extraction_confidence: 0.96,
    validation_status: 'valid',
    review_status: 'none',
    evidence_text: 'Demo sanitized evidence for ' + merchant,
    created_at: now,
    updated_at: now,
  };
}

function snapshot(id: string, month: string, balance: number): AssetSnapshot {
  return {
    asset_snapshot_id: id,
    source_document_id: 'demo-source-2',
    observed_month: month,
    observed_date: month + '-28',
    account_label: 'Demo Checking *6789',
    balance,
    balance_type: 'checking',
    confidence: 0.96,
    evidence_text: 'Demo sanitized balance evidence',
    created_at: now,
  };
}

export async function POST() {
  try {
    const env = getEnv();
    const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
    const sourceDocuments: SourceDocument[] = [
      {
        source_document_id: 'demo-source-1',
        source_type: 'upload',
        file_name: 'demo-credit-card-screenshot.png',
        mime_type: 'image/png',
        created_time: now,
        modified_time: now,
        processed_at: now,
        status: 'processed',
        error_summary: null,
      },
      {
        source_document_id: 'demo-source-2',
        source_type: 'upload',
        file_name: 'demo-bank-balance-screenshot.png',
        mime_type: 'image/png',
        created_time: now,
        modified_time: now,
        processed_at: now,
        status: 'processed',
        error_summary: null,
      },
    ];
    const transactions: Transaction[] = [
      transaction('demo-txn-1', '2026-05', '05', 'Trader Joes', 86.34, 'groceries'),
      transaction('demo-txn-2', '2026-05', '12', 'Netflix', 19.99, 'subscriptions'),
      transaction('demo-txn-3', '2026-06', '02', 'Trader Joes', 112.28, 'groceries'),
      transaction('demo-txn-4', '2026-06', '07', 'Metro Transit', 48.0, 'transportation'),
      {
        ...transaction('demo-txn-5', '2026-06', '12', 'Amazon Marketplace', 240.0, 'shopping'),
        category_confidence: 0.62,
        validation_status: 'needs_review',
        review_status: 'pending',
      },
      transaction('demo-txn-6', '2026-06', '13', 'Amazon Marketplace', 240.0, 'shopping'),
    ];
    const assetSnapshots: AssetSnapshot[] = [
      snapshot('demo-asset-1', '2026-05', 4200),
      snapshot('demo-asset-2', '2026-06', 3500),
    ];
    const reviewItems: ReviewItem[] = [
      {
        review_item_id: 'demo-review-1',
        target_type: 'transaction',
        target_id: 'demo-txn-5',
        issue_type: 'unclear_category',
        severity: 'medium',
        question: 'Amazon Marketplace can be groceries, shopping, or household. Which category should this charge use?',
        suggested_options: ['groceries', 'shopping', 'miscellaneous'],
        status: 'pending',
        user_answer: null,
        created_at: now,
        resolved_at: null,
      },
    ];

    await upsertRows<SourceDocument>(sheetId, 'SourceDocuments', 'source_document_id', sourceDocuments);
    await upsertRows<Transaction>(sheetId, 'Transactions', 'transaction_id', transactions);
    await upsertRows<AssetSnapshot>(sheetId, 'AssetSnapshots', 'asset_snapshot_id', assetSnapshots);
    await upsertRows<ReviewItem>(sheetId, 'ReviewQueue', 'review_item_id', reviewItems);
    const summaries = await refreshSummaryTabs();

    return NextResponse.json({
      sheetId,
      sourceDocuments: sourceDocuments.length,
      transactions: transactions.length,
      assetSnapshots: assetSnapshots.length,
      reviewItems: reviewItems.length,
      summaries,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: 'Demo seed failed',
        detail: safeErrorDetail(error),
      },
      { status: 500 }
    );
  }
}

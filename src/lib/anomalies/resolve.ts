import crypto from 'crypto';
import { getEnv } from '../env';
import { initializeSpreadsheet, readRows, upsertRows } from '../google/sheets';
import { refreshSummaryTabs, type RefreshSummariesResult } from '../orchestrator/summarize';
import type { Anomaly, Correction, Transaction } from '../../types/domain';

export type AnomalyResolutionDecision = 'resolved' | 'ignored' | 'mark_duplicate';

export interface ResolveAnomalyInput {
  anomalyId: string;
  decision: AnomalyResolutionDecision;
  duplicateTransactionId?: string;
  now?: string;
}

export interface ResolveAnomalyResult {
  sheetId: string;
  anomalyUpdated: boolean;
  transactionUpdated: boolean;
  correctionsWritten: number;
  summaries: RefreshSummariesResult | null;
}

function stableHash(parts: Array<string | number | null | undefined>): string {
  return crypto
    .createHash('sha256')
    .update(parts.map((part) => String(part ?? '')).join('|'))
    .digest('hex')
    .slice(0, 16);
}

function decisionStatus(decision: AnomalyResolutionDecision): Anomaly['status'] {
  return decision === 'ignored' ? 'ignored' : 'resolved';
}

export async function resolveAnomaly(input: ResolveAnomalyInput): Promise<ResolveAnomalyResult> {
  const env = getEnv();
  const now = input.now ?? new Date().toISOString();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const anomalies = await readRows<Anomaly>(sheetId, 'Anomalies');
  const anomaly = anomalies.find((item) => item.anomaly_id === input.anomalyId);
  if (!anomaly) {
    throw new Error('Anomaly not found: ' + input.anomalyId);
  }
  if (!['resolved', 'ignored', 'mark_duplicate'].includes(input.decision)) {
    throw new Error('Unsupported anomaly decision: ' + input.decision);
  }

  const updatedAnomaly: Anomaly = {
    ...anomaly,
    status: decisionStatus(input.decision),
  };
  const corrections: Correction[] = [
    {
      correction_id: 'correction_' + stableHash([anomaly.anomaly_id, 'anomaly_status', input.decision]),
      target_type: 'anomaly',
      target_id: anomaly.anomaly_id,
      field_name: 'anomaly_status',
      old_value: anomaly.status,
      new_value: updatedAnomaly.status,
      apply_future: false,
      created_at: now,
    },
  ];

  let updatedTransaction: Transaction | null = null;
  if (input.decision === 'mark_duplicate') {
    if (!input.duplicateTransactionId) {
      throw new Error('Choose which duplicate transaction to exclude.');
    }
    if (!anomaly.related_record_ids.includes(input.duplicateTransactionId)) {
      throw new Error('Selected transaction is not related to this anomaly.');
    }
    const transactions = await readRows<Transaction>(sheetId, 'Transactions');
    const transaction = transactions.find((item) => item.transaction_id === input.duplicateTransactionId);
    if (!transaction) {
      throw new Error('Transaction not found for duplicate decision: ' + input.duplicateTransactionId);
    }
    updatedTransaction = {
      ...transaction,
      validation_status: 'rejected',
      review_status: 'resolved',
      updated_at: now,
    };
    corrections.push({
      correction_id: 'correction_' + stableHash([anomaly.anomaly_id, input.duplicateTransactionId, 'validation_status', 'rejected']),
      target_type: 'transaction',
      target_id: input.duplicateTransactionId,
      field_name: 'validation_status',
      old_value: transaction.validation_status,
      new_value: 'rejected',
      apply_future: false,
      created_at: now,
    });
  }

  await upsertRows<Anomaly>(sheetId, 'Anomalies', 'anomaly_id', [updatedAnomaly]);
  if (updatedTransaction) {
    await upsertRows<Transaction>(sheetId, 'Transactions', 'transaction_id', [updatedTransaction]);
  }
  await upsertRows<Correction>(sheetId, 'Corrections', 'correction_id', corrections);
  const summaries = input.decision === 'mark_duplicate' ? await refreshSummaryTabs() : null;

  return {
    sheetId,
    anomalyUpdated: true,
    transactionUpdated: updatedTransaction !== null,
    correctionsWritten: corrections.length,
    summaries,
  };
}

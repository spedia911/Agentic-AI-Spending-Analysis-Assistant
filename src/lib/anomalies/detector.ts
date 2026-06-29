import crypto from 'crypto';
import type { Anomaly, AssetTrend, MonthlySummary, Transaction } from '../../types/domain';

export interface AnomalyGenerationContext {
  now?: string;
  spendingSpikeRatio?: number;
  duplicateLookbackDays?: number;
}

function stableHash(parts: Array<string | number | null | undefined>): string {
  return crypto
    .createHash('sha256')
    .update(parts.map((part) => String(part ?? '')).join('|'))
    .digest('hex')
    .slice(0, 16);
}

function makeAnomaly(input: Omit<Anomaly, 'anomaly_id' | 'status' | 'created_at'>, now: string): Anomaly {
  return {
    anomaly_id: 'anomaly_' + stableHash([input.anomaly_type, input.month, input.summary, input.related_record_ids.join(',')]),
    status: 'open',
    created_at: now,
    ...input,
  };
}

function dateDistanceDays(left: string, right: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(left) || !/^\d{4}-\d{2}-\d{2}$/.test(right)) return null;
  return Math.abs(new Date(left + 'T00:00:00Z').getTime() - new Date(right + 'T00:00:00Z').getTime()) / 86_400_000;
}

function merchantKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function detectDuplicateChargeAnomalies(transactions: Transaction[], now: string, lookbackDays: number): Anomaly[] {
  const anomalies: Anomaly[] = [];
  const usable = transactions.filter((transaction) => transaction.validation_status !== 'rejected');

  for (let i = 0; i < usable.length; i++) {
    for (let j = i + 1; j < usable.length; j++) {
      const left = usable[i];
      const right = usable[j];
      const distance = dateDistanceDays(left.transaction_date, right.transaction_date);
      if (
        merchantKey(left.merchant_normalized) === merchantKey(right.merchant_normalized) &&
        Math.abs(left.amount - right.amount) < 0.01 &&
        distance !== null &&
        distance <= lookbackDays
      ) {
        anomalies.push(
          makeAnomaly(
            {
              anomaly_type: 'duplicate_charge',
              severity: 'medium',
              month: left.observed_month || right.observed_month,
              related_record_ids: [left.transaction_id, right.transaction_id],
              summary: 'Possible duplicate charge at ' + left.merchant_normalized + ' for ' + Math.abs(left.amount).toFixed(2) + '.',
              suggested_action: 'Review both transactions and mark one as duplicate if only one charge is real.',
            },
            now
          )
        );
      }
    }
  }

  return anomalies;
}

export function detectSpendingSpikeAnomalies(monthlySummaries: MonthlySummary[], now: string, ratio: number): Anomaly[] {
  const anomalies: Anomaly[] = [];
  const byCategory = new Map<string, MonthlySummary[]>();
  for (const row of monthlySummaries) {
    byCategory.set(row.category, [...(byCategory.get(row.category) ?? []), row]);
  }

  for (const [category, rows] of byCategory) {
    const sorted = rows.sort((a, b) => a.month.localeCompare(b.month));
    for (let i = 1; i < sorted.length; i++) {
      const prior = sorted[i - 1];
      const current = sorted[i];
      if (prior.total_amount > 0 && current.total_amount / prior.total_amount >= ratio) {
        anomalies.push(
          makeAnomaly(
            {
              anomaly_type: 'spending_spike',
              severity: current.total_amount / prior.total_amount >= ratio * 1.5 ? 'high' : 'medium',
              month: current.month,
              related_record_ids: [current.month + ':' + category],
              summary: category + ' spending increased from ' + prior.total_amount.toFixed(2) + ' to ' + current.total_amount.toFixed(2) + '.',
              suggested_action: 'Review the largest ' + category + ' transactions for this month.',
            },
            now
          )
        );
      }
    }
  }

  return anomalies;
}

export function detectBalanceDropAnomalies(assetTrends: AssetTrend[], now: string): Anomaly[] {
  return assetTrends
    .filter((trend) => trend.maintainability_flag === 'watch' || trend.maintainability_flag === 'concern')
    .map((trend) =>
      makeAnomaly(
        {
          anomaly_type: 'balance_drop',
          severity: trend.maintainability_flag === 'concern' ? 'high' : 'medium',
          month: trend.month,
          related_record_ids: [trend.month + ':' + trend.account_label],
          summary: trend.account_label + ' balance changed by ' + trend.monthly_change.toFixed(2) + ' while spending was ' + trend.related_spending_total.toFixed(2) + '.',
          suggested_action: 'Check whether this balance drop is expected and whether spending should be adjusted.',
        },
        now
      )
    );
}

export function detectMissingMonthAnomalies(monthlySummaries: MonthlySummary[], now: string): Anomaly[] {
  const months = Array.from(new Set(monthlySummaries.map((row) => row.month))).sort();
  const anomalies: Anomaly[] = [];
  for (let i = 1; i < months.length; i++) {
    const previous = new Date(months[i - 1] + '-01T00:00:00Z');
    const expected = new Date(Date.UTC(previous.getUTCFullYear(), previous.getUTCMonth() + 1, 1)).toISOString().slice(0, 7);
    if (months[i] !== expected) {
      anomalies.push(
        makeAnomaly(
          {
            anomaly_type: 'missing_data',
            severity: 'low',
            month: expected,
            related_record_ids: [],
            summary: 'No monthly summary rows were found for ' + expected + '.',
            suggested_action: 'Confirm whether screenshots for this month are missing or still unprocessed.',
          },
          now
        )
      );
    }
  }
  return anomalies;
}

export function generateAnomalies(
  transactions: Transaction[],
  monthlySummaries: MonthlySummary[],
  assetTrends: AssetTrend[],
  context: AnomalyGenerationContext = {}
): Anomaly[] {
  const now = context.now ?? new Date().toISOString();
  return [
    ...detectDuplicateChargeAnomalies(transactions, now, context.duplicateLookbackDays ?? 3),
    ...detectSpendingSpikeAnomalies(monthlySummaries, now, context.spendingSpikeRatio ?? 2),
    ...detectBalanceDropAnomalies(assetTrends, now),
    ...detectMissingMonthAnomalies(monthlySummaries, now),
  ];
}

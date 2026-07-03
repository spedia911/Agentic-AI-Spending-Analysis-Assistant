import { getEnv } from '../env';
import { initializeSpreadsheet, replaceRows, readRows } from '../google/sheets';
import { generateAnomalies } from '../anomalies';
import { generateSummaries } from '../summaries';
import type { Anomaly, AssetSnapshot, AssetTrend, CashFlowSummary, MonthlySummary, QuarterlySummary, Transaction } from '../../types/domain';

export interface RefreshSummariesResult {
  sheetId: string;
  monthlyRowsWritten: number;
  quarterlyRowsWritten: number;
  cashFlowRowsWritten: number;
  assetTrendRowsWritten: number;
  anomaliesWritten: number;
}

export function preserveAnomalyDecisions(generated: Anomaly[], existing: Anomaly[]): Anomaly[] {
  const existingById = new Map(existing.map((anomaly) => [anomaly.anomaly_id, anomaly]));
  return generated.map((anomaly) => {
    const previous = existingById.get(anomaly.anomaly_id);
    if (!previous) return anomaly;
    return {
      ...anomaly,
      status: previous.status,
      created_at: previous.created_at || anomaly.created_at,
    };
  });
}

export async function refreshSummaryTabs(): Promise<RefreshSummariesResult> {
  const env = getEnv();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const transactions = await readRows<Transaction>(sheetId, 'Transactions');
  const assetSnapshots = await readRows<AssetSnapshot>(sheetId, 'AssetSnapshots');
  const existingAnomalies = await readRows<Anomaly>(sheetId, 'Anomalies');
  const summaries = generateSummaries(transactions, assetSnapshots);
  const anomalies = preserveAnomalyDecisions(
    generateAnomalies(transactions, summaries.monthlySummaries, summaries.assetTrends),
    existingAnomalies
  );

  await replaceRows<MonthlySummary>(sheetId, 'MonthlySummary', summaries.monthlySummaries);
  await replaceRows<QuarterlySummary>(sheetId, 'QuarterlySummary', summaries.quarterlySummaries);
  await replaceRows<CashFlowSummary>(sheetId, 'CashFlowSummary', summaries.cashFlowSummaries);
  await replaceRows<AssetTrend>(sheetId, 'AssetTrends', summaries.assetTrends);
  await replaceRows<Anomaly>(sheetId, 'Anomalies', anomalies);

  return {
    sheetId,
    monthlyRowsWritten: summaries.monthlySummaries.length,
    quarterlyRowsWritten: summaries.quarterlySummaries.length,
    cashFlowRowsWritten: summaries.cashFlowSummaries.length,
    assetTrendRowsWritten: summaries.assetTrends.length,
    anomaliesWritten: anomalies.length,
  };
}

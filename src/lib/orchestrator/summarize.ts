import { getEnv } from '../env';
import { initializeSpreadsheet, replaceRows, readRows } from '../google/sheets';
import { generateAnomalies } from '../anomalies';
import { generateSummaries } from '../summaries';
import type { Anomaly, AssetSnapshot, AssetTrend, MonthlySummary, QuarterlySummary, Transaction } from '../../types/domain';

export interface RefreshSummariesResult {
  sheetId: string;
  monthlyRowsWritten: number;
  quarterlyRowsWritten: number;
  assetTrendRowsWritten: number;
  anomaliesWritten: number;
}

export async function refreshSummaryTabs(): Promise<RefreshSummariesResult> {
  const env = getEnv();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const transactions = await readRows<Transaction>(sheetId, 'Transactions');
  const assetSnapshots = await readRows<AssetSnapshot>(sheetId, 'AssetSnapshots');
  const summaries = generateSummaries(transactions, assetSnapshots);
  const anomalies = generateAnomalies(transactions, summaries.monthlySummaries, summaries.assetTrends);

  await replaceRows<MonthlySummary>(sheetId, 'MonthlySummary', summaries.monthlySummaries);
  await replaceRows<QuarterlySummary>(sheetId, 'QuarterlySummary', summaries.quarterlySummaries);
  await replaceRows<AssetTrend>(sheetId, 'AssetTrends', summaries.assetTrends);
  await replaceRows<Anomaly>(sheetId, 'Anomalies', anomalies);

  return {
    sheetId,
    monthlyRowsWritten: summaries.monthlySummaries.length,
    quarterlyRowsWritten: summaries.quarterlySummaries.length,
    assetTrendRowsWritten: summaries.assetTrends.length,
    anomaliesWritten: anomalies.length,
  };
}

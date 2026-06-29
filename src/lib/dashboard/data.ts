import { getEnv } from '../env';
import { initializeSpreadsheet, readRows } from '../google/sheets';
import type { Anomaly, AssetTrend, MonthlySummary, QuarterlySummary, ReviewItem } from '../../types/domain';

export interface DashboardData {
  sheetId: string;
  monthlySummaries: MonthlySummary[];
  quarterlySummaries: QuarterlySummary[];
  assetTrends: AssetTrend[];
  reviewItems: ReviewItem[];
  anomalies: Anomaly[];
}

export async function loadDashboardData(): Promise<DashboardData> {
  const env = getEnv();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const [monthlySummaries, quarterlySummaries, assetTrends, reviewItems, anomalies] = await Promise.all([
    readRows<MonthlySummary>(sheetId, 'MonthlySummary'),
    readRows<QuarterlySummary>(sheetId, 'QuarterlySummary'),
    readRows<AssetTrend>(sheetId, 'AssetTrends'),
    readRows<ReviewItem>(sheetId, 'ReviewQueue'),
    readRows<Anomaly>(sheetId, 'Anomalies'),
  ]);

  return {
    sheetId,
    monthlySummaries,
    quarterlySummaries,
    assetTrends,
    reviewItems: reviewItems.filter((item) => item.status === 'pending'),
    anomalies: anomalies.filter((item) => item.status === 'open'),
  };
}

export function canViewDashboard(requestedEmail: string | undefined, configuredEmail: string): boolean {
  return !!requestedEmail && requestedEmail.toLowerCase() === configuredEmail.toLowerCase();
}

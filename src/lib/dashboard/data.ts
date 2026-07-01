import { getEnv } from '../env';
import { initializeSpreadsheet, readRows } from '../google/sheets';
import type {
  Anomaly,
  AssetSnapshot,
  AssetTrend,
  MonthlySummary,
  QuarterlySummary,
  ReviewItem,
  RunState,
  SourceDocument,
  Transaction,
} from '../../types/domain';

export interface DashboardData {
  sheetId: string;
  transactions: Transaction[];
  assetSnapshots: AssetSnapshot[];
  sourceDocuments: SourceDocument[];
  monthlySummaries: MonthlySummary[];
  quarterlySummaries: QuarterlySummary[];
  assetTrends: AssetTrend[];
  reviewItems: ReviewItem[];
  anomalies: Anomaly[];
  runs: RunState[];
}

function cleanCategory(category: string | null | undefined): string {
  return category === 'duplicate_remove_one' ? 'miscellaneous' : category ?? 'miscellaneous';
}

export async function loadDashboardData(): Promise<DashboardData> {
  const env = getEnv();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const [transactions, assetSnapshots, sourceDocuments, monthlySummaries, quarterlySummaries, assetTrends, reviewItems, anomalies, runs] = await Promise.all([
    readRows<Transaction>(sheetId, 'Transactions'),
    readRows<AssetSnapshot>(sheetId, 'AssetSnapshots'),
    readRows<SourceDocument>(sheetId, 'SourceDocuments'),
    readRows<MonthlySummary>(sheetId, 'MonthlySummary'),
    readRows<QuarterlySummary>(sheetId, 'QuarterlySummary'),
    readRows<AssetTrend>(sheetId, 'AssetTrends'),
    readRows<ReviewItem>(sheetId, 'ReviewQueue'),
    readRows<Anomaly>(sheetId, 'Anomalies'),
    readRows<RunState>(sheetId, 'Runs'),
  ]);

  return {
    sheetId,
    transactions: transactions.map((transaction) => ({
      ...transaction,
      category: cleanCategory(transaction.category),
    })),
    assetSnapshots,
    sourceDocuments,
    monthlySummaries: monthlySummaries.map((row) => ({
      ...row,
      category: cleanCategory(row.category),
    })),
    quarterlySummaries: quarterlySummaries.map((row) => ({
      ...row,
      category: cleanCategory(row.category),
    })),
    assetTrends,
    reviewItems: reviewItems.filter((item) => item.status === 'pending'),
    anomalies: anomalies.filter((item) => item.status === 'open'),
    runs,
  };
}

export function canViewDashboard(requestedEmail: string | undefined, configuredEmail: string): boolean {
  return !!requestedEmail && requestedEmail.toLowerCase() === configuredEmail.toLowerCase();
}

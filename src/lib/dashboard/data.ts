import { getEnv } from '../env';
import { initializeSpreadsheet, readRows } from '../google/sheets';
import type {
  Anomaly,
  AssetSnapshot,
  AssetTrend,
  CashFlowSummary,
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
  cashFlowSummaries: CashFlowSummary[];
  reviewItems: ReviewItem[];
  anomalies: Anomaly[];
  runs: RunState[];
}

const DASHBOARD_CACHE_TTL_MS = 30_000;
let dashboardCache: { expiresAt: number; data: DashboardData } | null = null;
let dashboardLoadInFlight: Promise<DashboardData> | null = null;

function cleanCategory(category: string | null | undefined): string {
  const value = category?.trim();
  if (!value || value === 'duplicate_remove_one') return 'miscellaneous';
  return value;
}

async function loadDashboardDataFresh(): Promise<DashboardData> {
  const env = getEnv();
  const sheetId = await initializeSpreadsheet(env.GOOGLE_SHEET_ID);
  const [transactions, assetSnapshots, sourceDocuments, monthlySummaries, quarterlySummaries, cashFlowSummaries, assetTrends, reviewItems, anomalies, runs] = await Promise.all([
    readRows<Transaction>(sheetId, 'Transactions'),
    readRows<AssetSnapshot>(sheetId, 'AssetSnapshots'),
    readRows<SourceDocument>(sheetId, 'SourceDocuments'),
    readRows<MonthlySummary>(sheetId, 'MonthlySummary'),
    readRows<QuarterlySummary>(sheetId, 'QuarterlySummary'),
    readRows<CashFlowSummary>(sheetId, 'CashFlowSummary'),
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
    cashFlowSummaries,
    assetTrends,
    reviewItems: reviewItems.filter((item) => item.status === 'pending'),
    anomalies: anomalies.filter((item) => item.status === 'open'),
    runs,
  };
}

export function clearDashboardDataCache(): void {
  dashboardCache = null;
  dashboardLoadInFlight = null;
}

export async function loadDashboardData(options: { refresh?: boolean } = {}): Promise<DashboardData> {
  const now = Date.now();
  if (!options.refresh && dashboardCache && dashboardCache.expiresAt > now) {
    return dashboardCache.data;
  }

  if (!options.refresh && dashboardLoadInFlight) {
    return dashboardLoadInFlight;
  }

  dashboardLoadInFlight = loadDashboardDataFresh()
    .then((data) => {
      dashboardCache = {
        data,
        expiresAt: Date.now() + DASHBOARD_CACHE_TTL_MS,
      };
      return data;
    })
    .finally(() => {
      dashboardLoadInFlight = null;
    });

  return dashboardLoadInFlight;
}

export function canViewDashboard(requestedEmail: string | undefined, configuredEmail: string): boolean {
  return !!requestedEmail && requestedEmail.toLowerCase() === configuredEmail.toLowerCase();
}

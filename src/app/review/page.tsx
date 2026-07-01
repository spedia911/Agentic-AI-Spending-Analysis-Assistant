import Link from 'next/link';
import { getEnv } from '../../lib/env';
import { canViewDashboard, loadDashboardData } from '../../lib/dashboard';
import ReviewWorkbench from './review-workbench';
import styles from '../page.module.css';

export const dynamic = 'force-dynamic';

export default async function ReviewPage({ searchParams }: { searchParams?: Promise<{ email?: string }> }) {
  const env = getEnv();
  const params = await searchParams;
  const email = params?.email;

  if (!canViewDashboard(email, env.SINGLE_USER_EMAIL)) {
    return (
      <main className={styles.pageShell}>
        <section className={styles.accessPanel}>
          <h1>Review Corrections</h1>
          <p>Enter the configured user email as a query parameter to review corrections.</p>
          <code>?email={env.SINGLE_USER_EMAIL}</code>
        </section>
      </main>
    );
  }

  let data;
  try {
    data = await loadDashboardData();
  } catch (error) {
    return (
      <main className={styles.pageShell}>
        <section className={styles.accessPanel}>
          <p className={styles.eyebrow}>Review unavailable</p>
          <h1>Review Corrections</h1>
          <p>Unable to read the configured Google Sheet. Check the Sheet ID and sharing, then refresh this page.</p>
          <code>{error instanceof Error ? error.message : 'Unknown review error'}</code>
        </section>
      </main>
    );
  }

  return (
    <main className={styles.pageShell}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>Correction workbench</p>
          <h1>Review Corrections</h1>
        </div>
        <Link className={styles.secondaryLink} href={'/?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL)}>
          Back to dashboard
        </Link>
      </header>

      <ReviewWorkbench
        assetSnapshots={data.assetSnapshots}
        pendingReviews={data.reviewItems}
        transactions={data.transactions}
      />
    </main>
  );
}

import Link from 'next/link';
import { getEnv } from '../../lib/env';
import { canViewDashboard } from '../../lib/dashboard';
import { readSnapshotReviewStage } from '../../lib/staging/snapshot-review';
import ImportReviewClient from './snapshot-import-client';
import styles from '../page.module.css';

export const dynamic = 'force-dynamic';

export default async function ImportPage({ searchParams }: { searchParams?: Promise<{ email?: string }> }) {
  const env = getEnv();
  const params = await searchParams;
  const email = params?.email;

  if (!canViewDashboard(email, env.SINGLE_USER_EMAIL)) {
    return (
      <main className={styles.pageShell}>
        <section className={styles.accessPanel}>
          <h1>Import Snapshots</h1>
          <p>Enter the configured user email as a query parameter to import snapshots.</p>
          <code>?email={env.SINGLE_USER_EMAIL}</code>
        </section>
      </main>
    );
  }

  const stage = await readSnapshotReviewStage();

  return (
    <main className={styles.pageShell}>
      <header className={styles.header}>
        <div>
          <p className={styles.eyebrow}>Pre-Sheets review</p>
          <h1>Import Snapshots</h1>
        </div>
        <Link className={styles.secondaryLink} href={'/?email=' + encodeURIComponent(env.SINGLE_USER_EMAIL)}>
          Back to dashboard
        </Link>
      </header>

      <ImportReviewClient initialStage={stage} />
    </main>
  );
}

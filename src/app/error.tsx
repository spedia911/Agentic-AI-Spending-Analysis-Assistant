'use client';

import styles from './page.module.css';

export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <main className={styles.pageShell}>
      <section className={styles.accessPanel}>
        <p className={styles.eyebrow}>Dashboard error</p>
        <h1>Spending Analysis</h1>
        <p>The dashboard hit an unexpected problem while loading.</p>
        <code>{error.message}</code>
        <div className={styles.statusActions}>
          <button type="button" onClick={reset}>Try again</button>
        </div>
      </section>
    </main>
  );
}

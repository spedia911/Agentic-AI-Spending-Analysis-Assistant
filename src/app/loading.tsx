import styles from './page.module.css';

export default function Loading() {
  return (
    <main className={styles.pageShell}>
      <section className={styles.accessPanel}>
        <p className={styles.eyebrow}>Loading dashboard</p>
        <h1>Spending Analysis</h1>
        <p>Reading the latest summaries, reviews, and anomaly checks from Google Sheets.</p>
      </section>
    </main>
  );
}

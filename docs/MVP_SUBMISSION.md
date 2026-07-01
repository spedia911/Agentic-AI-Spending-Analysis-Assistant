# MVP Submission Notes

This project is ready to present as a Drive-first MVP for an individual-only agentic spending analysis assistant.

Current development phase: the Drive-first MVP backend is working, and the first assistant-grade dashboard UX slice is implemented. The dashboard now includes workflow controls, staged snapshot import review, a focused spending explorer with pie-chart/category/table filters, inline transaction cleanup, a dedicated batch correction page, month-only transaction updates, asset snapshot review handling, and clearer spending versus income summaries. Remaining next-phase work includes anomaly resolution, richer source evidence navigation, source-document review handling, and guided first-time setup.

## What the Demo Shows

1. A configured Google Drive folder acts as the screenshot inbox.
2. The workflow discovers supported financial screenshots, skips unsupported files, and avoids duplicate processing unless forced.
3. Vision extraction converts screenshot evidence into transaction and asset candidates.
4. Normalization, validation, categorization, and review routing turn imperfect extraction output into auditable rows.
5. Google Sheets stores source documents, transactions, asset snapshots, review items, corrections, summaries, and anomalies.
6. The single-user dashboard displays spending charts, a category pie chart, filterable spending tables, inline spending cleanup, and asset context.
7. The workflow writes a `Runs` row so each guided run has auditable status, Drive files-seen count, output counts, and a masked error summary when needed.
8. The review workflow can resolve transaction corrections and asset snapshot reviews without manual Sheet editing.

## Fast Reviewer Path

Use the sanitized seed path when live Drive credentials or private screenshots are not available during review. The seed creates spending rows, asset snapshots, duplicate/balance-drop anomaly inputs, and one pending review item.

1. Start the app.

   ```bash
   npm run dev
   ```

2. Seed demo data into the configured Google Sheet.

   ```bash
   curl -X POST http://localhost:3000/api/demo/seed
   ```

3. Open the dashboard.

   ```text
   http://localhost:3000?email=YOUR_CONFIGURED_EMAIL
   ```

## Full Workflow Path

Use this path when Google Drive, Google Sheets, and an AI provider are configured.

1. Put 5 to 20 financial screenshots in the configured Drive folder.
2. Start the app.
3. Run the end-to-end workflow.

   ```bash
   curl -X POST http://localhost:3000/api/workflow/run -H "Content-Type: application/json" -d "{}"
   ```

4. Open the dashboard for spending analysis, or open the Google Sheet for raw extracted rows and anomaly details.
5. Apply corrections through `/review`, Spending Explorer inline controls, `/api/corrections/apply`, or `/api/corrections/batch`; the correction workflow refreshes summaries automatically.

## MVP Scope Notes

- Google Drive is the primary ingestion source for the submitted MVP.
- Google Photos remains an optional extension because the project requirements intentionally defer it until the Drive workflow is stable.
- Source screenshots are cached only under `data/private/`, which is ignored by git and cleaned according to `SOURCE_IMAGE_RETENTION_DAYS`.
- Account labels and logs are designed to avoid full account number exposure.
- Current correction supports transaction reviews, asset snapshot reviews, staged import review, and Spending Explorer transaction cleanup. Anomaly resolution and source-document review workflows are still tracked in `docs/specs/001-mvp/tasks.md`.

## Verification Status

Current local verification passes for the submitted MVP:

- `vitest run`: 13 test files passed, 65 tests passed.
- `eslint`: zero reported issues.
- `tsc --noEmit`: zero reported diagnostics.
- `next build`: production build completes successfully, with the dashboard rendered dynamically so runtime Google and AI credentials are not required at compile time.

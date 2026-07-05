# MVP Submission Notes

This project is ready to present as a Drive-first MVP for an individual-only agentic spending analysis assistant.

For a requirement-by-requirement evidence map, see [CAPSTONE_READINESS_AUDIT.md](CAPSTONE_READINESS_AUDIT.md).
For a short reviewer script, see [DEMO_WALKTHROUGH.md](DEMO_WALKTHROUGH.md).
For final include/exclude checks before upload, see [SUBMISSION_PACKAGE_CHECKLIST.md](SUBMISSION_PACKAGE_CHECKLIST.md).
For public-link and optional hosted-demo guidance, see [DEPLOYMENT.md](DEPLOYMENT.md).
Keep paste-ready Kaggle, YouTube, and recording assets in the local-only `docs/submission/` workspace when needed. That folder is intentionally ignored by git, so the public repository depends only on the tracked reviewer docs above.

Current development phase: the Drive-first MVP backend is working, and the first assistant-grade dashboard UX slice is implemented. The dashboard now includes workflow controls with force-reprocess confirmation and per-run file limits, pre-start setup preflight, setup health checks, staged snapshot import review with source include/exclude controls, a next-best-actions summary, a focused spending explorer with pie-chart/category/table filters, inline transaction cleanup, a dedicated batch correction page, issue-type review filters, month-only transaction updates, asset snapshot review handling, source-document review handling, anomaly review actions, source-file audit visibility, source evidence pages with optional screenshot-region highlighting, durable CashFlowSummary output, tested cash-flow sign handling, and clearer spending versus income summaries.

## What the Demo Shows

1. A configured Google Drive folder acts as the screenshot inbox.
2. The workflow discovers supported financial screenshots, can process a limited batch from a crowded folder, skips unsupported files, and avoids duplicate processing unless forced.
3. The setup health check validates Drive, Sheets, AI provider/model, service-account readiness, and the single-user email gate without processing screenshots.
4. Vision extraction converts screenshot evidence into transaction and asset candidates.
5. Normalization, validation, categorization, and review routing turn imperfect extraction output into auditable rows.
6. Google Sheets stores source documents, transactions, asset snapshots, review items, corrections, category summaries, cash-flow summaries, asset trends, and anomalies.
7. The single-user dashboard displays prioritized next-best actions, spending charts, a category pie chart, generated cash-flow rows, filterable spending tables, inline spending cleanup, anomaly review cards, source-file audit rows, source evidence pages with cached screenshot previews and row-region highlights when available, and asset context.
8. The workflow writes a `Runs` row so each guided run has auditable status, Drive files-seen count, output counts, and a masked error summary when needed.
9. The review workflow can resolve transaction corrections, asset snapshot reviews, source-document reviews, and anomaly decisions without manual Sheet editing.

## Fast Reviewer Path

Use the sanitized seed path when live Drive credentials or private screenshots are not available during review. The seed creates spending rows, asset snapshots, duplicate/balance-drop anomaly inputs, and one pending review item.

1. Start the app.

   Optional first check:

   ```bash
   sh scripts/preflight.sh
   ```

   ```bash
   npm run dev
   ```

2. Open the dashboard.

   ```text
   http://localhost:3000?email=YOUR_CONFIGURED_EMAIL
   ```

3. Click **Seed demo data** in the dashboard action center to populate the configured Google Sheet.

## Full Workflow Path

Use this path when Google Drive, Google Sheets, and an AI provider are configured.

1. Put 5 to 20 financial screenshots in the configured Drive folder.
2. Start the app.
3. Run the end-to-end workflow from the dashboard action center with **Files this run** and **Run Drive workflow**.

   Developer API equivalent:

   ```bash
   curl -X POST http://localhost:3000/api/workflow/run -H "Content-Type: application/json" -d "{}"
   ```

4. Open the dashboard for spending analysis, or open the Google Sheet for raw extracted rows and anomaly details.
5. Use `/import?email=YOUR_CONFIGURED_EMAIL` when you want to stage Drive screenshots, exclude an unwanted source snapshot, and approve rows before they touch Sheets.
6. Apply corrections through `/review`, Spending Explorer inline controls, `/api/corrections/apply`, or `/api/corrections/batch`; the correction workflow refreshes summaries automatically.
7. Resolve anomaly cards from the dashboard or `/api/anomalies/resolve`; duplicate decisions can exclude one related transaction and refresh summaries.

## MVP Scope Notes

- Google Drive is the primary ingestion source for the submitted MVP.
- Google Photos remains an optional extension because the project requirements intentionally defer it until the Drive workflow is stable. The current Picker API evaluation is documented in `docs/references/google-photos-picker-evaluation.md`.
- Source screenshots are cached only under `data/private/`, which is ignored by git and cleaned according to `SOURCE_IMAGE_RETENTION_DAYS`.
- Source evidence pages can render cached local screenshots when the private cache is present and link back to the original Drive file for audit.
- Account labels and logs are designed to avoid full account number exposure.
- Current correction supports transaction reviews, asset snapshot reviews, source-document reviews, anomaly decisions, staged import review, and Spending Explorer transaction cleanup.

## Kaggle Course Concept Evidence

This project demonstrates more than three required course concepts:

| Concept | Where shown |
| --- | --- |
| Agent / multi-agent system | Modular workflow layers for ingestion, extraction, normalization, validation, categorization, correction, summary generation, anomaly review, and dashboard guidance |
| Antigravity | Development prompts in `docs/prompts/antigravity-build-prompts.md` and the video build-process section |
| Security features | `SECURITY.md`, single-user email gate, private screenshot cache, redacted API/log errors, ignored secrets and private artifacts, and tracked-file privacy checks |
| Deployability | Next.js app, `.env.example`, setup health checks, preflight script, `npm run verify`, and reproducible demo path |
| Agent skills / tool use | Google Drive folder ingestion, Google Sheets durable memory, AI vision extraction, deterministic validation, and human correction loops |

MCP Server and ADK-specific implementation are not claimed for this MVP; they are future integration options.

## Verification Status

Current local verification passes for the submitted MVP:

- `npm run verify`: full verification wrapper passes.
- `npm run verify:ci`: public repository verification wrapper passes with placeholder environment values.
- `sh scripts/privacy-check.sh`: zero tracked secrets or private artifacts.
- `vitest run`: 26 test files passed, 112 tests passed.
- `eslint`: zero reported issues.
- `tsc --noEmit`: zero reported diagnostics.
- `next build`: production build completes successfully, with the dashboard rendered dynamically so runtime Google and AI credentials are not required at compile time.

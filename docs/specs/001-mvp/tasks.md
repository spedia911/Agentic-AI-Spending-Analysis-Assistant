# MVP Implementation Tasks

Use these tasks as the source of truth for incremental implementation.

Status: Phases 0 through 9 are implemented for the submitted Drive-first MVP. Phase 10 remains an optional Google Photos extension and is intentionally deferred. Phase 11 now includes force-reprocess guardrails and setup health checks, Phase 12 includes batch transaction and asset snapshot review, Phase 13 includes dashboard cash-flow separation, durable CashFlowSummary output, bank bill-payment spending, and sign-handling coverage, Phase 14 includes dashboard anomaly resolution, Phase 15 includes staged import review, source-file audit visibility, source evidence pages, optional screenshot-region highlighting, and a lightweight per-run file limit, Phase 16 includes preflight setup checks plus in-app setup checks, and Phase 17 includes action-oriented dashboard guidance.

## Phase 0: Project Foundation

- [x] Choose TypeScript/Next.js or another stack and scaffold the app.
- [x] Add environment variable loading and validation.
- [x] Add shared domain types for source documents, transactions, asset snapshots, review items, anomalies, and run state.
- [x] Add test framework and a small fixture directory for sanitized sample images or mocked extraction responses.
- [x] Add a local development README once the app exists.

Acceptance:

- The app starts locally.
- Required environment variables are validated.
- Domain types compile.
- At least one basic test runs.

## Phase 1: Google Drive Ingestion

- [x] Implement Google OAuth setup or service-account setup, depending on the chosen app model.
- [x] List image files in a configured Google Drive folder.
- [x] Track processed file IDs.
- [x] Download or stream unprocessed image content for extraction.
- [x] Write SourceDocuments rows to Google Sheets or a temporary local store.

Acceptance:

- A run can discover new screenshots in the Drive folder.
- Re-running does not process the same file twice.
- Unsupported files are skipped with masked warnings.

## Phase 2: Google Sheets Foundation

- [x] Create or verify required tabs.
- [x] Implement typed read/write helpers.
- [x] Implement upsert behavior by stable ID.
- [x] Add tests for row mapping and idempotent writes.

Acceptance:

- The app can create or update all MVP tabs.
- Re-running sample writes does not duplicate rows.

## Phase 3: Screenshot Extraction

- [x] Create a strict JSON extraction prompt for credit card screenshots.
- [x] Create a strict JSON extraction prompt for bank activity and balance screenshots.
- [x] Implement AI extraction client.
- [x] Add JSON repair or retry behavior.
- [x] Store raw evidence text with extracted records.
- [x] Add tests using mocked model responses.

Acceptance:

- Sample extraction responses produce transaction and asset snapshot candidates.
- Invalid model output fails gracefully and creates a processing error.

## Phase 4: Normalization and Validation

- [x] Normalize dates, amounts, merchants, account labels, and transaction types.
- [x] Mask account identifiers.
- [x] Detect missing fields and impossible values.
- [x] Detect duplicate-looking transactions.
- [x] Generate review queue items.

Acceptance:

- Messy extracted rows become predictable normalized records.
- Low-quality records are routed to review instead of silently accepted.

## Phase 5: Categorization

- [x] Add deterministic merchant rules.
- [x] Add AI classification fallback for unknown merchants.
- [x] Add category confidence and reasons.
- [x] Store future-applicable user corrections as merchant memory.
- [x] Route low-confidence categories to review.

Acceptance:

- Common merchants are categorized.
- Ambiguous merchants are flagged when confidence is low.
- User corrections can update category outcomes.

## Phase 6: Summary and Trend Generation

- [x] Generate MonthlySummary rows.
- [x] Generate QuarterlySummary rows.
- [x] Generate AssetTrends rows.
- [x] Add maintainability flags when spending rises and balances fall.

Acceptance:

- The sheet shows spending by month and category.
- The sheet shows quarterly totals where data exists.
- Asset trend rows update after new bank snapshots.

## Phase 7: Anomaly Detection

- [x] Detect duplicate charges.
- [x] Detect spending spikes by category.
- [x] Detect visible balance drops.
- [x] Detect missing or incomplete months.
- [x] Write Anomalies rows with suggested actions.

Acceptance:

- At least three anomaly types are implemented.
- Each anomaly includes a user-facing summary and suggested action.

## Phase 8: Single-User Web App

- [x] Add single-user access restriction by configured email.
- [x] Read summary, asset, review, and anomaly data from Google Sheets.
- [x] Build monthly category chart.
- [x] Build quarterly trend chart.
- [x] Build asset trend chart.
- [x] Build review queue and anomaly panels.

Acceptance:

- The configured user can view the dashboard.
- Other users are blocked.
- Dashboard reflects changes in the Google Sheet.

## Phase 9: Capstone Demo Polish

- [x] Add one-click or guided workflow run.
- [x] Add demo dataset instructions.
- [x] Add clear empty, loading, and error states.
- [x] Add screenshots or short demo notes.
- [x] Update README with final setup and run instructions.

Acceptance:

- A reviewer can understand the use case in under one minute.
- The demo shows image ingestion, extraction, review, Sheets output, and trends.

## Phase 10: Google Photos Optional Extension

- [x] Evaluate Google Photos Picker API for user-selected screenshots.
- [x] Add Photos source type without changing downstream data model.
- [ ] Store processed media IDs or selection timestamps.
- [x] Document limitations clearly.

Acceptance:

- Photos ingestion is optional.
- Drive ingestion remains the stable default.

## Next Implementation Plan: Assistant-Grade UX

The Drive-first MVP proves the backend workflow, but the next implementation should make the web app feel like an assistant rather than a read-only report. These phases come from live dashboard review and first-time setup friction observed during local testing.

## Phase 11: Dashboard Action Center

- [x] Add visible dashboard actions for running the full workflow, refreshing summaries, seeding demo data, and force reprocessing.
- [x] Show clear run status, latest run timestamp, files seen, files processed, errors, and next recommended action.
- [x] Add guardrails for force reprocess so the user understands it reruns already-known Drive files.
- [x] Show setup health checks for Drive folder access, Sheet access, AI key presence, and configured user email.

Acceptance:

- A non-technical reviewer can run the demo from the web page without curl.
- Failed workflow runs show a friendly, masked error and a concrete next step.
- Successful runs link the user to the dashboard sections that changed.

## Phase 12: Review Correction Cockpit

- [x] Replace static review cards with actionable review cards.
- [x] Show target record details: merchant, date, amount, transaction type, category, confidence, evidence text, and source document ID.
- [x] Render suggested options as buttons or dropdowns for category, date, amount, merchant, and transaction type corrections.
- [x] Add a custom correction input for cases where the suggestions are wrong.
- [x] Add an "apply to future similar merchants" control for category corrections.
- [x] Add a dedicated review page where multiple transaction corrections can be selected and applied in one batch.
- [x] Add month-only correction support so rows can be assigned to a spending month without requiring an exact date.
- [x] Keep same-merchant rows separate in review so two Trader Joe's transactions can receive different categories.
- [x] Keep the Spending Analysis dashboard focused on summary insights and route correction work to the dedicated review page.
- [x] Add severity filters and collapsible severity groups so users can focus on high, medium, or low priority corrections.
- [x] Add asset snapshot review controls for keeping, ignoring, or correcting balance snapshot reviews.
- [x] Add filters for missing date, missing amount, duplicate risk, unclear category, low confidence, asset snapshot review, and source-document review.
- [x] Rank and group reviews by severity.
- [x] Rank reviews by dollar amount and downstream summary impact.

Acceptance:

- A user can resolve common pending reviews from the dashboard or the dedicated review page.
- Applying corrections updates the Google Sheet, refreshes summaries once per batch, and removes resolved items from the pending queue.
- The page explains what changed after each correction.

## Phase 13: Spending, Earnings, and Cash Flow Separation

- [x] Add explicit summary outputs for spending, income, refunds, transfers, payments, and fees.
- [x] Update summary generation so income is not shown as a zero-dollar spending category.
- [x] Add dashboard metrics for monthly spend, monthly income, net cash flow, transfers/payments, and unresolved amount.
- [x] Add transaction type correction support for expense, income, transfer, payment, fee, refund, and unknown.
- [x] Count bank-account bill payments, such as utilities and rent, as spending when merchant evidence supports that category.
- [x] Exclude bank-activity credit card payments from spending totals.
- [x] Add a monthly category pie chart with clickable categories and filtered transaction rows.
- [x] Add a filterable spending summary table for month and category analysis.
- [x] Add inline Spending Explorer controls to correct a transaction category or remove a row from spending analysis.
- [x] Add tests for sign handling across credit card charges, refunds, payments, bank deposits, bank withdrawals, and transfers.

Acceptance:

- The dashboard clearly distinguishes money spent from money earned.
- Bank deposits and credit card payments do not inflate spending totals.
- The user can correct a transaction that was classified with the wrong money direction.

## Phase 14: Anomaly Resolution Workflow

- [x] Show related transaction or asset records inside each anomaly card.
- [x] For duplicate charge anomalies, display the two records side by side with date, merchant, amount, source, and evidence.
- [x] Add transaction-level actions for "keep as real spending", "mark duplicate", and "needs more review".
- [x] Add an anomaly status update endpoint or extend the correction workflow to resolve anomalies.
- [x] Preserve an audit trail for anomaly decisions in Sheets.

Acceptance:

- An anomaly tells the user exactly what records caused it.
- The user can resolve or ignore an anomaly from the dashboard.
- Duplicate decisions update summaries or status consistently.

Note: exact same-merchant, same-date, same-amount duplicate risks now default the second matching transaction to "mark duplicate" in the review workflow. Broader duplicate anomalies still need the full anomaly resolution UI.

## Phase 15: Evidence, Source, and File Selection UX

- [x] Show source document status counts: pending, processed, skipped, and error.
- [x] Add a pre-Sheets snapshot import page that stages extracted rows for review before logging them to Google Sheets.
- [x] Let users correct staged spending rows, categories, transaction types, dates, months, merchants, and amounts before commit.
- [x] Group staged import rows by source snapshot.
- [x] Let users type custom categories during staged import review.
- [x] Add category dropdown choices to staged import review so common categories do not need manual typing.
- [x] Let users exclude staged source snapshots before committing reviewed rows to Google Sheets.
- [x] Show recent Drive files with processing status and masked messages in the dashboard source audit.
- [x] Link source files, review items, and anomaly records to a source evidence page with metadata, linked extracted rows, open follow-ups, cached local screenshot preview when available, and Drive file handoff.
- [x] Add guidance that file selection is folder-based: put only desired screenshots in the configured Drive folder.
- [x] Add a page section for unprocessed, errored, and unsupported files.
- [x] Surface evidence text for extracted rows and review items.
- [x] Add exact screenshot-region highlighting when extraction returns coordinate hints.
- [x] Consider a lightweight file selection layer before processing if the Drive folder contains many screenshots.

Acceptance:

- The user can understand why a screenshot was or was not analyzed.
- The user can audit a row against its source evidence without opening the raw Sheet first.
- The dashboard explains how to refresh after adding new screenshots.

## Phase 16: First-Time Setup Experience

- [x] Add an in-app setup checklist for `.env`, Drive folder, Google Sheet, service account sharing, AI key, and selected model.
- [x] Show helpful messages for missing Node/npm before app startup.
- [x] Show helpful messages for missing `.env`, missing API keys, wrong email query parameter, or missing Google sharing.
- [x] Add a "test connections" endpoint that validates Drive, Sheets, and AI credentials without processing screenshots.
- [x] Add a "try sample data" button on empty dashboards.
- [x] Show a review-only dashboard safety note that the app is not financial advice and cannot move money.
- [x] Mask emails, long account-like numbers, and secret-shaped values in API-visible error details.
- [x] Keep the README aligned with this guided setup flow.

Acceptance:

- A first-time user can get from clone to demo without reading implementation docs.
- Setup failures explain the exact missing piece and where to get it.
- Empty Drive folders and empty Sheets are treated as normal first-run states, not confusing errors.

## Phase 17: Action-Oriented Dashboard Guidance

- [x] Add a tested dashboard insight generator that reads source files, reviews, anomalies, cash flow, and asset trends.
- [x] Prioritize failed source files, pending decisions, open anomalies, negative latest cash flow, and balance pressure.
- [x] Link each generated insight to the relevant dashboard, review, or evidence workflow.
- [x] Show an all-clear or first-run action when no urgent follow-up exists.

Acceptance:

- The dashboard tells the user what to do next instead of only showing charts.
- Insight ordering is deterministic and covered by unit tests.
- The guidance stays grounded in generated Sheet rows and does not provide financial advice.

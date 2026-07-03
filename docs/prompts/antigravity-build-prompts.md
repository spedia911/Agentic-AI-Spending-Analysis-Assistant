# Antigravity Build Prompts

Use these prompts one at a time. After each prompt, verify the acceptance criteria in `docs/specs/001-mvp/tasks.md` before moving on.

Status: Prompts 1 through 10 correspond to the implemented Drive-first MVP. Prompt 11 is partially implemented: workflow actions, setup health checks, staged import review, batch corrections, asset snapshot review handling, source-document review handling, anomaly resolution, source-file audit visibility, source evidence pages with optional screenshot-region highlighting, CashFlowSummary output, Spending Explorer cleanup, and spending/income separation are now in place.

## Prompt 1: Scaffold the App

Build the foundation for this project using the existing specs. Read `AGENTS.md`, `docs/PRD.md`, and all files under `docs/specs/001-mvp/`. Choose a TypeScript web app stack that can support Google Drive, Google Sheets, AI extraction, and a single-user dashboard. Scaffold the app, add environment validation based on `.env.example`, add shared domain types matching `docs/specs/001-mvp/data-model.md`, and add a minimal test setup. Do not implement Google APIs yet.

## Prompt 2: Implement Google Sheets Foundation

Implement the Google Sheets persistence layer. Create helpers that verify or create the required tabs, map typed domain objects to rows, and upsert rows by stable ID. Add tests for idempotent writes using mocks. Follow `docs/specs/001-mvp/data-model.md`.

## Prompt 3: Implement Google Drive Folder Ingestion

Implement the Drive ingestion agent. It should list image files in the configured Drive folder, skip already processed file IDs, collect metadata, and prepare image content for extraction. Write SourceDocuments rows and run history. Use masked logs.

## Prompt 4: Implement Screenshot Extraction

Implement the OCR and vision parsing agent. It should accept credit card and bank activity screenshots, call a multimodal AI model, and return strict JSON transaction and asset candidates. Add retry or repair handling for invalid JSON. Use mocked responses in tests.

## Prompt 5: Implement Normalization and Validation

Implement the normalization and validation agents. Normalize dates, amounts, merchants, account labels, transaction types, and balance snapshots. Detect missing fields, impossible dates, duplicate-looking transactions, and low-confidence rows. Write review items when needed.

## Prompt 6: Implement Categorization

Implement the categorization agent. Use deterministic merchant rules first, then AI classification fallback. Assign category, confidence, and reason. Route ambiguous merchants to ReviewQueue. Store future-applicable corrections in the Corrections tab.

## Prompt 7: Implement Summaries and Trends

Implement monthly category totals, quarterly category totals, and asset trend calculations. Write MonthlySummary, QuarterlySummary, and AssetTrends tabs. Include maintainability flags when spending rises while visible asset balances decline.

## Prompt 8: Implement Anomaly Detection

Implement anomaly detection for duplicate charges, spending spikes, visible balance drops, and incomplete months. Write Anomalies rows with severity, summary, and suggested action.

## Prompt 9: Build the Dashboard

Build the single-user dashboard that reads from Google Sheets and displays monthly spending by category, quarterly trends, asset trend, unresolved review queue items, and anomalies. Restrict access to the configured single user email.

## Prompt 10: Capstone Demo Polish

Create a polished demo flow. Add setup instructions, empty states, error states, and a clear run path. Ensure a reviewer can understand and run the project with sample screenshots or mocked extraction data.

## Prompt 11: Build Assistant-Grade UX

Continue upgrading the dashboard into an action-oriented assistant cockpit. Read the "Next Implementation Plan: Assistant-Grade UX" section in `docs/specs/001-mvp/tasks.md` first. Extend the existing workflow actions, staged import review, review correction page, asset snapshot correction controls, Spending Explorer cleanup, and spending/income metrics with setup health checks, anomaly resolution controls, richer source evidence display, and guided first-time setup. Keep the MVP single-user and Drive-first. Add tests for correction workflows, spending/income summary behavior, and anomaly status updates.

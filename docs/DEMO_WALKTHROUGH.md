# Demo Walkthrough

Use this script for a Kaggle submission writeup, screen recording, or live review. It is designed to show the product value in under five minutes while still pointing to the technical depth behind the UI.

## One-Sentence Pitch

This is an individual-only agentic finance assistant that turns Drive screenshots of credit card and bank activity into auditable Google Sheets data, reviewable corrections, anomaly decisions, and a dashboard for spending, cash flow, and visible asset trends.

## Demo Setup

Start from the project folder:

```bash
sh scripts/preflight.sh
npm install
npm run dev
```

Before recording or submitting, run:

```bash
npm run verify
```

Open:

```text
http://localhost:3000?email=YOUR_CONFIGURED_EMAIL
```

Seed safe demo data when private Drive screenshots are not available:

- Click **Seed demo data** in the dashboard action center.

The same path is also available as an API call for developer testing:

```bash
curl -X POST http://localhost:3000/api/demo/seed
```

For the full workflow, place screenshots in the configured Drive folder, set **Files this run**, and click **Run Drive workflow**.

The same workflow is also available as an API call:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d '{"maxDocuments":5}'
```

## Walkthrough Track

### 1. Setup Confidence

Show the preflight command and the dashboard "Test setup" button.

What it proves:

- First-time setup failures are made explicit.
- The app checks Drive, Sheets, AI configuration, service-account access, and the single-user email gate before processing private screenshots.
- The app avoids silently failing on credential or sharing issues.

### 2. Agentic Workflow Control

Show the dashboard action center:

- Import snapshots.
- Run Drive workflow.
- Files this run.
- Refresh summaries.
- Seed demo data.
- Force reprocess two-step confirmation.

What it proves:

- The assistant decides which Drive files need processing.
- The workflow is rerunnable and idempotent.
- Users can limit a run when the Drive folder contains many screenshots.
- Force reprocessing is guarded because it can rerun already-known files.

Show the next-best-actions panel.

What it proves:

- The dashboard converts reviews, anomalies, failed files, cash-flow pressure, and asset concerns into prioritized follow-up.
- Guidance links to the exact workflow the user should open next.
- The assistant produces action-oriented summaries, not only charts.

### 3. Durable Google Sheets Output

Open the generated Sheet or describe the tabs:

- `SourceDocuments`
- `Transactions`
- `AssetSnapshots`
- `ReviewQueue`
- `Corrections`
- `MonthlySummary`
- `QuarterlySummary`
- `CashFlowSummary`
- `AssetTrends`
- `Anomalies`
- `Runs`

What it proves:

- Sheets are the durable source of truth.
- Extracted rows keep source references and evidence.
- Summary tabs are generated outputs, not manual calculations.
- `Runs` provides an audit trail for each guided run.

### 4. Spending And Cash Flow Dashboard

Show the top metrics, monthly/quarterly charts, category pie chart, Spending Explorer, and Monthly money movement table.

What it proves:

- Spending, income, refunds, transfers/card payments, other payments, fees, and net cash flow are separated.
- Credit card payments and bank deposits do not inflate spending.
- Category totals are filterable and traceable to transaction rows.

### 5. Human-In-The-Loop Review

Open `/review?email=YOUR_CONFIGURED_EMAIL`.

Show:

- Severity filters.
- Issue-type filters.
- Dollar-impact ordering.
- Month-only correction.
- Category/type/date/amount controls.
- Asset snapshot handling.
- Source document retry/ignore controls.

What it proves:

- The assistant asks targeted questions instead of blindly accepting uncertain extraction.
- Corrections update Sheets and refresh summaries.
- Same-merchant rows can be corrected differently.
- User corrections can become future merchant memory.

### 6. Anomaly Decisions

Return to the dashboard anomaly panel.

Show:

- Related records inside anomaly cards.
- Duplicate rows side by side.
- Keep both, mark reviewed, ignore, and duplicate-exclusion decisions.

What it proves:

- Anomalies are action-oriented, not just charts.
- Decisions are preserved in `Corrections` and do not reopen on summary refresh.
- Duplicate decisions can update the underlying transaction status and summaries.

### 7. Source Evidence And Auditability

Open a source file from the Source file audit table or from a review/anomaly link.

Show:

- Source metadata.
- Cached screenshot preview when available.
- Optional screenshot-region overlays when coordinate hints exist.
- Extracted transactions and asset snapshots tied to that source.
- Open reviews/anomalies tied to that source.
- Drive file handoff link.

What it proves:

- The user can audit a row against source evidence without opening raw Sheets first.
- The app preserves enough evidence for human review.
- Sensitive source screenshots remain in a private local cache and are not committed.

## Technical Evaluation Signals To Mention

- Multi-agent architecture: ingestion, extraction, normalization, validation, categorization, correction, reporting, anomaly, and dashboard layers are separated.
- Action-oriented output: the dashboard insight layer turns generated Sheet state into prioritized next steps.
- Grounded AI output: strict JSON schema, evidence text, optional coordinate hints, confidence scores, review routing.
- Tool integration: Google Drive, Google Sheets, AI vision adapters, Next.js API routes.
- Rerunnable state: stable IDs, SourceDocuments processing state, upsert helpers, force-reprocess controls.
- Safety: review-only dashboard note, single-user email gate, shared API/log error redaction, private screenshot cache, no secrets in repo.
- Robustness: setup preflight, setup health endpoint, invalid JSON handling, file-level processing errors, partial-success runs.
- Test coverage: parsing, normalization, categorization, validation, summaries, cash-flow sign handling, corrections, staged import review, demo seeding, anomaly resolution, dashboard data access, dashboard insights, setup health, source evidence cache/preview access, and workflow options.
- Required course concepts: multi-agent workflow, Antigravity build prompts, security features, deployability, and agent tool use through Drive, Sheets, AI extraction, and human review. MCP Server and ADK-specific implementation are not claimed in this MVP.

## Honest Scope Notes

- Google Drive is the submitted MVP ingestion path.
- Google Photos is evaluated and documented as a future Picker API extension.
- Screenshot-region highlights appear only when the model returns reliable coordinate hints.
- The assistant is not financial advice and does not initiate payments or move money.

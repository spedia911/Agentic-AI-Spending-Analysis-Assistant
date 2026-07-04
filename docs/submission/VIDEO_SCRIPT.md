# Five-Minute Video Script

Target length: 4:30 to 4:50.

Video requirement: record with your own voice, publish to YouTube, and attach it to the Kaggle Media Gallery.

Use [DEMO_PRESENTATION.html](DEMO_PRESENTATION.html) for the opening concept deck and speaker notes, then switch to the running dashboard for the live demonstration. Use [YOUTUBE_UPLOAD_METADATA.md](YOUTUBE_UPLOAD_METADATA.md) for the final title, description, chapters, tags, and upload privacy checklist.

## Recording Flow

1. Open `docs/submission/DEMO_PRESENTATION.html` in a browser.
2. Record the HTML slides for the concept, agentic behavior, system flow, safety framing, and dashboard handoff.
3. Switch to the actual dashboard at `http://localhost:3000?email=YOUR_CONFIGURED_EMAIL`.
4. Use sanitized demo data if needed by clicking **Seed demo data**.
5. Demonstrate the real dashboard controls and evidence workflows.

## 0:00-0:20 Opening Concept

Show:

- Cover image or dashboard opening screen.

Say:

> This is Agentic AI Spending Analysis Assistant, my Concierge Agents capstone project. It is a private, single-user assistant for turning financial screenshots into auditable spreadsheet data, review decisions, and a dashboard for spending, cash flow, and visible asset trends.

## 0:20-0:45 Why This Is Agentic

Show:

- Architecture diagram and dashboard next-best-actions panel.

Say:

> A simple OCR pipeline is not enough for this problem. Financial screenshots can have cropped rows, ambiguous merchants, mixed transaction signs, and visible balances that need context. The assistant acts as a workflow: it decides which files need processing, checks extracted rows for risk, and asks the user targeted questions when confidence is low.

## 0:45-1:20 Product Flow

Show:

- Architecture diagram or README workflow section.

Say:

> The flow starts with a dedicated Google Drive folder. The agent modules extract rows, normalize amounts and dates, validate uncertainty, categorize spending, and create review items. Google Sheets is the durable memory layer, and the dashboard is where the user sees next-best actions, charts, evidence, and correction controls.

## 1:20-1:40 Trust And Demo Safety

Show:

- Dashboard safety notice.

Say:

> The project is intentionally review-only. It does not move money, initiate payments, or provide professional financial advice. For the recording, I am using sanitized data and avoiding `.env` values, service-account files, API keys, account numbers, and private screenshots.

## 1:40-1:55 Dashboard Handoff

Show:

- Final architecture or dashboard transition screen.
- Then switch to `http://localhost:3000?email=YOUR_CONFIGURED_EMAIL`.

Say:

> Now I am switching from the concept deck into the actual dashboard. This is where the workflow becomes usable: running or seeding data, reviewing results, correcting uncertainty, and auditing the source evidence.

## 1:55-2:25 Action Center And Setup

Show:

- Dashboard header and safety notice.
- Action center.
- **Test setup**, **Seed demo data**, **Run Drive workflow**, and **Refresh summaries** controls.
- Next-best-actions panel.

Say:

> The dashboard starts with operational controls, not just charts. A reviewer can test setup, seed safe demo data, run the Drive workflow, refresh summaries, and see prioritized next-best actions. The force-reprocess path is guarded because rerunning known Drive files should be intentional.

## 2:25-3:05 Spending And Cash Flow

Show:

- Top metrics.
- Monthly spending chart.
- Spending Explorer.
- Category pie chart.
- Cash-flow table or summary section.

Say:

> The dashboard separates spending from income, refunds, transfers, card payments, fees, and net cash flow. This matters because deposits and credit card payments should not inflate spending totals. The Spending Explorer lets me filter by month or category and trace summary numbers back to transaction rows.

## 3:05-3:45 Human Review Workflow

Show:

- `/import?email=YOUR_CONFIGURED_EMAIL` if staged rows are available.
- `/review?email=YOUR_CONFIGURED_EMAIL`.
- Severity filters, issue-type filters, suggested corrections, and batch correction controls.

Say:

> The human-in-the-loop part is where the assistant becomes safer. Before rows are committed, the import review can exclude unwanted screenshots or correct extracted fields. After rows are in Sheets, the review workbench supports category, amount, date, month, transaction-type, asset snapshot, and source-file decisions. Corrections update Sheets and refresh the summaries.

## 3:45-4:25 Anomalies And Source Evidence

Show:

- Anomaly panel.
- Duplicate charge or balance-drop anomaly.
- Related records inside anomaly cards.
- Source evidence page and Drive handoff link.

Say:

> The assistant also creates action-oriented anomalies. Duplicate-looking charges can be kept, ignored, or excluded from spending analysis. Balance drops and missing data are surfaced as follow-up items. Each row keeps source references and evidence text so the user can audit a decision instead of trusting a black box.

## 4:25-4:50 Course Concepts And Close

Show:

- Final dashboard state.
- Optionally show `docs/submission/COURSE_CONCEPT_COVERAGE.md`.

Say:

> This submission demonstrates five course concepts: a multi-agent workflow, Antigravity-assisted build documentation, security features, deployability, and agent tool use through Drive, Sheets, AI extraction, and human review. I am not claiming MCP Server or ADK-specific implementation in this MVP. The key idea is a private assistant that keeps the user in control while making monthly financial review faster and more auditable.

## Recording Checklist

- Keep the video at 5 minutes or less.
- Use your own voice.
- Use sanitized demo data unless all private details are masked.
- Do not show `.env`, service account JSON, API keys, real account numbers, private screenshots, or private local paths.
- Mention the Concierge Agents track.
- Show at least three course concepts explicitly.
- Be explicit about concepts not claimed: MCP Server and ADK-specific implementation.
- End with the public project link or repository link.

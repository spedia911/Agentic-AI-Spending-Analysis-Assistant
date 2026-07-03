# Five-Minute Video Script

Target length: 4:30 to 4:50.

Video requirement: publish to YouTube and attach it to the Kaggle Media Gallery.

Use [YOUTUBE_UPLOAD_METADATA.md](YOUTUBE_UPLOAD_METADATA.md) for the final title, description, chapters, tags, and upload privacy checklist.

## 0:00-0:25 Opening

Say:

> This is Agentic AI Spending Analysis Assistant, a Concierge Agent for personal financial organization. It turns screenshots from a private Google Drive folder into auditable Google Sheets data, review queues, anomaly decisions, and a dashboard for spending, cash flow, and visible asset trends.

Show:

- Cover image or dashboard opening screen.
- One sentence problem statement.

## 0:25-0:55 Why Agents

Say:

> A simple OCR pipeline is not enough here. Screenshots are messy, financial rows can be ambiguous, and wrong categorization can mislead the user. This assistant decides which files need processing, extracts structured rows, validates uncertain records, remembers corrections, asks targeted review questions, and reruns summaries after decisions.

Show:

- The action center.
- Next Best Actions.

## 0:55-1:30 Architecture

Say:

> The workflow is built as cooperating agent modules: ingestion, extraction, normalization, validation, categorization, correction, summary generation, anomaly detection, and dashboard guidance. Google Drive is the screenshot inbox. Google Sheets is durable memory. The web dashboard is the human decision layer.

Show:

- `docs/submission/cover-image.svg` or an architecture slide.
- `docs/submission/architecture-diagram.svg` for the technical architecture shot.
- Briefly show the generated Sheet tabs.

## 1:30-2:10 Setup And Safe Demo

Say:

> For judging, the app includes setup health checks and a sanitized demo path. The verification command runs preflight, privacy checks, docs checks, tests, type check, lint, and production build.

Show:

- `npm run verify` result, or a terminal screenshot after it completes.
- Dashboard **Test setup**.
- Dashboard **Seed demo data**.

## 2:10-2:55 Product Demo

Say:

> The dashboard separates spending, income, refunds, transfers, payments, fees, and net cash flow. The Spending Explorer lets the user filter a month or category and trace a total back to rows.

Show:

- Top metrics.
- Spending Explorer.
- Category pie chart.
- Cash-flow table.

## 2:55-3:35 Human Review

Say:

> Before rows are written to Sheets, the staged import page lets the user review each source screenshot, exclude unwanted snapshots, and correct extracted values. Existing Sheet rows can also be corrected in the review workbench, including asset snapshots and source-file issues.

Show:

- `/import` include/exclude control.
- Category or amount edit.
- `/review` filters and batch correction controls.

## 3:35-4:10 Anomalies And Evidence

Say:

> The assistant also creates action-oriented anomalies. Duplicate charges can be kept or excluded, balance drops can be reviewed, and source evidence remains linked for audit.

Show:

- Anomaly card.
- Source evidence page.
- Drive handoff link.

## 4:10-4:40 Course Concepts And Close

Say:

> This demonstrates five course concepts: a multi-agent workflow, Antigravity-assisted build documentation, security features, deployability, and agent tool use through Drive, Sheets, AI extraction, and human review. I am not claiming MCP Server or ADK-specific implementation in this MVP. The assistant is intentionally single-user, private by default, and review-only: it does not move money or give financial advice.

Show:

- README or submission checklist.
- `docs/prompts/antigravity-build-prompts.md` as build-process evidence.
- `docs/submission/COURSE_CONCEPT_COVERAGE.md` as the concept map.
- Final dashboard state.

## Recording Checklist

- Keep the video at 5 minutes or less.
- Use sanitized demo data unless all private details are masked.
- Do not show `.env`, service account JSON, API keys, real account numbers, or private screenshots.
- Show at least three course concepts explicitly.
- Be explicit about concepts not claimed: MCP Server and ADK-specific implementation.
- Mention the Concierge Agents track.
- End with the public project link or repository link.

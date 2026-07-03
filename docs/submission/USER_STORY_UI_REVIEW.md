# User Story And UI Review

Use this as the reviewer-facing trace from MVP user stories to visible product flows. It captures the UI gaps found during capstone polish and where they are now addressed.

## Review Summary

The MVP user stories are covered by the current Drive-first implementation and visible in the web app through four primary flows:

- Dashboard action center for setup, demo seeding, workflow runs, summary refreshes, and force-reprocess guardrails.
- Staged import review for checking extracted snapshot rows before they are written to Google Sheets.
- Review correction workbench for batch transaction, asset snapshot, and source-file decisions.
- Dashboard insight, anomaly, spending, cash-flow, asset, and source-evidence views for ongoing review.

The strongest UX improvements since the initial MVP are the human decision layers: staged source include/exclude, source evidence pages, anomaly decisions, setup health checks, and next-best actions. These make the product feel like an assistant instead of a read-only report.

## User Story Trace

| User story | Visible UI path | Evidence in code/docs | Review status |
| --- | --- | --- | --- |
| US-001 Configure financial screenshot source | Dashboard action center, setup health checks, source-file audit | `src/app/dashboard-actions.tsx`, `src/lib/setup/health.ts`, `src/lib/orchestrator/ingest.ts` | Covered |
| US-002 Extract credit card transactions | Dashboard workflow run, staged import, Spending Explorer, source evidence page | `src/lib/extraction/`, `src/lib/normalization/`, `src/app/import/`, `src/app/source/` | Covered |
| US-003 Extract bank activity and asset snapshots | Asset trend sections, asset snapshot review controls, cash-flow table | `src/lib/extraction/prompts.ts`, `src/lib/summaries/generator.ts`, `src/app/review/review-workbench.tsx` | Covered |
| US-004 Normalize extracted records | Spending Explorer rows, cash-flow separation, review field edits | `src/lib/normalization/normalizer.ts`, `src/lib/finance/spending.ts`, `src/lib/staging/snapshot-review.ts` | Covered |
| US-005 Categorize spending | Category pie chart, category filters, inline correction, merchant memory | `src/lib/categorization/`, `src/app/spending-explorer.tsx`, `src/lib/corrections/apply.ts` | Covered |
| US-006 Validate and review | Review workbench, severity filters, anomaly center, duplicate decisions | `src/lib/validation/`, `src/app/review/`, `src/app/anomaly-center.tsx` | Covered |
| US-007 Write Google Sheets output | Dashboard reads generated tabs; commit/import and correction actions write back | `src/lib/google/sheets.ts`, `src/app/api/staging/commit/route.ts`, `src/app/api/corrections/` | Covered |
| US-008 Generate monthly and quarterly trends | Monthly and quarterly spending charts, summary refresh action | `src/lib/summaries/generator.ts`, `src/app/page.tsx` | Covered |
| US-009 Show asset trend context | Asset trends, balance-pressure insights, asset snapshot review | `src/lib/summaries/generator.ts`, `src/lib/dashboard/insights.ts`, `src/app/page.tsx` | Covered |
| US-010 Single-user web app | Email-gated dashboard, import page, review page, source page | `src/lib/dashboard/data.ts`, `src/app/page.tsx`, `src/app/import/page.tsx`, `src/app/review/page.tsx` | Covered |

## UI Gaps Found And Addressed

| Gap found during review | Improvement made | User impact |
| --- | --- | --- |
| Workflow actions were too backend-centric for a non-technical reviewer | Added dashboard action center, setup health, demo seed, import, run, refresh, and guarded force reprocess controls | A reviewer can drive the demo from the app instead of using API calls |
| Review items were hard to resolve in bulk | Added dedicated review workbench with severity filters, issue-type filters, batch corrections, and impact ordering | The user can clean many uncertain rows without editing Sheets manually |
| Spending totals mixed expenses, income, refunds, transfers, and payments too easily | Added cash-flow separation, transaction type correction, and sign-handling tests | The dashboard is less likely to mislead the user about real spending |
| Source screenshots were not auditable enough from the UI | Added source-file audit, source evidence pages, cached preview support, Drive handoff, and optional evidence regions | The user can trace totals and corrections back to screenshot evidence |
| The import flow could write all staged screenshots even when one source was unwanted | Added source snapshot include/exclude controls before commit | The user can avoid polluting Sheets with accidental screenshots |
| Anomalies were mostly informational | Added anomaly resolution actions and audit trail rows | Duplicate and suspicious records can be decided from the dashboard |
| The dashboard showed information but did not prioritize what to do next | Added deterministic next-best-action insights | The assistant now points the user toward failed files, reviews, anomalies, cash-flow pressure, and asset concerns |
| First-run setup failures were hard to diagnose | Added preflight script, in-app setup health, redacted errors, and demo seed path | A judge can evaluate the product without private screenshots or trial-and-error setup |

## Remaining Future UX Ideas

These are useful but not required for the submitted Drive-first MVP:

- Hosted demo with mock credentials and fully public sanitized data.
- Richer chart interactions and downloadable reports.
- Screenshot-layout accuracy evaluation across more banks and card providers.
- Optional Google Photos Picker ingestion after Drive is stable.
- Natural-language question answering over the generated Sheet tabs.

## Demo Shot Checklist

Show these UI surfaces in the video or screenshots:

- Dashboard action center and setup health result.
- Seed demo data path.
- Next Best Actions panel.
- Staged import page with source include/exclude.
- Spending Explorer with category filtering and row-level corrections.
- Cash-flow table showing spending, income, refunds, transfers, payments, fees, and net cash flow.
- Review workbench with severity and issue filters.
- Anomaly center with related rows and resolution actions.
- Source-file audit and source evidence page.

## Submission Note

The UI is intentionally single-user and review-only. It helps a person reconcile private screenshots against auditable Sheet rows, but it does not initiate payments, move money, connect to bank APIs, or provide professional financial advice.

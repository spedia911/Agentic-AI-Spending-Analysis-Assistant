# Capstone Readiness Audit

Last updated: 2026-07-03

This audit maps the project requirements to current implementation evidence. It is intended as a reviewer-facing checklist before Kaggle submission.

For a concise recording or live-demo script, see [DEMO_WALKTHROUGH.md](DEMO_WALKTHROUGH.md).
For final packaging checks, see [SUBMISSION_PACKAGE_CHECKLIST.md](SUBMISSION_PACKAGE_CHECKLIST.md).

## Submission Position

The project is ready to present as a Drive-first MVP for an individual-only agentic AI spending analysis assistant.

The implementation satisfies the submitted MVP scope:

- Google Drive screenshot ingestion.
- AI screenshot extraction for credit card and bank activity screenshots.
- Normalization, validation, categorization, review routing, corrections, and reruns.
- Google Sheets as durable output.
- Monthly, quarterly, cash-flow, asset trend, and anomaly outputs.
- Single-user web dashboard with setup health checks, review workflows, anomaly decisions, source evidence, and demo seeding.
- Reviewer-controlled staged import so unwanted source screenshots can be excluded before they touch Google Sheets.

Google Photos remains optional and deferred. Current API evaluation is documented in [google-photos-picker-evaluation.md](references/google-photos-picker-evaluation.md).

## Requirement Evidence

| Requirement | Status | Evidence |
| --- | --- | --- |
| Configure screenshot source | Complete | Drive ingestion and source tracking in `src/lib/orchestrator/ingest.ts`; setup health in `src/lib/setup/health.ts`; dashboard action center in `src/app/dashboard-actions.tsx` |
| Skip processed files unless forced | Complete | Stable `SourceDocuments` IDs and force-reprocess guardrails in ingestion/workflow routes |
| Extract credit card transactions | Complete | Extraction prompts/schema/service in `src/lib/extraction/`; normalized transaction rows in `src/lib/normalization/normalizer.ts` |
| Extract bank activity and asset snapshots | Complete | Bank prompt, asset snapshot normalization, `AssetSnapshots`, and `AssetTrends` |
| Normalize messy data | Complete | Date, amount, merchant, account masking, and type normalization tests in `src/lib/normalization/normalizer.test.ts` |
| Categorize spending | Complete | Deterministic rules, AI fallback, merchant memory, and low-confidence review routing in `src/lib/categorization/` |
| Validate and review | Complete | Validation checks in `src/lib/validation/`; batch review cockpit in `src/app/review/review-workbench.tsx` |
| Write durable Sheets output | Complete | Typed schemas and upsert/replace helpers in `src/lib/google/sheets.ts` |
| Generate monthly/quarterly trends | Complete | Summary generator and tests in `src/lib/summaries/generator.ts` and `.test.ts` |
| Generate cash-flow separation | Complete | `CashFlowSummary` model, Sheet tab, generator, and dashboard table |
| Show asset trend context | Complete | Asset trend generation and dashboard visualization |
| Detect anomalies | Complete | Duplicate, spike, balance drop, and missing-month detection in `src/lib/anomalies/` |
| Resolve anomalies | Complete | Dashboard anomaly center and `/api/anomalies/resolve` |
| Generate action-oriented next steps | Complete | Dashboard insight generator in `src/lib/dashboard/insights.ts` and Next Best Actions panel in `src/app/page.tsx` |
| Preserve audit evidence | Complete | `evidence_text`, optional `evidence_region`, source evidence page, tested cached screenshot route, and Drive handoff |
| Single-user dashboard | Complete | Email gate and Sheet-backed dashboard data loading in `src/lib/dashboard/data.ts`, with focused tests |
| Demo without private screenshots | Complete | Sanitized seed endpoint `/api/demo/seed` with route-level test coverage |
| First-time setup support | Complete | `scripts/preflight.sh`, `npm run doctor`, in-app setup health endpoint, README setup path |

## Agentic Evaluation Signals

| Signal | Evidence |
| --- | --- |
| Multi-step agent workflow | Ingestion, extraction, normalization, validation, categorization, correction, summary, anomaly, and dashboard agents are separated by module |
| Tool/API integration | Google Drive, Google Sheets, AI vision extraction, and Next.js dashboard/API routes |
| Human-in-the-loop decisions | Review queue, batch corrections, tested staged import review with source include/exclude before commit, anomaly decisions, source-file retry/ignore controls |
| Action-oriented summaries | Next Best Actions panel prioritizes failed files, pending reviews, anomalies, negative cash flow, and asset concerns |
| Rerunnable/idempotent behavior | Stable IDs, upsert helpers, processed-source tracking, force-reprocess guardrails |
| Grounding and auditability | Evidence text, optional screenshot-region overlays, source evidence pages, source-file audit table, Drive handoff |
| Safety and privacy | Review-only dashboard note, single-user email gate, shared API/log error redaction, private screenshot cache, ignored secret files, service-account setup guidance, tracked-file privacy check |
| Robustness | Setup health checks, preflight script, typed schemas, validation, JSON parsing errors, partial-success workflow runs |
| Technical quality | TypeScript domain types, unit tests, lint/type/build gates, documented data model and demo path |

## Current Verification

Latest local verification:

- `npm run verify`: full verification wrapper passes.
- `sh scripts/preflight.sh`: passed in current environment.
- `sh scripts/privacy-check.sh`: passed with no tracked secrets or private artifacts.
- `sh scripts/docs-check.sh`: passed for required reviewer docs, demo signals, evaluation signals, and path portability.
- `npm run doctor`: passed in current environment.
- `npm test`: 26 test files passed, 112 tests passed.
- `npx tsc --noEmit`: zero diagnostics.
- `npm run lint`: zero reported issues.
- `git diff --check`: clean.
- `npm run build`: production build completes successfully.

## Remaining Non-Blocking Items

| Item | Why non-blocking |
| --- | --- |
| Google Photos Picker implementation | Explicitly optional and deferred until Drive workflow is stable; data model already supports `source_type = photos`; API evaluation is documented |
| Processed Photos media IDs / selection timestamps | Belongs to the future Picker adapter; Drive source IDs currently provide stable idempotency |

## Kaggle Submission Fit

Recommended track: Concierge Agents, because the assistant solves an individual financial organization problem while emphasizing private source data, single-user access, and human-controlled decisions.

| Required concept | Evidence |
| --- | --- |
| Agent / multi-agent system | Separated ingestion, extraction, normalization, validation, categorization, correction, summary, anomaly, and dashboard guidance modules |
| Antigravity | Build-prompt record in `docs/prompts/antigravity-build-prompts.md` and video callout |
| Security features | Email gate, private screenshot cache, secret/package checks, redacted errors, no tracked credentials |
| Deployability | Next.js app, setup docs, `.env.example`, preflight/doctor checks, full `npm run verify` script |
| Agent skills/tool use | Drive and Sheets tools, AI vision adapter, durable memory tabs, review/correction workflows |

The submitted MVP does not claim MCP Server or ADK-specific implementation.

## Recommended Reviewer Demo

1. Run `sh scripts/preflight.sh`.
2. Run `npm install` if needed.
3. Run `npm run dev`.
4. Open `http://localhost:3000?email=YOUR_CONFIGURED_EMAIL`.
5. Seed demo data with the dashboard **Seed demo data** button.
6. Use the dashboard action center, Next Best Actions, Spending Explorer, anomaly review panel, source-file audit, source evidence page, and `/review` correction workbench.

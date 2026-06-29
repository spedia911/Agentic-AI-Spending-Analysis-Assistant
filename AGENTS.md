# Agent Instructions

Use this file as the primary project guide when working in Antigravity or another agentic coding environment.

## Mission

Build an individual-only agentic AI spending analysis assistant. The assistant ingests screenshots of credit card spending and bank account activity, extracts structured financial records, validates and categorizes them, writes results to Google Sheets, and powers a lightweight web dashboard.

## Read Order

Before coding, read these files in order:

1. `docs/PRD.md`
2. `docs/specs/001-mvp/requirements.md`
3. `docs/specs/001-mvp/design.md`
4. `docs/specs/001-mvp/data-model.md`
5. `docs/specs/001-mvp/tasks.md`
6. `docs/references/google-api-constraints.md`

## Current Product Decisions

- Primary ingestion source: dedicated Google Drive folder.
- Secondary ingestion source: Google Photos, deferred until Drive workflow is stable.
- Durable output: Google Sheets.
- Web app mode: single user only.
- First input type: screenshots, not PDFs.
- First analysis target: credit card spending plus bank activity and asset balances.
- Financial source of truth: extracted rows plus the generated spreadsheet tabs.

## Agentic Behavior Requirements

The implementation should not be a thin OCR pipeline. Agents must:

- Decide which files need processing.
- Extract raw text and structured rows.
- Validate parsed data and flag uncertainty.
- Categorize spending with confidence scores.
- Suggest corrections for low-confidence or suspicious records.
- Preserve enough evidence for the user to audit a result.
- Orchestrate reruns after corrections.
- Generate action-oriented summaries, not only charts.

## Implementation Guardrails

- Do not store secrets in the repo.
- Do not commit OAuth tokens, service account keys, generated screenshots, or financial source images.
- Mask account numbers and sensitive identifiers in logs.
- Keep source image retention configurable.
- Prefer small, testable increments over large rewrites.
- Add tests around parsing, normalization, categorization, and Sheets writing.
- Keep Google Photos optional until the Drive ingestion path is complete.

## Definition of Done for Each Task

Each completed task should include:

- Working implementation.
- Clear error handling for the expected failure modes.
- Unit or integration tests where practical.
- Updated documentation if behavior changes.
- A short demo path the user can run.


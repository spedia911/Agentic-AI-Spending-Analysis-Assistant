# Agentic AI Spending Analysis Assistant

An agentic personal finance assistant for the Kaggle Vibe Coding Capstone Project.

The app ingests screenshots of credit card spending and bank account activity from a dedicated Google Drive folder, extracts and validates transaction data, categorizes spending, writes monthly summaries to Google Sheets, and supports an individual web app for spending and asset trend visualization.

## Current Status

This repository is currently a spec-driven project scaffold. It is ready for incremental implementation in Antigravity or another coding agent environment.

## MVP Focus

The first build should support:

- Google Drive folder ingestion for financial screenshots.
- Image OCR and multimodal transaction extraction.
- Agentic validation, categorization, and correction suggestions.
- Google Sheets output as the source of truth.
- Monthly and quarterly category trends.
- Asset trend tracking from bank activity snapshots.
- A single-user web app that reads from the generated spreadsheet.

Google Photos ingestion is intentionally deferred until after the Drive-based workflow is working, because automatic full-library scanning is constrained by current Google Photos API behavior. See [docs/references/google-api-constraints.md](docs/references/google-api-constraints.md).

## Repo Map

- [AGENTS.md](AGENTS.md): instructions for Antigravity and other coding agents.
- [docs/PRD.md](docs/PRD.md): product requirement document.
- [docs/specs/001-mvp/requirements.md](docs/specs/001-mvp/requirements.md): MVP user stories and acceptance criteria.
- [docs/specs/001-mvp/design.md](docs/specs/001-mvp/design.md): system design and agent architecture.
- [docs/specs/001-mvp/data-model.md](docs/specs/001-mvp/data-model.md): Sheets tabs and structured entities.
- [docs/specs/001-mvp/tasks.md](docs/specs/001-mvp/tasks.md): incremental implementation plan.
- [docs/prompts/antigravity-build-prompts.md](docs/prompts/antigravity-build-prompts.md): ready-to-use build prompts.
- [docs/references/google-api-constraints.md](docs/references/google-api-constraints.md): Google Drive, Sheets, and Photos notes.
- [.env.example](.env.example): environment variables for future implementation.

## Recommended Build Order

1. Implement Google Drive folder ingestion.
2. Extract structured transactions from sample screenshots.
3. Write normalized data to Google Sheets.
4. Add categorization confidence and review queue.
5. Generate monthly and quarterly summaries.
6. Add asset trend extraction.
7. Build the single-user web dashboard.
8. Add anomaly detection and correction workflow.
9. Add Google Photos as an optional source.

## Definition of Done for the Capstone Demo

The demo should show a user placing financial screenshots into a dedicated source, running the assistant, reviewing a few low-confidence items, and opening a Google Sheet or web dashboard that displays monthly spending by category plus asset trend context.


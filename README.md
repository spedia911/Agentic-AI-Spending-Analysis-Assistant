# Agentic AI Spending Analysis Assistant

An agentic personal finance assistant for the Kaggle Vibe Coding Capstone Project.

The app ingests screenshots of credit card spending and bank account activity from a dedicated Google Drive folder, extracts and validates transaction data, categorizes spending, writes monthly summaries to Google Sheets, and supports an individual web app for spending and asset trend visualization.

## Current Status

Phase 0 is implemented for MVP: the app is scaffolded with Next.js and TypeScript, environment validation exists, shared domain types are present, and focused tests are in place.

Phase 1 is implemented for MVP: the app can initialize Google Sheets tabs, list files in a configured Google Drive folder, skip unsupported files, avoid already-known screenshots unless force reprocessing is requested, download supported image files to a private local cache, and upsert SourceDocuments rows.

Phase 2 is implemented for MVP: required Sheets tabs are verified or created, headers are rewritten when they drift, tab rows have typed read helpers, and stable-ID upserts merge existing rows instead of appending duplicates.

Phase 3 is implemented for MVP: extraction prompts, strict model-output schemas, JSON parsing/repair, OpenAI/Gemini vision adapters, and a mockable vision-model adapter are in place for credit card, bank activity, and mixed screenshots.

Phase 4 is implemented for MVP: extraction candidates can be normalized into Transactions, AssetSnapshots, and ReviewQueue items with stable IDs, account masking, basic amount/date parsing, duplicate-looking transaction detection, impossible-value checks, and review routing for missing, anomalous, duplicate-risk, or low-confidence fields. Pending SourceDocuments can now be processed into those tabs through the processing orchestrator.

Phase 5 is implemented for MVP: deterministic merchant categorization, category confidence scores, ambiguous merchant review routing, transaction-type categories, future-applicable correction memory, and review correction application are wired into processing.

Phase 6 is implemented for MVP: monthly summaries, quarterly summaries, and asset trend rows can be generated from the Sheets transaction and asset snapshot tabs.

Phase 7 is implemented for MVP: duplicate charges, spending spikes, visible balance drops, and missing month anomalies are generated into the `Anomalies` tab.

Phase 8 is implemented for MVP: the homepage is a single-user dashboard gated by the configured email query parameter and reads summaries, asset trends, review items, and anomalies from Google Sheets.

Phase 9 is implemented for MVP: a guided workflow endpoint can run ingestion, processing, and summary refresh in sequence, a sanitized demo seed endpoint can populate the dashboard for review, and the dashboard has clear empty, loading, and error states.

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


## Local Development

1. Install dependencies:

   ```bash
   npm install
   ```

2. Copy `.env.example` to `.env` and fill in the Google Drive folder ID, Google Sheet ID, service account credentials or OAuth credentials, AI key, and single-user email.

3. Start the app:

   ```bash
   npm run dev
   ```

4. Run Phase 1 ingestion with a POST request while the app is running:

   ```bash
   curl -X POST http://localhost:3000/api/ingest -H "Content-Type: application/json" -d "{}"
   ```

   To re-download and re-register known screenshots, send `{ "forceReprocess": true }` in the request body.

5. Process pending cached screenshots through extraction and normalization:

   ```bash
   curl -X POST http://localhost:3000/api/process -H "Content-Type: application/json" -d "{}"
   ```

   This writes normalized `Transactions`, `AssetSnapshots`, and `ReviewQueue` rows back to the configured Google Sheet.

6. Apply a review correction when needed:

   ```bash
   curl -X POST http://localhost:3000/api/corrections/apply -H "Content-Type: application/json" -d '{"reviewItemId":"review-id","fieldName":"category","newValue":"groceries","applyFuture":true}'
   ```

7. Refresh summary and asset trend tabs:

   ```bash
   curl -X POST http://localhost:3000/api/summaries/refresh
   ```

Private cached screenshots are written under `data/private/`, which is intentionally ignored by git. Files older than `SOURCE_IMAGE_RETENTION_DAYS` are removed at the start of ingestion.

## Capstone Demo Flow

1. Put 5 to 20 financial screenshots in the configured Google Drive folder.
2. Start the app with `npm run dev`.
3. Run the guided workflow:

   ```bash
   curl -X POST http://localhost:3000/api/workflow/run -H "Content-Type: application/json" -d "{}"
   ```

   Or seed sanitized demo data when Drive credentials/screenshots are not ready:

   ```bash
   curl -X POST http://localhost:3000/api/demo/seed
   ```

4. Open the dashboard:

   ```text
   http://localhost:3000?email=YOUR_CONFIGURED_EMAIL
   ```

5. Review pending items in the dashboard and apply corrections with `/api/corrections/apply` when needed.
6. Corrections automatically refresh trend and anomaly tabs; use `/api/summaries/refresh` only when you want to rebuild summaries manually.

## Definition of Done for the Capstone Demo

The demo should show a user placing financial screenshots into a dedicated source, running the assistant, reviewing a few low-confidence items, and opening a Google Sheet or web dashboard that displays monthly spending by category plus asset trend context.


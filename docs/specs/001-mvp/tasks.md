# MVP Implementation Tasks

Use these tasks as the source of truth for incremental implementation.

Status: Phases 0 through 9 are implemented for the submitted Drive-first MVP. Phase 10 remains an optional Google Photos extension and is intentionally deferred.

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

- [ ] Evaluate Google Photos Picker API for user-selected screenshots.
- [ ] Add Photos source type without changing downstream data model.
- [ ] Store processed media IDs or selection timestamps.
- [ ] Document limitations clearly.

Acceptance:

- Photos ingestion is optional.
- Drive ingestion remains the stable default.


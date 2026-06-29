# MVP Implementation Tasks

Use these tasks as the source of truth for incremental implementation.

## Phase 0: Project Foundation

- [ ] Choose TypeScript/Next.js or another stack and scaffold the app.
- [ ] Add environment variable loading and validation.
- [ ] Add shared domain types for source documents, transactions, asset snapshots, review items, anomalies, and run state.
- [ ] Add test framework and a small fixture directory for sanitized sample images or mocked extraction responses.
- [ ] Add a local development README once the app exists.

Acceptance:

- The app starts locally.
- Required environment variables are validated.
- Domain types compile.
- At least one basic test runs.

## Phase 1: Google Drive Ingestion

- [ ] Implement Google OAuth setup or service-account setup, depending on the chosen app model.
- [ ] List image files in a configured Google Drive folder.
- [ ] Track processed file IDs.
- [ ] Download or stream unprocessed image content for extraction.
- [ ] Write SourceDocuments rows to Google Sheets or a temporary local store.

Acceptance:

- A run can discover new screenshots in the Drive folder.
- Re-running does not process the same file twice.
- Unsupported files are skipped with masked warnings.

## Phase 2: Google Sheets Foundation

- [ ] Create or verify required tabs.
- [ ] Implement typed read/write helpers.
- [ ] Implement upsert behavior by stable ID.
- [ ] Add tests for row mapping and idempotent writes.

Acceptance:

- The app can create or update all MVP tabs.
- Re-running sample writes does not duplicate rows.

## Phase 3: Screenshot Extraction

- [ ] Create a strict JSON extraction prompt for credit card screenshots.
- [ ] Create a strict JSON extraction prompt for bank activity and balance screenshots.
- [ ] Implement AI extraction client.
- [ ] Add JSON repair or retry behavior.
- [ ] Store raw evidence text with extracted records.
- [ ] Add tests using mocked model responses.

Acceptance:

- Sample extraction responses produce transaction and asset snapshot candidates.
- Invalid model output fails gracefully and creates a processing error.

## Phase 4: Normalization and Validation

- [ ] Normalize dates, amounts, merchants, account labels, and transaction types.
- [ ] Mask account identifiers.
- [ ] Detect missing fields and impossible values.
- [ ] Detect duplicate-looking transactions.
- [ ] Generate review queue items.

Acceptance:

- Messy extracted rows become predictable normalized records.
- Low-quality records are routed to review instead of silently accepted.

## Phase 5: Categorization

- [ ] Add deterministic merchant rules.
- [ ] Add AI classification fallback for unknown merchants.
- [ ] Add category confidence and reasons.
- [ ] Store future-applicable user corrections as merchant memory.
- [ ] Route low-confidence categories to review.

Acceptance:

- Common merchants are categorized.
- Ambiguous merchants are flagged when confidence is low.
- User corrections can update category outcomes.

## Phase 6: Summary and Trend Generation

- [ ] Generate MonthlySummary rows.
- [ ] Generate QuarterlySummary rows.
- [ ] Generate AssetTrends rows.
- [ ] Add maintainability flags when spending rises and balances fall.

Acceptance:

- The sheet shows spending by month and category.
- The sheet shows quarterly totals where data exists.
- Asset trend rows update after new bank snapshots.

## Phase 7: Anomaly Detection

- [ ] Detect duplicate charges.
- [ ] Detect spending spikes by category.
- [ ] Detect visible balance drops.
- [ ] Detect missing or incomplete months.
- [ ] Write Anomalies rows with suggested actions.

Acceptance:

- At least three anomaly types are implemented.
- Each anomaly includes a user-facing summary and suggested action.

## Phase 8: Single-User Web App

- [ ] Add single-user access restriction by configured email.
- [ ] Read summary, asset, review, and anomaly data from Google Sheets.
- [ ] Build monthly category chart.
- [ ] Build quarterly trend chart.
- [ ] Build asset trend chart.
- [ ] Build review queue and anomaly panels.

Acceptance:

- The configured user can view the dashboard.
- Other users are blocked.
- Dashboard reflects changes in the Google Sheet.

## Phase 9: Capstone Demo Polish

- [ ] Add one-click or guided workflow run.
- [ ] Add demo dataset instructions.
- [ ] Add clear empty, loading, and error states.
- [ ] Add screenshots or short demo notes.
- [ ] Update README with final setup and run instructions.

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


# Requirements — Local-First iOS (002)

## User stories

### US-001 Configure local sources
As the user, I can import screenshots from Photos or Files, and receive images or AI JSON via Share Extension, so I do not need Google Drive.

### US-002 Extract credit-card and bank activity
As the user, the app extracts transaction and balance candidates from screenshots using on-device Vision OCR (and optional Foundation Models), or accepts structured JSON from an external AI app.

### US-003 Normalize and mask
As the user, dates, amounts, merchants, and account labels are normalized; account numbers are masked in evidence and logs.

### US-004 Categorize with memory
As the user, known merchants are categorized by rules and prior corrections; novel merchants use on-device AI when available, otherwise review or paste.

### US-005 Review and correct
As the user, I can resolve low-confidence, missing-field, duplicate, anomaly, and unclear-category items; corrections can apply to future similar merchants.

### US-006 Local durable store
As the user, all processed data persists in on-device SwiftData and works offline.

### US-007 Dashboard and insights
As the user, I see monthly/quarterly category totals, cash flow, asset trends, anomalies, and prioritized next-best actions.

### US-008 Evidence audit
As the user, I can open a source document and see the image, extracted rows, and linked reviews/anomalies.

### US-009 Retention and export
As the user, I can configure source-image retention, explicitly delete the stored image while retaining extracted records, export a versioned JSON backup (optional originals) or analysis CSV, and restore a backup by replacing the local dataset after preview and confirmation.

### US-012 Accounts, currencies, and privacy
As the user, I manage stable accounts with ISO currencies, map legacy label groups explicitly, see unmapped/unknown-currency rows excluded from totals with a repair path, and optionally lock the app with Face ID / device passcode (off by default) with an automatic privacy cover when inactive.

### US-010 Manual activity and correction
As the user, I can add spending or other activity without a screenshot, search my transactions by merchant/card, and correct fields or category while preserving audit evidence.

### US-011 Card and layout context
As the user, I can choose Apple Card or Capital One Venture X, enter another card name, select a screenshot layout, and supply a statement month for yearless date headers.

## Non-functional

- No Google credentials required for the happy path.
- No cloud AI key required for the happy path.
- Idempotent re-import: same local source + row identity does not duplicate transactions.
- Mask sensitive identifiers in logs and error summaries.
- Baseline: iOS 18+. Foundation Models features gated by availability.
- Unit tests cover normalize, validate, categorize, summaries, anomalies, privacy, and AI JSON import parsing.

## Acceptance criteria

1. Import a screenshot without network access and produce at least OCR-backed candidate rows or a clear review item.
2. Paste valid extraction JSON and persist normalized transactions.
3. Correct a novel merchant category with “remember” and see the next similar merchant auto-categorized.
4. Dashboard reflects summaries after import and after corrections without any Google API calls.
5. USD and KRW totals never combine; unknown currencies and unmapped accounts are withheld with visible counts.
6. Versioned backup round-trips records and evidence; failed restores leave the prior dataset intact; CSV is clearly not a restorable backup.
7. Asset trends distinguish missing coverage from zero and show previous-observation change when the prior calendar month is absent.
8. With app lock enabled, cancelling authentication leaves financial content covered and pauses processing.

# Data Model — Local-First iOS (002)

SwiftData entities mirror the 001-mvp Sheets tabs. Field semantics are unchanged unless noted.

## SourceDocument

| Field | Type | Notes |
| --- | --- | --- |
| sourceDocumentId | String | Local UUID or content-hash based ID |
| sourceType | String | photos, files, share, ai_import |
| fileName | String | Original name |
| mimeType | String | Image or text/json |
| localRelativePath | String | Path under app sandbox Sources/ |
| createdTime | Date | |
| modifiedTime | Date | |
| processedAt | Date? | |
| status | String | pending, needs_details, processed, skipped, error |
| errorSummary | String? | Masked |
| rawText | String? | Original OCR/evidence text; retained during JSON repair |
| contentFingerprint | String? | Full SHA-256 digest with image/json type prefix; optional for legacy stores |
| importedJSON | String? | Original pasted/shared JSON retained for retry and canonical identity, including attached repair |
| cardName | String? | User-selected masked card/account label; copied to extracted transactions |
| screenshotLayout | String? | automatic, appleCard, capitalOne, or generic; layout is distinct from card identity |
| observedMonthHint | String? | Optional YYYY or YYYY-MM statement context for dates without a year |
| ocrLinesJSON | String? | Local OCR text, confidence, and normalized geometry for reparse after image deletion |
| imageDeletedAt | Date? | Explicit removal of this app’s stored image; records and OCR remain |

## Transaction

Same fields as 001-mvp `Transactions`, with `sourceDocumentId` referencing local sources.

### Type vs category

- **transaction_type** is the cash-flow role: `expense`, `income`, `transfer`, `payment`, `fee`, `refund`, `unknown`.
- **category** is the spending purpose for expenses (`groceries`, `dining`, …).
- Non-spending types lock a matching category: income→`income`, transfer→`transfer`, fee→`fees`.
- Choosing category `income` or `transfer` also updates type so the pair never contradicts.
- Spending charts use expense/fee amounts only; cash-flow income uses type `income`.

## AssetSnapshot

Same as 001-mvp `AssetSnapshots`.

## ReviewItem

Same as 001-mvp `ReviewQueue`. `suggestedOptions` stored as JSON string. Optional `fieldName` identifies the affected transaction field (or duplicate reference); validation review IDs use target + issue type + field, independent of question wording. Existing review history remains intact. On field edits, legacy validation reviews are superseded by current field-specific issues.

## Correction

Same as 001-mvp `Corrections`, including `merchant_rule` + `apply_future` memory.

## MonthlySummary / QuarterlySummary / CashFlowSummary / AssetTrend / Anomaly / RunState

Same semantics as 001-mvp. Summaries and anomalies may be regenerated and replaced on each summarize pass (equivalent to Sheets `replaceRows`).

## Extraction JSON contract

External AI apps and Foundation Models must return the same shape as v1 `screenshotExtractionResultSchema`:

```json
{
  "source_document_id": "string",
  "screenshot_kind": "credit_card | bank_activity | mixed | unknown",
  "raw_text": "string",
  "extraction_confidence": 0.0,
  "transactions": [],
  "asset_snapshots": [],
  "warnings": []
}
```

## App settings (UserDefaults / AppStorage)

| Key | Default | Notes |
| --- | --- | --- |
| sourceImageRetentionDays | 30 | 0 = keep forever |
| showOptionalExtractionReviews | false | Include advisory transaction extraction checks in the Unreviewed list |
| enableFoundationModels | true | Used only when available |

## Import identity and commits

Local source IDs are UUID-based and override external JSON IDs. Images use their exact bytes for SHA-256 fingerprints. JSON is decoded to the existing extraction contract, its source ID is cleared, and sorted-key encoding is hashed. Source lookup also recognizes retained repair JSON, while preserving the original screenshot fingerprint. Optional fields allow existing stores to migrate without clearing user data. Backfill does not merge historical duplicates.

A shared coordinator/service serializes import work across await points. All row, review, completion, and derived-summary mutations stage in the same ModelContext and save once with autosave disabled. Rollback uses staged entity deletions, not SwiftData bulk deletion. Failed-source evidence is committed separately. Asset review editing is deferred; no asset validation-status field is introduced in this increment.

## Manual records and screenshot layouts

`manual` is an additional source type. Manual transactions receive stable UUID identities independent of their editable fields, and pass validation/duplicate checks before a single atomic summary rebuild. Transaction corrections preserve original evidence and write correction history. Card metadata edits preserve row identity and record account-label corrections.

The parser uses spatially aligned merchant/amount pairs. Apple Card dates appear beneath each row; Capital One dates apply from the nearest preceding header. A visible month/year supplies date context. The parser never assumes the current year for a missing screenshot year. Screen totals, reward percentages, navigation, and blurred content above sticky headers are excluded. All heuristic/model candidates remain reviewable.

Stored-image deletion keeps source IDs, fingerprints, transactions, and OCR evidence. It never deletes from the system Photos library. Sources without extracted rows can retry from retained OCR geometry after image deletion; older sources without saved geometry require their image or replacement JSON. Sources with existing rows use manual edits rather than silently replacing corrected data.

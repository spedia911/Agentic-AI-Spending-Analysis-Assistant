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
| importAccountId | String? | Explicit account selected for the image or PDF batch. Saved on the source for deferred processing and retries. |
| contentFingerprint | String? | Full SHA-256 digest with image/json type prefix; optional for legacy stores |
| importedJSON | String? | Original pasted/shared JSON retained for retry and canonical identity, including attached repair |
| cardName | String? | User-selected masked card/account label; copied to extracted transactions |
| screenshotLayout | String? | automatic, appleCard, capitalOne, or generic; layout is distinct from card identity |
| observedMonthHint | String? | Optional YYYY or YYYY-MM statement context for dates without a year |
| ocrLinesJSON | String? | Local OCR text, confidence, and normalized geometry for reparse after image deletion |
| imageDeletedAt | Date? | Explicit removal of this app’s stored image; records and OCR remain |

## Account

| Field | Type | Notes |
| --- | --- | --- |
| accountId | String (UUID) | Stable identity; never inferred from display label |
| label | String | Editable display name; renames preserve history |
| currencyCode | String | ISO 4217; changing currency requires a new account |

## Transaction

Same fields as 001-mvp `Transactions`, with `sourceDocumentId` referencing local sources, plus:

| Field | Type | Notes |
| --- | --- | --- |
| accountId | String? | UUID reference; nil = unmapped / excluded from aggregates |
| currencyCode | String? | ISO code; must match the mapped account |

### Type vs category

- **transaction_type** is the cash-flow role: `expense`, `income`, `transfer`, `payment`, `fee`, `refund`, `unknown`.
- **category** is the spending purpose for expenses (`groceries`, `dining`, …).
- Non-spending types lock a matching category: income→`income`, transfer→`transfer`, fee→`fees`.
- Choosing category `income` or `transfer` also updates type so the pair never contradicts.
- Spending charts use expense/fee amounts only; cash-flow income uses type `income`.
- Gross spending includes rent/utilities; recognized card settlements are excluded from spending and tracked separately.

## AssetSnapshot

Same as 001-mvp `AssetSnapshots`, plus `accountId` and `currencyCode` with the same mapping rules as transactions. Conflicting same-day balances for the same account/type/currency are withheld.

## ReviewItem

Same as 001-mvp `ReviewQueue`. `suggestedOptions` stored as JSON string. Optional `fieldName` identifies the affected transaction field (or duplicate reference); validation review IDs use target + issue type + field, independent of question wording. Existing review history remains intact. On field edits, legacy validation reviews are superseded by current field-specific issues.

## Correction

Same as 001-mvp `Corrections`, including `merchant_rule` + `apply_future` memory.

## MonthlySummary / QuarterlySummary / CashFlowSummary / AssetTrend / Anomaly / RunState / Dataset

Same semantics as 001-mvp, partitioned by `currencyCode` where applicable. Summaries and anomalies may be regenerated and replaced on each summarize pass (equivalent to Sheets `replaceRows`). `AssetTrend` stores `previousObservationDate` / `previousObservationChange` and always uses `maintainabilityFlag = unknown`. `Dataset` holds `datasetId` and last restored snapshot id for portable backups.

## Portable backup envelope

Versioned JSON (`PortableBackup`) with `schemaVersion`, `datasetId`, `snapshotId`, `generatedAt`, `complete`, `recordCounts`, payload + integrity hashes, accounts, attachments, and eligibility/spending maps. Downstream replacement: validate the entire snapshot, then atomically replace only records belonging to that dataset; never treat partial or legacy exports as authoritative without the legacy migration path.

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

A shared coordinator/service serializes import work across await points. All row, review, completion, and derived-summary mutations stage in the same ModelContext and save once with autosave disabled. Rollback uses staged entity deletions, not SwiftData bulk deletion. Failed-source evidence is committed separately. Balance review uses its linked review items and validates account, date, amount, and conflicts before confirmation.

## Manual records and screenshot layouts

`manual` is an additional source type. Manual transactions receive stable UUID identities independent of their editable fields, and pass validation/duplicate checks before a single atomic summary rebuild. Transaction corrections preserve original evidence and write correction history. Card metadata edits preserve row identity and record account-label corrections.

The parser uses spatially aligned merchant/amount pairs. Apple Card dates appear beneath each row; Capital One dates apply from the nearest preceding header. A visible month/year supplies date context. The parser never assumes the current year for a missing screenshot year. Screen totals, reward percentages, navigation, and blurred content above sticky headers are excluded. All heuristic/model candidates remain reviewable.

Stored-image deletion keeps source IDs, fingerprints, transactions, and OCR evidence. It never deletes from the system Photos library. Sources without extracted rows can retry from retained OCR geometry after image deletion; older sources without saved geometry require their image or replacement JSON. Sources with existing rows use manual edits rather than silently replacing corrected data.

### Desktop snapshot consumer

Decode `payload` from base64 and verify its SHA-256 against `payloadSHA256`. The decoded bytes are the UTF-8 records JSON. Validate the outer manifest with the v1 Swift codec, which encodes with sorted keys and ISO 8601 dates and hashes the result with `manifestSHA256` set to the empty string. Validate the expected counts, unique IDs, source and account references, attachment checksums, and account/currency mappings. Checksums detect corruption. They provide no sender authentication.

Stage a validated snapshot before a single database replacement keyed by `datasetId`. An already applied `snapshotId` is a no-op. Withhold older or ambiguous competing snapshots for user review. Exclude records with desktop eligibility set to false and retain their reasons and source IDs for audit. A missing row in a newer authoritative snapshot removes its previous contribution. Legacy JSON and transaction CSV have no replacement authority.

Use the exported spending components per currency. Gross spending includes expense and fee activity plus payments classified as spending such as rent and utilities. Refunds are positive magnitudes. Net spending is gross spending less refunds. Card settlements and internal transfers are separate. Fixtures in `AuditFixtures` and `AuditRemediationTests` exercise classification and snapshot transitions.

The [synthetic snapshot sequence](../../../ios/docs/fixtures/bridge-snapshot-sequence.json) contains five successive snapshots for one dataset, with expected eligible transaction and balance IDs and USD totals for each state. Each case's `snapshot` object is a complete input for a desktop consumer.


### Transaction billed currency

`currencyCode` remains the currency of the linked account in the v1 snapshot. Optional `confirmedBilledCurrency` records a user decision for one transaction and is used by iOS for its local amount and totals. A conflicting billed currency in the evidence blocks local and desktop eligibility until resolved. When an explicitly confirmed billed currency differs from the account currency, v1 consumers receive the valid account pair and `desktop: false` with `billed_currency_differs_from_account`. The optional field survives iOS restore. Including the amount in desktop totals would require a coordinated bridge change.


`assumedCurrencyCode` persists a currency assigned from the app default or an account’s optional `preferredSpendingCurrency`. It never replaces the v1 account/currency pair. Local totals use confirmed billed currency first, then the saved assumption or the account currency. The app default fills transactions with no account or previously assigned currency. Changing either default preserves existing assignments. Desktop v1 withholds account-free transactions and transactions whose billed currency differs from the account currency. Balances still use the account’s balance currency.

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
| status | String | pending, processed, skipped, error |
| errorSummary | String? | Masked |
| rawText | String? | OCR or imported text |

## Transaction

Same fields as 001-mvp `Transactions`, with `sourceDocumentId` referencing local sources.

## AssetSnapshot

Same as 001-mvp `AssetSnapshots`.

## ReviewItem

Same as 001-mvp `ReviewQueue`. `suggestedOptions` stored as JSON string.

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
| lowConfidenceThreshold | 0.75 | |
| enableFoundationModels | true | Used only when available |

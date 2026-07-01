# Data Model

Google Sheets is the MVP data store. Each tab should have stable headers and upsert behavior.

## Tab: SourceDocuments

Tracks input files and processing state.

| Column | Type | Notes |
| --- | --- | --- |
| source_document_id | string | Google Drive file ID |
| source_type | string | drive, photos, upload |
| file_name | string | Original file name |
| mime_type | string | Image MIME type |
| created_time | datetime | From source metadata |
| modified_time | datetime | From source metadata |
| processed_at | datetime | Workflow timestamp |
| status | string | pending, processed, skipped, error |
| error_summary | string | Masked, non-sensitive |

## Tab: Transactions

Normalized transaction records.

| Column | Type | Notes |
| --- | --- | --- |
| transaction_id | string | Stable deterministic ID |
| source_document_id | string | Links to SourceDocuments |
| observed_month | string | YYYY-MM |
| transaction_date | date | ISO date |
| merchant_raw | string | Extracted text |
| merchant_normalized | string | Clean merchant name |
| amount | decimal | Signed decimal |
| transaction_type | string | expense, income, transfer, payment, fee, refund, unknown |
| account_label | string | Masked account/source label |
| category | string | Spending category |
| category_confidence | decimal | 0 to 1 |
| extraction_confidence | decimal | 0 to 1 |
| validation_status | string | valid, needs_review, rejected |
| review_status | string | none, pending, resolved |
| evidence_text | string | Short source evidence |
| created_at | datetime | Workflow timestamp |
| updated_at | datetime | Workflow timestamp |

## Tab: AssetSnapshots

Visible bank or account balance snapshots.

| Column | Type | Notes |
| --- | --- | --- |
| asset_snapshot_id | string | Stable deterministic ID |
| source_document_id | string | Links to SourceDocuments |
| observed_month | string | YYYY-MM |
| observed_date | date | Date visible or inferred |
| account_label | string | Masked account/source label |
| balance | decimal | Visible balance |
| balance_type | string | checking, savings, credit_available, credit_balance, unknown |
| confidence | decimal | 0 to 1 |
| evidence_text | string | Short source evidence |
| created_at | datetime | Workflow timestamp |

## Tab: ReviewQueue

Human-in-the-loop review items.

| Column | Type | Notes |
| --- | --- | --- |
| review_item_id | string | Stable deterministic ID |
| target_type | string | transaction, asset_snapshot, source_document |
| target_id | string | Linked record |
| issue_type | string | low_confidence, missing_field, duplicate_risk, anomaly, unclear_category |
| severity | string | low, medium, high |
| question | string | Concise user-facing question |
| suggested_options | string | JSON array or delimited list |
| status | string | pending, resolved, ignored |
| user_answer | string | User correction |
| created_at | datetime | Workflow timestamp |
| resolved_at | datetime | Optional |

## Tab: Corrections

Stores user corrections, asset snapshot review decisions, and merchant memory.

| Column | Type | Notes |
| --- | --- | --- |
| correction_id | string | Stable ID |
| target_type | string | transaction, asset_snapshot, merchant_rule |
| target_id | string | Linked record |
| field_name | string | category, merchant_normalized, amount, date, observed_month, transaction_type, validation_status, account_label, balance, balance_type, observed_date, review_status |
| old_value | string | Original value |
| new_value | string | Corrected value |
| apply_future | boolean | Whether correction trains future merchant rule |
| created_at | datetime | Timestamp |

## Tab: MonthlySummary

Monthly category totals.

| Column | Type | Notes |
| --- | --- | --- |
| month | string | YYYY-MM |
| category | string | Spending category |
| total_amount | decimal | Sum of signed amounts |
| transaction_count | integer | Count |
| reviewed_count | integer | Corrected/reviewed rows |
| unresolved_count | integer | Pending review rows |
| month_over_month_delta | decimal | Difference from prior month |
| completeness_status | string | complete, partial, unknown |

## Tab: QuarterlySummary

Quarterly category totals.

| Column | Type | Notes |
| --- | --- | --- |
| quarter | string | YYYY-QN |
| category | string | Spending category |
| total_amount | decimal | Sum |
| transaction_count | integer | Count |
| quarter_over_quarter_delta | decimal | Difference from prior quarter |
| completeness_status | string | complete, partial, unknown |

## Tab: AssetTrends

Monthly asset trend view.

| Column | Type | Notes |
| --- | --- | --- |
| month | string | YYYY-MM |
| account_label | string | Masked account/source label |
| ending_balance | decimal | Latest visible balance for month |
| prior_month_balance | decimal | Optional |
| monthly_change | decimal | ending - prior |
| related_spending_total | decimal | Monthly expenses from transactions |
| maintainability_flag | string | ok, watch, concern, unknown |

## Tab: Anomalies

Detected issues that deserve attention.

| Column | Type | Notes |
| --- | --- | --- |
| anomaly_id | string | Stable ID |
| anomaly_type | string | duplicate_charge, spending_spike, balance_drop, recurring_change, missing_data |
| severity | string | low, medium, high |
| month | string | YYYY-MM |
| related_record_ids | string | Linked IDs |
| summary | string | User-facing summary |
| suggested_action | string | Recommended follow-up |
| status | string | open, resolved, ignored |
| created_at | datetime | Timestamp |

## Tab: Runs

Workflow run history.

| Column | Type | Notes |
| --- | --- | --- |
| run_id | string | Unique run ID |
| started_at | datetime | Timestamp |
| finished_at | datetime | Timestamp |
| status | string | success, partial_success, failed |
| files_seen | integer | Count |
| files_processed | integer | Count |
| transactions_created | integer | Count |
| review_items_created | integer | Count |
| anomalies_created | integer | Count |
| error_summary | string | Masked |

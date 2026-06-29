# MVP Requirements

## Scope

The MVP processes screenshots of credit card spending and bank activity stored in a dedicated Google Drive folder, then produces a Google Sheet and a single-user web dashboard.

## User Stories

### US-001: Configure Financial Screenshot Source

As a user, I want to configure a Google Drive folder so the assistant knows where to look for monthly financial screenshots.

Acceptance criteria:

- Given a configured folder ID, when the workflow starts, the system lists image files in that folder.
- Given a file has already been processed, when the workflow runs again, the system skips it unless a force reprocess option is enabled.
- Given a file is unsupported, when the workflow runs, the system logs a non-sensitive warning and continues.

### US-002: Extract Transactions from Credit Card Screenshots

As a user, I want the assistant to extract transaction date, merchant, and amount from credit card screenshots.

Acceptance criteria:

- Given a screenshot with visible transaction rows, when extraction runs, the system creates transaction candidates.
- Each candidate includes source file ID, source image reference, date, merchant description, amount, account source, extraction confidence, and evidence text.
- If required fields are missing, the candidate is marked for review instead of being silently dropped.

### US-003: Extract Bank Activity and Asset Snapshots

As a user, I want the assistant to extract bank account activity and visible balance snapshots so I can see whether spending is maintainable.

Acceptance criteria:

- Given a bank activity screenshot, when extraction runs, the system identifies activity rows where visible.
- Given a visible account balance, when extraction runs, the system creates an asset snapshot record.
- Asset snapshots include account label, balance amount, observed date or inferred statement month, source file ID, and confidence.

### US-004: Normalize Extracted Records

As a user, I want messy extracted data converted into consistent rows that can be used in Sheets and charts.

Acceptance criteria:

- Dates are normalized to ISO format where possible.
- Amounts are normalized to signed decimal values.
- Transaction types distinguish expense, income, transfer, payment, fee, refund, and unknown.
- Account labels are normalized without exposing full account numbers.

### US-005: Categorize Spending

As a user, I want transactions grouped into useful categories.

Acceptance criteria:

- Expense transactions receive a category and confidence score.
- Supported categories include groceries, dining, utilities, transportation, rent, subscriptions, shopping, healthcare, transfer, income, fees, and miscellaneous.
- Ambiguous merchants are marked for review when confidence is below the threshold.
- User corrections are stored so future categorization can improve.

### US-006: Validate and Review

As a user, I want the assistant to catch likely extraction or classification mistakes.

Acceptance criteria:

- The system flags duplicate-looking transactions.
- The system flags missing dates, missing amounts, unclear merchant names, and low-confidence categories.
- Review items include a concise question and suggested options.
- Applying a correction updates the relevant transaction and summary output.

### US-007: Write Google Sheets Output

As a user, I want the assistant to write all structured results into a Google Sheet.

Acceptance criteria:

- The system creates or updates the required tabs.
- The system writes transactions, review queue, anomalies, monthly summary, quarterly summary, and asset trend data.
- Re-running the workflow is idempotent for already processed files.
- Rows include source references so results are auditable.

### US-008: Generate Monthly and Quarterly Trends

As a user, I want monthly and quarterly spending summaries by category.

Acceptance criteria:

- Monthly totals are grouped by year-month and category.
- Quarterly totals are grouped by year-quarter and category.
- Trends include month-over-month delta where prior month data exists.
- Summary rows distinguish actual data from incomplete months.

### US-009: Show Asset Trend Context

As a user, I want to see whether spending is maintainable relative to visible asset balances.

Acceptance criteria:

- Asset snapshots are grouped by account label and month.
- The dashboard shows balance changes over time.
- The summary highlights months where spending rises while visible balances decline.

### US-010: Single-User Web App

As a user, I want a simple web app that reads from the generated Google Sheet.

Acceptance criteria:

- The app is restricted to one configured user email.
- The app displays monthly spending by category.
- The app displays quarterly trends when data exists.
- The app displays asset trend visualization.
- The app displays unresolved review items and anomalies.

## Non-Functional Requirements

- The workflow should be rerunnable without duplicating rows.
- Logs must not expose full account numbers or secrets.
- The system should fail gracefully when Google APIs are unavailable.
- The data model should support later Google Photos ingestion.
- The first implementation should work with a small demo dataset of 5 to 20 screenshots.


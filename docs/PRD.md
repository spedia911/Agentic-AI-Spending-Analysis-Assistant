# Product Requirement Document

## Product Name

Agentic AI Spending Analysis Assistant

## Problem

Monthly personal spending review is slow and error-prone. A user often has screenshots of credit card spending and bank activity, but turning those images into category totals, recurring payment checks, and asset trend insight requires manual review.

The goal is to automate most of that work while still letting the user correct ambiguous transactions.

## Target User

An individual user who wants a lightweight monthly financial review without manually entering every transaction into a spreadsheet.

## Product Goal

Build an agentic AI assistant that monitors a dedicated financial screenshot source, extracts and validates transaction and asset data, categorizes spending, writes structured monthly data into Google Sheets, and supports a single-user web app for monthly, quarterly, and asset trend visualization.

## Primary Demo Scenario

1. The user saves screenshots of credit card spending and bank account activity into a dedicated Google Drive folder.
2. The assistant finds images that have not been processed.
3. The assistant extracts transaction and balance data from each image.
4. The assistant validates, normalizes, and categorizes the extracted records.
5. The assistant asks for correction only when confidence is low or data appears inconsistent.
6. The assistant writes transactions, review items, anomalies, monthly summaries, quarterly summaries, and asset trends to Google Sheets.
7. The web app reads the sheet and displays spending and asset trend visualizations.

## In Scope for MVP

- Google Drive folder ingestion.
- Screenshot-based extraction for credit card and bank account activity.
- Structured transaction normalization.
- Category assignment with confidence scores.
- Review queue for low-confidence or suspicious items.
- Google Sheets writer.
- Monthly and quarterly category summaries.
- Asset trend from visible bank balance snapshots.
- Basic anomaly detection.
- Single-user web app that reads from Sheets.

## Out of Scope for MVP

- Full Google Photos automation.
- Gmail bill ingestion.
- PDF statements.
- Multi-user account support.
- Bank login or account aggregation.
- Automated payment actions.
- Production-grade financial advice.

## Future Scope

- Google Photos Picker ingestion for selected screenshots.
- Gmail receipt and bill discovery.
- PDF statement parsing.
- Recurring bill tracking.
- Natural-language review chat over the spreadsheet.
- More advanced anomaly detection.
- Forecasting maintainable spending against asset trends.

## Agentic Components

### Orchestrator Agent

Coordinates the workflow, tracks processed files, retries failed steps, and decides which agents run next.

### Ingestion Agent

Finds new files in the configured Google Drive folder and collects metadata such as file ID, name, created time, modified time, MIME type, and source URL.

### OCR and Vision Parsing Agent

Extracts raw text and structured transaction or balance candidates from screenshots.

### Normalization Agent

Converts extracted candidates into consistent transaction, account activity, and asset snapshot records.

### Validation Agent

Checks for impossible dates, missing amounts, duplicate-looking rows, sign errors, unclear merchants, and inconsistent balances.

### Categorization Agent

Assigns spending categories and confidence scores. It flags ambiguous merchants such as Amazon, Costco, Walmart, Target, PayPal, Venmo, and Apple.

### Correction Agent

Creates targeted user review items and applies user corrections back into the normalized data.

### Sheets Reporting Agent

Writes normalized records and summary tabs to Google Sheets.

### Trend and Anomaly Agent

Calculates monthly totals, quarterly totals, category deltas, asset trend changes, unusual spending increases, duplicate charges, and unmatched activity.

## Success Metrics

- Percent of images processed without manual intervention.
- Transaction extraction accuracy.
- Category accuracy after user correction.
- Percent of transactions categorized without review.
- Number of useful anomalies detected.
- User correction rate.
- Time saved compared with manual spreadsheet review.

## Privacy and Security

- Store no secrets in source control.
- Mask account numbers in logs and summaries.
- Keep original image retention configurable.
- Allow deletion of processed source records and derived rows.
- Keep the MVP single-user to reduce privacy and permission complexity.
- Avoid making financial recommendations that imply professional financial advice.

## Non-Goals

- The assistant is not a tax product.
- The assistant is not a bank data aggregator.
- The assistant is not a financial advisor.
- The assistant should not initiate payments or move money.


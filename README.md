# Agentic AI Spending Analysis Assistant

This is a Drive-first personal finance assistant for the Kaggle Vibe Coding Capstone Project.

It reads financial screenshots from a Google Drive folder, extracts transactions and balances with an AI vision model, writes structured rows to Google Sheets, and shows a single-user dashboard for monthly spending, asset context, and correction guidance.

## What Works Today

- Google Drive folder ingestion for screenshots.
- Google Sheets as the durable output store.
- Gemini or OpenAI vision extraction.
- Transaction normalization, validation, categorization, and review queue generation.
- Monthly and quarterly summaries.
- Asset trend rows from visible balance screenshots.
- Duplicate, spending spike, balance drop, and missing month anomalies.
- A single-user dashboard gated by `SINGLE_USER_EMAIL`.
- Dashboard action buttons for running the workflow, refreshing summaries, force reprocessing, and seeding demo data.
- A dedicated `/import` page for importing Drive snapshots into a private staging review before writing to Google Sheets.
- A dedicated `/review` page for applying many corrections at once.
- The Spending Analysis dashboard shows a correction notice instead of inline correction forms, so analysis stays uncluttered.
- A spending explorer with month/category filters, a clickable monthly category pie chart, category totals, and transaction rows.
- Spending Explorer transaction rows support inline category correction and removing a row from spending analysis.
- Review corrections can be filtered and folded by severity.
- Asset snapshot reviews, such as Card Balance checks, can be kept, ignored, or corrected from the review page.
- Month-only batch corrections for transactions where exact dates are not needed for monthly spending totals.
- Same-merchant transactions stay separate during review, so two transactions at the same store can receive different categories.
- Exact same-merchant, same-date, same-amount duplicate risks default to "duplicate - exclude from spending" for the second matching row.
- Separate dashboard metrics for spending, income, net cash flow, and transfers/card payments.
- Bank-account bill payments, such as utilities and rent, can count as spending when merchant evidence supports that category.
- Credit card payments found in bank activity are excluded from spending totals.
- A sanitized demo seed endpoint so you can test the dashboard without real screenshots.

Current limitation: anomaly resolution, richer source evidence navigation, source-document review handling, and deeper setup checks are still in progress. The dashboard now supports batch transaction correction, asset snapshot review correction, staged import review, and inline Spending Explorer cleanup. See [docs/specs/001-mvp/tasks.md](docs/specs/001-mvp/tasks.md) for the next implementation plan.

## What You Need Before Running

You need four things:

1. A Google Drive folder for screenshots.
2. A Google Sheet for output.
3. Google API credentials that can read the folder and edit the sheet.
4. An AI API key, usually Gemini for easiest setup.

The Drive folder can be empty at first. The Google Sheet can also be blank. The app will create the needed sheet tabs.

## Step 1: Create the Google Drive Folder

1. Open Google Drive.
2. Create a folder, for example `Financial Screenshots MVP`.
3. Open the folder.
4. Copy the folder ID from the URL.

Example:

```text
https://drive.google.com/drive/folders/1AbCDEFghiJKLmnoPQRstu
```

Use only this part:

```env
GOOGLE_DRIVE_FOLDER_ID=1AbCDEFghiJKLmnoPQRstu
```

To choose which screenshots the app analyzes, put only those screenshots in this folder. For testing, use a small folder with 1 to 3 screenshots.

## Step 2: Create the Google Sheet

1. Create a blank Google Sheet.
2. Copy the sheet ID from the URL.

Example:

```text
https://docs.google.com/spreadsheets/d/1SheetABCdefGHIjkl/edit
```

Use only this part:

```env
GOOGLE_SHEET_ID=1SheetABCdefGHIjkl
```

The sheet can be completely empty. The app will create tabs such as `Transactions`, `ReviewQueue`, `MonthlySummary`, `AssetTrends`, `Anomalies`, and `Runs`.

## Step 3: Create Google API Credentials

The app needs Google credentials to read Drive and write Sheets.

Recommended setup for this MVP:

1. Open Google Cloud Console.
2. Create or select a project.
3. Enable these APIs:
   - Google Drive API
   - Google Sheets API
4. Create a service account.
5. Create a JSON key for the service account.
6. Save the JSON file as `service-account.json` in this project folder.

`service-account.json` is already ignored by git. Do not commit it.

Open the JSON file and find the service account email. It looks like:

```text
something@your-project.iam.gserviceaccount.com
```

Share both of these with that email:

- The Google Drive screenshot folder.
- The Google Sheet.

Give the service account edit access to the sheet.

In `.env`, use:

```env
GOOGLE_SERVICE_ACCOUNT_KEY=service-account.json
```

## Step 4: Create an AI Key and Pick a Model

For Gemini:

1. Open Google AI Studio.
2. Create an API key.
3. Put it in `.env`.

Recommended default:

```env
AI_PROVIDER=gemini
AI_MODEL=gemini-2.5-flash
AI_API_KEY=your_gemini_api_key
```

To see which Gemini models your key can use:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_GEMINI_API_KEY"
```

If a returned model name is `models/gemini-2.5-flash`, use this in `.env`:

```env
AI_MODEL=gemini-2.5-flash
```

Do not include the `models/` prefix.

## Step 5: Create the `.env` File

From the project folder:

```bash
cd "/Users/namkyounglee/Documents/Kaggle Vibe Coding Capstone Project"
cp .env.example .env
```

Open it with TextEdit:

```bash
open -a TextEdit .env
```

If that does not work:

```bash
nano .env
```

In `nano`, save with `Control + O`, press `Enter`, then exit with `Control + X`.

Your `.env` should look like this, with your real values:

```env
GOOGLE_DRIVE_FOLDER_ID=your_drive_folder_id
GOOGLE_SHEET_ID=your_google_sheet_id
GOOGLE_SERVICE_ACCOUNT_KEY=service-account.json

AI_PROVIDER=gemini
AI_MODEL=gemini-2.5-flash
AI_API_KEY=your_ai_key

SINGLE_USER_EMAIL=your_email@example.com
LOW_CONFIDENCE_THRESHOLD=0.75
TIMEZONE=America/Los_Angeles
SOURCE_IMAGE_RETENTION_DAYS=30
```

Restart the app after changing `.env`.

## Step 6: Start the App

If your computer has Node and npm:

```bash
cd "/Users/namkyounglee/Documents/Kaggle Vibe Coding Capstone Project"
npm install
npm run dev
```

Keep that terminal open.

If `npm` or `node` is not found, install Node:

```bash
brew install node
```

Or use the bundled Codex Node runtime:

```bash
cd "/Users/namkyounglee/Documents/Kaggle Vibe Coding Capstone Project"
export PATH="/Users/namkyounglee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH"
./node_modules/.bin/next dev
```

Then open the dashboard with your real email:

```text
http://localhost:3000?email=your_email@example.com
```

Do not use the placeholder `YOUR_CONFIGURED_EMAIL`.

## Step 7: Test Without Real Screenshots

Use this first. It checks that the app can write to your Google Sheet and display dashboard data.

Open a second terminal window or tab. Keep the first terminal running the app server.

```bash
cd "/Users/namkyounglee/Documents/Kaggle Vibe Coding Capstone Project"
curl -X POST http://localhost:3000/api/demo/seed
```

Refresh the browser.

Expected result:

- The Google Sheet has populated tabs.
- The dashboard shows spending totals, the category pie chart, filtered spending rows, and asset trends.

## Step 8: Test With Real Screenshots

1. Put 1 to 3 screenshots in the configured Google Drive folder.
2. Use credit card transactions, bank activity, or balance screenshots.
3. Run the workflow from a second terminal:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d "{}"
```

Refresh the dashboard and check the Google Sheet tabs.

The app skips files it already processed. If you add new screenshots, run the workflow again.

To reprocess files already seen in the folder:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d '{"forceReprocess":true}'
```

Use force reprocess carefully because it reruns known files in that Drive folder.

## Current User Experience Notes

The MVP now includes the first assistant-grade UX slice, but a few dashboard workflows still need refinement.

Use the dashboard action center to import, run, or refresh the workflow. Use `/import?email=YOUR_CONFIGURED_EMAIL` when you want to review extracted snapshot rows before they are logged to Google Sheets. The import page lets you:

- Import snapshots from the configured Drive folder into a private staging file.
- Review extracted spendings grouped by each source snapshot.
- Correct transaction types, categories, amounts, months, and merchants before logging.
- Select common categories from a dropdown or add a custom category when needed.
- Save staged edits without writing to Google Sheets.
- Commit reviewed rows to Google Sheets only when ready.

Use the spending explorer on the dashboard to filter month/category totals and click a pie-chart category to inspect its transactions. From the transaction table, you can change a transaction category with a dropdown or remove a row from spending analysis. Use `/review?email=YOUR_CONFIGURED_EMAIL` when you want to clean many items already in the Sheet. The review page lets you:

- Select several pending reviews and apply them in one batch.
- Filter or fold reviews by high, medium, or low severity.
- Set a month like `2026-06` for many transactions without entering exact dates.
- Correct two transactions from the same merchant separately.
- Mark an exact duplicate as excluded from spending, or keep it as real spending when both rows are legitimate.
- Resolve asset snapshot reviews by keeping the snapshot, ignoring the review, or correcting month, date, balance, account label, or balance type.
- Leave "apply to future similar merchants" unchecked when same-merchant transactions should stay different.

If a bank activity row is extracted as `transfer` but is actually rent or another spending category, change the staged category to `rent` or another spending category before committing. Corrected transfer rows with explicit spending categories are included in spending analysis.

Known gaps:

- Duplicate anomalies show related records, but do not yet have one-click "keep both" or "mark duplicate" resolution.
- Source document review items still need richer correction handling.
- Full setup health checks for Drive, Sheets, and AI access are not yet available in the page.
- Evidence text is shown for review cards, but source screenshot preview/navigation is still future work.

These are now captured in the next implementation plan in [docs/specs/001-mvp/tasks.md](docs/specs/001-mvp/tasks.md).

## Useful API Endpoints

Seed sanitized demo data:

```bash
curl -X POST http://localhost:3000/api/demo/seed
```

Run the full Drive workflow:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d "{}"
```

Force reprocess known Drive files:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d '{"forceReprocess":true}'
```

Refresh summaries only:

```bash
curl -X POST http://localhost:3000/api/summaries/refresh
```

Apply a correction through the API:

```bash
curl -X POST http://localhost:3000/api/corrections/apply \
  -H "Content-Type: application/json" \
  -d '{"reviewItemId":"review-id","fieldName":"category","newValue":"groceries","applyFuture":true}'
```

Apply several corrections through the API:

```bash
curl -X POST http://localhost:3000/api/corrections/batch \
  -H "Content-Type: application/json" \
  -d '{"corrections":[{"reviewItemId":"review-id-1","fieldName":"category","newValue":"utilities"},{"transactionId":"txn-id-2","fieldName":"observed_month","newValue":"2026-06"}]}'
```

## Troubleshooting

If the browser says `Invalid environment variables`, check that `.env` exists and includes:

```env
GOOGLE_DRIVE_FOLDER_ID=
GOOGLE_SHEET_ID=
GOOGLE_SERVICE_ACCOUNT_KEY=
AI_API_KEY=
SINGLE_USER_EMAIL=
```

If the dashboard says it cannot read the sheet:

- Make sure the sheet ID is correct.
- Share the sheet with the service account email.
- Make sure Google Sheets API is enabled.

If Drive finds no files:

- Make sure the folder ID is correct.
- Share the folder with the service account email.
- Put supported image files in the folder: PNG, JPG/JPEG, WEBP, HEIC, or HEIF.

If `npm install` does not work:

- Check `node -v` and `npm -v`.
- Install Node with `brew install node`, or use the bundled runtime command above.

If `.env` changes do not apply:

- Stop the dev server.
- Start it again.

## Verification

Run these before submitting:

```bash
npm test
npm run lint
npx tsc --noEmit
npm run build
```

If you are using the bundled Node runtime, prefix the commands with:

```bash
export PATH="/Users/namkyounglee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH"
```

## Repo Map

- [AGENTS.md](AGENTS.md): agent instructions for this project.
- [docs/PRD.md](docs/PRD.md): product requirement document.
- [docs/specs/001-mvp/requirements.md](docs/specs/001-mvp/requirements.md): MVP user stories and acceptance criteria.
- [docs/specs/001-mvp/design.md](docs/specs/001-mvp/design.md): system design and agent architecture.
- [docs/specs/001-mvp/data-model.md](docs/specs/001-mvp/data-model.md): Google Sheets tabs and structured entities.
- [docs/specs/001-mvp/tasks.md](docs/specs/001-mvp/tasks.md): completed MVP tasks plus the next implementation plan.
- [docs/MVP_SUBMISSION.md](docs/MVP_SUBMISSION.md): capstone submission notes.
- [.env.example](.env.example): environment variable template.

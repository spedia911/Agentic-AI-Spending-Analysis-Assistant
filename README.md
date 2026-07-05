# Agentic AI Spending Analysis Assistant

This is a Drive-first personal finance assistant built for the Kaggle Vibe Coding Capstone.

It reads financial screenshots from a Google Drive folder, extracts transactions and balances with an AI vision model, writes structured rows to Google Sheets, and shows a single-user dashboard for monthly spending, asset context, and correction guidance.

## For Kaggle Reviewers

- Recommended track: **Concierge Agents**.
- Fast evaluation: run `npm run verify:ci` to check docs, privacy, tests, type checking, lint, and production build without private credentials.
- Full local evaluation: configure `.env`, then run `npm run verify`.
- Final external submission check: after publishing the project link and YouTube video, run `npm run submission:final` with the Kaggle URL environment values from the final checklist.
- Demo without private screenshots: start the app, open `/?email=YOUR_CONFIGURED_EMAIL`, and click **Seed demo data**.
- Recording and upload assets can be prepared locally under `docs/submission/`, but that folder is ignored by git and is not required for public repository review.
- Public-link guidance is in [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md); security and privacy notes are in [SECURITY.md](SECURITY.md).

## What Works Today

- Google Drive folder ingestion for screenshots.
- Google Sheets as the durable output store.
- Gemini or OpenAI vision extraction.
- Transaction normalization, validation, categorization, and review queue generation.
- Monthly and quarterly summaries.
- A generated `CashFlowSummary` Sheet tab for monthly spending, income, refunds, transfers/card payments, other payments, fees, and net cash flow.
- Asset trend rows from visible balance screenshots.
- Duplicate, spending spike, balance drop, and missing month anomalies.
- A single-user dashboard gated by `SINGLE_USER_EMAIL`.
- A visible review-only safety note: the assistant does not provide financial advice, initiate payments, or move money.
- Dashboard action buttons for running the workflow, refreshing summaries, force reprocessing, and seeding demo data.
- The dashboard can limit how many pending Drive files are processed in one run, which is useful when the folder has many screenshots.
- A dashboard "Test setup" checklist for environment values, Drive folder access, Google Sheet tabs, service-account readiness, AI provider/model configuration, and the single-user email gate.
- Force reprocess uses a two-step confirmation because it reruns already-known Drive files.
- A dashboard source-file audit lists recent tracked screenshots, statuses, timestamps, and masked processing messages.
- Source-file names link to a source evidence page with file metadata, extracted rows, open reviews/anomalies, a cached screenshot preview when available, optional row-region highlights, and a Drive handoff link.
- A dedicated `/import` page for importing Drive snapshots into a private staging review before writing to Google Sheets.
- A dedicated `/review` page for applying many corrections at once.
- The Spending Analysis dashboard shows a correction notice instead of inline correction forms, so analysis stays uncluttered.
- A spending explorer with month/category filters, a clickable monthly category pie chart, category totals, and transaction rows.
- Spending Explorer transaction rows support inline category correction and removing a row from spending analysis.
- Review corrections can be filtered by severity and issue type, then ranked by dollar impact inside each severity group.
- Asset snapshot reviews, such as Card Balance checks, can be kept, ignored, or corrected from the review page.
- Source document reviews can retry failed files, ignore unwanted files, or keep a source in its current status without editing Sheets manually.
- Month-only batch corrections for transactions where exact dates are not needed for monthly spending totals.
- Same-merchant transactions stay separate during review, so two transactions at the same store can receive different categories.
- Exact same-merchant, same-date, same-amount duplicate risks default to "duplicate - exclude from spending" for the second matching row.
- Separate dashboard metrics for spending, income, net cash flow, transfers/card payments, and unresolved review amount.
- A next-best-actions panel that prioritizes failed source files, pending reviews, open anomalies, negative cash flow, and asset balance concerns.
- A dashboard cash-flow table mirrors the generated `CashFlowSummary` output so reviewers can inspect money movement without opening the raw Sheet.
- An anomaly review panel shows related transaction or asset records, supports "keep both", "mark reviewed", "ignore", and duplicate exclusion decisions, and records decisions in the Corrections tab.
- Bank-account bill payments, such as utilities and rent, can count as spending when merchant evidence supports that category.
- Credit card payments found in bank activity are excluded from spending totals.
- A sanitized demo seed endpoint so you can test the dashboard without real screenshots.

Current limitation: screenshot-region highlighting appears only when the extraction model returns reliable coordinate hints. The dashboard now supports setup health checks, batch transaction correction, asset snapshot review correction, source-document review correction, staged import review, anomaly resolution, source-file audit, source evidence pages, cached local screenshot previews when available, and inline Spending Explorer cleanup. See [docs/specs/001-mvp/tasks.md](docs/specs/001-mvp/tasks.md) for the next implementation plan.

## What You Need Before Running

You need four things:

1. A Google Drive folder for screenshots.
2. A Google Sheet for output.
3. Google API credentials that can read the folder and edit the sheet.
4. An AI API key, usually Gemini for easiest setup.

The Drive folder can be empty at first. The Google Sheet can also be blank. The app will create the needed sheet tabs.

## Quick Preflight Check

Before starting the app, run this from the project folder:

```powershell
Set-Location "C:\path\to\Agentic-AI-Spending-Analysis-Assistant"
npm run doctor
```

It checks for Node, npm, installed dependencies, `.env`, required environment values, and the configured service-account key file without printing secrets.

On Windows, the npm scripts use small shell helpers. If PowerShell says `sh` is not recognized, install [Git for Windows](https://git-scm.com/download/win), open Git Bash in the project folder, and rerun the same npm command.

## Step 1: Create the Google Drive Folder

1. Open [Google Drive](https://drive.google.com/).
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

1. Create a blank Google Sheet from [sheets.new](https://sheets.new/).
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

1. Open the [Google Cloud Console](https://console.cloud.google.com/).
2. Create or select a project.
3. Enable these APIs:
   - [Google Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com)
   - [Google Sheets API](https://console.cloud.google.com/apis/library/sheets.googleapis.com)
4. Open [Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts) and create a service account.
5. On that service account, open **Keys**, create a JSON key, and download it.
6. Save the JSON file as `service-account.json` in this project folder.

`service-account.json` is already ignored by git. Do not commit it.

Open the JSON file and find the service account email. It looks like:

```text
something@your-project.iam.gserviceaccount.com
```

If you already have the app running, click **Check connections** in the dashboard. The setup checklist will show the service account email automatically when it can read `service-account.json`.

Share both of these with the service account email:

- The Google Drive screenshot folder.
- The Google Sheet.

Give the service account:

- Viewer access to the Drive screenshot folder, or Editor access if you want it to update file metadata later.
- Editor access to the Google Sheet.

This sharing step is required. The service account is the identity the app uses when it reads Drive and writes Sheets; your personal Google account access does not automatically carry over to the app.

In `.env`, use:

```env
GOOGLE_SERVICE_ACCOUNT_KEY=service-account.json
```

## Step 4: Create an AI Key and Pick a Model

For Gemini:

1. Open [Google AI Studio API keys](https://aistudio.google.com/apikey).
2. Create or select an API key.
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

From the project folder in Windows PowerShell:

```powershell
Set-Location "C:\path\to\Agentic-AI-Spending-Analysis-Assistant"
Copy-Item .env.example .env
notepad .env
```

On macOS, Linux, or Git Bash:

```bash
cd "/path/to/Agentic-AI-Spending-Analysis-Assistant"
cp .env.example .env
nano .env
```

The template already selects the recommended Gemini provider and model. Fill in your Drive, Sheet, service-account, AI key, and email values. In `nano`, save with `Control + O`, press `Enter`, then exit with `Control + X`.

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

Use this checklist while filling it in:

| `.env` value | Where to get it |
| --- | --- |
| `GOOGLE_DRIVE_FOLDER_ID` | Open the Drive screenshot folder and copy the text after `/folders/` in the URL. |
| `GOOGLE_SHEET_ID` | Open the Google Sheet and copy the text between `/d/` and `/edit` in the URL. |
| `GOOGLE_SERVICE_ACCOUNT_KEY` | Use `service-account.json` if the downloaded key file is saved in this project folder. |
| Service account email | Open `service-account.json` and copy `client_email`, or run **Check connections** in the app after startup. Share the Drive folder and Sheet with this email. |
| `AI_API_KEY` | Create it at [Google AI Studio API keys](https://aistudio.google.com/apikey). |
| `SINGLE_USER_EMAIL` | Use the email you will put in the dashboard URL, for example `http://localhost:3000?email=you@example.com`. |

Restart the app after changing `.env`.

## Step 6: Start the App

Use Node 20-24 when possible. Node 26 can trigger a Next.js development-stream cloning error; `npm run dev` will use a compatible bundled runtime when one is available.

On Windows PowerShell:

```powershell
Set-Location "C:\path\to\Agentic-AI-Spending-Analysis-Assistant"
npm install
npm run doctor
npm run dev
```

On macOS, Linux, or Git Bash:

```bash
cd "/path/to/Agentic-AI-Spending-Analysis-Assistant"
npm install
npm run doctor
npm run dev
```

Keep that terminal open.

If `npm` or `node` is not found, install Node 24 LTS from [nodejs.org](https://nodejs.org/). On Windows, also install [Git for Windows](https://git-scm.com/download/win) if `npm run doctor` or `npm run dev` says `sh` is not recognized.

Then open the dashboard with your real email:

```text
http://localhost:3000?email=your_email@example.com
```

Do not use the placeholder `YOUR_CONFIGURED_EMAIL`.

## Step 7: Test Without Real Screenshots

Use this first. It checks that the app can write to your Google Sheet and display dashboard data.

From the dashboard action center, click **Seed demo data**.

Refresh the browser.

Expected result:

- The Google Sheet has populated tabs.
- The dashboard shows spending totals, the category pie chart, filtered spending rows, and asset trends.

For developer testing, the same seed path is available as an API call:

```bash
curl -X POST http://localhost:3000/api/demo/seed
```

## Step 8: Test With Real Screenshots

1. Put 1 to 3 screenshots in the configured Google Drive folder.
2. Use credit card transactions, bank activity, or balance screenshots.
3. From the dashboard action center, set **Files this run** and click **Run Drive workflow**.

For developer testing, the same workflow is available as an API call:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d "{}"
```

Refresh the dashboard and check the Google Sheet tabs.

The app skips files it already processed. If you add new screenshots, run the workflow again. In the dashboard, use "Files this run" to process a small batch from a crowded Drive folder.

To reprocess files already seen in the folder:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d '{"forceReprocess":true}'
```

Use force reprocess carefully because it reruns known files in that Drive folder. In the dashboard, the first click arms the action and the second click confirms it.

## Current User Experience Notes

The MVP now includes the first assistant-grade UX slice for a reviewer-facing Drive-first demo.

Use the dashboard action center to test setup, import, run, or refresh the workflow. The "Test setup" action checks the configured Drive folder, Google Sheet, AI provider/model, service account path, and single-user email gate without processing screenshots. Use `/import?email=YOUR_CONFIGURED_EMAIL` when you want to review extracted snapshot rows before they are logged to Google Sheets. The import page lets you:

- Import snapshots from the configured Drive folder into a private staging file.
- Review extracted spending rows grouped by each source snapshot.
- Exclude an unwanted source snapshot before any rows are committed.
- Correct transaction types, categories, amounts, months, and merchants before logging.
- Select common categories from a dropdown or add a custom category when needed.
- Save staged edits without writing to Google Sheets.
- Commit reviewed rows to Google Sheets only when ready.

Use the spending explorer on the dashboard to filter month/category totals and click a pie-chart category to inspect its transactions. From the transaction table, you can change a transaction category with a dropdown or remove a row from spending analysis. Use `/review?email=YOUR_CONFIGURED_EMAIL` when you want to clean many items already in the Sheet. The review page lets you:

- Select several pending reviews and apply them in one batch.
- Filter or fold reviews by high, medium, or low severity, then narrow by issue type such as missing field, duplicate risk, unclear category, low confidence, asset snapshot, or source file.
- Set a month like `2026-06` for many transactions without entering exact dates.
- Correct two transactions from the same merchant separately.
- Mark an exact duplicate as excluded from spending, or keep it as real spending when both rows are legitimate.
- Resolve asset snapshot reviews by keeping the snapshot, ignoring the review, or correcting month, date, balance, account label, or balance type.
- Resolve source file reviews by retrying failed processing, ignoring an unwanted source, marking it processed, or keeping it as an error.
- Leave "apply to future similar merchants" unchecked when same-merchant transactions should stay different.

If a bank activity row is extracted as `transfer` but is actually rent or another spending category, change the staged category to `rent` or another spending category before committing. Corrected transfer rows with explicit spending categories are included in spending analysis.

Use the anomaly review panel on the dashboard when the assistant finds duplicate charges, spending spikes, balance drops, or missing-month checks. Duplicate charge cards show the related transaction rows and let you keep both rows or exclude one from spending analysis. Other anomaly cards can be marked reviewed or ignored. Decisions are written back to Sheets so later summary refreshes do not reopen ignored checks.

Known gaps are captured in the next implementation plan in [docs/specs/001-mvp/tasks.md](docs/specs/001-mvp/tasks.md).

## Useful API Endpoints

Check setup health without processing screenshots:

```bash
curl http://localhost:3000/api/setup/health
```

Seed sanitized demo data:

```bash
curl -X POST http://localhost:3000/api/demo/seed
```

Run the full Drive workflow:

```bash
curl -X POST http://localhost:3000/api/workflow/run \
  -H "Content-Type: application/json" \
  -d '{"maxDocuments":5}'
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

Resolve or ignore an anomaly through the API:

```bash
curl -X POST http://localhost:3000/api/anomalies/resolve \
  -H "Content-Type: application/json" \
  -d '{"anomalyId":"anomaly-id","decision":"ignored"}'
```

For duplicate-charge anomalies, exclude one related transaction from spending:

```bash
curl -X POST http://localhost:3000/api/anomalies/resolve \
  -H "Content-Type: application/json" \
  -d '{"anomalyId":"anomaly-id","decision":"mark_duplicate","duplicateTransactionId":"txn-id"}'
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
- Install Node 24 LTS from [nodejs.org](https://nodejs.org/).
- On Windows, install Git for Windows if npm scripts cannot find `sh`.

If `.env` changes do not apply:

- Stop the dev server.
- Start it again.

## Verification

Run this before submitting from your configured local environment:

```bash
npm run verify
```

That command includes the private preflight check for your real `.env`, Drive folder, Google Sheet, service account, AI key, and single-user email. It then runs the same gates individually listed below:

```bash
npm run doctor
npm run privacy:check
npm run package:check
npm run docs:check
npm test
npx tsc --noEmit
npm run lint
npm run build
```

For public repository CI, use:

```bash
npm run verify:ci
```

That CI-safe command skips private credential preflight, sets harmless placeholder environment values for build-time checks, and still runs privacy checks, docs checks, tests, type check, lint, and production build.

## Repo Map

- [AGENTS.md](AGENTS.md): agent instructions for this project.
- [LICENSE](LICENSE): MIT license for public project reuse.
- [SECURITY.md](SECURITY.md): security, privacy, data-handling, and reporting notes.
- [docs/PRD.md](docs/PRD.md): product requirement document.
- [docs/specs/001-mvp/requirements.md](docs/specs/001-mvp/requirements.md): MVP user stories and acceptance criteria.
- [docs/specs/001-mvp/design.md](docs/specs/001-mvp/design.md): system design and agent architecture.
- [docs/specs/001-mvp/data-model.md](docs/specs/001-mvp/data-model.md): Google Sheets tabs and structured entities.
- [docs/specs/001-mvp/tasks.md](docs/specs/001-mvp/tasks.md): completed MVP tasks plus the next implementation plan.
- [docs/DEMO_WALKTHROUGH.md](docs/DEMO_WALKTHROUGH.md): five-minute reviewer demo script and evaluation talking points.
- [docs/CAPSTONE_READINESS_AUDIT.md](docs/CAPSTONE_READINESS_AUDIT.md): requirement-to-evidence submission audit.
- [docs/SUBMISSION_PACKAGE_CHECKLIST.md](docs/SUBMISSION_PACKAGE_CHECKLIST.md): final include/exclude checklist before upload.
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md): public project link and optional hosted demo guidance.
- `docs/submission/`: optional local-only workspace for Kaggle writeup drafts, recording decks, YouTube metadata, contact sheets, and media assets. This folder is intentionally ignored by git.
- [docs/references/google-photos-picker-evaluation.md](docs/references/google-photos-picker-evaluation.md): Google Photos Picker evaluation and future extension plan.
- [docs/MVP_SUBMISSION.md](docs/MVP_SUBMISSION.md): capstone submission notes.
- [.env.example](.env.example): environment variable template.

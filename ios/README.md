# Spending Assistant (iOS v2)

Local-first SwiftUI app for screenshot-based spending analysis. No Google Drive, Sheets, or cloud AI keys required for the core loop.

## Features (consolidated)

### Import
- **Photos / Files** images, Share Extension, paste **AI JSON**, and **manual** transaction or balance entry
- Supported **bank statement PDFs** (unlocked text PDFs that reconcile opening/running/closing balances)
- Card/layout presets (Apple Card, Capital One, bank activity) and statement month/year for yearless dates
- Copyable prompts for mixed extraction and **balances-only** JSON (`docs/prompts/balance-extraction.md`, samples under `Resources/`)

### Extraction & storage
- Apple Vision OCR + heuristic layout parsers; optional on-device Foundation Models when available
- SwiftData for sources, transactions, assets, reviews, corrections, summaries, and anomalies
- Fingerprinted dedupe for identical image/JSON bytes; failed Share items stay retryable in the inbox

### Type vs category
- **Type** = cash-flow role: expense, income, transfer, payment, fee, refund
- **Category** = spending purpose (groceries, dining, …)
- Income / transfer / fee keep type and category locked together so cash flow and spending charts stay consistent

### Review & batch corrections
- **Merchant categories**: change category on the overview list and confirm (or confirm many at once); Samples only when needed
- **Duplicates**: same-import alerts compare each transaction **by date**; cross-import pairs support batch remove of copies
- Individual transaction editor with filtered category pickers, account match-for-screenshot, and undo while the page is open
- Transaction list with filters (category, account, merchant, year/month)

### Home dashboard
- Month and category filters; **color-coded** spending-by-category chart
- Cash flow totals and trends; provisional totals while reviews remain open
- **Asset trends** for checking, savings, 401(k), Roth/Traditional IRA, HSA, brokerage/investment
- Sparse balances are **forward-filled for up to about one month** from the latest observation

### Privacy & export
- On-device by default; masked account labels; configurable source-image retention
- Delete stored image without dropping extracted rows/OCR; versioned JSON backup + CSV export and replace-only restore from Settings
- Stable account UUIDs / ISO currencies, eligibility gating, optional Face ID lock, private-device validation checklist

## Requirements

- macOS with Xcode 16+
- iOS 18+ simulator or device
- Optional: Apple Intelligence / Foundation Models capable device for on-device structuring and novel-merchant classification

## Generate / open the Xcode project

```bash
cd ios
./scripts/generate-xcodeproj.sh
open SpendingAssistant.xcodeproj
```

Select the **SpendingAssistant** scheme and your iPhone/simulator, then press **⌘R**. The scheme runs the main app; its Share Extension builds as a dependency. If Xcode shows “Choose an app to run,” regenerate the project with the script above and reopen it. Alternatively, in **Product → Scheme → Edit Scheme → Run → Info**, select **SpendingAssistant.app** as the executable.

Install XcodeGen with `brew install xcodegen` first. The generator exits with an error if it is missing. The generated project is ignored by Git; regenerate it after pulling changes to `project.yml`. Checked-in Info.plists are authoritative and are not rewritten by generation.

```bash
./scripts/verify-plists.sh
```

## Targets

| Target | Role |
| --- | --- |
| `SpendingAssistant` | Main SwiftUI app + SwiftData |
| `ShareExtension` | Accept shared images and AI JSON text |
| `SpendingDomain` | Pure Swift domain package (normalize, validate, categorize, summaries, …) |

## Try the app on a simulator

1. Run **SpendingAssistant**. A fresh install starts empty.
2. **Settings → Accounts & currencies**: create synthetic USD and KRW accounts (same display labels stay distinguishable by ID).
3. **Import → Input type → Paste AI JSON** and paste `SpendingAssistant/Resources/sample-extraction.json`, or **Add transaction manually** / **Add balance manually** with account/currency selection. For balances-only practice, use `sample-balances.json` or **Copy balances-only prompt**.
4. **Review → Batch corrections**: confirm merchant categories from the overview, and open **Duplicates & anomalies** for same-import date compare or import-pair cleanup. Map any unmapped rows via **Review → Account & currency**.
5. Return to **Home**: pick a currency and month, inspect separate totals, excluded-count repair, cash flow, and asset previous-observation / carried-forward labels.
6. **Home → Export**: share a desktop JSON snapshot or transaction CSV. To test recovery, use **Settings → Data safety → Backup & restore**, save a backup, change or delete a record, then restore it.
7. Optional: enable **Require Face ID / device passcode**, background the app, and confirm the privacy cover.

## Domain tests

```bash
cd ios/Packages/SpendingDomain
swift test
```

## TestFlight notes

- Set a unique bundle ID under your team.
- Enable the App Group `group.com.spendingassistant.shared` on app + extension.
- Archive → Distribute → TestFlight.
- Privacy Nutrition Labels: data is On-Device; no account required.

## Architecture pointers

See [`docs/specs/002-ios-local/design.md`](../docs/specs/002-ios-local/design.md).

## Import and review behavior

- Photos, Files, pasted JSON, and Share use one serialized coordinator with batch progress and per-item outcomes. A failed item does not stop the remaining batch.
- Identical image bytes are imported once, regardless of filename or entry point. Re-encoded and overlapping screenshots are not automatically merged; similar incoming transactions are flagged for duplicate review.
- JSON identity uses the parsed content with sorted keys and excludes `source_document_id`. That external ID is metadata, not a trusted local identifier. Different content using the same placeholder receives different local sources.
- Completed sources are skipped without touching rows or resolved reviews. Legacy fingerprints are backfilled from retained images or valid JSON; existing IDs, historical duplicates, and correction history are preserved. Images already removed by retention cannot be fingerprinted retroactively.
- Empty OCR and invalid JSON create a source error and review item. **Sources → source → Retry import** retries retained input. When no rows exist, paste replacement JSON in the same source to repair it. A removed image requires reimport or JSON repair.
- Source completion, extracted rows, reviews, and derived summaries commit together. Failed commits roll back all these changes. Source failure evidence is saved separately when storage is available.
- Share attachments are written atomically. The host processes them at launch and on foreground activation, then displays a result on Home and Import. Failed payloads remain in the App Group inbox and appear under **Import → Share items needing attention**, with **Retry** and **Delete pending attachment**. Failed items do not retry automatically. Deleting an inbox attachment leaves its source/error history intact.
- Review actions apply to their own issue: choosing a category does not confirm an amount or date. **Confirm** revalidates edited data while preserving original evidence and transaction IDs. Optional extraction checks are in transaction details; anomaly decisions stay explicit. Duplicate choices are **Both charges are real**, **Reject this duplicate**, and **Keep pending**.
- The newest remembered merchant correction wins. Dashboard totals include usable pending transactions and are labelled **provisional** while review remains; rejected or invalid-date/amount rows are excluded.
- Balance review and evidence are available in the balance editor. On eligible iOS 26+ devices with Apple Intelligence ready, Foundation Models provides extraction fallback and category suggestions. Settings displays current availability; other devices use layout parsing, rules, manual entry, and user-supplied JSON.

## Simulator verification

```bash
./scripts/generate-xcodeproj.sh
./scripts/test-simulator.sh
# Optional: choose a specific installed iPhone simulator
SPENDING_TEST_DEVICE_ID=<simulator-uuid> ./scripts/test-simulator.sh
```

The script uses an available iPhone runtime. Tests include in-memory SwiftData integration, real Vision OCR on a synthetic image, and an isolated UI smoke path (seed → review → JSON import → repeat import → export). Hosted unit tests and UI tests use an in-memory app store with automatic Share inbox processing disabled; integration cases create their own isolated stores and inboxes. Tests do not clear the normal app store. CI runs domain tests, checks source and built plists, builds unsigned for the simulator, and runs integration/UI tests.

Manual ingestion check (use synthetic images only):

1. Create an image containing `01/01/2026 Safeway $12.00` and add it to Simulator Photos; keep a copy accessible through Files.
2. Import from Photos, then import the exact same bytes from Files. Expect one source/transaction and an already-imported outcome when bytes match. Photos may supply a re-encoded representation, which instead uses duplicate-risk review.
3. Share the image from Photos to **Spending Assistant** (the **Spending Import** extension), return to the app, and inspect the **From Share** result and source evidence.
4. Share invalid JSON text. It must remain under **Share items needing attention** across foreground transitions; retry explicitly or delete the pending attachment.
5. Import an image with no financial rows. Inspect the retained OCR/error, attach sample JSON in that source, and verify the error review resolves without creating a second source.

Device/TestFlight validation still requires your signing team, registered App Group, and personal screenshots kept outside Git. Use [`docs/VALIDATION_CHECKLIST.md`](docs/VALIDATION_CHECKLIST.md) and `./scripts/accuracy-report.sh` for private annotated Korean/English samples; screenshots and OCR stay out of the repository.

## Export to a Mac

Open **Home → Export** or **Settings → Export data**. **Share desktop export** sends a full JSON snapshot of transactions, balances, and evidence for Asset Management Assistant. Original images and PDFs are omitted. Import the latest file after each round of capture or review so the desktop receives new rows, edits, and deletions. The screen shows how many records are eligible for desktop totals. **Share transaction CSV** includes all transactions and billed currencies for Excel or Numbers.

Run these commands from the desktop Asset Management Assistant workspace:

```bash
python3 asset.py import ios "/path/to/spending-desktop-export.json"
python3 asset.py report
open .local/reports/report.html
```

## Backup, restore, and privacy

- **Settings → Data safety → Backup & restore → Save backup file** creates a recovery snapshot. You can include retained originals. Restore validates the backup and shows a preview before replacement. Independently edited copies do not synchronize.
- **Source file retention** removes aged copies stored by the app when it opens or when you run cleanup. The default is 30 days. Choose 0 days to keep copies indefinitely. Extracted records, OCR evidence, and reviews remain, as do originals in Photos or Files.
- Shared files contain sensitive data. The app protects its temporary copies and cleans them up after sharing or when it next launches.
- The optional **Face ID / device passcode** lock covers content when inactive or locked. Cancelling unlock leaves the cover up and pauses financial-data processing.

Live Share verification requires a signed simulator build so iOS registers the App Group. No developer certificate is needed for simulator ad-hoc signing:

```bash
xcodebuild -project SpendingAssistant.xcodeproj -scheme SpendingAssistant \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SpendingAssistantSignedSimulator CODE_SIGN_IDENTITY=- build
```

The unsigned CI build verifies compilation; integration tests use an isolated inbox directory to exercise handoff failures without relying on signing.

## Verified in this increment

- Domain unit tests covering duplicate batches, type/category classification, cash-flow income sync, asset forward-fill, bank/layout parsers, and reliability cases; simulator integration and UI smoke coverage for review/import/export paths.
- Live iPhone 18 Pro simulator (iOS 27.2), with an ad-hoc signed build: Photos Share saved a synthetic `01/01/2026 Safeway $12.00` image; foreground activation imported one transaction and displayed a provisional $12 total. Selecting that image through Photos and its saved copy through Files both reported **0 imported · 1 already imported · 0 failed**.
- Source/built plist verification, structure verification, and documentation checks passed.

This does not establish accuracy on real bank layouts or validate signed physical-device/TestFlight distribution. No personal financial images were used or committed.

## App artwork

The app icon and Settings brand mark use the supplied [mint wallet artwork](https://chatgpt.com/s/m_6af0c9a33d388191bc691eea1facbe61). Navigation and dashboard headings use the supplied [finance icon sheet](https://chatgpt.com/s/m_6af0c9879f108191b0957ecb7b06b997). Both originals are bundled in `Resources/Assets.xcassets`; `AppIcon` contains a 1024 × 1024 packaging copy of the wallet artwork. `FinanceIcon` slices the transparent 4 × 3 sheet at runtime and renders template icons for native selection tint and dark-mode contrast. No image service or network fetch is used by the app.

## Real card screenshots, manual input, and image removal

1. In **Import → Import settings (•••) → Choose card preset**, select **Apple Card** or **Capital One Venture X**, or enter a custom card name. The selected settings also apply to incoming Share attachments. Use automatic layout detection for other screenshots.
2. If the screenshot has dates without a visible year, enter **Statement month** as `YYYY-MM`. A visible month/year is otherwise used automatically. No current-year assumption is made.
3. Import the screenshots. Apple Card rows combine merchant, right-aligned price, and the numeric date beneath the merchant. Capital One rows inherit the nearest date header. Totals and reward badges are not transactions. Overlapping images may create duplicate-risk reviews; reject the repeated row after checking evidence.
4. For images that failed in an older build: **Sources → source → Save card and layout → Retry import using saved OCR / image**. Save a statement month if needed. Retry is intended for sources without existing rows; edit existing rows directly to preserve corrections.
5. **Import → Input type → Add transaction manually** or **Add balance manually**, or **Home → View and correct transactions → +**, adds spending, income, refunds, transfers, payments, fees, or asset balances. Enter a positive magnitude for transactions; the selected type determines the stored sign. Categories stay filtered to the type. Manual entries also receive duplicate/anomaly checks. After entering all rows for a failed source, its **Confirm all visible rows entered manually** action completes the source review while keeping individual transaction issues open.
6. Open any transaction in the searchable list or its Source to correct date, merchant, signed amount, card, type, and category. Saving preserves its original ID and evidence. Category selection is explicit; changing fields alone does not resolve unrelated review issues.
7. **Sources → source → Image storage → Delete stored image** removes the app’s copy after confirmation. Transactions, OCR text/geometry, card metadata, and fingerprint remain. The original Photos-library image is unchanged. Retained OCR lets a failed source retry after deletion; a legacy source without saved OCR geometry needs reimport or replacement JSON.

Eight supplied financial screenshots were checked privately through Apple Vision plus the parser: all 45 visible candidates had the expected date and amount, with the displayed aggregate total excluded. These are parser checks rather than a guarantee for every card layout. Images and OCR text are not included in the repository. Unit fixtures use synthetic data.

Foundation Models runs locally only when the device reports availability; unavailable, malformed, or failed model output falls back to review/manual entry. Model-generated suggestions are confidence-capped for human confirmation. Real-device model quality still needs validation; the deterministic parser handles the two supplied layouts without requiring the model.

## Delete records and review corrections

- **Home → View and correct transactions:** swipe left on a row and tap **Delete**. The first swipe deletion asks for confirmation. For several rows, tap **Select**, choose the rows, then tap **Delete selected** and confirm. You can also delete from an individual transaction’s detail page. These actions keep the source and remove the selected transactions from totals.
- **Sources → source → Delete source and all its records:** confirm to remove the app’s stored image and evidence, linked transactions, balances, and reviews. The original in Photos and correction history remain. The screenshot can be imported again. Use **Delete stored image** to keep the extracted records and OCR.
- **Review → transaction:** check the date, merchant, amount, item type, and account/currency against the evidence. Choose a mapped account (or leave unmapped to exclude from totals). Tap **Confirm** even when no edits are needed. If a category needs confirmation, review the suggestion and choose whether to remember it. Saving or confirming one issue leaves unrelated issues pending. Use **Undo last review or edit** while the detail page is open to restore the previous values, review state, and remembered category. You can edit the category later from the transaction list.

## Home trends, batch review, and bank screenshots

- Home defaults to the latest recorded month and partitions totals by ISO currency (no FX conversion). Transactions with no assigned currency or conflicting billed evidence are excluded with a link to the Account & currency review queue. Pick another month to change the spending summary and the end of the historical charts. The category filter narrows spending and its transaction list; cash flow is portfolio-wide within the selected currency. Spending bars are color-coded by category. Gross spending, refunds, and net spending are shown separately.
- Cash flow shows recorded monthly net flow and a dashed least squares line from two or more recorded months. Year over year compares the exact same month last year; a missing comparison is shown as unavailable and a zero baseline has no percentage. Months without data are not treated as zero. Income totals follow **type = income** (kept in sync with category Income).
- Asset trends group by account ID, balance type, and currency. Sparse updates are carried forward for up to about one month and labelled with the original observation date. When the prior calendar month is missing, Home shows previous-observation date and change instead of a false MoM. Three distinct months enable a dashed three-month historical extrapolation (not an investment-return forecast). Credit lines and open balance reviews are excluded.
- **Review → Batch corrections** is the primary path for merchant categories and duplicates. Same-import duplicates list every related date before compare/remove. Individual Unreviewed items remain for one-offs; sort by lowest confidence or newest.
- **Import → Import settings (•••) → Screenshot layout → Bank activity** parses clearly labeled payroll and deposits as income, with transfers and card payments kept separate. Review ambiguous credits and verify the transaction type. Supported text-based bank statement PDFs can be imported from Files; image-only PDFs are not parsed directly.

## Optional extraction checks

The normal Review queue prioritizes missing fields, category decisions, anomalies, and duplicate risks. Use **Review → ••• → Show optional extraction checks** to also list transactions with low extraction scores. Those scores are advisory and do not make usable transactions provisional on their own. To inspect an individual row, open **Transaction → ••• → Confidence and evidence**. Comparing the original text or screenshot can catch a misread digit, date, or a merchant paired with the wrong amount. Confirming a row records your decision; it does not train OCR or change the original extraction score. Remembering a category improves future category selection only.

## Bank files and bulk review

- **Bank screenshots:** set the account and **Statement month** in **Import → •••** when the screen shows only dates like “Oct 8.” If you leave it blank, import asks for the missing year and account after reading the screenshot. The bank parser reads the amount beside the merchant, skips the running balance underneath, and uses the row's deposit or transfer label. Confirm the type of ambiguous credits. To recover a failed source without rows, save the month and layout in **Sources**, then retry. A completed source remains deduplicated; if a prior attempt produced incorrect rows, review them or delete that source before reimporting.
- **PDF statements:** select **Import → Choose from Files (images or PDF)**. The supported format is an unlocked text PDF with one checking or savings account, a printed statement period, signed amounts, and opening, running, and closing balances. An unreconciled table imports no rows. The closing balance appears in asset history, and the original PDF is available from **Sources → View original PDF**. Scanned, locked, and other unsupported layouts show an error; use screenshots or structured JSON for those.
- **Account matching:** changing an account applies to one transaction. Turn on **Match account for this screenshot** to explicitly update the other transactions from that source.
- **Merchant categories:** **Review → Merchant categories** lists merchants with an inline category picker and Confirm. Choosing Income or Transfer also updates transaction type. **Confirm categories for N merchants** applies mixed selections in one step. Matching ignores case, spaces, and punctuation; bank and card activity stay separately scoped when remembering rules.
- **Confirm** on a transaction detail returns to the previous list after saving. Required issues remain in Review until resolved.

## Missing screenshot details

When the app recognizes transaction rows but cannot read their year or account, it shows **Screenshot details** before importing the rows. Choose a year and an optional statement month, and choose a known account or enter a name. The original month and day on each row are kept. If dates cannot be read at all, enter a date only if it applies to every undated row, or choose to review the dates individually.

**Later** keeps the original and OCR for **Sources → source → Finish import**. For a source that already has transactions, **Account and date details → Save source details** saves the account to that source and repairs matching yearless dates. Turn on **Apply account to existing records from this source** to also update its existing rows. Dates with a year in the screenshot and dates edited manually stay as entered. Changes update the existing transactions and summaries without reimporting the source.

## Theme, date reuse, and statement-specific categories

- Home uses the system background, so text and charts follow light and dark appearance.
- When screenshot import needs a year, select it in the picker. Select a statement month if needed (especially around New Year). The app asks whether to use the same selection for the remaining yearless screenshots in that batch. It leaves each account and any readable dates alone.
- PDFs use dates and accounts printed on the statement first. A name like `20261031-Sample Checking.pdf` can fill in missing context. The file still has to reconcile against its opening, running, and closing balances.
- In merchant category review, bank and card transactions are separate groups. A category you remember for a bank payment does not change a fee from the same issuer on a card statement. Existing categories are preserved; older unscoped rules continue to apply to activity without an identified statement type.


## Account and billed currency

Choose an account on Import before picking an image or statement. The control shows the account’s normal currency and uses its saved identity. Use **Create account…** from the same control to create and select one in place. If the source provides an account name or currency, the form suggests it. Search currencies by code or localized name. **Settings → Default currency** assigns a currency to transactions that have no account or assigned currency. It fills previously unassigned transactions and applies to future imports and manual entries. Changing it preserves currencies already assigned.

Review compares the assigned currency with markers beside the billed amount. A bare dollar sign needs account or user context. An explicitly labeled original purchase amount is separate. Use **Review → Account & currency** to compare evidence, resolve one row, or map unmapped rows from one source together.

An explicit billed currency correction applies to one transaction and counts locally in that currency. If the billed currency differs from the account currency, the v1 backup retains the account pair, preserves the correction, and marks the transaction ineligible for desktop totals. The account’s default and the other transactions remain as entered.


Accounts are optional for local transaction totals. Save and reuse the same bank account or card when you want to track where a transaction was posted. Under **Settings → Accounts & currencies**, you can edit an account’s default spending currency for future transactions. The account ID and balance currency are preserved. Existing transactions retain their assigned currency.

Desktop v1 requires an account and a matching currency. An account-free transaction can appear in local totals and its backup while being withheld by the desktop importer. The same rule applies when an account’s spending currency differs from its balance currency.

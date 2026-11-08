# Spending Assistant (iOS v2)

Local-first SwiftUI app for screenshot-based spending analysis. No Google Drive, Sheets, or cloud AI keys required for the core loop.

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

## Demo path

1. Run **SpendingAssistant** on a simulator.
2. On Home, tap **Seed demo data** (synthetic transactions — no real finances).
3. Open **Review**, open the Blue Bottle transaction, and choose **dining** with “Remember for similar merchants” enabled.
4. Confirm Home insights and charts update.
5. **Import → Paste AI JSON** and use the sample in `SpendingAssistant/Resources/sample-extraction.json`, or copy the in-app extraction prompt into ChatGPT/Claude/Grok and paste the result.
6. Import the sample again: the result should say **already imported** and keep your corrections.
7. **Settings → Export JSON backup → Share export file** creates a JSON backup.

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
- Review actions apply to their own issue: choosing a category does not confirm an amount or date. **Save fields** revalidates edited data while preserving original evidence and transaction IDs. Confirm extraction/anomaly issues individually. Duplicate choices are **Both charges are real**, **Reject this duplicate**, and **Keep pending**.
- The newest remembered merchant correction wins. Dashboard totals include usable pending transactions and are labelled **provisional** while review remains; rejected or invalid-date/amount rows are excluded.
- Balance review remains visible with evidence but is not editable yet. Foundation Models adapters remain stubs; this build uses Vision, deterministic rules, and user-supplied AI JSON.

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

Device/TestFlight validation still requires your signing team, registered App Group, and personal screenshots kept outside Git.

Live Share verification requires a signed simulator build so iOS registers the App Group. No developer certificate is needed for simulator ad-hoc signing:

```bash
xcodebuild -project SpendingAssistant.xcodeproj -scheme SpendingAssistant \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SpendingAssistantSignedSimulator CODE_SIGN_IDENTITY=- build
```

The unsigned CI build verifies compilation; integration tests use an isolated inbox directory to exercise handoff failures without relying on signing.

## Verified in this increment

- 19 pure Swift domain tests and 12 simulator integration tests, including commit rollback and real Vision OCR on a generated synthetic screenshot.
- UI smoke: seed → category review → sample JSON → repeated JSON → backup export.
- Live iPhone 18 Pro simulator (iOS 27.2), with an ad-hoc signed build: Photos Share saved a synthetic `01/01/2026 Safeway $12.00` image; foreground activation imported one transaction and displayed a provisional $12 total. Selecting that image through Photos and its saved copy through Files both reported **0 imported · 1 already imported · 0 failed**.
- Source/built plist verification, structure verification, and documentation checks passed.

This does not establish accuracy on real bank layouts or validate signed physical-device/TestFlight distribution. No personal financial images were used or committed.

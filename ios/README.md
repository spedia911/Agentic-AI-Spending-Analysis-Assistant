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

If XcodeGen is not installed, the script falls back to opening the Swift Package workspace instructions and copies a checked-in project skeleton when present.

## Targets

| Target | Role |
| --- | --- |
| `SpendingAssistant` | Main SwiftUI app + SwiftData |
| `ShareExtension` | Accept shared images and AI JSON text |
| `SpendingDomain` | Pure Swift domain package (normalize, validate, categorize, summaries, …) |

## Demo path

1. Run **SpendingAssistant** on a simulator.
2. On Home, tap **Seed demo data** (synthetic transactions — no real finances).
3. Open **Review**, resolve a category with “Remember for similar merchants”.
4. Confirm Home insights and charts update.
5. **Import → Paste AI JSON** and use the sample in `SpendingAssistant/Resources/sample-extraction.json`, or copy the in-app extraction prompt into ChatGPT/Claude/Grok and paste the result.
6. **Settings → Export backup** to write a JSON backup into the share sheet.

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

# Tasks — Local-First iOS (002)

## Phase 0 — Specs and scaffold
- [x] PRD delta, requirements, design, data-model
- [x] Mark Google MVP as reference-only in AGENTS.md / README
- [x] Scaffold `ios/` XcodeGen project, Share Extension, SpendingDomain package

## Phase 1 — Local store + import
- [x] SwiftData models
- [x] Photos/Files import + local image storage + retention setting
- [x] Empty dashboard shell wired to store

## Phase 2 — Extraction
- [x] Vision OCR bridge
- [x] Heuristic line/table parser
- [x] Optional Foundation Models structurizer adapter
- [x] AI JSON import (paste / share text) + copyable prompt
- [x] Normalize → validate → persist

## Phase 3 — Categorization + review
- [x] Merchant rules + correction memory
- [x] Optional on-device category classifier adapter
- [x] Review queue UI + apply correction + regenerate summaries

## Phase 4 — Dashboard insights
- [x] Monthly / quarterly / cash-flow / asset trend / anomaly generators
- [x] Action-oriented home screen

## Phase 5 — Hardening
- [x] Idempotent upserts
- [x] Privacy masking
- [x] Backup export
- [x] Domain unit tests
- [x] Demo seed + TestFlight notes in `ios/README.md`

## Demo path

1. Open `ios/SpendingAssistant.xcodeproj` (generate via `ios/scripts/generate-xcodeproj.sh` if needed).
2. Run on simulator or device (iOS 18+).
3. Tap **Seed demo data** on Home, or Import → paste sample JSON from Resources.
4. Open Review, resolve one category, confirm Home insights update.
5. Settings → Export backup.

## Further work (post-MVP backlog)

### Product / UX
- [ ] Harden real-screenshot OCR on bank/credit-card layouts (multi-column, Korean/English mixed)
- [ ] Wire Foundation Models structurizer + category classifier for real on-device calls (replace no-op stubs)
- [ ] Improve Review UX (batch resolve, severity filters, dollar impact ranking like v1 web)
- [ ] Asset trend charts on Home (generator exists; UI mostly cash-flow + categories today)
- [ ] Face ID lock / privacy screen before showing balances
- [ ] Onboarding: copyable AI prompt + first-import walkthrough

### Ingestion
- [ ] Drain Share Extension inbox with user-visible “Imported from Share” toast/history
- [ ] Files/Photos multi-select progress + per-file error surfacing
- [ ] Optional Shortcuts / App Intent for “Import AI JSON”

### Data / reliability
- [ ] Prevent Xcode from stripping Share Extension / app Info.plist keys (or move keys into build settings)
- [ ] Check in or document regenerating `SpendingAssistant.xcodeproj` so clones don’t depend on ad-hoc local state
- [ ] Add `ios/**/.build/` to ignore hygiene if not already covered
- [ ] CSV export alongside JSON backup
- [ ] One-time import from v1 Sheets/CSV export (optional migration)

### Quality
- [ ] Run XCUITest smoke: seed → review → import sample JSON → export
- [ ] Device TestFlight build with App Group + unique bundle IDs under your team
- [ ] Real-device OCR accuracy pass on personal (non-committed) screenshots

### Cleanup
- [ ] Decide fate of Next.js Google MVP (`src/`): archive folder vs keep as algorithm reference only
- [ ] Close or merge GitHub PR #1 after local main is updated
- [ ] Bump XcodeGen `SWIFT_VERSION` in `ios/project.yml` to match tools 6.0 package

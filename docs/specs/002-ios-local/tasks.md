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
- [x] Drain Share inbox on launch/foreground with user-visible results, retained failures, retry/delete
- [x] Files/Photos multi-select progress + per-file error surfacing
- [ ] Optional Shortcuts / App Intent for “Import AI JSON”

### Data / reliability
- [x] Preserve authoritative app/extension Info.plists through XcodeGen and verify built settings
- [x] Document regenerating `SpendingAssistant.xcodeproj`; fail clearly when XcodeGen is missing
- [x] Ignore `ios/**/.build/` (already covered)
- [ ] CSV export alongside JSON backup
- [ ] One-time import from v1 Sheets/CSV export (optional migration)

### Quality
- [x] Run XCUITest smoke: seed → review → import sample JSON → repeat import → export
- [ ] Device TestFlight build with App Group + unique bundle IDs under your team
- [ ] Real-device OCR accuracy pass on personal (non-committed) screenshots

### Cleanup
- [ ] Decide fate of Next.js Google MVP (`src/`): archive folder vs keep as algorithm reference only
- [ ] Close or merge GitHub PR #1 after local main is updated
- [ ] Bump XcodeGen `SWIFT_VERSION` in `ios/project.yml` to match tools 6.0 package

## Reliability increment

- [x] Exact-byte image and canonical JSON fingerprints, independent local IDs, non-destructive legacy backfill
- [x] Shared import serialization, typed outcomes, batch progress, and per-file continuation
- [x] Empty/invalid extraction recovery with source evidence and attached JSON repair
- [x] Explicit atomic commits and rollback for rows, reviews, completion, and summaries
- [x] Transaction field editor and issue-specific category/confirmation/duplicate actions
- [x] Stable field-specific validation reviews and deterministic latest merchant memory
- [x] Duplicate risk against persisted rows; usable pending totals labelled provisional
- [x] In-memory SwiftData regression suite and synthetic Vision OCR check
- [x] macOS CI for domain tests, plist verification, unsigned build, and simulator tests
- [x] Simulator regression: 12 integration tests and 1 UI smoke passed; 19 domain tests passed
- [x] Live synthetic-image check: Photos Share imported one $12 Safeway row on foreground; Photos picker and Files both reported already imported

Deferred: editable asset reviews, Foundation Models calls, real bank OCR layouts, dashboard expansion, and signed device/TestFlight validation.

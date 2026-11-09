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
3. Use Import → Input type → Paste AI JSON with the synthetic sample from Resources.
4. Open Review, resolve one category, confirm Home insights update.
5. Settings → Export backup.

## Further work (post-MVP backlog)

### Product / UX
- [ ] Harden real-screenshot OCR on bank/credit-card layouts (multi-column, Korean/English mixed)
- [x] Wire availability-gated Foundation Models extraction and category calls; physical-device quality validation remains outstanding
- [x] Batch anomaly / merchant correction UX (same-import date compare, overview category confirm)
- [x] Color-coded spending-by-category chart
- [x] Asset balances: expanded account types, manual entry, one-month forward-fill, balances JSON prompt
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

Deferred: editable asset reviews, additional bank OCR layouts, dashboard expansion, physical-device model quality checks, and signed TestFlight validation.

## Real screenshot and manual-entry increment

- [x] Apple Card multiline transaction rows and Capital One date-header rows using Vision geometry
- [x] Local 16-bit screenshot normalization before Vision; retained OCR geometry/confidence for retry
- [x] Apple Card / Capital One Venture X presets, custom card labels, layout override, optional statement month
- [x] Stored-image deletion with confirmation; preserve records, evidence, and deduplication identity
- [x] Manual spending/activity entry and searchable transaction list; category/field editing for existing rows
- [x] Foundation Models availability-gated local calls; generated suggestions routed to review
- [x] Private local validation of all visible dates and amounts across eight supplied screenshots (45 candidates, including overlap)
- [x] Verification: 26 domain tests, 17 simulator integration tests, and 2 UI tests passed; source/built plists, scheme, and documentation checks verified

Personal screenshots and their OCR output are excluded from committed fixtures; layout tests use invented merchants and amounts. Overlapping screenshots produce duplicate-risk review rather than silently erasing potentially separate charges.

## Record deletion and clearer review
- [x] Single and bulk transaction deletion, confirmed source deletion, and refreshed totals.
- [x] Transaction summary, issue-specific review instructions, explicit category save, and undo on the detail page.
- [x] Integration coverage for deletion rollback, source reimport, and review undo.


## Consistent record actions and dashboard trends
- [x] Swipe edit/delete on transaction, source, and balance rows; edit records from their shared detail views.
- [x] Unified transaction summary with explicit merchant memory choice, plus Unreviewed and Reviewed filters.
- [x] Home month/category filters, cash flow regression and year-over-year comparisons, and per-account asset projections.
- [x] Screenshot-first Import with settings and input type controls; remove the user-facing seed action.
- [x] Recognize labeled income from bank screenshots; leave ambiguous credits for review.
- [x] Text-based bank statement PDF import from Files for the supported checking/savings table layout.


## Transaction confirmation and optional evidence
- [x] Select known accounts or enter a custom account in the shared transaction summary.
- [x] Confirm unchanged or edited transactions, with an explicit category prompt when needed.
- [x] Keep transaction extraction confidence advisory and accessible with source evidence in the detail menu.


## Bank statement recovery and bulk review
- [x] Read bank screenshot amounts separately from running balances and handle abbreviated date headers.
- [x] Recover physical PDF rows, verify signed amounts against running balances, and store the closing snapshot.
- [x] Apply account corrections to a screenshot source and category corrections to a matching merchant group.
- [x] Add merchant review and return to the previous list after completed confirmation.


## Missing screenshot metadata
- [x] Stage recognized screenshots with a missing year, date, or account, and resume without rerunning OCR.
- [x] Prompt after import, with a Sources recovery path and an individual date review option.
- [x] Repair source account labels and yearless dates in place while preserving explicit and manually entered dates.


## System theme and statement context
- [x] Use a theme-aware Home background.
- [x] Pick a year and month and offer to reuse them within an import batch.
- [x] Fill missing statement metadata from clear filename hints; keep printed metadata first.
- [x] Scope merchant categories to bank or card origin and return to the list after confirmation.

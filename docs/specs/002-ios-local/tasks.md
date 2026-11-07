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

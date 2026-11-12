# PRD Delta — Local-First iOS (v2)

## Summary

v2 replaces the Google Drive + Google Sheets + Next.js web MVP with a **local-first iOS app**. Screenshots stay on the device. Durable state is SwiftData. Cloud AI and Google APIs are not required for the core loop.

## Problem (unchanged)

Monthly personal spending review from credit-card and bank screenshots is slow and error-prone. The user wants extraction, categorization, review, and trend insight without manual spreadsheet entry.

## What changes

| Area | v1 (001-mvp) | v2 (002-ios-local) |
| --- | --- | --- |
| Client | Single-user Next.js web app | Native SwiftUI iOS app |
| Ingestion | Google Drive folder | Photos picker, Files, Share Extension |
| Extraction AI | Cloud Gemini / OpenAI vision | Apple Vision OCR + heuristics; optional Apple Foundation Models; Share/paste from ChatGPT/Claude/Grok |
| Categorization AI | Rules + optional cloud classifier | Rules + merchant memory + optional on-device Foundation Models; paste/manual fallback |
| Durable store | Google Sheets tabs | SwiftData on device |
| Auth / ACL | `SINGLE_USER_EMAIL` query gate | Device-local; optional Face ID / passcode lock (off by default) |

## What stays

- Screenshot-first input, with supported text-based bank statement PDF import from Files.
- Agentic loop: decide what to process → extract → normalize → validate → categorize → review → summaries → anomalies → action insights.
- Human-in-the-loop review queue and correction memory.
- Evidence audit from row back to source image.
- Categories, cash-flow separation, asset trends, anomaly types from 001-mvp.

## Primary demo scenario (v2)

1. User imports bank/credit-card screenshots from Photos or shares them into the app.
2. On-device OCR extracts text; heuristics and/or Foundation Models structure rows; or the user pastes JSON from an external AI app.
3. App normalizes, validates, categorizes, and queues uncertain rows.
4. User resolves reviews; merchant rules are remembered.
5. Home screen shows monthly/quarterly spending, cash flow, asset context, and next-best actions — fully offline.

## Out of scope (v2 MVP)

- Live Google Drive / Sheets backend
- Required cloud AI API keys
- Bank login / Plaid
- Scanned, locked, or unsupported PDF layouts
- Multi-user sync / iCloud sharing
- Direct private SDK hooks into ChatGPT / Claude / Grok apps
- Desktop importer / automatic sync / scheduling / holdings / market feeds (document integration contracts only; not end-to-end in iOS)
- FX conversion across currencies (totals stay partitioned by ISO currency)

## Audit remediation notes

Accounts use stable UUIDs with editable labels; unmapped or unknown-currency rows are excluded from aggregates until explicitly mapped. Exports use a versioned full-snapshot envelope (dataset/snapshot IDs, completeness, integrity hashes). Restore replaces the local dataset after preview and confirmation; independently edited copies do not synchronize. Downstream consumers must validate an entire snapshot before atomically replacing records for that dataset only.

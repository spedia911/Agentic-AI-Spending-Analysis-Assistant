# Agent Instructions

Use this file as the primary project guide when working in Antigravity or another agentic coding environment.

## Mission

Build an individual-only agentic AI spending analysis assistant. The **current product direction (v2)** is a **local-first iOS app** that ingests screenshots on-device, extracts and categorizes financial records with on-device AI (plus optional Share/paste from external AI apps), stores everything in SwiftData, and presents a SwiftUI dashboard.

The TypeScript Next.js + Google Drive/Sheets MVP under `src/` is retained as a **reference implementation** (algorithms, prompts, historical capstone demos). Do not add new Google-dependent product features unless explicitly requested.

## Read Order

Before coding on v2, read these files in order:

1. `docs/specs/002-ios-local/prd-delta.md`
2. `docs/specs/002-ios-local/requirements.md`
3. `docs/specs/002-ios-local/design.md`
4. `docs/specs/002-ios-local/data-model.md`
5. `docs/specs/002-ios-local/tasks.md`
6. `ios/README.md`

For algorithm parity with the reference MVP, also consult:

1. `docs/PRD.md` (v1 context)
2. `docs/specs/001-mvp/*`
3. `src/lib/{normalization,validation,categorization,summaries,anomalies,extraction,privacy,finance,dashboard}`

## Current Product Decisions (v2)

- Primary client: native iOS (SwiftUI), single user, on-device.
- Primary ingestion: Photos picker, Files, Share Extension.
- Durable store: SwiftData (not Google Sheets).
- Extraction AI: Apple Vision OCR + heuristics; optional Apple Foundation Models; Share/paste structured JSON from ChatGPT/Claude/Grok as fallback.
- Categorization AI: deterministic merchant rules + correction memory first; optional on-device model for novel merchants; review queue otherwise.
- First input type: screenshots, not PDFs.
- First analysis target: credit card spending plus bank activity and asset balances.
- Financial source of truth: on-device extracted rows + generated summary entities.

## Agentic Behavior Requirements

The implementation should not be a thin OCR pipeline. Agents must:

- Decide which files need processing.
- Extract raw text and structured rows.
- Validate parsed data and flag uncertainty.
- Categorize spending with confidence scores.
- Suggest corrections for low-confidence or suspicious records.
- Preserve enough evidence for the user to audit a result.
- Orchestrate reruns after corrections.
- Generate action-oriented summaries, not only charts.

## Implementation Guardrails

- Do not store secrets in the repo.
- Do not commit OAuth tokens, service account keys, generated screenshots, or financial source images.
- Mask account numbers and sensitive identifiers in logs.
- Keep source image retention configurable.
- Prefer small, testable increments over large rewrites.
- Add tests around parsing, normalization, categorization, summaries, and export.
- Keep Google Photos / Drive / Sheets optional and reference-only unless explicitly revived.

## Definition of Done for Each Task

Each completed task should include:

- Working implementation.
- Clear error handling for the expected failure modes.
- Unit or integration tests where practical.
- Updated documentation if behavior changes.
- A short demo path the user can run.

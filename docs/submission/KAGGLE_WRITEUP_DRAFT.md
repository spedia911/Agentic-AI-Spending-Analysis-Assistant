# Kaggle Writeup Draft

Track: Concierge Agents

Title: Agentic AI Spending Analysis Assistant

Subtitle: A private Drive-first finance agent that turns screenshots into auditable Sheets, human review queues, anomaly decisions, and next-best actions.

Estimated length: about 1,250 words. Kaggle limit: 2,500 words.

## Problem

Personal financial awareness is often trapped inside screenshots, app exports, and scattered banking interfaces. A person may have credit card spending in one place, bank activity in another, and balance snapshots elsewhere. The work of copying rows, reconciling duplicates, separating real spending from transfers, and finding unusual activity is tedious enough that many people do it rarely or give up.

This project solves that workflow for one user at a time. The assistant ingests screenshots from a dedicated Google Drive folder, extracts structured transactions and balance snapshots, validates and categorizes the results, routes uncertain records to human review, writes durable rows to Google Sheets, and presents a focused dashboard for spending, cash flow, assets, anomalies, and source evidence.

I chose the Concierge Agents track because the problem is personal, practical, and privacy-sensitive. The agent does not move money or provide financial advice. It helps a person organize their own records, inspect uncertain results, and decide what needs attention.

## Solution

The assistant is a Drive-first, single-user web app. The user places credit card or bank screenshots into a configured Google Drive folder. The app can run the full workflow, stage screenshots for review before they touch Sheets, seed a safe demo dataset, refresh summaries, test setup health, and force reprocess known files with a confirmation step.

The core product loop is:

1. Discover supported Drive screenshots and skip already-processed files unless forced.
2. Use a vision model to extract transaction candidates, balance snapshots, evidence text, confidence scores, and optional screenshot regions.
3. Normalize dates, merchants, account labels, transaction types, amounts, and observed months.
4. Categorize spending with deterministic rules, correction memory, and AI fallback.
5. Validate suspicious rows and create review items for missing fields, duplicate risk, low confidence, unclear categories, source-file failures, and balance questions.
6. Write durable outputs to Google Sheets tabs.
7. Generate monthly summaries, quarterly summaries, cash-flow summaries, asset trends, and anomalies.
8. Surface next-best actions in the dashboard so the user sees what to fix or investigate first.

This is intentionally not a thin OCR pipeline. The assistant makes workflow decisions, preserves evidence, produces audit trails, asks for corrections, and supports reruns after user decisions.

## Agent Architecture

Recommended visual attachment: [architecture-diagram.svg](architecture-diagram.svg).

The implementation is organized as a set of cooperating agent-like modules:

- Ingestion agent: lists Drive files, filters supported images, tracks processed source documents, downloads source screenshots, and controls reruns.
- Extraction agent: sends screenshots to the configured AI vision provider and expects strict structured JSON.
- Normalization agent: converts messy model output into consistent transaction and asset records.
- Validation agent: flags impossible dates, missing amounts, duplicate-looking rows, and other uncertainty.
- Categorization agent: combines deterministic rules, user correction memory, and AI classification.
- Correction agent: applies human decisions to transactions, asset snapshots, source documents, anomalies, and merchant memory.
- Summary agent: generates monthly, quarterly, cash-flow, asset trend, and anomaly tabs.
- Dashboard guidance agent: turns Sheet state into prioritized next-best actions.

Google Sheets is the durable memory layer. Tabs include `SourceDocuments`, `Transactions`, `AssetSnapshots`, `ReviewQueue`, `Corrections`, `MonthlySummary`, `QuarterlySummary`, `CashFlowSummary`, `AssetTrends`, `Anomalies`, and `Runs`.

## User Experience

The dashboard starts with setup confidence and action controls. A reviewer can test setup, seed safe demo data, import snapshots, run the Drive workflow, refresh summaries, limit files per run, and force reprocess with a two-step confirmation.

The staged import page is the pre-Sheets safety gate. It groups extracted rows by source screenshot, lets the user include or exclude each source snapshot, and supports edits to months, dates, merchants, amounts, transaction types, and categories before committing selected rows.

The review workbench supports batch corrections, severity filters, issue-type filters, dollar-impact ordering, month-only corrections, asset snapshot decisions, and source-document retry or ignore decisions.

The dashboard provides a spending explorer, category pie chart, cash-flow table, asset context, source-file audit, source evidence pages, and anomaly cards. Duplicate anomaly cards show related rows and let the user keep both or exclude one from spending.

## Course Concepts Demonstrated

This project demonstrates more than three required course concepts:

- Agent / multi-agent system: the workflow is split into ingestion, extraction, normalization, validation, categorization, correction, summarization, anomaly, and dashboard guidance modules.
- Antigravity: the repository includes Antigravity build prompts that document the agentic development flow used to shape the MVP.
- Security features: the app has a single-user email gate, redacted API/log errors, private screenshot cache, ignored secret files, tracked-file privacy checks, and review-only safety messaging.
- Deployability: the project includes a Next.js app, `.env.example`, setup health checks, preflight script, docs-check script, privacy-check script, and one-command `npm run verify`.
- Agent skills and tool use: the assistant uses Google Drive as the screenshot inbox, Google Sheets as durable memory, configurable AI vision extraction, deterministic validation, and human correction loops.

I am not claiming MCP Server or ADK-specific implementation in this MVP. Those would be natural future integration layers, but the current submission focuses on a practical Drive-first assistant with auditable human control.

## Technical Implementation

The app is built with Next.js and TypeScript. Domain types describe source documents, transactions, asset snapshots, review items, corrections, anomalies, run state, and generated summary rows. Google Sheets helpers create and update tabs through typed upsert and replace operations. The extraction layer supports Gemini and OpenAI-compatible vision adapters, with the default configured for Gemini.

The system is designed for rerunnable workflows. Source document IDs keep file processing idempotent. Transaction and asset IDs are deterministic. Force reprocess is available but guarded. Workflow runs write a `Runs` row with status, file counts, output counts, and masked error summaries.

The project includes unit and integration tests around parsing, extraction adapters, normalization, categorization, validation, summaries, cash-flow sign handling, corrections, staged import review, anomaly resolution, dashboard data access, setup health, privacy redaction, source evidence access, demo seeding, and workflow options.

## Safety And Privacy

The assistant is for review and organization, not financial advice. It does not initiate payments, move money, or connect to bank APIs. Screenshots are stored only in a private local cache path that is ignored by git. The privacy check scans tracked files for secret-shaped values and private artifact paths. API routes return redacted error details so account labels, keys, and sensitive identifiers are not leaked in UI messages.

The demo path can use sanitized seed data, which lets judges inspect the dashboard without exposing real financial screenshots.

## Demo

In the five-minute demo, I show:

1. `npm run verify` and setup health checks.
2. Safe demo seeding.
3. Dashboard action controls and next-best actions.
4. Spending and cash-flow analysis.
5. Staged import include/exclude review before writing to Sheets.
6. Batch correction and anomaly decisions.
7. Source evidence pages with cached preview support and Drive handoff.

## Scope And Next Steps

The submitted MVP is Drive-first. Google Photos is intentionally deferred until the Drive workflow is stable, and the repository includes an evaluation of how Photos Picker support would be added later.

Future improvements would include a deployed public demo with mock credentials, more export formats, richer charting, optional Google Photos Picker ingestion, and a stronger evaluation harness for extraction accuracy across screenshot layouts.

# Antigravity Project Context

## What To Build

Build the MVP described in `docs/specs/001-mvp/`.

The app should ingest Google Drive screenshots, extract credit card spending and bank activity, validate and categorize records, write Google Sheets outputs, and display a single-user dashboard.

## Most Important Constraints

- Use Google Drive as the first ingestion source.
- Use Google Sheets as the durable output.
- Keep Google Photos optional until the Drive path works.
- Keep the web app single-user.
- Protect financial privacy.
- Build incrementally using `docs/specs/001-mvp/tasks.md`.

## First Implementation Prompt

Start with Prompt 1 in `docs/prompts/antigravity-build-prompts.md`.


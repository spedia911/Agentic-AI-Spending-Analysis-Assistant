# Submission Package Checklist

Use this checklist immediately before packaging or linking the project for the Kaggle capstone submission.

## Include

- Source code under `src/`.
- Project configuration files:
  - `package.json`
  - `package-lock.json`
  - `tsconfig.json`
  - `eslint.config.mjs`
  - `next.config.ts`
- Setup and verification scripts under `scripts/`.
- Documentation under `docs/`.
- `.env.example`.
- `README.md`.
- `SECURITY.md`.
- `LICENSE`.
- `.gitignore`.

## Do Not Include

- `.env` or any `.env.*` file except `.env.example`.
- Google service account JSON keys.
- OAuth client secret files.
- API tokens.
- Cached financial screenshots under `data/private/`.
- Raw source images under `data/raw/`.
- Generated exports under `data/exports/`.
- Local build output such as `.next/`, `out/`, `dist/`, or `build/`.
- `node_modules/`.
- Browser screenshots or screen recordings that show private financial data.

These exclusions are already reflected in `.gitignore`, but check the package manually before upload.

## Required Pre-Submission Commands

Run:

```bash
npm run verify
```

This runs:

- setup preflight
- submission privacy check
- public package manifest check
- submission docs check
- unit and integration tests
- TypeScript type check
- lint
- production build

For public GitHub CI, the repository also includes:

```bash
npm run verify:ci
```

This CI-safe gate uses placeholder environment values and does not require private credentials.

After the YouTube video and public project link exist, run:

```bash
npm run submission:final
```

This final external gate requires `KAGGLE_PROJECT_LINK`, `KAGGLE_YOUTUBE_URL`, `KAGGLE_VIDEO_DURATION_SECONDS`, `KAGGLE_MEDIA_GALLERY_CONFIRMED=yes`, and `KAGGLE_TRACK_CONFIRMED='Concierge Agents'`.
It also requires `KAGGLE_WRITEUP_READY_CONFIRMED=yes` and `KAGGLE_PRIVATE_RESOURCES_CONFIRMED=yes`.

Expected current result:

- 26 test files passed
- 112 tests passed
- zero tracked secrets or private artifacts
- public package manifest check passes
- reviewer-facing docs pass package and demo checks
- zero TypeScript diagnostics
- zero lint issues
- production build succeeds
- public CI-safe verification succeeds

Kaggle package checks:

- Writeup has a selected track and stays under 2,500 words.
- Media Gallery includes a cover image and a YouTube video no longer than 5 minutes.
- Project link is public, or the public repository includes detailed setup instructions.
- Writeup/video explicitly demonstrate at least three course concepts such as multi-agent workflow, security features, deployability, and agent tool use.

## Reviewer-Facing Docs

Point reviewers to these files:

- [README.md](../README.md): setup and usage.
- [LICENSE](../LICENSE): MIT license.
- [SECURITY.md](../SECURITY.md): security, privacy, data-handling, and reporting notes.
- [DEPLOYMENT.md](DEPLOYMENT.md): public project link and optional hosted demo guidance.
- [MVP_SUBMISSION.md](MVP_SUBMISSION.md): concise submission notes.
- [DEMO_WALKTHROUGH.md](DEMO_WALKTHROUGH.md): five-minute demo script.
- [CAPSTONE_READINESS_AUDIT.md](CAPSTONE_READINESS_AUDIT.md): requirement-to-evidence map.
- [google-photos-picker-evaluation.md](references/google-photos-picker-evaluation.md): why Photos is deferred and how it would be added.
- [KAGGLE_WRITEUP_DRAFT.md](submission/KAGGLE_WRITEUP_DRAFT.md): paste-ready Kaggle Writeup draft under the 2,500-word limit.
- [ARCHITECTURE_AND_RUBRIC.md](submission/ARCHITECTURE_AND_RUBRIC.md): judge-facing architecture and evaluation evidence map.
- [KAGGLE_EVALUATION_SCORECARD.md](submission/KAGGLE_EVALUATION_SCORECARD.md): point-by-point Kaggle evaluation mapping.
- [USER_STORY_UI_REVIEW.md](submission/USER_STORY_UI_REVIEW.md): user-story trace, UI gap review, and demo shot checklist.
- [COURSE_CONCEPT_COVERAGE.md](submission/COURSE_CONCEPT_COVERAGE.md): required course-concept coverage and non-claims.
- [VIDEO_SCRIPT.md](submission/VIDEO_SCRIPT.md): YouTube demo narration and shot list.
- [MEDIA_GALLERY_PLAN.md](submission/MEDIA_GALLERY_PLAN.md): cover image, screenshots, and privacy checklist.
- [YOUTUBE_UPLOAD_METADATA.md](submission/YOUTUBE_UPLOAD_METADATA.md): upload title, description, chapters, tags, Public visibility, and video privacy checklist.
- [FINAL_KAGGLE_FORM_CHECKLIST.md](submission/FINAL_KAGGLE_FORM_CHECKLIST.md): final Kaggle fields and submit-time checks.
- [PUBLIC_REPO_MANIFEST.md](submission/PUBLIC_REPO_MANIFEST.md): public repository include/exclude manifest.

## Suggested Submission Summary

Use or adapt this text:

> Agentic AI Spending Analysis Assistant is a Drive-first, single-user finance assistant that ingests credit card and bank screenshots from a dedicated Google Drive folder, uses multimodal extraction to produce structured transactions and balance snapshots, validates and categorizes rows, routes uncertain records to human review, writes durable outputs to Google Sheets, and presents spending, cash-flow, asset-trend, anomaly, correction, and source-evidence workflows in a lightweight dashboard. It emphasizes agent orchestration, grounded evidence, human-in-the-loop correction, idempotent reruns, privacy guardrails, and reproducible verification.

## Suggested Demo Order

1. Run `npm run verify`.
2. Start the app with `npm run dev`.
3. Open the dashboard with `?email=YOUR_CONFIGURED_EMAIL`.
4. Seed safe demo data with the dashboard **Seed demo data** button.
5. Show setup health, action center, staged import include/exclude, Next Best Actions, Spending Explorer, cash-flow table, anomaly decisions, source-file audit, source evidence page, and `/review`.
6. Briefly describe the full Drive workflow with `maxDocuments` and force-reprocess guardrails.
7. Use `docs/submission/cover-image.svg` as the Media Gallery cover image or export it to PNG.
8. Include `docs/submission/architecture-diagram.svg` in the Writeup or video as the architecture visual.

## Final Manual Checks

- Confirm `.env` is not staged or packaged.
- Confirm `npm run package:check` passes before publishing the repository.
- Confirm service account files are not staged or packaged.
- Confirm `data/private/` is not staged or packaged.
- Confirm no screenshot contains private financial details.
- Confirm `docs/MVP_SUBMISSION.md` verification counts match the latest `npm run verify` output.
- Confirm `npm run verify:ci` passes before publishing the repository.
- Confirm `docs/submission/KAGGLE_WRITEUP_DRAFT.md` stays under 2,500 words after edits.
- Confirm the final YouTube video is 5 minutes or less and attached to the Kaggle Media Gallery.
- Confirm the YouTube upload uses [YOUTUBE_UPLOAD_METADATA.md](submission/YOUTUBE_UPLOAD_METADATA.md), is set to Public, and includes the public project link.
- Confirm the public project link points to either a public repository with setup instructions or a safe hosted demo.
- Confirm `npm run submission:final` passes after setting the final project/video environment values.
- Confirm the public repository satisfies [PUBLIC_REPO_MANIFEST.md](submission/PUBLIC_REPO_MANIFEST.md).
- Confirm [USER_STORY_UI_REVIEW.md](submission/USER_STORY_UI_REVIEW.md) still matches the final UI shown in the video.
- Confirm [KAGGLE_EVALUATION_SCORECARD.md](submission/KAGGLE_EVALUATION_SCORECARD.md) still matches the final Writeup and video.
- Confirm the Kaggle Writeup has the Concierge Agents track selected before submitting.
- Confirm the Kaggle Writeup is submitted, not left as a draft.
- Confirm no unintended private Kaggle Resources are attached to the public Writeup.
- Confirm the Writeup/video claim multi-agent workflow, Antigravity, security, deployability, and agent tool use without claiming MCP Server or ADK-specific implementation.
- Confirm Google Photos is described as optional/deferred, not as implemented ingestion.

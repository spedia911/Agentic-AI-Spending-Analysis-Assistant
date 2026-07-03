# Kaggle Evaluation Scorecard

Use this as the final judge-facing map from Kaggle's evaluation table to project evidence.

## Category 1: The Pitch - Problem, Solution, Value

Total: 30 points.

| Criterion | Points | Submission evidence |
| --- | ---: | --- |
| Core concept and value | 10 | The project solves a personal, privacy-sensitive reconciliation problem for the Concierge Agents track. It turns financial screenshots into auditable records, review queues, anomaly decisions, and next-best actions. |
| YouTube video submission | 10 | [VIDEO_SCRIPT.md](VIDEO_SCRIPT.md) covers the problem statement, why agents are useful, architecture, demo flow, build tools, course concepts, and safety within a target 4:30 to 4:50 recording. [YOUTUBE_UPLOAD_METADATA.md](YOUTUBE_UPLOAD_METADATA.md) prepares the upload title, description, chapters, and visibility checks. |
| Writeup | 10 | [KAGGLE_WRITEUP_DRAFT.md](KAGGLE_WRITEUP_DRAFT.md) explains the problem, solution, architecture, user experience, course concepts, implementation, safety, demo path, and future scope under the 2,500-word limit. |

## Category 2: The Implementation - Architecture, Code

Total: 70 points.

| Criterion | Points | Submission evidence |
| --- | ---: | --- |
| Technical implementation | 50 | Modular agent workflow; strict extraction schema; Google Drive ingestion; Google Sheets durable memory; typed domain model; deterministic IDs; rerunnable workflow; staged import review; correction memory; anomaly resolution; source evidence pages; setup health; redacted errors; tests, type check, lint, and production build. |
| Documentation | 20 | README, SECURITY, DEPLOYMENT, PRD, MVP requirements/design/data model/tasks, readiness audit, demo walkthrough, submission package checklist, public repo manifest, course concept map, user-story/UI review, architecture/rubric evidence, media plan, video script, and final Kaggle form checklist. |

## Required Course Concepts

Kaggle requires at least three course concepts. This project demonstrates five:

| Concept | Where demonstrated | Evidence |
| --- | --- | --- |
| Agent / multi-agent system | Code, writeup, video | Ingestion, extraction, normalization, validation, categorization, correction, summary, anomaly, and dashboard guidance modules. |
| Antigravity | Video and docs | [antigravity-build-prompts.md](../prompts/antigravity-build-prompts.md) records agentic build prompts and the video script calls it out. |
| Security features | Code and video | Single-user email gate, ignored secrets, private screenshot cache, redacted errors, privacy checks, and review-only safety note. |
| Deployability | Video and docs | Next.js app, `.env.example`, setup health, preflight, CI-safe verify, full local verify, and GitHub Actions workflow. |
| Agent skills / tool use | Code and video | Google Drive as screenshot inbox, Google Sheets as durable memory, AI vision adapters, correction memory, and human review loops. |

The submission does not claim MCP Server or ADK-specific implementation.

## Final Submission Requirements

| Requirement | Evidence or final action |
| --- | --- |
| Kaggle Writeup with title, subtitle, selected track, and detailed analysis | [KAGGLE_WRITEUP_DRAFT.md](KAGGLE_WRITEUP_DRAFT.md) and [FINAL_KAGGLE_FORM_CHECKLIST.md](FINAL_KAGGLE_FORM_CHECKLIST.md) |
| Writeup under 2,500 words | Enforced by `scripts/docs-check.sh` and `scripts/final-submission-check.sh` |
| Media Gallery cover image | [cover-image.svg](cover-image.svg) or PNG export |
| Attached public YouTube video, 5 minutes or less | [VIDEO_SCRIPT.md](VIDEO_SCRIPT.md), [MEDIA_GALLERY_PLAN.md](MEDIA_GALLERY_PLAN.md), [YOUTUBE_UPLOAD_METADATA.md](YOUTUBE_UPLOAD_METADATA.md), and `npm run submission:final` |
| Public project link or public repository with setup instructions | README setup path, [DEPLOYMENT.md](../DEPLOYMENT.md), and [PUBLIC_REPO_MANIFEST.md](PUBLIC_REPO_MANIFEST.md) |
| Final Writeup is submitted, not left as draft | Confirm manually in Kaggle and set `KAGGLE_WRITEUP_READY_CONFIRMED=yes` before running `npm run submission:final` |
| No accidental private Kaggle Resource exposure | Confirm no private Kaggle Resources are attached, or that intended private resources may become public after the deadline, then set `KAGGLE_PRIVATE_RESOURCES_CONFIRMED=yes` |

## Final Verification

Run:

```bash
npm run verify
npm run verify:ci
npm run submission:final
```

`npm run submission:final` is intentionally external-field-driven. It should be run only after the public project link, YouTube URL, video duration, Media Gallery attachments, selected track, and Kaggle Writeup readiness are known.

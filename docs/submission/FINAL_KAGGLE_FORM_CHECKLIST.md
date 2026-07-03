# Final Kaggle Form Checklist

Use this immediately before clicking Submit on Kaggle.

## Writeup Fields

- Title: `Agentic AI Spending Analysis Assistant`
- Subtitle: `A private Drive-first finance agent that turns screenshots into auditable Sheets, human review queues, anomaly decisions, and next-best actions.`
- Track: `Concierge Agents`
- Body: start from [KAGGLE_WRITEUP_DRAFT.md](KAGGLE_WRITEUP_DRAFT.md).
- Word count: keep under 2,500 words.

## Media Gallery

- Cover image: [cover-image.svg](cover-image.svg), or a PNG export of it.
- Architecture visual: [architecture-diagram.svg](architecture-diagram.svg).
- Video: YouTube link, 5 minutes or less. Use [YOUTUBE_UPLOAD_METADATA.md](YOUTUBE_UPLOAD_METADATA.md) for the upload title, description, chapters, tags, and Public visibility checklist.
- Optional screenshots: sanitized dashboard, staged import, review workbench, anomaly panel, source evidence, and Sheets tab list.

## Project Link

Preferred:

```text
https://github.com/spedia911/Agentic-AI-Spending-Analysis-Assistant
```

Optional hosted demo:

```text
https://YOUR_SAFE_DEMO_URL
```

Do not use a link that requires private credentials, exposes private screenshots, or shows real financial data.

Before using a repository link, check [PUBLIC_REPO_MANIFEST.md](PUBLIC_REPO_MANIFEST.md).

## Required Course Concepts To Mention

- Agent / multi-agent system.
- Antigravity.
- Security features.
- Deployability.
- Agent skills and tool use.

Use [ARCHITECTURE_AND_RUBRIC.md](ARCHITECTURE_AND_RUBRIC.md) for exact evidence.
Use [COURSE_CONCEPT_COVERAGE.md](COURSE_CONCEPT_COVERAGE.md) to stay honest about concepts claimed versus not claimed.

## Final Local Commands

Run:

```bash
npm run verify
npm run verify:ci
```

Confirm:

- Docs check passes.
- Privacy check has no errors.
- Tests pass.
- Type check passes.
- Lint passes.
- Production build passes.
- CI-safe verification passes without private credentials.

After the public project link and YouTube URL exist, run the final external check:

```bash
KAGGLE_PROJECT_LINK="https://github.com/spedia911/Agentic-AI-Spending-Analysis-Assistant" \
KAGGLE_YOUTUBE_URL="https://youtu.be/YOUR_VIDEO_ID" \
KAGGLE_VIDEO_DURATION_SECONDS="290" \
KAGGLE_MEDIA_GALLERY_CONFIRMED="yes" \
KAGGLE_TRACK_CONFIRMED="Concierge Agents" \
KAGGLE_WRITEUP_READY_CONFIRMED="yes" \
KAGGLE_PRIVATE_RESOURCES_CONFIRMED="yes" \
npm run submission:final
```

This check is intentionally separate from `npm run verify` because it should fail until the real project URL, video URL, duration, Media Gallery attachment, track selection, Writeup readiness, and private-resource review are known.

Kaggle notes that un-submitted draft Writeups are not considered by judges. Kaggle also notes that if a private Kaggle Resource is attached to a public Writeup, that Resource may automatically become public after the deadline.

## Privacy Checks

- `.env` is not committed.
- Service-account JSON is not committed.
- `data/private/` is not committed.
- No private screenshots appear in the Media Gallery or video.
- No API keys or account numbers appear in the video.
- No unintended private Kaggle Resources are attached to the public Writeup.

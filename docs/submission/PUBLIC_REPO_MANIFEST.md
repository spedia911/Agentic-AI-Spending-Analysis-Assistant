# Public Repository Manifest

Use this manifest before publishing the repository or attaching the public project link in Kaggle.

## Must Be Present

| Path | Purpose |
| --- | --- |
| `README.md` | Reviewer quick-start, local setup, demo path, API endpoints, and repo map |
| `LICENSE` | MIT license for public reuse |
| `SECURITY.md` | Security, privacy, sensitive-data handling, verification, and reporting notes |
| `.env.example` | Non-secret environment template |
| `.gitignore` | Excludes secrets, local data, generated artifacts, dependencies, and build output |
| `package.json` and `package-lock.json` | Node scripts and dependency lockfile |
| `.github/workflows/ci.yml` | Public CI-safe verification workflow |
| `scripts/` | Preflight, privacy, docs, local verify, CI-safe verify, and final external submission check scripts |
| `src/` | Application source code and tests |
| `docs/` | Product specs, readiness docs, deployment notes, and Kaggle submission assets |
| `docs/submission/YOUTUBE_UPLOAD_METADATA.md` | YouTube title, description, chapters, tags, Public visibility, and privacy checklist |
| `docs/submission/USER_STORY_UI_REVIEW.md` | User-story trace, UI gap review, and demo shot checklist |
| `docs/submission/KAGGLE_EVALUATION_SCORECARD.md` | Point-by-point Kaggle evaluation mapping |

## Must Not Be Present

| Path or pattern | Reason |
| --- | --- |
| `.env`, `.env.*` except `.env.example` | Secrets and private environment values |
| `service-account*.json`, `credentials.json`, `token.json`, `client_secret*.json`, `*.pem` | Google or OAuth credentials |
| `data/private/` | Cached financial source screenshots |
| `data/raw/` | Raw source images |
| `data/exports/` | Generated exports that may contain financial rows |
| `.next/`, `out/`, `dist/`, `build/`, `coverage/` | Generated build or test output |
| `node_modules/` | Dependencies should be installed from the lockfile |
| `artifacts/`, `screenshots/` | Local media that may show private financial data |

## Verification Commands

Run these before making the repository public:

```bash
npm run verify:ci
npm run verify
```

`npm run verify:ci` proves the public repository can pass checks without private credentials.

`npm run verify` proves the local configured environment passes the full submission gate.

## Manifest Coverage

This manifest is enforced indirectly by:

- `scripts/package-check.sh`, which verifies the required public files and directories exist and are tracked.
- `scripts/privacy-check.sh`, which rejects tracked secrets and private artifacts.
- `scripts/docs-check.sh`, which requires reviewer-facing docs and checks path portability.
- `scripts/final-submission-check.sh`, which checks real project/video URLs and Kaggle form confirmations after external assets exist.
- `.gitignore`, which excludes known private and generated paths.
- `.github/workflows/ci.yml`, which runs CI-safe verification for public pushes and pull requests.

## Final Public Link Rule

The Kaggle project link should point to either:

- a public repository that satisfies this manifest, or
- a hosted demo using sanitized Drive, Sheet, and AI credentials with no private screenshots.

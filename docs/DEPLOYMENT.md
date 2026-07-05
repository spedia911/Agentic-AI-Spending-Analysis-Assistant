# Deployment And Public Project Link Guide

Kaggle requires an attached public project link. A live hosted demo is helpful but not required. If a live demo is not feasible, use a public repository link with detailed setup instructions.

## Recommended Submission Option

Use the public repository as the project link unless you have time to prepare a safe hosted demo.

Why:

- The app depends on private Google Drive, Google Sheets, service-account credentials, and an AI API key.
- The safest judge path is a public repo with clear setup docs, a sanitized demo seed path, and a short video showing the working product.
- The repository includes `README.md`, `.env.example`, `npm run verify`, public reviewer docs, and a sanitized demo path. Keep writeup drafts, video scripts, and upload metadata local-only under `docs/submission/`, then paste or upload them directly to Kaggle and YouTube.

Public project link format:

```text
https://github.com/spedia911/Agentic-AI-Spending-Analysis-Assistant
```

## Optional Hosted Demo

You can deploy a hosted demo only if you are comfortable configuring private environment variables in the hosting provider.

Suggested platforms:

- Vercel for the Next.js app.
- Render, Railway, or another Node-compatible host.

Required hosted environment variables:

```env
GOOGLE_DRIVE_FOLDER_ID=
GOOGLE_SHEET_ID=
GOOGLE_SERVICE_ACCOUNT_KEY=
AI_PROVIDER=gemini
AI_MODEL=gemini-2.5-flash
AI_API_KEY=
SINGLE_USER_EMAIL=
LOW_CONFIDENCE_THRESHOLD=0.75
TIMEZONE=America/Los_Angeles
SOURCE_IMAGE_RETENTION_DAYS=30
```

Important:

- Do not upload `.env`.
- Do not commit a service-account JSON key.
- Prefer storing service-account JSON as a protected secret in the host.
- Use a sanitized Google Sheet and demo Drive folder, not private financial data.
- Keep the app single-user by setting `SINGLE_USER_EMAIL` to the reviewer/demo email you will use.

## Hosted Demo Smoke Test

After deployment:

1. Open the deployed dashboard with the configured email query parameter.
2. Run **Test setup** from the dashboard action center.
3. Click **Seed demo data**.
4. Refresh the page and confirm spending, cash-flow, anomaly, and source audit sections render.
5. Open `/review?email=YOUR_CONFIGURED_EMAIL`.
6. Open `/import?email=YOUR_CONFIGURED_EMAIL` only if the demo Drive folder contains safe screenshots.
7. Run `npm run verify` locally before submitting.

## Vercel Notes

For Vercel, use:

```bash
npm run build
```

as the build command. The project uses normal Next.js start/build behavior.

Because the dashboard loads Google and AI data at runtime, production build can pass without exposing those values in source code. Runtime requests still require environment variables to be configured in the host.

## If Using Only A Public Repository Link

Make sure the repository includes:

- `README.md` setup steps.
- `.env.example`.
- `.github/workflows/ci.yml` running `npm run verify:ci`.
- [SUBMISSION_PACKAGE_CHECKLIST.md](SUBMISSION_PACKAGE_CHECKLIST.md).
- [MVP_SUBMISSION.md](MVP_SUBMISSION.md).
- [DEMO_WALKTHROUGH.md](DEMO_WALKTHROUGH.md).
- [CAPSTONE_READINESS_AUDIT.md](CAPSTONE_READINESS_AUDIT.md).
- A successful latest `npm run verify` result in your final submission notes.
- Local-only Kaggle writeup, YouTube metadata, recording decks, contact sheets, and media assets prepared outside git under `docs/submission/`.

In the Kaggle Writeup, say:

> The public project link is the GitHub repository. A live hosted demo is not used because the app intentionally depends on private Drive, Sheets, service-account, and AI credentials. The repository includes setup instructions, a sanitized demo seed path, full verification scripts, and a video demonstration.

## Public CI Versus Local Full Verification

Use both verification paths for different purposes:

- `npm run verify` is the local submission gate. It checks real setup through `scripts/preflight.sh`, then runs privacy checks, docs checks, tests, type check, lint, and production build.
- `npm run verify:ci` is the public repository gate. It uses placeholder environment values so GitHub Actions can prove the code builds without exposing private credentials.

The GitHub Actions workflow does not access Drive, Sheets, service-account files, or AI APIs. Live integration still requires the local setup described in `README.md`.

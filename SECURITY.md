# Security And Privacy

This project handles personal financial screenshots and extracted financial records. Treat every real screenshot, account label, Sheet row, and API key as sensitive.

## Scope

This MVP is a single-user review assistant. It is designed to help a user organize and audit their own financial screenshots. It does not provide professional financial advice, initiate payments, move money, or connect directly to bank accounts.

## Sensitive Data

Do not commit or publish:

- `.env` or any `.env.*` file except `.env.example`.
- Google service-account JSON keys.
- OAuth client secret files.
- API tokens or model provider keys.
- Raw financial screenshots.
- Cached screenshots under `data/private/`.
- Generated exports under `data/exports/`.
- Videos or screenshots that show private financial data.

The repository `.gitignore` excludes these paths, and `scripts/privacy-check.sh` checks tracked files for common secret and private artifact mistakes.

## Runtime Data Handling

- Google Drive is the primary screenshot inbox.
- Google Sheets is the durable output store.
- Cached source screenshots are stored only under `data/private/`, which is ignored by git.
- Screenshot cache retention is controlled by `SOURCE_IMAGE_RETENTION_DAYS`.
- Account labels should be masked or partial, not full account numbers.
- API-visible errors use `safeErrorDetail` and `maskSensitiveText` from `src/lib/privacy/redact.ts`.

## Access Model

- The dashboard is single-user and gated by `SINGLE_USER_EMAIL`.
- Google Drive folder and Google Sheet access should be limited to the service account and the intended user.
- The service account should receive the minimum practical access: read access to the Drive folder and edit access to the output Sheet.
- Hosted demos should use sanitized Drive folders and Sheets, not private financial data.

## Verification

Local submission verification:

```bash
npm run verify
```

This checks real local setup, privacy, docs, tests, type checking, lint, and production build.

Public CI-safe verification:

```bash
npm run verify:ci
```

This uses placeholder environment values and does not access private Drive, Sheets, service-account files, or AI APIs.

## Known Limitations

- This is not a production banking system.
- The app does not implement multi-user authorization or organization-level access controls.
- The app relies on the user to configure Google Drive, Google Sheets, and service-account sharing correctly.
- Screenshot-region highlighting depends on model-provided coordinate hints.
- MCP Server and ADK-specific implementation are not claimed in the submitted MVP.

## Reporting Issues

If this repository is made public, report security or privacy issues privately to the repository owner instead of opening an issue that includes secrets or screenshots.

When reporting, include:

- A short description of the issue.
- Steps to reproduce with sanitized data.
- The affected file or route, if known.
- Whether any secret, source screenshot, or private financial row may have been exposed.

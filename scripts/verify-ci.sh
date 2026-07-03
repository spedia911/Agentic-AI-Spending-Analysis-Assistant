#!/bin/sh

set -eu

printf 'Running public CI verification gates...\n\n'

export GOOGLE_DRIVE_FOLDER_ID="${GOOGLE_DRIVE_FOLDER_ID:-ci-drive-folder}"
export GOOGLE_SHEET_ID="${GOOGLE_SHEET_ID:-ci-sheet-id}"
export GOOGLE_SERVICE_ACCOUNT_KEY="${GOOGLE_SERVICE_ACCOUNT_KEY:-ci-service-account.json}"
export AI_PROVIDER="${AI_PROVIDER:-gemini}"
export AI_MODEL="${AI_MODEL:-gemini-2.5-flash}"
export AI_API_KEY="${AI_API_KEY:-ci-ai-key}"
export SINGLE_USER_EMAIL="${SINGLE_USER_EMAIL:-reviewer@example.com}"
export LOW_CONFIDENCE_THRESHOLD="${LOW_CONFIDENCE_THRESHOLD:-0.75}"
export TIMEZONE="${TIMEZONE:-America/Los_Angeles}"
export SOURCE_IMAGE_RETENTION_DAYS="${SOURCE_IMAGE_RETENTION_DAYS:-30}"

run_step() {
  label="$1"
  shift
  printf '==> %s\n' "$label"
  "$@"
  printf '\n'
}

run_step "Submission privacy check" sh scripts/privacy-check.sh
run_step "Public package manifest check" sh scripts/package-check.sh
run_step "Submission docs check" sh scripts/docs-check.sh
run_step "Unit and integration tests" npm test
run_step "TypeScript type check" npx tsc --noEmit
run_step "Lint" npm run lint
run_step "Production build with placeholder env" npm run build

printf 'All public CI verification gates passed.\n'

#!/bin/sh

set -eu

error_count=0

fail() {
  error_count=$((error_count + 1))
  printf 'ERROR: %s\n' "$1"
}

require_file() {
  path="$1"
  if [ -f "$path" ]; then
    printf 'OK: %s exists.\n' "$path"
  else
    fail "$path is missing."
  fi
}

require_text() {
  path="$1"
  text="$2"
  if [ ! -f "$path" ]; then
    fail "$path is missing, so required text could not be checked: $text"
    return
  fi
  if grep -F "$text" "$path" >/dev/null 2>&1; then
    printf 'OK: %s mentions "%s".\n' "$path" "$text"
  else
    fail "$path should mention: $text"
  fi
}

printf 'Reviewer docs check\n'
printf 'Checking public reviewer-facing docs for required package, demo, and evaluation signals...\n\n'

require_file README.md
require_file LICENSE
require_file SECURITY.md
require_file .gitignore
require_file docs/MVP_SUBMISSION.md
require_file docs/DEMO_WALKTHROUGH.md
require_file docs/CAPSTONE_READINESS_AUDIT.md
require_file docs/SUBMISSION_PACKAGE_CHECKLIST.md
require_file docs/DEPLOYMENT.md
require_file docs/references/google-photos-picker-evaluation.md
require_file scripts/package-check.sh
require_file scripts/final-submission-check.sh

require_text .gitignore 'docs/submission/'
require_text README.md 'Seed demo data'
require_text README.md 'Run Drive workflow'
require_text README.md 'npm run verify:ci'
require_text README.md 'npm run submission:final'
require_text README.md 'npm run package:check'
require_text README.md 'For Kaggle Reviewers'
require_text README.md 'Recommended track: **Concierge Agents**'
require_text README.md 'docs/submission/'
require_text LICENSE 'MIT License'
require_text SECURITY.md 'Security And Privacy'
require_text SECURITY.md 'npm run verify:ci'
require_text SECURITY.md 'does not provide professional financial advice'
require_text docs/MVP_SUBMISSION.md 'next-best-actions'
require_text docs/MVP_SUBMISSION.md 'npm run verify'
require_text docs/MVP_SUBMISSION.md 'docs/submission/'
require_text docs/DEMO_WALKTHROUGH.md 'Technical Evaluation Signals'
require_text docs/DEMO_WALKTHROUGH.md 'dashboard action center'
require_text docs/CAPSTONE_READINESS_AUDIT.md 'Agentic Evaluation Signals'
require_text docs/CAPSTONE_READINESS_AUDIT.md 'Kaggle Submission Fit'
require_text docs/CAPSTONE_READINESS_AUDIT.md 'Required concept'
require_text docs/SUBMISSION_PACKAGE_CHECKLIST.md 'Do Not Include'
require_text docs/SUBMISSION_PACKAGE_CHECKLIST.md 'docs/submission/'
require_text docs/SUBMISSION_PACKAGE_CHECKLIST.md 'Writeup has a selected track'
require_text docs/SUBMISSION_PACKAGE_CHECKLIST.md 'npm run submission:final'
require_text docs/DEPLOYMENT.md 'public repository as the project link'
require_text docs/DEPLOYMENT.md 'Optional Hosted Demo'
require_text docs/DEPLOYMENT.md 'Public CI Versus Local Full Verification'
require_text docs/DEPLOYMENT.md 'docs/submission/'
require_text docs/references/google-photos-picker-evaluation.md 'Google Photos'

if [ -f docs/submission/KAGGLE_WRITEUP_DRAFT.md ]; then
  writeup_words=$(wc -w < docs/submission/KAGGLE_WRITEUP_DRAFT.md | tr -d ' ')
  if [ "$writeup_words" -le 2500 ]; then
    printf 'OK: local-only docs/submission/KAGGLE_WRITEUP_DRAFT.md is under 2,500 words (%s words).\n' "$writeup_words"
  else
    fail "local-only docs/submission/KAGGLE_WRITEUP_DRAFT.md is over 2,500 words ($writeup_words words)."
  fi
else
  printf 'OK: local-only Kaggle writeup draft is not present; word-count check skipped.\n'
fi

portable_matches=$(grep -R -n -E '/Users/|codex-runtimes' README.md SECURITY.md docs package.json .github scripts 2>/dev/null | grep -v '^docs/submission/' | grep -v '^scripts/docs-check.sh:' || true)
if [ -n "$portable_matches" ]; then
  fail "Reviewer-facing files contain local machine paths:"
  printf '%s\n' "$portable_matches" | sed 's/^/  - /'
else
  printf 'OK: Reviewer-facing docs and scripts avoid local machine paths.\n'
fi

printf '\nDocs check complete: %s errors.\n' "$error_count"

if [ "$error_count" -gt 0 ]; then
  printf 'Fix the reviewer-facing docs above before submitting.\n'
  exit 1
fi

#!/bin/sh

set -eu

error_count=0
warn_count=0

fail() {
  error_count=$((error_count + 1))
  printf 'ERROR: %s\n' "$1"
}

ok() {
  printf 'OK: %s\n' "$1"
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN: %s\n' "$1"
}

require_file() {
  path="$1"
  if [ -f "$path" ]; then
    ok "$path exists."
  else
    fail "$path is missing."
  fi
}

require_dir() {
  path="$1"
  if [ -d "$path" ]; then
    ok "$path exists."
  else
    fail "$path is missing."
  fi
}

printf 'Public package manifest check\n'
printf 'Checking required public repository files and directories...\n\n'

require_file README.md
require_file LICENSE
require_file SECURITY.md
require_file .env.example
require_file .gitignore
require_file package.json
require_file package-lock.json
require_file tsconfig.json
require_file eslint.config.mjs
require_file next.config.ts
require_file .github/workflows/ci.yml
require_file docs/MVP_SUBMISSION.md
require_file docs/DEMO_WALKTHROUGH.md
require_file docs/CAPSTONE_READINESS_AUDIT.md
require_file docs/SUBMISSION_PACKAGE_CHECKLIST.md
require_file docs/DEPLOYMENT.md
require_file scripts/final-submission-check.sh
require_dir scripts
require_dir src
require_dir docs

if grep -Fx 'docs/submission/' .gitignore >/dev/null 2>&1; then
  ok "docs/submission/ is ignored as a local-only submission workspace."
else
  fail "docs/submission/ should be ignored in .gitignore."
fi

if command -v git >/dev/null 2>&1; then
  untracked_required=''
  for path in README.md LICENSE SECURITY.md .env.example .gitignore package.json package-lock.json tsconfig.json eslint.config.mjs next.config.ts .github/workflows/ci.yml docs/MVP_SUBMISSION.md docs/DEMO_WALKTHROUGH.md docs/CAPSTONE_READINESS_AUDIT.md docs/SUBMISSION_PACKAGE_CHECKLIST.md docs/DEPLOYMENT.md scripts/final-submission-check.sh; do
    if [ -e "$path" ] && ! git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
      untracked_required="${untracked_required}${path}
"
    fi
  done
  if [ -n "$untracked_required" ]; then
    warn "Required public files exist but are not tracked by git yet:"
    printf '%s' "$untracked_required" | sed '/^$/d; s/^/  - /'
  else
    ok "Required public files are tracked by git."
  fi
else
  printf 'WARN: git is not available; tracked-file checks were skipped.\n'
fi

printf '\nPackage manifest check complete: %s warnings, %s errors.\n' "$warn_count" "$error_count"

if [ "$error_count" -gt 0 ]; then
  printf 'Fix the package manifest issues above before publishing the repository.\n'
  exit 1
fi

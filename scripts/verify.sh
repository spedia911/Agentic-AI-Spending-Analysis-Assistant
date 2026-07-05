#!/bin/sh

set -eu

printf 'Running capstone verification gates...\n\n'

run_step() {
  label="$1"
  shift
  printf '==> %s\n' "$label"
  "$@"
  printf '\n'
}

run_step "Preflight setup check" sh scripts/preflight.sh
run_step "Submission privacy check" sh scripts/privacy-check.sh
run_step "Public package manifest check" sh scripts/package-check.sh
run_step "Reviewer docs check" sh scripts/docs-check.sh
run_step "Unit and integration tests" npm test
run_step "TypeScript type check" npx tsc --noEmit
run_step "Lint" npm run lint
run_step "Production build" npm run build

printf 'All capstone verification gates passed.\n'

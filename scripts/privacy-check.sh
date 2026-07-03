#!/bin/sh

set -eu

warn_count=0
error_count=0

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN: %s\n' "$1"
}

fail_with_matches() {
  error_count=$((error_count + 1))
  printf 'ERROR: %s\n' "$1"
  printf '%s\n' "$2" | sed 's/^/  - /'
}

printf 'Submission privacy check\n'
printf 'Checking tracked files for secrets, private screenshots, and generated artifacts...\n\n'

if ! command -v git >/dev/null 2>&1; then
  warn "git is not available; tracked-file privacy checks were skipped."
else
  env_matches=$(git ls-files ".env" ".env.*" 2>/dev/null | grep -v '^\.env\.example$' || true)
  if [ -n "$env_matches" ]; then
    fail_with_matches "Environment files must not be tracked. Keep only .env.example." "$env_matches"
  fi

  sensitive_matches=$(git ls-files 2>/dev/null | grep -E '(^|/)(credentials\.json|token\.json|client_secret[^/]*\.json|service-account[^/]*\.json|[^/]*\.pem)$' || true)
  if [ -n "$sensitive_matches" ]; then
    fail_with_matches "Credential or key files must not be tracked." "$sensitive_matches"
  fi

  private_data_matches=$(git ls-files 2>/dev/null | grep -E '^(data/(private|raw|exports)/|artifacts/|screenshots/)' || true)
  if [ -n "$private_data_matches" ]; then
    fail_with_matches "Private source data, exports, screenshots, and artifacts must not be tracked." "$private_data_matches"
  fi

  build_matches=$(git ls-files 2>/dev/null | grep -E '^(\.next/|out/|dist/|build/|node_modules/|coverage/)' || true)
  if [ -n "$build_matches" ]; then
    fail_with_matches "Generated build or dependency output must not be tracked." "$build_matches"
  fi
fi

for local_path in .env data/private data/raw data/exports artifacts screenshots; do
  if [ -e "$local_path" ]; then
    warn "Local ignored path exists ($local_path). Confirm it is not included in the uploaded package."
  fi
done

printf '\nPrivacy check complete: %s warnings, %s errors.\n' "$warn_count" "$error_count"

if [ "$error_count" -gt 0 ]; then
  printf 'Remove the tracked private files above before submitting.\n'
  exit 1
fi

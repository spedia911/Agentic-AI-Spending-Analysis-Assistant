#!/bin/sh

set -u

ok_count=0
warn_count=0
error_count=0

ok() {
  ok_count=$((ok_count + 1))
  printf 'OK: %s\n' "$1"
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN: %s\n' "$1"
}

fail() {
  error_count=$((error_count + 1))
  printf 'ERROR: %s\n' "$1"
}

env_value() {
  key="$1"
  if [ ! -f .env ]; then
    return 1
  fi
  value=$(grep -E "^${key}=" .env 2>/dev/null | tail -n 1 | sed "s/^${key}=//" | sed 's/^"//' | sed 's/"$//')
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi
  return 1
}

printf 'Agentic Spending Analysis Assistant preflight\n'
printf 'Checking local tools and setup files...\n\n'

if command -v node >/dev/null 2>&1; then
  node_version=$(node -v 2>/dev/null)
  node_major=$(printf '%s' "$node_version" | sed 's/^v//' | cut -d. -f1)
  if [ "${node_major:-0}" -ge 26 ] 2>/dev/null; then
    warn "Node is installed ($node_version). Node 20-24 is recommended; npm run dev will use a compatible local runtime when one is available."
  elif [ "${node_major:-0}" -ge 20 ] 2>/dev/null; then
    ok "Node is installed ($node_version)."
  else
    warn "Node is installed ($node_version), but Node 20-24 is recommended for this project."
  fi
else
  fail "Node is not installed or is not on PATH. Install Node 20-24 from https://nodejs.org/ or with Homebrew: brew install node"
fi

if command -v npm >/dev/null 2>&1; then
  ok "npm is installed ($(npm -v 2>/dev/null))."
else
  fail "npm is not installed or is not on PATH. Installing Node from https://nodejs.org/ usually installs npm too."
fi

if [ -f package.json ]; then
  ok "package.json found."
else
  fail "package.json was not found. Run this script from the project folder."
fi

if [ -d node_modules ]; then
  ok "Dependencies are installed."
else
  warn "node_modules is missing. Run npm install before npm run dev."
fi

if [ -f .env ]; then
  ok ".env found."
else
  warn ".env is missing. Copy .env.example to .env and fill in your Drive, Sheet, AI, and email settings."
fi

for key in GOOGLE_DRIVE_FOLDER_ID GOOGLE_SHEET_ID AI_PROVIDER AI_MODEL AI_API_KEY SINGLE_USER_EMAIL; do
  if env_value "$key" >/dev/null; then
    ok "$key is set."
  else
    warn "$key is not set in .env."
  fi
done

service_account_key=$(env_value GOOGLE_SERVICE_ACCOUNT_KEY || true)
if [ -n "$service_account_key" ]; then
  if [ -f "$service_account_key" ]; then
    ok "Google service account key file exists."
  else
    warn "GOOGLE_SERVICE_ACCOUNT_KEY is set, but the file was not found. Share the Drive folder and Sheet with the service account after adding the key file."
  fi
else
  warn "GOOGLE_SERVICE_ACCOUNT_KEY is not set. Service-account setup is the recommended MVP path."
fi

printf '\nPreflight complete: %s ok, %s warnings, %s errors.\n' "$ok_count" "$warn_count" "$error_count"

if [ "$error_count" -gt 0 ]; then
  printf 'Fix the errors above before starting the app.\n'
  exit 1
fi

printf 'Next step: npm install, then npm run dev.\n'

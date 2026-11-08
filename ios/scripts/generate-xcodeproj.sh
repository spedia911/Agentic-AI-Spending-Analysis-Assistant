#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
  echo "Generated SpendingAssistant.xcodeproj"
  exit 0
fi

echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
exit 1

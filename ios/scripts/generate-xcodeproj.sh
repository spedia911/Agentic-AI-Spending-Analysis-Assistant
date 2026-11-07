#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
  echo "Generated SpendingAssistant.xcodeproj"
  exit 0
fi

echo "XcodeGen is not installed."
echo "Install with: brew install xcodegen"
echo "Then re-run: ios/scripts/generate-xcodeproj.sh"
echo
echo "You can also open Packages/SpendingDomain in Xcode and create an iOS app target that depends on it."
exit 0

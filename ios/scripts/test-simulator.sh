#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="${SPENDING_TEST_DEVICE_ID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for values in d["devices"].values() for v in values if v["name"].startswith("iPhone")))')}"
xcodebuild -project "$ROOT/SpendingAssistant.xcodeproj" -scheme SpendingAssistant \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "${SPENDING_TEST_DERIVED_DATA:-/tmp/SpendingAssistantTests}" \
  CODE_SIGNING_ALLOWED=NO test "$@"

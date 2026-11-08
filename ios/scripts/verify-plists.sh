#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" "${1:-}" <<'PY'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
built = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
app = built / 'SpendingAssistant.app/Info.plist' if built else root / 'SpendingAssistant/Resources/Info.plist'
ext = built / 'ShareExtension.appex/Info.plist' if built else root / 'ShareExtension/Info.plist'
with app.open('rb') as f: a = plistlib.load(f)
with ext.open('rb') as f: e = plistlib.load(f)
assert a['CFBundleDisplayName'] == 'Spending Assistant'
assert a['CFBundleShortVersionString'] == '2.0'
assert 'UILaunchScreen' in a
assert e['CFBundleDisplayName'] == 'Spending Import'
assert e['CFBundleShortVersionString'] == a['CFBundleShortVersionString']
assert e['CFBundleVersion'] == a['CFBundleVersion']
n = e['NSExtension']
assert n['NSExtensionPointIdentifier'] == 'com.apple.share-services'
assert n['NSExtensionPrincipalClass'].endswith('.ShareViewController')
r = n['NSExtensionAttributes']['NSExtensionActivationRule']
assert r['NSExtensionActivationSupportsImageWithMaxCount'] == 8
assert r['NSExtensionActivationSupportsText'] is True
print('App and Share Extension plist verification passed')
PY

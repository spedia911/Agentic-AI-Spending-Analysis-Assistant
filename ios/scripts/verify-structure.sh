#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

require() {
  if [[ ! -e "$1" ]]; then
    echo "MISSING: $1"
    fail=1
  else
    echo "OK: $1"
  fi
}

require "$ROOT/Packages/SpendingDomain/Package.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Models/DomainModels.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Normalization/Normalizer.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Validation/Validator.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Categorization/Categorizer.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Extraction/HeuristicParser.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Extraction/Schema.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Summaries/Generator.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Anomalies/Detector.swift"
require "$ROOT/Packages/SpendingDomain/Sources/SpendingDomain/Pipeline/Orchestrator.swift"
require "$ROOT/Packages/SpendingDomain/Tests/SpendingDomainTests/DomainTests.swift"
require "$ROOT/SpendingAssistant/App/SpendingAssistantApp.swift"
require "$ROOT/SpendingAssistant/Models/SwiftDataModels.swift"
require "$ROOT/SpendingAssistant/Services/ImportPipelineService.swift"
require "$ROOT/SpendingAssistant/Views/Home/HomeView.swift"
require "$ROOT/SpendingAssistant/Views/Import/ImportView.swift"
require "$ROOT/SpendingAssistant/Views/Review/ReviewView.swift"
require "$ROOT/SpendingAssistant/Resources/sample-extraction.json"
require "$ROOT/ShareExtension/ShareViewController.swift"
require "$ROOT/project.yml"
require "$ROOT/README.md"

python3 - <<'PY'
import json, pathlib, sys
p = pathlib.Path("/workspace/ios/SpendingAssistant/Resources/sample-extraction.json")
data = json.loads(p.read_text())
assert data["transactions"], "sample must include transactions"
assert "source_document_id" in data
print("OK: sample-extraction.json parses")
PY

if [[ "$fail" -ne 0 ]]; then
  echo "iOS structure verification failed"
  exit 1
fi
echo "iOS structure verification passed"

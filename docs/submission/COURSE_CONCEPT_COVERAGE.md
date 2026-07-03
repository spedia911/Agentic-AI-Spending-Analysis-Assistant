# Course Concept Coverage

Kaggle asks submissions to demonstrate at least three course concepts. This project demonstrates five concepts clearly and intentionally does not claim MCP Server or ADK-specific implementation.

## Concepts Claimed

| Course concept | Demonstrated in | Evidence |
| --- | --- | --- |
| Agent / multi-agent system | Code, writeup, video | The workflow is separated into ingestion, extraction, normalization, validation, categorization, correction, summary, anomaly, and dashboard guidance modules. See `src/lib/orchestrator/`, `src/lib/extraction/`, `src/lib/normalization/`, `src/lib/categorization/`, `src/lib/validation/`, `src/lib/corrections/`, `src/lib/summaries/`, `src/lib/anomalies/`, and `src/lib/dashboard/insights.ts`. |
| Antigravity | Video and development docs | [antigravity-build-prompts.md](../prompts/antigravity-build-prompts.md) records the agentic build prompts used to shape the MVP. Mention this in the video as the build process evidence. |
| Security features | Code, docs, video | `SECURITY.md`, single-user email gate, private screenshot cache, redacted API/log errors, tracked-file privacy checks, ignored secret files, service-account setup guidance, and review-only safety messaging. |
| Deployability | Docs, CI, video | README setup path, `.env.example`, `scripts/preflight.sh`, in-app setup health, `npm run verify`, CI-safe `npm run verify:ci`, and `.github/workflows/ci.yml`. |
| Agent skills / tool use | Code and video | Google Drive ingestion, Google Sheets durable memory, AI vision adapters, strict extraction schema, deterministic validation, correction memory, and human review loops. |

## Concepts Not Claimed

| Course concept | Reason |
| --- | --- |
| MCP Server | This MVP integrates Drive, Sheets, AI extraction, and dashboard APIs directly. Adding an MCP server would be a future integration layer, not part of the submitted implementation. |
| ADK-specific implementation | The architecture is multi-agent in design, but it is implemented as typed TypeScript workflow modules rather than a Google ADK app. |

## Video Callout

Use this sentence in the final minute:

> The submission demonstrates five course concepts: a multi-agent workflow, Antigravity-assisted build documentation, security features, deployability, and agent tool use through Drive, Sheets, AI extraction, and human review. I am not claiming MCP Server or ADK-specific implementation in this MVP.

## Writeup Callout

Use this sentence in the Writeup if space allows:

> I am explicitly claiming multi-agent workflow, Antigravity process evidence, security features, deployability, and agent tool use; MCP Server and ADK-specific implementation are documented as future extensions rather than current claims.

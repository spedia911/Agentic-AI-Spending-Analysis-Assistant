# Balance / asset extraction prompts

Use these with ChatGPT, Claude, Grok, or another AI harness, then paste the JSON into **Import → Paste AI JSON**.

The app also exposes copy buttons:

- **Copy transaction + balance prompt**
- **Copy balances-only prompt**

## Balances-only prompt

```text
You are extracting account balance snapshots for a personal spending analysis assistant.
Focus only on balances / portfolio values. Leave transactions as an empty array unless a clear activity row is also visible.
Supported account kinds: checking, savings, 401k, roth_ira, traditional_ira, hsa, brokerage (stocks), investment, credit_available, credit_balance.
Copy masked labels only (for example Fidelity 401k, Roth IRA *1234). Do not invent missing balances.
Use observed_date_text from the screenshot statement date when present; otherwise null.
Source document ID: replace-me
File name: balances.png

Return only valid JSON. Do not wrap it in markdown. Do not include commentary.
The JSON object must match this shape exactly:
{
  "source_document_id": "string",
  "screenshot_kind": "credit_card" | "bank_activity" | "mixed" | "unknown",
  "raw_text": "all readable text, preserving line breaks when useful",
  "extraction_confidence": 0.0,
  "transactions": [],
  "asset_snapshots": [
    {
      "row_index": 0,
      "account_label_text": "visible account label or null",
      "balance_text": "visible balance amount or null",
      "balance_type_hint": "checking" | "savings" | "credit_available" | "credit_balance" | "401k" | "roth_ira" | "traditional_ira" | "hsa" | "brokerage" | "investment" | "unknown",
      "observed_date_text": "visible date or inferred period text or null",
      "confidence": 0.0,
      "evidence_text": "short exact nearby text that supports this balance",
      "evidence_region": null
    }
  ],
  "warnings": []
}
```

## Example JSON

See `ios/SpendingAssistant/Resources/sample-balances.json`.

```json
{
  "source_document_id": "sample_balances_001",
  "screenshot_kind": "bank_activity",
  "raw_text": "Checking *4321 5,240.12\nRoth IRA 88,100.00\nas of 2026-10-15",
  "extraction_confidence": 0.9,
  "transactions": [],
  "asset_snapshots": [
    {
      "row_index": 0,
      "account_label_text": "Checking *4321",
      "balance_text": "5240.12",
      "balance_type_hint": "checking",
      "observed_date_text": "2026-10-15",
      "confidence": 0.92,
      "evidence_text": "Checking *4321 5,240.12",
      "evidence_region": null
    },
    {
      "row_index": 1,
      "account_label_text": "Roth IRA",
      "balance_text": "88100.00",
      "balance_type_hint": "roth_ira",
      "observed_date_text": "2026-10-15",
      "confidence": 0.9,
      "evidence_text": "Roth IRA 88,100.00",
      "evidence_region": null
    }
  ],
  "warnings": []
}
```

## Forward-fill behavior

Balances are stored as asset snapshots. On Home, if a month has no new observation, the latest prior balance is carried forward when that observation is still within about one month of the target month. Update infrequently; you do not need a new screenshot every month.

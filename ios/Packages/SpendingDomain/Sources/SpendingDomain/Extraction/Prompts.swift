import Foundation

public enum ExtractionPrompts {
    public static let strictJSONContract = """
Return only valid JSON. Do not wrap it in markdown. Do not include commentary.
The JSON object must match this shape exactly:
{
  "source_document_id": "string",
  "screenshot_kind": "credit_card" | "bank_activity" | "mixed" | "unknown",
  "raw_text": "all readable text, preserving line breaks when useful",
  "extraction_confidence": 0.0,
  "transactions": [
    {
      "row_index": 0,
      "date_text": "visible date or null",
      "merchant_text": "merchant or description or null",
      "amount_text": "visible signed or unsigned amount or null",
      "account_source_text": "visible account label/source or null",
      "transaction_type_hint": "expense" | "income" | "transfer" | "payment" | "fee" | "refund" | "unknown",
      "confidence": 0.0,
      "evidence_text": "short exact nearby text that supports this row",
      "evidence_region": {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0} | null
    }
  ],
  "asset_snapshots": [
    {
      "row_index": 0,
      "account_label_text": "visible account label or null",
      "balance_text": "visible balance amount or null",
      "balance_type_hint": "checking" | "savings" | "credit_available" | "credit_balance" | "unknown",
      "observed_date_text": "visible date or inferred period text or null",
      "confidence": 0.0,
      "evidence_text": "short exact nearby text that supports this balance",
      "evidence_region": {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0} | null
    }
  ],
  "warnings": ["non-sensitive issue summary"]
}
"""

    public static func mixedPrompt(sourceDocumentId: String, fileName: String) -> String {
        [
            "You are extracting financial screenshot data for a personal spending analysis assistant.",
            "The screenshot may contain credit card transactions, bank activity, balances, or a mix of these.",
            "Extract all visible transaction rows and all visible asset/balance snapshots.",
            "If the screenshot type is clear, set screenshot_kind accordingly; otherwise use mixed or unknown.",
            "When possible, include evidence_region as normalized screenshot coordinates from 0 to 1 around each row or balance area. Use null if coordinates are not reliable.",
            "Source document ID: \(sourceDocumentId)",
            "File name: \(fileName)",
            strictJSONContract
        ].joined(separator: "\n\n")
    }

    public static func creditCardPrompt(sourceDocumentId: String, fileName: String) -> String {
        [
            "You are extracting credit card screenshot data for a personal spending analysis assistant.",
            "Focus on visible transaction rows: date, merchant/description, amount, account/source label, and row evidence.",
            "If a required field is unclear, keep the row and set the unclear field to null with lower confidence.",
            "Do not infer merchants or dates that are not visible. Preserve ambiguous evidence for human review.",
            "Source document ID: \(sourceDocumentId)",
            "File name: \(fileName)",
            strictJSONContract
        ].joined(separator: "\n\n")
    }

    public static func bankActivityPrompt(sourceDocumentId: String, fileName: String) -> String {
        [
            "You are extracting bank activity and visible balance data for a personal spending analysis assistant.",
            "Focus on activity rows plus any visible checking, savings, credit balance, or available credit snapshots.",
            "Do not expose full account numbers; copy only masked labels when visible.",
            "Source document ID: \(sourceDocumentId)",
            "File name: \(fileName)",
            strictJSONContract
        ].joined(separator: "\n\n")
    }

    public static func categoryClassificationPrompt(merchant: String, amount: Double, transactionType: TransactionType, evidenceText: String) -> String {
        [
            "Classify this personal finance transaction into exactly one allowed category.",
            "Allowed categories: groceries, dining, utilities, transportation, rent, subscriptions, shopping, healthcare, transfer, income, fees, miscellaneous.",
            "Return only JSON with keys category, confidence, reason.",
            "Merchant: \(merchant)",
            "Amount: \(amount)",
            "Transaction type: \(transactionType.rawValue)",
            "Evidence: \(String(evidenceText.prefix(500)))"
        ].joined(separator: "\n")
    }

    public static func structureFromOCRPrompt(sourceDocumentId: String, fileName: String, ocrText: String) -> String {
        [
            mixedPrompt(sourceDocumentId: sourceDocumentId, fileName: fileName),
            "OCR text from the screenshot follows. Structure it into the JSON contract above.",
            ocrText
        ].joined(separator: "\n\n")
    }
}

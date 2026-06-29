export interface SourceDocument {
  source_document_id: string; // Google Drive file ID
  source_type: 'drive' | 'photos' | 'upload';
  file_name: string;
  mime_type: string;
  created_time: string; // ISO DateTime string
  modified_time: string; // ISO DateTime string
  processed_at: string | null; // ISO DateTime string
  status: 'pending' | 'processed' | 'skipped' | 'error';
  error_summary: string | null; // Masked, non-sensitive error
}

export interface Transaction {
  transaction_id: string; // Stable deterministic ID (hash of source ID, date, merchant, amount, row index)
  source_document_id: string; // Foreign key referencing SourceDocument
  observed_month: string; // YYYY-MM
  transaction_date: string; // YYYY-MM-DD
  merchant_raw: string; // Original extracted merchant text
  merchant_normalized: string; // Clean merchant name
  amount: number; // Signed decimal amount (e.g. expenses are negative or positive depending on type, usually expenses negative and income positive)
  transaction_type: 'expense' | 'income' | 'transfer' | 'payment' | 'fee' | 'refund' | 'unknown';
  account_label: string; // Masked account identifier (e.g. "Chase *1234")
  category: string; // Groceries, Rent, Dining, etc.
  category_confidence: number; // 0.0 to 1.0
  extraction_confidence: number; // 0.0 to 1.0
  validation_status: 'valid' | 'needs_review' | 'rejected';
  review_status: 'none' | 'pending' | 'resolved';
  evidence_text: string; // OCR text snippet for verification
  created_at: string; // ISO DateTime string
  updated_at: string; // ISO DateTime string
}

export interface AssetSnapshot {
  asset_snapshot_id: string; // Stable deterministic ID
  source_document_id: string; // Foreign key referencing SourceDocument
  observed_month: string; // YYYY-MM
  observed_date: string; // YYYY-MM-DD
  account_label: string; // Masked account label
  balance: number; // Account balance amount
  balance_type: 'checking' | 'savings' | 'credit_available' | 'credit_balance' | 'unknown';
  confidence: number; // 0.0 to 1.0
  evidence_text: string; // Snippet of text containing the balance
  created_at: string; // ISO DateTime string
}

export interface ReviewItem {
  review_item_id: string; // Stable deterministic ID (hash of target ID and issue type)
  target_type: 'transaction' | 'asset_snapshot' | 'source_document';
  target_id: string; // Reference to target entity ID
  issue_type: 'low_confidence' | 'missing_field' | 'duplicate_risk' | 'anomaly' | 'unclear_category';
  severity: 'low' | 'medium' | 'high';
  question: string; // E.g., "Is this $14.50 charge at AMZN to category groceries?"
  suggested_options: string[]; // Options user can pick from
  status: 'pending' | 'resolved' | 'ignored';
  user_answer: string | null; // Selected option or custom user text
  created_at: string; // ISO DateTime string
  resolved_at: string | null; // ISO DateTime string
}

export interface Correction {
  correction_id: string; // Stable ID
  target_type: 'transaction' | 'merchant_rule';
  target_id: string; // Linked ID
  field_name: 'category' | 'merchant_normalized' | 'amount' | 'date';
  old_value: string;
  new_value: string;
  apply_future: boolean; // True if should map similar merchants automatically in the future
  created_at: string; // ISO DateTime string
}

export interface MonthlySummary {
  month: string; // YYYY-MM
  category: string;
  total_amount: number;
  transaction_count: number;
  reviewed_count: number;
  unresolved_count: number;
  month_over_month_delta: number | null; // Total amount change from prior month
  completeness_status: 'complete' | 'partial' | 'unknown';
}

export interface QuarterlySummary {
  quarter: string; // YYYY-QN (e.g., 2026-Q2)
  category: string;
  total_amount: number;
  transaction_count: number;
  quarter_over_quarter_delta: number | null;
  completeness_status: 'complete' | 'partial' | 'unknown';
}

export interface AssetTrend {
  month: string; // YYYY-MM
  account_label: string;
  ending_balance: number;
  prior_month_balance: number | null;
  monthly_change: number; // ending - prior
  related_spending_total: number; // Sum of expenses for the month
  maintainability_flag: 'ok' | 'watch' | 'concern' | 'unknown';
}

export interface Anomaly {
  anomaly_id: string; // Stable ID
  anomaly_type: 'duplicate_charge' | 'spending_spike' | 'balance_drop' | 'recurring_change' | 'missing_data';
  severity: 'low' | 'medium' | 'high';
  month: string; // YYYY-MM
  related_record_ids: string[]; // List of related transaction/snapshot IDs
  summary: string; // User-facing summary
  suggested_action: string;
  status: 'open' | 'resolved' | 'ignored';
  created_at: string; // ISO DateTime string
}

export interface RunState {
  run_id: string; // Unique execution run ID
  started_at: string; // ISO DateTime string
  finished_at: string | null; // ISO DateTime string
  status: 'success' | 'partial_success' | 'failed';
  files_seen: number;
  files_processed: number;
  transactions_created: number;
  review_items_created: number;
  anomalies_created: number;
  error_summary: string | null;
}

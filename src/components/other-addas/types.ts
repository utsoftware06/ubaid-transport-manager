/** Handwritten contracts for the deployed, non-cash Phase 3A foundation. */
export type OtherAddaBusinessType = "regular" | "one_time";
export type OtherAddaStatus = "active" | "archived";
export type OtherAddaSide = "receivable" | "payable";
export type OtherAddaEventType = "obligation" | "reversal";
export type OtherAddaPaymentEventType = "payment" | "reversal";
export type OtherAddaOrigin = "manual" | "bilty";

/** Preserve transport numerics; never coerce missing/invalid values to zero. */
export type DatabaseNumeric = number | string;
export type DatabaseCount = number | string;

export type OtherAdda = {
  id: string;
  adda_id: string;
  adda_name: string;
  contact_person: string | null;
  mobile: string | null;
  whatsapp: string | null;
  city: string | null;
  address: string | null;
  ntn_cnic: string | null;
  business_type: OtherAddaBusinessType;
  status: OtherAddaStatus;
  notes: string | null;
  created_at: string;
  created_by: string;
  updated_at: string;
  updated_by: string;
  archived_at: string | null;
  archived_by: string | null;
};

export type OtherAddaTransaction = {
  id: string;
  adda_id: string;
  other_adda_id: string;
  transaction_date: string;
  due_date: string | null;
  side: OtherAddaSide;
  amount: DatabaseNumeric;
  description: string;
  reference_no: string | null;
  event_type: OtherAddaEventType;
  origin: OtherAddaOrigin;
  request_id: string;
  reverses_transaction_id: string | null;
  created_at: string;
  created_by: string;
};

/** All fields are required, including nullable fields: save is full replacement. */
export type OtherAddaMasterSnapshot = Pick<OtherAdda,
  | "adda_name" | "contact_person" | "mobile" | "whatsapp" | "city"
  | "address" | "ntn_cnic" | "business_type" | "notes"
>;

export type OtherAddaTarget = {
  /** Supported RPC target, not authorization. Omission preserves server fallback. */
  target_adda_id?: string | null;
};

export type SaveOtherAddaInput = OtherAddaMasterSnapshot & OtherAddaTarget & {
  /** null creates; an existing UUID edits that same master. */
  id: string | null;
};

export type FindOtherAddaDuplicatesInput = OtherAddaTarget & {
  adda_name: string;
  mobile?: string | null;
  city?: string | null;
};

/** Exact duplicate RPC output; business_type is NOT returned by this RPC. */
export type OtherAddaDuplicate = {
  id: string;
  adda_name: string;
  mobile: string | null;
  city: string | null;
  status: OtherAddaStatus;
  name_match: boolean;
  mobile_match: boolean;
  city_match: boolean;
};

export type PostOtherAddaObligationInput = {
  other_adda_id: string;
  transaction_date: string;
  side: OtherAddaSide;
  amount: DatabaseNumeric;
  description: string;
  reference_no?: string | null;
  dueDate?: string | null;
  /** UI owns this UUID and retains it with the payload across uncertain retries. */
  request_id: string;
};

export type OtherAddaDueStatus = "overdue" | "due_today" | "upcoming";

export interface OtherAddaDueReminder {
  transaction_id: string;
  transaction_date: string;
  due_date: string;
  side: OtherAddaSide;
  amount: DatabaseNumeric;
  reference_no: string | null;
  description: string;
  due_status: OtherAddaDueStatus;
  days_overdue: number | null;
  days_remaining: number | null;
}

export type ReverseOtherAddaObligationInput = {
  transaction_id: string;
  transaction_date: string;
  reason: string;
  request_id: string;
};

export type SetOtherAddaStatusInput = {
  other_adda_id: string;
  status: OtherAddaStatus;
};

export type OtherAddaBalance = {
  other_adda_id: string;
  gross_receivable: DatabaseNumeric;
  gross_payable: DatabaseNumeric;
  net: DatabaseNumeric;
  obligation_count: DatabaseCount;
  reversal_count: DatabaseCount;
  effective_obligation_count: DatabaseCount;
};

export type OtherAddaPayment = {
  id: string;
  payment_date: string;
  side: OtherAddaSide;
  amount: DatabaseNumeric;
  payment_method: string;
  reference_no: string | null;
  remarks: string | null;
  event_type: OtherAddaPaymentEventType;
  reverses_payment_id: string | null;
  created_at: string;
};

/** Bilty operational history for an Other Adda; settlements are authoritative only when linked. */
export type OtherAddaBiltyTrip = {
  booking_id: string;
  booking_no: string;
  booking_date: string;
  loading_date: string | null;
  vehicle_display: string | null;
  from_city: string | null;
  to_city: string | null;
  trip_type: string | null;
  freight: DatabaseNumeric;
  loading_source: string | null;
  loading_source_other_adda_id: string | null;
  loading_source_other_adda_name: string | null;
  freight_receivable_from: string | null;
  freight_receivable_other_adda_id: string | null;
  freight_receivable_other_adda_name: string | null;
  obligation_transaction_id: string | null;
  received: DatabaseNumeric | null;
  balance: DatabaseNumeric | null;
  payment_status: string | null;
  has_financial_obligation: boolean;
};

export type OtherAddaBiltyTripFilters = OtherAddaPagination & {
  other_adda_id: string;
  search?: string;
};

export type PostOtherAddaPaymentInput = {
  other_adda_id: string;
  payment_date: string;
  side: OtherAddaSide;
  amount: DatabaseNumeric;
  payment_method: string;
  reference_no?: string | null;
  remarks?: string | null;
  /** Kept with the submitted payload for safe retries after uncertain results. */
  request_id: string;
};

export type ReverseOtherAddaPaymentInput = {
  payment_id: string;
  reversal_date: string;
  reason: string;
  request_id: string;
};

/** Reads are paged (default 50, maximum 1000). Filters never confer authority. */
export type OtherAddaPagination = { offset?: number; limit?: number };
export type OtherAddaListFilters = OtherAddaPagination & {
  adda_id?: string;
  status?: OtherAddaStatus;
  business_type?: OtherAddaBusinessType;
  city?: string;
  name_search?: string;
  mobile_search?: string;
};
export type OtherAddaTransactionFilters = OtherAddaPagination & {
  other_adda_id: string;
  side?: OtherAddaSide;
  event_type?: OtherAddaEventType;
  date_from?: string;
  date_to?: string;
  /** Fetch reversal evidence for originals outside the current history page. */
  reverses_transaction_ids?: readonly string[];
};

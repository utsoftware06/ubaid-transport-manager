import { supabase } from "@/lib/supabase/client";
import type {
  DatabaseNumeric, FindOtherAddaDuplicatesInput, OtherAdda, OtherAddaBalance,
  OtherAddaDueReminder, OtherAddaDuplicate, OtherAddaListFilters, OtherAddaPagination, OtherAddaTarget,
  OtherAddaBiltyTrip, OtherAddaBiltyTripFilters, OtherAddaPayment, OtherAddaTransaction, OtherAddaTransactionFilters,
  PostOtherAddaObligationInput, PostOtherAddaPaymentInput,
  ReverseOtherAddaObligationInput, ReverseOtherAddaPaymentInput, SaveOtherAddaInput, SetOtherAddaStatusInput,
} from "./types";

const ERROR_MESSAGES = {
  active_authenticated_profile_required: "An active signed-in account is required.",
  role_not_authorized: "You do not have permission for this action.",
  tenant_mismatch: "This action is outside your authorized Adda.",
  valid_target_adda_required: "Select a valid authorized Adda.",
  other_adda_not_in_tenant: "This Other Adda is unavailable in the selected Adda.",
  invalid_master_payload: "Check Adda Name and Business Type.",
  invalid_status: "Choose Active or Archived.",
  other_adda_not_found: "Other Adda is unavailable. Refresh the list.",
  required_event_payload: "Complete the date, description or reason, and request identifier.",
  invalid_original: "This entry cannot be cancelled, or Cancel Date precedes the original Entry Date.",
  original_not_found: "The original entry is unavailable. Refresh history.",
  invalid_side_or_amount: "Choose LENA/DENA and a positive amount with at most two decimal places.",
  invalid_due_date: "Due Date cannot be earlier than Entry Date.",
  idempotency_payload_mismatch: "This request was already used with different details or another user. Resolve the original request first.",
  active_other_adda_required: "This Other Adda must be active. Ask an admin to reactivate it.",
  already_reversed: "This entry has already been cancelled. Refresh history.",
  invalid_reversal: "The Entry Cancel does not match the original entry.",
  posted_history_is_append_only: "Posted entries cannot be edited or deleted. Use an authorized Entry Cancel.",
  master_history_cannot_be_deleted: "Other Adda history cannot be deleted. Archive where eligible.",
  master_identity_is_immutable: "Other Adda identity and tenant cannot be changed.",
  invalid_reversal_state: "Reversal history needs admin review.",
  gross_obligations_outstanding: "Outstanding LENA/DENA or unresolved settlement evidence prevents archive.",
  other_adda_obligation_has_settlement: "This obligation has an active payment settlement. Reverse the payment before cancelling the obligation.",
  invalid_other_adda_payment_payload: "Enter a valid payment date, side, amount, and payment method.",
  other_adda_payment_exceeds_outstanding: "The payment amount is greater than the outstanding amount for this side.",
  other_adda_payment_allocation_evidence_inconsistent: "Settlement allocation evidence needs admin review. No payment was posted.",
  duplicate_other_adda_payment_cashbook_reference: "More than one Cashbook row exists for this payment. Contact an admin.",
  other_adda_payment_cashbook_missing: "The matching Cashbook row is missing. Contact an admin before retrying.",
  other_adda_payment_cashbook_source_missing: "The payment source for this Cashbook row is missing. Contact an admin.",
  other_adda_payment_cashbook_evidence_inconsistent: "The payment and Cashbook details do not match. Contact an admin.",
  other_adda_payment_not_found: "The payment is unavailable. Refresh payment history.",
  other_adda_payment_not_reversible: "Only an original payment can be reversed.",
  other_adda_payment_already_reversed: "This payment has already been reversed. Refresh payment history.",
  invalid_other_adda_payment_reversal_payload: "Enter a valid reversal date and reason.",
  invalid_other_adda_payment_reversal_date: "Reversal date cannot be earlier than the payment date.",
  other_adda_payment_requires_protected_rpc: "Payment history can only be changed through the protected payment action.",
  other_adda_payment_allocation_requires_protected_rpc: "Settlement allocations can only be changed through the protected payment action.",
  other_adda_payment_cashbook_requires_protected_rpc: "Payment Cashbook entries can only be created through the protected payment action.",
  other_adda_payment_cashbook_is_append_only: "Posted payment Cashbook history cannot be edited or deleted.",
  other_adda_payment_master_mismatch: "The payment does not match its Other Adda master record.",
  other_adda_payment_cashbook_tenant_or_source_mismatch: "The payment Cashbook row does not match its source. Contact an admin.",
  other_adda_payment_allocation_source_missing: "A payment allocation source is missing. Contact an admin.",
  other_adda_payment_allocation_obligation_invalid: "A payment cannot be allocated to this obligation.",
  other_adda_payment_cannot_allocate_reversed_obligation: "A reversed obligation cannot receive a payment.",
  other_adda_payment_allocation_exceeds_outstanding: "This payment exceeds the remaining obligation amount.",
  other_adda_payment_reversal_allocation_mismatch: "Payment reversal allocations do not match the original payment.",
  other_adda_bilty_obligation_evidence_inconsistent: "A linked Bilty obligation does not match its booking. Contact an admin before using this trip history.",
  other_adda_bilty_settlement_evidence_inconsistent: "Bilty settlement allocations do not reconcile to the obligation. Contact an admin before using this trip history.",
} as const;

export type OtherAddaErrorReason = keyof typeof ERROR_MESSAGES | "invalid_input" | "invalid_response" | "unknown";

export class OtherAddaError extends Error {
  readonly reason: OtherAddaErrorReason;
  readonly code: string | null;
  readonly diagnosticMessage: string;
  readonly details: string | null;
  readonly hint: string | null;
  readonly originalError: unknown;

  constructor(reason: OtherAddaErrorReason, message: string, diagnostic: {
    code?: string | null; message?: string; details?: string | null;
    hint?: string | null; originalError?: unknown;
  } = {}) {
    super(message);
    this.name = "OtherAddaError";
    this.reason = reason;
    this.code = diagnostic.code ?? null;
    this.diagnosticMessage = diagnostic.message ?? message;
    this.details = diagnostic.details ?? null;
    this.hint = diagnostic.hint ?? null;
    this.originalError = diagnostic.originalError;
  }
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Maps exact database messages; unknown diagnostics are retained, not suppressed. */
export function mapOtherAddaError(error: unknown): OtherAddaError {
  if (error instanceof OtherAddaError) return error;
  const raw = record(error) ? error : {};
  const message = typeof raw.message === "string" ? raw.message
    : typeof error === "string" ? error : "Other Adda request failed.";
  const reason = Object.keys(ERROR_MESSAGES).find((key) => key === message.trim()) as keyof typeof ERROR_MESSAGES | undefined;
  return new OtherAddaError(reason ?? "unknown", reason ? ERROR_MESSAGES[reason] : message, {
    code: typeof raw.code === "string" ? raw.code : null,
    message, details: typeof raw.details === "string" ? raw.details : null,
    hint: typeof raw.hint === "string" ? raw.hint : null, originalError: error,
  });
}

function invalidInput(message: string): never {
  throw new OtherAddaError("invalid_input", message);
}
function invalidResponse(field: string): never {
  throw new OtherAddaError("invalid_response", `Invalid Other Adda response: ${field}.`);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function uuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID.test(value)) invalidInput(`${field} must be a UUID.`);
  return value;
}
function date(value: string, field: string): string {
  const parsed = new Date(`${value}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    invalidInput(`${field} must be a valid YYYY-MM-DD date.`);
  }
  return value;
}
function nonblank(value: string, field: string): string {
  if (typeof value !== "string" || !value.trim()) invalidInput(`${field} is required.`);
  return value;
}
function choice<T extends string>(value: T, options: readonly T[], field: string): T {
  if (!options.includes(value)) invalidInput(`Invalid ${field}.`);
  return value;
}

/** Validate decimal text without rounding. Keep strings exact through RPC encoding. */
export function normalizeOtherAddaAmount(value: DatabaseNumeric): string {
  if (typeof value !== "string" && typeof value !== "number") invalidInput("Amount must be a decimal value.");
  if (typeof value === "number" && !Number.isFinite(value)) invalidInput("Amount must be finite.");
  const text = String(value).trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(text)) invalidInput("Amount must be positive with at most two decimal places.");
  const [whole, fraction = ""] = text.split(".");
  const normalizedWhole = whole.replace(/^0+(?=\d)/, "");
  const cents = BigInt(normalizedWhole) * BigInt(100) + BigInt(fraction.padEnd(2, "0"));
  if (cents <= BigInt(0) || normalizedWhole.length > 16) invalidInput("Amount is outside the supported range.");
  if (typeof value === "number" && cents > BigInt(Number.MAX_SAFE_INTEGER)) {
    invalidInput("Use an exact decimal string for large amounts.");
  }
  return `${normalizedWhole}.${fraction.padEnd(2, "0")}`;
}

type Validator = (value: unknown) => boolean;
const text: Validator = (v) => typeof v === "string";
const nullableText: Validator = (v) => v === null || text(v);
const id: Validator = (v) => typeof v === "string" && UUID.test(v);
const nullableId: Validator = (v) => v === null || id(v);
const dateText: Validator = (v) => {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return false;
  const parsed = new Date(`${v}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === v;
};
const nullableDate: Validator = (v) => v === null || dateText(v);
const nullableNonnegativeInteger: Validator = (v) => v === null || (typeof v === "number" && Number.isSafeInteger(v) && v >= 0);
const oneOf = (...values: string[]): Validator => (v) => typeof v === "string" && values.includes(v);
const numeric: Validator = (v) => {
  if (typeof v !== "number" && typeof v !== "string") return false;
  if (typeof v === "number" && !Number.isFinite(v)) return false;
  const s = String(v);
  if (!/^-?\d+(?:\.\d{1,2})?$/.test(s)) return false;
  if (typeof v === "number") {
    const [whole, fraction = ""] = s.replace(/^-/, "").split(".");
    return BigInt(whole) * BigInt(100) + BigInt(fraction.padEnd(2, "0")) <= BigInt(Number.MAX_SAFE_INTEGER);
  }
  return true;
};
const count: Validator = (v) => typeof v === "number" ? Number.isSafeInteger(v) && v >= 0
  : typeof v === "string" && /^\d+$/.test(v);
const masterShape = {
  id, adda_id: id, adda_name: text, contact_person: nullableText, mobile: nullableText,
  whatsapp: nullableText, city: nullableText, address: nullableText, ntn_cnic: nullableText,
  business_type: oneOf("regular", "one_time"), status: oneOf("active", "archived"), notes: nullableText,
  created_at: text, created_by: id, updated_at: text, updated_by: id, archived_at: nullableText, archived_by: nullableId,
} satisfies Record<keyof OtherAdda, Validator>;
const transactionShape = {
  id, adda_id: id, other_adda_id: id, transaction_date: dateText, due_date: nullableDate, side: oneOf("receivable", "payable"),
  amount: (v: unknown) => numeric(v) && Number(v) > 0, description: text, reference_no: nullableText,
  event_type: oneOf("obligation", "reversal"), origin: oneOf("manual", "bilty"), request_id: id,
  reverses_transaction_id: nullableId, created_at: text, created_by: id,
} satisfies Record<keyof OtherAddaTransaction, Validator>;
const reminderShape = {
  transaction_id: id, transaction_date: dateText, due_date: dateText,
  side: oneOf("receivable", "payable"), amount: (v: unknown) => numeric(v) && Number(v) > 0,
  reference_no: nullableText, description: text, due_status: oneOf("overdue", "due_today", "upcoming"),
  days_overdue: nullableNonnegativeInteger, days_remaining: nullableNonnegativeInteger,
} satisfies Record<keyof OtherAddaDueReminder, Validator>;
const balanceShape = {
  other_adda_id: id, gross_receivable: numeric, gross_payable: numeric, net: numeric,
  obligation_count: count, reversal_count: count, effective_obligation_count: count,
} satisfies Record<keyof OtherAddaBalance, Validator>;
const paymentShape = {
  id, payment_date: dateText, side: oneOf("receivable", "payable"),
  amount: (v: unknown) => numeric(v) && Number(v) > 0, payment_method: text,
  reference_no: nullableText, remarks: nullableText,
  event_type: oneOf("payment", "reversal"), reverses_payment_id: nullableId, created_at: text,
} satisfies Record<keyof OtherAddaPayment, Validator>;
const nullableNumeric: Validator = (v) => v === null || numeric(v);
const tripShape = {
  booking_id: id, booking_no: text, booking_date: dateText, loading_date: nullableDate,
  vehicle_display: nullableText, from_city: nullableText, to_city: nullableText,
  trip_type: nullableText, freight: numeric, loading_source: nullableText,
  loading_source_other_adda_id: nullableId, loading_source_other_adda_name: nullableText,
  freight_receivable_from: nullableText, freight_receivable_other_adda_id: nullableId,
  freight_receivable_other_adda_name: nullableText, obligation_transaction_id: nullableId,
  received: nullableNumeric, balance: nullableNumeric, payment_status: nullableText,
  has_financial_obligation: (v: unknown) => typeof v === "boolean",
} satisfies Record<keyof OtherAddaBiltyTrip, Validator>;
const duplicateShape = {
  id, adda_name: text, mobile: nullableText, city: nullableText, status: oneOf("active", "archived"),
  name_match: (v: unknown) => typeof v === "boolean", mobile_match: (v: unknown) => typeof v === "boolean",
  city_match: (v: unknown) => typeof v === "boolean",
} satisfies Record<keyof OtherAddaDuplicate, Validator>;

function decode<T>(value: unknown, shape: Record<string, Validator>): T {
  if (!record(value)) invalidResponse("row");
  for (const [field, validate] of Object.entries(shape)) {
    if (!validate(value[field])) invalidResponse(field);
  }
  return value as T;
}
function rows<T>(value: unknown, shape: Record<string, Validator>): T[] {
  if (!Array.isArray(value)) invalidResponse("expected row array");
  return value.map((row: unknown) => decode<T>(row, shape));
}

async function result<T>(request: PromiseLike<{ data: unknown; error: unknown }>, parse: (data: unknown) => T): Promise<T> {
  try {
    const response = await request;
    if (response.error) throw mapOtherAddaError(response.error);
    return parse(response.data);
  } catch (error) {
    throw mapOtherAddaError(error);
  }
}
function range(input: OtherAddaPagination): [number, number] {
  const offset = input.offset ?? 0;
  const limit = input.limit ?? 50;
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 1000 || !Number.isSafeInteger(offset + limit)) {
    invalidInput("Invalid pagination: limit must be 1–1000 and offset nonnegative.");
  }
  return [offset, offset + limit - 1];
}
function targetArgs(input: OtherAddaTarget): { p_target_adda_id?: string | null } {
  return input.target_adda_id === undefined ? {} : {
    p_target_adda_id: input.target_adda_id === null ? null : uuid(input.target_adda_id, "Target Adda"),
  };
}
function returnedId(value: unknown): string {
  if (!id(value)) invalidResponse("returned UUID");
  return value as string;
}
const MASTER_FIELDS = "id,adda_id,adda_name,contact_person,mobile,whatsapp,city,address,ntn_cnic,business_type,status,notes,created_at,created_by,updated_at,updated_by,archived_at,archived_by";
const TRANSACTION_FIELDS = "id,adda_id,other_adda_id,transaction_date,due_date,side,amount,description,reference_no,event_type,origin,request_id,reverses_transaction_id,created_at,created_by";
const literalLike = (value: string) => `%${value.replace(/[\\%_]/g, "\\$&")}%`;

/** Optional adda_id is a read filter only. RLS, never this filter, authorizes rows. */
export async function listOtherAddas(filters: OtherAddaListFilters = {}): Promise<OtherAdda[]> {
  let query = supabase.from("other_addas").select(MASTER_FIELDS);
  if (filters.adda_id !== undefined) query = query.eq("adda_id", uuid(filters.adda_id, "Adda filter"));
  if (filters.status !== undefined) query = query.eq("status", choice(filters.status, ["active", "archived"], "status"));
  if (filters.business_type !== undefined) query = query.eq("business_type", choice(filters.business_type, ["regular", "one_time"], "business type"));
  if (filters.city !== undefined) query = query.eq("city", filters.city);
  if (filters.name_search) query = query.ilike("adda_name", literalLike(filters.name_search));
  if (filters.mobile_search) query = query.ilike("mobile", literalLike(filters.mobile_search));
  return result(query.order("adda_name").order("id").range(...range(filters)), (data) => rows<OtherAdda>(data, masterShape));
}

/** Successful RLS-hidden/missing record is null; a failed request always throws. */
export async function getOtherAdda(otherAddaId: string): Promise<OtherAdda | null> {
  return result(supabase.from("other_addas").select(MASTER_FIELDS).eq("id", uuid(otherAddaId, "Other Adda")).maybeSingle(),
    (data) => data === null ? null : decode<OtherAdda>(data, masterShape));
}

/** Paginated events are history, not authoritative account totals. */
export async function listOtherAddaTransactions(filters: OtherAddaTransactionFilters): Promise<OtherAddaTransaction[]> {
  let query = supabase.from("other_adda_transactions").select(TRANSACTION_FIELDS)
    .eq("other_adda_id", uuid(filters.other_adda_id, "Other Adda"));
  if (filters.side !== undefined) query = query.eq("side", choice(filters.side, ["receivable", "payable"], "side"));
  if (filters.event_type !== undefined) query = query.eq("event_type", choice(filters.event_type, ["obligation", "reversal"], "event type"));
  if (filters.date_from) query = query.gte("transaction_date", date(filters.date_from, "From date"));
  if (filters.date_to) query = query.lte("transaction_date", date(filters.date_to, "To date"));
  if (filters.date_from && filters.date_to && filters.date_from > filters.date_to) invalidInput("From date must not exceed To date.");
  if (filters.reverses_transaction_ids !== undefined) {
    if (!filters.reverses_transaction_ids.length || filters.reverses_transaction_ids.length > 1000) invalidInput("Provide 1–1000 original transaction IDs.");
    query = query.in("reverses_transaction_id", filters.reverses_transaction_ids.map((value) => uuid(value, "Original transaction")));
  }
  return result(query.order("transaction_date", { ascending: false }).order("created_at", { ascending: false })
    .order("id", { ascending: false }).range(...range(filters)), (data) => rows<OtherAddaTransaction>(data, transactionShape));
}

export async function getOtherAddaBalances(target: OtherAddaTarget = {}): Promise<OtherAddaBalance[]> {
  return result(supabase.rpc("get_other_adda_balances", targetArgs(target)), (data) => rows<OtherAddaBalance>(data, balanceShape));
}

/** Account-scoped, server-authorized reminders. Omission uses the RPC's Asia/Karachi date fallback. */
export async function getOtherAddaDueReminders(otherAddaId: string, asOfDate?: string): Promise<OtherAddaDueReminder[]> {
  const args: { p_other_adda_id: string; p_as_of_date?: string } = {
    p_other_adda_id: uuid(otherAddaId, "Other Adda"),
  };
  if (asOfDate !== undefined) args.p_as_of_date = date(asOfDate, "As-of date");
  return result(supabase.rpc("get_other_adda_due_reminders", args), (data) => {
    const reminders = rows<OtherAddaDueReminder>(data, reminderShape);
    for (const reminder of reminders) {
      const validDays = reminder.due_status === "overdue"
        ? reminder.days_overdue !== null && reminder.days_overdue > 0 && reminder.days_remaining === null
        : reminder.due_status === "due_today"
          ? reminder.days_overdue === null && reminder.days_remaining === null
          : reminder.days_remaining !== null && reminder.days_remaining > 0 && reminder.days_overdue === null;
      if (!validDays) invalidResponse("due status day values");
    }
    return reminders;
  });
}

/** Payment history is returned by the tenant-authorizing read RPC. */
export async function getOtherAddaPayments(otherAddaId: string): Promise<OtherAddaPayment[]> {
  return result(supabase.rpc("get_other_adda_payments", {
    p_other_adda_id: uuid(otherAddaId, "Other Adda"),
  }), (data) => rows<OtherAddaPayment>(data, paymentShape));
}

/** Tenant-authorized operational and settlement history; the RPC derives Adda from the master. */
export async function getOtherAddaBiltyTrips(filters: OtherAddaBiltyTripFilters): Promise<OtherAddaBiltyTrip[]> {
  const limit = filters.limit ?? 25;
  const offset = filters.offset ?? 0;
  range({ limit, offset });
  return result(supabase.rpc("get_other_adda_bilty_trips", {
    p_other_adda_id: uuid(filters.other_adda_id, "Other Adda"),
    p_search: filters.search?.trim() || null,
    p_limit: limit,
    p_offset: offset,
  }), (data) => rows<OtherAddaBiltyTrip>(data, tripShape));
}

/** The payment RPC derives Adda from the persisted Other Adda master. */
export async function postOtherAddaPayment(input: PostOtherAddaPaymentInput): Promise<string> {
  return result(supabase.rpc("post_other_adda_payment", {
    p_other_adda_id: uuid(input.other_adda_id, "Other Adda"),
    p_payment_date: date(input.payment_date, "Payment date"),
    p_side: choice(input.side, ["receivable", "payable"], "side"),
    p_amount: normalizeOtherAddaAmount(input.amount),
    p_payment_method: nonblank(input.payment_method, "Payment method").trim(),
    p_reference_no: input.reference_no?.trim() || null,
    p_remarks: input.remarks?.trim() || null,
    p_request_id: uuid(input.request_id, "Request ID"),
  }), returnedId);
}

/** Payment reversals are appended; the original payment is never edited or deleted. */
export async function reverseOtherAddaPayment(input: ReverseOtherAddaPaymentInput): Promise<string> {
  return result(supabase.rpc("reverse_other_adda_payment", {
    p_payment_id: uuid(input.payment_id, "Payment"),
    p_reversal_date: date(input.reversal_date, "Reversal date"),
    p_reason: nonblank(input.reason, "Reversal reason").trim(),
    p_request_id: uuid(input.request_id, "Request ID"),
  }), returnedId);
}

export async function findOtherAddaDuplicates(input: FindOtherAddaDuplicatesInput): Promise<OtherAddaDuplicate[]> {
  return result(supabase.rpc("find_other_adda_duplicates", {
    p_adda_name: input.adda_name, p_mobile: input.mobile ?? null, p_city: input.city ?? null, ...targetArgs(input),
  }), (data) => rows<OtherAddaDuplicate>(data, duplicateShape));
}

/** Complete replacement only: even nullable snapshot fields must be supplied. */
export async function saveOtherAdda(input: SaveOtherAddaInput): Promise<string> {
  const snapshotFields = ["contact_person", "mobile", "whatsapp", "city", "address", "ntn_cnic", "notes"] as const;
  for (const field of snapshotFields) {
    if (!nullableText(input[field])) invalidInput(`Complete master snapshot required: ${field}.`);
  }
  return result(supabase.rpc("save_other_adda", {
    p_id: input.id === null ? null : uuid(input.id, "Master ID"),
    p_adda_name: nonblank(input.adda_name, "Adda Name"), p_contact_person: input.contact_person,
    p_mobile: input.mobile, p_whatsapp: input.whatsapp, p_city: input.city, p_address: input.address,
    p_ntn_cnic: input.ntn_cnic, p_business_type: choice(input.business_type, ["regular", "one_time"], "business type"),
    p_notes: input.notes, ...targetArgs(input),
  }), returnedId);
}
export async function setOtherAddaStatus(input: SetOtherAddaStatusInput): Promise<string> {
  return result(supabase.rpc("set_other_adda_status", {
    p_other_adda_id: uuid(input.other_adda_id, "Other Adda"), p_status: choice(input.status, ["active", "archived"], "status"),
  }), returnedId);
}

/** No UUID generation and no automatic mutation retry: UI retains request+payload. */
export async function postOtherAddaObligation(input: PostOtherAddaObligationInput): Promise<string> {
  return result(supabase.rpc("post_other_adda_obligation_v2", {
    p_other_adda_id: uuid(input.other_adda_id, "Other Adda"), p_transaction_date: date(input.transaction_date, "Transaction date"),
    p_side: choice(input.side, ["receivable", "payable"], "side"), p_amount: normalizeOtherAddaAmount(input.amount),
    p_description: nonblank(input.description, "Description"), p_request_id: uuid(input.request_id, "Request ID"),
    p_reference_no: input.reference_no ?? null,
    p_due_date: input.dueDate == null ? null : date(input.dueDate, "Due Date"),
  }), returnedId);
}
export async function reverseOtherAddaObligation(input: ReverseOtherAddaObligationInput): Promise<string> {
  return result(supabase.rpc("reverse_other_adda_obligation", {
    p_transaction_id: uuid(input.transaction_id, "Original transaction"), p_transaction_date: date(input.transaction_date, "Reversal date"),
    p_reason: nonblank(input.reason, "Reversal reason"), p_request_id: uuid(input.request_id, "Request ID"),
  }), returnedId);
}

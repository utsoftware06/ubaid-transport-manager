import { supabase } from "@/lib/supabase/client";
import type {
  AddaAccountCategory,
  AddaAccountEmployee,
  AddaAccountEntry,
  AddaAccountKind,
  AddaAccountEntryMetadata,
  AddaLoadingMarginDetails,
  AddaAccountEntryMetadataPayload,
  AddaAccountFilters,
  AddaFinanceSettlement,
  AddaFinanceSummary,
  AddaExpensePayload,
  AddaOtherIncomePayload,
  AddaSettlementPayload,
} from "./types";

type Row = Record<string, unknown>;

function asRow(value: unknown): Row {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
  }
  return value as Row;
}

function asRows(value: unknown): Row[] {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
  return value.map(asRow);
}

function stringValue(value: unknown, nullable = false): string | null {
  if (typeof value === "string") return value;
  if (nullable && value == null) return null;
  throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
}

function numberValue(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  if (!Number.isFinite(parsed)) throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
  return parsed;
}

function booleanValue(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
}

async function rpc(name: string, args: Record<string, unknown>) {
  const response = await supabase.rpc(name, args as never);
  if (response.error) throw response.error;
  return response.data as unknown;
}

export function mapAddaFinanceError(error: unknown, fallback: string) {
  const errorFields = error && typeof error === "object" ? error as Record<string, unknown> : {};
  const message = [errorFields.message, errorFields.details, errorFields.hint, errorFields.code]
    .filter((value): value is string => typeof value === "string" && value.length > 0)
    .join(" ") || (error instanceof Error ? error.message : String(error ?? ""));
  const marker = message.toUpperCase();
  const messages: Array<[string, string]> = [
    ["AUTHENTICATION_REQUIRED", "Your session has expired. Sign in again."],
    ["ADDA_SELECTION_REQUIRED", "Select an Adda before continuing."],
    ["ADDA_AUTHORIZATION_MISMATCH", "The selected Adda could not be verified."],
    ["TENANT_MISMATCH", "This record belongs to a different Adda."],
    ["ADDA_FINANCE_MANUAL_CATEGORY_REQUIRED", "Choose an active manual expense category."],
    ["ADDA_FINANCE_EMPLOYEE_ADDA_MISMATCH", "The selected employee does not belong to this Adda."],
    ["ADDA_FINANCE_PAYMENT_METHOD_REQUIRED", "Select a payment method when recording a payment or receipt."],
    ["ADDA_FINANCE_SETTLEMENT_EXCEEDS_PENDING_AMOUNT", "That amount exceeds the remaining unsettled balance."],
    ["ADDA_FINANCE_ACTIVE_SETTLEMENTS_MUST_BE_REVERSED_FIRST", "Reverse all active settlements before reversing this entry."],
    ["ADDA_FINANCE_ENTRY_ALREADY_REVERSED", "This entry has already been reversed."],
    ["ADDA_FINANCE_SETTLEMENT_ALREADY_REVERSED", "This settlement has already been reversed."],
    ["ADDA_FINANCE_SETTLEMENT_REVERSAL_TARGET_INVALID", "Select an active original payment or receipt to reverse."],
    ["ADDA_FINANCE_SETTLEMENT_EVIDENCE_INCONSISTENT", "Settlement history is inconsistent. No changes were made."],
    ["ADDA_FINANCE_SETTLEMENT_NOT_FOUND", "This settlement is no longer available. Refresh the entry history."],
    ["ADDA_FINANCE_SETTLEMENT_NOT_REVERSIBLE", "Only an active original payment or receipt can be reversed."],
    ["ADDA_FINANCE_ENTRY_NOT_ACTIVE", "This entry is already reversed or no longer active."],
    ["INVALID_ADDA_FINANCE_REVERSAL_PAYLOAD", "Enter a reversal date and reason."],
    ["ADDA_FINANCE_CASHBOOK_EVIDENCE_INCONSISTENT", "Cashbook evidence is inconsistent. No changes were made."],
    ["ADDA_FINANCE_SOURCE_JOURNAL_EVIDENCE_INCONSISTENT", "The source and journal do not match. No changes were made."],
    ["ADDA_FINANCE_INITIAL_SETTLEMENT_EVIDENCE_INCONSISTENT", "The settlement evidence does not match. No changes were made."],
    ["ADDA_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH", "This retry key was already used for different values."],
    ["ADDA_FINANCE_REQUEST_ID_ALREADY_USED", "This request key was already used. Retry with a new request."],
    ["ADDA_FINANCE_ENTRY_NOT_SETTLEABLE", "This entry is not available for settlement."],
    ["ADDA_FINANCE_ENTRY_NOT_REVERSIBLE", "This entry cannot be reversed through the manual workflow."],
    ["ADDA_FINANCE_ENTRY_METADATA_NOT_EDITABLE", "Only active manual Adda Finance entries can have descriptive details edited."],
    ["ADDA_FINANCE_METADATA_IDEMPOTENCY_MISMATCH", "This retry key was already used for different entry details."],
    ["ADDA_FINANCE_SETTLEMENT_NOT_REVERSIBLE", "This row is not an original settlement."],
    ["INVALID_ADDA_FINANCE", "Check the entered amount, date, and required fields."],
    ["VEHICLE_COMMISSION_BEFORE_PROSPECTIVE_CUTOVER", "Commission generation is available from October 2026 onward."],
    ["VEHICLE_COMMISSION_ALREADY_REVERSED", "This monthly commission has already been reversed."],
    ["VEHICLE_COMMISSION_EXISTING_PROJECTION_CONFLICT", "The commission source has an inconsistent projection. No changes were made."],
    ["VEHICLE_COMMISSION_PARTIAL_PROJECTION_CONFLICT", "A partial commission projection already exists. No changes were made."],
    ["VEHICLE_COMMISSION_JOURNAL_SOURCE_CONFLICT", "The Adda journal projection is inconsistent. No changes were made."],
    ["VEHICLE_COMMISSION_OWNER_SOURCE_CONFLICT", "The Owner/Gari projection is inconsistent. No changes were made."],
    ["VEHICLE_BELONGS_TO_ANOTHER_ADDA", "Select a vehicle that belongs to this Adda."],
  ];
  return messages.find(([key]) => marker.includes(key))?.[1] ?? fallback;
}

export type AddaVehicleCommissionSetting = {
  vehicle_id: string;
  vehicle_no: string | null;
  owner_name: string | null;
  monthly_amount: number;
  is_active: boolean;
  effective_from: string | null;
  updated_at: string;
};

export type AddaVehicleCommissionPreview = {
  vehicle_id: string;
  vehicle_no: string | null;
  owner_name: string | null;
  monthly_amount: number;
  accounting_month: string;
  setting_effective_from: string | null;
  existing_event_id: string | null;
  reversal_event_id: string | null;
  generation_status: "Ready" | "Already Generated" | "Not Eligible";
  eligibility_reason: string | null;
};

export type AddaVehicleCommissionHistory = {
  event_id: string;
  vehicle_id: string;
  vehicle_no: string | null;
  owner_name: string | null;
  accounting_month: string;
  amount: number;
  event_type: "commission" | "reversal" | "reissue" | "adjustment_increase" | "adjustment_decrease";
  reverses_event_id: string | null;
  reversal_event_id: string | null;
  reversal_date: string | null;
  reversal_reason: string | null;
  parent_event_id: string | null;
  root_event_id: string | null;
  correction_reason: string | null;
  signed_effect: number;
  root_original_amount: number;
  total_reversals: number;
  total_reissues: number;
  total_adjustment_increases: number;
  total_adjustment_decreases: number;
  effective_root_amount: number;
  effective_root_status: string;
  active_charge_event_id: string | null;
  can_reverse: boolean;
  can_reissue: boolean;
  can_adjust: boolean;
  owner_transaction_id: string | null;
  account_entry_id: string | null;
  event_created_at: string;
  status: string;
};

export type AddaCommissionVehicle = {
  id: string;
  vehicle_no: string | null;
  owner_name: string | null;
};

export async function listAddaCommissionVehicles(addaId: string): Promise<AddaCommissionVehicle[]> {
  const response = await supabase.from("vehicles").select("id, vehicle_no, owner_name")
    .eq("adda_id", addaId).order("vehicle_no");
  if (response.error) throw response.error;
  return (response.data ?? []).map((row) => ({
    id: String(row.id),
    vehicle_no: typeof row.vehicle_no === "string" ? row.vehicle_no : null,
    owner_name: typeof row.owner_name === "string" ? row.owner_name : null,
  }));
}

export async function listAddaVehicleCommissionSettings(addaId: string): Promise<AddaVehicleCommissionSetting[]> {
  return asRows(await rpc("get_adda_vehicle_commission_settings", { p_adda_id: addaId })).map((row) => ({
    vehicle_id: stringValue(row.vehicle_id) as string,
    vehicle_no: stringValue(row.vehicle_no, true),
    owner_name: stringValue(row.owner_name, true),
    monthly_amount: numberValue(row.monthly_amount),
    is_active: booleanValue(row.is_active),
    effective_from: stringValue(row.effective_from, true),
    updated_at: stringValue(row.updated_at) as string,
  }));
}

export async function previewAddaVehicleCommissionMonth(addaId: string, month: string): Promise<AddaVehicleCommissionPreview[]> {
  return asRows(await rpc("preview_adda_vehicle_commission_month", {
    p_adda_id: addaId, p_month: `${month}-01`,
  })).map((row) => {
    const status = stringValue(row.generation_status);
    if (status !== "Ready" && status !== "Already Generated" && status !== "Not Eligible") {
      throw new Error("INVALID_VEHICLE_COMMISSION_RESPONSE");
    }
    return {
      vehicle_id: stringValue(row.vehicle_id) as string,
      vehicle_no: stringValue(row.vehicle_no, true),
      owner_name: stringValue(row.owner_name, true),
      monthly_amount: numberValue(row.monthly_amount),
      accounting_month: stringValue(row.accounting_month) as string,
      setting_effective_from: stringValue(row.setting_effective_from, true),
      existing_event_id: stringValue(row.existing_event_id, true),
      reversal_event_id: stringValue(row.reversal_event_id, true),
      generation_status: status,
      eligibility_reason: stringValue(row.eligibility_reason, true),
    };
  });
}

export async function listAddaVehicleCommissionHistory(addaId: string): Promise<AddaVehicleCommissionHistory[]> {
  return asRows(await rpc("get_adda_vehicle_commission_history_v2", { p_adda_id: addaId, p_limit: 200 })).map((row) => {
    const eventType = stringValue(row.event_type);
    const status = stringValue(row.reversal_status);
    const eventTypes = ["commission", "reversal", "reissue", "adjustment_increase", "adjustment_decrease"] as const;
    if (!eventTypes.includes(eventType as (typeof eventTypes)[number])
      || typeof status !== "string") {
      throw new Error("INVALID_VEHICLE_COMMISSION_RESPONSE");
    }
    return {
      event_id: stringValue(row.event_id) as string,
      vehicle_id: stringValue(row.vehicle_id) as string,
      vehicle_no: stringValue(row.vehicle_no, true),
      owner_name: stringValue(row.owner_name, true),
      accounting_month: stringValue(row.accounting_month) as string,
      amount: numberValue(row.amount),
      event_type: eventType as AddaVehicleCommissionHistory["event_type"],
      reverses_event_id: stringValue(row.reverses_event_id, true),
      reversal_event_id: stringValue(row.reversal_event_id, true),
      reversal_date: stringValue(row.reversal_date, true),
      reversal_reason: stringValue(row.reversal_reason, true),
      parent_event_id: stringValue(row.parent_event_id, true),
      root_event_id: stringValue(row.root_event_id, true),
      correction_reason: stringValue(row.correction_reason, true),
      signed_effect: numberValue(row.signed_effect),
      root_original_amount: numberValue(row.root_original_amount),
      total_reversals: numberValue(row.total_reversals),
      total_reissues: numberValue(row.total_reissues),
      total_adjustment_increases: numberValue(row.total_adjustment_increases),
      total_adjustment_decreases: numberValue(row.total_adjustment_decreases),
      effective_root_amount: numberValue(row.effective_root_amount),
      effective_root_status: stringValue(row.effective_root_status) as string,
      active_charge_event_id: stringValue(row.active_charge_event_id, true),
      can_reverse: booleanValue(row.can_reverse),
      can_reissue: booleanValue(row.can_reissue),
      can_adjust: booleanValue(row.can_adjust),
      owner_transaction_id: null,
      account_entry_id: null,
      event_created_at: stringValue(row.created_at) as string,
      status: status as AddaVehicleCommissionHistory["status"],
    };
  });
}

export async function saveAddaVehicleCommissionSetting(input: {
  addaId: string; vehicleId: string; monthlyAmount: number; isActive: boolean; effectiveFrom: string | null;
}) {
  await rpc("save_adda_vehicle_commission_setting", {
    p_adda_id: input.addaId,
    p_vehicle_id: input.vehicleId,
    p_monthly_amount: input.monthlyAmount,
    p_is_active: input.isActive,
    p_effective_from: input.effectiveFrom,
  });
}

export async function generateAddaVehicleCommissionMonth(addaId: string, month: string, requestId: string) {
  return asRow(await rpc("generate_adda_vehicle_commission_month", {
    p_adda_id: addaId, p_month: `${month}-01`, p_request_id: requestId,
  }));
}

export async function reverseAddaVehicleCommission(input: {
  addaId: string; originalEventId: string; reversalDate: string; reason: string; requestId: string;
}) {
  return stringValue(await rpc("reverse_adda_vehicle_commission", {
    p_adda_id: input.addaId,
    p_original_event_id: input.originalEventId,
    p_reversal_date: input.reversalDate,
    p_reason: input.reason,
    p_request_id: input.requestId,
  })) as string;
}

export async function reissueAddaVehicleCommission(input: {
  addaId: string; reversalEventId: string; reason: string; requestId: string;
}) {
  return stringValue(await rpc("reissue_adda_vehicle_commission", {
    p_adda_id: input.addaId,
    p_reversal_event_id: input.reversalEventId,
    p_reason: input.reason,
    p_request_id: input.requestId,
  })) as string;
}

export async function adjustAddaVehicleCommission(input: {
  addaId: string; targetEventId: string; direction: "increase" | "decrease";
  amount: number; reason: string; requestId: string;
}) {
  return stringValue(await rpc("adjust_adda_vehicle_commission", {
    p_adda_id: input.addaId,
    p_target_event_id: input.targetEventId,
    p_direction: input.direction,
    p_amount: input.amount,
    p_reason: input.reason,
    p_request_id: input.requestId,
  })) as string;
}

export async function reverseAddaVehicleCommissionCorrection(input: {
  addaId: string; targetEventId: string; reversalDate: string; reason: string; requestId: string;
}) {
  return stringValue(await rpc("reverse_adda_vehicle_commission_correction", {
    p_adda_id: input.addaId,
    p_target_event_id: input.targetEventId,
    p_reversal_date: input.reversalDate,
    p_reason: input.reason,
    p_request_id: input.requestId,
  })) as string;
}

export async function ensureAddaFinanceCategories(addaId: string) {
  const data = await rpc("ensure_adda_finance_categories", { p_adda_id: addaId });
  return numberValue(data);
}

export async function listManualExpenseCategories(addaId: string): Promise<AddaAccountCategory[]> {
  const rows = asRows(await rpc("get_adda_expense_categories", { p_adda_id: addaId }));
  return rows.map((row) => {
    if (row.source_policy !== "manual") throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
    return {
      id: stringValue(row.id) as string,
      adda_id: stringValue(row.adda_id) as string,
      category_code: stringValue(row.category_code) as string,
      name: stringValue(row.name) as string,
      source_policy: "manual",
      is_active: booleanValue(row.is_active),
    };
  });
}

export async function getAddaFinanceSummary(addaId: string, from: string | null, to: string | null): Promise<AddaFinanceSummary> {
  const rows = asRows(await rpc("get_adda_account_summary_v4", { p_adda_id: addaId, p_from: from, p_to: to }));
  const row = rows[0];
  if (!row) throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
  return {
    total_income: numberValue(row.total_income),
    total_expense: numberValue(row.total_expense),
    net_profit: numberValue(row.net_profit),
    bilty_margin_income: numberValue(row.bilty_margin_income),
    bilty_loss_expense: numberValue(row.bilty_loss_expense),
    vehicle_monthly_commission_income: numberValue(row.vehicle_monthly_commission_income),
    employee_expense: numberValue(row.employee_expense),
    other_income: numberValue(row.other_income),
    settled_income: numberValue(row.settled_income),
    pending_income: numberValue(row.pending_income),
    settled_expense: numberValue(row.settled_expense),
    pending_expense: numberValue(row.pending_expense),
    bilty_margin_earned: numberValue(row.bilty_margin_earned),
    bilty_margin_realized: numberValue(row.bilty_margin_realized),
    bilty_margin_pending: numberValue(row.bilty_margin_pending),
    vehicle_commission_effective: numberValue(row.vehicle_commission_effective),
    issued_freight_financing_commission_income: numberValue(row.issued_freight_financing_commission_income),
  };
}

export async function getAddaEmployeeLoanReceivable(addaId: string): Promise<number> {
  const rows = asRows(await rpc("get_adda_employee_loan_receivable", { p_adda_id: addaId }));
  const row = rows[0];
  if (!row) throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
  return numberValue(row.employee_loan_receivable);
}

export async function listAddaAccountEntries(addaId: string, filters: AddaAccountFilters): Promise<AddaAccountEntry[]> {
  const rows = asRows(await rpc("get_adda_account_entries_v2", {
    p_adda_id: addaId,
    p_from: filters.from,
    p_to: filters.to,
    p_kind: filters.kind,
    p_category_id: filters.categoryId,
    p_vehicle_id: null,
    p_employee_id: filters.employeeId,
    p_search: filters.search,
    p_limit: filters.limit,
    p_offset: filters.offset,
  }));
  const entries = rows.map((row) => {
    const kind = stringValue(row.entry_kind);
    const status = stringValue(row.entry_status);
    if (kind !== "income" && kind !== "expense") throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
    if (!["pending", "partial", "settled", "reversal", "reversed", "realized"].includes(status as string)) {
      throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
    }
    const realizationStatus = stringValue(row.realization_status, true);
    if (realizationStatus !== null && !["pending", "partial", "realized", "reversed"].includes(realizationStatus)) {
      throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
    }
    return {
      id: stringValue(row.id) as string,
      adda_id: stringValue(row.adda_id) as string,
      entry_date: stringValue(row.entry_date) as string,
      entry_kind: kind as AddaAccountKind,
      category_id: stringValue(row.category_id, true),
      category_code: stringValue(row.category_code, true),
      category_name: stringValue(row.category_name, true),
      amount: numberValue(row.amount),
      source_type: stringValue(row.source_type) as string,
      source_id: stringValue(row.source_id) as string,
      booking_id: stringValue(row.booking_id, true),
      loading_id: row.loading_id == null ? null : numberValue(row.loading_id),
      vehicle_id: stringValue(row.vehicle_id, true),
      employee_id: stringValue(row.employee_id, true),
      salary_record_id: row.salary_record_id == null ? null : numberValue(row.salary_record_id),
      reference_no: stringValue(row.reference_no, true),
      description: stringValue(row.description, true),
      remarks: null,
      adda_name: null,
      reverses_entry_id: stringValue(row.reverses_entry_id, true),
      request_id: stringValue(row.request_id, true),
      created_at: stringValue(row.created_at) as string,
      created_by: stringValue(row.created_by, true),
      net_settled_amount: numberValue(row.net_settled_amount),
      pending_amount: numberValue(row.pending_amount),
      is_reversal: booleanValue(row.is_reversal),
      is_reversed: booleanValue(row.is_reversed),
      entry_status: status as AddaAccountEntry["entry_status"],
      earned_amount: row.earned_amount == null ? null : numberValue(row.earned_amount),
      realized_amount: row.realized_amount == null ? null : numberValue(row.realized_amount),
      margin_pending_amount: row.margin_pending_amount == null ? null : numberValue(row.margin_pending_amount),
      received_basis_amount: row.received_basis_amount == null ? null : numberValue(row.received_basis_amount),
      vehicle_freight: row.vehicle_freight == null ? null : numberValue(row.vehicle_freight),
      freight: row.freight == null ? null : numberValue(row.freight),
      realization_status: realizationStatus as AddaAccountEntry["realization_status"],
    };
  });
  if (entries.length === 0) return entries;
  const loadingIds = entries
    .filter((entry) => ["bilty_margin", "bilty_loss"].includes(entry.source_type) && entry.loading_id !== null)
    .map((entry) => entry.loading_id as number);
  const [metadata, loadingDetails] = await Promise.all([
    getAddaAccountEntryMetadata(addaId, entries.map((entry) => entry.id)),
    getAddaLoadingMarginDetails(addaId, [...new Set(loadingIds)]),
  ]);
  const metadataById = new Map(metadata.map((item) => [item.account_entry_id, item]));
  const loadingDetailsById = new Map(loadingDetails.map((item) => [item.loading_id, item]));
  return entries.map((entry) => {
    const current = metadataById.get(entry.id);
    return {
      ...entry,
      ...(current ? {
        reference_no: current.reference_no,
        description: current.description,
        remarks: current.remarks,
        adda_name: current.adda_name,
      } : {}),
      loading_details: entry.loading_id === null ? null : loadingDetailsById.get(entry.loading_id) ?? null,
    };
  });
}

export async function getAddaLoadingMarginDetails(
  addaId: string,
  loadingIds: number[]
): Promise<AddaLoadingMarginDetails[]> {
  if (loadingIds.length === 0) return [];
  const rows = asRows(await rpc("get_adda_loading_margin_details", {
    p_adda_id: addaId,
    p_loading_ids: loadingIds,
  }));
  return rows.map((row) => ({
    loading_id: numberValue(row.loading_id),
    booking_id: stringValue(row.booking_id) as string,
    booking_no: stringValue(row.booking_no, true),
    loading_no: stringValue(row.loading_no, true),
    loading_date: stringValue(row.loading_date, true),
    vehicle_no: stringValue(row.vehicle_no, true),
    from_city: stringValue(row.from_city, true),
    to_city: stringValue(row.to_city, true),
    route: stringValue(row.route, true),
    margin_amount: numberValue(row.margin_amount),
    is_reversed: booleanValue(row.is_reversed),
  }));
}

export async function getAddaAccountEntryMetadata(addaId: string, entryIds: string[]): Promise<AddaAccountEntryMetadata[]> {
  if (entryIds.length === 0) return [];
  const rows = asRows(await rpc("get_adda_account_entry_metadata", {
    p_adda_id: addaId,
    p_account_entry_ids: entryIds,
  }));
  return rows.map((row) => ({
    account_entry_id: stringValue(row.account_entry_id) as string,
    adda_name: stringValue(row.adda_name) as string,
    reference_no: stringValue(row.reference_no, true),
    description: stringValue(row.description, true),
    remarks: stringValue(row.remarks, true),
  }));
}

export async function updateAddaAccountEntryMetadata(payload: AddaAccountEntryMetadataPayload) {
  return stringValue(await rpc("update_adda_account_entry_metadata", {
    p_adda_id: payload.addaId,
    p_account_entry_id: payload.accountEntryId,
    p_reference_no: payload.referenceNo,
    p_description: payload.description,
    p_remarks: payload.remarks,
    p_request_id: payload.requestId,
  })) as string;
}

export async function listAddaFinanceSettlements(addaId: string, accountEntryId: string): Promise<AddaFinanceSettlement[]> {
  const rows = asRows(await rpc("get_adda_finance_settlements", {
    p_adda_id: addaId,
    p_account_entry_id: accountEntryId,
  }));
  return rows.map((row) => {
    const eventType = stringValue(row.event_type);
    const entryKind = stringValue(row.entry_kind);
    const cashbookType = stringValue(row.cashbook_entry_type, true);
    if ((eventType !== "settlement" && eventType !== "reversal")
      || (entryKind !== "income" && entryKind !== "expense")
      || (cashbookType !== null && cashbookType !== "Cash In" && cashbookType !== "Cash Out")) {
      throw new Error("INVALID_ADDA_FINANCE_RESPONSE");
    }
    return {
      id: stringValue(row.id) as string,
      account_entry_id: stringValue(row.account_entry_id) as string,
      event_type: eventType,
      payment_date: stringValue(row.payment_date) as string,
      amount: numberValue(row.amount),
      payment_method: stringValue(row.payment_method, true),
      reference_no: stringValue(row.reference_no, true),
      remarks: stringValue(row.remarks, true),
      reversal_reason: stringValue(row.reversal_reason, true),
      reverses_settlement_id: stringValue(row.reverses_settlement_id, true),
      created_at: stringValue(row.created_at) as string,
      entry_kind: entryKind,
      cashbook_entry_type: cashbookType,
      cashbook_reference_type: stringValue(row.cashbook_reference_type, true),
      cashbook_reference_id: stringValue(row.cashbook_reference_id, true),
    };
  });
}

export async function listAddaEmployees(addaId: string): Promise<AddaAccountEmployee[]> {
  const rows = asRows(await rpc("get_employees", { p_adda_id: addaId }));
  return rows.map((row) => ({
    id: stringValue(row.id) as string,
    employee_name: stringValue(row.employee_name) as string,
  }));
}

export async function postAddaExpense(payload: AddaExpensePayload) {
  return stringValue(await rpc("post_adda_expense", {
    p_adda_id: payload.addaId,
    p_expense_date: payload.expenseDate,
    p_category_id: payload.categoryId,
    p_amount: payload.amount,
    p_request_id: payload.requestId,
    p_paid_amount: payload.paidAmount,
    p_payment_method: payload.paymentMethod,
    p_employee_id: payload.employeeId,
    p_reference_no: payload.referenceNo,
    p_description: payload.description,
    p_remarks: payload.remarks,
  })) as string;
}

export async function postAddaOtherIncome(payload: AddaOtherIncomePayload) {
  return stringValue(await rpc("post_adda_other_income", {
    p_adda_id: payload.addaId,
    p_income_date: payload.incomeDate,
    p_amount: payload.amount,
    p_request_id: payload.requestId,
    p_received_amount: payload.receivedAmount,
    p_payment_method: payload.paymentMethod,
    p_reference_no: payload.referenceNo,
    p_description: payload.description,
    p_remarks: payload.remarks,
  })) as string;
}

export async function settleAddaAccountEntry(payload: AddaSettlementPayload) {
  return stringValue(await rpc("settle_adda_account_entry", {
    p_adda_id: payload.addaId,
    p_account_entry_id: payload.accountEntryId,
    p_payment_date: payload.paymentDate,
    p_amount: payload.amount,
    p_payment_method: payload.paymentMethod,
    p_request_id: payload.requestId,
    p_reference_no: payload.referenceNo,
    p_remarks: payload.remarks,
  })) as string;
}

export async function reverseAddaFinanceSettlement(input: {
  addaId: string; settlementId: string; reversalDate: string; reason: string; requestId: string;
}) {
  return stringValue(await rpc("reverse_adda_finance_settlement", {
    p_adda_id: input.addaId,
    p_settlement_id: input.settlementId,
    p_reversal_date: input.reversalDate,
    p_reason: input.reason,
    p_request_id: input.requestId,
  })) as string;
}

export async function reverseAddaFinanceEntry(input: {
  addaId: string; accountEntryId: string; reversalDate: string; reason: string; requestId: string;
}) {
  return stringValue(await rpc("reverse_adda_finance_entry", {
    p_adda_id: input.addaId,
    p_account_entry_id: input.accountEntryId,
    p_reversal_date: input.reversalDate,
    p_reason: input.reason,
    p_request_id: input.requestId,
  })) as string;
}

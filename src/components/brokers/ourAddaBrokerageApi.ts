import { supabase } from "@/lib/supabase/client";
import { getParchiVehicleSettlementTotals } from "@/lib/parchi/vehicleSettlement";

export type LoadingContext = {
  loadingId: number;
  loadingNo: string | null;
  loadingDate: string | null;
  route: string | null;
  vehicleNo: string | null;
  ownerName: string | null;
  vehicleContextStatus: "recorded" | "not_recorded" | "unverified";
  driverName: string | null;
};

export type VehiclePaymentHistory = {
  eventType: "payment" | "saved_advance";
  paymentDate: string | null;
  amount: number;
  paymentMethod: string | null;
  referenceNo: string | null;
  dateStatus: "recorded" | "not_recorded";
};

export type OurAddaBrokerageRow = {
  bookingId: string;
  bookingNo: string | null;
  bookingDate: string | null;
  accountDate: string | null;
  bookingRoute: string | null;
  loadingSource: string | null;
  externalBrokerId: string | null;
  externalBrokerName: string | null;
  partyFreight: number | null;
  grossVehicleKiraya: number | null;
  savedExternalBrokerage: number | null;
  overweightCharges: number | null;
  loloCharges: number | null;
  detainCharges: number | null;
  netVehicleEntitlement: number | null;
  vehicleNo: string | null;
  vehicleOwnerName: string | null;
  vehicleContextCount: number;
  vehicleContextStatus: string;
  vehicleAdvance: number;
  vehicleLaterPaid: number;
  vehicleTotalPaid: number;
  vehicleParchiWithheld: number;
  vehicleEntitlementSettled: number;
  vehicleOutstanding: number | null;
  vehiclePaymentStatus: string;
  vehiclePaymentHistory: VehiclePaymentHistory[];
  linkedLoadingCount: number;
  linkedLoadings: LoadingContext[];
  ourAddaMargin: number | null;
  freightReceiptsBasis: number | null;
  marginRealized: number | null;
  marginPending: number | null;
  marginRealizationStatus: string;
  marginIsReversed: boolean;
  freightSettlementBasis: string | null;
  externalBrokerageSourceStatus: string;
  bookingCreatedAt: string | null;
};

export type LoadingBrokerageAccount = {
  accrualId: string;
  bookingId: string;
  bookingNo: string | null;
  brokerId: string;
  brokerName: string;
  commissionAmount: number;
  outstandingAmount: number;
  isReversed: boolean;
  sourceRevision: number;
  createdAt: string | null;
  paymentCount: number;
};

export type LoadingBrokerageEvent = {
  eventId: string;
  eventKind: "payment" | "payment_reversal" | "accrual_reversal";
  amount: number;
  eventDate: string;
  paymentMethod: string | null;
  referenceNo: string | null;
  reason: string | null;
  reversesEventId: string | null;
  createdAt: string | null;
};

export type OurAddaBrokeragePage = { rows: OurAddaBrokerageRow[]; totalCount: number };
type RpcRow = Record<string, unknown>;

function asRows(value: unknown): RpcRow[] {
  if (!Array.isArray(value)) throw new Error("INVALID_BROKER_LOADING_ACCOUNT_RESPONSE");
  return value as RpcRow[];
}

function nullableText(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") throw new Error("INVALID_BROKER_LOADING_ACCOUNT_RESPONSE");
  return value;
}

function nullableNumber(value: unknown): number | null {
  if (value == null) return null;
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) throw new Error("INVALID_BROKER_LOADING_ACCOUNT_RESPONSE");
  return parsed;
}

function requiredNumber(value: unknown): number {
  const parsed = nullableNumber(value);
  if (parsed === null) throw new Error("INVALID_BROKER_LOADING_ACCOUNT_RESPONSE");
  return parsed;
}

function jsonRows(value: unknown): RpcRow[] {
  if (Array.isArray(value)) return value as RpcRow[];
  if (typeof value === "string") {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? parsed as RpcRow[] : [];
  }
  return [];
}

function parseLoading(value: RpcRow): LoadingContext {
  const loadingId = requiredNumber(value.loading_id);
  if (!Number.isInteger(loadingId)) throw new Error("INVALID_BROKER_LOADING_ACCOUNT_RESPONSE");
  const status = nullableText(value.vehicle_context_status);
  return {
    loadingId,
    loadingNo: nullableText(value.loading_no),
    loadingDate: nullableText(value.loading_date),
    route: nullableText(value.route),
    vehicleNo: nullableText(value.vehicle_no),
    ownerName: nullableText(value.owner_name),
    vehicleContextStatus: status === "recorded" || status === "unverified" ? status : "not_recorded",
    driverName: nullableText(value.driver_name),
  };
}

function parseVehiclePayment(value: RpcRow): VehiclePaymentHistory {
  const eventType = value.event_type === "saved_advance" ? "saved_advance" : "payment";
  const dateStatus = value.date_status === "recorded" ? "recorded" : "not_recorded";
  return {
    eventType,
    paymentDate: nullableText(value.payment_date),
    amount: requiredNumber(value.amount),
    paymentMethod: nullableText(value.payment_method),
    referenceNo: nullableText(value.reference_no),
    dateStatus,
  };
}

export async function getOurAddaBrokerageHistory(args: {
  addaId: string;
  fromDate: string | null;
  toDate: string | null;
  search: string;
  limit: number;
  offset: number;
}): Promise<OurAddaBrokeragePage> {
  const { data, error } = await supabase.rpc("get_broker_loading_account", {
    p_adda_id: args.addaId,
    p_from_date: args.fromDate,
    p_to_date: args.toDate,
    p_search: args.search.trim() || null,
    p_limit: args.limit,
    p_offset: args.offset,
  } as never);
  if (error) throw error;

  const rawRows = asRows(data);
  const totalCount = rawRows.length > 0 ? requiredNumber(rawRows[0].total_count) : 0;
  const rows = rawRows.filter((row) => typeof row.booking_id === "string").map((row): OurAddaBrokerageRow => {
    if (typeof row.booking_id !== "string" || typeof row.margin_is_reversed !== "boolean") {
      throw new Error("INVALID_BROKER_LOADING_ACCOUNT_RESPONSE");
    }
    return {
      bookingId: row.booking_id,
      bookingNo: nullableText(row.booking_no),
      bookingDate: nullableText(row.booking_date),
      accountDate: nullableText(row.account_date),
      bookingRoute: nullableText(row.booking_route),
      loadingSource: nullableText(row.loading_source),
      externalBrokerId: nullableText(row.external_broker_id),
      externalBrokerName: nullableText(row.external_broker_name),
      partyFreight: nullableNumber(row.party_freight),
      grossVehicleKiraya: nullableNumber(row.gross_vehicle_kiraya),
      savedExternalBrokerage: nullableNumber(row.saved_external_brokerage),
      overweightCharges: nullableNumber(row.overweight_charges),
      loloCharges: nullableNumber(row.lolo_charges),
      detainCharges: nullableNumber(row.detain_charges),
      netVehicleEntitlement: nullableNumber(row.net_vehicle_entitlement),
      vehicleNo: nullableText(row.vehicle_no),
      vehicleOwnerName: nullableText(row.vehicle_owner_name),
      vehicleContextCount: requiredNumber(row.vehicle_context_count),
      vehicleContextStatus: nullableText(row.vehicle_context_status) ?? "unverified",
      vehicleAdvance: requiredNumber(row.vehicle_advance),
      vehicleLaterPaid: requiredNumber(row.vehicle_later_paid),
      vehicleTotalPaid: requiredNumber(row.vehicle_total_paid),
      vehicleParchiWithheld: 0,
      vehicleEntitlementSettled: requiredNumber(row.vehicle_total_paid),
      vehicleOutstanding: nullableNumber(row.vehicle_outstanding),
      vehiclePaymentStatus: nullableText(row.vehicle_payment_status) ?? "unverified",
      vehiclePaymentHistory: jsonRows(row.vehicle_payment_history).map(parseVehiclePayment),
      linkedLoadingCount: requiredNumber(row.linked_loading_count),
      linkedLoadings: jsonRows(row.linked_loadings).map(parseLoading),
      ourAddaMargin: nullableNumber(row.our_adda_margin),
      freightReceiptsBasis: nullableNumber(row.freight_receipts_basis),
      marginRealized: nullableNumber(row.margin_realized),
      marginPending: nullableNumber(row.margin_pending),
      marginRealizationStatus: nullableText(row.margin_realization_status) ?? "unverified",
      marginIsReversed: row.margin_is_reversed,
      freightSettlementBasis: nullableText(row.freight_settlement_basis),
      externalBrokerageSourceStatus: nullableText(row.external_brokerage_source_status) ?? "unverified",
      bookingCreatedAt: nullableText(row.booking_created_at),
    };
  });
  const parchiTotals = await getParchiVehicleSettlementTotals(args.addaId, rows.map((row) => row.bookingId));
  const enrichedRows = rows.map((row) => {
    const withheld = parchiTotals.get(row.bookingId)?.withheldCommission ?? 0;
    const vehicleEntitlementSettled = row.vehicleTotalPaid + withheld;
    const vehicleOutstanding = row.vehicleOutstanding === null
      ? null
      : Math.max(row.vehicleOutstanding - withheld, 0);
    const vehiclePaymentStatus = row.netVehicleEntitlement === null || vehicleOutstanding === null
      ? "unverified"
      : vehicleEntitlementSettled <= 0
        ? "unpaid"
        : vehicleOutstanding <= 0 ? "paid" : "partial";
    return {
      ...row,
      vehicleParchiWithheld: withheld,
      vehicleEntitlementSettled,
      vehicleOutstanding,
      vehiclePaymentStatus,
    };
  });
  return { rows: enrichedRows, totalCount };
}

export async function getLoadingBrokerageAccounts(addaId: string): Promise<LoadingBrokerageAccount[]> {
  const { data, error } = await supabase.rpc("get_loading_brokerage_accounts", { p_adda_id: addaId });
  if (error) throw error;
  return asRows(data).map((row) => ({
    accrualId: String(row.accrual_id),
    bookingId: String(row.booking_id),
    bookingNo: nullableText(row.booking_no),
    brokerId: String(row.broker_id),
    brokerName: nullableText(row.broker_name) ?? "",
    commissionAmount: requiredNumber(row.commission_amount),
    outstandingAmount: requiredNumber(row.outstanding_amount),
    isReversed: row.is_reversed === true,
    sourceRevision: requiredNumber(row.source_revision),
    createdAt: nullableText(row.created_at),
    paymentCount: requiredNumber(row.payment_count),
  }));
}

export async function getLoadingBrokerageEvents(addaId: string, accrualId: string): Promise<LoadingBrokerageEvent[]> {
  const { data, error } = await supabase.rpc("get_loading_brokerage_events", {
    p_adda_id: addaId,
    p_accrual_id: accrualId,
  });
  if (error) throw error;
  return asRows(data).map((row) => ({
    eventId: String(row.event_id),
    eventKind: row.event_kind === "payment_reversal" || row.event_kind === "accrual_reversal"
      ? row.event_kind : "payment",
    amount: requiredNumber(row.amount),
    eventDate: String(row.event_date),
    paymentMethod: nullableText(row.payment_method),
    referenceNo: nullableText(row.reference_no),
    reason: nullableText(row.reason),
    reversesEventId: nullableText(row.reverses_event_id),
    createdAt: nullableText(row.created_at),
  }));
}

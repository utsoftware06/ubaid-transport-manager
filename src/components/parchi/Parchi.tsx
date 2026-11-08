"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { ArrowDownLeft, ArrowUpRight, Clock3, Eye, Plus, Printer, RefreshCw, Search, X } from "lucide-react";
import { isUserRole, USER_ROLES, type UserRole } from "@/config/navigation";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import { listOtherAddas } from "@/components/other-addas/api";
import type { OtherAdda } from "@/components/other-addas/types";
import { openParchiPrint, type ParchiPrintBrand } from "@/components/parchi/ParchiPrint";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import {
  analyzeParchiDeadlines,
  getAsiaKarachiToday,
  summarizeParchiDeadlines,
  type ParchiDeadline,
} from "@/lib/parchi/dueDates";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { resolveAddaLogoDisplayUrl } from "@/lib/storage/addaLogo";

type Direction = "received" | "issued";
type EventKind = "document_created" | "created" | "funding" | "settlement" | "recovery" | "reversal" | "amendment" | "cancellation" | "recourse";
type FundingStatus = "Unfunded" | "Partially Funded" | "Fully Funded" | "Cancelled";
type Profile = { role: UserRole; addaId: string | null };
type AddaOption = { id: string; name: string };
type BrokerOption = { id: string; broker_name: string | null };
type BookingOption = { id: string; booking_no: string | null; vehicle_id: string | null };
type LoadingOption = { id: number; loading_no: string | null; booking_id?: string | null; vehicle_id?: string | null };
type PartyOption = { id: string; name: string | null };
type ParchiHeader = {
  id: string;
  external_reference_no: string | null;
  remarks: string | null;
  vehicle_id: string | null;
  booking_id: string | null;
  movement_group_id: string | null;
  voucher_id: number | string | null;
};
type SavedReference = { labelKey: string; value: string };
type PrintHeader = { address: string | null; phone: string | null; logo_url: string | null; show_logo_on_print: boolean | null };
type VehicleReference = { id: string; vehicle_no: string | null };
type BiltyReference = { id: string; booking_no: string | null };
type GroupReference = { id: string; outbound: { booking_no: string | null } | null };
type VoucherReference = { id: number | string; expense_no: string | null };
type LoadingReference = { id: number | string; loading_no: string | null };
type VehicleSettlementReference = { funding_event_id: string; booking_id: string; loading_id: number | string | null; vehicle_id: string };
type StatementEvent = {
  parchi_id: string;
  parchi_no: string;
  direction: Direction;
  counterparty_type: "broker" | "other_adda" | "party";
  counterparty_id: string;
  counterparty_name: string | null;
  document_date: string;
  document_amount: number | string;
  funding_due_date: string | null;
  settlement_due_date: string | null;
  net_funded: number | string;
  funding_status: FundingStatus;
  net_settled: number | string;
  funded_outstanding: number | string;
  settlement_status: string;
  event_id: string | null;
  event_kind: EventKind | null;
  event_date: string | null;
  event_amount: number | string | null;
  payment_method: string | null;
  reference_no: string | null;
  reason: string | null;
  reverses_event_id: string | null;
  event_created_at: string | null;
  commission_withheld?: number | string | null;
  actual_cash_amount?: number | string | null;
  funding_route?: "direct_to_vehicle" | "through_adda" | null;
  vehicle_settlement_booking_no?: string | null;
  vehicle_settlement_loading_no?: string | null;
  vehicle_settlement_vehicle_no?: string | null;
  issued_mode?: "standard" | "freight_financing";
  primary_payer_type?: "party" | "other_adda" | null;
  primary_payer_id?: string | null;
  primary_payer_name?: string | null;
  vehicle_id?: string | null;
  vehicle_no?: string | null;
  responsible_party_id?: string | null;
  responsible_person_name?: string | null;
  responsible_phone?: string | null;
  booking_id?: string | null;
  loading_id?: number | string | null;
  net_commission_withheld?: number | string | null;
  net_actual_funding_cash?: number | string | null;
  event_commission_withheld?: number | string | null;
  event_actual_cash_amount?: number | string | null;
  event_payer_type?: string | null;
  event_payer_id?: string | null;
  event_payer_name?: string | null;
  recourse_target?: string | null;
  external_reference_no?: string | null;
  linked_remarks?: string | null;
};
type ParchiSummary = Omit<StatementEvent, "event_id" | "event_kind" | "event_date" | "event_amount" | "payment_method" | "reference_no" | "reason" | "reverses_event_id" | "event_created_at" | "commission_withheld" | "actual_cash_amount" | "funding_route" | "vehicle_settlement_booking_no" | "vehicle_settlement_loading_no" | "vehicle_settlement_vehicle_no"> & {
  booking_id: string | null;
  events: StatementEvent[];
  external_reference_no: string | null;
  remarks: string | null;
  references: SavedReference[];
  commission_withheld: number | null;
  actual_cash_amount: number | null;
  issued_mode: "standard" | "freight_financing";
  primary_payer_type: "party" | "other_adda" | null;
  primary_payer_id: string | null;
  primary_payer_name: string | null;
  vehicle_no: string | null;
  responsible_party_id: string | null;
  responsible_person_name: string | null;
  responsible_phone: string | null;
  loading_id: number | string | null;
  recourse_events: StatementEvent[];
};
type ModalKind = "create" | "funding" | "settlement" | "amend" | "cancel" | "reverse" | "recourse";
type ParchiModal = {
  kind: ModalKind;
  parchi?: ParchiSummary;
  originalEvent?: StatementEvent;
  direction?: Direction;
  counterpartyId?: string;
  documentDate?: string;
  documentAmount?: string;
  fundingDueDate?: string;
  settlementDueDate?: string;
  eventDate?: string;
  amount?: string;
  paymentMethod?: string;
  referenceNo?: string;
  reason?: string;
  externalReferenceNo?: string;
  remarks?: string;
  bookingId?: string;
  vehicleId?: string;
  withheldCommission?: string;
  fundingRoute?: "direct_to_vehicle" | "through_adda" | "";
  settleVehicle?: boolean;
  loadingId?: string;
  issuedMode?: "standard" | "freight_financing";
  primaryPayerType?: "party" | "other_adda";
  primaryPayerId?: string;
  vehicleNo?: string;
  responsiblePartyId?: string;
  responsiblePersonName?: string;
  responsiblePhone?: string;
  recoveryPayerType?: "primary_payer" | "secondary_person";
  recourseTarget?: "primary_payer" | "secondary_person";
  requestId: string;
  uncertain: boolean;
};

const control = "w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-sm text-slate-950 shadow-sm outline-none focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100 disabled:bg-slate-100";
const labelClass = "mb-1 block text-xs font-bold uppercase tracking-wide text-slate-600";
const buttonPrimary = "inline-flex items-center justify-center gap-2 rounded-lg bg-emerald-700 px-4 py-2.5 text-sm font-bold text-white shadow-sm hover:bg-emerald-800 focus:outline-none focus:ring-2 focus:ring-emerald-300 disabled:cursor-not-allowed disabled:opacity-50";
const buttonSecondary = "inline-flex items-center justify-center gap-2 rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-bold text-slate-700 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-200 disabled:cursor-not-allowed disabled:opacity-50";
const paymentMethods = ["Cash", "Bank", "Cheque", "Online Transfer", "Account"] as const;

function localDate() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}
function money(value: number | string | null | undefined) {
  const amount = Number(value ?? 0);
  return `₨ ${Number.isFinite(amount) ? amount.toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "0.00"}`;
}
function amountInputIsValid(value: string) {
  return /^\d{1,16}(?:\.\d{1,2})?$/.test(value.trim()) && Number(value) > 0 && Number.isFinite(Number(value));
}
function amountInputIsNonNegative(value: string) {
  return /^\d{1,16}(?:\.\d{1,2})?$/.test(value.trim()) && Number(value) >= 0 && Number.isFinite(Number(value));
}
function makeRequestId() {
  return window.crypto.randomUUID();
}
function chunks<T>(values: T[], size = 400): T[][] {
  const output: T[][] = [];
  for (let index = 0; index < values.length; index += size) output.push(values.slice(index, index + size));
  return output;
}
async function loadAllParchiStatementRows(addaId: string): Promise<StatementEvent[]> {
  const pageSize = 1000;
  const rows: StatementEvent[] = [];
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase.rpc("get_parchi_statement", {
      p_adda_id: addaId,
      p_counterparty_type: null,
      p_counterparty_id: null,
    }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    const page = (data ?? []) as unknown as StatementEvent[];
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}
async function loadAllIssuedFinanceRows(addaId: string): Promise<StatementEvent[]> {
  const pageSize = 1000;
  const rows: StatementEvent[] = [];
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase.rpc("get_issued_freight_parchi_statement", {
      p_adda_id: addaId, p_account_type: null, p_account_id: null,
    }).range(offset, offset + pageSize - 1);
    if (error) throw error;
    const page = ((data ?? []) as unknown as StatementEvent[]).map((row) => ({
      ...row,
      commission_withheld: row.event_commission_withheld,
      actual_cash_amount: row.event_actual_cash_amount,
    }));
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}
function labelStatus(value: string, t: (key: string) => string) {
  const keys: Record<string, string> = {
    Unfunded: "parchi.statuses.unfunded",
    "Partially Funded": "parchi.statuses.partiallyFunded",
    "Fully Funded": "parchi.statuses.fullyFunded",
    Cancelled: "parchi.statuses.cancelled",
    "Not Funded": "parchi.statuses.notFunded",
    Unpaid: "parchi.statuses.unpaid",
    "Partially Settled": "parchi.statuses.partiallySettled",
    Settled: "parchi.statuses.settled",
  };
  return t(keys[value] ?? value);
}
function labelEvent(value: EventKind | null, t: (key: string) => string) {
  if (!value) return "—";
  const keys: Record<EventKind, string> = {
    document_created: "parchi.events.documentCreated",
    created: "parchi.events.documentCreated",
    funding: "parchi.events.funding",
    settlement: "parchi.events.settlement",
    recovery: "parchi.events.settlement",
    reversal: "parchi.events.reversal",
    amendment: "parchi.events.amendment",
    cancellation: "parchi.events.cancellation",
    recourse: "parchi.events.recourse",
  };
  return t(keys[value]);
}
function roleCanManage(role: UserRole | undefined) {
  return role === USER_ROLES.addaAdmin || role === USER_ROLES.superAdmin;
}
function errorMessage(error: unknown) {
  if (error && typeof error === "object" && "message" in error && typeof error.message === "string") return error.message;
  return "Parchi action failed.";
}
function groupStatement(
  rows: StatementEvent[],
  headers: Map<string, ParchiHeader>,
  references: Map<string, SavedReference[]>,
  receivedVehicleNumbers: Map<string, string | null>,
): ParchiSummary[] {
  const grouped = new Map<string, ParchiSummary>();
  for (const row of rows) {
    if (!row || typeof row.parchi_id !== "string") throw new Error("Invalid Parchi statement response.");
    const current = grouped.get(row.parchi_id);
    if (current) {
      current.events.push(row);
      continue;
    }
    grouped.set(row.parchi_id, {
      parchi_id: row.parchi_id,
      parchi_no: row.parchi_no,
      direction: row.direction,
      counterparty_type: row.counterparty_type,
      counterparty_id: row.counterparty_id,
      counterparty_name: row.counterparty_name,
      document_date: row.document_date,
      document_amount: row.document_amount,
      funding_due_date: row.funding_due_date,
      settlement_due_date: row.settlement_due_date,
      net_funded: row.net_funded,
      funding_status: row.funding_status,
      net_settled: row.net_settled,
      funded_outstanding: row.funded_outstanding,
      settlement_status: row.settlement_status,
      booking_id: headers.get(row.parchi_id)?.booking_id ?? null,
      events: [row],
      external_reference_no: headers.get(row.parchi_id)?.external_reference_no ?? row.external_reference_no ?? null,
      remarks: headers.get(row.parchi_id)?.remarks ?? row.linked_remarks ?? null,
      references: references.get(row.parchi_id) ?? [],
      commission_withheld: 0,
      actual_cash_amount: 0,
      issued_mode: row.issued_mode ?? "standard",
      primary_payer_type: row.primary_payer_type ?? null,
      primary_payer_id: row.primary_payer_id ?? null,
      primary_payer_name: row.primary_payer_name ?? null,
      vehicle_no: row.direction === "received"
        ? receivedVehicleNumbers.get(row.parchi_id) ?? null
        : row.vehicle_no ?? null,
      responsible_party_id: row.responsible_party_id ?? null,
      responsible_person_name: row.responsible_person_name ?? null,
      responsible_phone: row.responsible_phone ?? null,
      loading_id: row.loading_id ?? null,
      recourse_events: [],
    });
  }
  for (const parchi of grouped.values()) {
    if (parchi.issued_mode === "freight_financing") {
      parchi.commission_withheld = Number(parchi.events[0]?.net_commission_withheld ?? 0);
      parchi.actual_cash_amount = Number(parchi.events[0]?.net_actual_funding_cash ?? 0);
      parchi.recourse_events = parchi.events.filter((event) => event.event_kind === "recourse");
      continue;
    }
    if (parchi.direction !== "received") continue;
    const originals = new Map(parchi.events.filter((event) => event.event_id && (event.event_kind === "funding" || event.event_kind === "settlement")).map((event) => [event.event_id!, event]));
    let commissionKnown = true;
    let actualCashKnown = true;
    for (const event of parchi.events) {
      if (event.event_kind === "funding") {
        if (event.commission_withheld === null || event.commission_withheld === undefined) commissionKnown = false;
        else parchi.commission_withheld = Number(parchi.commission_withheld ?? 0) + Number(event.commission_withheld);
        if (event.actual_cash_amount === null || event.actual_cash_amount === undefined) actualCashKnown = false;
        else parchi.actual_cash_amount = Number(parchi.actual_cash_amount ?? 0) + Number(event.actual_cash_amount);
      } else if (event.event_kind === "reversal" && event.reverses_event_id) {
        const original = originals.get(event.reverses_event_id);
        if (original?.event_kind === "funding") {
          if (original.commission_withheld === null || original.commission_withheld === undefined) commissionKnown = false;
          else parchi.commission_withheld = Number(parchi.commission_withheld ?? 0) - Number(original.commission_withheld);
          if (original.actual_cash_amount === null || original.actual_cash_amount === undefined) actualCashKnown = false;
          else parchi.actual_cash_amount = Number(parchi.actual_cash_amount ?? 0) - Number(original.actual_cash_amount);
        }
      }
    }
    parchi.commission_withheld = commissionKnown ? Math.max(0, Number(parchi.commission_withheld ?? 0)) : null;
    parchi.actual_cash_amount = actualCashKnown ? Math.max(0, Number(parchi.actual_cash_amount ?? 0)) : null;
  }
  return [...grouped.values()].sort((a, b) => b.document_date.localeCompare(a.document_date) || b.parchi_no.localeCompare(a.parchi_no));
}

export default function Parchi() {
  const { t, dir, language } = useLanguage();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const [rows, setRows] = useState<ParchiSummary[] | null>(null);
  const [brokers, setBrokers] = useState<BrokerOption[]>([]);
  const [parties, setParties] = useState<PartyOption[]>([]);
  const [bookings, setBookings] = useState<BookingOption[]>([]);
  const [financeLoadings, setFinanceLoadings] = useState<LoadingOption[]>([]);
  const [vehicles, setVehicles] = useState<VehicleReference[]>([]);
  const [loadingOptionsState, setLoadingOptionsState] = useState<{ bookingId: string; options: LoadingOption[]; error: boolean } | null>(null);
  const [otherAddas, setOtherAddas] = useState<OtherAdda[]>([]);
  const [printBrand, setPrintBrand] = useState<ParchiPrintBrand>({ addaName: null, logoUrl: null, showLogo: false, address: null, phone: null });
  const [contextBusy, setContextBusy] = useState(true);
  const [dataBusy, setDataBusy] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [actionBusy, setActionBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [search, setSearch] = useState("");
  const [directionFilter, setDirectionFilter] = useState<"all" | Direction>("all");
  const [fundingFilter, setFundingFilter] = useState("all");
  const [deadlineFilter, setDeadlineFilter] = useState<"all" | "due_today" | "overdue">("all");
  const [businessToday, setBusinessToday] = useState("");
  const [modal, setModal] = useState<ParchiModal | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [refreshToken, setRefreshToken] = useState(0);
  const actionLock = useRef(false);
  const contextAddaId = profile?.role === USER_ROLES.superAdmin ? selectedAddaId : profile?.addaId ?? "";
  const modulePrint = useModuleTransportPrint("parchi", contextAddaId || null, language === "ur" ? "ur" : "en");
  const canManage = roleCanManage(profile?.role);
  const selectedParchi = useMemo(() => rows?.find((row) => row.parchi_id === selectedId) ?? null, [rows, selectedId]);

  useEffect(() => {
    const refreshBusinessDate = () => setBusinessToday(getAsiaKarachiToday());
    refreshBusinessDate();
    const interval = window.setInterval(refreshBusinessDate, 60_000);
    return () => window.clearInterval(interval);
  }, []);

  function printParchiLegacy(parchi: ParchiSummary) {
    openParchiPrint({
      parchi: {
        ...parchi,
        commission_withheld: parchi.commission_withheld,
        actual_cash_amount: parchi.actual_cash_amount,
        events: parchi.events.map((event) => ({
          ...event,
          vehicle_settlement_reference: [
            event.vehicle_settlement_booking_no ? `${t("common.bookingNo")}: ${event.vehicle_settlement_booking_no}` : null,
            event.vehicle_settlement_loading_no ? `${t("common.loadingNo")}: ${event.vehicle_settlement_loading_no}` : null,
            event.vehicle_settlement_vehicle_no ? `${t("common.vehicle")}: ${event.vehicle_settlement_vehicle_no}` : null,
          ].filter(Boolean).join(" · ") || null,
        })),
        references: parchi.references.map((reference) => ({ label: t(reference.labelKey), value: reference.value })),
      },
      brand: printBrand,
      t,
      direction: dir,
      language,
    });
  }

  function printParchi(parchi: ParchiSummary) {
    const eventKeys: Record<string, string> = {
      document_created: "parchi.events.documentCreated", created: "parchi.events.documentCreated", funding: "parchi.events.funding", settlement: "parchi.events.settlement", recovery: "parchi.events.settlement",
      reversal: "parchi.events.reversal", amendment: "parchi.events.amendment", cancellation: "parchi.events.cancellation", recourse: "parchi.events.recourse",
    };
    const statusKeys: Record<string, string> = {
      Unfunded: "parchi.statuses.unfunded", "Partially Funded": "parchi.statuses.partiallyFunded", "Fully Funded": "parchi.statuses.fullyFunded", Cancelled: "parchi.statuses.cancelled",
      Unpaid: "parchi.statuses.unpaid", "Partially Settled": "parchi.statuses.partiallySettled", Settled: "parchi.statuses.settled",
    };
    const isFreightFinance = parchi.issued_mode === "freight_financing";
    const moneyRows = parchi.events.filter((event) => event.event_kind === "funding" || event.event_kind === "settlement" || event.event_kind === "recovery" || event.event_kind === "reversal" || (isFreightFinance && event.event_kind === "recourse"));
    const outstandingLabel = parchi.direction === "received" ? "parchi.print.brokerPayable" : isFreightFinance ? "parchi.print.issuedFinanceReceivable" : "parchi.print.otherAddaReceivable";
    const title = isFreightFinance ? "parchi.issuedFinance" : parchi.direction === "received" ? "parchi.received" : "parchi.issued";
    const presentation: ModulePrintPresentation = {
      documentType: "parchi",
      title: printLabel(title),
      documentNo: printValue(parchi.parchi_no),
      documentDate: printValue(parchi.document_date),
      subtitle: printLabel("parchi.print.financialSummary"),
      fields: [
        { label: printLabel(isFreightFinance ? "parchi.primaryPayer" : parchi.direction === "received" ? "parchi.broker" : "parchi.otherAdda"), value: printValue(parchi.counterparty_name) },
        ...(isFreightFinance ? [
          { label: printLabel("parchi.responsiblePerson"), value: printValue(parchi.responsible_person_name) },
          { label: printLabel("common.vehicle"), value: printValue(parchi.vehicle_no) },
        ] : []),
        { label: printLabel("parchi.documentAmount"), value: money(parchi.document_amount) },
        ...(parchi.direction === "received" || isFreightFinance ? [
          { label: printLabel(isFreightFinance ? "parchi.upfrontCommission" : "parchi.print.commissionWithheld"), value: parchi.commission_withheld === null ? printLabel("parchi.print.notRecorded") : money(parchi.commission_withheld) },
          { label: printLabel(isFreightFinance ? "parchi.actualCashDisbursed" : "parchi.print.actualCash"), value: parchi.actual_cash_amount === null ? printLabel("parchi.print.notRecorded") : money(parchi.actual_cash_amount) },
        ] : []),
        { label: printLabel("parchi.fundingDueDate"), value: printValue(parchi.funding_due_date) },
        { label: printLabel("parchi.settlementDueDate"), value: printValue(parchi.settlement_due_date) },
        { label: printLabel("parchi.fundingStatus"), value: printLabel(statusKeys[parchi.funding_status] ?? "parchi.statuses.unfunded") },
        { label: printLabel("parchi.settlementStatus"), value: printLabel(statusKeys[parchi.settlement_status] ?? "parchi.statuses.unpaid") },
        { label: printLabel("parchi.externalReference"), value: printValue(parchi.external_reference_no) },
        ...parchi.references.map((reference) => ({ label: printLabel(reference.labelKey), value: printValue(reference.value) })),
      ],
      totals: [
        { label: printLabel("parchi.print.netFunded"), value: money(parchi.net_funded) },
        { label: printLabel(parchi.direction === "received" ? "parchi.print.netRepayment" : "parchi.print.netRecovery"), value: money(parchi.net_settled) },
        { label: printLabel(outstandingLabel), value: money(parchi.funded_outstanding) },
      ],
      tables: [{
        title: printLabel("parchi.print.moneyHistory"),
        columns: ["parchi.eventDate", "parchi.event", "parchi.amount", ...(isFreightFinance ? ["parchi.print.upfrontCommission", "parchi.print.actualCashDisbursed", "parchi.recoveryPayer"] : parchi.direction === "received" ? ["parchi.print.commissionWithheld", "parchi.print.actualCash", "parchi.print.fundingRoute", "parchi.vehicleSettlement"] : []), "parchi.paymentMethod", "parchi.referenceNo", "parchi.print.status"].map(printLabel),
        rows: moneyRows.map((event) => {
          const original = event.reverses_event_id ? parchi.events.find((candidate) => candidate.event_id === event.reverses_event_id) : undefined;
          const routeSource = event.event_kind === "reversal" ? original : event;
          const commissionSource = event.event_kind === "reversal" ? original : event;
          const commission = commissionSource?.commission_withheld == null ? null : Number(commissionSource.commission_withheld) * (event.event_kind === "reversal" ? -1 : 1);
          const actualCash = commissionSource?.actual_cash_amount == null ? null : Number(commissionSource.actual_cash_amount) * (event.event_kind === "reversal" ? -1 : 1);
          const settlementSource = event.event_kind === "reversal" ? original : event;
          const fundingRelated = event.event_kind === "funding" || original?.event_kind === "funding";
          const settlementReference = settlementSource ? [
            settlementSource.vehicle_settlement_booking_no ? `${t("common.bookingNo")}: ${settlementSource.vehicle_settlement_booking_no}` : null,
            settlementSource.vehicle_settlement_loading_no ? `${t("common.loadingNo")}: ${settlementSource.vehicle_settlement_loading_no}` : null,
            settlementSource.vehicle_settlement_vehicle_no ? `${t("common.vehicle")}: ${settlementSource.vehicle_settlement_vehicle_no}` : null,
          ].filter(Boolean).join(" · ") : "";
          return [
            printValue(event.event_date), printLabel(event.event_kind ? (eventKeys[event.event_kind] ?? "parchi.event") : "parchi.event"), printValue(money(event.event_kind === "reversal" ? -Number(event.event_amount ?? 0) : event.event_amount)),
            ...(isFreightFinance ? [
              printValue(event.event_kind === "funding" ? money(event.commission_withheld) : event.event_kind === "reversal" && original?.event_kind === "funding" ? money(-Number(original.commission_withheld ?? 0)) : "—"),
              printValue(event.event_kind === "funding" || event.event_kind === "recovery" ? money(event.actual_cash_amount ?? event.event_amount) : event.event_kind === "reversal" ? money(-Number(original?.actual_cash_amount ?? original?.event_amount ?? 0)) : "—"),
              printValue(event.event_payer_name),
            ] : parchi.direction === "received" ? [
              printValue(!fundingRelated ? "—" : commission === null ? printLabel("parchi.print.notRecorded") : money(commission)),
              printValue(!fundingRelated ? "—" : actualCash === null ? printLabel("parchi.print.notRecorded") : money(actualCash)),
              !fundingRelated ? "—" : printLabel(routeSource?.funding_route === "direct_to_vehicle" ? "parchi.print.fundingRouteDirect" : routeSource?.funding_route === "through_adda" ? "parchi.print.fundingRouteThroughAdda" : "parchi.print.notRecorded"),
              printValue(settlementReference || "—"),
            ] : []),
            printValue(event.payment_method), printValue(event.reference_no), event.reverses_event_id ? printLabel("parchi.print.reversed") : "—",
          ];
        }),
      }],
      remarks: printValue(parchi.remarks),
    };
    modulePrint.openPresentation(presentation, () => printParchiLegacy(parchi), contextAddaId || null);
  }

  function printParchiMoneyEvent(parchi: ParchiSummary, event: StatementEvent) {
    if (!event.event_id || !event.event_kind || event.event_amount === null) return;
    const eventTitleKey: Record<string, string> = {
      funding: parchi.direction === "received" ? "parchi.print.fundingReceived" : "parchi.print.fundingDisbursed",
      settlement: parchi.direction === "received" ? "parchi.print.repayment" : "parchi.print.recovery",
      recovery: "parchi.print.recovery",
      reversal: "parchi.events.reversal",
    };
    const eventTitle = eventTitleKey[event.event_kind];
    if (!eventTitle) return;
    const commissionSource = event.event_kind === "reversal" && event.reverses_event_id
      ? parchi.events.find((candidate) => candidate.event_id === event.reverses_event_id)
      : event;
    const commissionSign = event.event_kind === "reversal" ? -1 : 1;
    const presentation: ModulePrintPresentation = {
      documentType: "parchi",
      title: printLabel(eventTitle),
      documentNo: printValue(event.reference_no || `${parchi.parchi_no} · ${event.event_id}`),
      documentDate: printValue(event.event_date),
      subtitle: printLabel("parchi.print.moneyHistory"),
      fields: [
        { label: printLabel("parchi.document"), value: printValue(parchi.parchi_no) },
        { label: printLabel(parchi.issued_mode === "freight_financing" ? "parchi.primaryPayer" : parchi.direction === "received" ? "parchi.broker" : "parchi.otherAdda"), value: printValue(parchi.counterparty_name) },
        { label: printLabel("parchi.event"), value: printLabel(eventTitle) },
        { label: printLabel("parchi.eventDate"), value: printValue(event.event_date) },
        { label: printLabel("parchi.paymentMethod"), value: printValue(event.payment_method) },
        { label: printLabel("parchi.referenceNo"), value: printValue(event.reference_no) },
        ...(parchi.issued_mode === "freight_financing" ? [
          { label: printLabel("parchi.responsiblePerson"), value: printValue(parchi.responsible_person_name) },
          { label: printLabel("common.vehicle"), value: printValue(parchi.vehicle_no) },
        ] : []),
        ...((parchi.direction === "received" || parchi.issued_mode === "freight_financing") && commissionSource && (commissionSource.event_kind === "funding" || commissionSource.event_kind === "recovery") ? [
          { label: printLabel(parchi.issued_mode === "freight_financing" ? "parchi.upfrontCommission" : "parchi.print.commissionWithheld"), value: commissionSource.commission_withheld == null ? printLabel("parchi.print.notRecorded") : money(commissionSign * Number(commissionSource.commission_withheld)) },
          { label: printLabel(parchi.issued_mode === "freight_financing" ? "parchi.actualCashDisbursed" : "parchi.print.actualCash"), value: commissionSource.actual_cash_amount == null ? printLabel("parchi.print.notRecorded") : money(commissionSign * Number(commissionSource.actual_cash_amount)) },
          ...(parchi.direction === "received" ? [{ label: printLabel("parchi.print.fundingRoute"), value: printLabel(commissionSource.funding_route === "direct_to_vehicle" ? "parchi.print.fundingRouteDirect" : commissionSource.funding_route === "through_adda" ? "parchi.print.fundingRouteThroughAdda" : "parchi.print.notRecorded") }] : []),
        ] : []),
        ...(commissionSource?.vehicle_settlement_booking_no || commissionSource?.vehicle_settlement_loading_no || commissionSource?.vehicle_settlement_vehicle_no ? [{
          label: printLabel("parchi.vehicleSettlement"),
          value: printValue([
            commissionSource.vehicle_settlement_booking_no ? `${t("common.bookingNo")}: ${commissionSource.vehicle_settlement_booking_no}` : null,
            commissionSource.vehicle_settlement_loading_no ? `${t("common.loadingNo")}: ${commissionSource.vehicle_settlement_loading_no}` : null,
            commissionSource.vehicle_settlement_vehicle_no ? `${t("common.vehicle")}: ${commissionSource.vehicle_settlement_vehicle_no}` : null,
          ].filter(Boolean).join(" · ")),
        }] : []),
        ...(event.reverses_event_id ? [{ label: printLabel("parchi.print.reversed"), value: printValue(event.reverses_event_id) }] : []),
        ...(event.reason ? [{ label: printLabel("parchi.reason"), value: printValue(event.reason) }] : []),
      ],
      totals: [{ label: printLabel("parchi.amount"), value: printValue(money(event.event_amount)) }],
    };
    modulePrint.openPresentation(presentation, () => printParchiLegacy(parchi), contextAddaId || null);
  }

  useEffect(() => {
    let active = true;
    async function loadContext() {
      setContextBusy(true);
      setLoadError("");
      setRows(null);
      try {
        const auth = await supabase.auth.getUser();
        if (auth.error) throw auth.error;
        if (!auth.data.user) throw new Error(t("parchi.accessError"));
        const { data: row, error } = await supabase.from("profiles").select("role,adda_id,is_active").eq("id", auth.data.user.id).maybeSingle();
        if (error) throw error;
        if (!row || row.is_active !== true || !isUserRole(row.role)) throw new Error(t("parchi.accessError"));
        if (row.role !== USER_ROLES.superAdmin && !row.adda_id) throw new Error(t("parchi.accessError"));
        let options: AddaOption[] = [];
        if (row.role === USER_ROLES.superAdmin) {
          const result = await supabase.from("addas").select("id,name").order("name");
          if (result.error) throw result.error;
          options = (result.data ?? []).map((adda) => ({ id: adda.id, name: adda.name }));
          const preferred = row.adda_id ?? "";
          setSelectedAddaId(options.some((option) => option.id === preferred) ? preferred : options[0]?.id ?? "");
        }
        if (!active) return;
        setAddas(options);
        setProfile({ role: row.role, addaId: row.adda_id });
      } catch (error) {
        if (active) {
          console.error("Parchi access context failed", error);
          setLoadError(errorMessage(error));
        }
      } finally {
        if (active) setContextBusy(false);
      }
    }
    void loadContext();
    return () => { active = false; };
  }, [t]);

  useEffect(() => {
    if (!profile || !contextAddaId) return;
    let active = true;
    async function loadData() {
      setDataBusy(true);
      setLoadError("");
      setRows(null);
      setBookings([]);
      setVehicles([]);
      setBrokers([]);
      setOtherAddas([]);
      setPrintBrand({ addaName: null, logoUrl: null, showLogo: false, address: null, phone: null });
      try {
        const [rawStatementRows, financeStatementRows, headerResult, brokerResult, otherAddaResult, brandResult, addaResult, bookingResult, vehicleOptionResult, partyResult] = await Promise.all([
          loadAllParchiStatementRows(contextAddaId),
          loadAllIssuedFinanceRows(contextAddaId),
          supabase.from("parchis").select("id,external_reference_no,remarks,vehicle_id,booking_id,movement_group_id,voucher_id").eq("adda_id", contextAddaId),
          supabase.rpc("get_brokers_for_adda", { p_adda_id: contextAddaId }),
          listOtherAddas({ adda_id: contextAddaId, status: "active", limit: 1000 }),
          supabase.from("company_settings").select("address,phone,logo_url,show_logo_on_print").eq("adda_id", contextAddaId).maybeSingle(),
          supabase.from("addas").select("id,name,address,city,phone").eq("id", contextAddaId).maybeSingle(),
          supabase.from("bookings").select("id,booking_no,vehicle_id").eq("adda_id", contextAddaId).order("booking_no"),
          supabase.from("vehicles").select("id,vehicle_no").eq("adda_id", contextAddaId).order("vehicle_no"),
          supabase.from("parties").select("id,name").eq("adda_id", contextAddaId).eq("is_active", true).order("name"),
        ]);
        const financeLoadingResult = (bookingResult.data ?? []).length
          ? await supabase.from("loadings").select("id,loading_no,booking_id,vehicle_id").in("booking_id", (bookingResult.data ?? []).map((booking) => booking.id)).order("id", { ascending: false })
          : { data: [] as LoadingOption[], error: null };
        if (headerResult.error) throw headerResult.error;
        if (brokerResult.error) throw brokerResult.error;
        if (bookingResult.error) throw bookingResult.error;
        if (vehicleOptionResult.error) throw vehicleOptionResult.error;
        if (partyResult.error) throw partyResult.error;
        if (financeLoadingResult.error) throw financeLoadingResult.error;
        if (!active) return;
        const eventIds = [...new Set(rawStatementRows.map((row) => row.event_id).filter((id): id is string => Boolean(id)))];
        const metadataResults = await Promise.all(chunks(eventIds).map((eventChunk) => supabase.from("parchi_events")
          .select("id,commission_withheld,actual_cash_amount,funding_route").in("id", eventChunk)));
        const metadataError = metadataResults.find((result) => result.error)?.error;
        if (metadataError) throw metadataError;
        if (!active) return;
        const eventMetadata = new Map(metadataResults.flatMap((result) => (result.data ?? []) as unknown as Array<{ id: string; commission_withheld: number | string | null; actual_cash_amount: number | string | null; funding_route: StatementEvent["funding_route"] }>).map((event) => [event.id, event] as const));
        const settlementResults = await Promise.all(chunks(eventIds).map((eventChunk) => supabase.from("parchi_vehicle_settlements")
          .select("funding_event_id,booking_id,loading_id,vehicle_id").in("funding_event_id", eventChunk)));
        const settlementError = settlementResults.find((result) => result.error)?.error;
        if (settlementError) throw settlementError;
        if (!active) return;
        const settlementRows = settlementResults.flatMap((result) => (result.data ?? []) as unknown as VehicleSettlementReference[]);
        const statementRows = [
          ...rawStatementRows.map((row) => ({ ...row, ...(row.event_id ? eventMetadata.get(row.event_id) : {}) })),
          ...financeStatementRows,
        ];
        const headerRows = (headerResult.data ?? []) as ParchiHeader[];
        const financeHeaders = [...new Map(financeStatementRows.map((row) => [row.parchi_id, row])).values()].map((row) => ({
          id: row.parchi_id, external_reference_no: row.external_reference_no ?? null,
          remarks: row.linked_remarks ?? null, vehicle_id: row.vehicle_id ?? null,
          booking_id: row.booking_id ?? null, movement_group_id: null, voucher_id: null,
        }));
        const allHeaderRows: ParchiHeader[] = [...headerRows, ...financeHeaders];
        const headers = new Map(allHeaderRows.map((header) => [header.id, header]));
        const bookingVehicleMap = new Map(((bookingResult.data ?? []) as BookingOption[]).map((booking) => [booking.id, booking.vehicle_id]));
        const bookingIds = [...new Set([...allHeaderRows.map((header) => header.booking_id), ...settlementRows.map((item) => item.booking_id)].filter((id): id is string => Boolean(id)))];
        const groupIds = [...new Set(headerRows.map((header) => header.movement_group_id).filter((id): id is string => Boolean(id)))];
        const voucherIds = [...new Set(headerRows.map((header) => header.voucher_id).filter((id): id is string | number => id !== null).map(String))];
        const loadingIds = [...new Set([...settlementRows.map((item) => item.loading_id), ...financeStatementRows.map((row) => row.loading_id ?? null)].filter((id): id is number | string => id !== null).map(String))];
        const [biltyRefs, groupRefs, voucherRefs, loadingRefs] = await Promise.all([
          bookingIds.length ? supabase.from("bookings").select("id,booking_no").in("id", bookingIds) : Promise.resolve({ data: [] as BiltyReference[], error: null }),
          groupIds.length ? supabase.from("bilty_movement_groups").select("id,outbound:bookings!bilty_movement_groups_outbound_bilty_id_fkey(booking_no)").in("id", groupIds) : Promise.resolve({ data: [] as GroupReference[], error: null }),
          voucherIds.length ? supabase.from("expenses").select("id,expense_no").in("id", voucherIds) : Promise.resolve({ data: [] as VoucherReference[], error: null }),
          loadingIds.length ? supabase.from("loadings").select("id,loading_no").in("id", loadingIds) : Promise.resolve({ data: [] as LoadingReference[], error: null }),
        ]);
        for (const optionalRead of [biltyRefs, groupRefs, voucherRefs, loadingRefs]) {
          if (optionalRead.error) console.warn("Parchi print reference lookup unavailable", optionalRead.error);
        }
        const vehicleMap = new Map(((vehicleOptionResult.data ?? []) as VehicleReference[]).map((item) => [item.id, item.vehicle_no]));
        const receivedVehicleNumbers = new Map(allHeaderRows.map((header) => {
          const linkedVehicleId = header.vehicle_id ?? (header.booking_id ? bookingVehicleMap.get(header.booking_id) ?? null : null);
          return [header.id, linkedVehicleId ? vehicleMap.get(linkedVehicleId) ?? null : null] as const;
        }));
        const biltyMap = new Map(((biltyRefs.data ?? []) as unknown as BiltyReference[]).map((item) => [item.id, item.booking_no]));
        const loadingMap = new Map(((loadingRefs.data ?? []) as unknown as LoadingReference[]).map((item) => [String(item.id), item.loading_no]));
        const settlementDetails = new Map(settlementRows.map((settlement) => [settlement.funding_event_id, {
          vehicle_settlement_booking_no: biltyMap.get(settlement.booking_id) ?? null,
          vehicle_settlement_loading_no: settlement.loading_id === null ? null : loadingMap.get(String(settlement.loading_id)) ?? null,
          vehicle_settlement_vehicle_no: vehicleMap.get(settlement.vehicle_id) ?? null,
        }]));
        const groupMap = new Map(((groupRefs.data ?? []) as unknown as GroupReference[]).map((item) => [item.id, item.outbound?.booking_no ?? null]));
        const voucherMap = new Map(((voucherRefs.data ?? []) as unknown as VoucherReference[]).map((item) => [String(item.id), item.expense_no]));
        const financeReferenceMap = new Map(financeStatementRows.map((row) => [row.parchi_id, row]));
        const references = new Map(allHeaderRows.map((header) => [header.id, [
          ...(header.vehicle_id && vehicleMap.get(header.vehicle_id) ? [{ labelKey: "common.vehicle", value: vehicleMap.get(header.vehicle_id)! }] : []),
          ...(!header.vehicle_id && financeReferenceMap.get(header.id)?.vehicle_no ? [{ labelKey: "common.vehicle", value: financeReferenceMap.get(header.id)!.vehicle_no! }] : []),
          ...(header.booking_id && biltyMap.get(header.booking_id) ? [{ labelKey: "common.bookingNo", value: biltyMap.get(header.booking_id)! }] : []),
          ...(header.booking_id && !biltyMap.get(header.booking_id) ? [{ labelKey: "common.bookingNo", value: header.booking_id }] : []),
          ...(financeReferenceMap.get(header.id)?.loading_id ? [{ labelKey: "common.loadingNo", value: loadingMap.get(String(financeReferenceMap.get(header.id)!.loading_id)) ?? String(financeReferenceMap.get(header.id)!.loading_id) }] : []),
          ...(header.movement_group_id && groupMap.get(header.movement_group_id) ? [{ labelKey: "parchi.print.biltyGroup", value: groupMap.get(header.movement_group_id)! }] : []),
          ...(header.voucher_id !== null && voucherMap.get(String(header.voucher_id)) ? [{ labelKey: "parchi.print.voucher", value: voucherMap.get(String(header.voucher_id))! }] : []),
        ]]));
        setRows(groupStatement(statementRows.map((row) => ({ ...row, ...(row.event_id ? settlementDetails.get(row.event_id) : {}) })), headers, references, receivedVehicleNumbers));
        setBrokers((brokerResult.data ?? []) as BrokerOption[]);
        setParties((partyResult.data ?? []) as PartyOption[]);
        setBookings((bookingResult.data ?? []) as BookingOption[]);
        setFinanceLoadings((financeLoadingResult.data ?? []) as LoadingOption[]);
        setVehicles((vehicleOptionResult.data ?? []) as VehicleReference[]);
        setOtherAddas(otherAddaResult);
        if (brandResult.error) console.warn("Parchi stationery settings unavailable", brandResult.error);
        if (addaResult.error) console.warn("Parchi Adda name unavailable", addaResult.error);
        const brand = brandResult.data as PrintHeader | null;
        const resolvedLogoUrl = await resolveAddaLogoDisplayUrl(contextAddaId, brand?.logo_url);
        if (!active) return;
        setPrintBrand({
          addaName: addaResult.data?.name ?? null,
          logoUrl: resolvedLogoUrl,
          showLogo: brand?.show_logo_on_print === true,
          address: brand?.address ?? addaResult.data?.address ?? null,
          phone: brand?.phone ?? addaResult.data?.phone ?? null,
        });
      } catch (error) {
        if (!active) return;
        console.error("Parchi statement load failed", error);
        setLoadError(errorMessage(error));
        setRows(null);
      } finally {
        if (active) setDataBusy(false);
      }
    }
    void loadData();
    return () => { active = false; };
  }, [profile, contextAddaId, refreshToken]);

  useEffect(() => {
    const bookingId = modal?.kind === "funding" ? modal.parchi?.booking_id : null;
    let active = true;
    if (!bookingId) return () => { active = false; };
    void (async () => {
      try {
        const { data, error } = await supabase.from("loadings").select("id,loading_no").eq("booking_id", bookingId).order("id", { ascending: false });
        if (!active) return;
        if (error) {
          console.error("Parchi linked Loading options failed", error);
          setLoadingOptionsState({ bookingId, options: [], error: true });
          return;
        }
        setLoadingOptionsState({ bookingId, options: (data ?? []) as LoadingOption[], error: false });
      } catch (error) {
        if (!active) return;
        console.error("Parchi linked Loading options failed", error);
        setLoadingOptionsState({ bookingId, options: [], error: true });
      }
    })();
    return () => { active = false; };
  }, [modal?.kind, modal?.parchi?.booking_id]);

  const fundingBookingId = modal?.kind === "funding" ? modal.parchi?.booking_id ?? null : null;
  const currentLoadingOptions = fundingBookingId && loadingOptionsState?.bookingId === fundingBookingId
    ? loadingOptionsState
    : null;
  const loadingOptions = currentLoadingOptions?.options ?? [];
  const loadingOptionsBusy = Boolean(fundingBookingId && !currentLoadingOptions);
  const loadingOptionsError = currentLoadingOptions?.error === true;

  const matchingRows = useMemo(() => {
    const term = search.trim().toLocaleLowerCase();
    return (rows ?? []).filter((row) => {
      if (directionFilter !== "all" && row.direction !== directionFilter) return false;
      if (fundingFilter !== "all" && row.funding_status !== fundingFilter) return false;
      if (!term) return true;
      const history = row.events.map((event) => [event.reference_no, event.reason, event.event_amount, event.event_date].filter(Boolean).join(" ")).join(" ");
      return [row.parchi_no, row.counterparty_name, row.counterparty_type, row.document_amount, row.external_reference_no, row.remarks, history]
        .filter(Boolean).join(" ").toLocaleLowerCase().includes(term);
    });
  }, [rows, search, directionFilter, fundingFilter]);

  const deadlineAnalyses = useMemo(() => new Map(matchingRows.map((row) => [
    row.parchi_id,
    analyzeParchiDeadlines(row, businessToday),
  ])), [matchingRows, businessToday]);
  const dueTodaySummary = useMemo(
    () => summarizeParchiDeadlines(matchingRows, businessToday, "due_today"),
    [matchingRows, businessToday],
  );
  const overdueSummary = useMemo(
    () => summarizeParchiDeadlines(matchingRows, businessToday, "overdue"),
    [matchingRows, businessToday],
  );
  const filteredRows = useMemo(() => matchingRows.filter((row) => {
    if (deadlineFilter === "all") return true;
    const analysis = deadlineAnalyses.get(row.parchi_id);
    return analysis?.funding.bucket === deadlineFilter || analysis?.settlement.bucket === deadlineFilter;
  }), [matchingRows, deadlineFilter, deadlineAnalyses]);

  // The statement RPC is the authoritative row source. Search covers Parchi number,
  // counterparty, amount and event references because the RPC does not return the
  // document's external reference field.
  const totals = useMemo(() => (rows ?? []).reduce((sum, row) => ({
    count: sum.count + 1,
    funded: sum.funded + Number(row.net_funded || 0),
    outstanding: sum.outstanding + Number(row.funded_outstanding || 0),
  }), { count: 0, funded: 0, outstanding: 0 }), [rows]);

  function openCreate(direction: Direction, issuedMode: "standard" | "freight_financing" = "standard") {
    setNotice(""); setActionError("");
    setModal({ kind: "create", direction, issuedMode, requestId: makeRequestId(), uncertain: false, documentDate: localDate(), documentAmount: "", fundingDueDate: "", settlementDueDate: "", counterpartyId: "", bookingId: "", vehicleId: "", externalReferenceNo: "", remarks: "", primaryPayerType: "party", primaryPayerId: "", vehicleNo: "", responsiblePartyId: "", responsiblePersonName: "", responsiblePhone: "" });
  }
  function openMoney(kind: "funding" | "settlement", parchi: ParchiSummary) {
    setNotice(""); setActionError("");
    setModal({ kind, parchi, requestId: makeRequestId(), uncertain: false, eventDate: localDate(), amount: "", withheldCommission: "", fundingRoute: "", settleVehicle: false, loadingId: "", paymentMethod: "Cash", referenceNo: "" });
  }
  function openAmend(parchi: ParchiSummary) {
    setNotice(""); setActionError("");
    setModal({ kind: "amend", parchi, requestId: makeRequestId(), uncertain: false, documentAmount: String(parchi.document_amount), fundingDueDate: parchi.funding_due_date ?? "", settlementDueDate: parchi.settlement_due_date ?? "", reason: "" });
  }
  function openCancel(parchi: ParchiSummary) {
    setNotice(""); setActionError("");
    setModal({ kind: "cancel", parchi, requestId: makeRequestId(), uncertain: false, reason: "" });
  }
  function openReverse(parchi: ParchiSummary, originalEvent: StatementEvent) {
    setNotice(""); setActionError("");
    setModal({ kind: "reverse", parchi, originalEvent, requestId: makeRequestId(), uncertain: false, eventDate: localDate(), reason: "" });
  }
  function openRecourse(parchi: ParchiSummary) {
    setNotice(""); setActionError("");
    setModal({ kind: "recourse", parchi, requestId: makeRequestId(), uncertain: false, eventDate: localDate(), recourseTarget: "primary_payer", reason: "" });
  }
  function updateModal(field: keyof ParchiModal, value: string) {
    setModal((current) => current ? { ...current, [field]: value, requestId: current.uncertain ? current.requestId : makeRequestId() } : current);
  }

  async function submitModal(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!modal || actionLock.current) return;
    if (modal.kind === "create" && (!contextAddaId || !modal.direction || !modal.documentDate || !amountInputIsValid(modal.documentAmount ?? ""))) {
      setActionError(t("parchi.errors.amount")); return;
    }
    if (modal.kind === "create" && modal.issuedMode === "freight_financing"
      && (!modal.primaryPayerType || !modal.primaryPayerId || !(modal.vehicleNo ?? "").trim() || !(modal.responsiblePersonName ?? "").trim())) {
      setActionError(t("parchi.errors.financeFields")); return;
    }
    if (modal.kind === "create" && modal.issuedMode !== "freight_financing" && !modal.counterpartyId) {
      setActionError(t("parchi.errors.amount")); return;
    }
    if ((modal.kind === "funding" || modal.kind === "settlement") && (!modal.eventDate || !amountInputIsValid(modal.amount ?? "") || !modal.paymentMethod)) {
      setActionError(t("parchi.errors.amount")); return;
    }
    if (modal.kind === "funding" && modal.parchi?.direction === "received"
      && (!modal.fundingRoute || !amountInputIsNonNegative(modal.withheldCommission ?? "") || Number(modal.withheldCommission ?? 0) >= Number(modal.amount ?? 0))) {
      setActionError(t("parchi.errors.commission")); return;
    }
    if (modal.kind === "funding" && modal.parchi?.issued_mode === "freight_financing"
      && (!amountInputIsNonNegative(modal.withheldCommission ?? "") || Number(modal.withheldCommission ?? 0) >= Number(modal.amount ?? 0))) {
      setActionError(t("parchi.errors.fundingCommission")); return;
    }
    if (modal.kind === "settlement" && modal.parchi?.issued_mode === "freight_financing" && !modal.recoveryPayerType) {
      setActionError(t("parchi.errors.recoveryPayer")); return;
    }
    if (modal.kind === "recourse" && (!modal.eventDate || !modal.recourseTarget || !(modal.reason ?? "").trim())) {
      setActionError(t("parchi.errors.date")); return;
    }
    if (modal.kind === "funding" && modal.parchi?.direction === "received" && modal.settleVehicle && !modal.parchi.booking_id) {
      setActionError(t("parchi.errors.vehicleLinkRequired")); return;
    }
    if (modal.kind === "amend" && (!amountInputIsValid(modal.documentAmount ?? "") || !(modal.reason ?? "").trim())) {
      setActionError(t("parchi.errors.amount")); return;
    }
    if ((modal.kind === "cancel" || modal.kind === "reverse") && !(modal.reason ?? "").trim()) {
      setActionError(t("parchi.errors.date")); return;
    }
    actionLock.current = true;
    setActionBusy(true);
    setActionError("");
    try {
      let result: { error: unknown | null };
      if (modal.kind === "create") {
        result = modal.issuedMode === "freight_financing"
          ? await supabase.rpc("create_issued_freight_parchi", {
          p_adda_id: contextAddaId,
          p_primary_payer_type: modal.primaryPayerType,
          p_primary_party_id: modal.primaryPayerType === "party" ? modal.primaryPayerId : null,
          p_primary_other_adda_id: modal.primaryPayerType === "other_adda" ? modal.primaryPayerId : null,
          p_document_date: modal.documentDate,
          p_document_amount: modal.documentAmount,
          p_funding_due_date: modal.fundingDueDate || null,
          p_settlement_due_date: modal.settlementDueDate || null,
          p_vehicle_id: modal.vehicleId || null,
          p_vehicle_no: modal.vehicleNo?.trim(),
          p_responsible_party_id: modal.responsiblePartyId || null,
          p_responsible_person_name: modal.responsiblePersonName?.trim(),
          p_responsible_phone: modal.responsiblePhone?.trim() || null,
          p_booking_id: modal.bookingId || null,
          p_loading_id: modal.loadingId ? Number(modal.loadingId) : null,
          p_external_reference_no: modal.externalReferenceNo?.trim() || null,
          p_remarks: modal.remarks?.trim() || null,
          p_request_id: modal.requestId,
        })
          : await supabase.rpc("create_parchi", {
          p_adda_id: contextAddaId,
          p_direction: modal.direction,
          p_broker_id: modal.direction === "received" ? modal.counterpartyId : null,
          p_other_adda_id: modal.direction === "issued" ? modal.counterpartyId : null,
          p_document_date: modal.documentDate,
          p_document_amount: modal.documentAmount,
          p_funding_due_date: modal.fundingDueDate || null,
          p_settlement_due_date: modal.settlementDueDate || null,
          p_external_reference_no: modal.externalReferenceNo?.trim() || null,
          p_remarks: modal.remarks?.trim() || null,
          p_party_id: null,
          p_vehicle_id: modal.direction === "received" ? (bookings.find((booking) => booking.id === modal.bookingId)?.vehicle_id ?? modal.vehicleId) || null : null,
          p_driver_id: null,
          p_booking_id: modal.direction === "received" ? modal.bookingId || null : null,
          p_movement_group_id: null,
          p_voucher_id: null,
          p_request_id: modal.requestId,
        });
      } else if (modal.kind === "funding" && modal.parchi) {
        if (modal.parchi.issued_mode === "freight_financing") {
          result = await supabase.rpc("post_issued_freight_parchi_funding", {
            p_parchi_id: modal.parchi.parchi_id, p_event_date: modal.eventDate,
            p_principal_amount: modal.amount, p_commission_withheld: modal.withheldCommission,
            p_payment_method: modal.paymentMethod, p_reference_no: modal.referenceNo?.trim() || null,
            p_request_id: modal.requestId,
          });
        } else if (modal.parchi.direction === "received") {
          const commission = modal.withheldCommission ?? "0";
          result = await supabase.rpc("post_received_parchi_funding_with_commission", {
            p_parchi_id: modal.parchi.parchi_id,
            p_event_date: modal.eventDate,
            p_principal_amount: modal.amount,
            p_withheld_commission: commission,
            p_funding_route: modal.fundingRoute ?? "",
            p_payment_method: modal.paymentMethod,
            p_reference_no: modal.referenceNo?.trim() || null,
            p_request_id: modal.requestId,
            p_settle_vehicle: modal.settleVehicle ?? false,
            p_loading_id: modal.loadingId ? Number(modal.loadingId) : null,
          });
        } else {
          result = await supabase.rpc("post_parchi_funding", {
            p_parchi_id: modal.parchi.parchi_id, p_event_date: modal.eventDate,
            p_amount: modal.amount, p_payment_method: modal.paymentMethod,
            p_reference_no: modal.referenceNo?.trim() || null, p_request_id: modal.requestId,
          });
        }
      } else if (modal.kind === "settlement" && modal.parchi) {
        result = modal.parchi.issued_mode === "freight_financing"
          ? await supabase.rpc("post_issued_freight_parchi_recovery", {
            p_parchi_id: modal.parchi.parchi_id, p_event_date: modal.eventDate,
            p_amount: modal.amount, p_payment_method: modal.paymentMethod,
            p_reference_no: modal.referenceNo?.trim() || null,
            p_payer_type: modal.recoveryPayerType, p_request_id: modal.requestId,
          })
          : await supabase.rpc("post_parchi_settlement", {
          p_parchi_id: modal.parchi.parchi_id, p_event_date: modal.eventDate,
          p_amount: modal.amount, p_payment_method: modal.paymentMethod,
          p_reference_no: modal.referenceNo?.trim() || null, p_request_id: modal.requestId,
        });
      } else if (modal.kind === "amend" && modal.parchi) {
        result = modal.parchi.issued_mode === "freight_financing"
          ? await supabase.rpc("amend_issued_freight_parchi", {
            p_parchi_id: modal.parchi.parchi_id, p_document_amount: modal.documentAmount,
            p_funding_due_date: modal.fundingDueDate || null, p_settlement_due_date: modal.settlementDueDate || null,
            p_reason: modal.reason?.trim(), p_request_id: modal.requestId,
          })
          : await supabase.rpc("amend_parchi_document", {
          p_parchi_id: modal.parchi.parchi_id,
          p_document_amount: modal.documentAmount,
          p_funding_due_date: modal.fundingDueDate || null,
          p_settlement_due_date: modal.settlementDueDate || null,
          p_reason: modal.reason?.trim(), p_request_id: modal.requestId,
        });
      } else if (modal.kind === "cancel" && modal.parchi) {
        result = modal.parchi.issued_mode === "freight_financing"
          ? await supabase.rpc("cancel_issued_freight_parchi", {
            p_parchi_id: modal.parchi.parchi_id, p_reason: modal.reason?.trim(), p_request_id: modal.requestId,
          })
          : await supabase.rpc("cancel_unfunded_parchi", {
          p_parchi_id: modal.parchi.parchi_id, p_reason: modal.reason?.trim(), p_request_id: modal.requestId,
        });
      } else if (modal.kind === "recourse" && modal.parchi) {
        result = await supabase.rpc("record_issued_freight_parchi_recourse", {
          p_parchi_id: modal.parchi.parchi_id, p_event_date: modal.eventDate,
          p_recourse_target: modal.recourseTarget, p_reason: modal.reason?.trim(), p_request_id: modal.requestId,
        });
      } else if (modal.kind === "reverse" && modal.originalEvent) {
        const isIssuedFinanceEvent = modal.parchi?.issued_mode === "freight_financing";
        const isReceivedCommissionFunding = modal.parchi?.direction === "received"
          && modal.originalEvent.event_kind === "funding"
          && modal.originalEvent.commission_withheld !== null
          && modal.originalEvent.actual_cash_amount !== null;
        result = isIssuedFinanceEvent
          ? await supabase.rpc("reverse_issued_freight_parchi_event", {
            p_event_id: modal.originalEvent.event_id, p_reversal_date: modal.eventDate,
            p_reason: modal.reason?.trim(), p_request_id: modal.requestId,
          })
          : isReceivedCommissionFunding
          ? await supabase.rpc("reverse_received_parchi_funding", {
            p_event_id: modal.originalEvent.event_id,
            p_reversal_date: modal.eventDate,
            p_reason: modal.reason?.trim(),
            p_request_id: modal.requestId,
          })
          : await supabase.rpc("reverse_parchi_event", {
            p_event_id: modal.originalEvent.event_id,
            p_reversal_date: modal.eventDate,
            p_reason: modal.reason?.trim(), p_request_id: modal.requestId,
          });
      } else {
        throw new Error("The requested Parchi action is incomplete.");
      }
      if (result.error) throw result.error;
      setModal(null);
      setNotice(modal.kind === "create" ? t("parchi.createSuccess") : t("parchi.actionSuccess"));
      setSelectedId(modal.parchi?.parchi_id ?? null);
      setRefreshToken((value) => value + 1);
    } catch (error) {
      console.error("Parchi RPC failed", error);
      const hasDatabaseCode = Boolean(error && typeof error === "object" && "code" in error && typeof error.code === "string");
      setActionError(hasDatabaseCode ? errorMessage(error) : `${errorMessage(error)} ${t("parchi.errors.requestUncertain")}`);
      if (!hasDatabaseCode) setModal((current) => current ? { ...current, uncertain: true } : current);
      else setModal((current) => current ? { ...current, requestId: makeRequestId(), uncertain: false } : current);
    } finally {
      actionLock.current = false;
      setActionBusy(false);
    }
  }

  function isCancelled(parchi: ParchiSummary) { return parchi.funding_status === "Cancelled"; }
  function hasMoneyHistory(parchi: ParchiSummary) { return parchi.events.some((event) => event.event_kind === "funding" || event.event_kind === "settlement" || event.event_kind === "recovery" || event.event_kind === "reversal"); }
  function isReversed(parchi: ParchiSummary, eventId: string | null) { return Boolean(eventId && parchi.events.some((event) => event.event_kind === "reversal" && event.reverses_event_id === eventId)); }

  return (
    <>
    <div className="space-y-6" dir={dir}>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <ModulePageHeading icon="receipt" title={t("parchi.title")} description={t("parchi.description")} accent="green" />
        <div className="flex flex-wrap gap-2">
          <button className={buttonSecondary} type="button" onClick={() => setRefreshToken((value) => value + 1)} disabled={!contextAddaId || dataBusy}>
            <RefreshCw className={`h-4 w-4 ${dataBusy ? "animate-spin" : ""}`} />{t("parchi.refresh")}
          </button>
          <button className={buttonPrimary} type="button" onClick={() => openCreate("received")} disabled={!contextAddaId || contextBusy}>
            <ArrowDownLeft className="h-4 w-4" />{t("parchi.newReceived")}
          </button>
          <button className={buttonPrimary} type="button" onClick={() => openCreate("issued")} disabled={!contextAddaId || contextBusy}>
            <ArrowUpRight className="h-4 w-4" />{t("parchi.newIssued")}
          </button>
          <button className={buttonSecondary} type="button" onClick={() => openCreate("issued", "freight_financing")} disabled={!contextAddaId || contextBusy}>
            <ArrowUpRight className="h-4 w-4" />{t("parchi.newIssuedFinance")}
          </button>
        </div>
      </div>

      {profile?.role === USER_ROLES.superAdmin && <div className="max-w-sm">
        <label className={labelClass} htmlFor="parchi-adda">{t("parchi.selectAdda")}</label>
        <select id="parchi-adda" className={control} value={selectedAddaId} onChange={(event) => { setSelectedAddaId(event.target.value); setRows(null); setSelectedId(null); setModal(null); setDeadlineFilter("all"); }}>
          <option value="">{t("parchi.selectAdda")}</option>
          {addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}
        </select>
      </div>}

      {loadError && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-800">{loadError}</div>}
      {actionError && !modal && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-semibold text-rose-800">{actionError}</div>}
      {notice && <div role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-800">{notice}</div>}

      <section className="grid gap-3 lg:grid-cols-2" aria-label={t("parchi.deadlineSummaries")}>
        <DeadlineSummaryCard
          title={t("parchi.dueToday")}
          summary={dueTodaySummary}
          selected={deadlineFilter === "due_today"}
          disabled={!rows || !businessToday}
          onClick={() => setDeadlineFilter((current) => current === "due_today" ? "all" : "due_today")}
          t={t}
        />
        <DeadlineSummaryCard
          title={t("parchi.overdue")}
          summary={overdueSummary}
          selected={deadlineFilter === "overdue"}
          disabled={!rows || !businessToday}
          onClick={() => setDeadlineFilter((current) => current === "overdue" ? "all" : "overdue")}
          t={t}
        />
      </section>
      <p className="-mt-3 text-xs text-slate-500">{t("parchi.deadlineSummaryScope")}</p>

      <section className="grid gap-3 sm:grid-cols-3">
        <SummaryCard label={t("parchi.totalParchis")} value={String(totals.count)} />
        <SummaryCard label={t("parchi.funded")} value={money(totals.funded)} />
        <SummaryCard label={t("parchi.outstanding")} value={money(totals.outstanding)} />
      </section>

      <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <div className="grid gap-3 md:grid-cols-[minmax(220px,1fr)_190px_210px]">

          <VoiceTypingField fieldLabel={t("parchi.search")} mode="text"><label className="relative block">
            <span className="sr-only">{t("parchi.search")}</span>
            <Search className="pointer-events-none absolute left-3 top-3 h-4 w-4 text-slate-400" />
            <input className={`${control} pl-9`} value={search} onChange={(event) => setSearch(event.target.value)} placeholder={t("parchi.search")} />
          </label></VoiceTypingField>

          <select className={control} aria-label={t("parchi.direction")} value={directionFilter} onChange={(event) => setDirectionFilter(event.target.value as "all" | Direction)}>
            <option value="all">{t("parchi.allDirections")}</option><option value="received">{t("parchi.received")}</option><option value="issued">{t("parchi.issued")}</option>
          </select>
          <select className={control} aria-label={t("parchi.fundingStatus")} value={fundingFilter} onChange={(event) => setFundingFilter(event.target.value)}>
            <option value="all">{t("parchi.allFundingStatuses")}</option>
            {["Unfunded", "Partially Funded", "Fully Funded", "Cancelled"].map((status) => <option value={status} key={status}>{labelStatus(status, t)}</option>)}
          </select>
        </div>
      </section>

      <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
        {dataBusy && <div className="border-b border-slate-100 px-4 py-2 text-sm text-slate-500">{t("parchi.loading")}</div>}
        <div className="overflow-x-auto">
          <table className="min-w-[1220px] w-full text-left text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-600">
              <tr>{[t("parchi.document"), t("parchi.direction"), t("parchi.counterparty"), t("parchi.vehicleNumber"), t("parchi.documentAmount"), t("parchi.fundingStatus"), t("parchi.funded"), t("parchi.outstanding"), t("parchi.dueDates"), t("parchi.settlementStatus"), t("parchi.actions")].map((heading) => <th className="px-4 py-3" key={heading}>{heading}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filteredRows.map((row) => <tr key={row.parchi_id} className="align-top hover:bg-slate-50/70">
                <td className="px-4 py-3"><div className="font-extrabold text-slate-900">{row.parchi_no}</div><div className="mt-1 text-xs text-slate-500">{row.document_date}</div></td>
                <td className="px-4 py-3"><span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-bold ${row.direction === "received" ? "bg-blue-50 text-blue-800" : "bg-violet-50 text-violet-800"}`}>{row.direction === "received" ? t("parchi.received") : t("parchi.issued")}</span></td>
                <td className="px-4 py-3 font-semibold text-slate-800">{row.counterparty_name || "—"}</td>
                <td dir="ltr" className="whitespace-nowrap px-4 py-3 font-semibold text-slate-700">{row.direction === "received" && row.counterparty_type === "broker" ? row.vehicle_no || "—" : "—"}</td>
                <td className="px-4 py-3 font-semibold tabular-nums">{money(row.document_amount)}</td>
                <td className="px-4 py-3"><StatusBadge value={row.funding_status} t={t} /></td>
                <td className="px-4 py-3 tabular-nums">{money(row.net_funded)}</td>
                <td className="px-4 py-3 tabular-nums">{money(row.funded_outstanding)}</td>
                <td className="min-w-[270px] px-4 py-3 text-xs leading-5">
                  <DeadlineLine label={t("parchi.fundingDueDate")} deadline={deadlineAnalyses.get(row.parchi_id)?.funding} t={t} />
                  <DeadlineLine label={t("parchi.settlementDueDate")} deadline={deadlineAnalyses.get(row.parchi_id)?.settlement} t={t} />
                </td>
                <td className="px-4 py-3"><StatusBadge value={row.settlement_status} t={t} /></td>
                <td className="px-4 py-3"><div className="flex gap-2"><button className={buttonSecondary} type="button" onClick={() => setSelectedId(row.parchi_id)}><Eye className="h-4 w-4" />{t("parchi.history")}</button><button className={buttonSecondary} type="button" onClick={() => printParchi(row)} aria-label={`${t("common.actions.print")} ${row.parchi_no}`}><Printer className="h-4 w-4" />{t("common.actions.print")}</button></div></td>
              </tr>)}
              {!dataBusy && filteredRows.length === 0 && <tr><td colSpan={11} className="px-4 py-12 text-center text-sm text-slate-500">{rows ? t("parchi.noRecords") : t("parchi.noAddaSelected")}</td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      {selectedParchi && <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/50 p-3 sm:p-6" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelectedId(null); }}>
        <section role="dialog" aria-modal="true" aria-labelledby="parchi-detail-title" className="max-h-[94vh] w-full max-w-5xl overflow-y-auto rounded-2xl bg-white shadow-2xl">
          <div className="sticky top-0 z-10 flex items-start justify-between gap-4 border-b border-slate-200 bg-white px-5 py-4">
            <div><h2 id="parchi-detail-title" className="text-xl font-extrabold text-slate-900">{selectedParchi.parchi_no}</h2><p className="mt-1 text-sm text-slate-600">{selectedParchi.counterparty_name} · {selectedParchi.issued_mode === "freight_financing" ? t("parchi.issuedFinance") : selectedParchi.direction === "received" ? t("parchi.received") : t("parchi.issued")}</p></div>
            <div className="flex gap-2"><button type="button" className={buttonSecondary} onClick={() => printParchi(selectedParchi)}><Printer className="h-4 w-4" />{t("common.actions.print")}</button><button type="button" className={buttonSecondary} aria-label={t("parchi.close")} onClick={() => setSelectedId(null)}><X className="h-4 w-4" /></button></div>
          </div>
          <div className="space-y-5 p-5">
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <DetailMetric label={t("parchi.documentAmount")} value={money(selectedParchi.document_amount)} />
              {selectedParchi.direction === "received" && selectedParchi.counterparty_type === "broker" && <DetailMetric label={t("parchi.vehicleNumber")} value={selectedParchi.vehicle_no || "—"} direction="ltr" />}
              {(selectedParchi.direction === "received" || selectedParchi.issued_mode === "freight_financing") && <DetailMetric label={t(selectedParchi.issued_mode === "freight_financing" ? "parchi.upfrontCommission" : "parchi.print.commissionWithheld")} value={selectedParchi.commission_withheld === null ? t("parchi.print.notRecorded") : money(selectedParchi.commission_withheld)} />}
              {(selectedParchi.direction === "received" || selectedParchi.issued_mode === "freight_financing") && <DetailMetric label={t(selectedParchi.issued_mode === "freight_financing" ? "parchi.actualCashDisbursed" : "parchi.print.actualCash")} value={selectedParchi.actual_cash_amount === null ? t("parchi.print.notRecorded") : money(selectedParchi.actual_cash_amount)} />}
              <DetailMetric label={t("parchi.funded")} value={money(selectedParchi.net_funded)} />
              <DetailMetric label={t("parchi.settled")} value={money(selectedParchi.net_settled)} />
              <DetailMetric label={t("parchi.outstanding")} value={money(selectedParchi.funded_outstanding)} />
            </div>
            <div className="grid gap-3 rounded-xl bg-slate-50 p-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <DetailField label={t("parchi.documentDate")} value={selectedParchi.document_date} />
              <DetailField label={t("parchi.fundingDueDate")} value={selectedParchi.funding_due_date || "—"} hint={t("parchi.fundingDueHelp")} />
                <DetailField label={t("parchi.settlementDueDate")} value={selectedParchi.settlement_due_date || "—"} hint={t("parchi.settlementDueHelp")} />
              <DetailField label={t("parchi.fundingStatus")} value={labelStatus(selectedParchi.funding_status, t)} />
            </div>
            {selectedParchi.issued_mode === "freight_financing" && <div className="grid gap-3 rounded-xl border border-indigo-100 bg-indigo-50/50 p-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <DetailField label={t("parchi.primaryPayer")} value={selectedParchi.primary_payer_name || selectedParchi.counterparty_name || "—"} />
              <DetailField label={t("parchi.responsiblePerson")} value={selectedParchi.responsible_person_name || "—"} />
              <DetailField label={t("common.vehicle")} value={selectedParchi.vehicle_no || "—"} />
              <DetailField label={t("parchi.responsiblePhone")} value={selectedParchi.responsible_phone || "—"} />
            </div>}
            {(selectedParchi.external_reference_no || selectedParchi.remarks) && <div className="grid gap-3 rounded-xl border border-slate-200 p-4 text-sm sm:grid-cols-2">
              {selectedParchi.external_reference_no && <DetailField label={t("parchi.externalReference")} value={selectedParchi.external_reference_no} />}
              {selectedParchi.remarks && <DetailField label={t("parchi.remarks")} value={selectedParchi.remarks} />}
            </div>}
            <div className="flex flex-wrap gap-2">
                {!isCancelled(selectedParchi) && <>
                {Number(selectedParchi.net_funded) < Number(selectedParchi.document_amount) && <button className={buttonPrimary} type="button" onClick={() => openMoney("funding", selectedParchi)}><Plus className="h-4 w-4" />{t("parchi.fund")}</button>}
                {Number(selectedParchi.net_funded) > 0 && Number(selectedParchi.funded_outstanding) > 0 && <button className={buttonSecondary} type="button" onClick={() => openMoney("settlement", selectedParchi)}>{t("parchi.settle")}</button>}
                {canManage && <button className={buttonSecondary} type="button" onClick={() => openAmend(selectedParchi)}>{t("parchi.amend")}</button>}
                {canManage && selectedParchi.issued_mode === "freight_financing" && Number(selectedParchi.funded_outstanding) > 0 && <button className={buttonSecondary} type="button" onClick={() => openRecourse(selectedParchi)}>{t("parchi.recordRecourse")}</button>}
                {canManage && !hasMoneyHistory(selectedParchi) && <button className={buttonSecondary} type="button" onClick={() => openCancel(selectedParchi)}>{t("parchi.cancelUnfunded")}</button>}
              </>}
            </div>
            <div>
              <h3 className="mb-3 flex items-center gap-2 font-extrabold text-slate-900"><Clock3 className="h-4 w-4" />{t("parchi.history")}</h3>
              <div className="overflow-x-auto rounded-xl border border-slate-200">
                <table className="min-w-[760px] w-full text-left text-sm">
                  <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-600"><tr>{[t("parchi.event"), t("parchi.eventDate"), t("parchi.amount"), ...(selectedParchi.direction === "received" ? [t("parchi.print.commissionWithheld"), t("parchi.print.actualCash"), t("parchi.print.fundingRoute")] : selectedParchi.issued_mode === "freight_financing" ? [t("parchi.upfrontCommission"), t("parchi.actualCashDisbursed"), t("parchi.recoveryPayer")] : []), t("parchi.paymentMethod"), t("parchi.referenceNo"), t("parchi.reason"), t("parchi.actions")].map((heading) => <th key={heading} className="px-3 py-2.5">{heading}</th>)}</tr></thead>
                  <tbody className="divide-y divide-slate-100">
                    {selectedParchi.events.map((event) => {
                      const original = event.reverses_event_id ? selectedParchi.events.find((candidate) => candidate.event_id === event.reverses_event_id) : undefined;
                      const valueSource = event.event_kind === "reversal" ? original : event;
                      const commission = valueSource?.commission_withheld == null ? null : Number(valueSource.commission_withheld) * (event.event_kind === "reversal" ? -1 : 1);
                      const actualCash = valueSource?.actual_cash_amount == null ? null : Number(valueSource.actual_cash_amount) * (event.event_kind === "reversal" ? -1 : 1);
                      const settlementSource = event.event_kind === "reversal" ? original : event;
                      const route = settlementSource?.funding_route === "direct_to_vehicle" ? t("parchi.fundingRouteDirect") : settlementSource?.funding_route === "through_adda" ? t("parchi.fundingRouteThroughAdda") : "—";
                      const fundingRelated = event.event_kind === "funding" || original?.event_kind === "funding";
                      const settlementReference = settlementSource ? [
                        settlementSource.vehicle_settlement_booking_no ? `${t("common.bookingNo")}: ${settlementSource.vehicle_settlement_booking_no}` : null,
                        settlementSource.vehicle_settlement_loading_no ? `${t("common.loadingNo")}: ${settlementSource.vehicle_settlement_loading_no}` : null,
                        settlementSource.vehicle_settlement_vehicle_no ? `${t("common.vehicle")}: ${settlementSource.vehicle_settlement_vehicle_no}` : null,
                      ].filter(Boolean).join(" · ") : "";
                      return <tr key={event.event_id ?? `${selectedParchi.parchi_id}-${event.event_kind}`}>
                      <td className="px-3 py-3 font-semibold">{labelEvent(event.event_kind, t)}</td><td className="px-3 py-3">{event.event_date || "—"}</td><td className="px-3 py-3 tabular-nums">{event.event_amount === null ? "—" : money(event.event_kind === "reversal" ? -Number(event.event_amount) : event.event_amount)}</td>
                      {selectedParchi.direction === "received" && <><td className="px-3 py-3 tabular-nums">{!fundingRelated ? "—" : commission === null ? t("parchi.print.notRecorded") : money(commission)}</td><td className="px-3 py-3 tabular-nums">{!fundingRelated ? "—" : actualCash === null ? t("parchi.print.notRecorded") : money(actualCash)}</td><td className="px-3 py-3">{!fundingRelated ? "—" : route === "—" ? t("parchi.print.notRecorded") : route}</td><td className="px-3 py-3 text-xs">{settlementReference || "—"}</td></>}
                      {selectedParchi.issued_mode === "freight_financing" && <><td className="px-3 py-3 tabular-nums">{event.event_kind === "funding" || (event.event_kind === "reversal" && original?.event_kind === "funding") ? commission === null ? t("parchi.print.notRecorded") : money(commission) : "—"}</td><td className="px-3 py-3 tabular-nums">{event.event_kind === "funding" || event.event_kind === "recovery" || event.event_kind === "reversal" ? actualCash === null ? t("parchi.print.notRecorded") : money(actualCash) : "—"}</td><td className="px-3 py-3">{event.event_payer_name || "—"}</td></>}
                      <td className="px-3 py-3">{event.payment_method || "—"}</td><td className="px-3 py-3">{event.reference_no || "—"}</td><td className="px-3 py-3">{event.reason || "—"}</td>
                      <td className="px-3 py-3"><div className="flex flex-wrap items-center gap-2">{(event.event_kind === "funding" || event.event_kind === "settlement" || event.event_kind === "recovery" || event.event_kind === "reversal") && event.event_id && <button type="button" className="text-xs font-bold text-slate-700 underline" onClick={() => printParchiMoneyEvent(selectedParchi, event)}>{t("common.actions.print")}</button>}{canManage && (event.event_kind === "funding" || event.event_kind === "settlement" || event.event_kind === "recovery") && event.event_id && !isReversed(selectedParchi, event.event_id) && <button type="button" className="text-xs font-bold text-rose-700 underline" onClick={() => openReverse(selectedParchi, event)}>{t("parchi.reverse")}</button>}</div></td>
                    </tr>;
                    })}
                    {selectedParchi.events.length === 0 && <tr><td className="px-3 py-8 text-center text-slate-500" colSpan={selectedParchi.direction === "received" || selectedParchi.issued_mode === "freight_financing" ? 10 : 7}>{t("parchi.noEvents")}</td></tr>}
                  </tbody>
                </table>
              </div>
            </div>
            <p className="text-xs text-slate-500">{t("parchi.principalNotice")}</p>
          </div>
        </section>
      </div>}

      {modal && <div className="fixed inset-0 z-[60] flex items-center justify-center bg-slate-950/55 p-3" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !modal.uncertain) setModal(null); }}>
        <section role="dialog" aria-modal="true" aria-labelledby="parchi-modal-title" className="max-h-[94vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white shadow-2xl">
          <div className="flex items-start justify-between gap-4 border-b border-slate-200 px-5 py-4">
            <div><h2 id="parchi-modal-title" className="text-lg font-extrabold text-slate-900">{modalTitle(modal, t)}</h2><p className="mt-1 text-xs text-slate-500">{modal.kind === "create" ? t("parchi.unfundedNotice") : modal.kind === "funding" || modal.kind === "settlement" ? t("parchi.cashbookNotice") : ""}</p></div>
            <button className={buttonSecondary} type="button" disabled={modal.uncertain} onClick={() => { setModal(null); setActionError(""); }} aria-label={t("parchi.close")}><X className="h-4 w-4" /></button>
          </div>
          <form className="space-y-4 p-5" onSubmit={(event) => void submitModal(event)}>
            {modal.kind === "create" && <>
              {modal.issuedMode === "freight_financing" ? <>
                <label className="block"><span className={labelClass}>{t("parchi.primaryPayerType")}</span>
                  <select className={control} value={modal.primaryPayerType ?? "party"} disabled={modal.uncertain} onChange={(event) => setModal((current) => current ? { ...current, primaryPayerType: event.target.value as "party" | "other_adda", primaryPayerId: "", requestId: current.uncertain ? current.requestId : makeRequestId() } : current)}>
                    <option value="party">{t("parchi.party")}</option><option value="other_adda">{t("parchi.otherAdda")}</option>
                  </select>
                </label>
                <label className="block"><span className={labelClass}>{t("parchi.primaryRecoveryPayer")}</span>
                  <select className={control} value={modal.primaryPayerId ?? ""} required disabled={modal.uncertain} onChange={(event) => updateModal("primaryPayerId", event.target.value)}>
                    <option value="">{t("parchi.chooseCounterparty")}</option>
                    {modal.primaryPayerType === "party" ? parties.map((party) => <option key={party.id} value={party.id}>{party.name || party.id}</option>) : otherAddas.map((adda) => <option key={adda.id} value={adda.id}>{adda.adda_name}</option>)}
                  </select>
                </label>
              </> : <label className="block"><span className={labelClass}>{modal.direction === "received" ? t("parchi.broker") : t("parchi.otherAdda")}</span>
                <select className={control} value={modal.counterpartyId ?? ""} required disabled={modal.uncertain} onChange={(event) => updateModal("counterpartyId", event.target.value)}>
                  <option value="">{t("parchi.chooseCounterparty")}</option>
                  {modal.direction === "received" ? brokers.map((broker) => <option key={broker.id} value={broker.id}>{broker.broker_name || broker.id}</option>) : otherAddas.map((adda) => <option key={adda.id} value={adda.id}>{adda.adda_name}</option>)}
                </select>
              </label>}
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label={t("parchi.documentDate")} type="date" value={modal.documentDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("documentDate", value)} required />
                <Field label={t("parchi.documentAmount")} type="number" min="0.01" step="0.01" value={modal.documentAmount ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("documentAmount", value)} required />
                <Field label={t("parchi.fundingDueDate")} type="date" min={modal.documentDate} value={modal.fundingDueDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("fundingDueDate", value)} hint={t("parchi.fundingDueHelp")} />
                <Field label={t("parchi.settlementDueDate")} type="date" min={modal.documentDate} value={modal.settlementDueDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("settlementDueDate", value)} hint={t("parchi.settlementDueHelp")} />
              </div>
                <Field label={t("parchi.externalReference")} mode="identifier" value={modal.externalReferenceNo ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("externalReferenceNo", value)} />
              <Field label={t("parchi.remarks")} value={modal.remarks ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("remarks", value)} />
              {modal.issuedMode === "freight_financing" && <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label={t("parchi.vehicleNumber")} mode="identifier" value={modal.vehicleNo ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("vehicleNo", value)} required />
                  <label className="block"><span className={labelClass}>{t("parchi.optionalVehicleRecord")}</span><select className={control} value={modal.vehicleId ?? ""} disabled={modal.uncertain || Boolean(bookings.find((item) => item.id === modal.bookingId)?.vehicle_id) || Boolean(financeLoadings.find((item) => String(item.id) === String(modal.loadingId))?.vehicle_id)} onChange={(event) => setModal((current) => { const id = event.target.value; const vehicle = vehicles.find((item) => item.id === id); return current ? { ...current, vehicleId: id, vehicleNo: vehicle?.vehicle_no ?? current.vehicleNo, requestId: current.uncertain ? current.requestId : makeRequestId() } : current; })}><option value="">{t("parchi.noLinkedVehicle")}</option>{vehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicle_no || vehicle.id}</option>)}</select></label>
                  <label className="block"><span className={labelClass}>{t("parchi.responsiblePartyLink")}</span><select className={control} value={modal.responsiblePartyId ?? ""} disabled={modal.uncertain} onChange={(event) => updateModal("responsiblePartyId", event.target.value)}><option value="">—</option>{parties.map((party) => <option key={party.id} value={party.id}>{party.name || party.id}</option>)}</select></label>
                  <Field label={t("parchi.responsiblePerson")} value={modal.responsiblePersonName ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("responsiblePersonName", value)} required />
                  <Field label={t("parchi.responsiblePhone")} mode="phone" value={modal.responsiblePhone ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("responsiblePhone", value)} />
                  <label className="block"><span className={labelClass}>{t("parchi.optionalBookingReference")}</span><select className={control} value={modal.bookingId ?? ""} disabled={modal.uncertain} onChange={(event) => setModal((current) => { const id = event.target.value; const booking = bookings.find((item) => item.id === id); const vehicle = vehicles.find((item) => item.id === booking?.vehicle_id); return current ? { ...current, bookingId: id, loadingId: "", vehicleId: booking?.vehicle_id ?? (id ? "" : current.vehicleId), vehicleNo: booking?.vehicle_id ? vehicle?.vehicle_no ?? "" : id ? "" : current.vehicleNo, requestId: current.uncertain ? current.requestId : makeRequestId() } : current; })}><option value="">{t("parchi.noLinkedBilty")}</option>{bookings.map((booking) => <option key={booking.id} value={booking.id}>{booking.booking_no || booking.id}</option>)}</select></label>
                  <label className="block"><span className={labelClass}>{t("parchi.optionalLoadingReference")}</span><select className={control} value={modal.loadingId ?? ""} disabled={modal.uncertain || !financeLoadings.length} onChange={(event) => setModal((current) => { const id = event.target.value; const loading = financeLoadings.find((item) => String(item.id) === id); const vehicle = vehicles.find((item) => item.id === loading?.vehicle_id); return current ? { ...current, loadingId: id, ...(loading?.vehicle_id ? { vehicleId: loading.vehicle_id, vehicleNo: vehicle?.vehicle_no ?? "" } : {}), requestId: current.uncertain ? current.requestId : makeRequestId() } : current; })}><option value="">{t("parchi.noLinkedLoading")}</option>{financeLoadings.filter((loading) => !modal.bookingId || loading.booking_id === modal.bookingId).map((loading) => <option key={loading.id} value={loading.id}>{loading.loading_no || loading.id}</option>)}</select></label>
                </div>
                <p className="rounded-lg bg-slate-50 p-3 text-xs text-slate-600">{t("parchi.financeAccountNote")}</p>
              </>}
              {modal.direction === "received" && <label className="block"><span className={labelClass}>{t("parchi.linkedBilty")}</span>
                <select className={control} value={modal.bookingId ?? ""} disabled={modal.uncertain} onChange={(event) => { const bookingId = event.target.value; setModal((current) => current ? { ...current, bookingId, vehicleId: bookings.find((booking) => booking.id === bookingId)?.vehicle_id ?? "", requestId: current.uncertain ? current.requestId : makeRequestId() } : current); }}>
                  <option value="">{t("parchi.noLinkedBilty")}</option>
                  {bookings.map((booking) => <option key={booking.id} value={booking.id}>{booking.booking_no || booking.id}</option>)}
                </select>
              </label>}
              {modal.direction === "received" && <label className="block"><span className={labelClass}>{t("parchi.linkedVehicle")}</span>
                <select className={control} value={modal.bookingId ? bookings.find((booking) => booking.id === modal.bookingId)?.vehicle_id ?? modal.vehicleId ?? "" : modal.vehicleId ?? ""} disabled={modal.uncertain || Boolean(modal.bookingId && bookings.find((booking) => booking.id === modal.bookingId)?.vehicle_id)} onChange={(event) => updateModal("vehicleId", event.target.value)}>
                  <option value="">{t("parchi.noLinkedVehicle")}</option>
                  {vehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicle_no || vehicle.id}</option>)}
                </select>
              </label>}
            </>}
            {(modal.kind === "funding" || modal.kind === "settlement") && <>
              <p className="rounded-lg bg-emerald-50 px-3 py-2 text-sm font-medium text-emerald-900">{modal.kind === "funding" ? modal.parchi?.issued_mode === "freight_financing" ? t("parchi.issuedFinanceFundingHelp") : fundingDirectionText(modal.parchi?.direction, t) : modal.parchi?.issued_mode === "freight_financing" ? t("parchi.issuedFinanceRecoveryHelp") : settlementDirectionText(modal.parchi?.direction, t)}</p>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label={t("parchi.eventDate")} type="date" min={modal.parchi?.document_date} value={modal.eventDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("eventDate", value)} required />
                <Field label={t("parchi.amount")} type="number" min="0.01" step="0.01" value={modal.amount ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("amount", value)} required />
              </div>
              {modal.kind === "funding" && modal.parchi?.direction === "received" && <>
                <div className="rounded-xl border border-indigo-200 bg-indigo-50 p-3">
                  <p className="text-sm font-bold text-indigo-950">{t("parchi.receivedCommissionHelp")}</p>
                  <div className="mt-3 grid gap-4 sm:grid-cols-2">
                    <Field label={t("parchi.commissionWithheld")} type="number" min="0" step="0.01" value={modal.withheldCommission ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("withheldCommission", value)} required />
                    <div><span className={labelClass}>{t("parchi.actualCashDelivered")}</span><div dir="ltr" className="rounded-lg border border-slate-200 bg-white px-3 py-2.5 font-bold tabular-nums">{amountInputIsValid(modal.amount ?? "") && amountInputIsNonNegative(modal.withheldCommission ?? "") ? money(Number(modal.amount) - Number(modal.withheldCommission)) : "—"}</div></div>
                  </div>
                  <label className="mt-3 block"><span className={labelClass}>{t("parchi.fundingRoute")}</span>
                    <select className={control} value={modal.fundingRoute ?? ""} disabled={modal.uncertain} onChange={(event) => updateModal("fundingRoute", event.target.value)} required>
                      <option value="">{t("parchi.chooseFundingRoute")}</option>
                      <option value="direct_to_vehicle">{t("parchi.directToVehicle")}</option>
                      <option value="through_adda">{t("parchi.throughAdda")}</option>
                    </select>
                  </label>
                  <label className={`mt-3 flex items-start gap-2 text-sm font-semibold ${modal.parchi.booking_id ? "text-slate-800" : "text-slate-400"}`}>
                    <input type="checkbox" className="mt-1" checked={modal.settleVehicle ?? false} disabled={modal.uncertain || !modal.parchi.booking_id} onChange={(event) => setModal((current) => current ? { ...current, settleVehicle: event.target.checked, loadingId: "", requestId: current.uncertain ? current.requestId : makeRequestId() } : current)} />
                    <span>{t("parchi.settleLinkedVehicle")}{!modal.parchi.booking_id ? ` — ${t("parchi.errors.vehicleLinkRequired")}` : ""}</span>
                  </label>
                  {modal.settleVehicle && modal.parchi.booking_id && <label className="mt-3 block"><span className={labelClass}>{t("parchi.linkedLoading")}</span>
                    <select className={control} value={modal.loadingId ?? ""} disabled={modal.uncertain || loadingOptionsBusy || loadingOptionsError} onChange={(event) => updateModal("loadingId", event.target.value)}>
                      <option value="">{t("parchi.noLinkedLoading")}</option>
                      {loadingOptions.map((loading) => <option key={loading.id} value={loading.id}>{loading.loading_no || loading.id}</option>)}
                    </select>
                    {loadingOptionsBusy && <span className="mt-1 block text-xs text-slate-500">{t("parchi.loading")}</span>}
                    {loadingOptionsError && <span role="alert" className="mt-1 block text-xs font-semibold text-rose-700">{t("parchi.errors.loadingReferences")}</span>}
                  </label>}
                </div>
              </>}
              {modal.kind === "funding" && modal.parchi?.issued_mode === "freight_financing" && <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-3">
                <p className="text-sm font-bold text-emerald-950">{t("parchi.commissionEarned")}</p>
                <div className="mt-3 grid gap-4 sm:grid-cols-2">
                  <Field label={t("parchi.upfrontCommission")} type="number" min="0" step="0.01" value={modal.withheldCommission ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("withheldCommission", value)} required />
                  <div><span className={labelClass}>{t("parchi.actualCashDisbursed")}</span><div dir="ltr" className="rounded-lg border border-slate-200 bg-white px-3 py-2.5 font-bold tabular-nums">{amountInputIsValid(modal.amount ?? "") && amountInputIsNonNegative(modal.withheldCommission ?? "") ? money(Number(modal.amount) - Number(modal.withheldCommission)) : "—"}</div></div>
                </div>
              </div>}
              {modal.kind === "settlement" && modal.parchi?.issued_mode === "freight_financing" && <label className="block"><span className={labelClass}>{t("parchi.recoveryPayer")}</span><select className={control} required value={modal.recoveryPayerType ?? ""} disabled={modal.uncertain} onChange={(event) => updateModal("recoveryPayerType", event.target.value)}><option value="">{t("parchi.chooseCounterparty")}</option><option value="primary_payer">{t("parchi.primaryPayer")} · {modal.parchi.primary_payer_name ?? modal.parchi.counterparty_name ?? "—"}</option><option value="secondary_person">{t("parchi.secondaryResponsible")} · {modal.parchi.responsible_person_name ?? "—"}</option></select><span className="mt-1 block text-xs text-slate-500">{t("parchi.recourseOnlyNote")}</span></label>}
              <label className="block"><span className={labelClass}>{t("parchi.paymentMethod")}</span><select className={control} value={modal.paymentMethod ?? "Cash"} disabled={modal.uncertain} onChange={(event) => updateModal("paymentMethod", event.target.value)}>{paymentMethods.map((method) => <option key={method}>{method}</option>)}</select></label>
              <Field label={t("parchi.referenceNo")} mode="identifier" value={modal.referenceNo ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("referenceNo", value)} />
            </>}
            {modal.kind === "amend" && <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label={t("parchi.documentAmount")} type="number" min={String(Number(modal.parchi?.net_funded ?? 0))} step="0.01" value={modal.documentAmount ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("documentAmount", value)} required />
                <Field label={t("parchi.fundingDueDate")} type="date" min={modal.parchi?.document_date} value={modal.fundingDueDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("fundingDueDate", value)} hint={t("parchi.fundingDueHelp")} />
                <Field label={t("parchi.settlementDueDate")} type="date" min={modal.parchi?.document_date} value={modal.settlementDueDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("settlementDueDate", value)} hint={t("parchi.settlementDueHelp")} />
              </div>
              <Field label={t("parchi.reason")} value={modal.reason ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("reason", value)} required />
            </>}
            {modal.kind === "recourse" && <>
              <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">{t("parchi.recourseOnlyNote")}</p>
              <Field label={t("parchi.eventDate")} type="date" min={modal.parchi?.document_date} value={modal.eventDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("eventDate", value)} required />
              <label className="block"><span className={labelClass}>{t("parchi.recourseTarget")}</span><select className={control} value={modal.recourseTarget ?? ""} required disabled={modal.uncertain} onChange={(event) => updateModal("recourseTarget", event.target.value)}><option value="">{t("parchi.chooseCounterparty")}</option><option value="primary_payer">{t("parchi.recoursePrimary")}</option><option value="secondary_person">{t("parchi.recourseSecondary")}</option></select></label>
              <Field label={t("parchi.reason")} value={modal.reason ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("reason", value)} required />
            </>}
            {(modal.kind === "cancel" || modal.kind === "reverse") && <>
              {modal.kind === "reverse" && <Field label={t("parchi.eventDate")} type="date" min={modal.originalEvent?.event_date ?? undefined} value={modal.eventDate ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("eventDate", value)} required />}
              <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">{modal.kind === "cancel" ? t("parchi.cancelNotice") : `${t("parchi.reverse")}: ${money(modal.originalEvent?.event_amount)}`}</p>
              <Field label={t("parchi.reason")} value={modal.reason ?? ""} disabled={modal.uncertain} onChange={(value) => updateModal("reason", value)} required />
            </>}
            {actionError && <div role="alert" className="rounded-lg border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800">{actionError}</div>}
            <div className="flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-4">
              {!modal.uncertain && <button type="button" className={buttonSecondary} onClick={() => { setModal(null); setActionError(""); }}>{t("parchi.close")}</button>}
              <button type="submit" className={buttonPrimary} disabled={actionBusy}>{modal.uncertain ? t("parchi.retrySameRequest") : modal.kind === "create" ? t("parchi.createDocument") : modal.kind === "amend" ? t("parchi.saveAmendment") : modal.kind === "cancel" ? t("parchi.confirmCancellation") : modal.kind === "reverse" ? t("parchi.confirmReversal") : modal.kind === "recourse" ? t("parchi.recordRecourse") : modal.kind === "funding" ? t("parchi.fund") : t("parchi.settle")}</button>
            </div>
          </form>
        </section>
      </div>}
    </div>
    {modulePrint.dialog}
    </>
  );
}

function DeadlineSummaryCard({ title, summary, selected, disabled, onClick, t }: {
  title: string;
  summary: ReturnType<typeof summarizeParchiDeadlines>;
  selected: boolean;
  disabled: boolean;
  onClick: () => void;
  t: (key: string) => string;
}) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      disabled={disabled}
      onClick={onClick}
      className={`rounded-2xl border bg-white p-4 text-start shadow-sm transition hover:border-emerald-400 hover:shadow ${selected ? "border-emerald-600 ring-2 ring-emerald-100" : "border-slate-200"} disabled:cursor-not-allowed disabled:opacity-60`}
    >
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-sm font-extrabold uppercase tracking-wide text-slate-700">{title}</h2>
        <div className="text-xl font-black tabular-nums text-slate-950">
          {summary.count} <span className="text-xs font-semibold text-slate-500">{t("parchi.uniqueParchis")}</span>
        </div>
      </div>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <div className="rounded-xl bg-slate-50 p-3">
          <p className="text-xs font-extrabold text-slate-700">{t("parchi.fundingDeadlineCount").replace("{count}", String(summary.fundingDocumentCount))}</p>
          <DeadlineAmount label={t("parchi.receivedFundingDue")} value={summary.receivedFundingDue} />
          <DeadlineAmount label={t("parchi.issuedFundingDue")} value={summary.issuedFundingDue} />
        </div>
        <div className="rounded-xl bg-slate-50 p-3">
          <p className="text-xs font-extrabold text-slate-700">{t("parchi.settlementDeadlineCount").replace("{count}", String(summary.settlementDocumentCount))}</p>
          <DeadlineAmount label={t("parchi.receivedPayable")} value={summary.receivedPayable} />
          <DeadlineAmount label={t("parchi.issuedReceivable")} value={summary.issuedReceivable} />
        </div>
      </div>
      <span className="sr-only">{selected ? t("parchi.clearDeadlineFilter") : t("parchi.filterByDeadline")}</span>
    </button>
  );
}

function DeadlineAmount({ label, value }: { label: string; value: number }) {
  return <div className="mt-2 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 text-xs">
    <span className="text-slate-600">{label}</span>
    <bdi dir="ltr" className="font-bold tabular-nums text-slate-950">{money(value)}</bdi>
  </div>;
}

function DeadlineLine({ label, deadline, t }: {
  label: string;
  deadline?: ParchiDeadline;
  t: (key: string) => string;
}) {
  const bucket = deadline?.bucket ?? "unverified";
  const badge = bucket === "due_today" ? t("parchi.dueToday")
    : bucket === "upcoming" ? t("parchi.upcoming")
      : bucket === "overdue" ? t("parchi.overdueByDays").replace("{days}", String(deadline?.daysOverdue ?? 0))
        : bucket === "inactive" ? t("parchi.noActiveDueBalance")
          : bucket === "unverified" ? t("parchi.deadlineUnverified")
            : "";
  const badgeClass = bucket === "overdue" ? "bg-rose-100 text-rose-800"
    : bucket === "due_today" ? "bg-amber-100 text-amber-900"
      : bucket === "upcoming" ? "bg-blue-50 text-blue-800"
        : bucket === "inactive" ? "bg-slate-100 text-slate-600"
          : "bg-slate-100 text-slate-600";
  return (
    <div className="mb-2 last:mb-0">
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="font-semibold text-slate-500">{label}:</span>
        <bdi dir="ltr" className="font-medium text-slate-800">{deadline?.date ?? t("parchi.print.notRecorded")}</bdi>
        {badge && <span className={`inline-flex rounded-full px-2 py-0.5 text-[10px] font-bold ${badgeClass}`}>{badge}</span>}
      </div>
      {deadline?.amount !== null && deadline?.amount !== undefined && (
        <div className="mt-0.5 text-[11px] text-slate-500">
          {t("parchi.deadlineAmount")}: <bdi dir="ltr" className="font-semibold text-slate-700">{money(deadline.amount)}</bdi>
        </div>
      )}
    </div>
  );
}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"><p className="text-xs font-bold uppercase tracking-wide text-slate-500">{label}</p><p className="mt-2 text-xl font-extrabold tabular-nums text-slate-900">{value}</p></div>;
}
function DetailMetric({ label, value, direction }: { label: string; value: string; direction?: "ltr" | "rtl" }) {
  return <div className="rounded-xl border border-slate-200 bg-white p-3"><div className="text-xs font-bold uppercase text-slate-500">{label}</div><div dir={direction} className="mt-1 text-base font-extrabold tabular-nums text-slate-900">{value}</div></div>;
}
function DetailField({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return <div><div className="text-[11px] font-bold uppercase tracking-wide text-slate-500">{label}</div><div className="mt-1 font-semibold text-slate-900">{value}</div>{hint && <p className="mt-1 text-xs text-slate-500">{hint}</p>}</div>;
}
function StatusBadge({ value, t }: { value: string; t: (key: string) => string }) {
  const color = value === "Fully Funded" || value === "Settled" ? "bg-emerald-50 text-emerald-800"
    : value === "Cancelled" ? "bg-slate-100 text-slate-600"
      : value === "Partially Funded" || value === "Partially Settled" ? "bg-amber-50 text-amber-800"
        : "bg-rose-50 text-rose-800";
  return <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-bold ${color}`}>{labelStatus(value, t)}</span>;
}
function Field({ label, value, onChange, type = "text", mode, hint, required = false, disabled = false, min, step }: {
  label: string; value: string; onChange: (value: string) => void; type?: string; mode?: "text" | "identifier" | "phone" | "cnic" | "amount" | "number" | "date" | "email"; hint?: string; required?: boolean; disabled?: boolean; min?: string; step?: string;
}) {
  const fieldMode = mode ?? (type === "date" ? "date" : type === "number" ? "amount" : type === "email" ? "email" : "text");
  return <label className="block"><span className={labelClass}>{label}</span><VoiceTypingField fieldLabel={label} mode={fieldMode}><input className={control} type={type} value={value} onChange={(event) => onChange(event.target.value)} required={required} disabled={disabled} min={min} step={step} /></VoiceTypingField>{hint && <span className="mt-1 block text-xs text-slate-500">{hint}</span>}</label>;
}
function modalTitle(modal: ParchiModal, t: (key: string) => string) {
  if (modal.kind === "create") return modal.direction === "received" ? t("parchi.newReceived") : modal.issuedMode === "freight_financing" ? t("parchi.newIssuedFinance") : t("parchi.newIssued");
  if (modal.kind === "funding") return t("parchi.fund");
  if (modal.kind === "settlement") return t("parchi.settle");
  if (modal.kind === "amend") return t("parchi.amend");
  if (modal.kind === "cancel") return t("parchi.cancelUnfunded");
  if (modal.kind === "recourse") return t("parchi.recordRecourse");
  return t("parchi.reverse");
}
function fundingDirectionText(direction: Direction | undefined, t: (key: string) => string) {
  return direction === "received" ? t("parchi.receivedFundingHelp") : t("parchi.issuedFundingHelp");
}
function settlementDirectionText(direction: Direction | undefined, t: (key: string) => string) {
  return direction === "received" ? t("parchi.receivedSettlementHelp") : t("parchi.issuedSettlementHelp");
}

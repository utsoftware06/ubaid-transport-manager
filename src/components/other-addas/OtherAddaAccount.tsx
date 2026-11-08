"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { isUserRole, USER_ROLES, type UserRole } from "@/config/navigation";
import { supabase } from "@/lib/supabase/client";
import { getOtherAdda, getOtherAddaBalances, getOtherAddaBiltyTrips, getOtherAddaDueReminders, getOtherAddaPayments, listOtherAddaTransactions, mapOtherAddaError } from "./api";
import OtherAddaEventModal from "./OtherAddaEventModal";
import OtherAddaCancelModal from "./OtherAddaCancelModal";
import OtherAddaPaymentForm from "./OtherAddaPaymentForm";
import OtherAddaPaymentReversalModal from "./OtherAddaPaymentReversalModal";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { printOtherAddaPaymentReceipt } from "./OtherAddaPaymentReceipt";
import type { DatabaseNumeric, OtherAdda, OtherAddaBalance, OtherAddaBiltyTrip, OtherAddaDueReminder, OtherAddaEventType, OtherAddaPayment, OtherAddaSide, OtherAddaTransaction } from "./types";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { bilingual, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import IssuedFreightParchiProjection from "@/components/parchi/IssuedFreightParchiProjection";

const control = "mt-2 w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 font-medium text-slate-950 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100";
const button = "rounded-lg border border-blue-200 bg-white px-4 py-2 font-bold text-blue-800 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50";
const panel = "rounded-xl border border-blue-100 bg-white p-5 shadow-sm";
const pageSize = 25;
type Filters = { from: string; to: string; side: OtherAddaSide | ""; event: OtherAddaEventType | "" };
type Context = { master: OtherAdda; role: UserRole; superAdmin: boolean; currentAddaName: string | null };

/** Exact cents for display/sign checks only. Never round or replace invalid data. */
function cents(value: DatabaseNumeric): bigint {
  const text = String(value);
  if (!/^-?\d+(?:\.\d{1,2})?$/.test(text)) throw new Error("Invalid account amount returned. Refresh or contact an admin.");
  const [whole, fraction = ""] = text.replace(/^-/, "").split(".");
  const amount = BigInt(whole) * BigInt(100) + BigInt(fraction.padEnd(2, "0"));
  if (typeof value === "number" && (!Number.isFinite(value) || amount > BigInt(Number.MAX_SAFE_INTEGER))) {
    throw new Error("Account amount cannot be displayed safely. Contact an admin.");
  }
  return text.startsWith("-") ? -amount : amount;
}
function money(value: DatabaseNumeric, reversal = false): string {
  const amount = cents(value) * (reversal ? BigInt(-1) : BigInt(1));
  const absolute = amount < BigInt(0) ? -amount : amount;
  const whole = String(absolute / BigInt(100)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${amount < BigInt(0) ? "-" : ""}Rs. ${whole}.${String(absolute % BigInt(100)).padStart(2, "0")}`;
}
function createdAt(value: string): string {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toLocaleString("en-PK") : value;
}
function calendarDate(value: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return value;
  const parsed = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return Number.isFinite(parsed.getTime()) ? parsed.toLocaleDateString("en-PK", {
    day: "2-digit", month: "short", year: "numeric", timeZone: "UTC",
  }) : value;
}

export default function OtherAddaAccount({ otherAddaId }: { otherAddaId: string }) {
  const { dir, language } = useLanguage();
  const validId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(otherAddaId);
  const [context, setContext] = useState<Context | null>(null);
  const [masterLoading, setMasterLoading] = useState(validId);
  const [masterError, setMasterError] = useState("");
  const [balance, setBalance] = useState<OtherAddaBalance | null>(null);
  const [balanceLoading, setBalanceLoading] = useState(false);
  const [balanceError, setBalanceError] = useState("");
  const [history, setHistory] = useState<OtherAddaTransaction[] | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState("");
  const [cancelledOriginalIds, setCancelledOriginalIds] = useState<Set<string> | null>(null);
  const [reminders, setReminders] = useState<OtherAddaDueReminder[] | null>(null);
  const [reminderLoading, setReminderLoading] = useState(false);
  const [reminderError, setReminderError] = useState("");
  const [payments, setPayments] = useState<OtherAddaPayment[] | null>(null);
  const [trips, setTrips] = useState<OtherAddaBiltyTrip[] | null>(null);
  const [tripLoading, setTripLoading] = useState(false);
  const [tripError, setTripError] = useState("");
  const [tripHasNext, setTripHasNext] = useState(false);
  const [tripPage, setTripPage] = useState(0);
  const [tripSearchDraft, setTripSearchDraft] = useState("");
  const [tripSearch, setTripSearch] = useState("");
  const [paymentLoading, setPaymentLoading] = useState(false);
  const [paymentError, setPaymentError] = useState("");
  const [hasNext, setHasNext] = useState(false);
  const [page, setPage] = useState(0);
  const [draft, setDraft] = useState<Filters>({ from: "", to: "", side: "", event: "" });
  const [filters, setFilters] = useState<Filters>(draft);
  const [search, setSearch] = useState("");
  const [eventSide, setEventSide] = useState<OtherAddaSide | null>(null);
  const [cancelEntry, setCancelEntry] = useState<OtherAddaTransaction | null>(null);
  const [paymentSide, setPaymentSide] = useState<OtherAddaSide | null>(null);
  const [paymentToReverse, setPaymentToReverse] = useState<OtherAddaPayment | null>(null);
  const [notice, setNotice] = useState("");
  const [statementPrinting, setStatementPrinting] = useState(false);
  const masterRequest = useRef(0);
  const balanceRequest = useRef(0);
  const historyRequest = useRef(0);
  const reminderRequest = useRef(0);
  const paymentRequest = useRef(0);
  const tripRequest = useRef(0);
  const cancelMaster = useCallback(() => {
    ++masterRequest.current; ++balanceRequest.current; ++historyRequest.current; ++reminderRequest.current; ++paymentRequest.current; ++tripRequest.current;
  }, []);
  const cancelBalance = useCallback(() => { ++balanceRequest.current; }, []);
  const cancelHistory = useCallback(() => { ++historyRequest.current; }, []);
  const cancelReminders = useCallback(() => { ++reminderRequest.current; }, []);
  const cancelPayments = useCallback(() => { ++paymentRequest.current; }, []);
  const cancelTrips = useCallback(() => { ++tripRequest.current; }, []);
  const modulePrint = useModuleTransportPrint("other_adda_receipt", context?.master.adda_id ?? null, language === "ur" ? "ur" : "en");

  const loadMaster = useCallback(async () => {
    if (!validId) return;
    const request = ++masterRequest.current;
    ++balanceRequest.current; ++historyRequest.current; ++reminderRequest.current; ++paymentRequest.current; ++tripRequest.current;
    setMasterLoading(true); setMasterError(""); setContext(null);
    setBalance(null); setHistory(null); setCancelledOriginalIds(null); setReminders(null); setPayments(null); setTrips(null);
    setTripPage(0); setTripSearch(""); setTripSearchDraft(""); setTripError("");
    setEventSide(null); setCancelEntry(null); setPaymentSide(null); setPaymentToReverse(null);
    try {
      const master = await getOtherAdda(otherAddaId);
      if (!master) throw new Error("Other Adda not found or you do not have access.");
      const addaNameResult = await supabase.from("addas").select("name").eq("id", master.adda_id).maybeSingle();
      const currentAddaName = !addaNameResult.error && typeof addaNameResult.data?.name === "string"
        ? addaNameResult.data.name : null;
      // Existing browser profile pattern; this only chooses RPC arguments.
      const auth = await supabase.auth.getUser();
      if (auth.error) throw auth.error;
      if (!auth.data.user) throw new Error("An active signed-in account is required.");
      const response = await supabase.from("profiles").select("role,is_active").eq("id", auth.data.user.id).single();
      if (response.error) throw response.error;
      if (!response.data?.is_active || !isUserRole(response.data.role)) throw new Error("An active supported profile is required.");
      if (request === masterRequest.current) setContext({ master, role: response.data.role, superAdmin: response.data.role === USER_ROLES.superAdmin, currentAddaName });
    } catch (failure) {
      if (request === masterRequest.current) setMasterError(mapOtherAddaError(failure).message);
    } finally { if (request === masterRequest.current) setMasterLoading(false); }
  }, [otherAddaId, validId]);

  const loadBalance = useCallback(async (): Promise<boolean> => {
    if (!context) return false;
    const request = ++balanceRequest.current;
    setBalanceLoading(true); setBalanceError(""); setBalance(null);
    try {
      const rows = await getOtherAddaBalances(context.superAdmin ? { target_adda_id: context.master.adda_id } : {});
      const matches = rows.filter((row) => row.other_adda_id === context.master.id);
      if (matches.length !== 1) throw new Error("The authoritative balance for this Other Adda is unavailable. Retry or contact an admin.");
      const row = matches[0];
      if (cents(row.gross_receivable) < BigInt(0) || cents(row.gross_payable) < BigInt(0)) throw new Error("Invalid gross balance returned. Contact an admin.");
      cents(row.net);
      if (request === balanceRequest.current) { setBalance(row); return true; }
    } catch (failure) {
      if (request === balanceRequest.current) setBalanceError(mapOtherAddaError(failure).message);
      return false;
    } finally { if (request === balanceRequest.current) setBalanceLoading(false); }
    return false;
  }, [context]);

  const loadHistory = useCallback(async (): Promise<boolean> => {
    if (!context) return false;
    const request = ++historyRequest.current;
    setHistoryLoading(true); setHistoryError(""); setHistory(null); setCancelledOriginalIds(null); setHasNext(false);
    try {
      const rows = await listOtherAddaTransactions({ other_adda_id: context.master.id,
        offset: page * pageSize, limit: pageSize + 1, date_from: filters.from || undefined,
        date_to: filters.to || undefined, side: filters.side || undefined, event_type: filters.event || undefined });
      for (const row of rows) {
        if (row.other_adda_id !== context.master.id || row.adda_id !== context.master.adda_id) throw new Error("Account history scope mismatch.");
        if (cents(row.amount) <= BigInt(0)) throw new Error("Invalid history amount returned.");
      }
      const pageRows = rows.slice(0, pageSize);
      const originalIds = pageRows.filter((row) => row.event_type === "obligation").map((row) => row.id);
      const reversalRows = originalIds.length ? await listOtherAddaTransactions({
        other_adda_id: context.master.id, event_type: "reversal",
        reverses_transaction_ids: originalIds, offset: 0, limit: originalIds.length,
      }) : [];
      const cancelled = new Set<string>();
      for (const reversal of reversalRows) {
        if (reversal.other_adda_id !== context.master.id || reversal.adda_id !== context.master.adda_id || !reversal.reverses_transaction_id || !originalIds.includes(reversal.reverses_transaction_id)) {
          throw new Error("Entry Cancel evidence scope mismatch.");
        }
        cancelled.add(reversal.reverses_transaction_id);
      }
      if (request === historyRequest.current) { setHistory(pageRows); setCancelledOriginalIds(cancelled); setHasNext(rows.length > pageSize); return true; }
    } catch (failure) {
      if (request === historyRequest.current) setHistoryError(mapOtherAddaError(failure).message);
      return false;
    } finally { if (request === historyRequest.current) setHistoryLoading(false); }
    return false;
  }, [context, page, filters]);

  const loadReminders = useCallback(async (): Promise<boolean> => {
    if (!context) return false;
    const request = ++reminderRequest.current;
    setReminderLoading(true); setReminderError(""); setReminders(null);
    try {
      // Omit as-of date deliberately: the deployed RPC uses its deterministic Asia/Karachi fallback.
      const rows = await getOtherAddaDueReminders(context.master.id);
      for (const row of rows) {
        if (cents(row.amount) <= BigInt(0)) throw new Error("Invalid reminder amount returned.");
      }
      if (request === reminderRequest.current) { setReminders(rows); return true; }
    } catch (failure) {
      if (request === reminderRequest.current) setReminderError(mapOtherAddaError(failure).message);
      return false;
    } finally { if (request === reminderRequest.current) setReminderLoading(false); }
    return false;
  }, [context]);

  const loadPayments = useCallback(async (): Promise<boolean> => {
    if (!context) return false;
    const request = ++paymentRequest.current;
    setPaymentLoading(true); setPaymentError(""); setPayments(null);
    try {
      const rows = await getOtherAddaPayments(context.master.id);
      for (const row of rows) {
        if (row.event_type === "payment" && row.reverses_payment_id !== null) throw new Error("Invalid payment reversal identity returned.");
        if (row.event_type === "reversal" && row.reverses_payment_id === null) throw new Error("Invalid payment reversal identity returned.");
        if (cents(row.amount) <= BigInt(0)) throw new Error("Invalid payment amount returned.");
      }
      if (request === paymentRequest.current) { setPayments(rows); return true; }
    } catch (failure) {
      if (request === paymentRequest.current) setPaymentError(mapOtherAddaError(failure).message);
      return false;
    } finally { if (request === paymentRequest.current) setPaymentLoading(false); }
    return false;
  }, [context]);

  const loadTrips = useCallback(async (): Promise<boolean> => {
    if (!context) return false;
    const request = ++tripRequest.current;
    setTripLoading(true); setTripError(""); setTrips(null); setTripHasNext(false);
    try {
      const rows = await getOtherAddaBiltyTrips({
        other_adda_id: context.master.id,
        search: tripSearch,
        offset: tripPage * pageSize,
        limit: pageSize,
      });
      const pageRows = rows.slice(0, pageSize);
      for (const row of rows) {
        if (row.booking_id === "" || (row.loading_source_other_adda_id !== context.master.id
          && row.freight_receivable_other_adda_id !== context.master.id)) {
          throw new Error("Bilty trip response scope mismatch.");
        }
        cents(row.freight);
        if (row.has_financial_obligation && (!row.obligation_transaction_id || row.received === null || row.balance === null)) {
          throw new Error("Linked Other Adda settlement evidence is incomplete.");
        }
      }
      const enriched = await Promise.all(pageRows.map(async (row) => {
        if (row.freight_receivable_from !== "existing_counterparty") return row;
        const response = await supabase.rpc("get_bilty_financial_summary", { p_bilty_id: row.booking_id });
        if (response.error) throw response.error;
        const summary = (Array.isArray(response.data) ? response.data[0] : response.data) as {
          total_received?: DatabaseNumeric;
          balance_receivable?: DatabaseNumeric;
          payment_status?: string;
        } | null;
        if (!summary || summary.total_received === undefined || summary.balance_receivable === undefined || !summary.payment_status) {
          throw new Error("Existing Party/Broker settlement summary is unavailable.");
        }
        cents(summary.total_received);
        cents(summary.balance_receivable);
        return {
          ...row,
          received: summary.total_received,
          balance: summary.balance_receivable,
          payment_status: summary.payment_status,
        };
      }));
      if (request === tripRequest.current) {
        setTrips(enriched);
        setTripHasNext(rows.length > pageSize);
        return true;
      }
    } catch (failure) {
      if (request === tripRequest.current) setTripError(mapOtherAddaError(failure).message);
      return false;
    } finally { if (request === tripRequest.current) setTripLoading(false); }
    return false;
  }, [context, tripPage, tripSearch]);

  useEffect(() => {
    const timer = window.setTimeout(() => { void loadMaster(); }, 0);
    return () => { window.clearTimeout(timer); cancelMaster(); };
  }, [loadMaster, cancelMaster]);
  useEffect(() => {
    const timer = window.setTimeout(() => { void loadBalance(); }, 0);
    return () => { window.clearTimeout(timer); cancelBalance(); };
  }, [loadBalance, cancelBalance]);
  useEffect(() => {
    const timer = window.setTimeout(() => { void loadHistory(); }, 0);
    return () => { window.clearTimeout(timer); cancelHistory(); };
  }, [loadHistory, cancelHistory]);
  useEffect(() => {
    const timer = window.setTimeout(() => { void loadReminders(); }, 0);
    return () => { window.clearTimeout(timer); cancelReminders(); };
  }, [loadReminders, cancelReminders]);
  useEffect(() => {
    const timer = window.setTimeout(() => { void loadPayments(); }, 0);
    return () => { window.clearTimeout(timer); cancelPayments(); };
  }, [loadPayments, cancelPayments]);
  useEffect(() => {
    const timer = window.setTimeout(() => { void loadTrips(); }, 0);
    return () => { window.clearTimeout(timer); cancelTrips(); };
  }, [loadTrips, cancelTrips]);

  const master = context?.master;
  const term = search.trim().toLocaleLowerCase();
  const visible = history?.filter((row) => `${row.description} ${row.reference_no ?? ""}`.toLocaleLowerCase().includes(term));
  const canCancel = context?.master.status === "active" && (context.role === USER_ROLES.superAdmin || context.role === USER_ROLES.addaAdmin);
  const reversedPaymentIds = new Set((payments ?? []).flatMap((row) => row.event_type === "reversal" && row.reverses_payment_id ? [row.reverses_payment_id] : []));
  const net = balance ? cents(balance.net) : null;
  const reminderGroups = reminders ? (["overdue", "due_today", "upcoming"] as const).map((status) => ({
    status, rows: reminders.filter((row) => row.due_status === status),
  })) : [];
  async function posted() {
    setEventSide(null);
    setNotice("Entry saved. Refreshing authoritative account data…");
    const [balanceOk, historyOk, remindersOk, paymentsOk, tripsOk] = await Promise.all([loadBalance(), loadHistory(), loadReminders(), loadPayments(), loadTrips()]);
    const failed = [!balanceOk && "balances", !historyOk && "obligation history", !remindersOk && "due reminders", !paymentsOk && "payment history", !tripsOk && "trips"].filter(Boolean);
    setNotice(failed.length === 0 ? "Entry saved and account refreshed." : `Entry saved, but ${failed.join(", ")} refresh failed. Refresh the account.`);
  }
  async function paymentPosted() {
    setPaymentSide(null);
    setNotice("Payment posted. Refreshing authoritative account data…");
    const [balanceOk, historyOk, remindersOk, paymentsOk, tripsOk] = await Promise.all([loadBalance(), loadHistory(), loadReminders(), loadPayments(), loadTrips()]);
    const failed = [!balanceOk && "balances", !historyOk && "obligation history", !remindersOk && "due reminders", !paymentsOk && "payment history", !tripsOk && "trips"].filter(Boolean);
    setNotice(failed.length === 0 ? "Payment posted and account refreshed." : `Payment posted, but ${failed.join(", ")} refresh failed. Refresh the account.`);
  }
  async function paymentReversed() {
    setPaymentToReverse(null);
    setNotice("Payment reversal posted. Refreshing authoritative account data…");
    const [balanceOk, historyOk, remindersOk, paymentsOk, tripsOk] = await Promise.all([loadBalance(), loadHistory(), loadReminders(), loadPayments(), loadTrips()]);
    const failed = [!balanceOk && "balances", !historyOk && "obligation history", !remindersOk && "due reminders", !paymentsOk && "payment history", !tripsOk && "trips"].filter(Boolean);
    setNotice(failed.length === 0 ? "Payment reversed and account refreshed." : `Payment reversed, but ${failed.join(", ")} refresh failed. Refresh the account.`);
  }

  function printOtherAddaPayment(payment: OtherAddaPayment) {
    if (!context) return;
    const reversed = payment.event_type === "reversal";
    const cashDirection = (payment.side === "receivable") !== reversed ? "Cash In" : "Cash Out";
    const presentation: ModulePrintPresentation = {
      documentType: "other_adda_receipt",
      title: bilingual("Other Adda Payment Receipt", "دوسرے اڈے کی ادائیگی رسید"),
      documentNo: printValue(payment.reference_no ?? payment.id.slice(0, 8)),
      documentDate: printValue(payment.payment_date),
      fields: [
        { label: bilingual("Other Adda", "دوسرا اڈا"), value: printValue(context.master.adda_name) },
        { label: bilingual("Payment side", "ادائیگی کی قسم"), value: bilingual(payment.side === "receivable" ? "LENA received" : "DENA paid", payment.side === "receivable" ? "لینا وصول" : "دینا ادا") },
        { label: bilingual("Cashbook direction", "کیش بک سمت"), value: bilingual(cashDirection, cashDirection === "Cash In" ? "کیش اِن" : "کیش آؤٹ") },
        { label: bilingual("Amount", "رقم"), value: printValue(money(payment.amount)) },
        { label: bilingual("Payment method", "ادائیگی کا طریقہ"), value: printValue(payment.payment_method) },
        { label: bilingual("Event", "اندراج"), value: bilingual(reversed ? "Reversal" : "Payment", reversed ? "واپسی" : "ادائیگی") },
        ...(payment.reverses_payment_id ? [{ label: bilingual("Reverses payment", "منسوخ شدہ ادائیگی"), value: printValue(payment.reverses_payment_id.slice(0, 8)) }] : []),
      ],
      remarks: printValue(payment.remarks),
    };
    modulePrint.openPresentation(presentation, () => printOtherAddaPaymentReceipt({ payment, addaId: context.master.adda_id, otherAddaName: context.master.adda_name, currentAddaName: context.currentAddaName, dir }), context.master.adda_id);
  }

  async function printAccountStatement() {
    if (!context || statementPrinting) return;
    const request = masterRequest.current;
    const scopeId = context.master.id;
    setStatementPrinting(true);
    setHistoryError("");
    try {
      const allTransactions: OtherAddaTransaction[] = [];
      const batchSize = 1000;
      for (let offset = 0; offset < 100_000; offset += batchSize) {
        const batch = await listOtherAddaTransactions({
          other_adda_id: scopeId, offset, limit: batchSize,
          date_from: filters.from || undefined, date_to: filters.to || undefined,
          side: filters.side || undefined, event_type: filters.event || undefined,
        });
        for (const row of batch) {
          if (row.other_adda_id !== scopeId || row.adda_id !== context.master.adda_id) throw new Error("Account history scope mismatch.");
        }
        allTransactions.push(...batch);
        if (batch.length < batchSize) break;
        if (offset + batchSize >= 100_000) throw new Error("Account statement exceeds the safe print limit. Narrow the date range.");
      }
      const allPayments = await getOtherAddaPayments(scopeId);
      if (request !== masterRequest.current || context.master.id !== otherAddaId) return;
      const balances = await getOtherAddaBalances(context.superAdmin ? { target_adda_id: context.master.adda_id } : {});
      const accountBalance = balances.find((row) => row.other_adda_id === scopeId);
      if (!accountBalance) throw new Error("Authoritative balance for this Other Adda is unavailable.");
      const period = filters.from || filters.to ? `${filters.from || "—"} — ${filters.to || "—"}` : "All dates";
      const statement: ModulePrintPresentation = {
        documentType: "other_adda_receipt",
        title: bilingual("Other Adda Account Statement", "دوسرے اڈے کا اکاؤنٹ اسٹیٹمنٹ"),
        subtitle: bilingual(`Obligations and payments · ${period}`, `واجبات اور ادائیگیاں · ${period}`),
        fields: [{ label: bilingual("Other Adda", "دوسرا اڈا"), value: printValue(context.master.adda_name) }],
        totals: [
          { label: bilingual("Receivable (LENA)", "قابل وصول (لینا)"), value: printValue(money(accountBalance.gross_receivable)) },
          { label: bilingual("Payable (DENA)", "قابل ادائیگی (دینا)"), value: printValue(money(accountBalance.gross_payable)) },
          { label: bilingual("Net balance", "خالص بیلنس"), value: printValue(money(accountBalance.net)) },
          { label: bilingual("Effective obligations", "موثر واجبات"), value: printValue(accountBalance.effective_obligation_count) },
        ],
        tables: [
          {
            title: bilingual("Append-only obligations and reversals", "واجبات اور واپسیوں کی تاریخ"),
            columns: ["Date", "Due date", "Side", "Reference", "Description", "LENA", "DENA", "Event"].map((en) => bilingual(en, ({ Date: "تاریخ", "Due date": "واجب الادا تاریخ", Side: "قسم", Reference: "حوالہ", Description: "تفصیل", LENA: "لینا", DENA: "دینا", Event: "اندراج" } as Record<string, string>)[en])),
            rows: allTransactions.map((row) => [
              printValue(row.transaction_date), printValue(row.event_type === "obligation" ? row.due_date : null),
              bilingual(row.side === "receivable" ? "LENA" : "DENA", row.side === "receivable" ? "لینا" : "دینا"),
              printValue(row.reference_no), printValue(row.description),
              row.side === "receivable" ? money(row.amount, row.event_type === "reversal") : "—",
              row.side === "payable" ? money(row.amount, row.event_type === "reversal") : "—",
              bilingual(row.event_type === "reversal" ? "Reversal" : "Obligation", row.event_type === "reversal" ? "واپسی" : "واجب"),
            ]),
          },
          {
            title: bilingual("Payments and Cashbook events", "ادائیگیاں اور کیش بک اندراجات"),
            columns: ["Date", "Side", "Amount", "Cashbook direction", "Method", "Reference", "Event", "Remarks"].map((en) => bilingual(en, ({ Date: "تاریخ", Side: "قسم", Amount: "رقم", "Cashbook direction": "کیش بک سمت", Method: "طریقہ", Reference: "حوالہ", Event: "اندراج", Remarks: "ریمارکس" } as Record<string, string>)[en])),
            rows: allPayments.map((payment) => {
              const reversed = payment.event_type === "reversal";
              const cashDirection = (payment.side === "receivable") !== reversed ? "Cash In" : "Cash Out";
              return [
                printValue(payment.payment_date), bilingual(payment.side === "receivable" ? "LENA received" : "DENA paid", payment.side === "receivable" ? "لینا وصول" : "دینا ادا"),
                printValue(money(payment.amount)), bilingual(cashDirection, cashDirection === "Cash In" ? "کیش اِن" : "کیش آؤٹ"), printValue(payment.payment_method),
                printValue(payment.reference_no), bilingual(reversed ? "Reversal" : "Payment", reversed ? "واپسی" : "ادائیگی"), printValue(payment.remarks),
              ];
            }),
          },
        ],
      };
      modulePrint.openPresentation(statement, () => undefined, context.master.adda_id);
    } catch (failure) {
      setHistoryError(mapOtherAddaError(failure).message);
    } finally { if (request === masterRequest.current) setStatementPrinting(false); }
  }
  async function cancelled() {
    setCancelEntry(null);
    setNotice("Entry cancelled. Refreshing authoritative account data…");
    const [balanceOk, historyOk, remindersOk, tripsOk] = await Promise.all([loadBalance(), loadHistory(), loadReminders(), loadTrips()]);
    const failed = [!balanceOk && "balances", !historyOk && "history", !remindersOk && "due reminders", !tripsOk && "trips"].filter(Boolean);
    setNotice(failed.length === 0 ? "Entry cancelled and account refreshed." : `Entry cancelled, but ${failed.join(", ")} refresh failed. Refresh the account.`);
  }

  return <main dir={dir} className="ut-module-page mx-auto max-w-[1500px] space-y-6 text-slate-950">
    <header className={`${panel} space-y-4`}><Link href="/other-addas" className="inline-flex rounded-lg px-2 py-1 font-bold text-blue-700 hover:bg-blue-50 hover:underline">← Back to Other Adda</Link><ModulePageHeading icon="otherAdda" accent="purple" title="Other Adda Account" description="Obligations and settlements · both LENA and DENA sides remain separate." /></header>
    {!validId && <p role="alert" className={panel}>Select a valid Other Adda from the master screen. The account URL requires a valid otherAddaId UUID.</p>}
    {validId && masterLoading && <p role="status" className={panel}>Loading Other Adda…</p>}
    {validId && masterError && <div role="alert" className={`${panel} border-red-200 text-red-800`}>{masterError}<button type="button" onClick={() => void loadMaster()} className={`${button} ms-3`}>Retry Account</button></div>}
    {master && <>
      <section className={panel}><div className="flex flex-wrap items-center justify-between gap-4"><div className="flex flex-wrap items-center gap-3"><h2 className="text-2xl font-extrabold">{master.adda_name}</h2><span className="rounded-full border border-blue-200 bg-blue-50 px-3 py-1 font-bold text-blue-900">{master.business_type === "regular" ? "Regular" : "One-Time"}</span><span className={`rounded-full border px-3 py-1 font-bold ${master.status === "archived" ? "border-amber-200 bg-amber-50 text-amber-900" : "border-emerald-200 bg-emerald-50 text-emerald-900"}`}>{master.status === "archived" ? "Archived" : "Active"}</span></div>{master.status === "active" && <div className="flex flex-wrap gap-2"><button type="button" onClick={() => { setNotice(""); setEventSide("receivable"); }} className="rounded-lg bg-emerald-600 px-4 py-2.5 font-bold text-white hover:bg-emerald-700">+ Add LENA</button><button type="button" onClick={() => { setNotice(""); setEventSide("payable"); }} className="rounded-lg bg-amber-600 px-4 py-2.5 font-bold text-white hover:bg-amber-700">+ Add DENA</button></div>}</div><dl className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{[["Contact Person", master.contact_person], ["Mobile", master.mobile], ["City", master.city], ["WhatsApp", master.whatsapp], ["Address", master.address], ["NTN/CNIC", master.ntn_cnic]].map(([label, value]) => <div key={label}><dt className="font-bold text-blue-800">{label}</dt><dd className="mt-1 break-words">{value || "—"}</dd></div>)}</dl>{master.notes && <p className="mt-4 whitespace-pre-wrap">{master.notes}</p>}{master.status === "archived" && <p className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 font-semibold text-amber-950">Archived accounts cannot receive new entries. Reactivate this Other Adda from the master screen to add LENA or DENA.</p>}</section>
      {notice && <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 font-semibold text-emerald-900">{notice}</p>}
      <section aria-label="Authoritative account balances" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="text-xl font-extrabold">Account Summary</h2><div className="flex gap-2"><button type="button" disabled={statementPrinting || !balance} onClick={() => void printAccountStatement()} className={button}>{statementPrinting ? "Preparing statement…" : "Print Account Statement"}</button><button type="button" disabled={balanceLoading} onClick={() => void loadBalance()} className={button}>Refresh Balances</button></div></div>
        {balanceLoading && <p role="status" className={panel}>Loading authoritative balances…</p>}
        {balanceError && <div role="alert" className={`${panel} border-red-200 text-red-800`}>{balanceError}<button type="button" disabled={balanceLoading} onClick={() => void loadBalance()} className={`${button} ms-3`}>Retry Balances</button></div>}
        {balance && <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{[["LENA HAI", "Receivable", money(balance.gross_receivable)], ["DENA HAI", "Payable", money(balance.gross_payable)], ["Net Balance", net !== null && net > BigInt(0) ? "Net LENA HAI" : net !== null && net < BigInt(0) ? "Net DENA HAI" : "Account Balanced", money(balance.net)]].map(([title, subtitle, value]) => <article key={title} className={panel}><h3 className="font-extrabold text-blue-800">{title}</h3><p className="mt-1 font-medium">{subtitle}</p><p dir="ltr" className="mt-3 break-words text-2xl font-extrabold">{value}</p></article>)}<article className={panel}><h3 className="font-extrabold text-blue-800">Entries</h3><dl className="mt-3 space-y-2">{[["Asal Entries", balance.obligation_count], ["Entry Cancels", balance.reversal_count], ["Effective entries", balance.effective_obligation_count]].map(([label, value]) => <div key={label} className="flex justify-between gap-3"><dt>{label}</dt><dd dir="ltr" className="font-extrabold">{String(value)}</dd></div>)}</dl></article></div>}
      </section>
      <section aria-label="Due reminders" className={panel}>
        <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-xl font-extrabold">Due Reminders</h2><p className="mt-1 font-medium text-slate-700">Effective due entries only. These are reminders, not payment or settlement status.</p></div><button type="button" disabled={reminderLoading} onClick={() => void loadReminders()} className={button}>Refresh Reminders</button></div>
        {reminderLoading && <p role="status" className="mt-4 rounded-lg bg-blue-50 p-4 font-bold text-blue-900">Loading due reminders…</p>}
        {reminderError && <div role="alert" className="mt-4 rounded-lg border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{reminderError}<button type="button" disabled={reminderLoading} onClick={() => void loadReminders()} className={`${button} ms-3`}>Retry Reminders</button></div>}
        {!reminderLoading && !reminderError && reminders && <>
          <div className="mt-4 grid gap-3 sm:grid-cols-3">{reminderGroups.map(({ status, rows }) => <article key={status} className={`rounded-xl border p-4 ${status === "overdue" ? "border-red-200 bg-red-50 text-red-950" : status === "due_today" ? "border-amber-200 bg-amber-50 text-amber-950" : "border-blue-200 bg-blue-50 text-blue-950"}`}><h3 className="font-extrabold">{status === "overdue" ? "Overdue" : status === "due_today" ? "Due Today" : "Upcoming"}</h3><p className="mt-1 text-2xl font-extrabold" dir="ltr">{rows.length}</p></article>)}</div>
          {reminders.length === 0 ? <p className="mt-4 rounded-lg border border-blue-100 bg-blue-50 p-5 font-bold text-blue-900">No due entries.</p> : <div className="mt-5 space-y-5">{reminderGroups.filter(({ rows }) => rows.length > 0).map(({ status, rows }) => <div key={status}><h3 className="mb-3 text-lg font-extrabold">{status === "overdue" ? "Overdue" : status === "due_today" ? "Due Today" : "Upcoming"}</h3><div className="grid gap-3 lg:grid-cols-2">{rows.map((row) => <article key={row.transaction_id} className={`rounded-xl border p-4 ${status === "overdue" ? "border-red-200 bg-red-50" : status === "due_today" ? "border-amber-200 bg-amber-50" : "border-blue-200 bg-blue-50"}`}><div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-extrabold">{row.side === "receivable" ? "LENA HAI" : "DENA HAI"}</p><p dir="ltr" className="mt-1 text-xl font-extrabold">{money(row.amount)}</p></div><div className="text-end"><p className="font-bold">Due: {calendarDate(row.due_date)}</p><p className="mt-1 font-extrabold">{status === "overdue" ? `${row.days_overdue} ${row.days_overdue === 1 ? "day" : "days"} overdue` : status === "due_today" ? "Due today" : `Due in ${row.days_remaining} ${row.days_remaining === 1 ? "day" : "days"}`}</p></div></div>{row.reference_no && <p className="mt-3 font-semibold">Reference: {row.reference_no}</p>}<p className="mt-2 whitespace-pre-wrap break-words">{row.description}</p></article>)}</div></div>)}</div>}
        </>}
      </section>
      <IssuedFreightParchiProjection addaId={master.adda_id} payerType="other_adda" payerId={master.id} />
      <section aria-label="Loadings and trips" className={panel}>
        <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-xl font-extrabold">Loadings / Trips</h2><p className="mt-1 font-medium text-slate-700">Operational trips are shown when this Other Adda supplied the loading or is the freight receivable party.</p></div><button type="button" disabled={tripLoading} onClick={() => void loadTrips()} className={button}>Refresh Trips</button></div>
        <form onSubmit={(event) => { event.preventDefault(); setTripPage(0); setTripSearch(tripSearchDraft.trim()); }} className="mt-4 flex flex-wrap items-end gap-3">

          <VoiceTypingField fieldLabel="Search Bilty, vehicle or route" mode="text"><label className="min-w-[260px] flex-1 font-bold">Search Bilty, vehicle or route<input type="search" value={tripSearchDraft} onChange={(event) => setTripSearchDraft(event.target.value)} className={control} /></label></VoiceTypingField>

          <button type="submit" disabled={tripLoading} className={button}>Search Trips</button>
        </form>
        {tripLoading && <p role="status" className="mt-4 rounded-lg bg-blue-50 p-4 font-bold text-blue-900">Loading trips…</p>}
        {tripError && <div role="alert" className="mt-4 rounded-lg border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{tripError}<button type="button" disabled={tripLoading} onClick={() => void loadTrips()} className={`${button} ms-3`}>Retry Trips</button></div>}
        {!tripLoading && !tripError && trips !== null && <>
          {trips.length === 0 ? <p className="mt-4 rounded-lg border border-blue-100 bg-blue-50 p-5 font-bold text-blue-900">No linked trips found for this Other Adda.</p> : <div className="mt-4 overflow-x-auto"><table className="w-full min-w-[1500px]"><thead className="bg-blue-600 text-white"><tr>{["Date", "Bilty No", "Vehicle", "From", "To", "Trip Type", "Freight", "Receivable From", "Received", "Balance", "Status", "Open Bilty"].map((label) => <th key={label} className="p-3 text-start font-bold">{label}</th>)}</tr></thead><tbody>{trips.map((trip) => <tr key={trip.booking_id} className="border-b hover:bg-blue-50/50">
            <td dir="ltr" className="whitespace-nowrap p-3">{calendarDate(trip.loading_date ?? trip.booking_date)}</td>
            <td dir="ltr" className="whitespace-nowrap p-3 font-bold">{trip.booking_no}</td>
            <td className="p-3">{trip.vehicle_display || "—"}</td>
            <td className="p-3">{trip.from_city || "—"}</td>
            <td className="p-3">{trip.to_city || "—"}</td>
            <td className="p-3">{trip.trip_type || "—"}</td>
            <td dir="ltr" className="whitespace-nowrap p-3 font-bold">{money(trip.freight)}</td>
            <td className="p-3">{trip.freight_receivable_from === "other_adda"
              ? `Other Adda: ${trip.freight_receivable_other_adda_name || "—"}`
              : trip.freight_receivable_from === "existing_counterparty" ? "Existing Party/Broker" : "Legacy / not set"}</td>
            <td dir="ltr" className="whitespace-nowrap p-3">{trip.received === null ? "—" : money(trip.received)}</td>
            <td dir="ltr" className="whitespace-nowrap p-3">{trip.balance === null ? "—" : money(trip.balance)}</td>
            <td className="p-3">{trip.payment_status || (trip.freight_receivable_from === "other_adda" && !trip.has_financial_obligation ? "Evidence unavailable" : "—")}</td>
            <td className="p-3"><Link href={`/bilty?bookingId=${encodeURIComponent(trip.booking_id)}`} className="inline-flex whitespace-nowrap rounded-lg bg-blue-600 px-3 py-2 font-bold text-white hover:bg-blue-700">Open Bilty</Link></td>
          </tr>)}</tbody></table></div>}
          <nav aria-label="Other Adda trips pagination" className="mt-4 flex flex-wrap items-center justify-between gap-3"><p className="font-bold">Page {tripPage + 1} · {trips.length} loaded trips</p><div className="flex gap-2"><button type="button" disabled={tripPage === 0 || tripLoading} onClick={() => setTripPage((current) => current - 1)} className={button}>Previous</button><button type="button" disabled={!tripHasNext || tripLoading} onClick={() => setTripPage((current) => current + 1)} className={button}>Next</button></div></nav>
        </>}
      </section>
      <section aria-label="Post Other Adda payment" className={panel}>
        <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-xl font-extrabold">Payments / Settlements</h2><p className="mt-1 font-medium text-slate-700">Payments are allocated FIFO against outstanding obligations and posted to Cashbook.</p></div><button type="button" disabled={paymentLoading} onClick={() => void loadPayments()} className={button}>Refresh Payments</button></div>
        <div className="mt-4 flex flex-wrap gap-3">
          <button type="button" disabled={master.status !== "active" || !balance || balanceLoading || cents(balance.gross_receivable) <= BigInt(0)} onClick={() => { setNotice(""); setPaymentSide("receivable"); }} className="rounded-lg bg-emerald-600 px-4 py-2.5 font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50">Receive LENA Payment</button>
          <button type="button" disabled={master.status !== "active" || !balance || balanceLoading || cents(balance.gross_payable) <= BigInt(0)} onClick={() => { setNotice(""); setPaymentSide("payable"); }} className="rounded-lg bg-amber-700 px-4 py-2.5 font-bold text-white hover:bg-amber-800 disabled:cursor-not-allowed disabled:opacity-50">Pay DENA</button>
        </div>
        {paymentLoading && <p role="status" className="mt-4 rounded-lg bg-blue-50 p-4 font-bold text-blue-900">Loading payment history…</p>}
        {paymentError && <div role="alert" className="mt-4 rounded-lg border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{paymentError}<button type="button" disabled={paymentLoading} onClick={() => void loadPayments()} className={`${button} ms-3`}>Retry Payments</button></div>}
        {!paymentLoading && !paymentError && payments !== null && (payments.length === 0
          ? <p className="mt-4 rounded-lg border border-blue-100 bg-blue-50 p-5 font-bold text-blue-900">No payments posted yet.</p>
          : <div className="mt-4 overflow-x-auto"><table className="w-full min-w-[1100px]"><thead className="bg-blue-600 text-white"><tr>{["Date", "Side", "Amount", "Cashbook", "Method", "Reference", "Remarks / Reversal Reason", "Event", "Action"].map((label) => <th key={label} className="p-3 text-start font-bold">{label}</th>)}</tr></thead><tbody>{payments.map((payment) => {
            const isReversal = payment.event_type === "reversal";
            const cashDirection = (payment.side === "receivable") !== isReversal ? "Cash In" : "Cash Out";
            const canReverse = canCancel && !isReversal && !reversedPaymentIds.has(payment.id);
            return <tr key={payment.id} className={`border-b ${isReversal ? "bg-amber-50" : "hover:bg-blue-50/50"}`}>
              <td dir="ltr" className="whitespace-nowrap p-3">{payment.payment_date}</td>
              <td className="p-3 font-bold">{payment.side === "receivable" ? "LENA received" : "DENA paid"}</td>
              <td dir="ltr" className="whitespace-nowrap p-3 font-extrabold">{money(payment.amount)}</td>
              <td className="p-3 font-bold">{cashDirection}</td>
              <td className="p-3">{payment.payment_method}</td>
              <td className="p-3">{payment.reference_no || "—"}</td>
              <td className="max-w-xs whitespace-pre-wrap break-words p-3">{payment.remarks || "—"}</td>
              <td className="p-3 font-extrabold">{isReversal ? "Reversal" : reversedPaymentIds.has(payment.id) ? "Reversed" : "Payment"}{payment.reverses_payment_id && <p className="mt-1 text-xs" title={payment.reverses_payment_id}>Reversal of {payment.reverses_payment_id.slice(0, 8)}</p>}</td>
              <td className="p-3"><div className="flex flex-wrap gap-2"><button type="button" onClick={() => printOtherAddaPayment(payment)} className={button}>Print</button>{canReverse && <button type="button" onClick={() => { setNotice(""); setPaymentToReverse(payment); }} className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 font-bold text-amber-900 hover:bg-amber-100">Reverse Payment</button>}</div></td>
            </tr>;
          })}</tbody></table></div>)}
      </section>
      <section className={panel}><h2 className="text-xl font-extrabold">History Filters</h2><form onSubmit={(event) => { event.preventDefault(); setPage(0); setFilters({ ...draft }); }} className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">

        <VoiceTypingField fieldLabel="Date From" mode="date"><label className="font-bold">Date From<input type="date" value={draft.from} onChange={(e) => setDraft({ ...draft, from: e.target.value })} className={control} /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel="Date To" mode="date"><label className="font-bold">Date To<input type="date" value={draft.to} onChange={(e) => setDraft({ ...draft, to: e.target.value })} className={control} /></label></VoiceTypingField>

        <label className="font-bold">Side<select value={draft.side} onChange={(e) => setDraft({ ...draft, side: e.target.value as Filters["side"] })} className={control}><option value="">All</option><option value="receivable">LENA</option><option value="payable">DENA</option></select></label>
        <label className="font-bold">Entry Type<select value={draft.event} onChange={(e) => setDraft({ ...draft, event: e.target.value as Filters["event"] })} className={control}><option value="">All</option><option value="obligation">Asal Entry</option><option value="reversal">Entry Cancel</option></select></label>
        <button type="submit" disabled={historyLoading} className={`${button} self-end`}>Apply Filters</button>
      </form>
      <VoiceTypingField fieldLabel="Description or Reference No" mode="identifier"><label className="mt-4 block font-bold">Search loaded page<input type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Description or Reference No" className={control} /></label></VoiceTypingField>
      <p className="mt-2 text-sm font-medium">Search covers this history page only. Filters do not change account balances.</p></section>
      <section className="overflow-hidden rounded-xl border border-blue-100 bg-white shadow-sm"><div className="flex flex-wrap items-center justify-between gap-3 border-b p-5"><h2 className="text-xl font-extrabold">Append-only Account History</h2><button type="button" disabled={historyLoading} onClick={() => void loadHistory()} className={button}>Refresh History</button></div>
        {historyLoading && <p role="status" className="p-6 font-bold">Loading history…</p>}
        {historyError && <div role="alert" className="m-5 rounded-lg border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{historyError}<button type="button" disabled={historyLoading} onClick={() => void loadHistory()} className={`${button} ms-3`}>Retry History</button></div>}
        {!historyLoading && !historyError && history !== null && cancelledOriginalIds !== null && <><div className="overflow-x-auto"><table className="w-full min-w-[1320px]"><thead className="bg-blue-600 text-white"><tr>{["Date", "Due Date", "Side", "Reference No", "Description", "LENA", "DENA", "Entry Type", "Created At", "Action"].map((label) => <th key={label} className="p-4 text-start font-bold">{label}</th>)}</tr></thead><tbody>
          {!visible?.length && <tr><td colSpan={10} className="p-10 text-center font-bold">{history.length ? "No entries match search on this page." : page > 0 ? "No entries on this page. Use Previous or refresh history." : filters.from || filters.to || filters.side || filters.event ? "No history matches these filters." : balance ? "No entry history yet." : "No history returned. Account balances are not yet verified."}</td></tr>}
          {visible?.map((row) => <tr key={row.id} className={`border-b ${row.event_type === "reversal" ? "bg-amber-50" : "hover:bg-blue-50/50"}`}><td className="p-4" dir="ltr">{row.transaction_date}</td><td className="whitespace-nowrap p-4" dir="ltr">{row.event_type === "obligation" && row.due_date ? calendarDate(row.due_date) : "—"}</td><td className="p-4 font-bold">{row.side === "receivable" ? "LENA HAI" : "DENA HAI"}</td><td className="p-4">{row.reference_no || "—"}</td><td className="max-w-xs whitespace-pre-wrap break-words p-4">{row.description}</td><td dir="ltr" className="whitespace-nowrap p-4 font-bold">{row.side === "receivable" ? money(row.amount, row.event_type === "reversal") : "—"}</td><td dir="ltr" className="whitespace-nowrap p-4 font-bold">{row.side === "payable" ? money(row.amount, row.event_type === "reversal") : "—"}</td><td className="p-4"><p className="font-extrabold">{row.event_type === "reversal" ? "Entry Cancel" : "Asal Entry"}</p>{row.reverses_transaction_id && <p className="mt-1 text-xs" title={row.reverses_transaction_id}>Entry Cancel of {row.reverses_transaction_id.slice(0, 8)}</p>}{row.event_type === "obligation" && cancelledOriginalIds.has(row.id) && <p className="mt-1 text-xs font-bold text-amber-900">Cancelled</p>}</td><td className="whitespace-nowrap p-4" dir="ltr">{createdAt(row.created_at)}</td><td className="p-4">{row.event_type === "obligation" && !cancelledOriginalIds.has(row.id) ? String(row.origin) === "bilty" ? <span className="max-w-xs text-sm font-semibold text-slate-600">Bilty-linked entry — correction workflow required</span> : canCancel && String(row.origin) === "manual" ? <button type="button" onClick={() => { setNotice(""); setCancelEntry(row); }} className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 font-bold text-amber-900 hover:bg-amber-100">Cancel Entry</button> : "—" : "—"}</td></tr>)}
        </tbody></table></div><nav aria-label="Account history pagination" className="flex flex-wrap items-center justify-between gap-3 p-5"><p className="font-bold">Page {page + 1} · {history.length} loaded entries</p><div className="flex gap-2"><button type="button" disabled={page === 0} onClick={() => setPage(page - 1)} className={button}>Previous</button><button type="button" disabled={!hasNext} onClick={() => setPage(page + 1)} className={button}>Next</button></div></nav></>}
      </section>
      {eventSide && master.status === "active" && <OtherAddaEventModal key={eventSide} otherAddaId={master.id} otherAddaName={master.adda_name} side={eventSide} onClose={() => setEventSide(null)} onSaved={async () => { await posted(); }} />}
      {cancelEntry && canCancel && String(cancelEntry.origin) === "manual" && <OtherAddaCancelModal key={cancelEntry.id} entry={cancelEntry} onClose={() => setCancelEntry(null)} onSaved={async () => { await cancelled(); }} />}
      {paymentSide && master.status === "active" && balance && <OtherAddaPaymentForm key={paymentSide} otherAddaId={master.id} otherAddaName={master.adda_name} side={paymentSide} outstanding={paymentSide === "receivable" ? balance.gross_receivable : balance.gross_payable} onClose={() => setPaymentSide(null)} onSaved={paymentPosted} />}
      {paymentToReverse && canCancel && <OtherAddaPaymentReversalModal key={paymentToReverse.id} payment={paymentToReverse} onClose={() => setPaymentToReverse(null)} onSaved={paymentReversed} />}
      {modulePrint.dialog}
    </>}
  </main>;
}

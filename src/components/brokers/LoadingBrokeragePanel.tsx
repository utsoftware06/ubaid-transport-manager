"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import {
  isValidLoadingBrokeragePayment,
} from "./loadingBrokerageValidation";

type SourceRow = {
  booking_id: string;
  booking_no: string;
  booking_date: string;
  broker_id: string;
  broker_name: string;
  commission_amount: number | string;
  loading_id: number | null;
  loading_no: string | null;
  vehicle_id: string | null;
  vehicle_no: string | null;
  created_at: string;
};

type AccountRow = {
  accrual_id: string;
  booking_id: string;
  booking_no: string;
  broker_id: string;
  broker_name: string;
  commission_amount: number | string;
  outstanding_amount: number | string;
  is_reversed: boolean;
  source_revision: number;
  created_at: string;
  payment_count: number;
};

type EventRow = {
  event_id: string;
  event_kind: "payment" | "payment_reversal" | "accrual_reversal";
  amount: number | string;
  event_date: string;
  payment_method: string | null;
  reference_no: string | null;
  reason: string | null;
  reverses_event_id: string | null;
  created_at: string;
};

type PaymentMethod = "Cash" | "Bank" | "Cheque" | "Online Transfer" | "Account";

type Props = { addaId: string; onUpdated?: () => void };

function localDate() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function amount(value: number | string) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
}

function isMissingRpc(error: { code?: string; message?: string } | null) {
  return Boolean(error && (error.code === "PGRST202" || error.code === "42883"
    || /could not find the function|function .* does not exist/i.test(error.message ?? "")));
}

export default function LoadingBrokeragePanel({ addaId, onUpdated }: Props) {
  const { t, dir } = useLanguage();
  const [sources, setSources] = useState<SourceRow[]>([]);
  const [accounts, setAccounts] = useState<AccountRow[]>([]);
  const [eventsByAccrual, setEventsByAccrual] = useState<Record<string, EventRow[]>>({});
  const [role, setRole] = useState("");
  const [enabled, setEnabled] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [busyKey, setBusyKey] = useState("");
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [payingAccrualId, setPayingAccrualId] = useState("");
  const [paymentDate, setPaymentDate] = useState(localDate());
  const [paymentAmount, setPaymentAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>("Cash");
  const [paymentReference, setPaymentReference] = useState("");
  const requestIds = useRef(new Map<string, { id: string; payload: string }>());
  const loadToken = useRef(0);

  async function refresh(targetAddaId: string) {
    const token = ++loadToken.current;
    setIsLoading(true);
    setError("");
    setSuccess("");
    setRole("");
    setSources([]);
    setAccounts([]);
    setEventsByAccrual({});
    requestIds.current.clear();
    if (!targetAddaId) {
      setEnabled(false);
      setIsLoading(false);
      return;
    }
    try {
      const [sourceResult, accountResult, roleResult] = await Promise.all([
        supabase.rpc("get_loading_brokerage_sources", { p_adda_id: targetAddaId }),
        supabase.rpc("get_loading_brokerage_accounts", { p_adda_id: targetAddaId }),
        supabase.rpc("current_user_role"),
      ]);
      if (token !== loadToken.current) return;
      const missing = sourceResult.error ?? accountResult.error;
      if (isMissingRpc(missing)) {
        setEnabled(false);
        setError(t("brokers.loadingBrokerage.notDeployed"));
        return;
      }
      if (sourceResult.error) throw sourceResult.error;
      if (accountResult.error) throw accountResult.error;
      setEnabled(true);
      setSources((sourceResult.data ?? []) as SourceRow[]);
      setAccounts((accountResult.data ?? []) as AccountRow[]);
      if (!roleResult.error) setRole(String(roleResult.data ?? ""));
    } catch (loadError) {
      if (token !== loadToken.current) return;
      console.error("Unable to load loading brokerage payable data:", loadError);
      setEnabled(false);
      setError(t("brokers.loadingBrokerage.loadFailed"));
    } finally {
      if (token === loadToken.current) setIsLoading(false);
    }
  }

  useEffect(() => {
    queueMicrotask(() => void refresh(addaId));
    return () => { loadToken.current += 1; };
    // Request changes are keyed only by the authorized Adda context.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [addaId, t]);

  function requestIdFor(key: string, payload: string) {
    const existing = requestIds.current.get(key);
    if (existing?.payload === payload) return existing.id;
    const next = crypto.randomUUID();
    requestIds.current.set(key, { id: next, payload });
    return next;
  }

  async function postAccrual(source: SourceRow) {
    const key = `accrue:${source.booking_id}`;
    setBusyKey(key);
    setError("");
    setSuccess("");
    try {
      const { error: rpcError } = await supabase.rpc("post_loading_brokerage_accrual", {
        p_adda_id: addaId,
        p_booking_id: source.booking_id,
        p_loading_id: source.loading_id,
        p_vehicle_id: source.vehicle_id,
        p_request_id: requestIdFor(key, JSON.stringify([source.booking_id, source.loading_id, source.vehicle_id])),
      });
      if (rpcError) throw rpcError;
      requestIds.current.delete(key);
      setSuccess(t("brokers.loadingBrokerage.accrualPosted"));
      onUpdated?.();
      await refresh(addaId);
    } catch (postError) {
      console.error("Unable to post loading brokerage payable:", postError);
      setError(t("brokers.loadingBrokerage.postFailed"));
    } finally {
      setBusyKey("");
    }
  }

  async function recordPayment(account: AccountRow) {
    const outstanding = Number(account.outstanding_amount);
    if (!paymentDate || !isValidLoadingBrokeragePayment(paymentAmount, outstanding)) {
      setError(t("brokers.loadingBrokerage.paymentInvalid"));
      return;
    }
    const key = `pay:${account.accrual_id}`;
    setBusyKey(key);
    setError("");
    setSuccess("");
    try {
      const { error: rpcError } = await supabase.rpc("record_loading_brokerage_payment", {
        p_adda_id: addaId,
        p_accrual_id: account.accrual_id,
        p_payment_date: paymentDate,
        p_amount: Number(paymentAmount),
        p_payment_method: paymentMethod,
        p_reference_no: paymentReference.trim() || null,
        p_request_id: requestIdFor(key, JSON.stringify([paymentDate, Number(paymentAmount), paymentMethod, paymentReference.trim() || null])),
      });
      if (rpcError) throw rpcError;
      requestIds.current.delete(key);
      setPayingAccrualId("");
      setPaymentAmount("");
      setPaymentReference("");
      setSuccess(t("brokers.loadingBrokerage.paymentPosted"));
      onUpdated?.();
      await refresh(addaId);
    } catch (paymentError) {
      console.error("Unable to record loading brokerage payment:", paymentError);
      setError(t("brokers.loadingBrokerage.paymentFailed"));
    } finally {
      setBusyKey("");
    }
  }

  async function loadEvents(accrualId: string) {
    setError("");
    const { data, error: rpcError } = await supabase.rpc("get_loading_brokerage_events", {
      p_adda_id: addaId,
      p_accrual_id: accrualId,
    });
    if (rpcError) {
      setError(t("brokers.loadingBrokerage.loadFailed"));
      return;
    }
    setEventsByAccrual((current) => ({ ...current, [accrualId]: (data ?? []) as EventRow[] }));
  }

  async function reversePayment(event: EventRow, accrualId: string) {
    const reason = window.prompt(t("brokers.loadingBrokerage.reversalReason"));
    if (!reason?.trim()) return;
    const key = `reverse-payment:${event.event_id}`;
    const reversalDate = localDate();
    setBusyKey(key);
    setError("");
    try {
      const { error: rpcError } = await supabase.rpc("reverse_loading_brokerage_payment", {
        p_adda_id: addaId,
        p_payment_event_id: event.event_id,
        p_reversal_date: reversalDate,
        p_reason: reason.trim(),
        p_request_id: requestIdFor(key, JSON.stringify([event.event_id, reversalDate, reason.trim()])),
      });
      if (rpcError) throw rpcError;
      requestIds.current.delete(key);
      await loadEvents(accrualId);
      await refresh(addaId);
      onUpdated?.();
      setSuccess(t("brokers.loadingBrokerage.reversalPosted"));
    } catch (reverseError) {
      console.error("Unable to reverse loading brokerage payment:", reverseError);
      setError(t("brokers.loadingBrokerage.reversalFailed"));
    } finally {
      setBusyKey("");
    }
  }

  async function reverseAccrual(account: AccountRow) {
    const reason = window.prompt(t("brokers.loadingBrokerage.reversalReason"));
    if (!reason?.trim()) return;
    const key = `reverse-accrual:${account.accrual_id}`;
    const reversalDate = localDate();
    setBusyKey(key);
    setError("");
    try {
      const { error: rpcError } = await supabase.rpc("reverse_loading_brokerage_accrual", {
        p_adda_id: addaId,
        p_accrual_id: account.accrual_id,
        p_reversal_date: reversalDate,
        p_reason: reason.trim(),
        p_request_id: requestIdFor(key, JSON.stringify([account.accrual_id, reversalDate, reason.trim()])),
      });
      if (rpcError) throw rpcError;
      requestIds.current.delete(key);
      setSuccess(t("brokers.loadingBrokerage.reversalPosted"));
      onUpdated?.();
      await refresh(addaId);
    } catch (reverseError) {
      console.error("Unable to reverse loading brokerage accrual:", reverseError);
      setError(t("brokers.loadingBrokerage.reverseAccrualFailed"));
    } finally {
      setBusyKey("");
    }
  }

  const isAdmin = role === "adda_admin" || role === "super_admin";
  const totalOutstanding = accounts.reduce((total, account) => total + Number(account.outstanding_amount || 0), 0);
  const reversedPaymentIds = new Set(Object.values(eventsByAccrual).flat()
    .filter((event) => event.event_kind === "payment_reversal" && event.reverses_event_id)
    .map((event) => event.reverses_event_id));

  return (
    <section dir={dir} className="rounded-2xl border border-amber-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-slate-950">{t("brokers.loadingBrokerage.title")}</h2>
          <p className="mt-1 max-w-3xl text-sm text-slate-600">{t("brokers.loadingBrokerage.description")}</p>
        </div>
        <div className="rounded-xl bg-amber-50 px-4 py-3 text-start">
          <p className="text-xs font-semibold text-slate-600">{t("brokers.loadingBrokerage.outstanding")}</p>
          <p className="mt-1 text-lg font-extrabold text-amber-900">{amount(totalOutstanding)}</p>
        </div>
      </div>

      {!enabled && error && <p role="status" className="mt-4 rounded-lg bg-amber-50 p-3 text-sm font-medium text-amber-900">{error}</p>}
      {enabled && error && <p role="alert" className="mt-4 rounded-lg bg-red-50 p-3 text-sm font-medium text-red-800">{error}</p>}
      {success && <p role="status" className="mt-4 rounded-lg bg-emerald-50 p-3 text-sm font-medium text-emerald-800">{success}</p>}
      {isLoading && <p className="mt-4 text-sm text-slate-600">{t("brokers.loadingBrokerage.loading")}</p>}

      {!isLoading && enabled && (
        <div className="mt-5 grid gap-5 xl:grid-cols-2">
          <div className="rounded-xl border border-slate-200 p-4">
            <h3 className="font-bold text-slate-900">{t("brokers.loadingBrokerage.eligibleSources")}</h3>
            <p className="mt-1 text-xs text-slate-600">{t("brokers.loadingBrokerage.explicitPostingOnly")}</p>
            {sources.length === 0 ? <p className="mt-4 text-sm text-slate-600">{t("brokers.loadingBrokerage.noSources")}</p> : (
              <ul className="mt-3 divide-y divide-slate-100">
                {sources.map((source) => {
                  const key = `accrue:${source.booking_id}`;
                  return (
                    <li key={source.booking_id} className="flex flex-wrap items-center justify-between gap-3 py-3">
                      <div className="min-w-0">
                        <p className="font-semibold text-slate-900">{source.broker_name} · {source.booking_no || source.booking_id}</p>
                        <p className="text-xs text-slate-600">{source.loading_no ? `${t("brokers.loadingBrokerage.loadingNo")}: ${source.loading_no} · ` : ""}{source.vehicle_no || "—"}</p>
                        <p className="mt-1 text-sm font-bold text-slate-800">{amount(source.commission_amount)}</p>
                      </div>
                      <button type="button" disabled={busyKey !== ""} onClick={() => void postAccrual(source)}
                        className="rounded-lg bg-amber-700 px-3 py-2 text-sm font-bold text-white disabled:opacity-50">
                        {busyKey === key ? t("brokers.loadingBrokerage.posting") : t("brokers.loadingBrokerage.postPayable")}
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>

          <div className="rounded-xl border border-slate-200 p-4">
            <h3 className="font-bold text-slate-900">{t("brokers.loadingBrokerage.payableHistory")}</h3>
            {accounts.length === 0 ? <p className="mt-4 text-sm text-slate-600">{t("brokers.loadingBrokerage.noAccounts")}</p> : (
              <ul className="mt-3 divide-y divide-slate-100">
                {accounts.map((account) => {
                  const outstanding = Number(account.outstanding_amount);
                  const events = eventsByAccrual[account.accrual_id] ?? [];
                  const isExpanded = Object.hasOwn(eventsByAccrual, account.accrual_id);
                  return (
                    <li key={account.accrual_id} className="py-3">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div>
                          <p className="font-semibold text-slate-900">{account.broker_name} · {account.booking_no || account.booking_id}</p>
                          <p className="mt-1 text-sm text-slate-700">{t("brokers.loadingBrokerage.accrued")}: {amount(account.commission_amount)}</p>
                          <p className="text-sm font-bold text-amber-900">{t("brokers.loadingBrokerage.outstanding")}: {amount(outstanding)}</p>
                          {account.is_reversed && <p className="text-xs font-semibold text-slate-500">{t("brokers.loadingBrokerage.reversed")}</p>}
                        </div>
                        <div className="flex flex-wrap gap-2">
                          {!account.is_reversed && outstanding > 0 && (
                            <button type="button" onClick={() => { setPayingAccrualId(account.accrual_id); setPaymentDate(localDate()); setPaymentAmount(""); }}
                              className="rounded-lg border border-blue-300 px-3 py-2 text-sm font-semibold text-blue-800">
                              {t("brokers.loadingBrokerage.recordPayment")}
                            </button>
                          )}
                          <button type="button" onClick={() => isExpanded ? setEventsByAccrual((current) => { const next={...current}; delete next[account.accrual_id]; return next; }) : void loadEvents(account.accrual_id)}
                            className="rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700">
                            {isExpanded ? t("brokers.loadingBrokerage.hideHistory") : t("brokers.loadingBrokerage.showHistory")}
                          </button>
                          {isAdmin && !account.is_reversed && (
                            <button type="button" disabled={busyKey !== ""} onClick={() => void reverseAccrual(account)}
                              className="rounded-lg border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 disabled:opacity-50">
                              {t("brokers.loadingBrokerage.reverseAccrual")}
                            </button>
                          )}
                        </div>
                      </div>

                      {payingAccrualId === account.accrual_id && (
                        <div className="mt-3 grid gap-2 rounded-lg bg-slate-50 p-3 sm:grid-cols-2">
                          <label className="text-xs font-semibold text-slate-700">{t("brokers.loadingBrokerage.paymentDate")}
                            <input type="date" value={paymentDate} onChange={(event) => setPaymentDate(event.target.value)} className="mt-1 w-full rounded border border-slate-300 bg-white px-2 py-2 text-sm" />
                          </label>
                          <label className="text-xs font-semibold text-slate-700">{t("brokers.loadingBrokerage.paymentAmount")}
                            <input type="number" min="0.01" step="0.01" max={outstanding} value={paymentAmount} onChange={(event) => setPaymentAmount(event.target.value)} className="mt-1 w-full rounded border border-slate-300 bg-white px-2 py-2 text-sm" />
                          </label>
                          <label className="text-xs font-semibold text-slate-700">{t("brokers.loadingBrokerage.paymentMethod")}
                            <select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value as PaymentMethod)} className="mt-1 w-full rounded border border-slate-300 bg-white px-2 py-2 text-sm">
                              {["Cash","Bank","Cheque","Online Transfer","Account"].map((method) => <option key={method} value={method}>{t(`brokers.paymentMethods.${method === "Online Transfer" ? "onlineTransfer" : method.toLowerCase()}`)}</option>)}
                            </select>
                          </label>
                          <label className="text-xs font-semibold text-slate-700">{t("brokers.loadingBrokerage.referenceNo")}
                            <input value={paymentReference} onChange={(event) => setPaymentReference(event.target.value)} className="mt-1 w-full rounded border border-slate-300 bg-white px-2 py-2 text-sm" />
                          </label>
                          <div className="flex gap-2 sm:col-span-2">
                            <button type="button" disabled={busyKey !== ""} onClick={() => void recordPayment(account)} className="rounded-lg bg-blue-700 px-3 py-2 text-sm font-bold text-white disabled:opacity-50">
                              {busyKey === `pay:${account.accrual_id}` ? t("brokers.loadingBrokerage.posting") : t("brokers.loadingBrokerage.savePayment")}
                            </button>
                            <button type="button" onClick={() => setPayingAccrualId("")} className="rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700">{t("common.cancel")}</button>
                          </div>
                        </div>
                      )}

                      {isExpanded && <div className="mt-3 space-y-2 border-s-2 border-slate-200 ps-3">
                        {events.length === 0 ? <p className="text-xs text-slate-500">{t("brokers.loadingBrokerage.noEvents")}</p> : events.map((event) => (
                          <div key={event.event_id} className="flex flex-wrap items-center justify-between gap-2 text-sm">
                            <span>{t(`brokers.loadingBrokerage.eventKinds.${event.event_kind}`)} · {event.event_date} · {amount(event.amount)} {event.payment_method ? `· ${event.payment_method}` : ""} {event.reason ? `· ${event.reason}` : ""}</span>
                            {event.event_kind === "payment" && (
                              reversedPaymentIds.has(event.event_id)
                                ? <span className="text-xs font-semibold text-slate-500">{t("brokers.loadingBrokerage.reversed")}</span>
                                : isAdmin && <button type="button" disabled={busyKey !== ""} onClick={() => void reversePayment(event, account.accrual_id)} className="rounded border border-red-300 px-2 py-1 text-xs font-semibold text-red-700 disabled:opacity-50">{t("brokers.loadingBrokerage.reversePayment")}</button>
                            )}
                          </div>
                        ))}
                      </div>}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </div>
      )}
      <p className="mt-4 text-xs text-slate-500">{t("brokers.loadingBrokerage.legacySeparate")}</p>
    </section>
  );
}

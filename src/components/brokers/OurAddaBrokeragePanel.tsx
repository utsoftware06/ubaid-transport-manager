"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import {
  getLoadingBrokerageAccounts,
  getLoadingBrokerageEvents,
  getOurAddaBrokerageHistory,
  type LoadingBrokerageAccount,
  type LoadingBrokerageEvent,
  type OurAddaBrokerageRow,
} from "./ourAddaBrokerageApi";

type Props = { addaId: string; refreshKey: number };
const PAGE_SIZE = 25;
type BrokerageEventView = LoadingBrokerageEvent & { brokerName: string; sourceRevision: number };
type EventLoad = { loading: boolean; error: string; rows: BrokerageEventView[] };

function amount(value: number | null, currency: string, missing: string) {
  if (value === null) return missing;
  return `${currency} ${value.toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
}

function statusText(status: string, t: (key: string) => string, prefix: string) {
  const key = `${prefix}.${status}`;
  const translated = t(key);
  return translated === key ? t(`${prefix}.unverified`) : translated;
}

function isMissingRpc(error: unknown) {
  if (!error || typeof error !== "object") return false;
  const detail = error as { code?: string; message?: string };
  return detail.code === "PGRST202" || detail.code === "42883"
    || /could not find the function|function .* does not exist/i.test(detail.message ?? "");
}

function summarizeExternalBrokerage(row: OurAddaBrokerageRow, accounts: LoadingBrokerageAccount[]) {
  const bookingAccounts = accounts.filter((account) => account.bookingId === row.bookingId);
  const active = bookingAccounts.filter((account) => !account.isReversed);
  if (active.length > 1) return { account: null, status: "multiple_active_unverified", amount: null, settled: null, outstanding: null, accounts: bookingAccounts };
  if (active.length === 1) {
    const account = active[0];
    const settled = account.commissionAmount - account.outstandingAmount;
    const valid = account.commissionAmount >= 0 && account.outstandingAmount >= 0
      && settled >= 0 && account.outstandingAmount <= account.commissionAmount;
    const status = !valid ? "unverified" : account.outstandingAmount === 0 ? "paid" : settled > 0 ? "partial" : "unpaid";
    return { account, status, amount: valid ? account.commissionAmount : null, settled: valid ? settled : null, outstanding: valid ? account.outstandingAmount : null, accounts: bookingAccounts };
  }
  if (bookingAccounts.length > 0) return { account: null, status: "reversed", amount: null, settled: null, outstanding: null, accounts: bookingAccounts };
  return {
    account: null,
    status: row.externalBrokerageSourceStatus,
    amount: null,
    settled: null,
    outstanding: null,
    accounts: bookingAccounts,
  };
}

function accountSettlement(account: LoadingBrokerageAccount) {
  if (account.isReversed) return { status: "reversed", settled: null as number | null, outstanding: null as number | null };
  const settled = account.commissionAmount - account.outstandingAmount;
  const valid = account.commissionAmount >= 0 && account.outstandingAmount >= 0
    && settled >= 0 && account.outstandingAmount <= account.commissionAmount;
  if (!valid) return { status: "unverified", settled: null, outstanding: null };
  return {
    status: account.outstandingAmount === 0 ? "paid" : settled > 0 ? "partial" : "unpaid",
    settled,
    outstanding: account.outstandingAmount,
  };
}

function Metric({ label, value, tone }: { label: string; value: string; tone: string }) {
  return <div className={`rounded-lg border p-3 ${tone}`}><dt className="text-xs font-semibold text-slate-600">{label}</dt><dd className="mt-1 text-base font-extrabold text-slate-950">{value}</dd></div>;
}

export default function OurAddaBrokeragePanel({ addaId, refreshKey }: Props) {
  const { t, dir } = useLanguage();
  const requestRef = useRef(0);
  const [rows, setRows] = useState<OurAddaBrokerageRow[]>([]);
  const [accounts, setAccounts] = useState<LoadingBrokerageAccount[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");
  const [loadedQueryKey, setLoadedQueryKey] = useState("");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [filters, setFilters] = useState({ fromDate: "", toDate: "", search: "" });
  const [page, setPage] = useState(0);
  const [expandedBookingId, setExpandedBookingId] = useState<string | null>(null);
  const [eventsByBooking, setEventsByBooking] = useState<Record<string, EventLoad>>({});

  useEffect(() => {
    const requestId = ++requestRef.current;
    const queryKey = JSON.stringify([addaId, filters, page, refreshKey]);
    if (!addaId) return () => { requestRef.current += 1; };

    void Promise.all([
      getOurAddaBrokerageHistory({
        addaId,
        fromDate: filters.fromDate || null,
        toDate: filters.toDate || null,
        search: filters.search,
        limit: PAGE_SIZE,
        offset: page * PAGE_SIZE,
      }),
      getLoadingBrokerageAccounts(addaId),
    ]).then(([history, brokerageAccounts]) => {
      if (requestId !== requestRef.current) return;
      setExpandedBookingId(null);
      setEventsByBooking({});
      setRows(history.rows);
      setTotalCount(history.totalCount);
      setAccounts(brokerageAccounts);
      setError("");
      setLoadedQueryKey(queryKey);
    }).catch((loadError: unknown) => {
      if (requestId !== requestRef.current) return;
      setExpandedBookingId(null);
      setEventsByBooking({});
      console.error("Unable to load unified Broker Loading Account:", loadError);
      setRows([]);
      setAccounts([]);
      setTotalCount(0);
      setError(isMissingRpc(loadError)
        ? t("brokers.ourAddaBrokerage.notDeployed")
        : t("brokers.ourAddaBrokerage.loadFailed"));
      setLoadedQueryKey(queryKey);
    }).finally(() => {
      if (requestId === requestRef.current) setIsLoading(false);
    });
    return () => { requestRef.current += 1; };
  }, [addaId, filters, page, refreshKey, t]);

  const accountsByBooking = useMemo(() => {
    const grouped = new Map<string, LoadingBrokerageAccount[]>();
    for (const account of accounts) {
      const current = grouped.get(account.bookingId) ?? [];
      current.push(account);
      grouped.set(account.bookingId, current);
    }
    return grouped;
  }, [accounts]);

  function applyFilters(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (fromDate && toDate && fromDate > toDate) {
      setError(t("brokers.ourAddaBrokerage.invalidDateRange"));
      return;
    }
    setError("");
    setPage(0);
    setFilters({ fromDate, toDate, search: searchInput.trim() });
  }

  async function toggleDetail(row: OurAddaBrokerageRow) {
    if (expandedBookingId === row.bookingId) {
      setExpandedBookingId(null);
      return;
    }
    setExpandedBookingId(row.bookingId);
    const relevantAccounts = accountsByBooking.get(row.bookingId) ?? [];
    if (relevantAccounts.length === 0 || eventsByBooking[row.bookingId]) return;
    setEventsByBooking((current) => ({ ...current, [row.bookingId]: { loading: true, error: "", rows: [] } }));
    const requestId = requestRef.current;
    try {
      const eventGroups = await Promise.all(relevantAccounts.map((account) =>
        getLoadingBrokerageEvents(addaId, account.accrualId).then((events) => ({ account, events }))));
      if (requestId !== requestRef.current) return;
      const merged = eventGroups.flatMap(({ account, events }) => events.map((event) => ({
        ...event,
        brokerName: account.brokerName,
        sourceRevision: account.sourceRevision,
      })))
        .sort((left, right) => left.eventDate.localeCompare(right.eventDate) || left.eventId.localeCompare(right.eventId));
      setEventsByBooking((current) => ({ ...current, [row.bookingId]: { loading: false, error: "", rows: merged } }));
    } catch (eventError) {
      if (requestId !== requestRef.current) return;
      console.error("Unable to load protected external Brokerage payment history:", eventError);
      setEventsByBooking((current) => ({ ...current, [row.bookingId]: { loading: false, error: t("brokers.ourAddaBrokerage.eventLoadFailed"), rows: [] } }));
    }
  }

  const pageCount = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const queryKey = JSON.stringify([addaId, filters, page, refreshKey]);
  const isCurrentQuery = loadedQueryKey === queryKey;
  const showLoading = isLoading || !isCurrentQuery;
  const visibleError = isCurrentQuery ? error : "";
  const currency = t("brokers.ourAddaBrokerage.currency");
  const missing = t("brokers.ourAddaBrokerage.notRecorded");

  return (
    <section dir={dir} className="rounded-2xl border border-violet-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-slate-950">{t("brokers.ourAddaBrokerage.title")}</h2>
          <p className="mt-1 max-w-5xl text-sm text-slate-600">{t("brokers.ourAddaBrokerage.description")}</p>
        </div>
      </div>
      <div className="mt-3 rounded-xl border border-violet-100 bg-violet-50/70 p-3 text-sm text-slate-700">
        {t("brokers.ourAddaBrokerage.accountingNote")}
      </div>

      {visibleError && <p role="alert" className="mt-4 rounded-lg bg-red-50 p-3 text-sm font-medium text-red-800">{visibleError}</p>}
      {showLoading && <p role="status" className="mt-4 text-sm text-slate-600">{t("brokers.ourAddaBrokerage.loading")}</p>}

      <form onSubmit={applyFilters} className="mt-5 grid gap-3 rounded-xl border border-slate-200 p-3 sm:grid-cols-2 xl:grid-cols-4">
        <label className="text-xs font-semibold text-slate-700">{t("brokers.ourAddaBrokerage.fromDate")}
          <input type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)} className="mt-1 block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-normal text-slate-900" />
        </label>
        <label className="text-xs font-semibold text-slate-700">{t("brokers.ourAddaBrokerage.toDate")}
          <input type="date" value={toDate} onChange={(event) => setToDate(event.target.value)} className="mt-1 block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-normal text-slate-900" />
        </label>
        <label className="text-xs font-semibold text-slate-700">{t("brokers.ourAddaBrokerage.search")}
          <input value={searchInput} onChange={(event) => setSearchInput(event.target.value)} maxLength={120} className="mt-1 block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-normal text-slate-900" />
        </label>
        <div className="flex items-end"><button type="submit" className="w-full rounded-lg bg-violet-800 px-4 py-2 text-sm font-bold text-white hover:bg-violet-900">{t("brokers.ourAddaBrokerage.applyFilters")}</button></div>
      </form>

      {!showLoading && !visibleError && rows.length === 0 && <p className="mt-5 rounded-lg bg-slate-50 p-4 text-sm text-slate-600">{t("brokers.ourAddaBrokerage.empty")}</p>}

      {!visibleError && isCurrentQuery && rows.length > 0 && <>
        <div className="mt-5 overflow-x-auto rounded-xl border border-slate-200">
          <table className="w-full min-w-[1180px] text-start text-sm">
            <thead className="bg-slate-100 text-xs text-slate-700"><tr>
              {["referenceDirection", "broker", "vehicle", "vehicleAccount", "ourAddaMargin", "externalPayable", "detail"].map((key) =>
                <th key={key} className="whitespace-nowrap px-3 py-3 font-bold">{t(`brokers.ourAddaBrokerage.columns.${key}`)}</th>)}
            </tr></thead>
            <tbody>{rows.map((row) => {
              const externalAccounts = accountsByBooking.get(row.bookingId) ?? [];
              const brokerage = summarizeExternalBrokerage(row, externalAccounts);
              const hasOurAddaDirection = row.loadingSource === "own_adda" || row.ourAddaMargin !== null;
              const hasExternalDirection = Boolean(row.externalBrokerId) || (row.savedExternalBrokerage ?? 0) > 0 || externalAccounts.length > 0;
              const open = expandedBookingId === row.bookingId;
              return <FragmentRow key={row.bookingId} row={row} brokerage={brokerage} hasOurAddaDirection={hasOurAddaDirection}
                hasExternalDirection={hasExternalDirection} open={open} onToggle={() => void toggleDetail(row)}
                currency={currency} missing={missing} t={t} eventLoad={eventsByBooking[row.bookingId]} />;
            })}</tbody>
          </table>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3 text-sm text-slate-600">
          <span>{t("brokers.ourAddaBrokerage.records").replace("{count}", String(totalCount))}</span>
          <div className="flex items-center gap-2">
            <button type="button" disabled={page <= 0 || showLoading} onClick={() => setPage((value) => Math.max(0, value - 1))} className="rounded-lg border border-slate-300 px-3 py-1.5 font-semibold disabled:opacity-50">{t("brokers.ourAddaBrokerage.previous")}</button>
            <span>{t("brokers.ourAddaBrokerage.page").replace("{current}", String(Math.min(page + 1, pageCount))).replace("{total}", String(pageCount))}</span>
            <button type="button" disabled={page + 1 >= pageCount || showLoading} onClick={() => setPage((value) => value + 1)} className="rounded-lg border border-slate-300 px-3 py-1.5 font-semibold disabled:opacity-50">{t("brokers.ourAddaBrokerage.next")}</button>
          </div>
        </div>
      </>}
    </section>
  );
}

type BrokerageSummary = ReturnType<typeof summarizeExternalBrokerage>;
function FragmentRow({
  row, brokerage, hasOurAddaDirection, hasExternalDirection, open, onToggle, currency, missing, t, eventLoad,
}: {
  row: OurAddaBrokerageRow;
  brokerage: BrokerageSummary;
  hasOurAddaDirection: boolean;
  hasExternalDirection: boolean;
  open: boolean;
  onToggle: () => void;
  currency: string;
  missing: string;
  t: (key: string) => string;
  eventLoad?: EventLoad;
}) {
  const money = (value: number | null) => amount(value, currency, missing);
  const routeSummary = row.linkedLoadingCount === 1
    ? row.linkedLoadings[0]?.route ?? missing
    : row.linkedLoadingCount > 1 ? t("brokers.ourAddaBrokerage.multipleLoadingsSeeDetail") : row.bookingRoute ?? missing;
  const payableBrokerName = brokerage.status === "multiple_active_unverified"
    ? t("brokers.ourAddaBrokerage.unverified")
    : brokerage.account?.brokerName
      ?? (brokerage.accounts.length === 1 ? brokerage.accounts[0].brokerName : null)
      ?? (brokerage.accounts.length > 1 ? t("brokers.ourAddaBrokerage.unverified") : row.externalBrokerName)
      ?? (row.externalBrokerId ? t("brokers.ourAddaBrokerage.unverified") : t("brokers.ourAddaBrokerage.notApplicable"));
  return <>
    <tr className="border-t border-slate-200 align-top text-slate-800">
      <td className="min-w-48 px-3 py-3"><span dir="ltr" className="font-semibold">{row.bookingNo ?? missing}</span><span dir="ltr" className="mt-1 block text-xs text-slate-500">{t("brokers.ourAddaBrokerage.loadingDate")}: {row.accountDate ?? missing}</span>
        <span dir="ltr" className="mt-1 block text-xs text-slate-500">{t("brokers.ourAddaBrokerage.bookingDate")}: {row.bookingDate ?? missing}</span>
        <span className="mt-1 block text-xs text-slate-600">{t("common.route")}: {routeSummary}</span>
        <span className="mt-1 block text-xs text-slate-600">{row.linkedLoadingCount > 0 ? t("brokers.ourAddaBrokerage.loadingCount").replace("{count}", String(row.linkedLoadingCount)) : t("brokers.ourAddaBrokerage.noLoading")}</span></td>
      <td className="min-w-48 px-3 py-3"><div className="flex flex-wrap gap-1">
        {hasOurAddaDirection && <span className="rounded-full bg-violet-100 px-2 py-1 text-xs font-bold text-violet-900">{t("brokers.ourAddaBrokerage.ourAddaDirection")}</span>}
        {hasExternalDirection && <span className="rounded-full bg-amber-100 px-2 py-1 text-xs font-bold text-amber-900">{t("brokers.ourAddaBrokerage.externalDirection")}</span>}
        {!hasOurAddaDirection && !hasExternalDirection && <span>{t("brokers.ourAddaBrokerage.unverified")}</span>}
      </div></td>
      <td className="min-w-44 px-3 py-3"><span>{payableBrokerName}</span>
        <span className="mt-1 block text-xs text-slate-500">{row.externalBrokerId ? t("brokers.ourAddaBrokerage.externalBroker") : t("brokers.ourAddaBrokerage.brokerNotLinked")}</span></td>
      <td className="min-w-48 px-3 py-3"><span dir="ltr">{row.vehicleNo ?? (row.vehicleContextCount > 1 ? t("brokers.ourAddaBrokerage.multipleVehicles") : missing)}</span>
        <span className="mt-1 block text-xs text-slate-500">{row.vehicleOwnerName ?? t("brokers.ourAddaBrokerage.ownerNotRecorded")}</span>
        <span className="mt-1 block text-xs font-semibold">{statusText(row.vehicleContextStatus, t, "brokers.ourAddaBrokerage.vehicleContextStatus")}</span></td>
      <td className="min-w-56 px-3 py-3"><dl className="space-y-1 text-xs">
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.grossKiraya")}: </dt><dd className="inline font-semibold">{money(row.grossVehicleKiraya)}</dd></div>
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.netVehicle")}: </dt><dd className="inline font-semibold">{money(row.netVehicleEntitlement)}</dd></div>
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.vehiclePaid")}: </dt><dd className="inline">{money(row.vehicleTotalPaid)}</dd></div>
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.parchiVehicleWithheld")}: </dt><dd className="inline">{money(row.vehicleParchiWithheld)}</dd></div>
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.vehicleEntitlementSettled")}: </dt><dd className="inline font-semibold">{money(row.vehicleEntitlementSettled)}</dd></div>
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.vehicleOutstanding")}: </dt><dd className="inline font-bold">{money(row.vehicleOutstanding)}</dd></div>
        <div className="pt-1 font-bold">{statusText(row.vehiclePaymentStatus, t, "brokers.ourAddaBrokerage.vehicleStatus")}</div>
      </dl></td>
      <td className="min-w-56 px-3 py-3"><dl className="space-y-1 text-xs">
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.marginEarned")}: </dt><dd className="inline font-semibold">{money(row.ourAddaMargin)}</dd></div>
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.marginRealized")}: </dt><dd className="inline">{money(row.marginRealized)}</dd></div>
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.marginPending")}: </dt><dd className="inline">{money(row.marginPending)}</dd></div>
        <div className="pt-1 font-semibold">{statusText(row.marginRealizationStatus, t, "brokers.ourAddaBrokerage.marginStatus")}</div>
        <div className="text-[11px] text-slate-500">{t("brokers.ourAddaBrokerage.freightReceiptBasis")}: {money(row.freightReceiptsBasis)}</div>
      </dl></td>
      <td className="min-w-60 px-3 py-3"><dl className="space-y-1 text-xs">
        <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.sourceAmount")}: </dt><dd className="inline">{money(brokerage.amount ?? row.savedExternalBrokerage)}</dd></div>
        {brokerage.account ? <>
          <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.actualSettled")}: </dt><dd className="inline">{money(brokerage.settled)}</dd></div>
          <div><dt className="inline text-slate-500">{t("brokers.ourAddaBrokerage.payableOutstanding")}: </dt><dd className="inline font-bold">{money(brokerage.outstanding)}</dd></div>
        </> : <div className="text-slate-500">{t("brokers.ourAddaBrokerage.settlementUnverified")}</div>}
        <div className="pt-1 font-bold">{statusText(brokerage.status, t, "brokers.ourAddaBrokerage.externalStatus")}</div>
      </dl></td>
      <td className="px-3 py-3"><button type="button" aria-expanded={open} onClick={onToggle} className="whitespace-nowrap rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-bold text-slate-800 hover:bg-slate-50">{open ? t("brokers.ourAddaBrokerage.hideDetail") : t("brokers.ourAddaBrokerage.viewDetail")}</button></td>
    </tr>
    {open && <tr className="border-t border-slate-200 bg-slate-50"><td colSpan={7} className="p-4">
      <div className="grid gap-4 xl:grid-cols-2">
        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h4 className="font-bold text-slate-900">{t("brokers.ourAddaBrokerage.linkedLoadingHistory")}</h4>
          {row.linkedLoadings.length === 0 ? <p className="mt-2 text-sm text-slate-600">{t("brokers.ourAddaBrokerage.noLoading")}</p> : <div className="mt-3 space-y-3">{row.linkedLoadings.map((loading) => <article key={loading.loadingId} className="rounded border border-slate-100 p-3 text-sm">
            <div className="flex flex-wrap justify-between gap-2"><strong>{t("brokers.ourAddaBrokerage.loadingNo")}: {loading.loadingNo ?? missing}</strong><span dir="ltr">{loading.loadingDate ?? missing}</span></div>
            <p className="mt-1">{t("common.route")}: {loading.route ?? missing}</p>
            <p className="mt-1">{t("common.vehicle")}: <span dir="ltr">{loading.vehicleNo ?? missing}</span> · {t("brokers.ourAddaBrokerage.owner")}: {loading.ownerName ?? t("brokers.ourAddaBrokerage.ownerNotRecorded")}</p>
            {loading.driverName && <p className="mt-1">{t("common.driver")}: {loading.driverName}</p>}
            {loading.vehicleContextStatus !== "recorded" && <p className="mt-1 text-xs font-semibold text-amber-800">{statusText(loading.vehicleContextStatus, t, "brokers.ourAddaBrokerage.vehicleContextStatus")}</p>}
          </article>)}</div>}
        </section>

        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h4 className="font-bold text-slate-900">{t("brokers.ourAddaBrokerage.vehiclePaymentHistory")}</h4>
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            <Metric label={t("brokers.ourAddaBrokerage.grossKiraya")} value={money(row.grossVehicleKiraya)} tone="border-slate-200 bg-slate-50" />
            <Metric label={t("brokers.ourAddaBrokerage.netVehicle")} value={money(row.netVehicleEntitlement)} tone="border-slate-200 bg-slate-50" />
          </div>
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            <Metric label={t("brokers.ourAddaBrokerage.deductionsAndCharges")} value={[
              `${t("brokers.ourAddaBrokerage.externalBrokerage")}: ${money(row.savedExternalBrokerage)}`,
              `${t("brokers.ourAddaBrokerage.overweight")}: ${money(row.overweightCharges)}`,
              `${t("brokers.ourAddaBrokerage.lolo")}: ${money(row.loloCharges)}`,
              `${t("brokers.ourAddaBrokerage.detain")}: ${money(row.detainCharges)}`,
            ].join(" · ")} tone="border-slate-200 bg-slate-50" />
            <Metric label={t("brokers.ourAddaBrokerage.paymentStatus")} value={statusText(row.vehiclePaymentStatus, t, "brokers.ourAddaBrokerage.vehicleStatus")} tone="border-slate-200 bg-slate-50" />
          </div>
          {row.vehiclePaymentHistory.length === 0 ? <p className="mt-3 text-sm text-slate-600">{t("brokers.ourAddaBrokerage.noVehiclePayments")}</p> : <ol className="mt-3 space-y-2">{row.vehiclePaymentHistory.map((payment, index) => <li key={`${payment.eventType}:${payment.paymentDate ?? "undated"}:${payment.referenceNo ?? index}:${index}`} className="flex flex-wrap justify-between gap-2 border-t border-slate-100 pt-2 text-sm">
            <span>{payment.eventType === "saved_advance" ? t("brokers.ourAddaBrokerage.savedAdvance") : t("brokers.ourAddaBrokerage.vehiclePayment")} · <span dir="ltr">{payment.paymentDate ?? t("brokers.ourAddaBrokerage.dateNotRecorded")}</span>
              {payment.paymentMethod ? ` · ${payment.paymentMethod}` : ""}{payment.referenceNo ? ` · ${t("brokers.ourAddaBrokerage.reference")}: ${payment.referenceNo}` : ""}</span><strong dir="ltr">{money(payment.amount)}</strong>
          </li>)}</ol>}
        </section>

        <section className="rounded-lg border border-violet-200 bg-white p-4">
          <h4 className="font-bold text-violet-950">{t("brokers.ourAddaBrokerage.ourAddaMarginDetail")}</h4>
          <dl className="mt-3 grid gap-3 sm:grid-cols-2">
            <div><dt className="text-xs text-slate-500">{t("brokers.ourAddaBrokerage.marginEarned")}</dt><dd className="mt-1 font-bold">{money(row.ourAddaMargin)}</dd></div>
            <div><dt className="text-xs text-slate-500">{t("brokers.ourAddaBrokerage.freightReceiptBasis")}</dt><dd className="mt-1 font-bold">{money(row.freightReceiptsBasis)}</dd></div>
            <div><dt className="text-xs text-slate-500">{t("brokers.ourAddaBrokerage.marginRealized")}</dt><dd className="mt-1 font-bold">{money(row.marginRealized)}</dd></div>
            <div><dt className="text-xs text-slate-500">{t("brokers.ourAddaBrokerage.marginPending")}</dt><dd className="mt-1 font-bold">{money(row.marginPending)}</dd></div>
            <div><dt className="text-xs text-slate-500">{t("brokers.ourAddaBrokerage.settlementBasis")}</dt><dd className="mt-1">{row.freightSettlementBasis ?? t("brokers.ourAddaBrokerage.unverified")}</dd></div>
          </dl>
          <p className="mt-3 rounded bg-violet-50 p-2 text-xs text-violet-950">{t("brokers.ourAddaBrokerage.marginReceiptNote")}</p>
        </section>

        <section className="rounded-lg border border-amber-200 bg-white p-4">
          <h4 className="font-bold text-amber-950">{t("brokers.ourAddaBrokerage.externalPayableDetail")}</h4>
          <p className="mt-2 text-sm">{t("brokers.ourAddaBrokerage.broker")}: {payableBrokerName}</p>
          <p className="mt-1 text-sm">{t("brokers.ourAddaBrokerage.sourceAmount")}: {money(brokerage.amount ?? row.savedExternalBrokerage)} · {statusText(brokerage.status, t, "brokers.ourAddaBrokerage.externalStatus")}</p>
          <p className="mt-2 text-xs text-slate-600">{t("brokers.ourAddaBrokerage.externalSourceNote")}</p>
          {brokerage.accounts.length > 0 && <div className="mt-3 space-y-2">
            <h5 className="text-sm font-bold text-slate-900">{t("brokers.ourAddaBrokerage.accrualHistory")}</h5>
            {brokerage.accounts.map((account) => {
              const settlement = accountSettlement(account);
              return <article key={account.accrualId} className="rounded border border-slate-100 p-3 text-sm">
                <p className="font-semibold">{account.brokerName || t("brokers.ourAddaBrokerage.unverified")} · {t("brokers.ourAddaBrokerage.sourceRevision").replace("{revision}", String(account.sourceRevision))}</p>
                <p className="mt-1">{t("brokers.ourAddaBrokerage.accruedAmount")}: {money(account.commissionAmount)} · {statusText(settlement.status, t, "brokers.ourAddaBrokerage.externalStatus")}</p>
                {!account.isReversed && <p className="mt-1">{t("brokers.ourAddaBrokerage.actualSettled")}: {money(settlement.settled)} · {t("brokers.ourAddaBrokerage.payableOutstanding")}: {money(settlement.outstanding)}</p>}
                {account.createdAt && <p dir="ltr" className="mt-1 text-xs text-slate-500">{t("brokers.ourAddaBrokerage.accrualDate")}: {account.createdAt.slice(0, 10)}</p>}
              </article>;
            })}
          </div>}
          {eventLoad?.loading && <p role="status" className="mt-3 text-sm text-slate-600">{t("brokers.ourAddaBrokerage.loadingEvents")}</p>}
          {eventLoad?.error && <p role="alert" className="mt-3 text-sm text-red-700">{eventLoad.error}</p>}
          {!eventLoad?.loading && !eventLoad?.error && brokerage.accounts.length === 0 && <p className="mt-3 text-sm text-slate-600">{row.savedExternalBrokerage && row.savedExternalBrokerage > 0 ? t("brokers.ourAddaBrokerage.unpostedSettlement") : t("brokers.ourAddaBrokerage.noExternalPayable")}</p>}
          {!eventLoad?.loading && !eventLoad?.error && brokerage.accounts.length > 0 && (eventLoad?.rows.length ?? 0) === 0 && <p className="mt-3 text-sm text-slate-600">{t("brokers.ourAddaBrokerage.noBrokerageEvents")}</p>}
          {(eventLoad?.rows ?? []).length > 0 && <ol className="mt-3 space-y-2">{(eventLoad?.rows ?? []).map((event) => <li key={event.eventId} className="flex flex-wrap justify-between gap-2 border-t border-slate-100 pt-2 text-sm">
            <span>{t(`brokers.loadingBrokerage.eventKinds.${event.eventKind}`)} · {event.brokerName || t("brokers.ourAddaBrokerage.unverified")} · {t("brokers.ourAddaBrokerage.sourceRevision").replace("{revision}", String(event.sourceRevision))} · <span dir="ltr">{event.eventDate}</span>{event.paymentMethod ? ` · ${event.paymentMethod}` : ""}{event.referenceNo ? ` · ${event.referenceNo}` : ""}{event.reason ? ` · ${event.reason}` : ""}</span><strong dir="ltr">{money(event.amount)}</strong>
          </li>)}</ol>}
        </section>
      </div>
    </td></tr>}
  </>;
}

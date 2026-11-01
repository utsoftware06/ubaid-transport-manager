"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type HistoryRow = {
  history_row_id: string | null;
  history_date: string | null;
  booking_id: string | null;
  booking_no: string | null;
  booking_date: string | null;
  bilty_loading_date: string | null;
  loading_id: number | null;
  loading_no: string | null;
  loading_date: string | null;
  route: string | null;
  from_city: string | null;
  to_city: string | null;
  vehicle_no: string | null;
  driver_name: string | null;
  gross_kiraya: number | string | null;
  loading_brokerage: number | string | null;
  booking_status: string | null;
  loading_status: string | null;
  loading_payment_status: string | null;
  total_count: number | string;
};

type Props = { addaId: string; brokerId: string };
const PAGE_SIZE = 25;

function formatAmount(value: number | string | null) {
  if (value === null || value === "") return "—";
  const numeric = Number(value);
  return Number.isFinite(numeric)
    ? `Rs. ${numeric.toLocaleString("en-PK", { maximumFractionDigits: 2 })}`
    : "—";
}

function missingRpc(error: { code?: string; message?: string } | null) {
  return Boolean(error && (error.code === "PGRST202" || error.code === "42883"
    || /could not find the function|function .* does not exist/i.test(error.message ?? "")));
}

export default function BrokerLoadingHistory({ addaId, brokerId }: Props) {
  const { t, dir } = useLanguage();
  const [rows, setRows] = useState<HistoryRow[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [expandedRow, setExpandedRow] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");
  const requestId = useRef(0);
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  useEffect(() => {
    const currentRequest = ++requestId.current;

    if (!addaId || !brokerId) {
      void Promise.resolve().then(() => {
        if (currentRequest === requestId.current) {
          setError(t("brokers.loadingHistory.contextMissing"));
          setIsLoading(false);
        }
      });
      return () => { requestId.current += 1; };
    }

    const historyRequest = supabase.rpc("get_broker_loading_history", {
      p_adda_id: addaId,
      p_broker_id: brokerId,
      p_from_date: fromDate || null,
      p_to_date: toDate || null,
      p_search: search.trim() || null,
      p_limit: PAGE_SIZE,
      p_offset: (page - 1) * PAGE_SIZE,
    });
    void Promise.resolve(historyRequest).then(({ data, error: queryError }) => {
      if (currentRequest !== requestId.current) return;
      if (queryError) {
        setRows([]);
        setTotalCount(0);
        setError(missingRpc(queryError)
          ? t("brokers.loadingHistory.notDeployed")
          : `${t("brokers.loadingHistory.loadFailed")} (${queryError.code ?? queryError.message})`);
        return;
      }
      const resultRows = (data ?? []) as HistoryRow[];
      const count = Number(resultRows[0]?.total_count ?? 0);
      setTotalCount(Number.isFinite(count) ? count : 0);
      setRows(resultRows.filter((row) => row.history_row_id !== null));
    }).catch((queryError: unknown) => {
      if (currentRequest !== requestId.current) return;
      const message = queryError instanceof Error ? queryError.message : String(queryError);
      setRows([]);
      setTotalCount(0);
      setError(`${t("brokers.loadingHistory.loadFailed")} (${message})`);
    }).finally(() => {
      if (currentRequest === requestId.current) setIsLoading(false);
    });

    return () => { requestId.current += 1; };
  }, [addaId, brokerId, fromDate, page, search, t, toDate]);

  function changeFilter(setter: (value: string) => void, value: string) {
    setRows([]);
    setTotalCount(0);
    setExpandedRow(null);
    setError("");
    setIsLoading(true);
    setter(value);
    setPage(1);
  }

  function changePage(nextPage: number) {
    setRows([]);
    setExpandedRow(null);
    setError("");
    setIsLoading(true);
    setPage(nextPage);
  }

  return (
    <section dir={dir} className="mb-6 rounded-xl border border-slate-200 bg-slate-50 p-4">
      <div className="mb-4 flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="text-lg font-bold text-slate-950">{t("brokers.loadingHistory.title")}</h3>
          <p className="mt-1 text-sm text-slate-600">{t("brokers.loadingHistory.description")}</p>
        </div>
        <span className="rounded-full bg-white px-3 py-1 text-sm font-semibold text-slate-700">
          {t("brokers.loadingHistory.records")}: {totalCount.toLocaleString()}
        </span>
      </div>

      <div className="mb-4 grid gap-3 md:grid-cols-4">
        <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date">
          <input type="date" dir="ltr" aria-label={t("common.fromDate")} value={fromDate}
            onChange={(event) => changeFilter(setFromDate,event.target.value)}
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm" />
        </VoiceTypingField>
        <VoiceTypingField fieldLabel={t("common.toDate")} mode="date">
          <input type="date" dir="ltr" aria-label={t("common.toDate")} value={toDate}
            onChange={(event) => changeFilter(setToDate,event.target.value)}
            className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm" />
        </VoiceTypingField>
        <div className="md:col-span-2">
          <VoiceTypingField fieldLabel={t("common.actions.search")} mode="text">
            <input type="search" aria-label={t("common.actions.search")} placeholder={t("brokers.loadingHistory.searchPlaceholder")}
              value={search} onChange={(event) => changeFilter(setSearch,event.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm" />
          </VoiceTypingField>
        </div>
      </div>

      {error && <p role="alert" className="mb-3 rounded-lg bg-red-50 p-3 text-sm font-medium text-red-800">{error}</p>}
      {isLoading && <p role="status" className="mb-3 text-sm text-slate-600">{t("brokers.loadingHistory.loading")}</p>}

      {!isLoading && !error && rows.length === 0 && (
        <p className="rounded-lg bg-white p-5 text-center text-sm text-slate-600">{t("brokers.loadingHistory.empty")}</p>
      )}

      {!error && rows.length > 0 && (
        <>
          <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
            <table className="w-full min-w-[1120px] border-collapse text-start text-sm">
              <thead className="bg-slate-100 text-slate-800">
                <tr>
                  <th className="p-3">{t("common.date")}</th>
                  <th className="p-3">{t("brokers.loadingHistory.biltyLoading")}</th>
                  <th className="p-3">{t("common.route")}</th>
                  <th className="p-3">{t("common.vehicle")}</th>
                  <th className="p-3">{t("common.driver")}</th>
                  <th className="p-3 text-end">{t("brokers.loadingHistory.grossKiraya")}</th>
                  <th className="p-3 text-end">{t("brokers.loadingHistory.existingBrokerage")}</th>
                  <th className="p-3">{t("common.status")}</th>
                  <th className="p-3">{t("common.actions.title")}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <HistoryTableRow key={row.history_row_id ?? `${row.booking_id ?? "booking"}:${row.loading_id ?? "none"}`} row={row} expanded={expandedRow === row.history_row_id}
                    onToggle={() => setExpandedRow((current) => current === row.history_row_id ? null : row.history_row_id)} />
                ))}
              </tbody>
            </table>
          </div>
          {totalPages > 1 && (
            <div className="mt-3 flex flex-wrap items-center justify-between gap-3 text-sm">
              <span>{t("common.pagination.page")} {page} {t("common.pagination.of")} {totalPages}</span>
              <div className="flex gap-2">
                <button type="button" disabled={page <= 1} onClick={() => changePage(Math.max(1,page - 1))}
                  className="rounded border border-slate-300 bg-white px-3 py-2 disabled:opacity-50">{t("common.pagination.previous")}</button>
                <button type="button" disabled={page >= totalPages} onClick={() => changePage(Math.min(totalPages,page + 1))}
                  className="rounded border border-slate-300 bg-white px-3 py-2 disabled:opacity-50">{t("common.pagination.next")}</button>
              </div>
            </div>
          )}
        </>
      )}
    </section>
  );
}

function HistoryTableRow({ row, expanded, onToggle }: { row: HistoryRow; expanded: boolean; onToggle: () => void }) {
  const { t, language } = useLanguage();
  const tripStatusRoot = language === "ur" ? "tripManagement.status" : "tripManagement.statuses";
  const tripStatusKeys = {
    planned: `${tripStatusRoot}.planned`,
    loading: `${tripStatusRoot}.loading`,
    intransit: `${tripStatusRoot}.${language === "ur" ? "intransit" : "inTransit"}`,
    delivered: `${tripStatusRoot}.delivered`,
    completed: `${tripStatusRoot}.completed`,
    cancelled: `${tripStatusRoot}.cancelled`,
  };
  const statusKey = (value: string | null, kind: "booking" | "loading" | "payment") => {
    if (!value) return "";
    const normalized = value.toLowerCase().replace(/[^a-z]/g, "");
    const keys: Record<string, Record<string, string>> = {
      booking: {
        booked: "bookings.status.booked",
        intransit: "bookings.status.inTransit",
        delivered: "bookings.status.delivered",
        cancelled: tripStatusKeys.cancelled,
      },
      loading: tripStatusKeys,
      payment: {
        unpaid: "loadings.paymentStatus.unpaid",
        paid: "loadings.paymentStatus.paid",
        partial: "loadings.paymentStatus.partial",
      },
    };
    const translationKey = keys[kind][normalized];
    if (translationKey) {
      const translated = t(translationKey);
      if (translated !== translationKey) return translated;
    }

    const fallback = value.trim().includes(".")
      ? value.trim().split(".").at(-1) ?? value.trim()
      : value.trim();
    return fallback
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/[_-]+/g, " ")
      .replace(/\s+/g, " ");
  };
  const statusText = [
    statusKey(row.booking_status,"booking"),
    statusKey(row.loading_status,"loading"),
    statusKey(row.loading_payment_status,"payment"),
  ].filter(Boolean).join(" · ");
  return (
    <>
      <tr className="border-t border-slate-100 align-top">
        <td dir="ltr" className="whitespace-nowrap p-3">{row.history_date ?? "—"}</td>
        <td className="p-3">
          <div className="font-semibold">{row.booking_no || "—"}</div>
          {row.loading_no && <div className="mt-1 text-xs text-slate-600">{t("common.loadingNo")}: {row.loading_no}</div>}
          {!row.loading_id && <div className="mt-1 text-xs text-slate-500">{t("brokers.loadingHistory.noLoading")}</div>}
        </td>
        <td className="p-3">{row.route || [row.from_city,row.to_city].filter(Boolean).join(" → ") || "—"}</td>
        <td dir="ltr" className="p-3">{row.vehicle_no || "—"}</td>
        <td className="p-3">{row.driver_name || "—"}</td>
        <td dir="ltr" className="whitespace-nowrap p-3 text-end">{formatAmount(row.gross_kiraya)}</td>
        <td dir="ltr" className="whitespace-nowrap p-3 text-end">
          <span>{formatAmount(row.loading_brokerage)}</span>
          <span className="mt-1 block text-xs text-slate-500">{t("brokers.loadingHistory.biltyScoped")}</span>
        </td>
        <td className="p-3">{statusText || (row.loading_id ? "—" : t("brokers.loadingHistory.biltyOnly"))}</td>
        <td className="p-3">
          <button type="button" onClick={onToggle} aria-expanded={expanded}
            className="whitespace-nowrap rounded border border-slate-300 px-3 py-1.5 font-semibold text-slate-800 hover:bg-slate-50">
            {expanded ? t("brokers.loadingHistory.hideDetail") : t("brokers.loadingHistory.viewDetail")}
          </button>
        </td>
      </tr>
      {expanded && (
        <tr className="border-t border-slate-100 bg-slate-50">
          <td colSpan={9} className="p-4">
            <dl className="grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <Detail label={t("common.bookingNo")} value={row.booking_no} />
              <Detail label={t("brokers.loadingHistory.bookingDate")} value={row.booking_date} technical />
              <Detail label={t("brokers.loadingHistory.biltyLoadingDate")} value={row.bilty_loading_date} technical />
              <Detail label={t("common.loadingNo")} value={row.loading_no} />
              <Detail label={t("common.loadingDate")} value={row.loading_date} technical />
              <Detail label={t("common.route")} value={row.route || [row.from_city,row.to_city].filter(Boolean).join(" → ")} />
              <Detail label={t("brokers.loadingHistory.bookingStatus")} value={statusKey(row.booking_status,"booking")} />
              <Detail label={t("brokers.loadingHistory.loadingStatus")} value={statusKey(row.loading_status,"loading")} />
              <Detail label={t("brokers.loadingHistory.loadingPaymentStatus")} value={statusKey(row.loading_payment_status,"payment")} />
              <Detail label={t("brokers.loadingHistory.grossKiraya")} value={formatAmount(row.gross_kiraya)} technical />
              <Detail label={t("brokers.loadingHistory.existingBrokerage")} value={formatAmount(row.loading_brokerage)} technical />
            </dl>
          </td>
        </tr>
      )}
    </>
  );
}

function Detail({ label, value, technical = false }: { label: string; value: string | null | undefined; technical?: boolean }) {
  return <div><dt className="text-xs font-semibold text-slate-500">{label}</dt><dd dir={technical ? "ltr" : undefined} className="mt-1 font-medium text-slate-900">{value || "—"}</dd></div>;
}

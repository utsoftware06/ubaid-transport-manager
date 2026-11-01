"use client";

import { useEffect, useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";

type PayerType = "party" | "other_adda";
type EventRow = {
  parchi_id: string; parchi_no: string; document_date: string; counterparty_name: string | null;
  primary_payer_type: PayerType; primary_payer_id: string; responsible_party_id: string | null;
  responsible_person_name: string; funding_due_date: string | null; settlement_due_date: string | null;
  document_amount: number | string; net_funded: number | string; net_settled: number | string;
  funded_outstanding: number | string; funding_status: string; settlement_status: string;
  event_id: string | null; event_kind: string | null; event_date: string | null;
  event_amount: number | string | null; event_payer_name: string | null; reason: string | null;
};
type DocumentRow = EventRow & { events: EventRow[] };

function money(value: number | string | null | undefined) {
  const amount = Number(value ?? 0);
  return `₨ ${Number.isFinite(amount) ? amount.toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "0.00"}`;
}

function statusLabel(value: string, t: (key: string) => string) {
  const keys: Record<string, string> = {
    Unfunded: "parchi.statuses.unfunded", "Partially Funded": "parchi.statuses.partiallyFunded",
    "Fully Funded": "parchi.statuses.fullyFunded", Cancelled: "parchi.statuses.cancelled",
    "Not Funded": "parchi.statuses.notFunded", Unpaid: "parchi.statuses.unpaid",
    "Partially Settled": "parchi.statuses.partiallySettled", Settled: "parchi.statuses.settled",
  };
  return keys[value] ? t(keys[value]) : value;
}

export default function IssuedFreightParchiProjection({ addaId, payerType, payerId }: {
  addaId: string;
  payerType: PayerType;
  payerId: string;
}) {
  const { t, dir, language } = useLanguage();
  const requestKey = `${addaId}|${payerType}|${payerId}|${language}`;
  const [loaded, setLoaded] = useState<{ key: string; rows: EventRow[] | null; error: unknown | null } | null>(null);
  const current = loaded?.key === requestKey ? loaded : null;
  const rows = current?.rows ?? null;
  const error = current?.error
    ? current.error instanceof Error
      ? current.error.message
      : typeof current.error === "object" && current.error !== null && "message" in current.error && typeof current.error.message === "string"
        ? current.error.message
        : t("parchi.loadError")
    : "";
  const busy = Boolean(addaId && payerId) && current === null;

  useEffect(() => {
    if (!addaId || !payerId) return;
    let active = true;
    void (async () => {
      const result: EventRow[] = [];
      const pageSize = 1000;
      for (let offset = 0; ; offset += pageSize) {
        const { data, error: queryError } = await supabase.rpc("get_issued_freight_parchi_statement", {
          p_adda_id: addaId, p_account_type: payerType, p_account_id: payerId,
        }).range(offset, offset + pageSize - 1);
        if (queryError) throw queryError;
        const page = (data ?? []) as unknown as EventRow[];
        result.push(...page);
        if (page.length < pageSize) break;
      }
      if (active) setLoaded({ key: requestKey, rows: result, error: null });
    })().catch((queryError: unknown) => {
      if (!active) return;
      setLoaded({ key: requestKey, rows: null, error: queryError });
    });
    return () => { active = false; };
  }, [addaId, payerId, payerType, language, requestKey]);

  const documents = useMemo(() => {
    const grouped = new Map<string, DocumentRow>();
    for (const row of rows ?? []) {
      const current = grouped.get(row.parchi_id);
      if (current) current.events.push(row);
      else grouped.set(row.parchi_id, { ...row, events: [row] });
    }
    return [...grouped.values()];
  }, [rows]);
  const isPrimaryPayer = (row: DocumentRow) => row.primary_payer_type === payerType && row.primary_payer_id === payerId;
  const primaryDocuments = documents.filter(isPrimaryPayer);
  const secondaryDocuments = payerType === "party"
    ? documents.filter((row) => row.responsible_party_id === payerId && !isPrimaryPayer(row))
    : [];
  const totals = useMemo(() => primaryDocuments.reduce((result, row) => ({
    count: result.count + 1,
    funded: result.funded + Number(row.net_funded ?? 0),
    recovered: result.recovered + Number(row.net_settled ?? 0),
    outstanding: result.outstanding + Number(row.funded_outstanding ?? 0),
  }), { count: 0, funded: 0, recovered: 0, outstanding: 0 }), [primaryDocuments]);

  const history = (row: DocumentRow) => row.events.length > 0 && <details className="mt-3 border-t border-slate-100 pt-2">
    <summary className="cursor-pointer text-xs font-bold text-indigo-800">{t("parchi.history")} ({row.events.length})</summary>
    <ul className="mt-2 space-y-1">{row.events.map((item, index) => <li key={item.event_id ?? `${row.parchi_id}-${index}`} className="flex flex-wrap justify-between gap-x-4 gap-y-1 text-xs text-slate-700">
      <span>{item.event_date || item.document_date} · {item.event_kind === "funding" ? t("parchi.events.funding") : item.event_kind === "recovery" ? t("parchi.events.settlement") : item.event_kind === "reversal" ? t("parchi.events.reversal") : item.event_kind === "recourse" ? t("parchi.events.recourse") : item.event_kind === "created" ? t("parchi.events.documentCreated") : item.event_kind || "—"}{item.event_payer_name ? ` · ${item.event_payer_name}` : ""}{item.reason ? ` · ${item.reason}` : ""}</span>
      <bdi dir="ltr" className="font-semibold tabular-nums">{item.event_amount == null ? "—" : money(item.event_kind === "reversal" ? -Number(item.event_amount) : item.event_amount)}</bdi>
    </li>)}</ul>
  </details>;

  return <section dir={dir} className="rounded-2xl border border-indigo-200 bg-indigo-50/60 p-4 shadow-sm">
    <header className="flex flex-wrap items-start justify-between gap-3">
      <div><h2 className="text-lg font-extrabold text-indigo-950">{t("parchi.issuedFinance")}</h2><p className="mt-1 max-w-3xl text-xs text-indigo-900">{t("parchi.financeAccountNote")}</p></div>
      {!busy && !error && rows && <span className="rounded-full bg-white px-3 py-1 text-xs font-bold text-indigo-900">{documents.length} {t("parchi.uniqueParchis")}</span>}
    </header>
    {busy && <p role="status" className="mt-3 text-sm text-indigo-900">{t("parchi.loading")}</p>}
    {error && <div role="alert" className="mt-3 rounded-lg border border-rose-200 bg-white p-3 text-sm font-semibold text-rose-800">{t("parchi.loadError")} {error}</div>}
    {!busy && !error && rows && <>
      <div className="mt-4 grid gap-2 sm:grid-cols-4">
        {[[t("parchi.document"), String(totals.count)], [t("parchi.funded"), money(totals.funded)], [t("parchi.settled"), money(totals.recovered)], [t("parchi.outstanding"), money(totals.outstanding)]].map(([label, value]) => <div key={label} className="rounded-lg border border-indigo-100 bg-white p-3"><p className="text-xs font-bold text-slate-600">{label}</p><p dir="ltr" className="mt-1 font-extrabold tabular-nums text-slate-950">{value}</p></div>)}
      </div>
      {primaryDocuments.length === 0 && secondaryDocuments.length === 0 ? <p className="mt-3 rounded-lg bg-white p-3 text-sm text-slate-600">{t("parchi.noRecords")}</p> : <div className="mt-4 max-h-[32rem] space-y-4 overflow-auto">
        {primaryDocuments.length > 0 && <section><h3 className="mb-2 text-sm font-extrabold text-slate-800">{t("parchi.primaryPayer")}</h3><div className="space-y-3">{primaryDocuments.map((row) => <article key={row.parchi_id} className="rounded-xl border border-indigo-100 bg-white p-3">
          <div className="grid gap-2 sm:grid-cols-5"><div><p className="text-xs text-slate-500">{t("parchi.document")}</p><p className="font-extrabold">{row.parchi_no}</p></div><div><p className="text-xs text-slate-500">{t("parchi.documentDate")}</p><p>{row.document_date}</p></div><div><p className="text-xs text-slate-500">{t("parchi.funded")}</p><p dir="ltr" className="font-semibold tabular-nums">{money(row.net_funded)}</p></div><div><p className="text-xs text-slate-500">{t("parchi.settled")}</p><p dir="ltr" className="font-semibold tabular-nums">{money(row.net_settled)}</p></div><div><p className="text-xs text-slate-500">{t("parchi.outstanding")}</p><p dir="ltr" className="font-extrabold tabular-nums">{money(row.funded_outstanding)}</p></div></div>
          <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600"><span>{t("parchi.fundingStatus")}: {statusLabel(row.funding_status, t)}</span><span>{t("parchi.settlementStatus")}: {statusLabel(row.settlement_status, t)}</span><span>{t("parchi.fundingDueDate")}: {row.funding_due_date || t("parchi.print.notRecorded")}</span><span>{t("parchi.settlementDueDate")}: {row.settlement_due_date || t("parchi.print.notRecorded")}</span></div>
          {history(row)}
        </article>)}</div></section>}
        {secondaryDocuments.length > 0 && <section><h3 className="mb-2 text-sm font-extrabold text-slate-800">{t("parchi.secondaryResponsible")}</h3><p className="mb-2 rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs font-semibold text-amber-950">{t("parchi.secondarySharedPrincipalNote")}</p><div className="space-y-3">{secondaryDocuments.map((row) => <article key={row.parchi_id} className="rounded-xl border border-amber-100 bg-white p-3">
          <div className="grid gap-2 sm:grid-cols-4"><div><p className="text-xs text-slate-500">{t("parchi.document")}</p><p className="font-extrabold">{row.parchi_no}</p></div><div><p className="text-xs text-slate-500">{t("parchi.primaryPayer")}</p><p className="font-semibold">{row.counterparty_name || "—"}</p></div><div><p className="text-xs text-slate-500">{t("parchi.outstanding")}</p><p dir="ltr" className="font-extrabold tabular-nums">{money(row.funded_outstanding)}</p></div><div><p className="text-xs text-slate-500">{t("parchi.settlementDueDate")}</p><p>{row.settlement_due_date || t("parchi.print.notRecorded")}</p></div></div>
          <div className="mt-2 text-xs text-slate-600">{statusLabel(row.settlement_status, t)}</div>{history(row)}
        </article>)}</div></section>}
      </div>}
    </>}
  </section>;
}

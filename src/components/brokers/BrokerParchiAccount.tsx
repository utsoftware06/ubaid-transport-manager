"use client";

import { useEffect, useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";

type StatementRow = {
  parchi_id: string;
  parchi_no: string;
  counterparty_name: string | null;
  document_date: string;
  funding_due_date: string | null;
  settlement_due_date: string | null;
  net_funded: number | string;
  net_settled: number | string;
  funded_outstanding: number | string;
  event_id: string | null;
  event_kind: string | null;
  event_date: string | null;
  event_amount: number | string | null;
  payment_method: string | null;
  reference_no: string | null;
  reverses_event_id: string | null;
};
type EventMetadata = {
  id: string;
  parchi_id: string;
  event_kind: string;
  amount: number | string | null;
  commission_withheld: number | string | null;
  actual_cash_amount: number | string | null;
  funding_route: string | null;
  reverses_event_id: string | null;
};
type ParchiRow = {
  id: string;
  no: string;
  documentDate: string;
  fundingDue: string | null;
  settlementDue: string | null;
  principal: number;
  commission: number | null;
  actualCash: number | null;
  repaid: number;
  outstanding: number;
  events: Array<StatementRow & EventMetadata>;
};

function numeric(value: number | string | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value: number) {
  return `₨ ${value.toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export default function BrokerParchiAccount({ addaId, brokerId }: { addaId: string; brokerId: string }) {
  const { t, dir } = useLanguage();
  const [rows, setRows] = useState<ParchiRow[] | null>(null);
  const [error, setError] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    async function load() {
      try {
        const statement = await supabase.rpc("get_parchi_statement", {
          p_adda_id: addaId,
          p_counterparty_type: "broker",
          p_counterparty_id: brokerId,
        });
        if (statement.error) throw statement.error;
        const statementRows = (statement.data ?? []) as StatementRow[];
        const parchiIds = Array.from(new Set(statementRows.map((row) => row.parchi_id)));
        const detail = parchiIds.length
          ? await supabase.from("parchi_events")
            .select("id,parchi_id,event_kind,amount,commission_withheld,actual_cash_amount,funding_route,reverses_event_id")
            .in("parchi_id", parchiIds)
          : { data: [] as EventMetadata[], error: null };
        if (detail.error) throw detail.error;
        const metadataById = new Map(((detail.data ?? []) as EventMetadata[]).map((event) => [event.id, event]));
        const grouped = new Map<string, StatementRow[]>();
        for (const row of statementRows) {
          const list = grouped.get(row.parchi_id) ?? [];
          list.push(row);
          grouped.set(row.parchi_id, list);
        }
        const result = Array.from(grouped.entries()).map(([id, history]) => {
          const events = history.flatMap((row) => row.event_id
            ? [{ ...row, ...metadataById.get(row.event_id) } as StatementRow & EventMetadata]
            : []);
          const originals = new Map(events
            .filter((event) => event.event_kind === "funding" || event.event_kind === "settlement")
            .map((event) => [event.id, event]));
          let principal = 0;
          let commission = 0;
          let actualCash = 0;
          let commissionKnown = true;
          let actualCashKnown = true;
          let repaid = 0;
          for (const event of events) {
            if (event.event_kind === "funding") {
              const principalAmount = numeric(event.amount ?? event.event_amount);
              principal += principalAmount;
              if (event.commission_withheld == null) commissionKnown = false;
              else commission += numeric(event.commission_withheld);
              if (event.actual_cash_amount == null) actualCashKnown = false;
              else actualCash += numeric(event.actual_cash_amount);
            } else if (event.event_kind === "settlement") {
              repaid += numeric(event.amount ?? event.event_amount);
            } else if (event.event_kind === "reversal" && event.reverses_event_id) {
              const original = originals.get(event.reverses_event_id);
              if (original?.event_kind === "funding") {
                principal -= numeric(original.amount ?? original.event_amount);
                if (original.commission_withheld == null) commissionKnown = false;
                else commission -= numeric(original.commission_withheld);
                if (original.actual_cash_amount == null) actualCashKnown = false;
                else actualCash -= numeric(original.actual_cash_amount);
              } else if (original?.event_kind === "settlement") {
                repaid -= numeric(original.amount ?? original.event_amount);
              }
            }
          }
          const first = history[0];
          return {
            id,
            no: first.parchi_no,
            documentDate: first.document_date,
            fundingDue: first.funding_due_date,
            settlementDue: first.settlement_due_date,
            principal: Math.max(principal, 0),
            commission: commissionKnown ? Math.max(commission, 0) : null,
            actualCash: actualCashKnown ? Math.max(actualCash, 0) : null,
            repaid: Math.max(repaid, 0),
            outstanding: Math.max(numeric(first.funded_outstanding), 0),
            events,
          };
        }).sort((left, right) => right.documentDate.localeCompare(left.documentDate) || right.no.localeCompare(left.no));
        if (active) setRows(result);
      } catch (loadError) {
        console.error("Broker Received Parchi account load failed", loadError);
        if (active) setError(true);
      }
    }
    void load();
    return () => { active = false; };
  }, [addaId, brokerId]);

  const totals = useMemo(() => {
    const total = (rows ?? []).reduce((sum, row) => ({
      principal: sum.principal + row.principal,
      commission: sum.commission + (row.commission ?? 0),
      commissionKnown: sum.commissionKnown && row.commission !== null,
      actualCash: sum.actualCash + (row.actualCash ?? 0),
      actualCashKnown: sum.actualCashKnown && row.actualCash !== null,
      repaid: sum.repaid + row.repaid,
      outstanding: sum.outstanding + row.outstanding,
    }), { principal: 0, commission: 0, commissionKnown: true, actualCash: 0, actualCashKnown: true, repaid: 0, outstanding: 0 });
    return { ...total, commission: total.commissionKnown ? total.commission : null, actualCash: total.actualCashKnown ? total.actualCash : null };
  }, [rows]);
  const title = "brokerLedger.parchiAccount";

  return (
    <section dir={dir} className="mb-6 rounded-xl border border-indigo-200 bg-indigo-50/50 p-4">
      <div className="mb-3">
        <h3 className="text-lg font-extrabold text-gray-950">{t(`${title}.title`)}</h3>
        <p className="mt-1 text-sm text-gray-700">{t(`${title}.description`)}</p>
      </div>
      {rows === null && !error && <p className="py-4 text-sm text-gray-700">{t(`${title}.loading`)}</p>}
      {error && <p role="alert" className="rounded-lg bg-rose-50 p-3 text-sm font-semibold text-rose-800">{t(`${title}.loadFailed`)}</p>}
      {rows && <>
        <div className="mb-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
          {[
            ["principalFunded", totals.principal], ["commissionWithheld", totals.commission],
            ["actualCash", totals.actualCash], ["repaid", totals.repaid], ["outstanding", totals.outstanding],
          ].map(([key, value]) => <div key={String(key)} className="rounded-lg border border-indigo-100 bg-white px-3 py-2">
            <p className="text-xs font-semibold text-gray-600">{t(`${title}.${key}`)}</p>
            <p dir="ltr" className="mt-1 font-extrabold tabular-nums text-gray-950">{typeof value === "number" ? money(value) : t("parchi.print.notRecorded")}</p>
          </div>)}
        </div>
        {rows.length === 0
          ? <p className="rounded-lg bg-white p-4 text-center text-sm text-gray-600">{t(`${title}.empty`)}</p>
          : <div className="overflow-x-auto rounded-lg border border-indigo-100 bg-white">
            <table className="min-w-[1120px] w-full text-start text-sm">
              <thead className="bg-indigo-100/70 text-xs text-gray-700"><tr>
                {[t(`${title}.pNo`), t("parchi.documentDate"), t(`${title}.fundingDue`), t(`${title}.settlementDue`), t(`${title}.principalFunded`), t(`${title}.commissionWithheld`), t(`${title}.actualCash`), t(`${title}.repaid`), t(`${title}.outstanding`), t("common.actions.title")].map((heading) => <th key={heading} className="p-2.5 text-start">{heading}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-gray-100">
                {rows.map((row) => <tr key={row.id}>
                  <td className="p-2.5 font-bold">{row.no}</td>
                  <td dir="ltr" className="p-2.5">{row.documentDate}</td>
                  <td dir="ltr" className="p-2.5">{row.fundingDue || "—"}</td>
                  <td dir="ltr" className="p-2.5">{row.settlementDue || "—"}</td>
                  {[row.principal, row.commission, row.actualCash, row.repaid, row.outstanding].map((value, index) => <td dir="ltr" key={index} className="p-2.5 tabular-nums">{value === null ? t("parchi.print.notRecorded") : money(value)}</td>)}
                  <td className="p-2.5"><button type="button" className="font-bold text-indigo-800 underline" onClick={() => setExpandedId(expandedId === row.id ? null : row.id)}>{t(`${title}.${expandedId === row.id ? "hideDetails" : "viewDetails"}`)}</button></td>
                </tr>)}
              </tbody>
            </table>
          </div>}
        {expandedId && rows.find((row) => row.id === expandedId) && (() => {
          const row = rows.find((item) => item.id === expandedId)!;
          const originalById = new Map(row.events.filter((item) => item.event_kind === "funding" || item.event_kind === "settlement").map((item) => [item.id, item]));
          return <div className="mt-3 overflow-x-auto rounded-lg border border-indigo-100 bg-white p-3">
            <h4 className="mb-2 font-bold text-gray-900">{t(`${title}.events`)} · {row.no}</h4>
            {row.events.length === 0 ? <p className="text-sm text-gray-600">{t("parchi.noEvents")}</p> : <table className="min-w-[800px] w-full text-start text-xs">
              <thead className="bg-gray-50 text-gray-700"><tr>{[t("parchi.eventDate"), t("parchi.event"), t("parchi.amount"), t(`${title}.commissionWithheld`), t(`${title}.actualCash`), t("parchi.paymentMethod"), t("parchi.referenceNo"), t(`${title}.route`)].map((heading) => <th key={heading} className="p-2 text-start">{heading}</th>)}</tr></thead>
              <tbody>{row.events.map((event) => {
                const original = event.reverses_event_id ? originalById.get(event.reverses_event_id) : undefined;
                const label = event.event_kind === "funding" ? t("parchi.events.funding")
                  : event.event_kind === "settlement" ? t("parchi.events.settlement")
                    : event.event_kind === "reversal" ? `${t("parchi.events.reversal")}${original ? ` · ${t(`${title}.reversed`)}` : ""}`
                      : t("parchi.event");
                const valueSource = event.event_kind === "reversal" ? original : event;
                const sign = event.event_kind === "reversal" ? -1 : 1;
                const actualCash = valueSource?.actual_cash_amount == null ? null : sign * numeric(valueSource.actual_cash_amount);
                const commission = valueSource?.commission_withheld == null ? null : sign * numeric(valueSource.commission_withheld);
                const routeSource = event.event_kind === "reversal" ? original : event;
                const fundingRelated = event.event_kind === "funding" || original?.event_kind === "funding";
                const route = routeSource?.funding_route === "direct_to_vehicle" ? t(`${title}.direct`)
                  : routeSource?.funding_route === "through_adda" ? t(`${title}.throughAdda`)
                    : fundingRelated ? t("parchi.print.notRecorded") : "—";
                return <tr key={event.id} className="border-t border-gray-100">
                  <td dir="ltr" className="p-2">{event.event_date || "—"}</td><td className="p-2">{label}</td>
                  <td dir="ltr" className="p-2 tabular-nums">{money(event.event_kind === "reversal" ? -numeric(event.amount) : numeric(event.amount))}</td>
                  <td dir="ltr" className="p-2 tabular-nums">{!fundingRelated ? "—" : commission === null ? t("parchi.print.notRecorded") : money(commission)}</td>
                  <td dir="ltr" className="p-2 tabular-nums">{!fundingRelated ? "—" : actualCash === null ? t("parchi.print.notRecorded") : money(actualCash)}</td>
                  <td className="p-2">{event.payment_method || "—"}</td><td className="p-2">{event.reference_no || "—"}</td><td className="p-2">{route}</td>
                </tr>;
              })}</tbody>
            </table>}
          </div>;
        })()}
      </>}
    </section>
  );
}

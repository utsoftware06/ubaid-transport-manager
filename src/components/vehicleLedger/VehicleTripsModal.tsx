"use client";

import { useEffect, useRef } from "react";
import type { VehicleFilterType, VehicleReport, VehicleTrip, VehicleTripFreightLeg } from "./VehicleLedger";
import { formatAmount } from "./reporting";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { usePrintAddaName } from "@/lib/print/usePrintAddaName";
import LedgerStatementPrintButton, { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { vehicleLedgerPrintPresentation } from "./vehicleLedgerPrintPresentation";

type Props = { vehicleReport: VehicleReport; period: { filterType: VehicleFilterType; fromDate: string; toDate: string }; onClose: () => void };

export default function VehicleTripsModal({ vehicleReport, period, onClose }: Props) {
  const { t, dir, language } = useLanguage();
  const printAddaName = usePrintAddaName(vehicleReport.addaId, language === "ur" ? "ur" : "en");
  const printAddaId = singleResolvedAddaId(vehicleReport.trips.map((trip) => trip.addaId));
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const previousActiveElement = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();
    const handleKeyDown = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousActiveElement?.focus();
    };
  }, [onClose]);

  function freightRows(trip: VehicleTrip) {
    const general: [string, string][] = [
      [t("vehicleLedger.fields.date"), trip.date || "—"],
      [t("common.driver"), trip.driverName],
    ];
    if (trip.sourceType === "bilty") return general;

    return [
      ...general,
      [t("vehicleLedger.fields.voucherNo"), trip.voucherNo],
      [t("vehicleLedger.fields.tripType"), trip.tripType],
      [t("common.route"), trip.route],
      [t("vehicleLedger.fields.loadedThrough"), trip.loadedThrough],
      [t("vehicleLedger.fields.collectFrom"), trip.collectFrom],
      [t("vehicleLedger.fields.manualFreight"), formatAmount(trip.income)],
      [t("vehicleLedger.fields.chakkarDays"), trip.chakkarDays ? String(trip.chakkarDays) : "—"],
      [t("vehicleLedger.fields.totalTripExpenses"), formatAmount(trip.totalExpense)],
      [t("vehicleLedger.fields.netVehicleEarnings"), formatAmount(trip.profit)],
      [t("vehicleLedger.fields.finalized"), trip.finalizedAt ? trip.finalizedAt.slice(0, 10) : "—"],
      [t("vehicleLedger.fields.paymentStatus"), t("vehicleLedger.fields.notTracked")],
    ];
  }

  function paymentStatusLabel(status: VehicleTripFreightLeg["paymentStatus"]) {
    return t(`vehicleLedger.filters.status.${status.toLowerCase()}`);
  }

  function biltyTotals(trip: VehicleTrip) {
    const legs = trip.freightLegs ?? [];
    const totalRaw = legs.reduce((sum, leg) => sum + leg.rawVehicleFreight, 0);
    const totalAdjusted = legs.reduce((sum, leg) => sum + leg.adjustedVehicleFreight, 0);
    const totalReceived = legs.reduce((sum, leg) => sum + leg.totalVehiclePaid, 0);
    const parchiWithheld = legs.reduce((sum, leg) => sum + leg.parchiVehicleWithheld, 0);
    const entitlementSettled = totalReceived + parchiWithheld;
    const totalOutstanding = legs.reduce((sum, leg) => sum + leg.balance, 0);
    const status = entitlementSettled <= 0
      ? "Unpaid"
      : legs.length > 0 && legs.every((leg) => leg.paymentStatus === "Paid") ? "Paid" : "Partial";
    return { totalRaw, totalAdjusted, totalReceived, parchiWithheld, entitlementSettled, totalOutstanding, status };
  }

  function biltyLegCells(leg: VehicleTripFreightLeg) {
    return [
      leg.side,
      leg.biltyNo,
      leg.bookingDate || t("driverLedger.notRecorded"),
      leg.vehicleNo,
      leg.route,
      leg.loadingDrivers.length
        ? leg.loadingDrivers.map((assignment) => `${assignment.loadingId}: ${assignment.driverName}`).join(" · ")
        : leg.driverName || t("driverLedger.notRecorded"),
      leg.loadingIds.length ? leg.loadingIds.join(", ") : t("driverLedger.notRecorded"),
      leg.loadedThrough,
      leg.collectFrom,
      formatAmount(leg.rawVehicleFreight),
      `−${formatAmount(leg.brokerCommission)}`,
      `+${formatAmount(leg.overweightCharges)}`,
      `+${formatAmount(leg.loloCharges)}`,
      `+${formatAmount(leg.detainCharges)}`,
      formatAmount(leg.adjustedVehicleFreight),
      formatAmount(leg.advanceVehicle),
      formatAmount(leg.laterVehiclePayments),
      formatAmount(leg.totalVehiclePaid),
      formatAmount(leg.parchiVehicleWithheld),
      formatAmount(leg.totalVehicleEntitlementSettled),
      formatAmount(leg.balance),
      paymentStatusLabel(leg.paymentStatus),
    ];
  }

  function biltyLegTableHtml(trip: VehicleTrip) {
    const headers = [
      t("vehicleLedger.fields.sideTripType"),
      t("vehicleLedger.fields.biltyNo"),
      t("common.date"),
      t("common.vehicle"),
      t("common.route"),
      t("common.driver"),
      t("vehicleLedger.fields.loadingIds"),
      t("vehicleLedger.fields.loadedThrough"),
      t("vehicleLedger.fields.collectFrom"),
      t("vehicleLedger.fields.rawVehicleFreight"),
      `${t("vehicleLedger.fields.brokerCommission")} (−)`,
      `${t("vehicleLedger.fields.overweightCharges")} (+)`,
      `${t("vehicleLedger.fields.loloCharges")} (+)`,
      `${t("vehicleLedger.fields.detainCharges")} (+)`,
      t("vehicleLedger.fields.adjustedVehicleFreight"),
      t("vehicleLedger.fields.advanceVehicle"),
      t("vehicleLedger.fields.laterVehiclePayments"),
      t("vehicleLedger.fields.totalVehiclePaid"),
      t("vehicleLedger.fields.parchiWithheldCommission"),
      t("vehicleLedger.fields.vehicleEntitlementSettled"),
      t("vehicleLedger.fields.vehicleBalance"),
      t("vehicleLedger.fields.paymentStatus"),
    ];
    const legs = trip.freightLegs ?? [];
    const rows = legs.map((leg) => `<tr>${biltyLegCells(leg).map((value) => `<td>${escapeHtml(value)}</td>`).join("")}</tr>`).join("");
    const totals = biltyTotals(trip);
    const totalRows = [
      [t("vehicleLedger.fields.totalRawVehicleFreight"), formatAmount(totals.totalRaw)],
      [t("vehicleLedger.fields.totalAdjustedVehicleFreight"), formatAmount(totals.totalAdjusted)],
      [t("vehicleLedger.fields.totalVehicleReceived"), formatAmount(totals.totalReceived)],
      [t("vehicleLedger.fields.totalParchiVehicleWithheld"), formatAmount(totals.parchiWithheld)],
      [t("vehicleLedger.fields.totalVehicleEntitlementSettled"), formatAmount(totals.entitlementSettled)],
      [t("vehicleLedger.fields.totalOutstanding"), formatAmount(totals.totalOutstanding)],
      [t("vehicleLedger.fields.paymentStatus"), t(`vehicleLedger.filters.status.${totals.status.toLowerCase()}`)],
    ].map(([label, value]) => `<tr><th>${escapeHtml(label)}</th><td>${escapeHtml(value)}</td></tr>`).join("");
    return `<table class="leg-table"><thead><tr>${headers.map((header) => `<th>${escapeHtml(header)}</th>`).join("")}</tr></thead><tbody>${rows}</tbody></table><div class="chakkar-totals"><h5>${escapeHtml(t("vehicleLedger.fields.chakkarTotals"))}</h5><table>${totalRows}</table></div>`;
  }

  function biltyLegTable(trip: VehicleTrip) {
    const totals = biltyTotals(trip);
    const headers = [
      t("vehicleLedger.fields.sideTripType"),
      t("vehicleLedger.fields.biltyNo"),
      t("common.date"),
      t("common.vehicle"),
      t("common.route"),
      t("common.driver"),
      t("vehicleLedger.fields.loadingIds"),
      t("vehicleLedger.fields.loadedThrough"),
      t("vehicleLedger.fields.collectFrom"),
      t("vehicleLedger.fields.rawVehicleFreight"),
      `${t("vehicleLedger.fields.brokerCommission")} (−)`,
      `${t("vehicleLedger.fields.overweightCharges")} (+)`,
      `${t("vehicleLedger.fields.loloCharges")} (+)`,
      `${t("vehicleLedger.fields.detainCharges")} (+)`,
      t("vehicleLedger.fields.adjustedVehicleFreight"),
      t("vehicleLedger.fields.advanceVehicle"),
      t("vehicleLedger.fields.laterVehiclePayments"),
      t("vehicleLedger.fields.totalVehiclePaid"),
      t("vehicleLedger.fields.parchiWithheldCommission"),
      t("vehicleLedger.fields.vehicleEntitlementSettled"),
      t("vehicleLedger.fields.vehicleBalance"),
      t("vehicleLedger.fields.paymentStatus"),
    ];
    const totalsRows: [string, string][] = [
      [t("vehicleLedger.fields.totalRawVehicleFreight"), formatAmount(totals.totalRaw)],
      [t("vehicleLedger.fields.totalAdjustedVehicleFreight"), formatAmount(totals.totalAdjusted)],
      [t("vehicleLedger.fields.totalVehicleReceived"), formatAmount(totals.totalReceived)],
      [t("vehicleLedger.fields.totalParchiVehicleWithheld"), formatAmount(totals.parchiWithheld)],
      [t("vehicleLedger.fields.totalVehicleEntitlementSettled"), formatAmount(totals.entitlementSettled)],
      [t("vehicleLedger.fields.totalOutstanding"), formatAmount(totals.totalOutstanding)],
      [t("vehicleLedger.fields.paymentStatus"), t(`vehicleLedger.filters.status.${totals.status.toLowerCase()}`)],
    ];
    return <>
      <div className="overflow-x-auto">
        <table className="min-w-[2100px] border-collapse text-xs">
          <thead><tr>{headers.map((header) => <th key={header} className="border border-gray-300 bg-blue-100 px-2 py-2 text-start font-bold text-gray-800">{header}</th>)}</tr></thead>
          <tbody>{(trip.freightLegs ?? []).map((leg) => <tr key={leg.bookingId}>
            {biltyLegCells(leg).map((value, index) => <td key={`${leg.bookingId}-${index}`} dir={index >= 5 && index <= 14 ? "ltr" : "auto"} className="border border-gray-300 bg-white px-2 py-2 text-start font-medium text-gray-800">{value}</td>)}
          </tr>)}</tbody>
        </table>
      </div>
      <div className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-3">
        {totalsRows.map(([label, value]) => <div key={label} className="rounded-md border border-blue-200 bg-white px-3 py-2"><InfoRow label={label} value={value} strong /></div>)}
      </div>
    </>;
  }

  function handlePrint() {
    const tripHtml = vehicleReport.trips.map((trip) => {
      const leftRows = freightRows(trip).map(([label, value]) =>
        `<tr><th>${escapeHtml(label)}</th><td>${escapeHtml(value)}</td></tr>`).join("");
      const freightContent = trip.sourceType === "bilty"
        ? `<table class="general-table">${leftRows}</table>${biltyLegTableHtml(trip)}`
        : `<table class="general-table">${leftRows}</table>`;
      const expenseRows = trip.expenseItems.length
        ? trip.expenseItems.map((item) => `<tr><td>${escapeHtml(item.category)}</td><td>${escapeHtml(item.source || "—")}</td><td dir="ltr">${escapeHtml(formatAmount(item.amount))}</td></tr>`).join("")
        : `<tr><td colspan="3">${escapeHtml(t("vehicleLedger.modal.noTripExpenses"))}</td></tr>`;
      const summary = trip.sourceType === "manual"
        ? `<p>${escapeHtml(formatAmount(trip.income))} − ${escapeHtml(formatAmount(trip.totalExpense))} = <strong>${escapeHtml(formatAmount(trip.profit))}</strong></p>`
        : `<p>${escapeHtml(formatAmount(trip.income))} − ${escapeHtml(formatAmount(trip.totalExpense))} = <strong>${escapeHtml(formatAmount(trip.profit))}</strong></p>`;
      return `<section class="trip"><h3>${escapeHtml(trip.sourceType === "manual" ? trip.voucherNo : trip.biltyNo)} · ${escapeHtml(trip.date)}</h3><div class="columns${trip.sourceType === "bilty" ? " bilty-columns" : ""}"><div><h4>${escapeHtml(t("vehicleLedger.modal.freightRecovery"))}</h4>${freightContent}</div><div><h4>${escapeHtml(t("vehicleLedger.modal.tripExpenses"))}</h4><table><thead><tr><th>${escapeHtml(t("vehicleLedger.fields.category"))}</th><th>${escapeHtml(t("vehicleLedger.fields.source"))}</th><th>${escapeHtml(t("vehicleLedger.fields.amount"))}</th></tr></thead><tbody>${expenseRows}</tbody></table><p>${escapeHtml(t("vehicleLedger.fields.totalTripExpenses"))}: <strong>${escapeHtml(formatAmount(trip.totalExpense))}</strong></p></div></div><div class="net"><strong>${escapeHtml(t("vehicleLedger.modal.netVehicleEarnings"))}</strong>${summary}</div></section>`;
    }).join("");
    const printWindow = window.open("", "_blank", "width=1200,height=850");
    if (!printWindow) { alert(t("vehicleLedger.messages.allowPopups")); return; }
    printWindow.document.write(`<!DOCTYPE html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head><title>${escapeHtml(t("vehicleLedger.title"))}</title><style>
      @page{size:landscape;margin:10mm}body{font-family:Arial,sans-serif;padding:24px;color:#111827}h1,h2{text-align:center;margin:0}h2{margin:8px 0 18px}.totals{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:18px}.total,.net{border:1px solid #cbd5e1;border-radius:7px;padding:10px}.trip{border:1px solid #94a3b8;border-radius:9px;padding:14px;margin:14px 0;page-break-inside:avoid}.columns{display:grid;grid-template-columns:1fr 1fr;gap:12px}.bilty-columns{grid-template-columns:1fr}h3{margin:0 0 10px}h4{margin:4px 0 8px}table{width:100%;border-collapse:collapse;font-size:11px}.leg-table{font-size:7px}.leg-table td,.leg-table th{padding:3px}.chakkar-totals{margin-top:8px}.chakkar-totals h5{margin:4px 0}.general-table{margin-bottom:8px}td,th{border:1px solid #cbd5e1;padding:6px;text-align:start}th{background:#eff6ff}.net{margin-top:10px}.net p{margin:5px 0}@media print{body{padding:0}.trip{page-break-inside:avoid}}
      </style></head><body dir="${escapeHtml(dir)}"><h1>${escapeHtml(printAddaName)}</h1><h2>${escapeHtml(vehicleReport.vehicleNo)} · ${escapeHtml(t("vehicleLedger.title"))}</h2><div class="totals"><div class="total">${escapeHtml(t("vehicleLedger.cards.totalTrips"))}: ${vehicleReport.totalTrips}</div><div class="total">${escapeHtml(t("vehicleLedger.cards.totalVehicleFreight"))}: ${escapeHtml(formatAmount(vehicleReport.totalVehicleFreight))}</div><div class="total">${escapeHtml(t("vehicleLedger.cards.totalReceived"))}: ${escapeHtml(formatAmount(vehicleReport.totalReceived))}</div><div class="total">${escapeHtml(t("vehicleLedger.cards.parchiVehicleWithheld"))}: ${escapeHtml(formatAmount(vehicleReport.totalParchiVehicleWithheld))}</div><div class="total">${escapeHtml(t("vehicleLedger.cards.vehicleEntitlementSettled"))}: ${escapeHtml(formatAmount(vehicleReport.totalVehicleEntitlementSettled))}</div><div class="total">${escapeHtml(t("vehicleLedger.cards.totalOutstanding"))}: ${escapeHtml(formatAmount(vehicleReport.totalOutstanding))}</div><div class="total">${escapeHtml(t("vehicleLedger.cards.totalExpense"))}: ${escapeHtml(formatAmount(vehicleReport.totalExpense))}</div><div class="total">${escapeHtml(t("vehicleLedger.cards.netVehicleEarnings"))}: ${escapeHtml(formatAmount(vehicleReport.netVehicleEarnings))}</div></div>${tripHtml}<script>window.onload=function(){window.print();window.onafterprint=function(){window.close()}}</script></body></html>`);
    printWindow.document.close();
  }

  return (
    <div dir={dir} className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <div role="dialog" aria-modal="true" aria-labelledby="vehicle-trips-modal-title" aria-describedby="vehicle-trips-modal-description" className="max-h-[92vh] w-full max-w-7xl overflow-hidden rounded-xl bg-white shadow-xl">
        <div className="flex items-start justify-between gap-4 border-b border-gray-200 p-5">
          <div><h3 id="vehicle-trips-modal-title" className="text-2xl font-bold text-gray-900"><span dir="ltr">{vehicleReport.vehicleNo}</span> {t("vehicleLedger.modal.tripsDetail")}</h3><p id="vehicle-trips-modal-description" className="mt-1 text-sm font-medium text-gray-700">{t("vehicleLedger.modal.description")}</p></div>
          <div className="flex gap-3"><LedgerStatementPrintButton addaId={printAddaId} documentType="vehicle_ledger" initialLanguage={language} makePresentation={(printLanguage) => vehicleLedgerPrintPresentation(vehicleReport, printLanguage, period)} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={handlePrint} unavailableReason={vehicleReport.trips.length && !printAddaId ? (language === "ur" ? "مخلوط یا غیر تصدیق شدہ اڈے والی رپورٹ پرنٹ نہیں ہو سکتی۔" : "A mixed or unresolved Adda report cannot be printed.") : undefined}><button ref={closeButtonRef} type="button" disabled={!printAddaId} className="rounded-lg bg-blue-600 px-4 py-2 font-bold text-white shadow-sm hover:bg-blue-700 disabled:opacity-50">{t("common.actions.print")}</button></LedgerStatementPrintButton><button type="button" onClick={onClose} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50">{t("common.actions.close")}</button></div>
        </div>
        <div className="max-h-[calc(92vh-84px)] overflow-auto p-5">
          <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-3 2xl:grid-cols-6">
            <Metric label={t("vehicleLedger.cards.totalTrips")} value={String(vehicleReport.totalTrips)} />
            <Metric label={t("vehicleLedger.cards.totalVehicleFreight")} value={formatAmount(vehicleReport.totalVehicleFreight)} />
          <Metric label={t("vehicleLedger.cards.totalReceived")} value={formatAmount(vehicleReport.totalReceived)} />
            <Metric label={t("vehicleLedger.cards.parchiVehicleWithheld")} value={formatAmount(vehicleReport.totalParchiVehicleWithheld)} />
            <Metric label={t("vehicleLedger.cards.vehicleEntitlementSettled")} value={formatAmount(vehicleReport.totalVehicleEntitlementSettled)} />
            <Metric label={t("vehicleLedger.cards.totalOutstanding")} value={formatAmount(vehicleReport.totalOutstanding)} />
            <Metric label={t("vehicleLedger.cards.totalExpense")} value={formatAmount(vehicleReport.totalExpense)} />
            <Metric label={t("vehicleLedger.cards.netVehicleEarnings")} value={formatAmount(vehicleReport.netVehicleEarnings)} />
          </div>
          <div className="space-y-5">
            {vehicleReport.trips.map((trip) => (
              <article key={trip.id} className="rounded-xl border border-gray-300 p-4 shadow-sm">
                <div className="mb-4 flex flex-wrap items-center justify-between gap-2 border-b border-gray-200 pb-3">
                  <h4 className="text-lg font-bold text-gray-900">{trip.sourceType === "manual" ? trip.voucherNo : trip.biltyNo}</h4>
                  <span className="rounded-full bg-slate-100 px-3 py-1 text-sm font-semibold text-gray-800">{trip.date} · {trip.tripType}</span>
                </div>
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                  <section className="rounded-lg border border-blue-200 bg-blue-50/40 p-4">
                    <h5 className="mb-3 text-base font-bold text-gray-900">{t("vehicleLedger.modal.freightRecovery")}</h5>
                    {trip.sourceType === "bilty" ? <>
                      <div className="divide-y divide-gray-200">{freightRows(trip).map(([label, value]) => <InfoRow key={label} label={label} value={value} />)}</div>
                      <div className="mt-3 border-t border-blue-200 pt-3">{biltyLegTable(trip)}</div>
                    </> : <div className="divide-y divide-gray-200">{freightRows(trip).map(([label, value]) => <InfoRow key={label} label={label} value={value} />)}</div>}
                  </section>
                  <section className="rounded-lg border border-amber-200 bg-amber-50/30 p-4">
                    <h5 className="mb-3 text-base font-bold text-gray-900">{t("vehicleLedger.modal.tripExpenses")}</h5>
                    {trip.expenseItems.length ? <div className="space-y-2">
                      {trip.expenseItems.map((item) => <div key={item.id} className="rounded-md border border-gray-200 bg-white p-3">
                        <div className="flex items-start justify-between gap-3"><div><p className="font-bold text-gray-900">{item.category}</p><p className="mt-1 text-sm text-gray-700">{item.source || "—"}</p></div><p dir="ltr" className="whitespace-nowrap font-bold text-gray-900">{formatAmount(item.amount)}</p></div>
                        {item.diesel && <p className="mt-2 text-xs font-medium text-gray-700">{t("vehicleLedger.fields.dieselPaymentDetails")}: {t("vehicleLedger.fields.paid")}: {formatAmount(item.diesel.paid)} · {t("vehicleLedger.fields.remaining")}: {formatAmount(item.diesel.remaining)} · {t("vehicleLedger.fields.paymentStatus")}: {item.diesel.status} · {t("vehicleLedger.fields.slipNo")}: {item.diesel.slipNo}</p>}
                      </div>)}
                    </div> : <p className="rounded-md bg-white p-4 text-sm font-medium text-gray-600">{t("vehicleLedger.modal.noTripExpenses")}</p>}
                    <div className="mt-4 border-t border-gray-300 pt-3"><InfoRow label={t("vehicleLedger.fields.totalTripExpenses")} value={formatAmount(trip.totalExpense)} strong /></div>
                  </section>
                </div>
                <div className="mt-4 rounded-lg bg-slate-900 p-4 text-white"><p className="text-sm font-semibold">{t("vehicleLedger.modal.netVehicleEarnings")}</p><p dir="ltr" className="mt-1 text-lg font-bold">{formatAmount(trip.income)} − {formatAmount(trip.totalExpense)} = {formatAmount(trip.profit)}</p>{trip.sourceType === "manual" && <p className="mt-1 text-xs text-slate-200">{t("vehicleLedger.modal.manualSettlementAuthority")}</p>}</div>
              </article>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-lg border border-gray-300 bg-white p-3"><p className="text-xs font-semibold text-gray-600">{label}</p><p dir="ltr" className="mt-1 font-bold text-gray-900">{value}</p></div>;
}

function InfoRow({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) {
  return <div className="flex items-start justify-between gap-3 py-2"><span className="text-sm font-medium text-gray-700">{label}</span><span dir="auto" className={`text-right text-sm ${strong ? "font-bold text-gray-900" : "font-semibold text-gray-900"}`}>{value}</span></div>;
}

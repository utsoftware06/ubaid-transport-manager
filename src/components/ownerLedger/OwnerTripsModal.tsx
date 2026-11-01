"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VehicleTripsModal from "@/components/vehicleLedger/VehicleTripsModal";
import { formatAmount } from "@/components/vehicleLedger/reporting";
import { printOwnerLedger } from "@/components/ownerLedger/printOwnerLedger";
import LedgerStatementPrintButton, { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { ownerLedgerPrintPresentation } from "@/components/ownerLedger/ownerLedgerPrintPresentation";
import type { OwnerLedgerSummary, OwnerReport } from "@/components/ownerLedger/types";
import type { VehicleReport } from "@/components/vehicleLedger/VehicleLedger";
import type { VehicleFilterType } from "@/components/vehicleLedger/VehicleLedger";

type Props = { ownerReport: OwnerReport; period: { filterType: VehicleFilterType; fromDate: string; toDate: string }; onClose: () => void };

export default function OwnerTripsModal({ ownerReport, period, onClose }: Props) {
  const { t, dir, language } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const [selectedVehicleReport, setSelectedVehicleReport] = useState<VehicleReport | null>(null);
  const summary = useMemo<OwnerLedgerSummary>(() => ({
    totalOwners: 1,
    totalVehicles: ownerReport.totalVehicles,
    totalTrips: ownerReport.totalTrips,
    totalVehicleFreight: ownerReport.totalVehicleFreight,
    totalReceived: ownerReport.totalReceived,
    totalParchiVehicleWithheld: ownerReport.totalParchiVehicleWithheld,
    totalVehicleEntitlementSettled: ownerReport.totalVehicleEntitlementSettled,
    totalOutstanding: ownerReport.totalOutstanding,
    totalExpenses: ownerReport.totalExpenses,
    netVehicleEarnings: ownerReport.netVehicleEarnings,
  }), [ownerReport]);
  const ownerAddaId = singleResolvedAddaId(ownerReport.trips.map((trip) => trip.addaId));

  useEffect(() => {
    const previousFocus = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();
    const handleKeyDown = (event: KeyboardEvent) => { if (event.key === "Escape" && !selectedVehicleReport) onClose(); };
    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocus?.focus();
    };
  }, [onClose, selectedVehicleReport]);

  return <>
    <div dir={dir} role="dialog" aria-modal="true" aria-labelledby="owner-trips-modal-title" className="fixed inset-0 z-40 flex items-center justify-center bg-black/50 p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="max-h-[92vh] w-full max-w-6xl overflow-hidden rounded-xl bg-white shadow-xl">
        <div className="flex items-start justify-between gap-4 border-b border-gray-200 p-5">
          <div><h3 id="owner-trips-modal-title" className="text-2xl font-bold text-gray-900">{ownerReport.ownerName} · {t("ownerLedger.modal.tripsDetail")}</h3><p className="mt-1 text-sm font-medium text-gray-700">{t("ownerLedger.modal.description")}</p></div>
          <div className="flex gap-3">
            <LedgerStatementPrintButton addaId={ownerAddaId} documentType="owner_ledger" initialLanguage={language} makePresentation={(printLanguage) => ownerLedgerPrintPresentation([ownerReport], summary, printLanguage, period)} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={() => printOwnerLedger([ownerReport], summary, t, dir, language)}>
              <button type="button" disabled={!ownerAddaId} className="rounded-lg bg-blue-600 px-4 py-2 font-bold text-white hover:bg-blue-700 disabled:opacity-50">{t("common.actions.print")}</button>
            </LedgerStatementPrintButton>
            <button ref={closeButtonRef} type="button" onClick={onClose} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50">{t("common.actions.close")}</button>
          </div>
        </div>
        <div className="max-h-[calc(92vh-84px)] overflow-auto p-5">
          <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Metric label={t("ownerLedger.summary.totalVehicles")} value={String(ownerReport.totalVehicles)} />
            <Metric label={t("ownerLedger.summary.totalTrips")} value={String(ownerReport.totalTrips)} />
            <Metric label={t("ownerLedger.summary.totalVehicleFreight")} value={formatAmount(ownerReport.totalVehicleFreight)} />
            <Metric label={t("ownerLedger.summary.totalReceived")} value={formatAmount(ownerReport.totalReceived)} />
            <Metric label={t("vehicleLedger.cards.parchiVehicleWithheld")} value={formatAmount(ownerReport.totalParchiVehicleWithheld)} />
            <Metric label={t("vehicleLedger.cards.vehicleEntitlementSettled")} value={formatAmount(ownerReport.totalVehicleEntitlementSettled)} />
            <Metric label={t("ownerLedger.summary.totalOutstanding")} value={formatAmount(ownerReport.totalOutstanding)} />
            <Metric label={t("ownerLedger.summary.totalExpense")} value={formatAmount(ownerReport.totalExpenses)} />
            <Metric label={t("ownerLedger.summary.netVehicleEarnings")} value={formatAmount(ownerReport.netVehicleEarnings)} />
          </div>
          <div className="space-y-4">
            {ownerReport.vehicles.map((vehicle) => <article key={vehicle.vehicleId} className="rounded-xl border border-gray-300 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3 border-b border-gray-200 pb-3">
                <div><h4 className="text-lg font-bold text-gray-900">{vehicle.vehicleNo}</h4><p className="mt-1 text-sm font-medium text-gray-600">{vehicle.totalTrips} {t("ownerLedger.summary.totalTrips")} · {t("ownerLedger.summary.totalVehicleFreight")}: {formatAmount(vehicle.totalVehicleFreight)} · {t("ownerLedger.summary.totalExpense")}: {formatAmount(vehicle.totalExpense)} · {t("ownerLedger.summary.netVehicleEarnings")}: {formatAmount(vehicle.netVehicleEarnings)}</p></div>
                <button type="button" onClick={() => setSelectedVehicleReport(vehicle)} className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-bold text-white hover:bg-indigo-700">{t("vehicleLedger.actions.viewTrips")}</button>
              </div>
              <div className="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
                {vehicle.trips.map((trip) => <div key={trip.id} className="rounded-lg bg-gray-50 p-3 text-sm"><p className="font-bold text-gray-900">{trip.sourceType === "manual" ? trip.voucherNo : trip.biltyNo}</p><p className="mt-1 text-gray-700">{trip.date} · {trip.route}</p><p className="mt-1 text-gray-700">{t("ownerLedger.summary.totalExpense")}: {formatAmount(trip.totalExpense)} · {t("ownerLedger.summary.netVehicleEarnings")}: {formatAmount(trip.profit)}</p></div>)}
              </div>
            </article>)}
          </div>
        </div>
      </div>
    </div>
    {selectedVehicleReport && <VehicleTripsModal vehicleReport={selectedVehicleReport} period={period} onClose={() => setSelectedVehicleReport(null)} />}
  </>;
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-lg border border-gray-300 bg-white p-3"><p className="text-xs font-semibold text-gray-600">{label}</p><p dir="ltr" className="mt-1 font-bold text-gray-900">{value}</p></div>;
}

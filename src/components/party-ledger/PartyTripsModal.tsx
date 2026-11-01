"use client";

import { useEffect, useRef } from "react";

import { useLanguage } from "@/contexts/LanguageContext";
import { PartyLedgerPrintAction } from "./PartyLedgerPrint";
import type { PartyLedgerPeriod, PartyLedgerReport } from "./types";
import IssuedFreightParchiProjection from "@/components/parchi/IssuedFreightParchiProjection";

type Props = {
  report: PartyLedgerReport;
  dateRange: string;
  period: { period: PartyLedgerPeriod; fromDate: string; toDate: string };
  onClose: () => void;
};

function amount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

export default function PartyTripsModal({ report, dateRange, period, onClose }: Props) {
  const { t, dir } = useLanguage();
  const closeRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const previousFocus =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocus?.focus();
    };
  }, [onClose]);

  return (
    <div
      dir={dir}
      className="fixed inset-0 z-[70] flex items-center justify-center bg-slate-950/45 p-4"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="party-trips-title"
        aria-describedby="party-trips-description"
        className="max-h-[92vh] w-full max-w-7xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 text-slate-900 shadow-2xl md:p-7"
      >
        <header className="flex flex-col justify-between gap-4 border-b border-slate-200 pb-5 sm:flex-row sm:items-start">
          <div>
            <h2 id="party-trips-title" className="text-2xl font-extrabold">
              {report.partyName} — {t("partyLedger.modal.title")}
            </h2>
            <p id="party-trips-description" className="mt-2 font-semibold text-slate-700">
              {report.addaName} · {dateRange}
            </p>
          </div>
          <div className="flex flex-wrap gap-3">
            <PartyLedgerPrintAction reports={[report]} dateRange={dateRange} period={period} title={t("common.actions.print")} />
            <button
              ref={closeRef}
              type="button"
              onClick={onClose}
              className="rounded-lg border border-slate-300 bg-white px-5 py-3 font-bold text-slate-900 hover:bg-slate-50"
            >
              {t("common.actions.close")}
            </button>
          </div>
        </header>

        <div className="my-5 grid grid-cols-2 gap-4 lg:grid-cols-4">
          {[
            [t("partyLedger.fields.totalTrips"), String(report.totalTrips)],
            [t("partyLedger.fields.totalFreight"), amount(report.totalFreight)],
            [t("partyLedger.fields.totalReceived"), amount(report.totalReceived)],
            [t("partyLedger.fields.remaining"), amount(report.remainingBalance)],
          ].map(([label, value]) => (
            <div key={label} className="rounded-lg border border-slate-300 bg-white p-4 shadow-sm">
              <p className="font-semibold text-slate-700">{label}</p>
              <p dir="ltr" className="mt-2 text-xl font-extrabold text-slate-900">{value}</p>
            </div>
          ))}
        </div>

        <div className="mb-5">
          <IssuedFreightParchiProjection addaId={report.addaId} payerType="party" payerId={report.partyId} />
        </div>

        <div className="overflow-x-auto rounded-lg border border-slate-200">
          <table className="w-full min-w-[1450px] text-sm">
            <thead>
              <tr className="bg-blue-600 text-white">
                <th className="p-3 text-start">{t("common.date")}</th>
                <th className="p-3 text-start">{t("common.loadingNo")}</th>
                <th className="p-3 text-start">{t("common.bookingNo")}</th>
                <th className="p-3 text-start">{t("common.route")}</th>
                <th className="p-3 text-start">{t("common.vehicle")}</th>
                <th className="p-3 text-start">{t("common.driver")}</th>
                <th className="p-3 text-end">{t("common.freight")}</th>
                <th className="p-3 text-end">{t("common.advance")}</th>
                <th className="p-3 text-end">{t("partyLedger.fields.receiptPayments")}</th>
                <th className="p-3 text-end">{t("partyLedger.fields.totalReceived")}</th>
                <th className="p-3 text-end">{t("partyLedger.fields.remaining")}</th>
                <th className="p-3 text-start">{t("partyLedger.fields.status")}</th>
              </tr>
            </thead>
            <tbody>
              {report.trips.map((trip) => (
                <tr key={trip.id} className="border-b border-slate-200 hover:bg-slate-50">
                  <td dir="ltr" className="p-3">{trip.loadingDate}</td>
                  <td dir="ltr" className="p-3 font-bold">{trip.loadingNo}</td>
                  <td dir="ltr" className="p-3">{trip.bookingNo}</td>
                  <td className="p-3">{trip.route}</td>
                  <td dir="ltr" className="p-3">{trip.vehicleNo}</td>
                  <td className="p-3">{trip.driverName}</td>
                  <td dir="ltr" className="p-3 text-end">{amount(trip.freight)}</td>
                  <td dir="ltr" className="p-3 text-end">{amount(trip.advance)}</td>
                  <td dir="ltr" className="p-3 text-end">{amount(trip.receiptPayments)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold">{amount(trip.totalReceived)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold">{amount(trip.remaining)}</td>
                  <td className="p-3">{t(`partyLedger.status.${trip.paymentStatus}`)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

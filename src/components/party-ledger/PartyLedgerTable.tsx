"use client";

import { useState } from "react";

import { useLanguage } from "@/contexts/LanguageContext";
import type { PartyLedgerPeriod, PartyLedgerReport } from "./types";
import { PartyLedgerPrintAction } from "./PartyLedgerPrint";

type Props = {
  reports: PartyLedgerReport[];
  isLoading: boolean;
  errorMessage: string;
  onViewTrips: (report: PartyLedgerReport) => void;
  dateRange: string;
  period: { period: PartyLedgerPeriod; fromDate: string; toDate: string };
};

function amount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

export default function PartyLedgerTable({
  reports,
  isLoading,
  errorMessage,
  onViewTrips,
  dateRange,
  period,
}: Props) {
  const { t } = useLanguage();
  const [page, setPage] = useState(1);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(reports.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleReports = reports.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );

  return (
    <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm md:p-6">
      <div className="overflow-x-auto rounded-lg border border-slate-200">
        <table className="w-full min-w-[1100px] border-collapse text-sm text-slate-900">
          <thead>
            <tr className="bg-blue-600 text-white">
              <th className="p-3 text-start">{t("partyLedger.fields.partyName")}</th>
              <th className="p-3 text-start">{t("partyLedger.fields.adda")}</th>
              <th className="p-3 text-end">{t("partyLedger.fields.totalTrips")}</th>
              <th className="p-3 text-end">{t("partyLedger.fields.totalFreight")}</th>
              <th className="p-3 text-end">{t("partyLedger.fields.totalReceived")}</th>
              <th className="p-3 text-end">{t("partyLedger.fields.remaining")}</th>
              <th className="p-3 text-start">{t("partyLedger.fields.status")}</th>
              <th className="p-3 text-start">{t("common.actions.title")}</th>
            </tr>
          </thead>
          <tbody>
            {isLoading && (
              <tr><td colSpan={8} className="p-10 text-center font-bold text-slate-700">{t("partyLedger.states.loading")}</td></tr>
            )}
            {!isLoading && errorMessage && (
              <tr><td colSpan={8} role="alert" className="p-10 text-center font-bold text-red-700">{errorMessage}</td></tr>
            )}
            {!isLoading && !errorMessage && visibleReports.length === 0 && (
              <tr><td colSpan={8} className="p-10 text-center font-bold text-slate-700">{t("partyLedger.states.empty")}</td></tr>
            )}
            {!isLoading && !errorMessage && visibleReports.map((report) => (
              <tr key={report.partyId} className="border-b border-slate-200 last:border-0 hover:bg-slate-50">
                <td className="p-3 font-bold">{report.partyName}</td>
                <td className="p-3 font-semibold">{report.addaName}</td>
                <td dir="ltr" className="p-3 text-end font-bold">{report.totalTrips}</td>
                <td dir="ltr" className="p-3 text-end font-bold">{amount(report.totalFreight)}</td>
                <td dir="ltr" className="p-3 text-end font-bold text-emerald-700">{amount(report.totalReceived)}</td>
                <td dir="ltr" className="p-3 text-end font-bold text-red-700">{amount(report.remainingBalance)}</td>
                <td className="p-3">
                  <span className={`inline-flex rounded-full border px-3 py-1 font-bold ${
                    report.paymentStatus === "paid"
                      ? "border-emerald-200 bg-emerald-50 text-emerald-800"
                      : report.paymentStatus === "partial"
                        ? "border-amber-200 bg-amber-50 text-amber-800"
                        : "border-red-200 bg-red-50 text-red-800"
                  }`}>
                    {t(`partyLedger.status.${report.paymentStatus}`)}
                  </span>
                </td>
                <td className="p-3">
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => onViewTrips(report)}
                      aria-label={`${t("partyLedger.actions.viewTrips")} ${report.partyName}`}
                      className="rounded-lg bg-blue-600 px-3 py-2 font-bold text-white hover:bg-blue-700 focus-visible:ring-2 focus-visible:ring-blue-500"
                    >
                      {t("partyLedger.actions.viewTrips")}
                    </button>
                    <PartyLedgerPrintAction reports={[report]} dateRange={dateRange} period={period} title={t("partyLedger.actions.printStatement")} />
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {!isLoading && !errorMessage && reports.length > 0 && (
        <nav aria-label={t("partyLedger.paginationLabel")} className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <span className="font-bold text-slate-800">
            {t("common.pagination.page")} <span dir="ltr">{currentPage}</span>{" "}
            {t("common.pagination.of")} <span dir="ltr">{totalPages}</span>
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              disabled={currentPage === 1}
              onClick={() => setPage((value) => Math.max(1, value - 1))}
              className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold text-slate-900 hover:bg-slate-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-600"
            >
              {t("common.pagination.previous")}
            </button>
            <button
              type="button"
              disabled={currentPage === totalPages}
              onClick={() => setPage((value) => Math.min(totalPages, value + 1))}
              className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold text-slate-900 hover:bg-slate-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-600"
            >
              {t("common.pagination.next")}
            </button>
          </div>
        </nav>
      )}
    </section>
  );
}

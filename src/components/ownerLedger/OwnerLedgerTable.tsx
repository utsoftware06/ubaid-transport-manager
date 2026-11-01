"use client";

import { useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { formatAmount } from "@/components/vehicleLedger/reporting";
import type { OwnerReport } from "@/components/ownerLedger/types";

type Props = { reports: OwnerReport[]; onViewTrips: (report: OwnerReport) => void };
const PAGE_SIZE = 10;

export default function OwnerLedgerTable({ reports, onViewTrips }: Props) {
  const { t, dir } = useLanguage();
  const [currentPage, setCurrentPage] = useState(1);
  const totalPages = Math.max(1, Math.ceil(reports.length / PAGE_SIZE));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const visibleReports = useMemo(() => reports.slice((safeCurrentPage - 1) * PAGE_SIZE, safeCurrentPage * PAGE_SIZE), [reports, safeCurrentPage]);

  return <section dir={dir} className="rounded-xl bg-white p-6 shadow-md">
    <div className="mb-5"><h2 className="text-2xl font-bold text-gray-900">{t("ownerLedger.table.title")}</h2><p className="mt-1 text-sm font-medium text-gray-700">{t("ownerLedger.table.description")}</p></div>
    {reports.length === 0 ? <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center"><p className="font-semibold text-gray-900">{t("ownerLedger.table.empty")}</p></div> : <>
      <div className="grid grid-cols-1 gap-5 xl:grid-cols-2">
        {visibleReports.map((report) => <article key={report.ownerName} className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
          <div className="border-b border-gray-200 pb-3"><p className="text-sm font-semibold text-gray-700">{t("ownerLedger.ownerName")}</p><h3 className="mt-1 text-xl font-bold text-gray-900">{report.ownerName}</h3></div>
          <div className="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
            <Summary label={t("ownerLedger.summary.totalVehicles")} value={String(report.totalVehicles)} />
            <Summary label={t("ownerLedger.summary.totalTrips")} value={String(report.totalTrips)} />
            <Summary label={t("ownerLedger.summary.totalVehicleFreight")} value={formatAmount(report.totalVehicleFreight)} />
            <Summary label={t("ownerLedger.summary.totalReceived")} value={formatAmount(report.totalReceived)} />
            <Summary label={t("vehicleLedger.cards.parchiVehicleWithheld")} value={formatAmount(report.totalParchiVehicleWithheld)} />
            <Summary label={t("vehicleLedger.cards.vehicleEntitlementSettled")} value={formatAmount(report.totalVehicleEntitlementSettled)} />
            <Summary label={t("ownerLedger.summary.totalOutstanding")} value={formatAmount(report.totalOutstanding)} />
            <Summary label={t("ownerLedger.summary.totalExpense")} value={formatAmount(report.totalExpenses)} />
            <Summary label={t("ownerLedger.summary.netVehicleEarnings")} value={formatAmount(report.netVehicleEarnings)} />
          </div>
          <div className="mt-5 flex justify-end border-t border-gray-200 pt-4"><button type="button" onClick={() => onViewTrips(report)} aria-label={`${t("ownerLedger.actions.viewTrips")} ${report.ownerName}`} className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-bold text-white shadow-sm hover:bg-blue-700">{t("ownerLedger.actions.viewTrips")}</button></div>
        </article>)}
      </div>
      <nav aria-label={t("common.pagination.page")} className="mt-5 flex flex-wrap items-center justify-center gap-3">
        <button type="button" onClick={() => setCurrentPage((page) => Math.max(1, page - 1))} disabled={safeCurrentPage === 1} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button>
        <span dir="ltr" aria-current="page" className="font-bold text-gray-900">{t("common.pagination.page")} {safeCurrentPage} {t("common.pagination.of")} {totalPages}</span>
        <button type="button" onClick={() => setCurrentPage((page) => Math.min(totalPages, page + 1))} disabled={safeCurrentPage === totalPages} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button>
      </nav>
    </>}
  </section>;
}

function Summary({ label, value }: { label: string; value: string }) {
  return <div><p className="text-xs font-semibold text-gray-600">{label}</p><p dir="ltr" className="mt-1 text-sm font-bold text-gray-900">{value}</p></div>;
}

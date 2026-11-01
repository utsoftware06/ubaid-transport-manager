"use client";

import type { Dispatch, SetStateAction } from "react";
import type { VehicleReport } from "./VehicleLedger";
import { formatAmount } from "./reporting";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  reports: VehicleReport[];
  page: number;
  setPage: Dispatch<SetStateAction<number>>;
  onViewTrips: (vehicleReport: VehicleReport) => void;
};

export default function VehicleLedgerTable({ reports, page, setPage, onViewTrips }: Props) {
  const { t, dir } = useLanguage();
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(reports.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleReports = reports.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-gray-900">{t("vehicleLedger.summaryTitle")}</h2>
        <p className="mt-1 text-sm font-medium text-gray-700">{t("vehicleLedger.summaryDescription")}</p>
        <p className="mt-1 text-xs font-medium text-gray-600">{t("vehicleLedger.cards.paymentScope")}</p>
      </div>
      {reports.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-semibold text-gray-900">{t("vehicleLedger.empty")}</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
          {visibleReports.map((report) => (
            <article key={report.vehicleId} className="rounded-xl border border-gray-300 bg-white p-5 shadow-sm transition hover:shadow-md">
              <div className="border-b border-gray-200 pb-4">
                <p className="text-sm font-semibold text-gray-700">{t("vehicleLedger.fields.vehicleNumber")}</p>
                <h3 className="mt-1 text-xl font-bold text-gray-900">{report.vehicleNo}</h3>
                <p className="mt-1 text-sm font-semibold text-gray-700">{t("vehicleLedger.fields.ownerName")}: {report.ownerName}</p>
              </div>
              <div className="mt-4 grid grid-cols-2 gap-4">
                <SummaryValue label={t("vehicleLedger.cards.totalTrips")} value={report.totalTrips.toLocaleString("en-PK")} />
                <SummaryValue label={t("vehicleLedger.cards.totalVehicleFreight")} value={formatAmount(report.totalVehicleFreight)} />
                <SummaryValue label={t("vehicleLedger.cards.totalReceived")} value={formatAmount(report.totalReceived)} />
                <SummaryValue label={t("vehicleLedger.cards.parchiVehicleWithheld")} value={formatAmount(report.totalParchiVehicleWithheld)} />
                <SummaryValue label={t("vehicleLedger.cards.vehicleEntitlementSettled")} value={formatAmount(report.totalVehicleEntitlementSettled)} />
                <SummaryValue label={t("vehicleLedger.cards.totalOutstanding")} value={formatAmount(report.totalOutstanding)} />
                <SummaryValue label={t("vehicleLedger.cards.totalExpense")} value={formatAmount(report.totalExpense)} />
                <SummaryValue label={t("vehicleLedger.cards.netVehicleEarnings")} value={formatAmount(report.netVehicleEarnings)} valueClass={report.netVehicleEarnings >= 0 ? "text-green-700" : "text-red-700"} />
              </div>
              <div className="mt-5 flex items-center justify-between border-t border-gray-200 pt-4">
                <span className={`rounded-full px-3 py-1 text-xs font-bold ${report.netVehicleEarnings >= 0 ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"}`}>
                  {report.netVehicleEarnings >= 0 ? t("vehicleLedger.fields.profit") : t("vehicleLedger.fields.loss")}
                </span>
                <button type="button" aria-label={`${t("vehicleLedger.actions.viewTrips")} ${report.vehicleNo}`} onClick={() => onViewTrips(report)}
                  className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-blue-700">
                  {t("vehicleLedger.actions.viewTrips")}
                </button>
              </div>
            </article>
          ))}
        </div>
      )}
      {reports.length > 0 && (
        <div className="mt-5 flex flex-wrap items-center justify-between gap-3 text-gray-900">
          <span className="font-bold">{t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}</span>
          <div className="flex gap-2">
            <button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))}
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">
              {t("common.pagination.previous")}
            </button>
            <button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))}
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">
              {t("common.pagination.next")}
            </button>
          </div>
        </div>
      )}
    </section>
  );
}

function SummaryValue({ label, value, valueClass = "text-gray-900" }: { label: string; value: string; valueClass?: string }) {
  return <div><p className="text-xs font-semibold text-gray-600">{label}</p><p dir="ltr" className={`mt-1 text-base font-bold ${valueClass}`}>{value}</p></div>;
}

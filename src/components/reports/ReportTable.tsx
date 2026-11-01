"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import type { ReportFilterValues } from "@/components/reports/ReportFilters";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";

const PAGE_SIZE = 10;

type RelatedRecord<T> = T | T[] | null;

type BookingRelation = {
  adda_id: string | null;
  freight: number | string | null;
};

type VehicleRelation = {
  adda_id: string | null;
  vehicle_no: string | null;
};

type DriverRelation = {
  name: string | null;
};

type ExpenseItemRelation = {
  amount: number | string | null;
};

type ExpenseRelation = {
  id: number | string;
  expense_items: ExpenseItemRelation[] | null;
};

type LoadingQueryRecord = {
  id: number | string;
  loading_no: string;
  booking_id: number | string | null;
  loading_date: string;
  vehicle_id: string;
  driver_id: string;
  route: string;
  bookings: RelatedRecord<BookingRelation>;
  vehicles: RelatedRecord<VehicleRelation>;
  drivers: RelatedRecord<DriverRelation>;
  expenses: ExpenseRelation[] | null;
};

type ReportRow = {
  id: number | string;
  addaId: string | null;
  loadingNo: string;
  loadingDate: string;
  vehicleId: string;
  vehicle: string;
  driverId: string;
  driver: string;
  route: string;
  income: number;
  expense: number;
  profit: number;
};

type ReportTableProps = {
  filters: ReportFilterValues;
};

function getSingleRelation<T>(relation: RelatedRecord<T>): T | null {
  if (Array.isArray(relation)) {
    return relation[0] ?? null;
  }

  return relation;
}

function toNumber(value: number | string | null | undefined): number {
  const parsedValue = Number(value ?? 0);
  return Number.isFinite(parsedValue) ? parsedValue : 0;
}

function formatAmount(value: number): string {
  return value.toLocaleString("en-PK", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

export default function ReportTable({ filters }: ReportTableProps) {
  const { t, dir, language } = useLanguage();
  const [reports, setReports] = useState<ReportRow[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const reportAddaId = singleResolvedAddaId(filteredReportsForOwner(reports));
  const modulePrint = useModuleTransportPrint("reports", reportAddaId, language === "ur" ? "ur" : "en");

  useEffect(() => {
    let isMounted = true;

    async function loadReports() {
      setIsLoading(true);
      setErrorMessage("");

      const { data, error } = await supabase
        .from("loadings")
        .select(
          `
          id,
          loading_no,
          loading_date,
          booking_id,
          vehicle_id,
          driver_id,
          route,
          bookings(
            adda_id,
            freight
          ),
          vehicles(
            adda_id,
            vehicle_no
          ),
          drivers(
            name
          ),
          expenses(
            id,
            expense_items(
              amount
            )
          )
        `
        )
        .order("loading_date", { ascending: false });

      if (!isMounted) return;

      if (error) {
        console.error("Unable to load report:", error);
        setReports([]);
        setErrorMessage(t("reports.messages.loadError"));
        setIsLoading(false);
        return;
      }

      const loadingRecords = (data ?? []) as unknown as LoadingQueryRecord[];

      const reportRows = loadingRecords.map((loading) => {
        const booking = getSingleRelation(loading.bookings);
        const vehicle = getSingleRelation(loading.vehicles);
        const driver = getSingleRelation(loading.drivers);

        const income = toNumber(booking?.freight);
        const expense = (loading.expenses ?? []).reduce(
          (expenseTotal, expenseRecord) =>
            expenseTotal +
            (expenseRecord.expense_items ?? []).reduce(
              (itemTotal, item) => itemTotal + toNumber(item.amount),
              0
            ),
          0
        );

        return {
          id: loading.id,
          loadingNo: loading.loading_no,
          loadingDate: loading.loading_date,
          vehicleId: loading.vehicle_id,
          vehicle: vehicle?.vehicle_no ?? "-",
          driverId: loading.driver_id,
          driver: driver?.name ?? "-",
          addaId: loading.booking_id != null ? booking?.adda_id ?? null : vehicle?.adda_id ?? null,
          route: loading.route || "-",
          income,
          expense,
          profit: income - expense,
        };
      });

      setReports(reportRows);
      setIsLoading(false);
    }

    void loadReports();

    return () => {
      isMounted = false;
    };
  }, [t]);

  const filteredReports = useMemo(() => {
    const routeSearch = filters.route.trim().toLowerCase();

    return reports.filter((report) => {
      if (filters.fromDate && report.loadingDate < filters.fromDate) {
        return false;
      }

      if (filters.toDate && report.loadingDate > filters.toDate) {
        return false;
      }

      if (filters.vehicle && report.vehicleId !== filters.vehicle) {
        return false;
      }

      if (filters.driver && report.driverId !== filters.driver) {
        return false;
      }

      if (
        routeSearch &&
        !report.route.toLowerCase().includes(routeSearch)
      ) {
        return false;
      }

      return true;
    });
  }, [reports, filters]);

  const totalPages = Math.max(1, Math.ceil(filteredReports.length / PAGE_SIZE));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const visibleReports = useMemo(
    () =>
      filteredReports.slice(
        (safeCurrentPage - 1) * PAGE_SIZE,
        safeCurrentPage * PAGE_SIZE
      ),
    [filteredReports, safeCurrentPage]
  );
  const totals = useMemo(
    () =>
      filteredReports.reduce(
        (summary, report) => ({
          income: summary.income + report.income,
          expense: summary.expense + report.expense,
          profit: summary.profit + report.profit,
        }),
        { income: 0, expense: 0, profit: 0 }
      ),
    [filteredReports]
  );

  function handlePrintFilteredLegacy() {
    if (filteredReports.length === 0) return;
    const printWindow = window.open("", "_blank", "width=1200,height=800");
    if (!printWindow) {
      window.alert(t("reports.messages.allowPopups"));
      return;
    }
    const rowsHtml = filteredReports
      .map(
        (report) => `<tr>
          <td class="technical">${escapeHtml(report.loadingNo)}</td>
          <td class="technical">${escapeHtml(report.loadingDate)}</td>
          <td class="technical">${escapeHtml(report.vehicle)}</td>
          <td>${escapeHtml(report.driver)}</td>
          <td>${escapeHtml(report.route)}</td>
          <td class="technical">${escapeHtml(formatAmount(report.income))}</td>
          <td class="technical">${escapeHtml(formatAmount(report.expense))}</td>
          <td class="technical">${escapeHtml(formatAmount(report.profit))}</td>
        </tr>`
      )
      .join("");
    const ownerIds = Array.from(new Set(filteredReports.map((report) => report.addaId).filter((id): id is string => Boolean(id))));
    void writeAddaBrandedPrintDocument(printWindow, `<!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head>
      <title>${escapeHtml(t("reports.table.title"))}</title>
      <style>
        @page { size:A4 landscape; margin:10mm; }
        body { font-family:Arial,sans-serif; color:#111827; direction:${dir}; }
        h1,h2 { text-align:center; }
        table { width:100%; border-collapse:collapse; font-size:11px; }
        th,td { border:1px solid #d1d5db; padding:7px; text-align:start; }
        th { background:#2563eb; color:white; }
        .technical { direction:ltr; unicode-bidi:isolate; text-align:end; }
      </style></head><body><h1>${PRINT_ADDA_NAME_TOKEN}</h1>
      <h2>${escapeHtml(t("reports.table.title"))}</h2>
      <table><thead><tr>
        <th>${escapeHtml(t("common.loadingNo"))}</th>
        <th>${escapeHtml(t("common.date"))}</th>
        <th>${escapeHtml(t("common.vehicle"))}</th>
        <th>${escapeHtml(t("common.driver"))}</th>
        <th>${escapeHtml(t("common.route"))}</th>
        <th>${escapeHtml(t("common.income"))}</th>
        <th>${escapeHtml(t("common.expense"))}</th>
        <th>${escapeHtml(t("common.profit"))}</th>
      </tr></thead><tbody>${rowsHtml}</tbody>
      <tfoot><tr><th colspan="5">${escapeHtml(t("common.total"))}</th>
      <th class="technical">${escapeHtml(formatAmount(totals.income))}</th>
      <th class="technical">${escapeHtml(formatAmount(totals.expense))}</th>
      <th class="technical">${escapeHtml(formatAmount(totals.profit))}</th>
      </tr></tfoot></table>
      <script>window.onload=function(){window.print();window.onafterprint=function(){window.close();};};</script>
      </body></html>`, ownerIds.length === 1 ? ownerIds[0] : null, language === "ur" ? "ur" : "en");
  }

  function handlePrintFiltered() {
    if (filteredReports.length === 0 || !reportAddaId || filteredReports.some((report) => !report.addaId)) return;
    const presentation: ModulePrintPresentation = {
      documentType: "reports",
      title: printLabel("reports.table.title"),
      subtitle: printLabel("reports.table.description"),
      fields: [
        { label: printLabel("common.date"), value: printValue(`${filters.fromDate || "—"} — ${filters.toDate || "—"}`) },
        { label: printLabel("common.vehicle"), value: printValue(filters.vehicle || null) },
        { label: printLabel("common.driver"), value: printValue(filters.driver || null) },
        { label: printLabel("common.route"), value: printValue(filters.route || null) },
      ],
      tables: [{
        columns: [printLabel("common.loadingNo"), printLabel("common.date"), printLabel("common.vehicle"), printLabel("common.driver"), printLabel("common.route"), printLabel("common.income"), printLabel("common.expense"), printLabel("common.profit")],
        rows: filteredReports.map((report) => [printValue(report.loadingNo), printValue(report.loadingDate), printValue(report.vehicle), printValue(report.driver), printValue(report.route), printValue(formatAmount(report.income)), printValue(formatAmount(report.expense)), printValue(formatAmount(report.profit))]),
      }],
      totals: [
        { label: printLabel("common.income"), value: printValue(formatAmount(totals.income)) },
        { label: printLabel("common.expense"), value: printValue(formatAmount(totals.expense)) },
        { label: printLabel("common.profit"), value: printValue(formatAmount(totals.profit)) },
      ],
    };
    modulePrint.openPresentation(presentation, handlePrintFilteredLegacy, reportAddaId);
  }

  function handleView(report: ReportRow) {
    const status =
      report.profit > 0
        ? t("common.statuses.profit")
        : report.profit < 0
          ? t("common.statuses.loss")
          : t("common.statuses.breakEven");

    window.alert(
      [
        `${t("common.loadingNo")}: ${report.loadingNo}`,
        `${t("common.loadingDate")}: ${report.loadingDate}`,
        `${t("common.vehicle")}: ${report.vehicle}`,
        `${t("common.driver")}: ${report.driver}`,
        `${t("common.route")}: ${report.route}`,
        `${t("common.income")}: Rs. ${formatAmount(report.income)}`,
        `${t("common.expense")}: Rs. ${formatAmount(report.expense)}`,
        `${t("common.profit")}: Rs. ${formatAmount(report.profit)}`,
        `${t("common.status")}: ${status}`,
      ].join("\n")
    );
  }

  function handlePrintLegacy(report: ReportRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      window.alert(t("reports.messages.allowPopups"));
      return;
    }

    const status =
      report.profit > 0
        ? t("common.statuses.profit")
        : report.profit < 0
          ? t("common.statuses.loss")
          : t("common.statuses.breakEven");
    const printLabel = (key: string) => escapeHtml(t(key));

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html dir="${escapeHtml(dir)}" lang="${escapeHtml(language)}">
        <head>
          <title>${printLabel("reports.table.title")} - ${escapeHtml(report.loadingNo)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              background: #ffffff;
              color: #111827;
              font-family: Arial, sans-serif;
            }
            .report {
              max-width: 850px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              padding: 28px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              padding-bottom: 18px;
              border-bottom: 2px solid #2563eb;
            }
            h1 {
              margin: 0;
              font-size: 26px;
            }
            .subtitle {
              margin-top: 6px;
              font-size: 14px;
            }
            .loading-number {
              text-align: right;
              font-size: 15px;
              line-height: 1.7;
            }
            .details {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 14px 24px;
              margin: 24px 0;
            }
            .detail {
              border-bottom: 1px solid #d1d5db;
              padding-bottom: 8px;
              font-size: 15px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              margin-top: 12px;
            }
            th {
              padding: 11px;
              border: 1px solid #2563eb;
              background: #2563eb;
              color: #ffffff;
              text-align: left;
            }
            td {
              padding: 11px;
              border: 1px solid #d1d5db;
              font-weight: 600;
            }
            .right {
              text-align: right;
            }
            .status {
              margin-top: 22px;
              font-size: 16px;
              font-weight: 700;
              text-align: right;
            }
            @media print {
              body { padding: 0; }
              .report { border: 0; }
            }
          </style>
        </head>
        <body>
          <div class="report">
            <div class="header">
              <div>
                <h1>${printLabel("reports.table.title")}</h1>
                <div class="subtitle">Ubaid Transport Manager</div>
              </div>
              <div class="loading-number">
                <div><strong>${printLabel("common.loadingNo")}:</strong> ${escapeHtml(
                  report.loadingNo
                )}</div>
                <div><strong>${printLabel("common.date")}:</strong> ${escapeHtml(
                  report.loadingDate
                )}</div>
              </div>
            </div>

            <div class="details">
              <div class="detail"><strong>${printLabel("common.vehicle")}:</strong> ${escapeHtml(
                report.vehicle
              )}</div>
              <div class="detail"><strong>${printLabel("common.driver")}:</strong> ${escapeHtml(
                report.driver
              )}</div>
              <div class="detail"><strong>${printLabel("common.route")}:</strong> ${escapeHtml(
                report.route
              )}</div>
              <div class="detail"><strong>${printLabel("common.status")}:</strong> ${escapeHtml(status)}</div>
            </div>

            <table>
              <thead>
                <tr>
                  <th>${printLabel("common.income")}</th>
                  <th>${printLabel("common.expense")}</th>
                  <th>${printLabel("common.profit")}</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td class="right">Rs. ${formatAmount(report.income)}</td>
                  <td class="right">Rs. ${formatAmount(report.expense)}</td>
                  <td class="right">Rs. ${formatAmount(report.profit)}</td>
                </tr>
              </tbody>
            </table>

            <div class="status">${printLabel("common.status")}: ${escapeHtml(status)}</div>
          </div>

          <script>
            window.onload = function () {
              window.print();
            };
          </script>
        </body>
      </html>
    `, report.addaId, language === "ur" ? "ur" : "en");
  }

  function handlePrint(report: ReportRow) {
    if (!report.addaId) return;
    const statusKey = report.profit > 0 ? "common.statuses.profit" : report.profit < 0 ? "common.statuses.loss" : "common.statuses.breakEven";
    const presentation: ModulePrintPresentation = {
      documentType: "reports",
      title: printLabel("reports.table.title"),
      documentNo: printValue(report.loadingNo),
      documentDate: printValue(report.loadingDate),
      fields: [
        { label: printLabel("common.vehicle"), value: printValue(report.vehicle) },
        { label: printLabel("common.driver"), value: printValue(report.driver) },
        { label: printLabel("common.route"), value: printValue(report.route) },
        { label: printLabel("common.status"), value: printLabel(statusKey) },
      ],
      totals: [
        { label: printLabel("common.income"), value: printValue(formatAmount(report.income)) },
        { label: printLabel("common.expense"), value: printValue(formatAmount(report.expense)) },
        { label: printLabel("common.profit"), value: printValue(formatAmount(report.profit)) },
      ],
    };
    modulePrint.openPresentation(presentation, () => handlePrintLegacy(report), report.addaId);
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("reports.table.title")}
          </h2>
          <p className="mt-1 text-sm text-gray-600">
            {t("reports.table.description")}
          </p>
        </div>
        <button
          type="button"
          onClick={handlePrintFiltered}
          disabled={filteredReports.length === 0 || !reportAddaId || filteredReports.some((report) => !report.addaId)}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-gray-400"
        >
          {t("common.actions.printReport")}
        </button>
      </div>

      {!isLoading && !errorMessage && filteredReports.length > 0 && (
        <div className="mb-5 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div className="rounded-lg border border-blue-200 bg-blue-50 p-4">
            <p className="font-bold text-gray-900">{t("common.income")}</p>
            <p dir="ltr" className="mt-1 text-xl font-extrabold text-blue-700">Rs. {formatAmount(totals.income)}</p>
          </div>
          <div className="rounded-lg border border-red-200 bg-red-50 p-4">
            <p className="font-bold text-gray-900">{t("common.expense")}</p>
            <p dir="ltr" className="mt-1 text-xl font-extrabold text-red-700">Rs. {formatAmount(totals.expense)}</p>
          </div>
          <div className="rounded-lg border border-green-200 bg-green-50 p-4">
            <p className="font-bold text-gray-900">{t("common.profit")}</p>
            <p dir="ltr" className="mt-1 text-xl font-extrabold text-green-700">Rs. {formatAmount(totals.profit)}</p>
          </div>
        </div>
      )}

      {isLoading && (
        <div className="flex min-h-48 items-center justify-center">
          <div className="flex items-center gap-3 text-gray-900">
            <span className="h-6 w-6 animate-spin rounded-full border-2 border-gray-300 border-t-blue-600" />
            <span className="font-semibold">{t("reports.loading")}</span>
          </div>
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-5 text-red-700">
          <p className="font-bold">{t("reports.messages.loadError")}</p>
          <p className="mt-1 text-sm font-medium">{errorMessage}</p>
        </div>
      )}

      {!isLoading && !errorMessage && (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="w-full min-w-[1200px] border-collapse text-sm">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-semibold">{t("common.loadingNo")}</th>
                <th className="p-3 text-start font-semibold">{t("common.loadingDate")}</th>
                <th className="p-3 text-start font-semibold">{t("common.vehicle")}</th>
                <th className="p-3 text-start font-semibold">{t("common.driver")}</th>
                <th className="p-3 text-start font-semibold">{t("common.route")}</th>
                <th className="p-3 text-end font-semibold">{t("common.income")} (Rs.)</th>
                <th className="p-3 text-end font-semibold">{t("common.expense")} (Rs.)</th>
                <th className="p-3 text-end font-semibold">{t("common.profit")} (Rs.)</th>
                <th className="p-3 text-center font-semibold">{t("common.status")}</th>
                <th className="p-3 text-start font-semibold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody className="bg-white text-gray-900">
              {filteredReports.length === 0 && (
                <tr>
                  <td
                    colSpan={10}
                    className="p-8 text-center font-semibold text-gray-900"
                  >
                    {t("reports.table.empty")}
                  </td>
                </tr>
              )}

              {visibleReports.map((report) => {
                const isProfit = report.profit > 0;
                const isLoss = report.profit < 0;

                return (
                  <tr
                    key={report.id}
                    className="border-b border-gray-200 transition hover:bg-gray-50"
                  >
                    <td className="p-3 font-bold">{report.loadingNo}</td>
                    <td className="p-3 font-medium">{report.loadingDate}</td>
                    <td className="p-3 font-medium">{report.vehicle}</td>
                    <td className="p-3 font-medium">{report.driver}</td>
                    <td className="p-3 font-medium">{report.route}</td>
                    <td dir="ltr" className="p-3 text-end font-bold">
                      {formatAmount(report.income)}
                    </td>
                    <td dir="ltr" className="p-3 text-end font-bold">
                      {formatAmount(report.expense)}
                    </td>
                    <td
                      dir="ltr"
                      className={`p-3 text-end font-bold ${
                        isProfit
                          ? "text-green-700"
                          : isLoss
                            ? "text-red-700"
                            : "text-gray-900"
                      }`}
                    >
                      {formatAmount(report.profit)}
                    </td>
                    <td className="p-3 text-center">
                      {isProfit ? (
                        <span className="inline-flex rounded-full bg-green-100 px-3 py-1 text-xs font-bold text-green-700">
                          {t("common.statuses.profit")}
                        </span>
                      ) : isLoss ? (
                        <span className="inline-flex rounded-full bg-red-100 px-3 py-1 text-xs font-bold text-red-700">
                          {t("common.statuses.loss")}
                        </span>
                      ) : (
                        <span className="inline-flex rounded-full bg-gray-200 px-3 py-1 text-xs font-bold text-gray-800">
                          {t("common.statuses.breakEven")}
                        </span>
                      )}
                    </td>
                    <td className="p-3">
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => handleView(report)}
                          aria-label={`${t("common.actions.view")} ${report.loadingNo}`}
                          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                        >
                          {t("common.actions.view")}
                        </button>
                        <button
                          type="button"
                          onClick={() => handlePrint(report)}
                          aria-label={`${t("common.actions.print")} ${report.loadingNo}`}
                          className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                        >
                          {t("common.actions.print")}
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {!isLoading && !errorMessage && filteredReports.length > 0 && (
        <nav
          aria-label={t("common.pagination.page")}
          className="mt-5 flex flex-wrap items-center justify-center gap-3"
        >
          <button
            type="button"
            onClick={() => setCurrentPage((page) => Math.max(1, page - 1))}
            disabled={safeCurrentPage === 1}
            className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
          >
            {t("common.pagination.previous")}
          </button>
          <span dir="ltr" aria-current="page" className="font-bold text-gray-900">
            {t("common.pagination.page")} {safeCurrentPage} {t("common.pagination.of")} {totalPages}
          </span>
          <button
            type="button"
            onClick={() => setCurrentPage((page) => Math.min(totalPages, page + 1))}
            disabled={safeCurrentPage === totalPages}
            className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
          >
            {t("common.pagination.next")}
          </button>
        </nav>
      )}
      {modulePrint.dialog}
    </div>
  );
}

function filteredReportsForOwner(reports: ReportRow[]): Array<string | null> {
  return reports.map((report) => report.addaId);
}

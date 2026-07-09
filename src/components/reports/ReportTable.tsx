"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import type { ReportFilterValues } from "@/components/reports/ReportFilters";

type RelatedRecord<T> = T | T[] | null;

type BookingRelation = {
  freight: number | string | null;
};

type VehicleRelation = {
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

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export default function ReportTable({ filters }: ReportTableProps) {
  const [reports, setReports] = useState<ReportRow[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

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
          vehicle_id,
          driver_id,
          route,
          bookings(
            freight
          ),
          vehicles(
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
        setReports([]);
        setErrorMessage(error.message);
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
  }, []);

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

  function handleView(report: ReportRow) {
    const status =
      report.profit > 0
        ? "Profit"
        : report.profit < 0
          ? "Loss"
          : "Break Even";

    window.alert(
      [
        `Loading No: ${report.loadingNo}`,
        `Loading Date: ${report.loadingDate}`,
        `Vehicle: ${report.vehicle}`,
        `Driver: ${report.driver}`,
        `Route: ${report.route}`,
        `Income: Rs. ${formatAmount(report.income)}`,
        `Expense: Rs. ${formatAmount(report.expense)}`,
        `Profit: Rs. ${formatAmount(report.profit)}`,
        `Status: ${status}`,
      ].join("\n")
    );
  }

  function handlePrint(report: ReportRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      window.alert("Please allow popups to print this report.");
      return;
    }

    const status =
      report.profit > 0
        ? "Profit"
        : report.profit < 0
          ? "Loss"
          : "Break Even";

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Loading Profit & Loss - ${escapeHtml(report.loadingNo)}</title>
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
                <h1>Loading Profit &amp; Loss Report</h1>
                <div class="subtitle">Ubaid Transport Manager</div>
              </div>
              <div class="loading-number">
                <div><strong>Loading No:</strong> ${escapeHtml(
                  report.loadingNo
                )}</div>
                <div><strong>Date:</strong> ${escapeHtml(
                  report.loadingDate
                )}</div>
              </div>
            </div>

            <div class="details">
              <div class="detail"><strong>Vehicle:</strong> ${escapeHtml(
                report.vehicle
              )}</div>
              <div class="detail"><strong>Driver:</strong> ${escapeHtml(
                report.driver
              )}</div>
              <div class="detail"><strong>Route:</strong> ${escapeHtml(
                report.route
              )}</div>
              <div class="detail"><strong>Status:</strong> ${status}</div>
            </div>

            <table>
              <thead>
                <tr>
                  <th>Income</th>
                  <th>Expense</th>
                  <th>Profit</th>
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

            <div class="status">Status: ${status}</div>
          </div>

          <script>
            window.onload = function () {
              window.print();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  return (
    <div className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          Loading Profit &amp; Loss Report
        </h2>
        <p className="mt-1 text-sm text-gray-600">
          Detailed loading-wise income, expense and profit summary.
        </p>
      </div>

      {isLoading && (
        <div className="flex min-h-48 items-center justify-center">
          <div className="flex items-center gap-3 text-gray-900">
            <span className="h-6 w-6 animate-spin rounded-full border-2 border-gray-300 border-t-blue-600" />
            <span className="font-semibold">Loading report...</span>
          </div>
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-5 text-red-700">
          <p className="font-bold">Unable to load the report.</p>
          <p className="mt-1 text-sm font-medium">{errorMessage}</p>
        </div>
      )}

      {!isLoading && !errorMessage && (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="w-full min-w-[1200px] border-collapse text-sm">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-semibold">Loading No</th>
                <th className="p-3 text-left font-semibold">Loading Date</th>
                <th className="p-3 text-left font-semibold">Vehicle</th>
                <th className="p-3 text-left font-semibold">Driver</th>
                <th className="p-3 text-left font-semibold">Route</th>
                <th className="p-3 text-right font-semibold">Income (Rs.)</th>
                <th className="p-3 text-right font-semibold">Expense (Rs.)</th>
                <th className="p-3 text-right font-semibold">Profit (Rs.)</th>
                <th className="p-3 text-center font-semibold">Status</th>
                <th className="p-3 text-left font-semibold">Actions</th>
              </tr>
            </thead>

            <tbody className="bg-white text-gray-900">
              {filteredReports.length === 0 && (
                <tr>
                  <td
                    colSpan={10}
                    className="p-8 text-center font-semibold text-gray-900"
                  >
                    No loading records found.
                  </td>
                </tr>
              )}

              {filteredReports.map((report) => {
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
                    <td className="p-3 text-right font-bold">
                      {formatAmount(report.income)}
                    </td>
                    <td className="p-3 text-right font-bold">
                      {formatAmount(report.expense)}
                    </td>
                    <td
                      className={`p-3 text-right font-bold ${
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
                          Profit
                        </span>
                      ) : isLoss ? (
                        <span className="inline-flex rounded-full bg-red-100 px-3 py-1 text-xs font-bold text-red-700">
                          Loss
                        </span>
                      ) : (
                        <span className="inline-flex rounded-full bg-gray-200 px-3 py-1 text-xs font-bold text-gray-800">
                          Break Even
                        </span>
                      )}
                    </td>
                    <td className="p-3">
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => handleView(report)}
                          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                        >
                          View
                        </button>
                        <button
                          type="button"
                          onClick={() => handlePrint(report)}
                          className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                        >
                          Print
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
    </div>
  );
}
"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";

type RelatedRecord<T> = T | T[] | null;

type VehicleRelation = {
  vehicle_no: string | null;
};

type BookingRelation = {
  freight: number | string | null;
};

type ExpenseItemRelation = {
  amount: number | string | null;
};

type ExpenseRelation = {
  expense_items: ExpenseItemRelation[] | null;
};

type LoadingRecord = {
  id: number | string;
  loading_no: string;
  vehicle_id: string;
  loading_date: string;
  route: string | null;
  vehicles: RelatedRecord<VehicleRelation>;
  bookings: RelatedRecord<BookingRelation>;
  expenses: ExpenseRelation[] | null;
};

type VehicleReport = {
  vehicleId: string;
  vehicleNumber: string;
  totalTrips: number;
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
};

type DateFilter =
  | "all"
  | "today"
  | "last7Days"
  | "thisMonth"
  | "last6Months"
  | "thisYear"
  | "last10Years"
  | "custom";

type DateFilterOption = {
  value: DateFilter;
  label: string;
};

const dateFilterOptions: DateFilterOption[] = [
  { value: "all", label: "All Time" },
  { value: "today", label: "Today" },
  { value: "last7Days", label: "Last 7 Days" },
  { value: "thisMonth", label: "This Month" },
  { value: "last6Months", label: "Last 6 Months" },
  { value: "thisYear", label: "This Year" },
  { value: "last10Years", label: "Last 10 Years" },
  { value: "custom", label: "Custom Date" },
];

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

function formatInputDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export default function VehicleWiseReport() {
  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [dateFilter, setDateFilter] = useState<DateFilter>("all");
  const [customFromDate, setCustomFromDate] = useState("");
  const [customToDate, setCustomToDate] = useState("");
  const [selectedVehicleId, setSelectedVehicleId] = useState<string | null>(
    null
  );

  useEffect(() => {
    let isMounted = true;

    async function loadVehicleReport() {
      setIsLoading(true);
      setErrorMessage("");

      const { data, error } = await supabase
        .from("loadings")
        .select(
          `
          id,
          loading_no,
          vehicle_id,
          loading_date,
          route,
          vehicles(
            vehicle_no
          ),
          bookings(
            freight
          ),
          expenses(
            expense_items(
              amount
            )
          )
        `
        )
        .order("loading_date", { ascending: false });

      if (!isMounted) return;

      if (error) {
        setLoadings([]);
        setErrorMessage(error.message);
        setIsLoading(false);
        return;
      }

      setLoadings((data ?? []) as unknown as LoadingRecord[]);
      setIsLoading(false);
    }

    void loadVehicleReport();

    return () => {
      isMounted = false;
    };
  }, []);

  function getLoadingIncome(loading: LoadingRecord): number {
    const booking = getSingleRelation(loading.bookings);
    return toNumber(booking?.freight);
  }

  function getLoadingExpense(loading: LoadingRecord): number {
    return (loading.expenses ?? []).reduce(
      (expenseTotal, expense) =>
        expenseTotal +
        (expense.expense_items ?? []).reduce(
          (itemTotal, item) => itemTotal + toNumber(item.amount),
          0
        ),
      0
    );
  }

  const filteredLoadings = useMemo(() => {
    if (dateFilter === "all") return loadings;

    const today = new Date();
    const todayValue = formatInputDate(today);

    let fromDate = "";
    let toDate = todayValue;

    if (dateFilter === "today") {
      fromDate = todayValue;
    }

    if (dateFilter === "last7Days") {
      const startDate = new Date(today);
      startDate.setDate(startDate.getDate() - 6);
      fromDate = formatInputDate(startDate);
    }

    if (dateFilter === "thisMonth") {
      fromDate = formatInputDate(
        new Date(today.getFullYear(), today.getMonth(), 1)
      );
    }

    if (dateFilter === "last6Months") {
      const startDate = new Date(today);
      startDate.setMonth(startDate.getMonth() - 6);
      fromDate = formatInputDate(startDate);
    }

    if (dateFilter === "thisYear") {
      fromDate = `${today.getFullYear()}-01-01`;
    }

    if (dateFilter === "last10Years") {
      fromDate = `${today.getFullYear() - 10}-01-01`;
    }

    if (dateFilter === "custom") {
      fromDate = customFromDate;
      toDate = customToDate;
    }

    return loadings.filter((loading) => {
      if (fromDate && loading.loading_date < fromDate) return false;
      if (toDate && loading.loading_date > toDate) return false;
      return true;
    });
  }, [loadings, dateFilter, customFromDate, customToDate]);

  const vehicleReports = useMemo(() => {
    const reportMap = new Map<string, VehicleReport>();

    filteredLoadings.forEach((loading) => {
      const vehicle = getSingleRelation(loading.vehicles);
      const loadingIncome = getLoadingIncome(loading);
      const loadingExpense = getLoadingExpense(loading);
      const existingReport = reportMap.get(loading.vehicle_id);

      if (existingReport) {
        existingReport.totalTrips += 1;
        existingReport.totalIncome += loadingIncome;
        existingReport.totalExpense += loadingExpense;
        existingReport.netProfit =
          existingReport.totalIncome - existingReport.totalExpense;
        return;
      }

      reportMap.set(loading.vehicle_id, {
        vehicleId: loading.vehicle_id,
        vehicleNumber: vehicle?.vehicle_no ?? "Unknown Vehicle",
        totalTrips: 1,
        totalIncome: loadingIncome,
        totalExpense: loadingExpense,
        netProfit: loadingIncome - loadingExpense,
      });
    });

    return Array.from(reportMap.values()).sort((first, second) =>
      first.vehicleNumber.localeCompare(second.vehicleNumber)
    );
  }, [filteredLoadings]);

  const selectedVehicleReport = useMemo(
    () =>
      vehicleReports.find(
        (report) => report.vehicleId === selectedVehicleId
      ) ?? null,
    [vehicleReports, selectedVehicleId]
  );

  const selectedVehicleLoadings = useMemo(
    () =>
      filteredLoadings.filter(
        (loading) => loading.vehicle_id === selectedVehicleId
      ),
    [filteredLoadings, selectedVehicleId]
  );

  function handleDateFilterChange(value: DateFilter) {
    setDateFilter(value);
    setSelectedVehicleId(null);

    if (value !== "custom") {
      setCustomFromDate("");
      setCustomToDate("");
    }
  }

  function handlePrintReport() {
    if (vehicleReports.length === 0) {
      window.alert("No vehicle report data is available to print.");
      return;
    }

    const printWindow = window.open("", "_blank", "width=1100,height=800");

    if (!printWindow) {
      window.alert("Please allow popups to print the vehicle report.");
      return;
    }

    const activeFilter =
      dateFilterOptions.find((option) => option.value === dateFilter)?.label ??
      "All Time";

    const vehicleSections = vehicleReports
      .map((report) => {
        const vehicleLoadings = filteredLoadings.filter(
          (loading) => loading.vehicle_id === report.vehicleId
        );

        const tripRows = vehicleLoadings
          .map((loading) => {
            const income = getLoadingIncome(loading);
            const expense = getLoadingExpense(loading);
            const profit = income - expense;

            return `
              <tr>
                <td>${escapeHtml(loading.loading_no)}</td>
                <td>${escapeHtml(loading.loading_date)}</td>
                <td>${escapeHtml(loading.route ?? "-")}</td>
                <td class="amount">Rs. ${formatAmount(income)}</td>
                <td class="amount">Rs. ${formatAmount(expense)}</td>
                <td class="amount ${
                  profit > 0 ? "profit" : profit < 0 ? "loss" : ""
                }">
                  Rs. ${formatAmount(profit)}
                </td>
              </tr>
            `;
          })
          .join("");

        return `
          <section class="vehicle-section">
            <h2>${escapeHtml(report.vehicleNumber)}</h2>

            <div class="summary-grid">
              <div class="summary-box">
                <span>Total Trips</span>
                <strong>${report.totalTrips.toLocaleString("en-PK")}</strong>
              </div>

              <div class="summary-box">
                <span>Total Income</span>
                <strong>Rs. ${formatAmount(report.totalIncome)}</strong>
              </div>

              <div class="summary-box">
                <span>Total Expense</span>
                <strong>Rs. ${formatAmount(report.totalExpense)}</strong>
              </div>

              <div class="summary-box">
                <span>Net Profit</span>
                <strong class="${
                  report.netProfit > 0
                    ? "profit"
                    : report.netProfit < 0
                      ? "loss"
                      : ""
                }">
                  Rs. ${formatAmount(report.netProfit)}
                </strong>
              </div>
            </div>

            <table>
              <thead>
                <tr>
                  <th>Loading No</th>
                  <th>Date</th>
                  <th>Route</th>
                  <th>Income</th>
                  <th>Expense</th>
                  <th>Profit</th>
                </tr>
              </thead>
              <tbody>${tripRows}</tbody>
            </table>
          </section>
        `;
      })
      .join("");

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Vehicle Wise Detailed Report</title>
          <style>
            * {
              box-sizing: border-box;
            }

            body {
              margin: 0;
              padding: 28px;
              background: #ffffff;
              color: #111827;
              font-family: Arial, sans-serif;
            }

            .report-header {
              margin-bottom: 30px;
              padding-bottom: 18px;
              border-bottom: 3px solid #2563eb;
              text-align: center;
            }

            .report-header h1 {
              margin: 0;
              font-size: 30px;
              color: #111827;
            }

            .report-header h3 {
              margin: 7px 0 0;
              font-size: 19px;
              color: #111827;
            }

            .filter-label {
              margin-top: 10px;
              font-size: 13px;
              font-weight: 700;
            }

            .vehicle-section {
              margin-bottom: 38px;
              break-inside: avoid;
              page-break-inside: avoid;
            }

            .vehicle-section + .vehicle-section {
              padding-top: 26px;
              border-top: 2px solid #111827;
            }

            .vehicle-section h2 {
              margin: 0 0 16px;
              padding: 11px 14px;
              background: #2563eb;
              color: #ffffff;
              font-size: 21px;
            }

            .summary-grid {
              display: grid;
              grid-template-columns: repeat(4, minmax(0, 1fr));
              gap: 12px;
              margin-bottom: 18px;
            }

            .summary-box {
              min-height: 78px;
              padding: 13px;
              border: 1px solid #d1d5db;
              background: #f9fafb;
            }

            .summary-box span {
              display: block;
              margin-bottom: 8px;
              font-size: 12px;
              font-weight: 700;
            }

            .summary-box strong {
              display: block;
              font-size: 17px;
            }

            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 12px;
            }

            th {
              padding: 10px;
              border: 1px solid #2563eb;
              background: #2563eb;
              color: #ffffff;
              text-align: left;
            }

            td {
              padding: 9px;
              border: 1px solid #d1d5db;
              font-weight: 600;
            }

            .amount {
              text-align: right;
              white-space: nowrap;
            }

            .profit {
              color: #15803d;
            }

            .loss {
              color: #b91c1c;
            }

            @media print {
              body {
                padding: 0;
              }

              .vehicle-section {
                break-inside: avoid;
              }

              .vehicle-section + .vehicle-section {
                break-before: auto;
              }
            }
          </style>
        </head>

        <body>
          <header class="report-header">
            <h1>UT Software</h1>
            <h3>Vehicle Wise Detailed Report</h3>
            <div class="filter-label">
              Period: ${escapeHtml(activeFilter)}
              ${
                dateFilter === "custom"
                  ? ` (${escapeHtml(customFromDate || "Start")} to ${escapeHtml(
                      customToDate || "End"
                    )})`
                  : ""
              }
            </div>
          </header>

          ${vehicleSections}

          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };

            window.onafterprint = function () {
              window.close();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Vehicle Wise Report
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-600">
            Vehicle-wise trips, income, expenses and net profit summary.
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintReport}
          disabled={isLoading || vehicleReports.length === 0}
          className="rounded-lg bg-blue-600 px-5 py-3 font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
        >
          Print Report
        </button>
      </div>

      <div className="mb-6 border-b border-gray-200 pb-6">
        <div className="flex flex-wrap gap-2">
          {dateFilterOptions.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => handleDateFilterChange(option.value)}
              className={`rounded-lg px-4 py-2 text-sm font-semibold transition ${
                dateFilter === option.value
                  ? "bg-blue-600 text-white"
                  : "border border-gray-300 bg-white text-gray-900 hover:bg-gray-50"
              }`}
            >
              {option.label}
            </button>
          ))}
        </div>

        {dateFilter === "custom" && (
          <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <label
                htmlFor="vehicle-report-from-date"
                className="mb-2 block text-sm font-semibold text-gray-900"
              >
                From Date
              </label>
              <input
                id="vehicle-report-from-date"
                type="date"
                value={customFromDate}
                max={customToDate || undefined}
                onChange={(event) => {
                  setCustomFromDate(event.target.value);
                  setSelectedVehicleId(null);
                }}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              />
            </div>

            <div>
              <label
                htmlFor="vehicle-report-to-date"
                className="mb-2 block text-sm font-semibold text-gray-900"
              >
                To Date
              </label>
              <input
                id="vehicle-report-to-date"
                type="date"
                value={customToDate}
                min={customFromDate || undefined}
                onChange={(event) => {
                  setCustomToDate(event.target.value);
                  setSelectedVehicleId(null);
                }}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </div>
        )}
      </div>

      {isLoading && (
        <div className="flex min-h-48 items-center justify-center">
          <div className="flex items-center gap-3 text-gray-900">
            <span className="h-6 w-6 animate-spin rounded-full border-2 border-gray-300 border-t-blue-600" />
            <span className="font-semibold">Loading vehicle report...</span>
          </div>
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-5 text-red-700">
          <p className="font-bold">Unable to load the vehicle report.</p>
          <p className="mt-1 text-sm font-medium">{errorMessage}</p>
        </div>
      )}

      {!isLoading && !errorMessage && vehicleReports.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-semibold text-gray-900">
            No vehicle loading records found for the selected period.
          </p>
        </div>
      )}

      {!isLoading && !errorMessage && vehicleReports.length > 0 && (
        <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
          {vehicleReports.map((report) => {
            const isProfit = report.netProfit > 0;
            const isLoss = report.netProfit < 0;

            return (
              <article
                key={report.vehicleId}
                className="rounded-lg border border-gray-200 bg-white p-5 shadow-sm transition hover:shadow-md"
              >
                <div className="border-b border-gray-200 pb-4">
                  <p className="text-sm font-semibold text-gray-600">
                    Vehicle Number
                  </p>
                  <h3 className="mt-1 text-xl font-bold text-gray-900">
                    {report.vehicleNumber}
                  </h3>
                </div>

                <div className="mt-4 grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-sm font-semibold text-gray-600">
                      Total Trips
                    </p>
                    <p className="mt-1 text-lg font-bold text-gray-900">
                      {report.totalTrips.toLocaleString("en-PK")}
                    </p>
                  </div>

                  <div>
                    <p className="text-sm font-semibold text-gray-600">
                      Total Income
                    </p>
                    <p className="mt-1 text-lg font-bold text-gray-900">
                      Rs. {formatAmount(report.totalIncome)}
                    </p>
                  </div>

                  <div>
                    <p className="text-sm font-semibold text-gray-600">
                      Total Expense
                    </p>
                    <p className="mt-1 text-lg font-bold text-gray-900">
                      Rs. {formatAmount(report.totalExpense)}
                    </p>
                  </div>

                  <div>
                    <p className="text-sm font-semibold text-gray-600">
                      Net Profit
                    </p>
                    <p
                      className={`mt-1 text-lg font-bold ${
                        isProfit
                          ? "text-green-700"
                          : isLoss
                            ? "text-red-700"
                            : "text-gray-900"
                      }`}
                    >
                      Rs. {formatAmount(report.netProfit)}
                    </p>
                  </div>
                </div>

                <div className="mt-5 flex items-center justify-between gap-3 border-t border-gray-200 pt-4">
                  <span
                    className={`inline-flex rounded-full px-3 py-1 text-xs font-bold ${
                      isProfit
                        ? "bg-green-100 text-green-700"
                        : isLoss
                          ? "bg-red-100 text-red-700"
                          : "bg-gray-200 text-gray-800"
                    }`}
                  >
                    {isProfit ? "Profit" : isLoss ? "Loss" : "Break Even"}
                  </span>

                  <button
                    type="button"
                    onClick={() => setSelectedVehicleId(report.vehicleId)}
                    className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-700"
                  >
                    View Trips
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      )}

      {selectedVehicleReport && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="vehicle-trips-title"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) {
              setSelectedVehicleId(null);
            }
          }}
        >
          <div className="max-h-[90vh] w-full max-w-6xl overflow-hidden rounded-xl bg-white shadow-xl">
            <div className="flex items-start justify-between gap-4 border-b border-gray-200 p-5">
              <div>
                <h3
                  id="vehicle-trips-title"
                  className="text-2xl font-bold text-gray-900"
                >
                  {selectedVehicleReport.vehicleNumber} Trips
                </h3>
                <p className="mt-1 text-sm font-medium text-gray-600">
                  Complete loading-wise income, expense and profit details.
                </p>
              </div>

              <button
                type="button"
                onClick={() => setSelectedVehicleId(null)}
                className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50"
              >
                Close
              </button>
            </div>

            <div className="overflow-auto p-5">
              <div className="mb-5 grid grid-cols-2 gap-4 lg:grid-cols-4">
                <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                  <p className="text-sm font-semibold text-gray-600">
                    Total Trips
                  </p>
                  <p className="mt-1 text-xl font-bold text-gray-900">
                    {selectedVehicleReport.totalTrips}
                  </p>
                </div>

                <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                  <p className="text-sm font-semibold text-gray-600">
                    Total Income
                  </p>
                  <p className="mt-1 text-xl font-bold text-gray-900">
                    Rs. {formatAmount(selectedVehicleReport.totalIncome)}
                  </p>
                </div>

                <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                  <p className="text-sm font-semibold text-gray-600">
                    Total Expense
                  </p>
                  <p className="mt-1 text-xl font-bold text-gray-900">
                    Rs. {formatAmount(selectedVehicleReport.totalExpense)}
                  </p>
                </div>

                <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                  <p className="text-sm font-semibold text-gray-600">
                    Net Profit
                  </p>
                  <p
                    className={`mt-1 text-xl font-bold ${
                      selectedVehicleReport.netProfit > 0
                        ? "text-green-700"
                        : selectedVehicleReport.netProfit < 0
                          ? "text-red-700"
                          : "text-gray-900"
                    }`}
                  >
                    Rs. {formatAmount(selectedVehicleReport.netProfit)}
                  </p>
                </div>
              </div>

              <div className="overflow-x-auto rounded-lg border border-gray-200">
                <table className="w-full min-w-[850px] border-collapse text-sm">
                  <thead className="bg-blue-600 text-white">
                    <tr>
                      <th className="p-3 text-left">Loading No</th>
                      <th className="p-3 text-left">Date</th>
                      <th className="p-3 text-left">Route</th>
                      <th className="p-3 text-right">Income</th>
                      <th className="p-3 text-right">Expense</th>
                      <th className="p-3 text-right">Profit</th>
                    </tr>
                  </thead>

                  <tbody className="bg-white text-gray-900">
                    {selectedVehicleLoadings.map((loading) => {
                      const income = getLoadingIncome(loading);
                      const expense = getLoadingExpense(loading);
                      const profit = income - expense;

                      return (
                        <tr
                          key={loading.id}
                          className="border-b border-gray-200 hover:bg-gray-50"
                        >
                          <td className="p-3 font-bold">
                            {loading.loading_no}
                          </td>
                          <td className="p-3 font-medium">
                            {loading.loading_date}
                          </td>
                          <td className="p-3 font-medium">
                            {loading.route ?? "-"}
                          </td>
                          <td className="p-3 text-right font-bold">
                            Rs. {formatAmount(income)}
                          </td>
                          <td className="p-3 text-right font-bold">
                            Rs. {formatAmount(expense)}
                          </td>
                          <td
                            className={`p-3 text-right font-bold ${
                              profit > 0
                                ? "text-green-700"
                                : profit < 0
                                  ? "text-red-700"
                                  : "text-gray-900"
                            }`}
                          >
                            Rs. {formatAmount(profit)}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
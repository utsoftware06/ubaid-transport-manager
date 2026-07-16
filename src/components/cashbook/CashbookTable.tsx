"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  type CashbookEntryRow,
  type CashbookFilterValues,
  type CashbookEntryType,
  type CashbookPersonType,
  type CashbookPaymentMethod,
  formatAmount,
} from "./Cashbook";

type Props = {
  rows: CashbookEntryRow[];
  filters: CashbookFilterValues;
  setFilters: Dispatch<SetStateAction<CashbookFilterValues>>;
  onReset: () => void;
  onSync: () => void;
  isSyncing: boolean;
  isLoading: boolean;
  errorMessage: string;
};

const entryTypes: CashbookEntryType[] = ["Cash In", "Cash Out"];

const personTypes: CashbookPersonType[] = [
  "Customer",
  "Driver",
  "Vehicle Owner",
  "Broker",
  "Adda",
  "Petrol Pump",
  "Workshop",
  "Other",
];

const paymentMethods: CashbookPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

function updateFilter<K extends keyof CashbookFilterValues>(
  setFilters: Dispatch<SetStateAction<CashbookFilterValues>>,
  key: K,
  value: CashbookFilterValues[K]
) {
  setFilters((previous) => ({
    ...previous,
    [key]: value,
  }));
}

function getTypeBadgeClass(entryType: CashbookEntryType) {
  if (entryType === "Cash In") {
    return "border-green-200 bg-green-100 text-green-700";
  }

  return "border-red-200 bg-red-100 text-red-700";
}

function getDateRangeLabel(filters: CashbookFilterValues) {
  if (filters.fromDate && filters.toDate) {
    return `${filters.fromDate} to ${filters.toDate}`;
  }

  if (filters.fromDate) {
    return `From ${filters.fromDate}`;
  }

  if (filters.toDate) {
    return `Up to ${filters.toDate}`;
  }

  return "All Dates";
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export default function CashbookTable({
  rows,
  filters,
  setFilters,
  onReset,
  onSync,
  isSyncing,
  isLoading,
  errorMessage,
}: Props) {
  const totalCashIn = rows
    .filter((row) => row.entryType === "Cash In")
    .reduce((total, row) => total + row.amount, 0);
  const totalCashOut = rows
    .filter((row) => row.entryType === "Cash Out")
    .reduce((total, row) => total + row.amount, 0);
  const finalRunningBalance = rows.at(-1)?.runningBalance ?? 0;

  function handlePrintCashbook() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print cashbook report.");
      return;
    }

    const tableRows =
      rows.length > 0
        ? rows
            .map(
              (row) => `
                <tr>
                  <td>${escapeHtml(row.entryDate || "-")}</td>
                  <td>${escapeHtml(row.entryType)}</td>
                  <td>${escapeHtml(row.personType)}</td>
                  <td>${escapeHtml(row.personName || "-")}</td>
                  <td>${escapeHtml(row.vehicleNo || "-")}</td>
                  <td>${escapeHtml(row.driverName || "-")}</td>
                  <td>${escapeHtml(row.loadingNo || "-")}</td>
                  <td>${escapeHtml(row.paymentMethod)}</td>
                  <td>${escapeHtml(row.description || "-")}</td>
                  <td class="cash-in">${
                    row.entryType === "Cash In"
                      ? escapeHtml(formatAmount(row.amount))
                      : "-"
                  }</td>
                  <td class="cash-out">${
                    row.entryType === "Cash Out"
                      ? escapeHtml(formatAmount(row.amount))
                      : "-"
                  }</td>
                  <td class="${
                    row.runningBalance >= 0 ? "balance-green" : "balance-red"
                  }">${escapeHtml(formatAmount(row.runningBalance))}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="12" class="empty">No cashbook entries found.</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Cashbook Report</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 12mm; }
            body {
              margin: 0;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 2px solid #111827;
              padding-bottom: 16px;
              margin-bottom: 18px;
            }
            h1 {
              margin: 0;
              font-size: 28px;
              color: #111827;
            }
            h2 {
              margin: 4px 0 0;
              font-size: 18px;
              color: #111827;
            }
            .meta {
              text-align: right;
              font-size: 13px;
              line-height: 1.7;
              color: #111827;
            }
            .summary {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 12px;
              margin-bottom: 18px;
            }
            .summary-box {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
            }
            .summary-title {
              font-size: 12px;
              font-weight: 700;
              color: #111827;
            }
            .summary-value {
              margin-top: 5px;
              font-size: 17px;
              font-weight: 800;
              color: #111827;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 10px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: left;
              padding: 7px;
              border: 1px solid #2563eb;
              white-space: nowrap;
            }
            td {
              padding: 7px;
              border: 1px solid #d1d5db;
              color: #111827;
              vertical-align: top;
            }
            .cash-in,
            .balance-green {
              color: #047857;
              font-weight: 700;
              white-space: nowrap;
            }
            .cash-out,
            .balance-red {
              color: #b91c1c;
              font-weight: 700;
              white-space: nowrap;
            }
            .empty {
              text-align: center;
              font-weight: 700;
              padding: 18px;
            }
            tfoot td {
              background: #f9fafb;
              font-weight: 800;
              white-space: nowrap;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>UT Software</h1>
              <h2>Cashbook Report</h2>
            </div>
            <div class="meta">
              <div><strong>Date Range:</strong> ${escapeHtml(
                getDateRangeLabel(filters)
              )}</div>
              <div><strong>Printed:</strong> ${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</div>
            </div>
          </div>

          <div class="summary">
            <div class="summary-box">
              <div class="summary-title">Total Cash In</div>
              <div class="summary-value">${escapeHtml(
                formatAmount(totalCashIn)
              )}</div>
            </div>
            <div class="summary-box">
              <div class="summary-title">Total Cash Out</div>
              <div class="summary-value">${escapeHtml(
                formatAmount(totalCashOut)
              )}</div>
            </div>
            <div class="summary-box">
              <div class="summary-title">Closing Balance</div>
              <div class="summary-value">${escapeHtml(
                formatAmount(finalRunningBalance)
              )}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>Person Type</th>
                <th>Person Name</th>
                <th>Vehicle</th>
                <th>Driver</th>
                <th>Loading</th>
                <th>Payment</th>
                <th>Description</th>
                <th>Cash In</th>
                <th>Cash Out</th>
                <th>Balance</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="9">Total</td>
                <td class="cash-in">${escapeHtml(formatAmount(totalCashIn))}</td>
                <td class="cash-out">${escapeHtml(
                  formatAmount(totalCashOut)
                )}</td>
                <td class="${
                  finalRunningBalance >= 0 ? "balance-green" : "balance-red"
                }">${escapeHtml(formatAmount(finalRunningBalance))}</td>
              </tr>
            </tfoot>
          </table>

          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Cashbook Entries
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Filter, sync, print and review daily cash transactions.
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={handlePrintCashbook}
            className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
          >
            Print Cashbook
          </button>
          <button
            type="button"
            onClick={onSync}
            disabled={isSyncing}
            className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
          >
            {isSyncing ? "Syncing..." : "Sync Auto Entries"}
          </button>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            From Date
          </label>
          <input
            type="date"
            value={filters.fromDate}
            onChange={(event) =>
              updateFilter(setFilters, "fromDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            To Date
          </label>
          <input
            type="date"
            value={filters.toDate}
            onChange={(event) =>
              updateFilter(setFilters, "toDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Entry Type
          </label>
          <select
            value={filters.entryType}
            onChange={(event) =>
              updateFilter(setFilters, "entryType", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All</option>
            {entryTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Person Type
          </label>
          <select
            value={filters.personType}
            onChange={(event) =>
              updateFilter(setFilters, "personType", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All</option>
            {personTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Method
          </label>
          <select
            value={filters.paymentMethod}
            onChange={(event) =>
              updateFilter(setFilters, "paymentMethod", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All</option>
            {paymentMethods.map((method) => (
              <option key={method} value={method}>
                {method}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Search
          </label>
          <input
            type="text"
            value={filters.search}
            onChange={(event) =>
              updateFilter(setFilters, "search", event.target.value)
            }
            placeholder="Search cashbook"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      <div className="mt-4 flex justify-end">
        <button
          type="button"
          onClick={onReset}
          className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
        >
          Reset
        </button>
      </div>

      {isLoading && (
        <div className="mt-6 rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          Loading cashbook entries...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          No cashbook entries found.
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto">
          <table className="w-full min-w-[1300px] border-collapse text-left">
            <thead>
              <tr className="bg-blue-600 text-white">
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Date
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Type
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Person Type
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Person Name
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Vehicle
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Driver
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Loading
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Payment Method
                </th>
                <th className="px-4 py-3 text-sm font-bold">Description</th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Cash In
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Cash Out
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Running Balance
                </th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.entryDate}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getTypeBadgeClass(
                        row.entryType
                      )}`}
                    >
                      {row.entryType}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.personType}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                    {row.personName}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.vehicleNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.driverName}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.loadingNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.paymentMethod}
                  </td>
                  <td className="min-w-[260px] px-4 py-3 text-sm font-semibold">
                    <div>{row.description}</div>
                    {row.referenceType && (
                      <div className="mt-1 text-xs font-bold text-gray-900">
                        Ref: {row.referenceType}
                      </div>
                    )}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold text-green-700">
                    {row.entryType === "Cash In"
                      ? formatAmount(row.amount)
                      : "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold text-red-700">
                    {row.entryType === "Cash Out"
                      ? formatAmount(row.amount)
                      : "-"}
                  </td>
                  <td
                    className={`whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold ${
                      row.runningBalance >= 0
                        ? "text-green-700"
                        : "text-red-700"
                    }`}
                  >
                    {formatAmount(row.runningBalance)}
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={9} className="px-4 py-4 text-sm font-extrabold">
                  Total
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold text-green-700">
                  {formatAmount(totalCashIn)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold text-red-700">
                  {formatAmount(totalCashOut)}
                </td>
                <td
                  className={`whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold ${
                    finalRunningBalance >= 0
                      ? "text-green-700"
                      : "text-red-700"
                  }`}
                >
                  {formatAmount(finalRunningBalance)}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
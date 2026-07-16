"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  type VehicleOption,
  type WorkshopEntryRow,
  type WorkshopFilterValues,
  type WorkshopPaymentStatus,
  formatAmount,
} from "./Workshop";

type Props = {
  rows: WorkshopEntryRow[];
  filters: WorkshopFilterValues;
  setFilters: Dispatch<SetStateAction<WorkshopFilterValues>>;
  vehicles: VehicleOption[];
  onReset: () => void;
  onEdit: (row: WorkshopEntryRow) => void;
  onDelete: (row: WorkshopEntryRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
};

function updateFilter<K extends keyof WorkshopFilterValues>(
  setFilters: Dispatch<SetStateAction<WorkshopFilterValues>>,
  key: K,
  value: WorkshopFilterValues[K]
) {
  setFilters((previous) => ({
    ...previous,
    [key]: value,
  }));
}

function getStatusClass(status: WorkshopPaymentStatus) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function dateRange(filters: WorkshopFilterValues) {
  if (filters.fromDate && filters.toDate) {
    return `${filters.fromDate} to ${filters.toDate}`;
  }

  if (filters.fromDate) return `From ${filters.fromDate}`;
  if (filters.toDate) return `Up to ${filters.toDate}`;
  return "All Dates";
}

export default function WorkshopTable({
  rows,
  filters,
  setFilters,
  vehicles,
  onReset,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const totalParts = rows.reduce((total, row) => total + row.partsCost, 0);
  const totalLabour = rows.reduce((total, row) => total + row.labourCost, 0);
  const totalCost = rows.reduce((total, row) => total + row.totalCost, 0);
  const totalPaid = rows.reduce((total, row) => total + row.paidAmount, 0);
  const totalRemaining = rows.reduce(
    (total, row) => total + row.remainingAmount,
    0
  );

  function openPrintWindow(title: string, printableRows: WorkshopEntryRow[]) {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print workshop report.");
      return;
    }

    const partsTotal = printableRows.reduce(
      (total, row) => total + row.partsCost,
      0
    );
    const labourTotal = printableRows.reduce(
      (total, row) => total + row.labourCost,
      0
    );
    const costTotal = printableRows.reduce(
      (total, row) => total + row.totalCost,
      0
    );
    const paidTotal = printableRows.reduce(
      (total, row) => total + row.paidAmount,
      0
    );
    const remainingTotal = printableRows.reduce(
      (total, row) => total + row.remainingAmount,
      0
    );

    const tableRows =
      printableRows.length > 0
        ? printableRows
            .map(
              (row) => `
                <tr>
                  <td>${escapeHtml(row.workDate || "-")}</td>
                  <td>${escapeHtml(row.vehicleNo)}</td>
                  <td>${escapeHtml(row.ownerName)}</td>
                  <td>${escapeHtml(row.workshopName || "-")}</td>
                  <td>${escapeHtml(row.mechanicName || "-")}</td>
                  <td>${escapeHtml(row.workType || "-")}</td>
                  <td>${escapeHtml(row.billNo || "-")}</td>
                  <td>${escapeHtml(formatAmount(row.partsCost))}</td>
                  <td>${escapeHtml(formatAmount(row.labourCost))}</td>
                  <td>${escapeHtml(formatAmount(row.totalCost))}</td>
                  <td>${escapeHtml(formatAmount(row.paidAmount))}</td>
                  <td>${escapeHtml(formatAmount(row.remainingAmount))}</td>
                  <td>${escapeHtml(row.paymentStatus)}</td>
                  <td>${escapeHtml(row.nextServiceDate || "-")}</td>
                  <td>${escapeHtml(String(row.odometer || "-"))}</td>
                  <td>${escapeHtml(row.remarks || "-")}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="16" class="empty">No workshop records found.</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>${escapeHtml(title)}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 10mm; }
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
              padding-bottom: 14px;
              margin-bottom: 16px;
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
              grid-template-columns: repeat(4, 1fr);
              gap: 10px;
              margin-bottom: 16px;
            }
            .box {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
            }
            .box-title {
              font-size: 11px;
              font-weight: 700;
            }
            .box-value {
              margin-top: 4px;
              font-size: 16px;
              font-weight: 800;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 9px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: left;
              padding: 6px;
              border: 1px solid #2563eb;
              white-space: nowrap;
            }
            td {
              padding: 6px;
              border: 1px solid #d1d5db;
              color: #111827;
              vertical-align: top;
            }
            tfoot td {
              background: #f9fafb;
              font-weight: 800;
              white-space: nowrap;
            }
            .empty {
              text-align: center;
              font-weight: 700;
              padding: 16px;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>UT Software</h1>
              <h2>${escapeHtml(title)}</h2>
            </div>
            <div class="meta">
              <div><strong>Date Range:</strong> ${escapeHtml(
                dateRange(filters)
              )}</div>
              <div><strong>Printed:</strong> ${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</div>
            </div>
          </div>

          <div class="summary">
            <div class="box">
              <div class="box-title">Total Jobs</div>
              <div class="box-value">${printableRows.length}</div>
            </div>
            <div class="box">
              <div class="box-title">Total Cost</div>
              <div class="box-value">${escapeHtml(formatAmount(costTotal))}</div>
            </div>
            <div class="box">
              <div class="box-title">Paid</div>
              <div class="box-value">${escapeHtml(formatAmount(paidTotal))}</div>
            </div>
            <div class="box">
              <div class="box-title">Remaining</div>
              <div class="box-value">${escapeHtml(
                formatAmount(remainingTotal)
              )}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Vehicle</th>
                <th>Owner</th>
                <th>Workshop</th>
                <th>Mechanic</th>
                <th>Work Type</th>
                <th>Bill No</th>
                <th>Parts</th>
                <th>Labour</th>
                <th>Total</th>
                <th>Paid</th>
                <th>Remaining</th>
                <th>Status</th>
                <th>Next Service</th>
                <th>Odometer</th>
                <th>Remarks</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="7">Total</td>
                <td>${escapeHtml(formatAmount(partsTotal))}</td>
                <td>${escapeHtml(formatAmount(labourTotal))}</td>
                <td>${escapeHtml(formatAmount(costTotal))}</td>
                <td>${escapeHtml(formatAmount(paidTotal))}</td>
                <td>${escapeHtml(formatAmount(remainingTotal))}</td>
                <td colspan="4"></td>
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
            Workshop Records
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Search, filter, print, edit and delete workshop entries.
          </p>
        </div>

        <button
          type="button"
          onClick={() => openPrintWindow("Workshop Report", rows)}
          className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
        >
          Print Report
        </button>
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
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
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
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Vehicle
          </label>
          <select
            value={filters.vehicleId}
            onChange={(event) =>
              updateFilter(setFilters, "vehicleId", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Vehicles</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Status
          </label>
          <select
            value={filters.paymentStatus}
            onChange={(event) =>
              updateFilter(setFilters, "paymentStatus", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Status</option>
            <option value="Paid">Paid</option>
            <option value="Partial">Partial</option>
            <option value="Unpaid">Unpaid</option>
          </select>
        </div>

        <div className="md:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Search
          </label>
          <input
            type="text"
            value={filters.search}
            onChange={(event) =>
              updateFilter(setFilters, "search", event.target.value)
            }
            placeholder="Search workshop records"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
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
          Loading workshop records...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          No workshop records found.
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto">
          <table className="w-full min-w-[1700px] border-collapse text-left">
            <thead>
              <tr className="bg-blue-600 text-white">
                {[
                  "Date",
                  "Vehicle",
                  "Owner",
                  "Workshop",
                  "Mechanic",
                  "Work Type",
                  "Bill No",
                  "Parts Cost",
                  "Labour Cost",
                  "Total Cost",
                  "Paid",
                  "Remaining",
                  "Status",
                  "Next Service",
                  "Odometer",
                  "Remarks",
                  "Actions",
                ].map((heading) => (
                  <th
                    key={heading}
                    className="whitespace-nowrap px-4 py-3 text-sm font-bold"
                  >
                    {heading}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.workDate || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                    {row.vehicleNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.ownerName}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.workshopName || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.mechanicName || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.workType || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.billNo || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatAmount(row.partsCost)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatAmount(row.labourCost)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold">
                    {formatAmount(row.totalCost)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold text-green-700">
                    {formatAmount(row.paidAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold text-red-700">
                    {formatAmount(row.remainingAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.paymentStatus
                      )}`}
                    >
                      {row.paymentStatus}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.nextServiceDate || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.odometer || "-"}
                  </td>
                  <td className="min-w-[220px] px-4 py-3 text-sm font-semibold">
                    {row.remarks || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => onEdit(row)}
                        className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        onClick={() => onDelete(row)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        Delete
                      </button>
                      <button
                        type="button"
                        onClick={() =>
                          openPrintWindow("Workshop Entry", [row])
                        }
                        className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-gray-800"
                      >
                        Print
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={7} className="px-4 py-4 text-sm font-extrabold">
                  Total
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(totalParts)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(totalLabour)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(totalCost)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold text-green-700">
                  {formatAmount(totalPaid)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold text-red-700">
                  {formatAmount(totalRemaining)}
                </td>
                <td colSpan={5} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
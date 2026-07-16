"use client";

import {
  type DieselEntryRow,
  type DieselFilterValues,
  formatAmount,
  formatLiters,
} from "./Diesel";

type Props = {
  rows: DieselEntryRow[];
  isLoading: boolean;
  errorMessage: string;
  filters: DieselFilterValues;
};

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getStatusClass(status: string) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

function dateRange(filters: DieselFilterValues) {
  if (filters.fromDate && filters.toDate) {
    return `${filters.fromDate} to ${filters.toDate}`;
  }

  if (filters.fromDate) return `From ${filters.fromDate}`;
  if (filters.toDate) return `Up to ${filters.toDate}`;
  return "All Dates";
}

export default function DieselTable({
  rows,
  isLoading,
  errorMessage,
  filters,
}: Props) {
  const totalLiters = rows.reduce((total, row) => total + row.liters, 0);
  const totalAmount = rows.reduce((total, row) => total + row.totalAmount, 0);
  const totalPaid = rows.reduce((total, row) => total + row.paidAmount, 0);
  const totalRemaining = rows.reduce(
    (total, row) => total + row.remainingAmount,
    0
  );

  function printRows(printRowsList: DieselEntryRow[]) {
    if (printRowsList.length === 0) {
      return `<tr><td colspan="15" class="empty">No diesel records found.</td></tr>`;
    }

    return printRowsList
      .map(
        (row) => `
          <tr>
            <td>${escapeHtml(row.entryDate || "-")}</td>
            <td>${escapeHtml(row.expenseNo || "-")}</td>
            <td>${escapeHtml(row.pumpName || "-")}</td>
            <td>${escapeHtml(row.vehicleNo || "-")}</td>
            <td>${escapeHtml(row.vehicleOwner || "-")}</td>
            <td>${escapeHtml(row.driverName || "-")}</td>
            <td>${escapeHtml(row.loadingNo || "-")}</td>
            <td>${escapeHtml(row.route || "-")}</td>
            <td>${escapeHtml(row.slipNo || "-")}</td>
            <td>${escapeHtml(formatLiters(row.liters))}</td>
            <td>${escapeHtml(formatAmount(row.rate))}</td>
            <td>${escapeHtml(formatAmount(row.totalAmount))}</td>
            <td>${escapeHtml(formatAmount(row.paidAmount))}</td>
            <td>${escapeHtml(formatAmount(row.remainingAmount))}</td>
            <td>${escapeHtml(row.paymentStatus)}</td>
          </tr>
        `
      )
      .join("");
  }

  function handlePrintEntry(row: DieselEntryRow) {
    const printWindow = window.open("", "_blank", "width=1000,height=800");

    if (!printWindow) {
      alert("Please allow popups to print diesel entry.");
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Diesel Entry - ${escapeHtml(row.slipNo)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 28px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .slip {
              max-width: 900px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 24px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 16px;
              margin-bottom: 18px;
            }
            h1 { margin: 0; font-size: 28px; color: #111827; }
            h2 { margin: 4px 0 0; font-size: 18px; color: #111827; }
            .meta { text-align: right; line-height: 1.7; font-size: 14px; }
            .details {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 12px 24px;
              font-size: 14px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
          </style>
        </head>
        <body>
          <div class="slip">
            <div class="header">
              <div>
                <h1>UT Software</h1>
                <h2>Diesel Entry</h2>
              </div>
              <div class="meta">
                <div><strong>Date:</strong> ${escapeHtml(row.entryDate)}</div>
                <div><strong>Expense No:</strong> ${escapeHtml(row.expenseNo)}</div>
              </div>
            </div>

            <div class="details">
              <div><strong>Petrol Pump:</strong> ${escapeHtml(row.pumpName)}</div>
              <div><strong>Pump Owner:</strong> ${escapeHtml(row.pumpOwner)}</div>
              <div><strong>Vehicle:</strong> ${escapeHtml(row.vehicleNo)}</div>
              <div><strong>Vehicle Owner:</strong> ${escapeHtml(row.vehicleOwner)}</div>
              <div><strong>Driver:</strong> ${escapeHtml(row.driverName)}</div>
              <div><strong>Loading:</strong> ${escapeHtml(row.loadingNo)}</div>
              <div><strong>Route:</strong> ${escapeHtml(row.route)}</div>
              <div><strong>Slip No:</strong> ${escapeHtml(row.slipNo)}</div>
              <div><strong>Litres:</strong> ${escapeHtml(formatLiters(row.liters))}</div>
              <div><strong>Rate:</strong> ${escapeHtml(formatAmount(row.rate))}</div>
              <div><strong>Total:</strong> ${escapeHtml(formatAmount(row.totalAmount))}</div>
              <div><strong>Paid:</strong> ${escapeHtml(formatAmount(row.paidAmount))}</div>
              <div><strong>Remaining:</strong> ${escapeHtml(formatAmount(row.remainingAmount))}</div>
              <div><strong>Status:</strong> ${escapeHtml(row.paymentStatus)}</div>
              <div><strong>Remarks:</strong> ${escapeHtml(row.remarks)}</div>
            </div>
          </div>

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

  function handlePrintReport() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print diesel report.");
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Diesel Report</title>
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
            h1 { margin: 0; font-size: 28px; color: #111827; }
            h2 { margin: 4px 0 0; font-size: 18px; color: #111827; }
            .meta {
              text-align: right;
              font-size: 13px;
              line-height: 1.7;
              color: #111827;
            }
            .summary {
              display: grid;
              grid-template-columns: repeat(5, 1fr);
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
              color: #111827;
            }
            .box-value {
              margin-top: 4px;
              font-size: 15px;
              font-weight: 800;
              color: #111827;
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
              padding: 18px;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>UT Software</h1>
              <h2>Diesel Report</h2>
            </div>
            <div class="meta">
              <div><strong>Date Range:</strong> ${escapeHtml(dateRange(filters))}</div>
              <div><strong>Printed:</strong> ${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</div>
            </div>
          </div>

          <div class="summary">
            <div class="box">
              <div class="box-title">Total Entries</div>
              <div class="box-value">${rows.length}</div>
            </div>
            <div class="box">
              <div class="box-title">Total Litres</div>
              <div class="box-value">${escapeHtml(formatLiters(totalLiters))}</div>
            </div>
            <div class="box">
              <div class="box-title">Total Amount</div>
              <div class="box-value">${escapeHtml(formatAmount(totalAmount))}</div>
            </div>
            <div class="box">
              <div class="box-title">Total Paid</div>
              <div class="box-value">${escapeHtml(formatAmount(totalPaid))}</div>
            </div>
            <div class="box">
              <div class="box-title">Total Remaining</div>
              <div class="box-value">${escapeHtml(formatAmount(totalRemaining))}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Expense No</th>
                <th>Pump</th>
                <th>Vehicle</th>
                <th>Owner</th>
                <th>Driver</th>
                <th>Loading</th>
                <th>Route</th>
                <th>Slip No</th>
                <th>Litres</th>
                <th>Rate</th>
                <th>Total</th>
                <th>Paid</th>
                <th>Remaining</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>${printRows(rows)}</tbody>
            <tfoot>
              <tr>
                <td colspan="9">Total</td>
                <td>${escapeHtml(formatLiters(totalLiters))}</td>
                <td></td>
                <td>${escapeHtml(formatAmount(totalAmount))}</td>
                <td>${escapeHtml(formatAmount(totalPaid))}</td>
                <td>${escapeHtml(formatAmount(totalRemaining))}</td>
                <td></td>
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
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Diesel Entries</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Read-only diesel entries generated from Expense Vouchers.
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintReport}
          className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
        >
          Print Diesel Report
        </button>
      </div>

      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          Loading diesel entries...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          No diesel records found.
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1700px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Date</th>
                <th className="p-3 text-left font-bold">Expense No</th>
                <th className="p-3 text-left font-bold">Pump</th>
                <th className="p-3 text-left font-bold">Vehicle</th>
                <th className="p-3 text-left font-bold">Owner</th>
                <th className="p-3 text-left font-bold">Driver</th>
                <th className="p-3 text-left font-bold">Loading</th>
                <th className="p-3 text-left font-bold">Route</th>
                <th className="p-3 text-left font-bold">Slip No</th>
                <th className="p-3 text-right font-bold">Litres</th>
                <th className="p-3 text-right font-bold">Rate</th>
                <th className="p-3 text-right font-bold">Total Amount</th>
                <th className="p-3 text-right font-bold">Paid</th>
                <th className="p-3 text-right font-bold">Remaining</th>
                <th className="p-3 text-left font-bold">Status</th>
                <th className="p-3 text-left font-bold">Remarks</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 font-semibold">{row.entryDate || "-"}</td>
                  <td className="p-3 font-bold">{row.expenseNo}</td>
                  <td className="p-3 font-semibold">{row.pumpName}</td>
                  <td className="p-3 font-bold">{row.vehicleNo}</td>
                  <td className="p-3 font-semibold">{row.vehicleOwner}</td>
                  <td className="p-3 font-semibold">{row.driverName}</td>
                  <td className="p-3 font-semibold">{row.loadingNo}</td>
                  <td className="p-3 font-semibold">{row.route}</td>
                  <td className="p-3 font-semibold">{row.slipNo}</td>
                  <td className="p-3 text-right font-bold">
                    {formatLiters(row.liters)}
                  </td>
                  <td className="p-3 text-right font-bold">
                    {formatAmount(row.rate)}
                  </td>
                  <td className="p-3 text-right font-extrabold">
                    {formatAmount(row.totalAmount)}
                  </td>
                  <td className="p-3 text-right font-extrabold text-green-700">
                    {formatAmount(row.paidAmount)}
                  </td>
                  <td className="p-3 text-right font-extrabold text-red-700">
                    {formatAmount(row.remainingAmount)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.paymentStatus
                      )}`}
                    >
                      {row.paymentStatus}
                    </span>
                  </td>
                  <td className="max-w-[260px] p-3 font-semibold">
                    {row.remarks}
                  </td>
                  <td className="p-3">
                    <button
                      type="button"
                      onClick={() => handlePrintEntry(row)}
                      className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white transition hover:bg-gray-800"
                    >
                      Print Entry
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={9} className="p-3 font-extrabold">
                  Total
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatLiters(totalLiters)}
                </td>
                <td />
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totalAmount)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totalPaid)}
                </td>
                <td className="p-3 text-right font-extrabold text-red-700">
                  {formatAmount(totalRemaining)}
                </td>
                <td colSpan={3} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
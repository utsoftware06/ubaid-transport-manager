"use client";

import {
  type PetrolPumpRow,
  type PetrolPumpDieselEntry,
  formatAmount,
} from "./PetrolPumps";

type Props = {
  rows: PetrolPumpRow[];
  search: string;
  setSearch: (value: string) => void;
  onEdit: (row: PetrolPumpRow) => void;
  onDelete: (row: PetrolPumpRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
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

function getPrintRows(entries: PetrolPumpDieselEntry[]) {
  if (entries.length === 0) {
    return `<tr><td colspan="10" class="empty">No diesel entries found.</td></tr>`;
  }

  return entries
    .map(
      (entry) => `
        <tr>
          <td>${escapeHtml(entry.entryDate || "-")}</td>
          <td>${escapeHtml(entry.vehicleNo || "-")}</td>
          <td>${escapeHtml(entry.loadingNo || "-")}</td>
          <td>${escapeHtml(entry.slipNo || "-")}</td>
          <td>${entry.liters}</td>
          <td>${escapeHtml(formatAmount(entry.rate))}</td>
          <td>${escapeHtml(formatAmount(entry.totalAmount))}</td>
          <td>${escapeHtml(formatAmount(entry.paidAmount))}</td>
          <td>${escapeHtml(formatAmount(entry.remainingAmount))}</td>
          <td>${escapeHtml(entry.paymentStatus)}</td>
        </tr>
      `
    )
    .join("");
}

export default function PetrolPumpTable({
  rows,
  search,
  setSearch,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const totalOpening = rows.reduce(
    (total, row) => total + row.openingBalance,
    0
  );
  const totalDiesel = rows.reduce((total, row) => total + row.totalDiesel, 0);
  const totalPaid = rows.reduce((total, row) => total + row.totalPaid, 0);
  const totalBalance = rows.reduce(
    (total, row) => total + row.currentBalance,
    0
  );

  function handlePrintLedger(row: PetrolPumpRow) {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print petrol pump ledger.");
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Petrol Pump Ledger - ${escapeHtml(row.pumpName)}</title>
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
            .details {
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
              <h2>Petrol Pump Ledger</h2>
            </div>
            <div class="meta">
              <div><strong>Pump:</strong> ${escapeHtml(row.pumpName)}</div>
              <div><strong>Printed:</strong> ${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</div>
            </div>
          </div>

          <div class="details">
            <div class="box">
              <div class="box-title">Owner</div>
              <div class="box-value">${escapeHtml(row.ownerName)}</div>
            </div>
            <div class="box">
              <div class="box-title">Phone</div>
              <div class="box-value">${escapeHtml(row.phone)}</div>
            </div>
            <div class="box">
              <div class="box-title">Address</div>
              <div class="box-value">${escapeHtml(row.address)}</div>
            </div>
            <div class="box">
              <div class="box-title">Opening Balance</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.openingBalance)
              )}</div>
            </div>
            <div class="box">
              <div class="box-title">Total Diesel</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.totalDiesel)
              )}</div>
            </div>
            <div class="box">
              <div class="box-title">Total Paid</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.totalPaid)
              )}</div>
            </div>
            <div class="box">
              <div class="box-title">Current Balance</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.currentBalance)
              )}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Vehicle</th>
                <th>Loading</th>
                <th>Slip No</th>
                <th>Litres</th>
                <th>Rate</th>
                <th>Total</th>
                <th>Paid</th>
                <th>Remaining</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>${getPrintRows(row.dieselEntries)}</tbody>
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
          <h2 className="text-2xl font-bold text-gray-900">
            Petrol Pump Ledger
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Search pumps, view balances and print individual pump ledgers.
          </p>
        </div>

        <input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search pump, owner, phone or address..."
          className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        />
      </div>

      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          Loading petrol pumps...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          No petrol pumps found.
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1200px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Pump Name</th>
                <th className="p-3 text-left font-bold">Owner</th>
                <th className="p-3 text-left font-bold">Phone</th>
                <th className="p-3 text-left font-bold">Address</th>
                <th className="p-3 text-right font-bold">Opening Balance</th>
                <th className="p-3 text-right font-bold">Total Diesel</th>
                <th className="p-3 text-right font-bold">Total Paid</th>
                <th className="p-3 text-right font-bold">Current Balance</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 font-bold text-gray-900">
                    {row.pumpName}
                  </td>
                  <td className="p-3 font-semibold text-gray-900">
                    {row.ownerName}
                  </td>
                  <td className="p-3 font-semibold text-gray-900">
                    {row.phone}
                  </td>
                  <td className="max-w-[260px] p-3 font-semibold text-gray-900">
                    {row.address}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(row.openingBalance)}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(row.totalDiesel)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(row.totalPaid)}
                  </td>
                  <td
                    className={`p-3 text-right font-extrabold ${
                      row.currentBalance > 0
                        ? "text-red-700"
                        : "text-green-700"
                    }`}
                  >
                    {formatAmount(row.currentBalance)}
                  </td>
                  <td className="min-w-[230px] p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => onEdit(row)}
                        className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                      >
                        Edit
                      </button>

                      <button
                        type="button"
                        onClick={() => onDelete(row)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        Delete
                      </button>

                      <button
                        type="button"
                        onClick={() => handlePrintLedger(row)}
                        className="rounded-lg bg-gray-900 px-3 py-2 font-semibold text-white transition hover:bg-gray-800"
                      >
                        Print Ledger
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={4} className="p-3 font-extrabold">
                  Total
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totalOpening)}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totalDiesel)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totalPaid)}
                </td>
                <td
                  className={`p-3 text-right font-extrabold ${
                    totalBalance > 0 ? "text-red-700" : "text-green-700"
                  }`}
                >
                  {formatAmount(totalBalance)}
                </td>
                <td />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
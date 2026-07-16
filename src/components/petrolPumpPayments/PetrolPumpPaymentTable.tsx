"use client";

import {
  type PetrolPumpOption,
  type PetrolPumpPaymentRow,
  formatAmount,
} from "./PetrolPumpPayments";

type Props = {
  rows: PetrolPumpPaymentRow[];
  search: string;
  setSearch: (value: string) => void;
  onEdit: (row: PetrolPumpPaymentRow) => void;
  onDelete: (row: PetrolPumpPaymentRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
  pumps: PetrolPumpOption[];
};

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getStatusTextClass(status: string) {
  if (status === "Payable") return "text-red-700";
  if (status === "Advance") return "text-green-700";
  return "text-blue-700";
}

function getStatusBadgeClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") {
    return "border-green-200 bg-green-100 text-green-700";
  }

  return "border-blue-200 bg-blue-100 text-blue-700";
}

function getBalanceTextClass(balance: number) {
  if (balance > 0) return "text-red-700";
  if (balance < 0) return "text-green-700";
  return "text-blue-700";
}

export default function PetrolPumpPaymentTable({
  rows,
  search,
  setSearch,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
  pumps,
}: Props) {
  const totalPayments = rows.reduce((total, row) => total + row.amount, 0);

  function getPump(row: PetrolPumpPaymentRow) {
    return pumps.find((item) => item.id === row.petrolPumpId) ?? null;
  }

  function handlePrintReceipt(row: PetrolPumpPaymentRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert("Please allow popups to print payment receipt.");
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Petrol Pump Payment Receipt - ${escapeHtml(row.pumpName)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .receipt {
              max-width: 850px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 28px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 18px;
              margin-bottom: 22px;
            }
            h1 { margin: 0; font-size: 28px; color: #111827; }
            h2 { margin: 6px 0 0; font-size: 18px; color: #111827; }
            .meta { text-align: right; font-size: 14px; line-height: 1.7; }
            .details {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 14px 24px;
              font-size: 15px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
            .amount {
              margin-top: 24px;
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 16px;
              font-size: 24px;
              font-weight: 800;
              text-align: center;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 40px;
              margin-top: 60px;
              font-size: 14px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 8px;
              text-align: center;
            }
          </style>
        </head>
        <body>
          <div class="receipt">
            <div class="header">
              <div>
                <h1>UT Software</h1>
                <h2>Petrol Pump Payment Receipt</h2>
              </div>
              <div class="meta">
                <div><strong>Date:</strong> ${escapeHtml(row.paymentDate)}</div>
                <div><strong>Reference:</strong> ${escapeHtml(row.referenceNo)}</div>
              </div>
            </div>

            <div class="details">
              <div><strong>Petrol Pump:</strong> ${escapeHtml(row.pumpName)}</div>
              <div><strong>Owner:</strong> ${escapeHtml(row.ownerName)}</div>
              <div><strong>Payment Method:</strong> ${escapeHtml(row.paymentMethod)}</div>
              <div><strong>Remarks:</strong> ${escapeHtml(row.remarks)}</div>
            </div>

            <div class="amount">${escapeHtml(formatAmount(row.amount))}</div>

            <div class="signatures">
              <div class="signature">Prepared By</div>
              <div class="signature">Received By</div>
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
      alert("Please allow popups to print payment report.");
      return;
    }

    const paymentRows =
      rows.length > 0
        ? rows
            .map((row) => {
              const pump = getPump(row);
              const currentBalance = pump?.currentBalance ?? 0;
              const payableAmount = pump?.payableAmount ?? 0;
              const advanceAmount = pump?.advanceAmount ?? 0;
              const status = pump?.balanceStatus ?? "Settled";

              return `
                <tr>
                  <td>${escapeHtml(row.paymentDate || "-")}</td>
                  <td>${escapeHtml(row.pumpName)}</td>
                  <td>${escapeHtml(row.ownerName)}</td>
                  <td>${escapeHtml(formatAmount(row.amount))}</td>
                  <td class="${getStatusTextClass(status)}">${escapeHtml(
                    formatAmount(currentBalance)
                  )}</td>
                  <td class="text-red-700">${escapeHtml(
                    formatAmount(payableAmount)
                  )}</td>
                  <td class="text-green-700">${escapeHtml(
                    formatAmount(advanceAmount)
                  )}</td>
                  <td class="${getStatusTextClass(status)}">${escapeHtml(
                    status
                  )}</td>
                  <td>${escapeHtml(row.paymentMethod)}</td>
                  <td>${escapeHtml(row.referenceNo)}</td>
                  <td>${escapeHtml(row.remarks)}</td>
                </tr>
              `;
            })
            .join("")
        : `<tr><td colspan="11" class="empty">No payments found.</td></tr>`;

    const pumpRows =
      pumps.length > 0
        ? pumps
            .map(
              (pump) => `
                <tr>
                  <td>${escapeHtml(pump.pumpName)}</td>
                  <td>${escapeHtml(formatAmount(pump.openingBalance))}</td>
                  <td>${escapeHtml(formatAmount(pump.totalDiesel))}</td>
                  <td>${escapeHtml(formatAmount(pump.manualPayments))}</td>
                  <td>${escapeHtml(formatAmount(pump.payableAmount))}</td>
                  <td>${escapeHtml(formatAmount(pump.advanceAmount))}</td>
                  <td class="${getStatusTextClass(pump.balanceStatus)}">${escapeHtml(
                    pump.balanceStatus
                  )}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="7" class="empty">No pump balances found.</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Petrol Pump Payment Report</title>
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
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 10px;
              margin-bottom: 20px;
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
            }
            tfoot td {
              background: #f9fafb;
              font-weight: 800;
            }
            .section-title {
              margin: 18px 0 8px;
              font-size: 17px;
              font-weight: 800;
            }
            .empty {
              text-align: center;
              font-weight: 700;
              padding: 16px;
            }
            .text-red-700 { color: #b91c1c; font-weight: 800; }
            .text-green-700 { color: #047857; font-weight: 800; }
            .text-blue-700 { color: #1d4ed8; font-weight: 800; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>UT Software</h1>
              <h2>Petrol Pump Payment Report</h2>
            </div>
            <div class="meta">
              <div><strong>Printed:</strong> ${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</div>
              <div><strong>Total:</strong> ${escapeHtml(formatAmount(totalPayments))}</div>
            </div>
          </div>

          <div class="section-title">Pump Balance Summary</div>
          <table>
            <thead>
              <tr>
                <th>Pump</th>
                <th>Opening Balance</th>
                <th>Total Diesel</th>
                <th>Total Paid</th>
                <th>Payable</th>
                <th>Advance</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>${pumpRows}</tbody>
          </table>

          <div class="section-title">Payment Details</div>
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Pump</th>
                <th>Owner</th>
                <th>Amount</th>
                <th>Current Balance</th>
                <th>Payable</th>
                <th>Advance</th>
                <th>Status</th>
                <th>Method</th>
                <th>Reference</th>
                <th>Remarks</th>
              </tr>
            </thead>
            <tbody>${paymentRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="3">Total</td>
                <td>${escapeHtml(formatAmount(totalPayments))}</td>
                <td colspan="7"></td>
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
          <h2 className="text-2xl font-bold text-gray-900">
            Payment Records
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            View, edit, delete and print petrol pump payment records.
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <input
            type="text"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search payments..."
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 lg:w-80"
          />

          <button
            type="button"
            onClick={handlePrintReport}
            className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
          >
            Print Payment Report
          </button>
        </div>
      </div>

      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          Loading petrol pump payments...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          No petrol pump payments found.
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1500px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Date</th>
                <th className="p-3 text-left font-bold">Petrol Pump</th>
                <th className="p-3 text-left font-bold">Owner</th>
                <th className="p-3 text-right font-bold">Amount</th>
                <th className="p-3 text-right font-bold">Current Balance</th>
                <th className="p-3 text-right font-bold">Payable</th>
                <th className="p-3 text-right font-bold">Advance</th>
                <th className="p-3 text-left font-bold">Status</th>
                <th className="p-3 text-left font-bold">Payment Method</th>
                <th className="p-3 text-left font-bold">Reference No</th>
                <th className="p-3 text-left font-bold">Remarks</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => {
                const pump = getPump(row);
                const currentBalance = pump?.currentBalance ?? 0;
                const payableAmount = pump?.payableAmount ?? 0;
                const advanceAmount = pump?.advanceAmount ?? 0;
                const status = pump?.balanceStatus ?? "Settled";

                return (
                  <tr
                    key={row.id}
                    className="border-b border-gray-200 hover:bg-gray-50"
                  >
                    <td className="p-3 font-semibold">{row.paymentDate}</td>
                    <td className="p-3 font-bold">{row.pumpName}</td>
                    <td className="p-3 font-semibold">{row.ownerName}</td>
                    <td className="p-3 text-right font-extrabold text-green-700">
                      {formatAmount(row.amount)}
                    </td>
                    <td
                      className={`p-3 text-right font-extrabold ${getBalanceTextClass(
                        currentBalance
                      )}`}
                    >
                      <div>{formatAmount(currentBalance)}</div>
                      <div className="mt-1 text-xs font-bold text-gray-900">
                        Latest Balance
                      </div>
                    </td>
                    <td className="p-3 text-right font-extrabold text-red-700">
                      {formatAmount(payableAmount)}
                    </td>
                    <td className="p-3 text-right font-extrabold text-green-700">
                      {formatAmount(advanceAmount)}
                    </td>
                    <td className="p-3">
                      <span
                        className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusBadgeClass(
                          status
                        )}`}
                      >
                        {status}
                      </span>
                    </td>
                    <td className="p-3 font-semibold">{row.paymentMethod}</td>
                    <td className="p-3 font-semibold">{row.referenceNo}</td>
                    <td className="max-w-[260px] p-3 font-semibold">
                      {row.remarks}
                    </td>
                    <td className="min-w-[240px] p-3">
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
                          onClick={() => handlePrintReceipt(row)}
                          className="rounded-lg bg-gray-900 px-3 py-2 font-semibold text-white transition hover:bg-gray-800"
                        >
                          Print Receipt
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={3} className="p-3 font-extrabold">
                  Total
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totalPayments)}
                </td>
                <td colSpan={8} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
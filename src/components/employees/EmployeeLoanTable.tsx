"use client";

import { type Dispatch, type SetStateAction } from "react";
import { type EmployeeLoanRow, formatAmount } from "./EmployeeLoans";

type Props = {
  rows: EmployeeLoanRow[];
  search: string;
  setSearch: Dispatch<SetStateAction<string>>;
  onEdit: (row: EmployeeLoanRow) => void;
  onDelete: (row: EmployeeLoanRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
};

function escapeHtml(value: string | number) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getStatusBadgeClass(status: EmployeeLoanRow["status"]) {
  if (status === "Completed") {
    return "bg-green-100 text-green-700";
  }

  return "bg-orange-100 text-orange-700";
}

export default function EmployeeLoanTable({
  rows,
  search,
  setSearch,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const totalLoanAmount = rows.reduce((total, row) => total + row.loanAmount, 0);
  const totalMonthlyInstallment = rows.reduce(
    (total, row) => total + row.monthlyInstallment,
    0
  );
  const totalRecovered = rows.reduce(
    (total, row) => total + row.recoveredAmount,
    0
  );
  const totalRemaining = rows.reduce(
    (total, row) => total + row.remainingAmount,
    0
  );

  function handlePrintReceipt(row: EmployeeLoanRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert("Please allow popups to print the loan receipt.");
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Employee Loan Receipt - ${escapeHtml(row.employeeName)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              background: #ffffff;
              color: #111827;
              font-family: Arial, sans-serif;
            }
            .receipt {
              max-width: 850px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 12px;
              padding: 28px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 18px;
              margin-bottom: 24px;
            }
            h1 {
              margin: 0;
              color: #111827;
              font-size: 28px;
              font-weight: 800;
            }
            .subtitle {
              margin-top: 6px;
              color: #111827;
              font-size: 15px;
              font-weight: 600;
            }
            .meta {
              text-align: right;
              color: #111827;
              font-size: 14px;
              line-height: 1.7;
            }
            .grid {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 14px 22px;
            }
            .field {
              border: 1px solid #e5e7eb;
              border-radius: 8px;
              padding: 12px;
              background: #f9fafb;
            }
            .label {
              color: #111827;
              font-size: 12px;
              font-weight: 700;
              text-transform: uppercase;
            }
            .value {
              margin-top: 6px;
              color: #111827;
              font-size: 16px;
              font-weight: 800;
            }
            .status {
              display: inline-block;
              border-radius: 999px;
              padding: 5px 12px;
              font-size: 13px;
              font-weight: 800;
              ${
                row.status === "Completed"
                  ? "background:#dcfce7;color:#15803d;"
                  : "background:#ffedd5;color:#c2410c;"
              }
            }
            .remarks {
              grid-column: 1 / -1;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 42px;
              margin-top: 64px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 10px;
              text-align: center;
              color: #111827;
              font-size: 14px;
              font-weight: 700;
            }
            @media print {
              body { padding: 0; }
              .receipt {
                border: none;
                border-radius: 0;
              }
            }
          </style>
        </head>
        <body>
          <div class="receipt">
            <div class="header">
              <div>
                <h1>UT Software</h1>
                <div class="subtitle">Employee Loan Receipt</div>
              </div>
              <div class="meta">
                <div><strong>Loan Date:</strong> ${escapeHtml(row.loanDate || "-")}</div>
                <div><strong>Reference:</strong> ${escapeHtml(row.referenceNo || "-")}</div>
              </div>
            </div>

            <div class="grid">
              <div class="field">
                <div class="label">Employee Name</div>
                <div class="value">${escapeHtml(row.employeeName)}</div>
              </div>
              <div class="field">
                <div class="label">Employee Type</div>
                <div class="value">${escapeHtml(row.employeeType)}</div>
              </div>
              <div class="field">
                <div class="label">Loan Date</div>
                <div class="value">${escapeHtml(row.loanDate || "-")}</div>
              </div>
              <div class="field">
                <div class="label">Loan Amount</div>
                <div class="value">${escapeHtml(formatAmount(row.loanAmount))}</div>
              </div>
              <div class="field">
                <div class="label">Monthly Installment</div>
                <div class="value">${escapeHtml(formatAmount(row.monthlyInstallment))}</div>
              </div>
              <div class="field">
                <div class="label">Recovered Amount</div>
                <div class="value">${escapeHtml(formatAmount(row.recoveredAmount))}</div>
              </div>
              <div class="field">
                <div class="label">Remaining Amount</div>
                <div class="value">${escapeHtml(formatAmount(row.remainingAmount))}</div>
              </div>
              <div class="field">
                <div class="label">Payment Method</div>
                <div class="value">${escapeHtml(row.paymentMethod)}</div>
              </div>
              <div class="field">
                <div class="label">Reference No</div>
                <div class="value">${escapeHtml(row.referenceNo || "-")}</div>
              </div>
              <div class="field">
                <div class="label">Status</div>
                <div class="value"><span class="status">${escapeHtml(row.status)}</span></div>
              </div>
              <div class="field remarks">
                <div class="label">Remarks</div>
                <div class="value">${escapeHtml(row.remarks || "-")}</div>
              </div>
            </div>

            <div class="signatures">
              <div class="signature">Prepared By</div>
              <div class="signature">Received By</div>
            </div>
          </div>

          <script>
            window.onload = function () {
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

  function handlePrintReport() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print the employee loan report.");
      return;
    }

    const tableRows =
      rows.length > 0
        ? rows
            .map(
              (row) => `
                <tr>
                  <td>${escapeHtml(row.employeeName)}</td>
                  <td>${escapeHtml(row.employeeType)}</td>
                  <td>${escapeHtml(row.loanDate || "-")}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.loanAmount))}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.monthlyInstallment))}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.recoveredAmount))}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.remainingAmount))}</td>
                  <td>${escapeHtml(row.paymentMethod)}</td>
                  <td>${escapeHtml(row.referenceNo || "-")}</td>
                  <td>${escapeHtml(row.status)}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="10" class="empty">No loan records found</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Employee Loan Report</title>
          <style>
            * { box-sizing: border-box; }
            @page {
              size: A4 landscape;
              margin: 12mm;
            }
            body {
              margin: 0;
              color: #111827;
              background: #ffffff;
              font-family: Arial, sans-serif;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 14px;
              margin-bottom: 18px;
            }
            h1 {
              margin: 0;
              color: #111827;
              font-size: 26px;
              font-weight: 800;
            }
            .subtitle {
              margin-top: 5px;
              color: #111827;
              font-size: 15px;
              font-weight: 700;
            }
            .printed {
              color: #111827;
              font-size: 13px;
              font-weight: 700;
              text-align: right;
              line-height: 1.6;
            }
            .summary {
              display: grid;
              grid-template-columns: repeat(4, 1fr);
              gap: 10px;
              margin-bottom: 18px;
            }
            .card {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
              background: #f9fafb;
            }
            .card-title {
              color: #111827;
              font-size: 11px;
              font-weight: 800;
              text-transform: uppercase;
            }
            .card-value {
              margin-top: 5px;
              color: #111827;
              font-size: 16px;
              font-weight: 900;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 11px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              border: 1px solid #2563eb;
              padding: 8px;
              text-align: left;
              font-weight: 800;
            }
            td {
              border: 1px solid #d1d5db;
              padding: 7px;
              color: #111827;
              vertical-align: top;
            }
            tfoot td {
              background: #f3f4f6;
              color: #111827;
              font-weight: 900;
            }
            .amount {
              text-align: right;
              white-space: nowrap;
            }
            .empty {
              text-align: center;
              font-weight: 800;
              padding: 18px;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>UT Software</h1>
              <div class="subtitle">Employee Loan Report</div>
            </div>
            <div class="printed">
              <div>Printed: ${escapeHtml(new Date().toLocaleString())}</div>
              <div>Total Records: ${rows.length}</div>
            </div>
          </div>

          <div class="summary">
            <div class="card">
              <div class="card-title">Loan Amount</div>
              <div class="card-value">${escapeHtml(formatAmount(totalLoanAmount))}</div>
            </div>
            <div class="card">
              <div class="card-title">Monthly Installment Total</div>
              <div class="card-value">${escapeHtml(formatAmount(totalMonthlyInstallment))}</div>
            </div>
            <div class="card">
              <div class="card-title">Recovered Amount</div>
              <div class="card-value">${escapeHtml(formatAmount(totalRecovered))}</div>
            </div>
            <div class="card">
              <div class="card-title">Remaining Amount</div>
              <div class="card-value">${escapeHtml(formatAmount(totalRemaining))}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Employee</th>
                <th>Type</th>
                <th>Loan Date</th>
                <th>Loan Amount</th>
                <th>Monthly Installment</th>
                <th>Recovered</th>
                <th>Remaining</th>
                <th>Payment Method</th>
                <th>Reference</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="3">Totals</td>
                <td class="amount">${escapeHtml(formatAmount(totalLoanAmount))}</td>
                <td class="amount">${escapeHtml(formatAmount(totalMonthlyInstallment))}</td>
                <td class="amount">${escapeHtml(formatAmount(totalRecovered))}</td>
                <td class="amount">${escapeHtml(formatAmount(totalRemaining))}</td>
                <td colspan="3"></td>
              </tr>
            </tfoot>
          </table>

          <script>
            window.onload = function () {
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
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Employee Loan Records
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Search, manage and print employee loan records.
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintReport}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-blue-700"
        >
          Print Report
        </button>
      </div>

      <div className="mb-5">
        <input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search employee, type, date, reference, remarks, status or payment method..."
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
        />
      </div>

      {errorMessage && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {isLoading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center text-base font-bold text-gray-900">
          Loading employee loans...
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center text-base font-bold text-gray-900">
          No employee loan records found.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1500px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Employee</th>
                <th className="p-3 text-left font-bold">Employee Type</th>
                <th className="p-3 text-left font-bold">Loan Date</th>
                <th className="p-3 text-right font-bold">Loan Amount</th>
                <th className="p-3 text-right font-bold">
                  Monthly Installment
                </th>
                <th className="p-3 text-right font-bold">Recovered Amount</th>
                <th className="p-3 text-right font-bold">Remaining Amount</th>
                <th className="p-3 text-left font-bold">Payment Method</th>
                <th className="p-3 text-left font-bold">Reference No</th>
                <th className="p-3 text-left font-bold">Remarks</th>
                <th className="p-3 text-left font-bold">Status</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr key={row.id} className="hover:bg-blue-50">
                  <td className="p-3 font-bold text-gray-900">
                    {row.employeeName}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.employeeType}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.loanDate || "-"}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(row.loanAmount)}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(row.monthlyInstallment)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(row.recoveredAmount)}
                  </td>
                  <td className="p-3 text-right font-bold text-red-700">
                    {formatAmount(row.remainingAmount)}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.paymentMethod}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.referenceNo || "-"}
                  </td>
                  <td className="max-w-[260px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">
                      {row.remarks || "-"}
                    </div>
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full px-3 py-1 text-xs font-extrabold ${getStatusBadgeClass(
                        row.status
                      )}`}
                    >
                      {row.status}
                    </span>
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => onEdit(row)}
                        className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-blue-700"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        onClick={() => onDelete(row)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        Delete
                      </button>
                      <button
                        type="button"
                        onClick={() => handlePrintReceipt(row)}
                        className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white transition hover:bg-black"
                      >
                        Print Receipt
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td
                  colSpan={3}
                  className="p-3 text-right text-sm font-extrabold text-gray-900"
                >
                  Totals
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-gray-900">
                  {formatAmount(totalLoanAmount)}
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-gray-900">
                  {formatAmount(totalMonthlyInstallment)}
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-green-700">
                  {formatAmount(totalRecovered)}
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-red-700">
                  {formatAmount(totalRemaining)}
                </td>
                <td colSpan={5} className="p-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
"use client";

import { type Dispatch, type SetStateAction } from "react";
import { type EmployeeSalaryRow, formatAmount } from "./EmployeeSalary";

type Props = {
  rows: EmployeeSalaryRow[];
  search: string;
  setSearch: Dispatch<SetStateAction<string>>;
  onEdit: (row: EmployeeSalaryRow) => void;
  onDelete: (row: EmployeeSalaryRow) => void;
  onPrintSlip: (row: EmployeeSalaryRow) => void;
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

function statusClass(status: EmployeeSalaryRow["paymentStatus"]) {
  if (status === "Paid") return "bg-green-100 text-green-700";
  if (status === "Partial") return "bg-orange-100 text-orange-700";
  return "bg-red-100 text-red-700";
}

export default function EmployeeSalaryTable({
  rows,
  search,
  setSearch,
  onEdit,
  onDelete,
  onPrintSlip,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const totals = rows.reduce(
    (total, row) => {
      total.basic += row.basicSalary;
      total.bonus += row.bonus;
      total.deduction += row.deduction;
      total.loanRecovery += row.loanRecovery;
      total.advanceRecovery += row.advanceRecovery;
      total.net += row.netSalary;
      total.paid += row.paidAmount;
      total.remaining += row.remainingAmount;
      return total;
    },
    {
      basic: 0,
      bonus: 0,
      deduction: 0,
      loanRecovery: 0,
      advanceRecovery: 0,
      net: 0,
      paid: 0,
      remaining: 0,
    }
  );

  function handlePrintReport() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print the salary report.");
      return;
    }

    const bodyRows =
      rows.length > 0
        ? rows
            .map(
              (row) => `
                <tr>
                  <td>${escapeHtml(row.salaryMonth)}</td>
                  <td>${escapeHtml(row.employeeName)}</td>
                  <td>${escapeHtml(row.employeeType)}</td>
                  <td>${escapeHtml(formatAmount(row.basicSalary))}</td>
                  <td>${escapeHtml(formatAmount(row.bonus))}</td>
                  <td>${escapeHtml(formatAmount(row.deduction))}</td>
                  <td>${escapeHtml(formatAmount(row.loanRecovery))}</td>
                  <td>${escapeHtml(formatAmount(row.advanceRecovery))}</td>
                  <td>${escapeHtml(formatAmount(row.netSalary))}</td>
                  <td>${escapeHtml(formatAmount(row.paidAmount))}</td>
                  <td>${escapeHtml(formatAmount(row.remainingAmount))}</td>
                  <td>${escapeHtml(row.paymentStatus)}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="12" class="empty">No salary records found</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Employee Salary Report</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 12mm; }
            body { margin: 0; color: #111827; font-family: Arial, sans-serif; }
            .header {
              display: flex;
              justify-content: space-between;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 14px;
              margin-bottom: 18px;
            }
            h1 { margin: 0; font-size: 26px; font-weight: 800; }
            .subtitle { margin-top: 5px; font-size: 15px; font-weight: 700; }
            .printed { text-align: right; font-size: 13px; font-weight: 700; line-height: 1.6; }
            table { width: 100%; border-collapse: collapse; font-size: 10px; }
            th { background: #2563eb; color: #fff; padding: 7px; border: 1px solid #2563eb; text-align: left; }
            td { padding: 6px; border: 1px solid #d1d5db; color: #111827; }
            tfoot td { background: #f3f4f6; font-weight: 900; }
            .empty { text-align: center; padding: 16px; font-weight: 800; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>UT Software</h1>
              <div class="subtitle">Employee Salary Report</div>
            </div>
            <div class="printed">
              <div>Printed: ${escapeHtml(new Date().toLocaleString())}</div>
              <div>Total Records: ${rows.length}</div>
            </div>
          </div>
          <table>
            <thead>
              <tr>
                <th>Salary Month</th>
                <th>Employee</th>
                <th>Type</th>
                <th>Basic</th>
                <th>Bonus</th>
                <th>Deduction</th>
                <th>Loan Recovery</th>
                <th>Advance Recovery</th>
                <th>Net Salary</th>
                <th>Paid</th>
                <th>Remaining</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>${bodyRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="3">Totals</td>
                <td>${escapeHtml(formatAmount(totals.basic))}</td>
                <td>${escapeHtml(formatAmount(totals.bonus))}</td>
                <td>${escapeHtml(formatAmount(totals.deduction))}</td>
                <td>${escapeHtml(formatAmount(totals.loanRecovery))}</td>
                <td>${escapeHtml(formatAmount(totals.advanceRecovery))}</td>
                <td>${escapeHtml(formatAmount(totals.net))}</td>
                <td>${escapeHtml(formatAmount(totals.paid))}</td>
                <td>${escapeHtml(formatAmount(totals.remaining))}</td>
                <td></td>
              </tr>
            </tfoot>
          </table>
          <script>
            window.onload = function () { window.print(); };
            window.onafterprint = function () { window.close(); };
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
          <h2 className="text-2xl font-bold text-gray-900">Salary Records</h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Search, manage and print employee salary records.
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintReport}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700"
        >
          Print Salary Report
        </button>
      </div>

      <input
        type="text"
        value={search}
        onChange={(event) => setSearch(event.target.value)}
        placeholder="Search employee, type, month, status, payment method, reference or remarks..."
        className="mb-5 w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
      />

      {errorMessage && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {isLoading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          Loading salary records...
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          No salary records found.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1800px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Salary Month</th>
                <th className="p-3 text-left font-bold">Employee</th>
                <th className="p-3 text-left font-bold">Type</th>
                <th className="p-3 text-right font-bold">Basic Salary</th>
                <th className="p-3 text-right font-bold">Bonus</th>
                <th className="p-3 text-right font-bold">Deduction</th>
                <th className="p-3 text-right font-bold">Loan Recovery</th>
                <th className="p-3 text-right font-bold">Advance Recovery</th>
                <th className="p-3 text-right font-bold">Net Salary</th>
                <th className="p-3 text-right font-bold">Paid</th>
                <th className="p-3 text-right font-bold">Remaining</th>
                <th className="p-3 text-left font-bold">Status</th>
                <th className="p-3 text-left font-bold">Payment Method</th>
                <th className="p-3 text-left font-bold">Reference</th>
                <th className="p-3 text-left font-bold">Remarks</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr key={row.id} className="hover:bg-blue-50">
                  <td className="p-3 font-medium text-gray-900">{row.salaryMonth}</td>
                  <td className="p-3 font-bold text-gray-900">{row.employeeName}</td>
                  <td className="p-3 font-medium text-gray-900">{row.employeeType}</td>
                  <td className="p-3 text-right font-bold text-gray-900">{formatAmount(row.basicSalary)}</td>
                  <td className="p-3 text-right font-bold text-green-700">{formatAmount(row.bonus)}</td>
                  <td className="p-3 text-right font-bold text-red-700">{formatAmount(row.deduction)}</td>
                  <td className="p-3 text-right font-bold text-orange-700">{formatAmount(row.loanRecovery)}</td>
                  <td className="p-3 text-right font-bold text-red-700">{formatAmount(row.advanceRecovery)}</td>
                  <td className="p-3 text-right font-bold text-blue-700">{formatAmount(row.netSalary)}</td>
                  <td className="p-3 text-right font-bold text-green-700">{formatAmount(row.paidAmount)}</td>
                  <td className="p-3 text-right font-bold text-red-700">{formatAmount(row.remainingAmount)}</td>
                  <td className="p-3">
                    <span className={`rounded-full px-3 py-1 text-xs font-extrabold ${statusClass(row.paymentStatus)}`}>
                      {row.paymentStatus}
                    </span>
                  </td>
                  <td className="p-3 font-medium text-gray-900">{row.paymentMethod}</td>
                  <td className="p-3 font-medium text-gray-900">{row.referenceNo || "-"}</td>
                  <td className="max-w-[260px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">{row.remarks || "-"}</div>
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button type="button" onClick={() => onEdit(row)} className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700">
                        Edit
                      </button>
                      <button type="button" onClick={() => onDelete(row)} disabled={isDeleting} className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed">
                        Delete
                      </button>
                      <button type="button" onClick={() => onPrintSlip(row)} className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-black">
                        Print Salary Slip
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td colSpan={3} className="p-3 text-right font-extrabold text-gray-900">
                  Totals
                </td>
                <td className="p-3 text-right font-extrabold text-gray-900">{formatAmount(totals.basic)}</td>
                <td className="p-3 text-right font-extrabold text-green-700">{formatAmount(totals.bonus)}</td>
                <td className="p-3 text-right font-extrabold text-red-700">{formatAmount(totals.deduction)}</td>
                <td className="p-3 text-right font-extrabold text-orange-700">{formatAmount(totals.loanRecovery)}</td>
                <td className="p-3 text-right font-extrabold text-red-700">{formatAmount(totals.advanceRecovery)}</td>
                <td className="p-3 text-right font-extrabold text-blue-700">{formatAmount(totals.net)}</td>
                <td className="p-3 text-right font-extrabold text-green-700">{formatAmount(totals.paid)}</td>
                <td className="p-3 text-right font-extrabold text-red-700">{formatAmount(totals.remaining)}</td>
                <td colSpan={5} className="p-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
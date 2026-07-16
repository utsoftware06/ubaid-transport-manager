"use client";

import { type EmployeeRow, formatAmount } from "./Employees";

type Props = {
  rows: EmployeeRow[];
  search: string;
  setSearch: (value: string) => void;
  onEdit: (row: EmployeeRow) => void;
  onDelete: (row: EmployeeRow) => void;
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
  if (status === "Active") {
    return "border-green-200 bg-green-100 text-green-700";
  }

  return "border-red-200 bg-red-100 text-red-700";
}

export default function EmployeeTable({
  rows,
  search,
  setSearch,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const totals = rows.reduce(
    (total, row) => ({
      monthlySalary: total.monthlySalary + row.monthlySalary,
      totalLoan: total.totalLoan + row.totalLoan,
      recoveredLoan: total.recoveredLoan + row.recoveredLoan,
      remainingLoan: total.remainingLoan + row.remainingLoan,
      salaryGenerated: total.salaryGenerated + row.totalSalaryGenerated,
      salaryPaid: total.salaryPaid + row.totalSalaryPaid,
      remainingSalary: total.remainingSalary + row.remainingSalary,
    }),
    {
      monthlySalary: 0,
      totalLoan: 0,
      recoveredLoan: 0,
      remainingLoan: 0,
      salaryGenerated: 0,
      salaryPaid: 0,
      remainingSalary: 0,
    }
  );

  function handlePrintReport() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print employee report.");
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
                  <td>${escapeHtml(row.driverName)}</td>
                  <td>${escapeHtml(row.phone)}</td>
                  <td>${escapeHtml(row.cnic)}</td>
                  <td>${escapeHtml(row.joiningDate || "-")}</td>
                  <td>${escapeHtml(formatAmount(row.monthlySalary))}</td>
                  <td>${escapeHtml(formatAmount(row.totalLoan))}</td>
                  <td>${escapeHtml(formatAmount(row.recoveredLoan))}</td>
                  <td>${escapeHtml(formatAmount(row.remainingLoan))}</td>
                  <td>${escapeHtml(formatAmount(row.totalSalaryGenerated))}</td>
                  <td>${escapeHtml(formatAmount(row.totalSalaryPaid))}</td>
                  <td>${escapeHtml(formatAmount(row.remainingSalary))}</td>
                  <td>${escapeHtml(row.status)}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="14" class="empty">No employee records found.</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Employee Report</title>
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
              <h2>Employee Report</h2>
            </div>
            <div class="meta">
              <div><strong>Printed:</strong> ${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</div>
              <div><strong>Total Employees:</strong> ${rows.length}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Employee Name</th>
                <th>Type</th>
                <th>Driver</th>
                <th>Phone</th>
                <th>CNIC</th>
                <th>Joining</th>
                <th>Monthly Salary</th>
                <th>Total Loan</th>
                <th>Recovered Loan</th>
                <th>Remaining Loan</th>
                <th>Salary Generated</th>
                <th>Salary Paid</th>
                <th>Remaining Salary</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="6">Total</td>
                <td>${escapeHtml(formatAmount(totals.monthlySalary))}</td>
                <td>${escapeHtml(formatAmount(totals.totalLoan))}</td>
                <td>${escapeHtml(formatAmount(totals.recoveredLoan))}</td>
                <td>${escapeHtml(formatAmount(totals.remainingLoan))}</td>
                <td>${escapeHtml(formatAmount(totals.salaryGenerated))}</td>
                <td>${escapeHtml(formatAmount(totals.salaryPaid))}</td>
                <td>${escapeHtml(formatAmount(totals.remainingSalary))}</td>
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
          <h2 className="text-2xl font-bold text-gray-900">
            Employee Records
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Search, edit, delete and print employee records.
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <input
            type="text"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search employee, type, phone, CNIC, driver or status..."
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 lg:w-96"
          />

          <button
            type="button"
            onClick={handlePrintReport}
            className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
          >
            Print Employee Report
          </button>
        </div>
      </div>

      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          Loading employee records...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          No employee records found.
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1800px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Employee Name</th>
                <th className="p-3 text-left font-bold">Employee Type</th>
                <th className="p-3 text-left font-bold">Driver</th>
                <th className="p-3 text-left font-bold">Phone</th>
                <th className="p-3 text-left font-bold">CNIC</th>
                <th className="p-3 text-left font-bold">Joining Date</th>
                <th className="p-3 text-right font-bold">Monthly Salary</th>
                <th className="p-3 text-right font-bold">Total Loan</th>
                <th className="p-3 text-right font-bold">Recovered Loan</th>
                <th className="p-3 text-right font-bold">Remaining Loan</th>
                <th className="p-3 text-right font-bold">Salary Generated</th>
                <th className="p-3 text-right font-bold">Salary Paid</th>
                <th className="p-3 text-right font-bold">Remaining Salary</th>
                <th className="p-3 text-left font-bold">Status</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 font-bold">{row.employeeName}</td>
                  <td className="p-3 font-semibold">{row.employeeType}</td>
                  <td className="p-3 font-semibold">{row.driverName}</td>
                  <td className="p-3 font-semibold">{row.phone}</td>
                  <td className="p-3 font-semibold">{row.cnic}</td>
                  <td className="p-3 font-semibold">
                    {row.joiningDate || "-"}
                  </td>
                  <td className="p-3 text-right font-bold">
                    {formatAmount(row.monthlySalary)}
                  </td>
                  <td className="p-3 text-right font-bold text-purple-700">
                    {formatAmount(row.totalLoan)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(row.recoveredLoan)}
                  </td>
                  <td className="p-3 text-right font-bold text-red-700">
                    {formatAmount(row.remainingLoan)}
                  </td>
                  <td className="p-3 text-right font-bold">
                    {formatAmount(row.totalSalaryGenerated)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(row.totalSalaryPaid)}
                  </td>
                  <td className="p-3 text-right font-bold text-orange-700">
                    {formatAmount(row.remainingSalary)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.status
                      )}`}
                    >
                      {row.status}
                    </span>
                  </td>
                  <td className="min-w-[150px] p-3">
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
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={6} className="p-3 font-extrabold">
                  Total
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totals.monthlySalary)}
                </td>
                <td className="p-3 text-right font-extrabold text-purple-700">
                  {formatAmount(totals.totalLoan)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totals.recoveredLoan)}
                </td>
                <td className="p-3 text-right font-extrabold text-red-700">
                  {formatAmount(totals.remainingLoan)}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totals.salaryGenerated)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totals.salaryPaid)}
                </td>
                <td className="p-3 text-right font-extrabold text-orange-700">
                  {formatAmount(totals.remainingSalary)}
                </td>
                <td colSpan={2} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
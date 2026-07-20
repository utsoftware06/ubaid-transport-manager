"use client";

import {
  type EmployeeLedgerFilterValues,
  type EmployeeLedgerTransactionRow,
  formatAmount,
} from "./EmployeeLedger";

type Props = {
  rows: EmployeeLedgerTransactionRow[];
  isLoading: boolean;
  errorMessage: string;
  filters: EmployeeLedgerFilterValues;
};

function escapeHtml(value: string | number) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getBalanceStatus(balance: number) {
  if ( balance > 0) return "Payable";
  if (balance < 0) return "Receivable";
  return "Settled";
}

function getStatusClass(balance: number) {
  if (balance > 0) return "bg-red-100 text-red-700";
  if (balance < 0) return "bg-purple-100 text-purple-700";
  return "bg-blue-100 text-blue-700";
}

function getBalanceTextClass(balance: number) {
  if (balance > 0) return "text-red-700";
  if (balance < 0) return "text-purple-700";
  return "text-blue-700";
}

function sortRowsByEmployeeLedgerOrder(
  rows: EmployeeLedgerTransactionRow[]
): EmployeeLedgerTransactionRow[] {
  return [...rows].sort((first, second) => {
    const dateCompare = first.transactionDate.localeCompare(
      second.transactionDate
    );

    if (dateCompare !== 0) return dateCompare;

    const createdAtCompare = first.createdAt.localeCompare(second.createdAt);

    if (createdAtCompare !== 0) return createdAtCompare;

    return first.id - second.id;
  });
}

function getLatestEmployeeBalances(rows: EmployeeLedgerTransactionRow[]) {
  const latestBalanceByEmployee = new Map<string, number>();
  const sortedRows = [...rows].sort((first, second) => {
    const employeeCompare = first.employeeId.localeCompare(second.employeeId);

    if (employeeCompare !== 0) return employeeCompare;

    const dateCompare = first.transactionDate.localeCompare(
      second.transactionDate
    );

    if (dateCompare !== 0) return dateCompare;

    const createdAtCompare = first.createdAt.localeCompare(second.createdAt);

    if (createdAtCompare !== 0) return createdAtCompare;

    return first.id - second.id;
  });

  sortedRows.forEach((row) => {
    latestBalanceByEmployee.set(row.employeeId, row.runningBalance);
  });

  let companyPayable = 0;
  let employeeReceivable = 0;
  let netClosingBalance = 0;

  latestBalanceByEmployee.forEach((balance) => {
    netClosingBalance += balance;

    if (balance > 0) {
      companyPayable += balance;
    }

    if (balance < 0) {
      employeeReceivable += Math.abs(balance);
    }
  });

  return {
    companyPayable,
    employeeReceivable,
    netClosingBalance,
  };
}

export default function EmployeeLedgerTable({
  rows,
  isLoading,
  errorMessage,
  filters,
}: Props) {
  const totalDebit = rows.reduce((total, row) => total + row.debit, 0);
  const totalCredit = rows.reduce((total, row) => total + row.credit, 0);
  const latestBalances = getLatestEmployeeBalances(rows);
  const netClosingBalance = latestBalances.netClosingBalance;

  function getPrintableRows(targetRows: EmployeeLedgerTransactionRow[]) {
    return targetRows
      .map(
        (row) => `
          <tr>
            <td>${escapeHtml(row.transactionDate)}</td>
            <td>${escapeHtml(row.employeeName)}</td>
            <td>${escapeHtml(row.employeeType)}</td>
            <td>${escapeHtml(row.transactionType)}</td>
            <td>${escapeHtml(row.description || "-")}</td>
            <td>${escapeHtml(row.paymentMethod || "-")}</td>
            <td>${escapeHtml(row.referenceNo || "-")}</td>
            <td class="amount debit">${escapeHtml(formatAmount(row.debit))}</td>
            <td class="amount credit">${escapeHtml(formatAmount(row.credit))}</td>
            <td class="amount">${escapeHtml(formatAmount(row.runningBalance))}</td>
            <td>${escapeHtml(getBalanceStatus(row.runningBalance))}</td>
          </tr>
        `
      )
      .join("");
  }

  function openPrintWindow(title: string, html: string) {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print the ledger.");
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>${escapeHtml(title)}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 12mm; }
            body { margin: 0; color: #111827; font-family: Arial, sans-serif; }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 14px;
              margin-bottom: 18px;
            }
            h1 { margin: 0; font-size: 26px; font-weight: 800; }
            .subtitle { margin-top: 5px; font-size: 15px; font-weight: 700; }
            .meta { text-align: right; font-size: 13px; font-weight: 700; line-height: 1.6; }
            .summary {
              display: grid;
              grid-template-columns: repeat(var(--columns, 3), 1fr);
              gap: 10px;
              margin-bottom: 18px;
            }
            .card {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
              background: #f9fafb;
            }
            .label { font-size: 11px; font-weight: 800; text-transform: uppercase; }
            .value { margin-top: 5px; font-size: 16px; font-weight: 900; }
            table { width: 100%; border-collapse: collapse; font-size: 10px; }
            th { background: #2563eb; color: #fff; padding: 7px; border: 1px solid #2563eb; text-align: left; }
            td { padding: 6px; border: 1px solid #d1d5db; color: #111827; vertical-align: top; }
            tfoot td { background: #f3f4f6; font-weight: 900; }
            .amount { text-align: right; white-space: nowrap; }
            .debit { color: #b91c1c; font-weight: 800; }
            .credit { color: #15803d; font-weight: 800; }
            .signatures {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 48px;
              margin-top: 52px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 10px;
              text-align: center;
              font-size: 14px;
              font-weight: 700;
            }
          </style>
        </head>
        <body>
          ${html}
          <script>
            window.onload = function () { window.print(); };
            window.onafterprint = function () { window.close(); };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  function handlePrintEntry(row: EmployeeLedgerTransactionRow) {
    const status = getBalanceStatus(row.runningBalance);

    openPrintWindow(
      `Employee Ledger Entry - ${row.employeeName}`,
      `
        <div class="header">
          <div>
            <h1>UT Software</h1>
            <div class="subtitle">Employee Ledger Entry</div>
          </div>
          <div class="meta">
            <div>Date: ${escapeHtml(row.transactionDate)}</div>
            <div>Employee: ${escapeHtml(row.employeeName)}</div>
          </div>
        </div>

        <div class="summary" style="--columns: 3;">
          <div class="card">
            <div class="label">Debit</div>
            <div class="value">${escapeHtml(formatAmount(row.debit))}</div>
          </div>
          <div class="card">
            <div class="label">Credit</div>
            <div class="value">${escapeHtml(formatAmount(row.credit))}</div>
          </div>
          <div class="card">
            <div class="label">Running Balance</div>
            <div class="value">${escapeHtml(formatAmount(row.runningBalance))}</div>
          </div>
        </div>

        <table>
          <tbody>
            <tr><th>Employee</th><td>${escapeHtml(row.employeeName)}</td></tr>
            <tr><th>Employee Type</th><td>${escapeHtml(row.employeeType)}</td></tr>
            <tr><th>Transaction Date</th><td>${escapeHtml(row.transactionDate)}</td></tr>
            <tr><th>Transaction Type</th><td>${escapeHtml(row.transactionType)}</td></tr>
            <tr><th>Description</th><td>${escapeHtml(row.description || "-")}</td></tr>
            <tr><th>Payment Method</th><td>${escapeHtml(row.paymentMethod || "-")}</td></tr>
            <tr><th>Reference</th><td>${escapeHtml(row.referenceNo || "-")}</td></tr>
            <tr><th>Status</th><td>${escapeHtml(status)}</td></tr>
            <tr><th>Remarks</th><td>${escapeHtml(row.remarks || "-")}</td></tr>
          </tbody>
        </table>

        <div class="signatures">
          <div class="signature">Prepared By</div>
          <div class="signature">Employee Signature</div>
        </div>
      `
    );
  }

  function handlePrintEmployeeLedger(row: EmployeeLedgerTransactionRow) {
    const employeeRows = sortRowsByEmployeeLedgerOrder(
      rows.filter((item) => item.employeeId === row.employeeId)
    );
    const firstEmployeeRow = employeeRows[0] ?? null;
    const lastEmployeeRow = employeeRows[employeeRows.length - 1] ?? null;
    const openingBalance = firstEmployeeRow
      ? firstEmployeeRow.runningBalance -
        firstEmployeeRow.debit +
        firstEmployeeRow.credit
      : 0;
    const periodDebit = employeeRows.reduce(
      (total, item) => total + item.debit,
      0
    );
    const periodCredit = employeeRows.reduce(
      (total, item) => total + item.credit,
      0
    );
    const closingBalance = lastEmployeeRow?.runningBalance ?? 0;

    openPrintWindow(
      `Employee Ledger - ${row.employeeName}`,
      `
        <div class="header">
          <div>
            <h1>UT Software</h1>
            <div class="subtitle">Employee Ledger</div>
          </div>
          <div class="meta">
            <div>Employee: ${escapeHtml(row.employeeName)}</div>
            <div>Type: ${escapeHtml(row.employeeType)}</div>
            <div>Date Range: ${escapeHtml(filters.fromDate || "All")} to ${escapeHtml(filters.toDate || "All")}</div>
          </div>
        </div>

        <div class="summary" style="--columns: 4;">
          <div class="card"><div class="label">Opening Balance</div><div class="value">${escapeHtml(formatAmount(openingBalance))}</div></div>
          <div class="card"><div class="label">Period Debit</div><div class="value">${escapeHtml(formatAmount(periodDebit))}</div></div>
          <div class="card"><div class="label">Period Credit</div><div class="value">${escapeHtml(formatAmount(periodCredit))}</div></div>
          <div class="card"><div class="label">Closing Balance</div><div class="value">${escapeHtml(formatAmount(closingBalance))}</div></div>
        </div>

        <table>
          <thead>
            <tr>
              <th>Date</th>
              <th>Employee</th>
              <th>Type</th>
              <th>Transaction Type</th>
              <th>Description</th>
              <th>Payment Method</th>
              <th>Reference</th>
              <th>Debit</th>
              <th>Credit</th>
              <th>Running Balance</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>${getPrintableRows(employeeRows)}</tbody>
          <tfoot>
            <tr>
              <td colspan="7">Totals</td>
              <td class="amount debit">${escapeHtml(formatAmount(periodDebit))}</td>
              <td class="amount credit">${escapeHtml(formatAmount(periodCredit))}</td>
              <td class="amount">${escapeHtml(formatAmount(closingBalance))}</td>
              <td>${escapeHtml(getBalanceStatus(closingBalance))}</td>
            </tr>
          </tfoot>
        </table>
      `
    );
  }

  function handlePrintFullReport() {
    openPrintWindow(
      "Employee Ledger Report",
      `
        <div class="header">
          <div>
            <h1>UT Software</h1>
            <div class="subtitle">Employee Ledger Report</div>
          </div>
          <div class="meta">
            <div>Printed: ${escapeHtml(new Date().toLocaleString())}</div>
            <div>Date Range: ${escapeHtml(filters.fromDate || "All")} to ${escapeHtml(filters.toDate || "All")}</div>
            <div>Total Records: ${rows.length}</div>
          </div>
        </div>

        <div class="summary" style="--columns: 5;">
          <div class="card"><div class="label">Total Debit</div><div class="value">${escapeHtml(formatAmount(totalDebit))}</div></div>
          <div class="card"><div class="label">Total Credit</div><div class="value">${escapeHtml(formatAmount(totalCredit))}</div></div>
          <div class="card"><div class="label">Company Payable</div><div class="value">${escapeHtml(formatAmount(latestBalances.companyPayable))}</div></div>
          <div class="card"><div class="label">Employee Receivable</div><div class="value">${escapeHtml(formatAmount(latestBalances.employeeReceivable))}</div></div>
          <div class="card"><div class="label">Net Closing Balance</div><div class="value">${escapeHtml(formatAmount(netClosingBalance))}</div></div>
        </div>

        <table>
          <thead>
            <tr>
              <th>Date</th>
              <th>Employee</th>
              <th>Type</th>
              <th>Transaction Type</th>
              <th>Description</th>
              <th>Payment Method</th>
              <th>Reference</th>
              <th>Debit</th>
              <th>Credit</th>
              <th>Running Balance</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>${getPrintableRows(rows)}</tbody>
          <tfoot>
            <tr>
              <td colspan="7">Totals</td>
              <td class="amount debit">${escapeHtml(formatAmount(totalDebit))}</td>
              <td class="amount credit">${escapeHtml(formatAmount(totalCredit))}</td>
              <td class="amount">${escapeHtml(formatAmount(netClosingBalance))}</td>
              <td>${escapeHtml(getBalanceStatus(netClosingBalance))}</td>
            </tr>
          </tfoot>
        </table>
      `
    );
  }

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Employee Ledger Transactions
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Running balance by employee with debit and credit transaction view.
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintFullReport}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700"
        >
          Print Full Ledger Report
        </button>
      </div>

      {errorMessage && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {isLoading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          Loading employee ledger...
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          No ledger transactions found.
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1700px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Date</th>
                <th className="p-3 text-left font-bold">Employee</th>
                <th className="p-3 text-left font-bold">Type</th>
                <th className="p-3 text-left font-bold">Transaction Type</th>
                <th className="p-3 text-left font-bold">Description</th>
                <th className="p-3 text-left font-bold">Payment Method</th>
                <th className="p-3 text-left font-bold">Reference</th>
                <th className="p-3 text-right font-bold">Debit</th>
                <th className="p-3 text-right font-bold">Credit</th>
                <th className="p-3 text-right font-bold">Running Balance</th>
                <th className="p-3 text-left font-bold">Status</th>
                <th className="p-3 text-left font-bold">Remarks</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr key={row.id} className="hover:bg-blue-50">
                  <td className="p-3 font-medium text-gray-900">
                    {row.transactionDate || "-"}
                  </td>
                  <td className="p-3 font-bold text-gray-900">
                    {row.employeeName}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.employeeType}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.transactionType}
                  </td>
                  <td className="max-w-[280px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">
                      {row.description || "-"}
                    </div>
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.paymentMethod || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.referenceNo || "-"}
                  </td>
                  <td className="p-3 text-right font-bold text-red-700">
                    {row.debit > 0 ? formatAmount(row.debit) : "-"}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {row.credit > 0 ? formatAmount(row.credit) : "-"}
                  </td>
                  <td
                    className={`p-3 text-right font-extrabold ${getBalanceTextClass(
                      row.runningBalance
                    )}`}
                  >
                    {formatAmount(row.runningBalance)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-extrabold ${getStatusClass(
                        row.runningBalance
                      )}`}
                    >
                      {getBalanceStatus(row.runningBalance)}
                    </span>
                  </td>
                  <td className="max-w-[240px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">
                      {row.remarks || "-"}
                    </div>
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => handlePrintEntry(row)}
                        className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-black"
                      >
                        Print Entry
                      </button>
                      <button
                        type="button"
                        onClick={() => handlePrintEmployeeLedger(row)}
                        className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700"
                      >
                        Print Employee Ledger
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td
                  colSpan={7}
                  className="p-3 text-right font-extrabold text-gray-900"
                >
                  Totals
                </td>
                <td className="p-3 text-right font-extrabold text-red-700">
                  {formatAmount(totalDebit)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totalCredit)}
                </td>
                <td
                  className={`p-3 text-right font-extrabold ${getBalanceTextClass(
                    netClosingBalance
                  )}`}
                >
                  {formatAmount(netClosingBalance)}
                </td>
                <td className="p-3">
                  <span
                    className={`rounded-full px-3 py-1 text-xs font-extrabold ${getStatusClass(
                      netClosingBalance
                    )}`}
                  >
                    {getBalanceStatus(netClosingBalance)}
                  </span>
                </td>
                <td colSpan={2} className="p-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
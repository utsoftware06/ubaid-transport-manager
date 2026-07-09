"use client";

import type {
  OwnerLedgerFilterValues,
  OwnerLedgerSummary,
  OwnerReport,
} from "./OwnerLedger";
import { formatAmount } from "./OwnerLedger";

type Props = {
  reports: OwnerReport[];
  summary: OwnerLedgerSummary;
  filters: OwnerLedgerFilterValues;
};

export default function OwnerPrint({ reports, summary, filters }: Props) {
  function handlePrint() {
    if (reports.length === 0) return;

    const rowsHtml = reports
      .map(
        (report) => `
          <tr>
            <td>${report.ownerName}</td>
            <td>${report.totalTrips}</td>
            <td>${formatAmount(report.totalIncome)}</td>
            <td>${formatAmount(report.totalExpense)}</td>
            <td>${formatAmount(report.netProfit)}</td>
          </tr>
        `
      )
      .join("");

    const printWindow = window.open("", "_blank", "width=1100,height=800");
    if (!printWindow) return;

    printWindow.document.write(`
      <html>
        <head>
          <title>Owner Ledger Report</title>
          <style>
            body { font-family: Arial, sans-serif; padding: 30px; color: #111827; }
            h1, h2 { text-align: center; margin: 0; }
            h2 { margin-top: 8px; margin-bottom: 20px; }
            .summary { display: grid; grid-template-columns: repeat(5, 1fr); gap: 10px; margin-bottom: 25px; }
            .box { border: 1px solid #d1d5db; padding: 12px; border-radius: 8px; }
            .box p { margin: 0; font-weight: 700; font-size: 12px; }
            .box h3 { margin: 6px 0 0; font-size: 16px; }
            table { width: 100%; border-collapse: collapse; font-size: 12px; }
            th, td { border: 1px solid #d1d5db; padding: 9px; text-align: left; font-weight: 600; }
            th { background: #2563eb; color: white; }
          </style>
        </head>
        <body>
          <h1>UT Software</h1>
          <h2>Owner Ledger Report</h2>

          <div class="summary">
            <div class="box"><p>Owners</p><h3>${summary.totalOwners}</h3></div>
            <div class="box"><p>Trips</p><h3>${summary.totalTrips}</h3></div>
            <div class="box"><p>Income</p><h3>${formatAmount(summary.totalIncome)}</h3></div>
            <div class="box"><p>Expense</p><h3>${formatAmount(summary.totalExpense)}</h3></div>
            <div class="box"><p>Profit</p><h3>${formatAmount(summary.netProfit)}</h3></div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Owner</th>
                <th>Trips</th>
                <th>Income</th>
                <th>Expense</th>
                <th>Profit</th>
              </tr>
            </thead>
            <tbody>${rowsHtml}</tbody>
          </table>

          <script>
            window.onload = function () {
              window.print();
              window.onafterprint = function () {
                window.close();
              };
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  return (
    <button
      type="button"
      onClick={handlePrint}
      disabled={reports.length === 0}
      className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-gray-400"
    >
      🖨 Print All Owners
    </button>
  );
}
"use client";

import type {
  LoadingDetailsData,
  LoadingExpenseItem,
} from "./LoadingDetails";
import { formatAmount } from "./LoadingDetails";

type Props = {
  loading: LoadingDetailsData;
  expenses: LoadingExpenseItem[];
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
};

export default function LoadingPrint({
  loading,
  expenses,
  totalIncome,
  totalExpense,
  netProfit,
}: Props) {
  function handlePrint() {
    const itemsRows = loading.items
      .map(
        (item) => `
          <tr>
            <td>${item.itemName}</td>
            <td>${item.quantity || "-"}</td>
            <td>${item.weight || "-"}</td>
            <td>${item.unit}</td>
            <td>${item.remarks}</td>
          </tr>
        `
      )
      .join("");

    const expenseRows = expenses
      .map(
        (expense) => `
          <tr>
            <td>${expense.expenseName}</td>
            <td>${formatAmount(expense.amount)}</td>
            <td>${expense.remarks}</td>
          </tr>
        `
      )
      .join("");

    const printWindow = window.open("", "_blank", "width=1000,height=800");
    if (!printWindow) return;

    printWindow.document.write(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>Loading Details</title>
          <style>
            body { font-family: Arial, sans-serif; padding: 30px; color: #111827; }
            h1, h2 { text-align: center; margin: 0; }
            h2 { margin-top: 8px; margin-bottom: 20px; }
            h3 { margin-top: 25px; margin-bottom: 10px; color: #111827; }
            .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 20px; }
            .box { border: 1px solid #d1d5db; padding: 12px; border-radius: 8px; }
            .box p { margin: 0; font-size: 12px; font-weight: 700; color: #374151; }
            .box h4 { margin: 6px 0 0; font-size: 16px; color: #111827; }
            table { width: 100%; border-collapse: collapse; font-size: 12px; margin-top: 10px; }
            th, td { border: 1px solid #d1d5db; padding: 9px; text-align: left; font-weight: 600; color: #111827; }
            th { background: #2563eb; color: white; }
            .summary { margin-top: 22px; }
          </style>
        </head>

        <body>
          <h1>UT Software</h1>
          <h2>Loading Details Report</h2>

          <div class="grid">
            <div class="box"><p>Loading No</p><h4>${loading.loadingNo}</h4></div>
            <div class="box"><p>Date</p><h4>${loading.loadingDate}</h4></div>
            <div class="box"><p>Route</p><h4>${loading.route}</h4></div>
            <div class="box"><p>Vehicle</p><h4>${loading.vehicleNo}</h4></div>
            <div class="box"><p>Owner</p><h4>${loading.ownerName}</h4></div>
            <div class="box"><p>Driver</p><h4>${loading.driverName}</h4></div>
            <div class="box"><p>Customer</p><h4>${loading.customerName}</h4></div>
            <div class="box"><p>Freight</p><h4>${formatAmount(loading.freight)}</h4></div>
            <div class="box"><p>Profit</p><h4>${formatAmount(netProfit)}</h4></div>
          </div>

          <h3>Loading Items</h3>
          <table>
            <thead>
              <tr>
                <th>Item</th>
                <th>Quantity</th>
                <th>Weight</th>
                <th>Unit</th>
                <th>Remarks</th>
              </tr>
            </thead>
            <tbody>
              ${
                itemsRows ||
                `<tr><td colspan="5">No loading items found.</td></tr>`
              }
            </tbody>
          </table>

          <h3>Expense Breakdown</h3>
          <table>
            <thead>
              <tr>
                <th>Expense Name</th>
                <th>Amount</th>
                <th>Remarks</th>
              </tr>
            </thead>
            <tbody>
              ${
                expenseRows ||
                `<tr><td colspan="3">No expense record found.</td></tr>`
              }
            </tbody>
          </table>

          <div class="summary">
            <table>
              <thead>
                <tr>
                  <th>Total Income</th>
                  <th>Total Expense</th>
                  <th>Net Profit</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>${formatAmount(totalIncome)}</td>
                  <td>${formatAmount(totalExpense)}</td>
                  <td>${formatAmount(netProfit)}</td>
                </tr>
              </tbody>
            </table>
          </div>

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
      className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white shadow-sm hover:bg-blue-700"
    >
      🖨 Print Details
    </button>
  );
}
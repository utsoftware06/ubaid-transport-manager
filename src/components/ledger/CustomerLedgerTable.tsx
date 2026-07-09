"use client";

import type { CustomerLedgerRow } from "./CustomerLedger";

type Props = {
  loading: boolean;
  rows: CustomerLedgerRow[];
};

function formatAmount(value: number): string {
  return value.toLocaleString("en-PK", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

export default function CustomerLedgerTable({ loading, rows }: Props) {
  function handlePrint() {
    if (rows.length === 0) return;

    const totalFreight = rows.reduce((sum, row) => sum + row.freight, 0);

    const rowsHtml = rows
      .map(
        (row) => `
          <tr>
            <td>${row.bookingDate}</td>
            <td>${row.bookingNo}</td>
            <td>${row.senderName}</td>
            <td>${row.receiverName}</td>
            <td>${row.route}</td>
            <td>${row.goodsName}</td>
            <td>${row.quantity}</td>
            <td>${row.weight}</td>
            <td>Rs. ${formatAmount(row.freight)}</td>
            <td>${row.status}</td>
          </tr>
        `
      )
      .join("");

    const printWindow = window.open("", "_blank", "width=1100,height=800");
    if (!printWindow) return;

    printWindow.document.write(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>Customer Ledger</title>
          <style>
            body {
              font-family: Arial, sans-serif;
              padding: 30px;
              color: #111827;
            }

            h1, h3 {
              text-align: center;
              margin: 0;
              color: #111827;
            }

            h3 {
              margin-top: 8px;
              margin-bottom: 20px;
            }

            .summary {
              margin-bottom: 20px;
              padding: 15px;
              border: 1px solid #d1d5db;
              font-weight: bold;
              color: #111827;
            }

            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 12px;
              color: #111827;
            }

            th, td {
              border: 1px solid #d1d5db;
              padding: 9px;
              text-align: left;
              color: #111827;
              font-weight: 600;
            }

            th {
              background: #2563eb;
              color: #ffffff;
              font-weight: 700;
            }
          </style>
        </head>

        <body>
          <h1>UT Software</h1>
          <h3>Customer Ledger Report</h3>

          <div class="summary">
            Total Bookings: ${rows.length}
            &nbsp;&nbsp;&nbsp;
            Total Freight: Rs. ${formatAmount(totalFreight)}
          </div>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Booking No</th>
                <th>Sender</th>
                <th>Receiver</th>
                <th>Route</th>
                <th>Goods</th>
                <th>Qty</th>
                <th>Weight</th>
                <th>Freight</th>
                <th>Status</th>
              </tr>
            </thead>

            <tbody>
              ${rowsHtml}
            </tbody>
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

  if (loading) {
    return (
      <div className="rounded-xl bg-white p-10 text-center shadow-md">
        <span className="font-semibold text-gray-900">
          Loading Customer Ledger...
        </span>
      </div>
    );
  }

  return (
    <div className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5 flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Customer Ledger
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-700">
            Sender wise booking details
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrint}
          disabled={rows.length === 0}
          className="rounded-lg bg-blue-600 px-5 py-2 font-semibold text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-gray-400"
        >
          🖨 Print
        </button>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full border-collapse text-sm text-gray-900">
          <thead>
            <tr className="bg-gray-100 text-gray-900">
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Date
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Booking No
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Sender
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Receiver
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Route
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Goods
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Qty
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Weight
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Freight
              </th>
              <th className="border border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                Status
              </th>
            </tr>
          </thead>

          <tbody className="bg-white text-gray-900">
            {rows.length === 0 ? (
              <tr>
                <td
                  colSpan={10}
                  className="border border-gray-200 px-4 py-10 text-center font-semibold text-gray-900"
                >
                  No Record Found
                </td>
              </tr>
            ) : (
              rows.map((row) => (
                <tr
                  key={row.id}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.bookingDate}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-bold text-gray-900">
                    {row.bookingNo}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.senderName}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.receiverName}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.route}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.goodsName}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.quantity}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.weight}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-bold text-gray-900">
                    Rs. {formatAmount(row.freight)}
                  </td>

                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {row.status}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
"use client";

import type { OwnerReport } from "./OwnerLedger";
import { formatAmount } from "./OwnerLedger";

type Props = {
  ownerReport: OwnerReport;
  onClose: () => void;
};

export default function OwnerTripsModal({ ownerReport, onClose }: Props) {
  function handlePrint() {
    const rowsHtml = ownerReport.trips
      .map(
        (trip) => `
          <tr>
            <td>${trip.date}</td>
            <td>${trip.loadingNo}</td>
            <td>${trip.vehicleNo}</td>
            <td>${trip.driverName}</td>
            <td>${trip.route}</td>
            <td>Rs. ${formatAmount(trip.income)}</td>
            <td>Rs. ${formatAmount(trip.expense)}</td>
            <td>Rs. ${formatAmount(trip.profit)}</td>
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
          <title>Owner Ledger</title>
          <style>
            body {
              font-family: Arial, sans-serif;
              padding: 30px;
              color: #111827;
            }

            h1, h2 {
              text-align: center;
              margin: 0;
              color: #111827;
            }

            h2 {
              margin-top: 8px;
              margin-bottom: 20px;
            }

            .summary {
              display: grid;
              grid-template-columns: repeat(4, 1fr);
              gap: 12px;
              margin-bottom: 22px;
            }

            .box {
              border: 1px solid #d1d5db;
              padding: 12px;
              border-radius: 8px;
            }

            .box p {
              margin: 0;
              font-size: 13px;
              color: #374151;
              font-weight: 700;
            }

            .box h3 {
              margin: 6px 0 0;
              font-size: 18px;
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
          <h2>${ownerReport.ownerName} Owner Ledger</h2>

          <div class="summary">
            <div class="box">
              <p>Total Trips</p>
              <h3>${ownerReport.totalTrips}</h3>
            </div>

            <div class="box">
              <p>Total Income</p>
              <h3>Rs. ${formatAmount(ownerReport.totalIncome)}</h3>
            </div>

            <div class="box">
              <p>Total Expense</p>
              <h3>Rs. ${formatAmount(ownerReport.totalExpense)}</h3>
            </div>

            <div class="box">
              <p>Net Profit</p>
              <h3>Rs. ${formatAmount(ownerReport.netProfit)}</h3>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Loading No</th>
                <th>Vehicle</th>
                <th>Driver</th>
                <th>Route</th>
                <th>Income</th>
                <th>Expense</th>
                <th>Profit</th>
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

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div className="max-h-[90vh] w-full max-w-6xl overflow-hidden rounded-xl bg-white shadow-xl">
        <div className="flex items-start justify-between gap-4 border-b border-gray-200 p-5">
          <div>
            <h3 className="text-2xl font-bold text-gray-900">
              {ownerReport.ownerName} Trips Detail
            </h3>
            <p className="mt-1 text-sm font-medium text-gray-700">
              Owner wise vehicle trips, income, expense aur profit detail.
            </p>
          </div>

          <div className="flex gap-3">
            <button
              type="button"
              onClick={handlePrint}
              className="rounded-lg bg-blue-600 px-4 py-2 font-bold text-white shadow-sm hover:bg-blue-700"
            >
              🖨 Print
            </button>

            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50"
            >
              Close
            </button>
          </div>
        </div>

        <div className="overflow-auto p-5">
          <div className="mb-5 grid grid-cols-2 gap-4 lg:grid-cols-4">
            <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
              <p className="text-sm font-semibold text-gray-700">
                Total Trips
              </p>
              <p className="mt-1 text-xl font-bold text-gray-900">
                {ownerReport.totalTrips}
              </p>
            </div>

            <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
              <p className="text-sm font-semibold text-gray-700">
                Total Income
              </p>
              <p className="mt-1 text-xl font-bold text-gray-900">
                Rs. {formatAmount(ownerReport.totalIncome)}
              </p>
            </div>

            <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
              <p className="text-sm font-semibold text-gray-700">
                Total Expense
              </p>
              <p className="mt-1 text-xl font-bold text-gray-900">
                Rs. {formatAmount(ownerReport.totalExpense)}
              </p>
            </div>

            <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
              <p className="text-sm font-semibold text-gray-700">
                Net Profit
              </p>
              <p
                className={`mt-1 text-xl font-bold ${
                  ownerReport.netProfit >= 0
                    ? "text-green-700"
                    : "text-red-700"
                }`}
              >
                Rs. {formatAmount(ownerReport.netProfit)}
              </p>
            </div>
          </div>

          <div className="overflow-x-auto rounded-lg border border-gray-200">
            <table className="w-full min-w-[900px] border-collapse text-sm text-gray-900">
              <thead>
                <tr className="bg-gray-100 text-gray-900">
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Date
                  </th>
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Loading No
                  </th>
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Vehicle
                  </th>
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Driver
                  </th>
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Route
                  </th>
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Income
                  </th>
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Expense
                  </th>
                  <th className="border-b border-gray-300 px-4 py-3 text-left font-bold text-gray-900">
                    Profit
                  </th>
                </tr>
              </thead>

              <tbody className="bg-white text-gray-900">
                {ownerReport.trips.map((trip) => (
                  <tr
                    key={trip.id}
                    className="bg-white text-gray-900 hover:bg-gray-50"
                  >
                    <td className="border-b border-gray-200 px-4 py-3 font-semibold text-gray-900">
                      {trip.date}
                    </td>

                    <td className="border-b border-gray-200 px-4 py-3 font-bold text-gray-900">
                      {trip.loadingNo}
                    </td>

                    <td className="border-b border-gray-200 px-4 py-3 font-semibold text-gray-900">
                      {trip.vehicleNo}
                    </td>

                    <td className="border-b border-gray-200 px-4 py-3 font-semibold text-gray-900">
                      {trip.driverName}
                    </td>

                    <td className="border-b border-gray-200 px-4 py-3 font-semibold text-gray-900">
                      {trip.route}
                    </td>

                    <td className="border-b border-gray-200 px-4 py-3 font-bold text-gray-900">
                      Rs. {formatAmount(trip.income)}
                    </td>

                    <td className="border-b border-gray-200 px-4 py-3 font-bold text-gray-900">
                      Rs. {formatAmount(trip.expense)}
                    </td>

                    <td
                      className={`border-b border-gray-200 px-4 py-3 font-bold ${
                        trip.profit >= 0 ? "text-green-700" : "text-red-700"
                      }`}
                    >
                      Rs. {formatAmount(trip.profit)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
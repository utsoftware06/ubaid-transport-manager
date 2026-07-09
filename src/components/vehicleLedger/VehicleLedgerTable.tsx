"use client";

import type { VehicleReport } from "./VehicleLedger";
import { formatAmount } from "./VehicleLedger";

type Props = {
  reports: VehicleReport[];
  onViewTrips: (vehicleReport: VehicleReport) => void;
};

export default function VehicleLedgerTable({ reports, onViewTrips }: Props) {
  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-gray-900">
          Vehicle Summary
        </h2>
        <p className="mt-1 text-sm font-medium text-gray-700">
          Har vehicle ka trips, income, expense aur profit summary.
        </p>
      </div>

      {reports.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-semibold text-gray-900">
            No vehicle record found.
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
          {reports.map((report) => {
            const isProfit = report.netProfit >= 0;

            return (
              <article
                key={report.vehicleId}
                className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm transition hover:shadow-md"
              >
                <div className="border-b border-gray-200 pb-4">
                  <p className="text-sm font-semibold text-gray-700">
                    Vehicle Number
                  </p>
                  <h3 className="mt-1 text-xl font-bold text-gray-900">
                    {report.vehicleNo}
                  </h3>
                  <p className="mt-1 text-sm font-semibold text-gray-700">
                    Owner: {report.ownerName}
                  </p>
                </div>

                <div className="mt-4 grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-sm font-semibold text-gray-700">
                      Total Trips
                    </p>
                    <p className="mt-1 text-lg font-bold text-gray-900">
                      {report.totalTrips}
                    </p>
                  </div>

                  <div>
                    <p className="text-sm font-semibold text-gray-700">
                      Income
                    </p>
                    <p className="mt-1 text-lg font-bold text-gray-900">
                      {formatAmount(report.totalIncome)}
                    </p>
                  </div>

                  <div>
                    <p className="text-sm font-semibold text-gray-700">
                      Expense
                    </p>
                    <p className="mt-1 text-lg font-bold text-gray-900">
                      {formatAmount(report.totalExpense)}
                    </p>
                  </div>

                  <div>
                    <p className="text-sm font-semibold text-gray-700">
                      Profit
                    </p>
                    <p
                      className={`mt-1 text-lg font-bold ${
                        isProfit ? "text-green-700" : "text-red-700"
                      }`}
                    >
                      {formatAmount(report.netProfit)}
                    </p>
                  </div>
                </div>

                <div className="mt-5 flex items-center justify-between border-t border-gray-200 pt-4">
                  <span
                    className={`rounded-full px-3 py-1 text-xs font-bold ${
                      isProfit
                        ? "bg-green-100 text-green-700"
                        : "bg-red-100 text-red-700"
                    }`}
                  >
                    {isProfit ? "Profit" : "Loss"}
                  </span>

                  <button
                    type="button"
                    onClick={() => onViewTrips(report)}
                    className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-blue-700"
                  >
                    View Trips
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}
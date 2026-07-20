"use client";

import { type DashboardTrip, formatAmount } from "./DashboardOverview";

type Props = {
  trips: DashboardTrip[];
  loading: boolean;
  errorMessage: string;
};

function formatDate(value: string) {
  if (!value) return "-";

  const date = new Date(`${value}T00:00:00`);

  if (Number.isNaN(date.getTime())) return "-";

  return date.toLocaleDateString("en-PK", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function statusClass(status: DashboardTrip["tripStatus"]) {
  if (status === "Planned") return "bg-gray-100 text-gray-700";
  if (status === "Loading") return "bg-blue-100 text-blue-700";
  if (status === "In Transit") return "bg-indigo-100 text-indigo-700";
  if (status === "Delivered") return "bg-amber-100 text-amber-700";
  if (status === "Completed") return "bg-green-100 text-green-700";
  return "bg-red-100 text-red-700";
}

function formatRoute(loadingFrom: string, deliveryTo: string) {
  const from = loadingFrom.trim();
  const to = deliveryTo.trim();

  if (!from && !to) return "-";

  return `${from || "-"} → ${to || "-"}`;
}

function formatProfit(value: number) {
  return value < 0
    ? `-${formatAmount(Math.abs(value))}`
    : formatAmount(value);
}

export default function RecentTrips({
  trips,
  loading,
}: Props) {
  return (
    <section className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">Recent Trips</h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Latest 10 trips from the selected dashboard filter.
        </p>
      </div>

      {loading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          Loading recent trips...
        </div>
      ) : trips.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-extrabold text-gray-900">No trips found.</p>
          <p className="mt-2 text-sm font-bold text-gray-900">
            Add trips or change the selected dashboard filter.
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1400px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">Trip No</th>
                <th className="p-3 text-left font-bold">Date</th>
                <th className="p-3 text-left font-bold">Vehicle</th>
                <th className="p-3 text-left font-bold">Driver</th>
                <th className="p-3 text-left font-bold">Customer</th>
                <th className="p-3 text-left font-bold">Route</th>
                <th className="p-3 text-right font-bold">Freight</th>
                <th className="p-3 text-right font-bold">Received</th>
                <th className="p-3 text-right font-bold">Expense</th>
                <th className="p-3 text-right font-bold">Profit</th>
                <th className="p-3 text-left font-bold">Status</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {trips.map((trip) => (
                <tr key={trip.id} className="hover:bg-blue-50">
                  <td className="p-3 font-bold text-gray-900">
                    {trip.tripNo || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {formatDate(trip.tripDate)}
                  </td>
                  <td className="p-3 font-bold text-gray-900">
                    {trip.vehicleNo}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {trip.driverName}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {trip.customerName || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {formatRoute(trip.loadingFrom, trip.deliveryTo)}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(trip.freightAmount)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(trip.receivedAmount)}
                  </td>
                  <td className="p-3 text-right font-bold text-red-700">
                    {formatAmount(trip.totalExpense)}
                  </td>
                  <td
                    className={`p-3 text-right font-bold ${
                      trip.netProfit >= 0 ? "text-green-700" : "text-red-700"
                    }`}
                  >
                    {formatProfit(trip.netProfit)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-extrabold ${statusClass(
                        trip.tripStatus
                      )}`}
                    >
                      {trip.tripStatus}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
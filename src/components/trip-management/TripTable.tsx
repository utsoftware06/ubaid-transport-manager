"use client";

import { type TripRecord, formatAmount } from "./TripManagement";

type Props = {
  trips: TripRecord[];
  loading: boolean;
  saving: boolean;
  error: string;
  onSelect: (trip: TripRecord) => void;
  onDelete: (id: string) => Promise<boolean>;
  onView: (trip: TripRecord) => void;
  onRefresh: () => Promise<void>;
};

function formatDate(value: string | null) {
  if (!value) return "-";
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return "-";
  return date.toLocaleDateString("en-PK");
}

function statusClass(status: TripRecord["trip_status"]) {
  if (status === "Planned") return "bg-gray-100 text-gray-700";
  if (status === "Loading") return "bg-blue-100 text-blue-700";
  if (status === "In Transit") return "bg-indigo-100 text-indigo-700";
  if (status === "Delivered") return "bg-amber-100 text-amber-700";
  if (status === "Completed") return "bg-green-100 text-green-700";
  return "bg-red-100 text-red-700";
}

export default function TripTable({
  trips,
  loading,
  saving,
  error,
  onSelect,
  onDelete,
  onView,
  onRefresh,
}: Props) {
  const totals = trips.reduce(
    (total, trip) => {
      total.freight += trip.freight_amount;
      total.received += trip.received_amount;
      total.balance += trip.payment_balance;
      total.expense += trip.total_expense;
      total.profit += trip.net_profit;
      return total;
    },
    { freight: 0, received: 0, balance: 0, expense: 0, profit: 0 }
  );

  return (
    <section className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Trip Records</h2>
          <p className="mt-2 text-sm font-medium text-gray-900">
            Review trip progress, payments, balances and profitability.
          </p>
        </div>

        <button
          type="button"
          onClick={() => void onRefresh()}
          disabled={loading || saving}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {loading ? "Refreshing..." : "Refresh"}
        </button>
      </div>

      {error && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {error}
        </div>
      )}

      {loading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          Loading trip records...
        </div>
      ) : trips.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-extrabold text-gray-900">No trip records found.</p>
          <p className="mt-2 text-sm font-bold text-gray-900">
            Add a new trip or change the filters.
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1700px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">#</th>
                <th className="p-3 text-left font-bold">Trip No</th>
                <th className="p-3 text-left font-bold">Date</th>
                <th className="p-3 text-left font-bold">Vehicle</th>
                <th className="p-3 text-left font-bold">Owner</th>
                <th className="p-3 text-left font-bold">Driver</th>
                <th className="p-3 text-left font-bold">Customer</th>
                <th className="p-3 text-left font-bold">Route</th>
                <th className="p-3 text-right font-bold">Freight</th>
                <th className="p-3 text-right font-bold">Received</th>
                <th className="p-3 text-right font-bold">Balance</th>
                <th className="p-3 text-right font-bold">Expense</th>
                <th className="p-3 text-right font-bold">Profit</th>
                <th className="p-3 text-left font-bold">Status</th>
                <th className="p-3 text-left font-bold">Actions</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {trips.map((trip, index) => (
                <tr key={trip.id} className="hover:bg-blue-50">
                  <td className="p-3 font-bold">{index + 1}</td>
                  <td className="p-3 font-bold">{trip.trip_no}</td>
                  <td className="p-3 font-medium">{formatDate(trip.trip_date)}</td>
                  <td className="p-3 font-bold">{trip.vehicleNo}</td>
                  <td className="p-3 font-medium">{trip.ownerName}</td>
                  <td className="p-3 font-medium">{trip.driverName}</td>
                  <td className="p-3 font-medium">{trip.customer_name || "-"}</td>
                  <td className="p-3 font-medium">
                    {trip.loading_from} → {trip.delivery_to}
                  </td>
                  <td className="p-3 text-right font-bold">{formatAmount(trip.freight_amount)}</td>
                  <td className="p-3 text-right font-bold text-green-700">{formatAmount(trip.received_amount)}</td>
                  <td className="p-3 text-right font-bold text-amber-700">{formatAmount(trip.payment_balance)}</td>
                  <td className="p-3 text-right font-bold text-red-700">{formatAmount(trip.total_expense)}</td>
                  <td className={`p-3 text-right font-bold ${trip.net_profit >= 0 ? "text-green-700" : "text-red-700"}`}>
                    {formatAmount(trip.net_profit)}
                  </td>
                  <td className="p-3">
                    <span className={`rounded-full px-3 py-1 text-xs font-extrabold ${statusClass(trip.trip_status)}`}>
                      {trip.trip_status}
                    </span>
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button type="button" onClick={() => onView(trip)} disabled={saving} className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-black disabled:cursor-not-allowed">
                        View
                      </button>
                      <button type="button" onClick={() => onSelect(trip)} disabled={saving} className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed">
                        Edit
                      </button>
                      <button type="button" onClick={() => void onDelete(trip.id)} disabled={saving} className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed">
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td colSpan={8} className="p-3 text-right font-extrabold text-gray-900">Totals</td>
                <td className="p-3 text-right font-extrabold">{formatAmount(totals.freight)}</td>
                <td className="p-3 text-right font-extrabold text-green-700">{formatAmount(totals.received)}</td>
                <td className="p-3 text-right font-extrabold text-amber-700">{formatAmount(totals.balance)}</td>
                <td className="p-3 text-right font-extrabold text-red-700">{formatAmount(totals.expense)}</td>
                <td className={`p-3 text-right font-extrabold ${totals.profit >= 0 ? "text-green-700" : "text-red-700"}`}>
                  {formatAmount(totals.profit)}
                </td>
                <td colSpan={2} className="p-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </section>
  );
}
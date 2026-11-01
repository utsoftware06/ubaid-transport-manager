"use client";

import { useState } from "react";
import {
  type TripRecord,
  formatAmount,
  tripStatusTranslationKey,
} from "./TripManagement";
import { useLanguage } from "@/contexts/LanguageContext";

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
  const { t, dir } = useLanguage();
  const [page, setPage] = useState(1);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(trips.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleTrips = trips.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );
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
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("tripManagement.table.title")}
          </h2>
          <p className="mt-2 text-sm font-medium text-gray-900">
            {t("tripManagement.table.description")}
          </p>
        </div>

        <button
          type="button"
          onClick={() => void onRefresh()}
          disabled={loading || saving}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {loading ? t("common.states.refreshing") : t("common.actions.refresh")}
        </button>
      </div>

      {error && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {error}
        </div>
      )}

      {loading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          {t("tripManagement.table.loading")}
        </div>
      ) : trips.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-extrabold text-gray-900">
            {t("tripManagement.table.empty")}
          </p>
          <p className="mt-2 text-sm font-bold text-gray-900">
            {t("tripManagement.table.emptyHint")}
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-300">
          <table className="min-w-[1700px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">#</th>
                <th className="p-3 text-start font-bold">{t("tripManagement.form.tripNumber")}</th>
                <th className="p-3 text-start font-bold">{t("common.date")}</th>
                <th className="p-3 text-start font-bold">{t("common.vehicle")}</th>
                <th className="p-3 text-start font-bold">{t("common.owner")}</th>
                <th className="p-3 text-start font-bold">{t("common.driver")}</th>
                <th className="p-3 text-start font-bold">{t("common.customer")}</th>
                <th className="p-3 text-start font-bold">{t("common.route")}</th>
                <th className="p-3 text-end font-bold">{t("common.freight")}</th>
                <th className="p-3 text-end font-bold">{t("tripManagement.table.received")}</th>
                <th className="p-3 text-end font-bold">{t("common.balance")}</th>
                <th className="p-3 text-end font-bold">{t("common.expense")}</th>
                <th className="p-3 text-end font-bold">{t("common.profit")}</th>
                <th className="p-3 text-start font-bold">{t("common.status")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {visibleTrips.map((trip, index) => (
                <tr key={trip.id} className="hover:bg-blue-50">
                  <td className="p-3 font-bold">{(currentPage - 1) * pageSize + index + 1}</td>
                  <td className="p-3 font-bold" dir="ltr">{trip.trip_no}</td>
                  <td className="p-3 font-medium" dir="ltr">{formatDate(trip.trip_date)}</td>
                  <td className="p-3 font-bold" dir="ltr">{trip.vehicleNo}</td>
                  <td className="p-3 font-medium">{trip.ownerName}</td>
                  <td className="p-3 font-medium">{trip.driverName}</td>
                  <td className="p-3 font-medium">{trip.customer_name || "-"}</td>
                  <td className="p-3 font-medium">
                    {trip.loading_from} {dir === "rtl" ? "←" : "→"} {trip.delivery_to}
                  </td>
                  <td className="p-3 text-end font-bold" dir="ltr">{formatAmount(trip.freight_amount)}</td>
                  <td className="p-3 text-end font-bold text-green-700" dir="ltr">{formatAmount(trip.received_amount)}</td>
                  <td className="p-3 text-end font-bold text-amber-700" dir="ltr">{formatAmount(trip.payment_balance)}</td>
                  <td className="p-3 text-end font-bold text-red-700" dir="ltr">{formatAmount(trip.total_expense)}</td>
                  <td dir="ltr" className={`p-3 text-end font-bold ${trip.net_profit >= 0 ? "text-green-700" : "text-red-700"}`}>
                    {formatAmount(trip.net_profit)}
                  </td>
                  <td className="p-3">
                    <span className={`rounded-full px-3 py-1 text-xs font-extrabold ${statusClass(trip.trip_status)}`}>
                      {t(tripStatusTranslationKey(trip.trip_status))}
                    </span>
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button type="button" aria-label={`${t("common.actions.view")} ${trip.trip_no}`} onClick={() => onView(trip)} disabled={saving} className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-black disabled:cursor-not-allowed">
                        {t("common.actions.view")}
                      </button>
                      <button type="button" aria-label={`${t("common.actions.edit")} ${trip.trip_no}`} onClick={() => onSelect(trip)} disabled={saving} className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed">
                        {t("common.actions.edit")}
                      </button>
                      <button type="button" aria-label={`${t("common.actions.delete")} ${trip.trip_no}`} onClick={() => void onDelete(trip.id)} disabled={saving} className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed">
                        {t("common.actions.delete")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="border-t-2 border-gray-300 bg-white text-gray-900">
              <tr>
                <td colSpan={8} className="p-3 text-end font-extrabold text-gray-900">{t("tripManagement.table.totals")}</td>
                <td className="p-3 text-end font-extrabold" dir="ltr">{formatAmount(totals.freight)}</td>
                <td className="p-3 text-end font-extrabold text-green-700" dir="ltr">{formatAmount(totals.received)}</td>
                <td className="p-3 text-end font-extrabold text-amber-700" dir="ltr">{formatAmount(totals.balance)}</td>
                <td className="p-3 text-end font-extrabold text-red-700" dir="ltr">{formatAmount(totals.expense)}</td>
                <td dir="ltr" className={`p-3 text-end font-extrabold ${totals.profit >= 0 ? "text-green-700" : "text-red-700"}`}>
                  {formatAmount(totals.profit)}
                </td>
                <td colSpan={2} className="p-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
      {!loading && trips.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-gray-900">
          <span className="font-bold">
            {t("common.pagination.page")} {currentPage}{" "}
            {t("common.pagination.of")} {totalPages}
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              aria-label={t("common.pagination.previous")}
              disabled={currentPage === 1}
              onClick={() => setPage((value) => Math.max(1, value - 1))}
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
            >
              {t("common.pagination.previous")}
            </button>
            <button
              type="button"
              aria-label={t("common.pagination.next")}
              disabled={currentPage === totalPages}
              onClick={() =>
                setPage((value) => Math.min(totalPages, value + 1))
              }
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
            >
              {t("common.pagination.next")}
            </button>
          </div>
        </div>
      )}
    </section>
  );
}

"use client";

import { useEffect } from "react";
import { type TripRecord, formatAmount } from "./TripManagement";

type Props = {
  trip: TripRecord | null;
  onClose: () => void;
};

function formatDate(value: string | null) {
  if (!value) return "-";
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return "-";
  return date.toLocaleDateString("en-PK");
}

function formatDateTime(value: string | null) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  return date.toLocaleString("en-PK");
}

function displayValue(value: string | null) {
  return value && value.trim() ? value : "-";
}

export default function TripDetailsModal({ trip, onClose }: Props) {
  useEffect(() => {
    if (!trip) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }

    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.body.style.overflow = "";
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose, trip]);

  if (!trip) return null;

  const details = [
    ["Trip No", trip.trip_no],
    ["Trip Date", formatDate(trip.trip_date)],
    ["Vehicle", trip.vehicleNo],
    ["Owner", trip.ownerName],
    ["Driver", trip.driverName],
    ["Booking Customer", trip.bookingCustomerName],
    ["Customer Name", displayValue(trip.customer_name)],
    ["Customer Phone", displayValue(trip.customer_phone)],
    ["Loading From", trip.loading_from],
    ["Delivery To", trip.delivery_to],
    ["Goods Description", displayValue(trip.goods_description)],
    ["Freight Amount", formatAmount(trip.freight_amount)],
    ["Customer Advance", formatAmount(trip.customer_advance)],
    ["Driver Advance", formatAmount(trip.driver_advance)],
    ["Total Expense", formatAmount(trip.total_expense)],
    ["Received Amount", formatAmount(trip.received_amount)],
    ["Payment Balance", formatAmount(trip.payment_balance)],
    ["Net Profit", formatAmount(trip.net_profit)],
    ["Status", trip.trip_status],
    ["Start Date", formatDate(trip.start_date)],
    ["Completion Date", formatDate(trip.completion_date)],
    ["Remarks", displayValue(trip.remarks)],
    ["Created At", formatDateTime(trip.created_at)],
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="max-h-[90vh] w-full max-w-5xl overflow-y-auto rounded-xl bg-white p-6 shadow-2xl md:p-8">
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">
              Trip / Chakkar Details
            </h2>
            <p className="mt-1 text-sm font-medium text-gray-900">
              Complete record for {trip.trip_no}.
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            className="rounded-lg bg-gray-900 px-4 py-2 text-sm font-bold text-white hover:bg-black"
          >
            Close
          </button>
        </div>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {details.map(([label, value]) => (
            <div
              key={label}
              className="rounded-lg border border-gray-200 bg-gray-50 p-4"
            >
              <p className="text-xs font-extrabold uppercase text-gray-900">
                {label}
              </p>
              <p className="mt-2 break-words text-base font-bold text-gray-900">
                {value}
              </p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
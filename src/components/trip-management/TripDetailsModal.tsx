"use client";

import { useEffect, useRef } from "react";
import {
  type TripRecord,
  formatAmount,
  tripStatusTranslationKey,
} from "./TripManagement";
import { useLanguage } from "@/contexts/LanguageContext";

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
  const { t, dir } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!trip) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);
    closeButtonRef.current?.focus();

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose, trip]);

  if (!trip) return null;

  const details = [
    { label: t("tripManagement.form.tripNumber"), value: trip.trip_no, technical: true },
    { label: t("tripManagement.form.tripDate"), value: formatDate(trip.trip_date), technical: true },
    { label: t("common.vehicle"), value: trip.vehicleNo, technical: true },
    { label: t("common.owner"), value: trip.ownerName },
    { label: t("common.driver"), value: trip.driverName },
    { label: t("tripManagement.details.bookingCustomer"), value: trip.bookingCustomerName },
    { label: t("tripManagement.details.customerName"), value: displayValue(trip.customer_name) },
    { label: t("tripManagement.details.customerPhone"), value: displayValue(trip.customer_phone), technical: true },
    { label: t("tripManagement.form.loadingFrom"), value: trip.loading_from },
    { label: t("tripManagement.form.deliveryTo"), value: trip.delivery_to },
    { label: t("tripManagement.details.goodsDescription"), value: displayValue(trip.goods_description) },
    { label: t("tripManagement.form.freightAmount"), value: formatAmount(trip.freight_amount), technical: true },
    { label: t("tripManagement.form.customerAdvance"), value: formatAmount(trip.customer_advance), technical: true },
    { label: t("tripManagement.form.driverAdvance"), value: formatAmount(trip.driver_advance), technical: true },
    { label: t("tripManagement.form.totalExpense"), value: formatAmount(trip.total_expense), technical: true },
    { label: t("tripManagement.form.receivedAmount"), value: formatAmount(trip.received_amount), technical: true },
    { label: t("tripManagement.form.paymentBalance"), value: formatAmount(trip.payment_balance), technical: true },
    { label: t("tripManagement.cards.netProfit"), value: formatAmount(trip.net_profit), technical: true },
    { label: t("common.status"), value: t(tripStatusTranslationKey(trip.trip_status)) },
    { label: t("tripManagement.form.startDate"), value: formatDate(trip.start_date), technical: true },
    { label: t("tripManagement.form.completionDate"), value: formatDate(trip.completion_date), technical: true },
    { label: t("common.remarks"), value: displayValue(trip.remarks) },
    { label: t("tripManagement.details.createdAt"), value: formatDateTime(trip.created_at), technical: true },
  ];

  return (
    <div dir={dir} className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div role="dialog" aria-modal="true" aria-labelledby="trip-details-title" className="max-h-[90vh] w-full max-w-5xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 shadow-2xl sm:p-6">
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h2 id="trip-details-title" className="text-2xl font-bold text-gray-900">
              {t("tripManagement.details.title")}
            </h2>
            <p className="mt-1 text-sm font-medium text-gray-900">
              {t("tripManagement.details.completeRecord")}{" "}
              <span dir="ltr">{trip.trip_no}</span>.
            </p>
          </div>

          <button
            ref={closeButtonRef}
            type="button"
            onClick={onClose}
            className="rounded-lg bg-gray-900 px-4 py-2 text-sm font-bold text-white hover:bg-black"
          >
            {t("common.actions.close")}
          </button>
        </div>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {details.map((detail) => (
            <div
              key={detail.label}
              className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm"
            >
              <p className="text-xs font-extrabold uppercase text-gray-900">
                {detail.label}
              </p>
              <p
                className="mt-2 break-words text-base font-bold text-gray-900"
                dir={detail.technical ? "ltr" : undefined}
              >
                {detail.value}
              </p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

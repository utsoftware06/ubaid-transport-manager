"use client";

import { useEffect, useState } from "react";
import {
  TRIP_STATUSES,
  type BookingOption,
  type DriverOption,
  type TripPayload,
  type TripRecord,
  type TripStatus,
  type VehicleOption,
  formatAmount,
  tripStatusTranslationKey,
} from "./TripManagement";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  vehicles: VehicleOption[];
  drivers: DriverOption[];
  bookings: BookingOption[];
  selectedTrip: TripRecord | null;
  saving: boolean;
  error: string;
  onCreate: (payload: TripPayload) => Promise<boolean>;
  onUpdate: (id: string, payload: TripPayload) => Promise<boolean>;
  onCancel: () => void;
};

type FormErrors = {
  tripNo?: string;
  tripDate?: string;
  vehicleId?: string;
  loadingFrom?: string;
  deliveryTo?: string;
  tripStatus?: string;
  amounts?: string;
  dates?: string;
};

function toNumber(value: string) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function nullableText(value: string) {
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

export default function TripForm({
  vehicles,
  drivers,
  bookings,
  selectedTrip,
  saving,
  error,
  onCreate,
  onUpdate,
  onCancel,
}: Props) {
  const { t, dir } = useLanguage();
  const [tripNo, setTripNo] = useState("");
  const [tripDate, setTripDate] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [driverId, setDriverId] = useState("");
  const [bookingId, setBookingId] = useState("");
  const [customerName, setCustomerName] = useState("");
  const [customerPhone, setCustomerPhone] = useState("");
  const [loadingFrom, setLoadingFrom] = useState("");
  const [deliveryTo, setDeliveryTo] = useState("");
  const [goodsDescription, setGoodsDescription] = useState("");
  const [freightAmount, setFreightAmount] = useState("0");
  const [customerAdvance, setCustomerAdvance] = useState("0");
  const [driverAdvance, setDriverAdvance] = useState("0");
  const [totalExpense, setTotalExpense] = useState("0");
  const [receivedAmount, setReceivedAmount] = useState("0");
  const [tripStatus, setTripStatus] = useState<TripStatus>("Planned");
  const [startDate, setStartDate] = useState("");
  const [completionDate, setCompletionDate] = useState("");
  const [remarks, setRemarks] = useState("");
  const [formErrors, setFormErrors] = useState<FormErrors>({});

  const isEditing = Boolean(selectedTrip);
  const freight = toNumber(freightAmount);
  const expense = toNumber(totalExpense);
  const received = toNumber(receivedAmount);
  const paymentBalance = freight - received;
  const estimatedProfit = freight - expense;

  useEffect(() => {
    const syncTimer = window.setTimeout(() => {
      if (!selectedTrip) {
        resetForm();
        return;
      }

      setTripNo(selectedTrip.trip_no);
      setTripDate(selectedTrip.trip_date);
      setVehicleId(selectedTrip.vehicle_id);
      setDriverId(selectedTrip.driver_id ?? "");
      setBookingId(selectedTrip.booking_id ?? "");
      setCustomerName(selectedTrip.customer_name ?? "");
      setCustomerPhone(selectedTrip.customer_phone ?? "");
      setLoadingFrom(selectedTrip.loading_from);
      setDeliveryTo(selectedTrip.delivery_to);
      setGoodsDescription(selectedTrip.goods_description ?? "");
      setFreightAmount(String(selectedTrip.freight_amount));
      setCustomerAdvance(String(selectedTrip.customer_advance));
      setDriverAdvance(String(selectedTrip.driver_advance));
      setTotalExpense(String(selectedTrip.total_expense));
      setReceivedAmount(String(selectedTrip.received_amount));
      setTripStatus(selectedTrip.trip_status);
      setStartDate(selectedTrip.start_date ?? "");
      setCompletionDate(selectedTrip.completion_date ?? "");
      setRemarks(selectedTrip.remarks ?? "");
      setFormErrors({});
    }, 0);

    return () => window.clearTimeout(syncTimer);
  }, [selectedTrip]);

  function resetForm() {
    setTripNo("");
    setTripDate("");
    setVehicleId("");
    setDriverId("");
    setBookingId("");
    setCustomerName("");
    setCustomerPhone("");
    setLoadingFrom("");
    setDeliveryTo("");
    setGoodsDescription("");
    setFreightAmount("0");
    setCustomerAdvance("0");
    setDriverAdvance("0");
    setTotalExpense("0");
    setReceivedAmount("0");
    setTripStatus("Planned");
    setStartDate("");
    setCompletionDate("");
    setRemarks("");
    setFormErrors({});
  }

  function handleBookingChange(value: string) {
    setBookingId(value);

    const booking = bookings.find((item) => item.id === value);

    if (!booking) {
      setCustomerName("");
      setCustomerPhone("");
      setLoadingFrom("");
      setDeliveryTo("");
      setGoodsDescription("");
      setFreightAmount("0");
      return;
    }

    setCustomerName(booking.customerName);
    setCustomerPhone(booking.customerPhone);
    setLoadingFrom(booking.loadingFrom);
    setDeliveryTo(booking.deliveryTo);
    setGoodsDescription(booking.goodsDescription);
    setFreightAmount(String(booking.freightAmount));
  }

  function validateForm() {
    const nextErrors: FormErrors = {};
    const customerAdvanceValue = toNumber(customerAdvance);
    const receivedValue = toNumber(receivedAmount);
    const amounts = [
      freightAmount,
      customerAdvance,
      driverAdvance,
      totalExpense,
      receivedAmount,
    ].map(toNumber);

    if (!tripNo.trim()) nextErrors.tripNo = t("tripManagement.validation.tripNumberRequired");
    if (!tripDate) nextErrors.tripDate = t("tripManagement.validation.tripDateRequired");
    if (!vehicleId) nextErrors.vehicleId = t("tripManagement.validation.vehicleRequired");
    if (!loadingFrom.trim()) nextErrors.loadingFrom = t("tripManagement.validation.loadingFromRequired");
    if (!deliveryTo.trim()) nextErrors.deliveryTo = t("tripManagement.validation.deliveryToRequired");
    if (!tripStatus) nextErrors.tripStatus = t("tripManagement.validation.statusRequired");

    if (amounts.some((value) => value < 0)) {
      nextErrors.amounts = t("tripManagement.validation.amountsNonNegative");
    }

    if (customerAdvanceValue > freight) {
      nextErrors.amounts = t("tripManagement.validation.customerAdvanceLimit");
    }

    if (receivedValue > freight) {
      nextErrors.amounts = t("tripManagement.validation.receivedLimit");
    }

    if (startDate && completionDate && completionDate < startDate) {
      nextErrors.dates = t("tripManagement.validation.completionDate");
    }

    setFormErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  }

  function buildPayload(): TripPayload {
    return {
      vehicle_id: vehicleId,
      driver_id: driverId || null,
      booking_id: bookingId || null,
      trip_no: tripNo.trim(),
      trip_date: tripDate,
      customer_name: nullableText(customerName),
      customer_phone: nullableText(customerPhone),
      loading_from: loadingFrom.trim(),
      delivery_to: deliveryTo.trim(),
      goods_description: nullableText(goodsDescription),
      freight_amount: toNumber(freightAmount),
      customer_advance: toNumber(customerAdvance),
      driver_advance: toNumber(driverAdvance),
      total_expense: toNumber(totalExpense),
      received_amount: toNumber(receivedAmount),
      trip_status: tripStatus,
      start_date: startDate || null,
      completion_date: completionDate || null,
      remarks: nullableText(remarks),
    };
  }

  async function handleSubmit() {
    if (!validateForm()) return;

    const success =
      selectedTrip && isEditing
        ? await onUpdate(selectedTrip.id, buildPayload())
        : await onCreate(buildPayload());

    if (success) resetForm();
  }

  function handleCancel() {
    resetForm();
    onCancel();
  }

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {isEditing
            ? t("tripManagement.form.editTitle")
            : t("tripManagement.form.createTitle")}
        </h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          {t("tripManagement.form.description")}
        </p>
      </div>

      {error && (
        <div className="mb-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
        <Field label={t("tripManagement.form.tripNumber")} error={formErrors.tripNo}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.tripNumber")} value={tripNo} onValueChange={setTripNo} mode="identifier" contextKey={selectedTrip?.id ?? "new"}>
          <input
            dir="ltr"
            value={tripNo}
            onChange={(event) => setTripNo(event.target.value)}
            disabled={saving}
            className="input"
          />
          </VoiceTypingField>
        </Field>

        <Field label={t("tripManagement.form.tripDate")} error={formErrors.tripDate}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.tripDate")} mode="date" contextKey={selectedTrip?.id ?? "new"}>
          <input
            type="date"
            dir="ltr"
            value={tripDate}
            onChange={(event) => setTripDate(event.target.value)}
            disabled={saving}
            className="input"
          />
          </VoiceTypingField>
        </Field>

        <Field label={t("common.vehicle")} error={formErrors.vehicleId}>
          <select
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            disabled={saving}
            className="input"
          >
            <option value="">{t("tripManagement.form.selectVehicle")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo} -{" "}
                {vehicle.ownerName || t("tripManagement.filters.noOwner")}
              </option>
            ))}
          </select>
        </Field>

        <Field label={t("common.driver")}>
          <select
            value={driverId}
            onChange={(event) => setDriverId(event.target.value)}
            disabled={saving}
            className="input"
          >
            <option value="">{t("tripManagement.form.selectDriver")}</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
              </option>
            ))}
          </select>
        </Field>

        <Field label={t("common.booking")}>
          <select
            value={bookingId}
            onChange={(event) => handleBookingChange(event.target.value)}
            disabled={saving}
            className="input"
          >
            <option value="">{t("tripManagement.form.selectBooking")}</option>
            {bookings.map((booking) => (
              <option key={booking.id} value={booking.id}>
                {booking.customerName} - {booking.loadingFrom}{" "}
                {t("tripManagement.form.to")}{" "}
                {booking.deliveryTo} - {formatAmount(booking.freightAmount)}
              </option>
            ))}
          </select>
        </Field>

        <Field label={t("tripManagement.form.customerName")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.customerName")} value={customerName} onValueChange={setCustomerName} contextKey={selectedTrip?.id ?? "new"}>
          <input
            value={customerName}
            onChange={(event) => setCustomerName(event.target.value)}
            disabled={saving}
            className="input"
          />
          </VoiceTypingField>
        </Field>


        <Field label={t("tripManagement.form.customerPhone")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.customerPhone")} mode="phone" contextKey={selectedTrip?.id ?? "new"}><input
            dir="ltr"
            value={customerPhone}
            onChange={(event) => setCustomerPhone(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.loadingFrom")} error={formErrors.loadingFrom}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.loadingFrom")} mode="text" contextKey={selectedTrip?.id ?? "new"}><input
            value={loadingFrom}
            onChange={(event) => setLoadingFrom(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.deliveryTo")} error={formErrors.deliveryTo}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.deliveryTo")} mode="text" contextKey={selectedTrip?.id ?? "new"}><input
            value={deliveryTo}
            onChange={(event) => setDeliveryTo(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.freightAmount")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.freightAmount")} mode="amount" contextKey={selectedTrip?.id ?? "new"}><input
            type="number"
            dir="ltr"
            min="0"
            value={freightAmount}
            onChange={(event) => setFreightAmount(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.customerAdvance")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.customerAdvance")} mode="amount" contextKey={selectedTrip?.id ?? "new"}><input
            type="number"
            dir="ltr"
            min="0"
            value={customerAdvance}
            onChange={(event) => setCustomerAdvance(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.driverAdvance")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.driverAdvance")} mode="amount" contextKey={selectedTrip?.id ?? "new"}><input
            type="number"
            dir="ltr"
            min="0"
            value={driverAdvance}
            onChange={(event) => setDriverAdvance(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.totalExpense")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.totalExpense")} mode="amount" contextKey={selectedTrip?.id ?? "new"}><input
            type="number"
            dir="ltr"
            min="0"
            value={totalExpense}
            onChange={(event) => setTotalExpense(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.receivedAmount")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.receivedAmount")} mode="amount" contextKey={selectedTrip?.id ?? "new"}><input
            type="number"
            dir="ltr"
            min="0"
            value={receivedAmount}
            onChange={(event) => setReceivedAmount(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>


        <Field label={t("tripManagement.form.tripStatus")} error={formErrors.tripStatus}>
          <select
            value={tripStatus}
            onChange={(event) => setTripStatus(event.target.value as TripStatus)}
            disabled={saving}
            className="input"
          >
            {TRIP_STATUSES.map((status) => (
              <option key={status} value={status}>
                {t(tripStatusTranslationKey(status))}
              </option>
            ))}
          </select>
        </Field>


        <Field label={t("tripManagement.form.startDate")} error={formErrors.dates}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.startDate")} mode="date" contextKey={selectedTrip?.id ?? "new"}><input
            type="date"
            dir="ltr"
            value={startDate}
            onChange={(event) => setStartDate(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>



        <Field label={t("tripManagement.form.completionDate")}>
          <VoiceTypingField fieldLabel={t("tripManagement.form.completionDate")} mode="date" contextKey={selectedTrip?.id ?? "new"}><input
            type="date"
            dir="ltr"
            value={completionDate}
            onChange={(event) => setCompletionDate(event.target.value)}
            disabled={saving}
            className="input"
          /></VoiceTypingField>
        </Field>


        <div className="lg:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("tripManagement.form.goodsDescription")}
          </label>
          <VoiceTypingField fieldLabel={t("tripManagement.form.goodsDescription")} value={goodsDescription} onValueChange={setGoodsDescription} contextKey={selectedTrip?.id ?? "new"}>
          <textarea
            aria-label={t("tripManagement.form.goodsDescription")}
            value={goodsDescription}
            onChange={(event) => setGoodsDescription(event.target.value)}
            disabled={saving}
            rows={3}
            className="input resize-none"
          />
          </VoiceTypingField>
        </div>

        <div className="lg:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.remarks")}
          </label>
          <VoiceTypingField fieldLabel={t("common.remarks")} value={remarks} onValueChange={setRemarks} contextKey={selectedTrip?.id ?? "new"}>
          <textarea
            aria-label={t("common.remarks")}
            value={remarks}
            onChange={(event) => setRemarks(event.target.value)}
            disabled={saving}
            rows={3}
            className="input resize-none"
          />
          </VoiceTypingField>
        </div>
      </div>

      {formErrors.amounts && (
        <p className="mt-4 text-sm font-bold text-red-700">
          {formErrors.amounts}
        </p>
      )}

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-5">
          <p className="text-sm font-bold text-gray-900">
            {t("tripManagement.form.paymentBalance")}
          </p>
          <p className="mt-2 text-2xl font-extrabold text-amber-700" dir="ltr">
            {formatAmount(paymentBalance)}
          </p>
        </div>

        <div
          className={`rounded-xl border p-5 ${
            estimatedProfit >= 0
              ? "border-green-200 bg-green-50"
              : "border-red-200 bg-red-50"
          }`}
        >
          <p className="text-sm font-bold text-gray-900">
            {t("tripManagement.form.estimatedProfit")}
          </p>
          <p
            dir="ltr"
            className={`mt-2 text-2xl font-extrabold ${
              estimatedProfit >= 0 ? "text-green-700" : "text-red-700"
            }`}
          >
            {formatAmount(estimatedProfit)}
          </p>
        </div>
      </div>

      <div className="mt-8 flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          onClick={handleSubmit}
          disabled={saving}
          className="rounded-lg bg-blue-600 px-8 py-3 font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {saving
            ? t("common.saving")
            : isEditing
              ? t("tripManagement.form.updateTrip")
              : t("tripManagement.form.saveTrip")}
        </button>

        {isEditing && (
          <button
            type="button"
            onClick={handleCancel}
            disabled={saving}
            className="rounded-lg border border-gray-300 bg-white px-8 py-3 font-bold text-gray-900 hover:bg-gray-100 disabled:cursor-not-allowed"
          >
            {t("common.actions.cancel")}
          </button>
        )}
      </div>

      <style jsx>{`
        .input {
          width: 100%;
          border-radius: 0.5rem;
          border: 1px solid #d1d5db;
          background: #ffffff;
          padding: 0.75rem;
          font-weight: 500;
          color: #111827;
          outline: none;
        }

        .input:focus {
          border-color: #2563eb;
          box-shadow: 0 0 0 2px #dbeafe;
        }

        .input:disabled {
          cursor: not-allowed;
        }
      `}</style>
    </section>
  );
}

function Field({
  label,
  error,
  children,
}: {
  label: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="block">
        <span className="mb-2 block text-sm font-bold text-gray-900">
          {label}
        </span>
        {children}
      </label>
      {error && <p className="mt-2 text-sm font-bold text-red-700">{error}</p>}
    </div>
  );
}

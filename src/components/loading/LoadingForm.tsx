import type {
  LoadingBooking as Booking,
  LoadingDriver as Driver,
  LoadingVehicle as Vehicle,
} from "@/types/loading";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type LoadingFormProps = {
  loadingNo: string;
  setLoadingNo: (value: string) => void;
  loadingDate: string;
  setLoadingDate: (value: string) => void;
  bookingId: string;
  setBookingId: (value: string) => void;
  bookings: Booking[];
  vehicleId: string;
  setVehicleId: (value: string) => void;
  driverId: string;
  setDriverId: (value: string) => void;
  route: string;
  setRoute: (value: string) => void;
  advanceAmount: string;
  setAdvanceAmount: (value: string) => void;
  vehicles: Vehicle[];
  drivers: Driver[];
  onSave: () => void;
  isSaving?: boolean;
  isEditing?: boolean;
  onCancelEdit?: () => void;
};

function formatAmount(value: number): string {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK")}`;
}

export default function LoadingForm({
  loadingNo,
  setLoadingNo,
  loadingDate,
  setLoadingDate,
  bookingId,
  setBookingId,
  bookings,
  vehicleId,
  setVehicleId,
  driverId,
  setDriverId,
  route,
  setRoute,
  advanceAmount,
  setAdvanceAmount,
  vehicles,
  drivers,
  onSave,
  isSaving = false,
  isEditing = false,
  onCancelEdit,
}: LoadingFormProps) {
  const { t, dir } = useLanguage();
  const selectedBooking = bookings.find((booking) => booking.id === bookingId);
  const totalFreight = Number(selectedBooking?.freight ?? 0);
  const advance = Number(advanceAmount || 0);
  const remainingAmount = Math.max(totalFreight - advance, 0);

  const paymentStatus =
    advance <= 0 ? "Unpaid" : advance >= totalFreight ? "Paid" : "Partial";

  return (
    <div dir={dir}>
      <div className="mb-8 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-3xl font-bold text-gray-900">
            {isEditing ? t("loadings.edit") : t("loadings.create")}
          </h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            {t("loadings.formDescription")}
          </p>
        </div>

        {isEditing && onCancelEdit && (
          <button
            type="button"
            onClick={onCancelEdit}
            disabled={isSaving}
            className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-semibold text-gray-900 transition hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            {t("common.cancelEdit")}
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        <div>
          <label
            htmlFor="loading-no"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("loadings.loadingNumber")}
          </label>
          <VoiceTypingField fieldLabel={t("loadings.loadingNumber")} mode="identifier" contextKey={bookingId}>
          <input
            id="loading-no"
            type="text"
            placeholder={t("loadings.loadingNumber")}
            dir="ltr"
            value={loadingNo}
            onChange={(event) => setLoadingNo(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          />
          </VoiceTypingField>
        </div>


        <div>
          <label
            htmlFor="loading-date"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("loadings.loadingDate")}
          </label>
          <VoiceTypingField fieldLabel={t("loadings.loadingDate")} mode="date" contextKey={bookingId}><input
            id="loading-date"
            type="date"
            dir="ltr"
            value={loadingDate}
            onChange={(event) => setLoadingDate(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          /></VoiceTypingField>
        </div>


        <div className="md:col-span-2">
          <label
            htmlFor="booking"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("common.booking")}
          </label>
          <select
            id="booking"
            value={bookingId}
            onChange={(event) => setBookingId(event.target.value)}
            disabled={isSaving}
            required
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            <option value="">{t("loadings.selectBooking")}</option>
            {bookings.map((booking) => (
              <option key={booking.id} value={booking.id}>
                {booking.booking_no} -{" "}
                {booking.parties?.name ?? booking.sender_name}{" "}
                {t("loadings.to")}{" "}
                {booking.receiver_name} - Rs.{" "}
                {Number(booking.freight || 0).toLocaleString("en-PK")}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label
            htmlFor="vehicle"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("common.vehicle")}
          </label>
          <select
            id="vehicle"
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            <option value="">{t("loadings.selectVehicle")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicle_no}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label
            htmlFor="driver"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("common.driver")}
          </label>
          <select
            id="driver"
            value={driverId}
            onChange={(event) => setDriverId(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            <option value="">{t("loadings.selectDriver")}</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
              </option>
            ))}
          </select>
        </div>


        <div className="md:col-span-2">
          <label
            htmlFor="route"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("common.route")}
          </label>
          <VoiceTypingField fieldLabel={t("common.route")} mode="text" contextKey={bookingId}><input
            id="route"
            type="text"
            placeholder={t("common.route")}
            value={route}
            onChange={(event) => setRoute(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          /></VoiceTypingField>
        </div>


        <div className="rounded-xl border border-gray-200 bg-blue-50 p-5 md:col-span-2">
          <h3 className="mb-4 text-xl font-bold text-gray-900">
            {t("loadings.freightPayment")}
          </h3>

          <div className="grid grid-cols-1 gap-5 md:grid-cols-4">
            <div>
              <p className="mb-2 block text-sm font-bold text-gray-900">
                {t("loadings.totalFreight")}
              </p>
              <div className="rounded-lg border border-gray-300 bg-white p-3 font-bold text-gray-900" dir="ltr">
                {formatAmount(totalFreight)}
              </div>
            </div>


            <div>
              <label
                htmlFor="advance-amount"
                className="mb-2 block text-sm font-bold text-gray-900"
              >
                {t("loadings.advanceAmount")}
              </label>
              <VoiceTypingField fieldLabel={t("loadings.advanceAmount")} mode="amount"><input
                id="advance-amount"
                type="number"
                dir="ltr"
                min="0"
                placeholder="0"
                value={advanceAmount}
                onChange={(event) => setAdvanceAmount(event.target.value)}
                disabled={isSaving || !bookingId}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
              /></VoiceTypingField>
            </div>


            <div>
              <p className="mb-2 block text-sm font-bold text-gray-900">
                {t("loadings.remaining")}
              </p>
              <div className="rounded-lg border border-gray-300 bg-white p-3 font-bold text-gray-900" dir="ltr">
                {formatAmount(remainingAmount)}
              </div>
            </div>

            <div>
              <p className="mb-2 block text-sm font-bold text-gray-900">
                {t("common.status")}
              </p>
              <div
                className={`rounded-lg border p-3 font-bold ${
                  paymentStatus === "Paid"
                    ? "border-green-200 bg-green-100 text-green-700"
                    : paymentStatus === "Partial"
                      ? "border-yellow-200 bg-yellow-100 text-yellow-800"
                      : "border-red-200 bg-red-100 text-red-700"
                }`}
              >
                {t(`loadings.paymentStatus.${paymentStatus.toLowerCase()}`)}
              </div>
            </div>
          </div>
        </div>
      </div>

      <button
        type="button"
        onClick={onSave}
        disabled={isSaving}
        className="mt-8 rounded-lg bg-blue-600 px-8 py-3 font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
      >
        {isSaving
          ? t("common.saving")
          : isEditing
            ? t("loadings.update")
            : t("loadings.saveAndNext")}
      </button>
    </div>
  );
}

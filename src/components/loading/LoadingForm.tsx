type Booking = {
  id: string;
  booking_no: string;
  sender_name: string;
  receiver_name: string;
  freight: number;
};

type Vehicle = {
  id: string;
  vehicle_no: string;
};

type Driver = {
  id: string;
  name: string;
};

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
  const selectedBooking = bookings.find((booking) => booking.id === bookingId);
  const totalFreight = Number(selectedBooking?.freight ?? 0);
  const advance = Number(advanceAmount || 0);
  const remainingAmount = Math.max(totalFreight - advance, 0);

  const paymentStatus =
    advance <= 0 ? "Unpaid" : advance >= totalFreight ? "Paid" : "Partial";

  return (
    <div>
      <div className="mb-8 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-3xl font-bold text-gray-900">
            {isEditing ? "Edit Loading" : "Create New Loading"}
          </h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            Link a booking and enter loading, vehicle, driver, route and freight
            payment details.
          </p>
        </div>

        {isEditing && onCancelEdit && (
          <button
            type="button"
            onClick={onCancelEdit}
            disabled={isSaving}
            className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-semibold text-gray-900 transition hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            Cancel Edit
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        <div>
          <label
            htmlFor="loading-no"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            Loading Number
          </label>
          <input
            id="loading-no"
            type="text"
            placeholder="Loading Number"
            value={loadingNo}
            onChange={(event) => setLoadingNo(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          />
        </div>

        <div>
          <label
            htmlFor="loading-date"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            Loading Date
          </label>
          <input
            id="loading-date"
            type="date"
            value={loadingDate}
            onChange={(event) => setLoadingDate(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          />
        </div>

        <div className="md:col-span-2">
          <label
            htmlFor="booking"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            Booking
          </label>
          <select
            id="booking"
            value={bookingId}
            onChange={(event) => setBookingId(event.target.value)}
            disabled={isSaving}
            required
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            <option value="">Select Booking</option>
            {bookings.map((booking) => (
              <option key={booking.id} value={booking.id}>
                {booking.booking_no} - {booking.sender_name} to{" "}
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
            Vehicle
          </label>
          <select
            id="vehicle"
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            <option value="">Select Vehicle</option>
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
            Driver
          </label>
          <select
            id="driver"
            value={driverId}
            onChange={(event) => setDriverId(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          >
            <option value="">Select Driver</option>
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
            Route
          </label>
          <input
            id="route"
            type="text"
            placeholder="Route"
            value={route}
            onChange={(event) => setRoute(event.target.value)}
            disabled={isSaving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
          />
        </div>

        <div className="rounded-xl border border-gray-200 bg-blue-50 p-5 md:col-span-2">
          <h3 className="mb-4 text-xl font-bold text-gray-900">
            Freight Payment
          </h3>

          <div className="grid grid-cols-1 gap-5 md:grid-cols-4">
            <div>
              <p className="mb-2 block text-sm font-bold text-gray-900">
                Total Freight
              </p>
              <div className="rounded-lg border border-gray-300 bg-white p-3 font-bold text-gray-900">
                {formatAmount(totalFreight)}
              </div>
            </div>

            <div>
              <label
                htmlFor="advance-amount"
                className="mb-2 block text-sm font-bold text-gray-900"
              >
                Advance Amount
              </label>
              <input
                id="advance-amount"
                type="number"
                min="0"
                placeholder="0"
                value={advanceAmount}
                onChange={(event) => setAdvanceAmount(event.target.value)}
                disabled={isSaving || !bookingId}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
              />
            </div>

            <div>
              <p className="mb-2 block text-sm font-bold text-gray-900">
                Remaining
              </p>
              <div className="rounded-lg border border-gray-300 bg-white p-3 font-bold text-gray-900">
                {formatAmount(remainingAmount)}
              </div>
            </div>

            <div>
              <p className="mb-2 block text-sm font-bold text-gray-900">
                Status
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
                {paymentStatus}
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
          ? "Saving..."
          : isEditing
            ? "Update Loading"
            : "Save & Next"}
      </button>
    </div>
  );
}
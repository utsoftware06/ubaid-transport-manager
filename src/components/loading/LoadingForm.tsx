type Vehicle = {
  id: number;
  vehicle_no: string;
};

type Driver = {
  id: number;
  name: string;
};

type LoadingFormProps = {
  loadingNo: string;
  setLoadingNo: (value: string) => void;
  loadingDate: string;
  setLoadingDate: (value: string) => void;
  vehicleId: string;
  setVehicleId: (value: string) => void;
  driverId: string;
  setDriverId: (value: string) => void;
  route: string;
  setRoute: (value: string) => void;
  vehicles: Vehicle[];
  drivers: Driver[];
  onSave: () => void;
  isSaving?: boolean;
  isEditing?: boolean;
  onCancelEdit?: () => void;
};

export default function LoadingForm({
  loadingNo,
  setLoadingNo,
  loadingDate,
  setLoadingDate,
  vehicleId,
  setVehicleId,
  driverId,
  setDriverId,
  route,
  setRoute,
  vehicles,
  drivers,
  onSave,
  isSaving = false,
  isEditing = false,
  onCancelEdit,
}: LoadingFormProps) {
  return (
    <div>
      <div className="mb-8 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-3xl font-bold text-gray-900">
            {isEditing ? "Edit Loading" : "Create New Loading"}
          </h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            Enter loading details and continue to add goods.
          </p>
        </div>

        {isEditing && onCancelEdit && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-semibold text-gray-900 transition hover:bg-gray-50"
          >
            Cancel Edit
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        <input
          type="text"
          placeholder="Loading Number"
          value={loadingNo}
          onChange={(event) => setLoadingNo(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        />

        <input
          type="date"
          value={loadingDate}
          onChange={(event) => setLoadingDate(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        />

        <select
          value={vehicleId}
          onChange={(event) => setVehicleId(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        >
          <option value="">Select Vehicle</option>
          {vehicles.map((vehicle) => (
            <option key={vehicle.id} value={vehicle.id}>
              {vehicle.vehicle_no}
            </option>
          ))}
        </select>

        <select
          value={driverId}
          onChange={(event) => setDriverId(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        >
          <option value="">Select Driver</option>
          {drivers.map((driver) => (
            <option key={driver.id} value={driver.id}>
              {driver.name}
            </option>
          ))}
        </select>

        <input
          type="text"
          placeholder="Route"
          value={route}
          onChange={(event) => setRoute(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 md:col-span-2"
        />
      </div>

      <button
        type="button"
        onClick={onSave}
        disabled={isSaving}
        className="mt-8 rounded-lg bg-blue-600 px-8 py-3 font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
      >
        {isSaving ? "Saving..." : isEditing ? "Update Loading" : "Save & Next"}
      </button>
    </div>
  );
}
"use client";

type Props = {
  loadingNo: string;
  setLoadingNo: (v: string) => void;

  loadingDate: string;
  setLoadingDate: (v: string) => void;

  vehicleId: string;
  setVehicleId: (v: string) => void;

  driverId: string;
  setDriverId: (v: string) => void;

  route: string;
  setRoute: (v: string) => void;

  vehicles: any[];
  drivers: any[];

  handleSaveLoading: () => void;
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
  handleSaveLoading,
}: Props) {
  return (
    <>
      <h2 className="text-3xl font-bold mb-8 text-gray-900">
        Create New Loading
      </h2>

      <div className="grid grid-cols-2 gap-6">

        <input
          type="text"
          placeholder="Loading Number"
          value={loadingNo}
          onChange={(e) => setLoadingNo(e.target.value)}
          className="border p-3 rounded-lg text-gray-900"
        />

        <input
          type="date"
          value={loadingDate}
          onChange={(e) => setLoadingDate(e.target.value)}
          className="border p-3 rounded-lg text-gray-900"
        />

        <select
          value={vehicleId}
          onChange={(e) => setVehicleId(e.target.value)}
          className="border p-3 rounded-lg text-gray-900"
        >
          <option value="">Select Vehicle</option>

          {vehicles.map((vehicle: any) => (
            <option key={vehicle.id} value={vehicle.id}>
              {vehicle.vehicle_no}
            </option>
          ))}
        </select>

        <select
          value={driverId}
          onChange={(e) => setDriverId(e.target.value)}
          className="border p-3 rounded-lg text-gray-900"
        >
          <option value="">Select Driver</option>

          {drivers.map((driver: any) => (
            <option key={driver.id} value={driver.id}>
              {driver.name}
            </option>
          ))}
        </select>

        <input
          type="text"
          placeholder="Route"
          value={route}
          onChange={(e) => setRoute(e.target.value)}
          className="border p-3 rounded-lg col-span-2 text-gray-900"
        />

      </div>

      <button
        onClick={handleSaveLoading}
        className="mt-8 bg-blue-600 hover:bg-blue-700 text-white px-8 py-3 rounded-lg"
      >
        Save & Next
      </button>
    </>
  );
}
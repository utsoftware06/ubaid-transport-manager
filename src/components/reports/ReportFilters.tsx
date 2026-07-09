export type ReportFilterValues = {
  fromDate: string;
  toDate: string;
  vehicle: string;
  driver: string;
  route: string;
};

type VehicleOption = {
  id: string;
  vehicle_no: string;
};

type DriverOption = {
  id: string;
  name: string;
};

type ReportFiltersProps = {
  filters: ReportFilterValues;
  vehicles: VehicleOption[];
  drivers: DriverOption[];
  onChange: (field: keyof ReportFilterValues, value: string) => void;
  onSearch: () => void;
  onReset: () => void;
};

export default function ReportFilters({
  filters,
  vehicles,
  drivers,
  onChange,
  onSearch,
  onReset,
}: ReportFiltersProps) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md">
      <h2 className="mb-6 text-2xl font-bold text-gray-900">
        Report Filters
      </h2>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label
            htmlFor="report-from-date"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            From Date
          </label>
          <input
            id="report-from-date"
            type="date"
            value={filters.fromDate}
            onChange={(event) => onChange("fromDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label
            htmlFor="report-to-date"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            To Date
          </label>
          <input
            id="report-to-date"
            type="date"
            value={filters.toDate}
            onChange={(event) => onChange("toDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label
            htmlFor="report-vehicle"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            Vehicle
          </label>
          <select
            id="report-vehicle"
            value={filters.vehicle}
            onChange={(event) => onChange("vehicle", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Vehicles</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicle_no}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label
            htmlFor="report-driver"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            Driver
          </label>
          <select
            id="report-driver"
            value={filters.driver}
            onChange={(event) => onChange("driver", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Drivers</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
              </option>
            ))}
          </select>
        </div>

        <div className="md:col-span-2 xl:col-span-2">
          <label
            htmlFor="report-route"
            className="mb-2 block text-sm font-semibold text-gray-900"
          >
            Route
          </label>
          <input
            id="report-route"
            type="text"
            value={filters.route}
            onChange={(event) => onChange("route", event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                onSearch();
              }
            }}
            placeholder="Search Route"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="flex items-end">
          <button
            type="button"
            onClick={onSearch}
            className="w-full rounded-lg bg-blue-600 px-6 py-3 font-semibold text-white transition hover:bg-blue-700"
          >
            Search
          </button>
        </div>

        <div className="flex items-end">
          <button
            type="button"
            onClick={onReset}
            className="w-full rounded-lg bg-gray-600 px-6 py-3 font-semibold text-white transition hover:bg-gray-700"
          >
            Reset
          </button>
        </div>
      </div>
    </div>
  );
}
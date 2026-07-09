"use client";

import type {
  VehicleLedgerFilterValues,
  VehicleFilterType,
} from "./VehicleLedger";

type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

type Props = {
  filters: VehicleLedgerFilterValues;
  setFilters: React.Dispatch<React.SetStateAction<VehicleLedgerFilterValues>>;
  vehicleOptions: VehicleOption[];
};

export default function VehicleLedgerFilters({
  filters,
  setFilters,
  vehicleOptions,
}: Props) {
  function updateFilter(key: keyof VehicleLedgerFilterValues, value: string) {
    setFilters((prev) => ({
      ...prev,
      [key]: value,
    }));
  }

  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-gray-900">Vehicle Filters</h2>
        <p className="mt-1 text-sm font-medium text-gray-700">
          Vehicle, date aur search ke hisaab se ledger filter karein.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-5">
        <select
          value={filters.vehicleId}
          onChange={(event) => updateFilter("vehicleId", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        >
          <option value="">All Vehicles</option>

          {vehicleOptions.map((vehicle) => (
            <option key={vehicle.id} value={vehicle.id}>
              {vehicle.vehicleNo} - {vehicle.ownerName}
            </option>
          ))}
        </select>

        <select
          value={filters.filterType}
          onChange={(event) => {
            const value = event.target.value as VehicleFilterType;

            setFilters((prev) => ({
              ...prev,
              filterType: value,
              fromDate: value === "custom" ? prev.fromDate : "",
              toDate: value === "custom" ? prev.toDate : "",
            }));
          }}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        >
          <option value="all">All Time</option>
          <option value="today">Today</option>
          <option value="week">Last 7 Days</option>
          <option value="month">This Month</option>
          <option value="sixMonths">Last 6 Months</option>
          <option value="year">This Year</option>
          <option value="custom">Custom Date</option>
        </select>

        <input
          type="date"
          value={filters.fromDate}
          disabled={filters.filterType !== "custom"}
          onChange={(event) => updateFilter("fromDate", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
        />

        <input
          type="date"
          value={filters.toDate}
          disabled={filters.filterType !== "custom"}
          onChange={(event) => updateFilter("toDate", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none disabled:bg-white disabled:text-gray-900 disabled:opacity-100"
        />

        <input
          type="text"
          placeholder="Search loading / route / driver"
          value={filters.search}
          onChange={(event) => updateFilter("search", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        />
      </div>
    </section>
  );
}
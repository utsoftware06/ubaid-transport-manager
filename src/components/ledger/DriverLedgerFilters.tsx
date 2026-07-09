"use client";

import {
  DriverLedgerFilterValues,
  DriverOption,
} from "./DriverLedger";

type Props = {
  drivers: DriverOption[];
  filterValues: DriverLedgerFilterValues;
  setFilterValues: React.Dispatch<
    React.SetStateAction<DriverLedgerFilterValues>
  >;
  onSearch: () => void;
  onReset: () => void;
};

export default function DriverLedgerFilters({
  drivers,
  filterValues,
  setFilterValues,
  onSearch,
  onReset,
}: Props) {
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-6">
      <select
        value={filterValues.driverId}
        onChange={(e) =>
          setFilterValues((prev) => ({
            ...prev,
            driverId: e.target.value,
          }))
        }
        className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
      >
        <option value="">All Drivers</option>

        {drivers.map((driver) => (
          <option key={driver.id} value={driver.id}>
            {driver.name}
          </option>
        ))}
      </select>

      <input
        type="date"
        value={filterValues.fromDate}
        onChange={(e) =>
          setFilterValues((prev) => ({
            ...prev,
            fromDate: e.target.value,
          }))
        }
        className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
      />

      <input
        type="date"
        value={filterValues.toDate}
        onChange={(e) =>
          setFilterValues((prev) => ({
            ...prev,
            toDate: e.target.value,
          }))
        }
        className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
      />

      <input
        type="text"
        placeholder="Loading No / Route"
        value={filterValues.search}
        onChange={(e) =>
          setFilterValues((prev) => ({
            ...prev,
            search: e.target.value,
          }))
        }
        className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
      />

      <button
        onClick={onSearch}
        className="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white transition hover:bg-blue-700"
      >
        Search
      </button>

      <button
        onClick={onReset}
        className="rounded-lg bg-gray-600 px-4 py-2 font-semibold text-white transition hover:bg-gray-700"
      >
        Reset
      </button>
    </div>
  );
}
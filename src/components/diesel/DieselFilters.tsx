"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  type DieselFilterValues,
  type PetrolPumpOption,
  type VehicleOption,
} from "./Diesel";

type Props = {
  filters: DieselFilterValues;
  setFilters: Dispatch<SetStateAction<DieselFilterValues>>;
  petrolPumps: PetrolPumpOption[];
  vehicles: VehicleOption[];
  onReset: () => void;
};

function updateFilter<K extends keyof DieselFilterValues>(
  setFilters: Dispatch<SetStateAction<DieselFilterValues>>,
  key: K,
  value: DieselFilterValues[K]
) {
  setFilters((previous) => ({
    ...previous,
    [key]: value,
  }));
}

export default function DieselFilters({
  filters,
  setFilters,
  petrolPumps,
  vehicles,
  onReset,
}: Props) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">Diesel Filters</h2>
        <p className="mt-1 text-sm font-semibold text-gray-900">
          Filter diesel records by date, pump, vehicle and payment status.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            From Date
          </label>
          <input
            type="date"
            value={filters.fromDate}
            onChange={(event) =>
              updateFilter(setFilters, "fromDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            To Date
          </label>
          <input
            type="date"
            value={filters.toDate}
            onChange={(event) =>
              updateFilter(setFilters, "toDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Petrol Pump
          </label>
          <select
            value={filters.petrolPumpId}
            onChange={(event) =>
              updateFilter(setFilters, "petrolPumpId", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Pumps</option>
            {petrolPumps.map((pump) => (
              <option key={pump.id} value={pump.id}>
                {pump.pumpName}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Vehicle
          </label>
          <select
            value={filters.vehicleId}
            onChange={(event) =>
              updateFilter(setFilters, "vehicleId", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Vehicles</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Status
          </label>
          <select
            value={filters.paymentStatus}
            onChange={(event) =>
              updateFilter(setFilters, "paymentStatus", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All</option>
            <option value="Paid">Paid</option>
            <option value="Partial">Partial</option>
            <option value="Unpaid">Unpaid</option>
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Search
          </label>
          <input
            type="text"
            value={filters.search}
            onChange={(event) =>
              updateFilter(setFilters, "search", event.target.value)
            }
            placeholder="Search diesel..."
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      <div className="mt-5 flex justify-end">
        <button
          type="button"
          onClick={onReset}
          className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
        >
          Reset
        </button>
      </div>
    </div>
  );
}
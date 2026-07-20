"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  TRIP_STATUSES,
  type DriverOption,
  type TripDateFilter,
  type VehicleOption,
} from "./TripManagement";

type Props = {
  search: string;
  setSearch: Dispatch<SetStateAction<string>>;
  vehicles: VehicleOption[];
  selectedVehicle: string;
  setSelectedVehicle: Dispatch<SetStateAction<string>>;
  drivers: DriverOption[];
  selectedDriver: string;
  setSelectedDriver: Dispatch<SetStateAction<string>>;
  selectedStatus: string;
  setSelectedStatus: Dispatch<SetStateAction<string>>;
  selectedTripDateFilter: TripDateFilter;
  setSelectedTripDateFilter: Dispatch<SetStateAction<TripDateFilter>>;
  customFromDate: string;
  setCustomFromDate: Dispatch<SetStateAction<string>>;
  customToDate: string;
  setCustomToDate: Dispatch<SetStateAction<string>>;
  onReset: () => void;
};

const dateFilters: { value: TripDateFilter; label: string }[] = [
  { value: "all", label: "All Time" },
  { value: "today", label: "Today" },
  { value: "last7Days", label: "Last 7 Days" },
  { value: "thisMonth", label: "This Month" },
  { value: "last6Months", label: "Last 6 Months" },
  { value: "thisYear", label: "This Year" },
  { value: "custom", label: "Custom" },
];

export default function TripFilters({
  search,
  setSearch,
  vehicles,
  selectedVehicle,
  setSelectedVehicle,
  drivers,
  selectedDriver,
  setSelectedDriver,
  selectedStatus,
  setSelectedStatus,
  selectedTripDateFilter,
  setSelectedTripDateFilter,
  customFromDate,
  setCustomFromDate,
  customToDate,
  setCustomToDate,
  onReset,
}: Props) {
  return (
    <section className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <h2 className="text-2xl font-bold text-gray-900">Trip Filters</h2>

      <div className="mt-6 grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-5">
        <div className="xl:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Search
          </label>
          <input
            type="text"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search trip no, vehicle, driver, customer or route..."
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Vehicle
          </label>
          <select
            value={selectedVehicle}
            onChange={(event) => setSelectedVehicle(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Vehicles</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo} - {vehicle.ownerName || "No Owner"}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Driver
          </label>
          <select
            value={selectedDriver}
            onChange={(event) => setSelectedDriver(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Drivers</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Trip Status
          </label>
          <select
            value={selectedStatus}
            onChange={(event) => setSelectedStatus(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Status</option>
            {TRIP_STATUSES.map((status) => (
              <option key={status} value={status}>
                {status}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Date Filter
          </label>
          <select
            value={selectedTripDateFilter}
            onChange={(event) =>
              setSelectedTripDateFilter(event.target.value as TripDateFilter)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {dateFilters.map((filter) => (
              <option key={filter.value} value={filter.value}>
                {filter.label}
              </option>
            ))}
          </select>
        </div>

        {selectedTripDateFilter === "custom" && (
          <>
            <div>
              <label className="mb-2 block text-sm font-bold text-gray-900">
                From Date
              </label>
              <input
                type="date"
                value={customFromDate}
                onChange={(event) => setCustomFromDate(event.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </div>

            <div>
              <label className="mb-2 block text-sm font-bold text-gray-900">
                To Date
              </label>
              <input
                type="date"
                value={customToDate}
                onChange={(event) => setCustomToDate(event.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </>
        )}
      </div>

      <div className="mt-6">
        <button
          type="button"
          onClick={onReset}
          className="rounded-lg bg-gray-800 px-6 py-3 font-bold text-white hover:bg-gray-900"
        >
          Reset Filters
        </button>
      </div>
    </section>
  );
}
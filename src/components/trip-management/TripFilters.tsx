"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  TRIP_STATUSES,
  tripStatusTranslationKey,
  type DriverOption,
  type TripDateFilter,
  type VehicleOption,
} from "./TripManagement";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

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

const dateFilters: { value: TripDateFilter; key: string }[] = [
  { value: "all", key: "allTime" },
  { value: "today", key: "today" },
  { value: "last7Days", key: "last7Days" },
  { value: "thisMonth", key: "thisMonth" },
  { value: "last6Months", key: "last6Months" },
  { value: "thisYear", key: "thisYear" },
  { value: "custom", key: "custom" },
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
  const { t, dir } = useLanguage();
  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <h2 className="text-2xl font-bold text-gray-900">
        {t("tripManagement.filters.title")}
      </h2>

      <div className="mt-6 grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-5">

        <div className="xl:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("tripManagement.filters.search")}
          </label>
          <VoiceTypingField fieldLabel={t("tripManagement.filters.searchPlaceholder")} mode="text"><input
            type="text"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder={t("tripManagement.filters.searchPlaceholder")}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.vehicle")}
          </label>
          <select
            value={selectedVehicle}
            onChange={(event) => setSelectedVehicle(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("tripManagement.filters.allVehicles")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo} -{" "}
                {vehicle.ownerName || t("tripManagement.filters.noOwner")}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.driver")}
          </label>
          <select
            value={selectedDriver}
            onChange={(event) => setSelectedDriver(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("tripManagement.filters.allDrivers")}</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("tripManagement.filters.tripStatus")}
          </label>
          <select
            value={selectedStatus}
            onChange={(event) => setSelectedStatus(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("tripManagement.filters.allStatuses")}</option>
            {TRIP_STATUSES.map((status) => (
              <option key={status} value={status}>
                {t(tripStatusTranslationKey(status))}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("tripManagement.filters.dateFilter")}
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
                {t(`common.dateFilters.${filter.key}`)}
              </option>
            ))}
          </select>
        </div>

        {selectedTripDateFilter === "custom" && (
          <>

            <div>
              <label className="mb-2 block text-sm font-bold text-gray-900">
                {t("common.fromDate")}
              </label>
              <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input
                type="date"
                dir="ltr"
                value={customFromDate}
                onChange={(event) => setCustomFromDate(event.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              /></VoiceTypingField>
            </div>



            <div>
              <label className="mb-2 block text-sm font-bold text-gray-900">
                {t("common.toDate")}
              </label>
              <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input
                type="date"
                dir="ltr"
                value={customToDate}
                onChange={(event) => setCustomToDate(event.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              /></VoiceTypingField>
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
          {t("tripManagement.filters.reset")}
        </button>
      </div>
    </section>
  );
}

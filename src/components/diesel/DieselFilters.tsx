"use client";

import type { Dispatch, SetStateAction } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import {
  type DieselFilterValues,
  type PetrolPumpOption,
  type VehicleOption,
} from "./Diesel";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

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
  const { t, dir } = useLanguage();
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {t("diesel.filters.title")}
        </h2>
        <p className="mt-1 text-sm font-semibold text-gray-900">
          {t("diesel.filters.description")}
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">

        <div>
          <label htmlFor="diesel-from-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.fromDate")}
          </label>
          <VoiceTypingField fieldLabel="diesel from date" mode="date"><input
            id="diesel-from-date"
            type="date"
            value={filters.fromDate}
            onChange={(event) =>
              updateFilter(setFilters, "fromDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="diesel-to-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.toDate")}
          </label>
          <VoiceTypingField fieldLabel="diesel to date" mode="date"><input
            id="diesel-to-date"
            type="date"
            value={filters.toDate}
            onChange={(event) =>
              updateFilter(setFilters, "toDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="diesel-pump-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("diesel.fields.petrolPump")}
          </label>
          <select
            id="diesel-pump-filter"
            value={filters.petrolPumpId}
            onChange={(event) =>
              updateFilter(setFilters, "petrolPumpId", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("diesel.filters.allPumps")}</option>
            {petrolPumps.map((pump) => (
              <option key={pump.id} value={pump.id}>
                {pump.pumpName}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="diesel-vehicle-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.vehicle")}
          </label>
          <select
            id="diesel-vehicle-filter"
            value={filters.vehicleId}
            onChange={(event) =>
              updateFilter(setFilters, "vehicleId", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("diesel.filters.allVehicles")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="diesel-status-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("diesel.fields.paymentStatus")}
          </label>
          <select
            id="diesel-status-filter"
            value={filters.paymentStatus}
            onChange={(event) =>
              updateFilter(setFilters, "paymentStatus", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("diesel.filters.all")}</option>
            <option value="Paid">{t("common.paymentStatus.paid")}</option>
            <option value="Partial">{t("common.paymentStatus.partial")}</option>
            <option value="Unpaid">{t("common.paymentStatus.unpaid")}</option>
          </select>
        </div>


        <div>
          <label htmlFor="diesel-search" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.actions.search")}
          </label>
          <VoiceTypingField fieldLabel={t("diesel.filters.searchPlaceholder")} mode="text"><input
            id="diesel-search"
            type="text"
            value={filters.search}
            onChange={(event) =>
              updateFilter(setFilters, "search", event.target.value)
            }
            placeholder={t("diesel.filters.searchPlaceholder")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>

      </div>

      <div className="mt-5 flex justify-end">
        <button
          type="button"
          onClick={onReset}
          className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
        >
          {t("common.actions.reset")}
        </button>
      </div>
    </div>
  );
}

import { CalendarDays, RotateCcw, Search } from "lucide-react";

import {
  OWNER_GARI_TRANSACTION_TYPES,
  type MovementGroupOption,
  type OwnerGariFilters,
  type VehicleOption,
} from "./types";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  filters: OwnerGariFilters;
  vehicles: VehicleOption[];
  owners: string[];
  movementGroups: MovementGroupOption[];
  loadingVehicles: boolean;
  onChange: (next: OwnerGariFilters) => void;
  onSearch: () => void;
  onReset: () => void;
  t: (key: string) => string;
};

function display(value: string | null | undefined) {
  return value?.trim() || "—";
}

export default function OwnerGariAccountFilters({
  filters,
  vehicles,
  owners,
  movementGroups,
  loadingVehicles,
  onChange,
  onSearch,
  onReset,
  t,
}: Props) {
  const visibleVehicles = filters.ownerName
    ? vehicles.filter((vehicle) => vehicle.owner_name?.trim() === filters.ownerName)
    : vehicles;

  const update = <Key extends keyof OwnerGariFilters>(
    key: Key,
    value: OwnerGariFilters[Key]
  ) => onChange({ ...filters, [key]: value });

  return (
    <section className="rounded-2xl bg-white p-5 shadow-md">
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.vehicle")}</span>
          <select
            value={filters.vehicleId}
            disabled={loadingVehicles}
            onChange={(event) => update("vehicleId", event.target.value)}
            className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("ownerGariAccount.filters.selectVehicle")}</option>
            {visibleVehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {display(vehicle.vehicle_no)}
                {vehicle.owner_name ? ` — ${vehicle.owner_name}` : ""}
              </option>
            ))}
          </select>
        </label>

        <label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.owner")}</span>
          <select
            value={filters.ownerName}
            onChange={(event) => {
              const ownerName = event.target.value;
              const selectedVehicle = vehicles.find(
                (vehicle) => vehicle.id === filters.vehicleId
              );
              onChange({
                ...filters,
                ownerName,
                vehicleId:
                  !ownerName || selectedVehicle?.owner_name?.trim() === ownerName
                    ? filters.vehicleId
                    : vehicles.find(
                        (vehicle) => vehicle.owner_name?.trim() === ownerName
                      )?.id ?? "",
              });
            }}
            className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("ownerGariAccount.filters.allOwners")}</option>
            {owners.map((owner) => (
              <option key={owner} value={owner}>{owner}</option>
            ))}
          </select>
        </label>


        <VoiceTypingField fieldLabel={t("ownerGariAccount.filters.month")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.month")}</span>
          <div className="relative">
            <CalendarDays className="pointer-events-none absolute start-3 top-3.5 text-slate-400" size={18} />
            <input
              type="month"
              value={filters.month}
              onChange={(event) => onChange({
                ...filters,
                month: event.target.value,
                dateFrom: "",
                dateTo: "",
              })}
              className="w-full rounded-xl border border-slate-300 py-3 pe-3 ps-10 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            />
          </div>
        </label></VoiceTypingField>


        <label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.transactionType")}</span>
          <select
            value={filters.transactionType}
            onChange={(event) => update(
              "transactionType",
              event.target.value as OwnerGariFilters["transactionType"]
            )}
            className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("ownerGariAccount.filters.allTransactionTypes")}</option>
            {OWNER_GARI_TRANSACTION_TYPES.map((type) => (
              <option key={type} value={type}>
                {t(`ownerGariAccount.transactionTypes.${type}`)}
              </option>
            ))}
          </select>
        </label>


        <VoiceTypingField fieldLabel={t("ownerGariAccount.filters.dateFrom")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.dateFrom")}</span>
          <input
            type="date"
            value={filters.dateFrom}
            onChange={(event) => onChange({
              ...filters,
              dateFrom: event.target.value,
              month: "",
            })}
            className="w-full rounded-xl border border-slate-300 px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
          />
        </label></VoiceTypingField>



        <VoiceTypingField fieldLabel={t("ownerGariAccount.filters.dateTo")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.dateTo")}</span>
          <input
            type="date"
            value={filters.dateTo}
            onChange={(event) => onChange({
              ...filters,
              dateTo: event.target.value,
              month: "",
            })}
            className="w-full rounded-xl border border-slate-300 px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
          />
        </label></VoiceTypingField>


        <label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.movementGroup")}</span>
          <select
            value={filters.movementGroupId}
            onChange={(event) => update("movementGroupId", event.target.value)}
            className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("ownerGariAccount.filters.allMovementGroups")}</option>
            {movementGroups.map((group) => (
              <option key={group.movement_group_id} value={group.movement_group_id}>
                {group.reference_no || group.movement_group_id.slice(0, 8)} — {group.transaction_date}
              </option>
            ))}
          </select>
        </label>


        <VoiceTypingField fieldLabel={t("ownerGariAccount.filters.searchPlaceholder")} mode="text"><label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.filters.search")}</span>
          <div className="relative">
            <Search className="pointer-events-none absolute start-3 top-3.5 text-slate-400" size={18} />
            <input
              value={filters.search}
              onChange={(event) => update("search", event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") onSearch();
              }}
              placeholder={t("ownerGariAccount.filters.searchPlaceholder")}
              className="w-full rounded-xl border border-slate-300 py-3 pe-3 ps-10 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            />
          </div>
        </label></VoiceTypingField>

      </div>

      <div className="mt-4 flex flex-wrap justify-end gap-3">
        <button
          type="button"
          onClick={onReset}
          className="inline-flex items-center gap-2 rounded-xl border border-slate-300 px-4 py-3 font-bold text-slate-700 hover:bg-slate-50"
        >
          <RotateCcw size={18} /> {t("common.actions.reset")}
        </button>
        <button
          type="button"
          onClick={onSearch}
          disabled={!filters.vehicleId}
          className="inline-flex items-center gap-2 rounded-xl bg-blue-700 px-5 py-3 font-black text-white hover:bg-blue-800 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <Search size={18} /> {t("common.actions.search")}
        </button>
      </div>
    </section>
  );
}

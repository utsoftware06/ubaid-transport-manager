"use client";

import type { VehicleLedgerFilterValues, VehicleFilterType } from "./VehicleLedger";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type VehicleOption = { id: string; vehicleNo: string; ownerName: string };
type Props = {
  filters: VehicleLedgerFilterValues;
  setFilters: React.Dispatch<React.SetStateAction<VehicleLedgerFilterValues>>;
  vehicleOptions: VehicleOption[];
  paymentStatuses: string[];
  loadingSources: string[];
  counterparties: string[];
};

export default function VehicleLedgerFilters({
  filters,
  setFilters,
  vehicleOptions,
  paymentStatuses,
  loadingSources,
  counterparties,
}: Props) {
  const { t, dir } = useLanguage();
  function updateFilter(key: keyof VehicleLedgerFilterValues, value: string) {
    setFilters((previous) => ({ ...previous, [key]: value }));
  }

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-gray-900">{t("vehicleLedger.filters.title")}</h2>
        <p className="mt-1 text-sm font-medium text-gray-700">{t("vehicleLedger.filters.description")}</p>
      </div>



      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <select aria-label={t("vehicleLedger.filters.allVehicles")} value={filters.vehicleId}
          onChange={(event) => updateFilter("vehicleId", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="">{t("vehicleLedger.filters.allVehicles")}</option>
          {vehicleOptions.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicleNo} - {vehicle.ownerName}</option>)}
        </select>

        <select aria-label={t("vehicleLedger.filters.title")} value={filters.filterType}
          onChange={(event) => {
            const value = event.target.value as VehicleFilterType;
            setFilters((previous) => ({ ...previous, filterType: value, fromDate: value === "custom" ? previous.fromDate : "", toDate: value === "custom" ? previous.toDate : "" }));
          }} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="all">{t("vehicleLedger.filters.allTime")}</option>
          <option value="today">{t("vehicleLedger.filters.today")}</option>
          <option value="week">{t("vehicleLedger.filters.last7Days")}</option>
          <option value="month">{t("vehicleLedger.filters.thisMonth")}</option>
          <option value="sixMonths">{t("vehicleLedger.filters.last6Months")}</option>
          <option value="year">{t("vehicleLedger.filters.thisYear")}</option>
          <option value="custom">{t("vehicleLedger.filters.custom")}</option>
        </select>

        <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input type="date" dir="ltr" aria-label={t("common.fromDate")} value={filters.fromDate}
          disabled={filters.filterType !== "custom"} onChange={(event) => updateFilter("fromDate", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600" /></VoiceTypingField>
        <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input type="date" dir="ltr" aria-label={t("common.toDate")} value={filters.toDate}
          disabled={filters.filterType !== "custom"} onChange={(event) => updateFilter("toDate", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600" /></VoiceTypingField>

        <select aria-label={t("vehicleLedger.filters.paymentStatus")} value={filters.paymentStatus}
          onChange={(event) => updateFilter("paymentStatus", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="">{t("vehicleLedger.filters.allPaymentStatuses")}</option>
          {paymentStatuses.map((status) => <option key={status} value={status}>{t(`vehicleLedger.filters.status.${status === "Not tracked" ? "notTracked" : status.toLowerCase()}`)}</option>)}
        </select>

        <select aria-label={t("vehicleLedger.filters.loadedThrough")} value={filters.loadingSource}
          onChange={(event) => updateFilter("loadingSource", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="">{t("vehicleLedger.filters.allSources")}</option>
          {loadingSources.map((source) => <option key={source} value={source}>{source}</option>)}
        </select>

        <select aria-label={t("vehicleLedger.filters.collectFrom")} value={filters.collectFrom}
          onChange={(event) => updateFilter("collectFrom", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="">{t("vehicleLedger.filters.allCounterparties")}</option>
          {counterparties.map((counterparty) => <option key={counterparty} value={counterparty}>{counterparty}</option>)}
        </select>


        <VoiceTypingField fieldLabel={t("vehicleLedger.filters.biltyVoucherNo")} mode="identifier"><label className="grid gap-1 text-sm font-semibold text-gray-800">
          <span>{t("vehicleLedger.filters.biltyVoucherNo")}</span>
          <input type="text" aria-label={t("vehicleLedger.filters.biltyVoucherNo")} placeholder={t("vehicleLedger.filters.biltyVoucherPlaceholder")}
            value={filters.biltyVoucherNo} onChange={(event) => updateFilter("biltyVoucherNo", event.target.value)}
            className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm" />
        </label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("common.actions.search")} mode="text"><input type="text" aria-label={t("common.actions.search")} placeholder={t("vehicleLedger.filters.searchPlaceholder")}
          value={filters.search} onChange={(event) => updateFilter("search", event.target.value)}
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm" /></VoiceTypingField>
        <button type="button" onClick={() => setFilters({ vehicleId: "", vehicle: "", filterType: "all", fromDate: "", toDate: "", search: "", biltyVoucherNo: "", paymentStatus: "", loadingSource: "", collectFrom: "" })}
          className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 shadow-sm hover:bg-gray-50">
          {t("common.actions.reset")}
        </button>
      </div>
    </section>
  );
}

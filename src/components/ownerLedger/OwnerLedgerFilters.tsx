"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import type { OwnerFilterType, OwnerLedgerFilterValues, OwnerVehicleOption } from "@/components/ownerLedger/types";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  filters: OwnerLedgerFilterValues;
  setFilters: React.Dispatch<React.SetStateAction<OwnerLedgerFilterValues>>;
  ownerOptions: string[];
  vehicleOptions: OwnerVehicleOption[];
  paymentStatuses: string[];
};

export default function OwnerLedgerFilters({ filters, setFilters, ownerOptions, vehicleOptions, paymentStatuses }: Props) {
  const { t, dir } = useLanguage();
  function updateFilter(key: keyof OwnerLedgerFilterValues, value: string) {
    setFilters((previous) => ({ ...previous, [key]: value }));
  }

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-gray-900">{t("ownerLedger.table.title")}</h2>
        <p className="mt-1 text-sm font-medium text-gray-700">{t("ownerLedger.table.description")}</p>
      </div>



      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <select aria-label={t("common.owner")} value={filters.ownerName} onChange={(event) => updateFilter("ownerName", event.target.value)} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="">{t("ownerLedger.filters.allOwners")}</option>
          {ownerOptions.map((owner) => <option key={owner} value={owner}>{owner}</option>)}
        </select>
        <select aria-label={t("reports.print.period")} value={filters.filterType} onChange={(event) => {
          const value = event.target.value as OwnerFilterType;
          setFilters((previous) => ({ ...previous, filterType: value, fromDate: value === "custom" ? previous.fromDate : "", toDate: value === "custom" ? previous.toDate : "" }));
        }} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="all">{t("common.dateFilters.allTime")}</option>
          <option value="today">{t("common.dateFilters.today")}</option>
          <option value="week">{t("common.dateFilters.last7Days")}</option>
          <option value="month">{t("common.dateFilters.thisMonth")}</option>
          <option value="sixMonths">{t("common.dateFilters.last6Months")}</option>
          <option value="year">{t("common.dateFilters.thisYear")}</option>
          <option value="custom">{t("common.dateFilters.custom")}</option>
        </select>
        <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input type="date" aria-label={t("common.fromDate")} dir="ltr" value={filters.fromDate} disabled={filters.filterType !== "custom"} onChange={(event) => updateFilter("fromDate", event.target.value)} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm disabled:bg-gray-100" /></VoiceTypingField>
        <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input type="date" aria-label={t("common.toDate")} dir="ltr" value={filters.toDate} disabled={filters.filterType !== "custom"} onChange={(event) => updateFilter("toDate", event.target.value)} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm disabled:bg-gray-100" /></VoiceTypingField>
        <select aria-label={t("common.vehicle")} value={filters.vehicleId} onChange={(event) => updateFilter("vehicleId", event.target.value)} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="">{t("vehicleLedger.filters.allVehicles")}</option>
          {vehicleOptions.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicleNo}</option>)}
        </select>
        <select aria-label={t("vehicleLedger.filters.paymentStatus")} value={filters.paymentStatus} onChange={(event) => updateFilter("paymentStatus", event.target.value)} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm">
          <option value="">{t("vehicleLedger.filters.allPaymentStatuses")}</option>
          {paymentStatuses.map((status) => <option key={status} value={status}>{t(`vehicleLedger.filters.status.${status === "Not tracked" ? "notTracked" : status.toLowerCase()}`)}</option>)}
        </select>

        <VoiceTypingField fieldLabel={t("ownerLedger.filters.biltyVoucherNo")} mode="identifier"><label className="grid gap-1 text-sm font-semibold text-gray-800">
          <span>{t("ownerLedger.filters.biltyVoucherNo")}</span>
          <input type="text" aria-label={t("ownerLedger.filters.biltyVoucherNo")} placeholder={t("ownerLedger.filters.biltyVoucherPlaceholder")} value={filters.biltyVoucherNo} onChange={(event) => updateFilter("biltyVoucherNo", event.target.value)} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm" />
        </label></VoiceTypingField>

        <VoiceTypingField fieldLabel={t("common.actions.search")} mode="text"><input type="text" aria-label={t("common.actions.search")} placeholder={t("ownerLedger.filters.searchPlaceholder")} value={filters.search} onChange={(event) => updateFilter("search", event.target.value)} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 shadow-sm" /></VoiceTypingField>
      </div>
    </section>
  );
}

"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import type {
  PartyLedgerAdda,
  PartyLedgerFilters as FilterValues,
  PartyLedgerOption,
  PartyLedgerPeriod,
  PartyPaymentStatus,
} from "./types";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  filters: FilterValues;
  addas: PartyLedgerAdda[];
  parties: PartyLedgerOption[];
  showAddaFilter: boolean;
  invalidDateRange: boolean;
  onChange: (filters: FilterValues) => void;
  onReset: () => void;
};

export default function PartyLedgerFilters({
  filters,
  addas,
  parties,
  showAddaFilter,
  invalidDateRange,
  onChange,
  onReset,
}: Props) {
  const { t } = useLanguage();
  const inputClass =
    "w-full rounded-lg border border-slate-300 bg-white px-3 py-3 font-semibold text-slate-900 placeholder:text-slate-500 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100";

  function update<K extends keyof FilterValues>(key: K, value: FilterValues[K]) {
    onChange({ ...filters, [key]: value });
  }

  const partyOptions = parties.filter(
    (party) => !filters.addaId || party.addaId === filters.addaId
  );

  return (
    <section
      aria-labelledby="party-ledger-filters-title"
      className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm md:p-6"
    >
      <h2 id="party-ledger-filters-title" className="text-2xl font-extrabold text-slate-900">
        {t("partyLedger.filters.title")}
      </h2>
      <div className="mt-5 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        {showAddaFilter && (
          <div>
            <label htmlFor="party-ledger-adda" className="mb-2 block font-bold text-slate-900">
              {t("partyLedger.fields.adda")}
            </label>
            <select
              id="party-ledger-adda"
              value={filters.addaId}
              onChange={(event) =>
                onChange({ ...filters, addaId: event.target.value, partyId: "" })
              }
              className={inputClass}
            >
              <option value="">{t("partyLedger.filters.allAddas")}</option>
              {addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}
            </select>
          </div>
        )}

        <div>
          <label htmlFor="party-ledger-party" className="mb-2 block font-bold text-slate-900">
            {t("common.party")}
          </label>
          <select
            id="party-ledger-party"
            value={filters.partyId}
            onChange={(event) => update("partyId", event.target.value)}
            className={inputClass}
          >
            <option value="">{t("partyLedger.filters.allParties")}</option>
            {partyOptions.map((party) => <option key={party.id} value={party.id}>{party.name}</option>)}
          </select>
        </div>

        <div>
          <label htmlFor="party-ledger-period" className="mb-2 block font-bold text-slate-900">
            {t("partyLedger.filters.period")}
          </label>
          <select
            id="party-ledger-period"
            value={filters.period}
            onChange={(event) => {
              const period = event.target.value as PartyLedgerPeriod;
              onChange({
                ...filters,
                period,
                fromDate: period === "custom" ? filters.fromDate : "",
                toDate: period === "custom" ? filters.toDate : "",
              });
            }}
            className={inputClass}
          >
            <option value="all">{t("common.dateFilters.allTime")}</option>
            <option value="today">{t("common.dateFilters.today")}</option>
            <option value="last7Days">{t("common.dateFilters.last7Days")}</option>
            <option value="thisMonth">{t("common.dateFilters.thisMonth")}</option>
            <option value="last6Months">{t("common.dateFilters.last6Months")}</option>
            <option value="thisYear">{t("common.dateFilters.thisYear")}</option>
            <option value="custom">{t("common.dateFilters.custom")}</option>
          </select>
        </div>

        <div>
          <label htmlFor="party-ledger-status" className="mb-2 block font-bold text-slate-900">
            {t("partyLedger.fields.status")}
          </label>
          <select
            id="party-ledger-status"
            value={filters.paymentStatus}
            onChange={(event) =>
              update(
                "paymentStatus",
                event.target.value as "all" | PartyPaymentStatus
              )
            }
            className={inputClass}
          >
            <option value="all">{t("partyLedger.filters.allStatuses")}</option>
            <option value="paid">{t("partyLedger.status.paid")}</option>
            <option value="partial">{t("partyLedger.status.partial")}</option>
            <option value="unpaid">{t("partyLedger.status.unpaid")}</option>
          </select>
        </div>

        {filters.period === "custom" && (
          <>

            <div>
              <label htmlFor="party-ledger-from" className="mb-2 block font-bold text-slate-900">
                {t("common.fromDate")}
              </label>
              <VoiceTypingField fieldLabel="party ledger from" mode="date"><input
                id="party-ledger-from"
                type="date"
                dir="ltr"
                value={filters.fromDate}
                onChange={(event) => update("fromDate", event.target.value)}
                className={inputClass}
              /></VoiceTypingField>
            </div>


            <div>
              <label htmlFor="party-ledger-to" className="mb-2 block font-bold text-slate-900">
                {t("common.toDate")}
              </label>
              <VoiceTypingField fieldLabel="party ledger to" mode="date"><input
                id="party-ledger-to"
                type="date"
                dir="ltr"
                value={filters.toDate}
                onChange={(event) => update("toDate", event.target.value)}
                className={inputClass}
              /></VoiceTypingField>
            </div>

          </>
        )}


        <div className={filters.period === "custom" ? "xl:col-span-2" : ""}>
          <label htmlFor="party-ledger-search" className="mb-2 block font-bold text-slate-900">
            {t("common.actions.search")}
          </label>
          <VoiceTypingField fieldLabel={t("partyLedger.filters.searchPlaceholder")} mode="text"><input
            id="party-ledger-search"
            type="search"
            value={filters.search}
            onChange={(event) => update("search", event.target.value)}
            placeholder={t("partyLedger.filters.searchPlaceholder")}
            className={inputClass}
          /></VoiceTypingField>
        </div>

      </div>

      {invalidDateRange && (
        <p role="alert" className="mt-4 rounded-lg border border-red-200 bg-red-50 p-3 font-bold text-red-700">
          {t("reports.validation.invalidDateRange")}
        </p>
      )}

      <div className="mt-5 flex justify-end">
        <button
          type="button"
          onClick={onReset}
          className="rounded-lg border border-slate-300 bg-white px-5 py-3 font-bold text-slate-900 hover:bg-slate-50 focus-visible:ring-2 focus-visible:ring-blue-500"
        >
          {t("common.actions.reset")}
        </button>
      </div>
    </section>
  );
}

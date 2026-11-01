"use client";

import type {
  CustomerLedgerFilterValues,
  SenderOption,
} from "@/types/customerLedger";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  senders: SenderOption[];
  filterValues: CustomerLedgerFilterValues;
  setFilterValues: React.Dispatch<
    React.SetStateAction<CustomerLedgerFilterValues>
  >;
  onSearch: () => void;
  onReset: () => void;
};

export default function CustomerLedgerFilters({
  senders,
  filterValues,
  setFilterValues,
  onSearch,
  onReset,
}: Props) {
  const { t, dir } = useLanguage();
  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md">



      <div className="grid grid-cols-1 gap-4 lg:grid-cols-6">
        <label htmlFor="customer-ledger-sender" className="sr-only">
          {t("common.sender")}
        </label>
        <select
          id="customer-ledger-sender"
          value={filterValues.senderName}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              senderName: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        >
          <option value="">{t("customerLedger.filters.allSenders")}</option>

          {senders.map((sender) => (
            <option key={sender.name} value={sender.name}>
              {sender.name}
            </option>
          ))}
        </select>

        <label htmlFor="customer-ledger-from-date" className="sr-only">
          {t("common.fromDate")}
        </label>
        <VoiceTypingField fieldLabel="customer ledger from date" mode="date"><input
          id="customer-ledger-from-date"
          type="date"
          dir="ltr"
          value={filterValues.fromDate}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              fromDate: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        /></VoiceTypingField>

        <label htmlFor="customer-ledger-to-date" className="sr-only">
          {t("common.toDate")}
        </label>
        <VoiceTypingField fieldLabel="customer ledger to date" mode="date"><input
          id="customer-ledger-to-date"
          type="date"
          dir="ltr"
          value={filterValues.toDate}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              toDate: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        /></VoiceTypingField>

        <label htmlFor="customer-ledger-search" className="sr-only">
          {t("common.actions.search")}
        </label>
        <VoiceTypingField fieldLabel={t("customerLedger.filters.searchPlaceholder")} mode="text"><input
          id="customer-ledger-search"
          type="text"
          placeholder={t("customerLedger.filters.searchPlaceholder")}
          value={filterValues.search}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              search: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        /></VoiceTypingField>

        <button
          type="button"
          onClick={onSearch}
          className="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white transition hover:bg-blue-700"
        >
          {t("common.actions.search")}
        </button>

        <button
          type="button"
          onClick={onReset}
          className="rounded-lg
      bg-gray-600 px-4 py-2 font-semibold text-white transition hover:bg-gray-700"

              >
          {t("common.actions.reset")}
        </button>
      </div>

    </section>
  );
}

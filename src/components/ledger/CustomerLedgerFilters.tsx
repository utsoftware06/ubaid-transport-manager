"use client";

import type {
  CustomerLedgerFilterValues,
  SenderOption,
} from "./CustomerLedger";

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
  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h1 className="text-2xl font-bold text-gray-900">Customer Ledger</h1>
        <p className="mt-1 text-sm font-medium text-gray-700">
          Sender wise booking, freight aur payment summary.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-6">
        <select
          value={filterValues.senderName}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              senderName: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        >
          <option value="">All Senders</option>

          {senders.map((sender) => (
            <option key={sender.name} value={sender.name}>
              {sender.name}
            </option>
          ))}
        </select>

        <input
          type="date"
          value={filterValues.fromDate}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              fromDate: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        />

        <input
          type="date"
          value={filterValues.toDate}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              toDate: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        />

        <input
          type="text"
          placeholder="Booking No / Route / Goods"
          value={filterValues.search}
          onChange={(event) =>
            setFilterValues((prev) => ({
              ...prev,
              search: event.target.value,
            }))
          }
          className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm focus:border-blue-500 focus:outline-none"
        />

        <button
          type="button"
          onClick={onSearch}
          className="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white transition hover:bg-blue-700"
        >
          Search
        </button>

        <button
          type="button"
          onClick={onReset}
          className="rounded-lg bg-gray-600 px-4 py-2 font-semibold text-white transition hover:bg-gray-700"
        >
          Reset
        </button>
      </div>
    </section>
  );
}
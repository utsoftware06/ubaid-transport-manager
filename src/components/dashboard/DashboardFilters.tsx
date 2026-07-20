"use client";

import type { Dispatch, SetStateAction } from "react";
import { type DashboardDateFilter } from "./DashboardOverview";

type Props = {
  dateFilter: DashboardDateFilter;
  setDateFilter: Dispatch<SetStateAction<DashboardDateFilter>>;
  fromDate: string;
  setFromDate: Dispatch<SetStateAction<string>>;
  toDate: string;
  setToDate: Dispatch<SetStateAction<string>>;
  onReset: () => void;
};

const filterOptions: { value: DashboardDateFilter; label: string }[] = [
  { value: "today", label: "Today" },
  { value: "last7Days", label: "Last 7 Days" },
  { value: "thisMonth", label: "This Month" },
  { value: "last6Months", label: "Last 6 Months" },
  { value: "thisYear", label: "This Year" },
  { value: "custom", label: "Custom Date Range" },
];

export default function DashboardFilters({
  dateFilter,
  setDateFilter,
  fromDate,
  setFromDate,
  toDate,
  setToDate,
  onReset,
}: Props) {
  return (
    <section className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <h2 className="text-2xl font-bold text-gray-900">Dashboard Filters</h2>

      <div className="mt-6 grid grid-cols-1 gap-5 md:grid-cols-2 lg:grid-cols-4">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Date Filter
          </label>
          <select
            value={dateFilter}
            onChange={(event) =>
              setDateFilter(event.target.value as DashboardDateFilter)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {filterOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </div>

        {dateFilter === "custom" && (
          <>
            <div>
              <label className="mb-2 block text-sm font-bold text-gray-900">
                From Date
              </label>
              <input
                type="date"
                value={fromDate}
                onChange={(event) => setFromDate(event.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </div>

            <div>
              <label className="mb-2 block text-sm font-bold text-gray-900">
                To Date
              </label>
              <input
                type="date"
                value={toDate}
                onChange={(event) => setToDate(event.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </>
        )}

        <div className="flex items-end">
          <button
            type="button"
            onClick={onReset}
            className="w-full rounded-lg bg-gray-800 px-6 py-3 font-bold text-white hover:bg-gray-900"
          >
            Reset Filters
          </button>
        </div>
      </div>
    </section>
  );
}
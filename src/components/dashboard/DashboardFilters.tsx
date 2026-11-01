"use client";

import type { Dispatch, SetStateAction } from "react";
import { type DashboardDateFilter } from "./DashboardOverview";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  dateFilter: DashboardDateFilter;
  setDateFilter: Dispatch<SetStateAction<DashboardDateFilter>>;
  fromDate: string;
  setFromDate: Dispatch<SetStateAction<string>>;
  toDate: string;
  setToDate: Dispatch<SetStateAction<string>>;
  onReset: () => void;
};

export default function DashboardFilters({
  dateFilter,
  setDateFilter,
  fromDate,
  setFromDate,
  toDate,
  setToDate,
  onReset,
}: Props) {
  const { t, dir } = useLanguage();
  const filterOptions: { value: DashboardDateFilter; label: string }[] = [
    { value: "today", label: t("dashboard.filters.today") },
    { value: "last7Days", label: t("dashboard.filters.last7Days") },
    { value: "thisMonth", label: t("dashboard.filters.thisMonth") },
    { value: "last6Months", label: t("dashboard.filters.last6Months") },
    { value: "thisYear", label: t("dashboard.filters.thisYear") },
    { value: "custom", label: t("dashboard.filters.custom") },
  ];
  return (
    <div dir={dir} className="flex flex-wrap items-end gap-1.5">
      <div className="w-[120px] shrink-0">
        <label
          htmlFor="dashboard-period-filter"
          className="sr-only"
        >
          {t("dashboard.shell.chart.period")}
        </label>
        <select
          id="dashboard-period-filter"
          value={dateFilter}
          onChange={(event) =>
            setDateFilter(event.target.value as DashboardDateFilter)
          }
          className="h-9 w-full rounded-lg border border-slate-200 bg-white px-2 text-xs font-bold text-slate-700 outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
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

          <div className="w-[132px]">
            <label
              htmlFor="dashboard-from-date"
              className="sr-only"
            >
              {t("dashboard.filters.fromDate")}
            </label>
            <VoiceTypingField fieldLabel="dashboard from date" mode="date"><input
              id="dashboard-from-date"
              type="date"
              dir="ltr"
              value={fromDate}
              onChange={(event) => setFromDate(event.target.value)}
              className="h-9 w-full rounded-lg border border-slate-200 bg-white px-2 text-xs font-bold text-slate-700 outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
            /></VoiceTypingField>
          </div>


          <div className="w-[132px]">
            <label
              htmlFor="dashboard-to-date"
              className="sr-only"
            >
              {t("dashboard.filters.toDate")}
            </label>
            <VoiceTypingField fieldLabel="dashboard to date" mode="date"><input
              id="dashboard-to-date"
              type="date"
              dir="ltr"
              value={toDate}
              onChange={(event) => setToDate(event.target.value)}
              className="h-9 w-full rounded-lg border border-slate-200 bg-white px-2 text-xs font-bold text-slate-700 outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
            /></VoiceTypingField>
          </div>

        </>
      )}

      <button
        type="button"
        onClick={onReset}
        className="h-6 rounded-lg px-1.5 text-[10px] font-semibold text-slate-500 transition hover:bg-slate-100 hover:text-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
      >
        {t("dashboard.filters.reset")}
      </button>
    </div>
  );
}

"use client";

import type { Dispatch, SetStateAction } from "react";
import { TrendingUp } from "lucide-react";
import {
  type DashboardDateFilter,
  type DashboardMetricSummary,
  type DashboardTrip,
  formatAmount,
} from "./DashboardOverview";
import DashboardFilters from "@/components/dashboard/DashboardFilters";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  trips: DashboardTrip[];
  summary: DashboardMetricSummary;
  loading: boolean;
  dateFilter: DashboardDateFilter;
  setDateFilter: Dispatch<SetStateAction<DashboardDateFilter>>;
  fromDate: string;
  setFromDate: Dispatch<SetStateAction<string>>;
  toDate: string;
  setToDate: Dispatch<SetStateAction<string>>;
  onReset: () => void;
};

type DailyValues = {
  date: string;
  income: number;
  expense: number;
};

type ChartGranularity = "day" | "week" | "month";

type Coordinate = {
  x: number;
  y: number;
  date: string;
};

function buildSmoothPath(points: Coordinate[]) {
  if (points.length === 0) return "";
  let path = "M " + points[0].x + " " + points[0].y;

  for (let index = 1; index < points.length; index += 1) {
    const previous = points[index - 1];
    const current = points[index];
    const middleX = (previous.x + current.x) / 2;
    path +=
      " C " +
      middleX +
      " " +
      previous.y +
      ", " +
      middleX +
      " " +
      current.y +
      ", " +
      current.x +
      " " +
      current.y;
  }

  return path;
}

function parseDateKey(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day] = match;
  const date = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
  if (
    date.getUTCFullYear() !== Number(year) ||
    date.getUTCMonth() !== Number(month) - 1 ||
    date.getUTCDate() !== Number(day)
  ) {
    return null;
  }
  return date;
}

function formatDateKey(date: Date) {
  return [
    date.getUTCFullYear(),
    String(date.getUTCMonth() + 1).padStart(2, "0"),
    String(date.getUTCDate()).padStart(2, "0"),
  ].join("-");
}

function getTodayDateKey() {
  const today = new Date();
  return new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
}

function buildTimeSeries(
  trips: DashboardTrip[],
  dateFilter: DashboardDateFilter,
  fromDate: string,
  toDate: string
) {
  const tripDates = trips
    .map((trip) => parseDateKey(trip.tripDate))
    .filter((date): date is Date => date !== null);
  const today = getTodayDateKey();
  let start: Date | null = null;
  let end: Date | null = null;
  let granularity: ChartGranularity = "day";

  if (dateFilter === "today") {
    start = today;
    end = today;
  } else if (dateFilter === "last7Days") {
    start = new Date(today);
    start.setUTCDate(start.getUTCDate() - 6);
    end = today;
  } else if (dateFilter === "thisMonth") {
    start = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1));
    end = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0));
  } else if (dateFilter === "last6Months") {
    start = new Date(today);
    start.setUTCMonth(start.getUTCMonth() - 6);
    end = today;
    granularity = "month";
  } else if (dateFilter === "thisYear") {
    start = new Date(Date.UTC(today.getUTCFullYear(), 0, 1));
    end = new Date(Date.UTC(today.getUTCFullYear(), 11, 31));
    granularity = "month";
  } else {
    start = fromDate ? parseDateKey(fromDate) : null;
    end = toDate ? parseDateKey(toDate) : null;
    if (!start && tripDates.length) {
      start = new Date(Math.min(...tripDates.map((date) => date.getTime())));
    }
    if (!end && tripDates.length) {
      end = new Date(Math.max(...tripDates.map((date) => date.getTime())));
    }
    if (start && end) {
      const spanDays = Math.floor((end.getTime() - start.getTime()) / 86_400_000) + 1;
      granularity = spanDays <= 45 ? "day" : spanDays <= 180 ? "week" : "month";
    }
  }

  if (!start || !end || end < start) return { values: [] as DailyValues[], granularity };

  const bucketStarts: Date[] = [];
  if (granularity === "month") {
    let cursor = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));
    while (cursor <= end) {
      bucketStarts.push(cursor);
      cursor = new Date(Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 1));
    }
  } else {
    let cursor = new Date(start);
    while (cursor <= end) {
      bucketStarts.push(cursor);
      cursor = new Date(cursor);
      cursor.setUTCDate(cursor.getUTCDate() + (granularity === "week" ? 7 : 1));
    }
  }

  const aggregates = new Map<string, DailyValues>();
  for (const trip of trips) {
    const tripDate = parseDateKey(trip.tripDate);
    if (!tripDate || tripDate < start || tripDate > end) continue;

    let bucketDate = tripDate;
    if (granularity === "week") {
      const weekIndex = Math.floor((tripDate.getTime() - start.getTime()) / (7 * 86_400_000));
      bucketDate = new Date(start);
      bucketDate.setUTCDate(bucketDate.getUTCDate() + weekIndex * 7);
    } else if (granularity === "month") {
      bucketDate = new Date(Date.UTC(tripDate.getUTCFullYear(), tripDate.getUTCMonth(), 1));
    }

    const key = formatDateKey(bucketDate);
    const values = aggregates.get(key) ?? { date: key, income: 0, expense: 0 };
    values.income += trip.receivedAmount;
    values.expense += trip.totalExpense;
    aggregates.set(key, values);
  }

  return {
    values: bucketStarts.map((bucket) => {
      const key = formatDateKey(bucket);
      return aggregates.get(key) ?? { date: key, income: 0, expense: 0 };
    }),
    granularity,
  };
}

function formatAxisDate(value: string, granularity: ChartGranularity, locale: string) {
  const date = new Date(value + "T00:00:00");
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat(
        locale,
        granularity === "month"
          ? { month: "short", year: "2-digit" }
          : { day: "numeric", month: "short" }
      ).format(date);
}

function formatAxisAmount(value: number, locale: string) {
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(value);
}

export default function IncomeExpenseChart({
  trips,
  summary,
  loading,
  dateFilter,
  setDateFilter,
  fromDate,
  setFromDate,
  toDate,
  setToDate,
  onReset,
}: Props) {
  const { t, dir, language } = useLanguage();
  const locale = language === "ur" ? "ur-PK" : "en-PK";
  const { values: series, granularity } = buildTimeSeries(
    trips,
    dateFilter,
    fromDate,
    toDate
  );
  const maximum = series.reduce(
    (current, point) => Math.max(current, point.income, point.expense),
    1
  );
  const chartLeft = 82;
  const chartRight = 840;
  const chartTop = 24;
  const chartBottom = 204;
  const coordinatesFor = (key: "income" | "expense"): Coordinate[] =>
    series.map((point, index) => ({
      x:
        series.length < 2
          ? (chartLeft + chartRight) / 2
          : chartLeft + (index / (series.length - 1)) * (chartRight - chartLeft),
      y: chartBottom - (point[key] / maximum) * (chartBottom - chartTop),
      date: point.date,
    }));
  const incomeCoordinates = coordinatesFor("income");
  const expenseCoordinates = coordinatesFor("expense");
  const incomePath = buildSmoothPath(incomeCoordinates);
  const expensePath = buildSmoothPath(expenseCoordinates);
  const areaPath = (path: string, points: Coordinate[]) =>
    path && points.length > 1
      ? path +
        " L " +
        points[points.length - 1].x +
        " " +
        chartBottom +
        " L " +
        points[0].x +
        " " +
        chartBottom +
        " Z"
      : "";
  const incomeArea = areaPath(incomePath, incomeCoordinates);
  const expenseArea = areaPath(expensePath, expenseCoordinates);
  const axisTicks = Array.from({ length: 5 }, (_, index) => {
    const ratio = (4 - index) / 4;
    return {
      y: chartTop + (index / 4) * (chartBottom - chartTop),
      value: maximum * ratio,
    };
  });
  const lastSeriesIndex = series.length - 1;
  const labelIndexes =
    series.length <= 5
      ? series.map((_, index) => index)
      : [...new Set([0, 1, 2, 3, 4].map((step) => Math.round((lastSeriesIndex * step) / 4)))];

  return (
    <section
      dir={dir}
      className="h-full min-h-[330px] min-w-0 rounded-[16px] border border-[#e7edf5] bg-white p-4 shadow-[0_3px_14px_rgb(22_47_82_/_5%)]"
    >
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-b border-slate-100 pb-2.5">
        <div className="flex min-w-0 items-center gap-2">
          <span className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-lg bg-blue-50 text-blue-700">
            <TrendingUp className="h-4 w-4" aria-hidden="true" />
          </span>
          <h2 className="text-lg font-extrabold tracking-tight text-slate-900">
            {t("dashboard.chart.title")}
          </h2>
        </div>
        <DashboardFilters
          dateFilter={dateFilter}
          setDateFilter={setDateFilter}
          fromDate={fromDate}
          setFromDate={setFromDate}
          toDate={toDate}
          setToDate={setToDate}
          onReset={onReset}
        />
      </div>

      <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
        <div className="flex items-center gap-2.5">
          <span className="h-2 w-2 rounded-full bg-emerald-600" />
          <span className="text-[11px] font-bold text-slate-600">
            {t("dashboard.shell.chart.incomeLegend")}
          </span>
          <span dir="ltr" className="text-[11px] font-black text-slate-900">
            {formatAmount(summary.cashReceived)}
          </span>
        </div>
        <div className="flex items-center gap-2.5">
          <span className="h-2 w-2 rounded-full bg-rose-600" />
          <span className="text-[11px] font-bold text-slate-600">
            {t("dashboard.shell.chart.expenses")}
          </span>
          <span dir="ltr" className="text-[11px] font-black text-slate-900">
            {formatAmount(summary.expenses)}
          </span>
        </div>
      </div>

      {loading ? (
        <div className="mt-2 h-[210px] animate-pulse rounded-xl bg-slate-50">
          <div className="flex h-full flex-col justify-between p-6">
            <div className="h-px w-full bg-slate-200" />
            <div className="h-px w-full bg-slate-200" />
            <div className="h-px w-full bg-slate-200" />
            <div className="h-px w-full bg-slate-200" />
          </div>
        </div>
      ) : series.length === 0 ? (
        <div className="mt-2 flex min-h-[210px] flex-col items-center justify-center rounded-xl border border-dashed border-slate-200 bg-slate-50/70 p-6 text-center">
          <p className="font-extrabold text-slate-700">
            {t("dashboard.chart.empty")}
          </p>
          <p className="mt-1.5 text-sm text-slate-500">
            {t("dashboard.chart.emptyHint")}
          </p>
        </div>
      ) : (
        <div className="mt-2 min-w-0 overflow-hidden">
          <svg
            viewBox="0 0 870 250"
            preserveAspectRatio="none"
            className="h-[210px] w-full overflow-visible"
            role="img"
            aria-label={t("dashboard.chart.title")}
          >
            <defs>
              <linearGradient id="dashboard-income-area" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#059669" stopOpacity=".2" />
                <stop offset="100%" stopColor="#059669" stopOpacity="0" />
              </linearGradient>
              <linearGradient id="dashboard-expense-area" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#f43f5e" stopOpacity=".14" />
                <stop offset="100%" stopColor="#f43f5e" stopOpacity="0" />
              </linearGradient>
            </defs>
            {axisTicks.map((tick) => (
              <g key={tick.y}>
                <line
                  x1={chartLeft}
                  x2={chartRight}
                  y1={tick.y}
                  y2={tick.y}
                  stroke="#e8eef6"
                />
                <text
                  x={chartLeft - 12}
                  y={tick.y + 4}
                  textAnchor="end"
                  fill="#8390a4"
                  fontSize="10"
                  fontWeight="700"
                >
                  {formatAxisAmount(tick.value, locale)}
                </text>
              </g>
            ))}
            {expenseArea && <path d={expenseArea} fill="url(#dashboard-expense-area)" />}
            {incomeArea && <path d={incomeArea} fill="url(#dashboard-income-area)" />}
            {incomePath && (
              <path
                d={incomePath}
                fill="none"
                stroke="#059669"
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2.5"
              />
            )}
            {expensePath && (
              <path
                d={expensePath}
                fill="none"
                stroke="#f43f5e"
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2.5"
              />
            )}
            <text
              x={chartLeft}
              y="14"
              fill="#8390a4"
              fontSize="10"
              fontWeight="700"
            >
              Rs.
            </text>
            {labelIndexes.map((index) => {
              const point = incomeCoordinates[index];
              const expensePoint = expenseCoordinates[index];
              if (!point || !expensePoint) return null;
              return (
                <g key={point.date}>
                  {series.length === 1 && (
                    <>
                      <circle cx={point.x} cy={point.y} r="2" fill="#fff" stroke="#059669" strokeWidth="1.5" />
                      <circle cx={expensePoint.x} cy={expensePoint.y} r="2" fill="#fff" stroke="#f43f5e" strokeWidth="1.5" />
                    </>
                  )}
                  <text
                    x={point.x}
                    y="235"
                    textAnchor="middle"
                    fill="#8390a4"
                    fontSize="10"
                    fontWeight="700"
                  >
                    {formatAxisDate(point.date, granularity, locale)}
                  </text>
                </g>
              );
            })}
          </svg>
        </div>
      )}
    </section>
  );
}

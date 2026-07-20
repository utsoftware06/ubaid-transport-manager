"use client";

import {
  type DashboardMetricSummary,
  type DashboardOverallSummary,
  type DashboardSummary,
  formatAmount,
} from "./DashboardOverview";

type Props = {
  summary: DashboardSummary;
  loading: boolean;
};

type MetricCard = {
  label: string;
  value: string | number;
  helper: string;
  className: string;
  valueClass: string;
};

function metricCards(summary: DashboardMetricSummary): MetricCard[] {
  return [
    {
      label: "Total Trips",
      value: summary.totalTrips,
      helper: "Trips in this period",
      className: "border-blue-200 bg-blue-50",
      valueClass: "text-blue-700",
    },
    {
      label: "Total Freight",
      value: formatAmount(summary.totalFreight),
      helper: "Booked freight",
      className: "border-purple-200 bg-purple-50",
      valueClass: "text-purple-700",
    },
    {
      label: "Cash Received",
      value: formatAmount(summary.cashReceived),
      helper: "Received amount",
      className: "border-green-200 bg-green-50",
      valueClass: "text-green-700",
    },
    {
      label: "Expenses",
      value: formatAmount(summary.expenses),
      helper: "Trip expenses",
      className: "border-red-200 bg-red-50",
      valueClass: "text-red-700",
    },
    {
      label: "Net Profit",
      value: formatAmount(summary.netProfit),
      helper: "Freight minus expenses",
      className:
        summary.netProfit >= 0
          ? "border-green-200 bg-green-50"
          : "border-red-200 bg-red-50",
      valueClass: summary.netProfit >= 0 ? "text-green-700" : "text-red-700",
    },
    {
      label: "Pending Balance",
      value: formatAmount(summary.pendingBalance),
      helper: "Customer balance",
      className: "border-amber-200 bg-amber-50",
      valueClass: "text-amber-700",
    },
  ];
}

function overallCards(summary: DashboardOverallSummary): MetricCard[] {
  return [
    {
      label: "Active Trips",
      value: summary.activeTrips,
      helper: "Loading, transit or delivered",
      className: "border-indigo-200 bg-indigo-50",
      valueClass: "text-indigo-700",
    },
    {
      label: "Completed Trips",
      value: summary.completedTrips,
      helper: "Completed operations",
      className: "border-green-200 bg-green-50",
      valueClass: "text-green-700",
    },
    {
      label: "Cancelled Trips",
      value: summary.cancelledTrips,
      helper: "Cancelled trips",
      className: "border-red-200 bg-red-50",
      valueClass: "text-red-700",
    },
    {
      label: "Total Pending Balance",
      value: formatAmount(summary.totalPendingBalance),
      helper: "Overall pending amount",
      className: "border-amber-200 bg-amber-50",
      valueClass: "text-amber-700",
    },
  ];
}

function SkeletonGrid({ count }: { count: number }) {
  return (
    <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6">
      {Array.from({ length: count }).map((_, index) => (
        <div
          key={index}
          className="animate-pulse rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
        >
          <div className="h-3 w-24 rounded bg-gray-200" />
          <div className="mt-4 h-8 w-28 rounded bg-gray-200" />
          <div className="mt-4 h-3 w-full rounded bg-gray-200" />
        </div>
      ))}
    </div>
  );
}

function CardGrid({ cards }: { cards: MetricCard[] }) {
  return (
    <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6">
      {cards.map((card) => (
        <div
          key={card.label}
          className={`rounded-xl border p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md ${card.className}`}
        >
          <p className="text-xs font-extrabold uppercase tracking-wide text-gray-900">
            {card.label}
          </p>
          <p className={`mt-3 break-words text-2xl font-extrabold ${card.valueClass}`}>
            {card.value}
          </p>
          <p className="mt-3 text-sm font-semibold text-gray-900">
            {card.helper}
          </p>
        </div>
      ))}
    </div>
  );
}

export default function DashboardCards({ summary, loading }: Props) {
  return (
    <section className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h2 className="text-2xl font-bold text-gray-900">Filtered Period</h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Cards below follow the selected dashboard date filter.
        </p>
        <div className="mt-6">
          {loading ? (
            <SkeletonGrid count={6} />
          ) : (
            <CardGrid cards={metricCards(summary.filtered)} />
          )}
        </div>
      </div>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h2 className="text-2xl font-bold text-gray-900">Today</h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Today's trip, freight, cash and profit position.
        </p>
        <div className="mt-6">
          {loading ? (
            <SkeletonGrid count={6} />
          ) : (
            <CardGrid cards={metricCards(summary.today)} />
          )}
        </div>
      </div>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h2 className="text-2xl font-bold text-gray-900">This Month</h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Current month operational totals.
        </p>
        <div className="mt-6">
          {loading ? (
            <SkeletonGrid count={6} />
          ) : (
            <CardGrid cards={metricCards(summary.month)} />
          )}
        </div>
      </div>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h2 className="text-2xl font-bold text-gray-900">Overall</h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Overall active, completed, cancelled and pending balance position.
        </p>
        <div className="mt-6">
          {loading ? (
            <SkeletonGrid count={4} />
          ) : (
            <CardGrid cards={overallCards(summary.overall)} />
          )}
        </div>
      </div>
    </section>
  );
}
"use client";

import {
  type DashboardMetricSummary,
  type DashboardTrip,
  formatAmount,
} from "./DashboardOverview";

type Props = {
  trips: DashboardTrip[];
  summary: DashboardMetricSummary;
  loading: boolean;
};

type ChartItem = {
  label: string;
  value: number;
  className: string;
};

export default function IncomeExpenseChart({ trips, summary, loading }: Props) {
  const chartItems: ChartItem[] = [
    {
      label: "Freight",
      value: summary.totalFreight,
      className: "bg-blue-600",
    },
    {
      label: "Received",
      value: summary.cashReceived,
      className: "bg-green-600",
    },
    {
      label: "Expenses",
      value: summary.expenses,
      className: "bg-red-600",
    },
    {
      label: summary.netProfit >= 0 ? "Profit" : "Loss",
      value: Math.abs(summary.netProfit),
      className: summary.netProfit >= 0 ? "bg-indigo-600" : "bg-red-700",
    },
  ];

  const maxValue = Math.max(...chartItems.map((item) => item.value), 1);

  return (
    <section className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          Income vs Expense
        </h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Freight, received cash, expenses and profit for the selected period.
        </p>
      </div>

      {loading ? (
        <div className="space-y-4">
          {Array.from({ length: 4 }).map((_, index) => (
            <div key={index} className="animate-pulse">
              <div className="mb-2 h-3 w-24 rounded bg-gray-200" />
              <div className="h-8 w-full rounded bg-gray-200" />
            </div>
          ))}
        </div>
      ) : trips.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-extrabold text-gray-900">
            No chart data available.
          </p>
          <p className="mt-2 text-sm font-bold text-gray-900">
            Add trips or change the selected filter.
          </p>
        </div>
      ) : (
        <div className="space-y-5">
          {chartItems.map((item) => {
            const width =
              item.value > 0 ? Math.max((item.value / maxValue) * 100, 2) : 0;

            return (
              <div key={item.label}>
                <div className="mb-2 flex items-center justify-between gap-4">
                  <p className="text-sm font-extrabold text-gray-900">
                    {item.label}
                  </p>
                  <p className="text-sm font-extrabold text-gray-900">
                    {item.label === "Loss"
                      ? `-${formatAmount(item.value)}`
                      : formatAmount(item.value)}
                  </p>
                </div>

                <div className="h-9 overflow-hidden rounded-lg bg-gray-100">
                  <div
                    className={`flex h-full items-center justify-end rounded-lg px-3 text-xs font-bold text-white ${item.className}`}
                    style={{ width: `${width}%` }}
                  >
                    {Math.round(width)}%
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
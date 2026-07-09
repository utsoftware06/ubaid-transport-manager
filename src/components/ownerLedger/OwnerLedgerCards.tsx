"use client";

import type { OwnerLedgerSummary } from "./OwnerLedger";

type Props = {
  summary: OwnerLedgerSummary;
};

function formatAmount(value: number): string {
  return value.toLocaleString("en-PK", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

export default function OwnerLedgerCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Owners",
      value: summary.totalOwners.toLocaleString("en-PK"),
      color: "text-blue-700",
      bg: "bg-blue-50",
    },
    {
      title: "Total Trips",
      value: summary.totalTrips.toLocaleString("en-PK"),
      color: "text-indigo-700",
      bg: "bg-indigo-50",
    },
    {
      title: "Total Income",
      value: `Rs. ${formatAmount(summary.totalIncome)}`,
      color: "text-green-700",
      bg: "bg-green-50",
    },
    {
      title: "Total Expense",
      value: `Rs. ${formatAmount(summary.totalExpense)}`,
      color: "text-red-700",
      bg: "bg-red-50",
    },
    {
      title: "Net Profit",
      value: `Rs. ${formatAmount(summary.netProfit)}`,
      color:
        summary.netProfit >= 0
          ? "text-emerald-700"
          : "text-red-700",
      bg:
        summary.netProfit >= 0
          ? "bg-emerald-50"
          : "bg-red-50",
    },
  ];

  return (
    <section className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-5">
      {cards.map((card) => (
        <article
          key={card.title}
          className="rounded-xl border border-gray-200 bg-white p-5 shadow-md transition hover:shadow-lg"
        >
          <p className="text-sm font-semibold text-gray-600">
            {card.title}
          </p>

          <div
            className={`mt-4 rounded-lg ${card.bg} p-4`}
          >
            <p
              className={`text-2xl font-bold ${card.color}`}
            >
              {card.value}
            </p>
          </div>
        </article>
      ))}
    </section>
  );
}
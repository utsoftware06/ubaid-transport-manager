"use client";

import type { DriverLedgerSummary } from "./DriverLedger";

type Props = {
  summary: DriverLedgerSummary;
};

function formatAmount(value: number): string {
  return value.toLocaleString("en-PK", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

export default function DriverLedgerCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Trips",
      value: summary.totalTrips.toLocaleString("en-PK"),
    },
    {
      title: "Total Income",
      value: `Rs. ${formatAmount(summary.totalIncome)}`,
    },
    {
      title: "Total Expense",
      value: `Rs. ${formatAmount(summary.totalExpense)}`,
    },
    {
      title: "Net Balance",
      value: `Rs. ${formatAmount(summary.netBalance)}`,
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
      {cards.map((card) => (
        <div
          key={card.title}
          className="rounded-xl border border-gray-200 bg-white p-5 shadow-md"
        >
          <p className="text-sm font-semibold text-gray-700">{card.title}</p>
          <p className="mt-2 text-2xl font-bold text-gray-900">{card.value}</p>
        </div>
      ))}
    </div>
  );
}
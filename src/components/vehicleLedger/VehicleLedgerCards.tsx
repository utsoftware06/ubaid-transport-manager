"use client";

import type { VehicleLedgerSummary } from "./VehicleLedger";
import { formatAmount } from "./VehicleLedger";

type Props = {
  summary: VehicleLedgerSummary;
};

export default function VehicleLedgerCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Vehicles",
      value: summary.totalVehicles.toLocaleString("en-PK"),
    },
    {
      title: "Total Trips",
      value: summary.totalTrips.toLocaleString("en-PK"),
    },
    {
      title: "Total Income",
      value: formatAmount(summary.totalIncome),
    },
    {
      title: "Total Expense",
      value: formatAmount(summary.totalExpense),
    },
    {
      title: "Net Profit",
      value: formatAmount(summary.netProfit),
    },
  ];

  return (
    <section className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-5">
      {cards.map((card) => (
        <article
          key={card.title}
          className="rounded-xl border border-gray-200 bg-white p-5 shadow-md"
        >
          <p className="text-sm font-semibold text-gray-700">{card.title}</p>
          <p className="mt-3 text-2xl font-bold text-gray-900">
            {card.value}
          </p>
        </article>
      ))}
    </section>
  );
}
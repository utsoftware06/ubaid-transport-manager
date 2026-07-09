"use client";

import { formatAmount } from "./LoadingDetails";

type Props = {
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
};

export default function LoadingSummary({
  totalIncome,
  totalExpense,
  netProfit,
}: Props) {
  const cards = [
    {
      title: "Total Income",
      value: formatAmount(totalIncome),
      color: "text-green-700",
    },
    {
      title: "Total Expense",
      value: formatAmount(totalExpense),
      color: "text-red-700",
    },
    {
      title: "Net Profit",
      value: formatAmount(netProfit),
      color: netProfit >= 0 ? "text-blue-700" : "text-red-700",
    },
  ];

  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-gray-900">
          Trip Summary
        </h2>

        <p className="mt-1 text-sm font-medium text-gray-700">
          Income, expense aur final profit summary.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
        {cards.map((card) => (
          <div
            key={card.title}
            className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
          >
            <p className="text-sm font-semibold text-gray-700">
              {card.title}
            </p>

            <p className={`mt-3 text-2xl font-bold ${card.color}`}>
              {card.value}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
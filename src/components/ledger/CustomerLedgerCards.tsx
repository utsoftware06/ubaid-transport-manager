"use client";

import type { CustomerLedgerSummary } from "./CustomerLedger";

type Props = {
  summary: CustomerLedgerSummary;
};

function formatAmount(value: number): string {
  return value.toLocaleString("en-PK", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

export default function CustomerLedgerCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Bilty",
      value: summary.totalBookings.toLocaleString("en-PK"),
    },
    {
      title: "Total Freight",
      value: `Rs. ${formatAmount(summary.totalFreight)}`,
    },
    {
      title: "Received Amount",
      value: `Rs. ${formatAmount(summary.receivedAmount)}`,
    },
    {
      title: "Pending Balance",
      value: `Rs. ${formatAmount(summary.pendingAmount)}`,
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
      {cards.map((card) => (
        <div
          key={card.title}
          className="rounded-xl border border-gray-200 bg-white p-5 shadow-md transition hover:shadow-lg"
        >
          <p className="text-sm font-semibold text-gray-700">
            {card.title}
          </p>

          <p className="mt-3 text-2xl font-bold text-gray-900">
            {card.value}
          </p>
        </div>
      ))}
    </div>
  );
}
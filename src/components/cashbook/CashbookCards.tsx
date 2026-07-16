"use client";

import {
  ArrowDownCircle,
  ArrowUpCircle,
  Landmark,
  Wallet,
} from "lucide-react";
import { type CashbookSummary, formatAmount } from "./Cashbook";

type Props = {
  summary: CashbookSummary;
};

type Card = {
  title: string;
  value: string;
  color: string;
  bgColor: string;
  icon: React.ComponentType<{ className?: string }>;
};

export default function CashbookCards({ summary }: Props) {
  const closingPositive = summary.closingBalance >= 0;

  const cards: Card[] = [
    {
      title: "Opening Balance",
      value: formatAmount(summary.openingBalance),
      color: "text-blue-700",
      bgColor: "bg-blue-600",
      icon: Wallet,
    },
    {
      title: "Total Cash In",
      value: formatAmount(summary.totalCashIn),
      color: "text-green-700",
      bgColor: "bg-green-600",
      icon: ArrowDownCircle,
    },
    {
      title: "Total Cash Out",
      value: formatAmount(summary.totalCashOut),
      color: "text-red-700",
      bgColor: "bg-red-600",
      icon: ArrowUpCircle,
    },
    {
      title: "Closing Balance",
      value: formatAmount(summary.closingBalance),
      color: closingPositive ? "text-green-700" : "text-red-700",
      bgColor: closingPositive ? "bg-green-600" : "bg-red-600",
      icon: Landmark,
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-xl bg-white p-6 shadow-md">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-bold text-gray-900">
                  {card.title}
                </p>
                <h3 className={`mt-3 text-2xl font-extrabold ${card.color}`}>
                  {card.value}
                </h3>
              </div>

              <div
                className={`flex h-12 w-12 items-center justify-center rounded-full ${card.bgColor}`}
              >
                <Icon className="h-6 w-6 text-white" />
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
"use client";

import { Banknote, BriefcaseBusiness, CreditCard, Wrench } from "lucide-react";
import { type WorkshopSummary, formatAmount } from "./Workshop";

type Props = {
  summary: WorkshopSummary;
};

export default function WorkshopCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Jobs",
      value: String(summary.totalJobs),
      icon: BriefcaseBusiness,
      color: "bg-blue-600",
    },
    {
      title: "Total Workshop Cost",
      value: formatAmount(summary.totalCost),
      icon: Wrench,
      color: "bg-purple-600",
    },
    {
      title: "Paid Amount",
      value: formatAmount(summary.paidAmount),
      icon: Banknote,
      color: "bg-green-600",
    },
    {
      title: "Remaining Amount",
      value: formatAmount(summary.remainingAmount),
      icon: CreditCard,
      color: "bg-red-600",
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
                <h3 className="mt-3 text-2xl font-extrabold text-gray-900">
                  {card.value}
                </h3>
              </div>

              <div
                className={`flex h-12 w-12 items-center justify-center rounded-full ${card.color}`}
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
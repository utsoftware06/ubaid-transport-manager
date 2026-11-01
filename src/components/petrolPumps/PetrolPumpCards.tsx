"use client";

import {
  Banknote,
  Droplets,
  Fuel,
  Landmark,
  Wallet,
} from "lucide-react";
import { type PetrolPumpSummary, formatAmount } from "./PetrolPumps";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: PetrolPumpSummary;
};

export default function PetrolPumpCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const outstandingIsPositive = summary.totalOutstanding > 0;

  const cards = [
    {
      title: t("petrolPumps.cards.totalPumps"),
      value: String(summary.totalPumps),
      icon: Fuel,
      color: "bg-blue-600",
      textColor: "text-gray-900",
    },
    {
      title: t("petrolPumps.fields.openingBalance"),
      value: formatAmount(summary.totalOpeningBalance),
      icon: Landmark,
      color: "bg-indigo-600",
      textColor: "text-gray-900",
    },
    {
      title: t("petrolPumps.cards.totalDiesel"),
      value: formatAmount(summary.totalDiesel),
      icon: Droplets,
      color: "bg-purple-600",
      textColor: "text-gray-900",
    },
    {
      title: t("petrolPumps.cards.totalPaid"),
      value: formatAmount(summary.totalPaid),
      icon: Banknote,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: t("petrolPumps.cards.outstandingBalance"),
      value: formatAmount(summary.totalOutstanding),
      icon: Wallet,
      color: outstandingIsPositive ? "bg-red-600" : "bg-green-600",
      textColor: outstandingIsPositive ? "text-red-700" : "text-green-700",
    },
  ];

  return (
    <div dir={dir} className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-5">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-xl bg-white p-6 shadow-md">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-bold text-gray-900">
                  {card.title}
                </p>
                <h3 dir="ltr" className={`mt-3 text-2xl font-extrabold ${card.textColor}`}>
                  {card.value}
                </h3>
              </div>

              <div
                className={`flex h-11 w-11 items-center justify-center rounded-xl ${card.color}`}
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

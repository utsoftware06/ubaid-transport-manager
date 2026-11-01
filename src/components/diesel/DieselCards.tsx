"use client";

import { Banknote, Droplets, Fuel, ReceiptText, Wallet } from "lucide-react";
import {
  type DieselSummary,
  formatAmount,
  formatLiters,
} from "./Diesel";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: DieselSummary;
};

export default function DieselCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const cards = [
    {
      title: t("diesel.cards.totalEntries"),
      value: String(summary.totalEntries),
      icon: ReceiptText,
      color: "bg-blue-600",
      textColor: "text-gray-900",
    },
    {
      title: t("diesel.cards.totalLiters"),
      value: formatLiters(summary.totalLiters),
      icon: Droplets,
      color: "bg-purple-600",
      textColor: "text-gray-900",
    },
    {
      title: t("diesel.cards.totalAmount"),
      value: formatAmount(summary.totalAmount),
      icon: Fuel,
      color: "bg-indigo-600",
      textColor: "text-gray-900",
    },
    {
      title: t("diesel.cards.totalPaid"),
      value: formatAmount(summary.totalPaid),
      icon: Banknote,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: t("diesel.cards.totalRemaining"),
      value: formatAmount(summary.totalRemaining),
      icon: Wallet,
      color: "bg-red-600",
      textColor: "text-red-700",
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

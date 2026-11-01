"use client";

import {
  ArrowDownCircle,
  ArrowUpCircle,
  Landmark,
  Wallet,
} from "lucide-react";
import { type CashbookSummary, formatAmount } from "./Cashbook";
import { useLanguage } from "@/contexts/LanguageContext";

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
  const { t, dir } = useLanguage();
  const closingPositive = summary.closingBalance >= 0;

  const cards: Card[] = [
    {
      title: t("common.openingBalance"),
      value: formatAmount(summary.openingBalance),
      color: "text-blue-700",
      bgColor: "bg-blue-600",
      icon: Wallet,
    },
    {
      title: t("cashbook.cards.totalCashIn"),
      value: formatAmount(summary.totalCashIn),
      color: "text-green-700",
      bgColor: "bg-green-600",
      icon: ArrowDownCircle,
    },
    {
      title: t("cashbook.cards.totalCashOut"),
      value: formatAmount(summary.totalCashOut),
      color: "text-red-700",
      bgColor: "bg-red-600",
      icon: ArrowUpCircle,
    },
    {
      title: t("cashbook.closingBalance"),
      value: formatAmount(summary.closingBalance),
      color: closingPositive ? "text-green-700" : "text-red-700",
      bgColor: closingPositive ? "bg-green-600" : "bg-red-600",
      icon: Landmark,
    },
  ];

  return (
    <div dir={dir} className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-bold text-gray-900">
                  {card.title}
                </p>
                <h3 dir="ltr" className={`mt-3 text-2xl font-extrabold ${card.color}`}>
                  {card.value}
                </h3>
              </div>

              <div
                className={`flex h-11 w-11 items-center justify-center rounded-xl ${card.bgColor}`}
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

"use client";

import {
  ArrowDownCircle,
  ArrowUpCircle,
  Landmark,
  Users,
  Wallet,
  WalletCards,
} from "lucide-react";
import { type BrokerSummary, formatAmount } from "./Brokers";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: BrokerSummary;
};

export default function BrokerCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const cards = [
    {
      title: t("brokers.cards.totalBrokers"),
      value: String(summary.totalBrokers),
      icon: Users,
      color: "bg-blue-600",
      textColor: "text-gray-900",
    },
    {
      title: t("common.openingBalance"),
      value: formatAmount(summary.totalOpeningBalance),
      icon: Landmark,
      color: "bg-indigo-600",
      textColor: "text-gray-900",
    },
    {
      title: t("brokers.cards.totalPayable"),
      value: formatAmount(summary.totalPayable),
      icon: Wallet,
      color: "bg-red-600",
      textColor: "text-red-700",
    },
    {
      title: t("brokers.cards.totalAdvance"),
      value: formatAmount(summary.totalAdvance),
      icon: WalletCards,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: t("brokers.cards.paidToBrokers"),
      value: formatAmount(summary.totalPaymentsToBrokers),
      icon: ArrowUpCircle,
      color: "bg-orange-600",
      textColor: "text-gray-900",
    },
    {
      title: t("brokers.cards.receivedFromBrokers"),
      value: formatAmount(summary.totalReceivedFromBrokers),
      icon: ArrowDownCircle,
      color: "bg-emerald-600",
      textColor: "text-gray-900",
    },
  ];

  return (
    <div dir={dir} className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-bold text-gray-900">
                  {card.title}
                </p>
                <h3 className={`mt-3 text-xl font-extrabold ${card.textColor}`}>
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

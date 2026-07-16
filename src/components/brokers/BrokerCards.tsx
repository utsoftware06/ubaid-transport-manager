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

type Props = {
  summary: BrokerSummary;
};

export default function BrokerCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Brokers",
      value: String(summary.totalBrokers),
      icon: Users,
      color: "bg-blue-600",
      textColor: "text-gray-900",
    },
    {
      title: "Opening Balance",
      value: formatAmount(summary.totalOpeningBalance),
      icon: Landmark,
      color: "bg-indigo-600",
      textColor: "text-gray-900",
    },
    {
      title: "Total Payable",
      value: formatAmount(summary.totalPayable),
      icon: Wallet,
      color: "bg-red-600",
      textColor: "text-red-700",
    },
    {
      title: "Total Advance",
      value: formatAmount(summary.totalAdvance),
      icon: WalletCards,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: "Paid To Brokers",
      value: formatAmount(summary.totalPaymentsToBrokers),
      icon: ArrowUpCircle,
      color: "bg-orange-600",
      textColor: "text-gray-900",
    },
    {
      title: "Received From Brokers",
      value: formatAmount(summary.totalReceivedFromBrokers),
      icon: ArrowDownCircle,
      color: "bg-emerald-600",
      textColor: "text-gray-900",
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-6">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-xl bg-white p-6 shadow-md">
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
-"use client";

import { CreditCard, IndianRupee, ReceiptText, Wallet } from "lucide-react";
import {
  type CustomerLedgerSummary,
  formatAmount,
} from "./CustomerLedger";
type Props = {
  summary: CustomerLedgerSummary;
};

type Card = {
  title: string;
  value: string;
  icon: React.ComponentType<{ className?: string }>;
};

export default function CustomerLedgerCards({ summary }: Props) {
  const cards: Card[] = [
    {
      title: "Total Bookings",
      value: String(summary.totalBookings),
      icon: ReceiptText,
    },
    {
      title: "Total Freight",
      value: formatAmount(summary.totalFreight),
      icon: IndianRupee,
    },
    {
      title: "Received Amount",
      value: formatAmount(summary.receivedAmount),
      icon: Wallet,
    },
    {
      title: "Pending Amount",
      value: formatAmount(summary.pendingAmount),
      icon: CreditCard,
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

              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-blue-600">
                <Icon className="h-6 w-6 text-white" />
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
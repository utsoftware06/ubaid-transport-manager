"use client";

import { CreditCard, IndianRupee, ReceiptText, Wallet } from "lucide-react";
import {
  type CustomerLedgerSummary,
  formatCurrency,
} from "./CustomerLedger";
import { useLanguage } from "@/contexts/LanguageContext";
type Props = {
  summary: CustomerLedgerSummary;
};

type Card = {
  title: string;
  value: string;
  icon: React.ComponentType<{ className?: string }>;
};

export default function CustomerLedgerCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const cards: Card[] = [
    {
      title: t("customerLedger.summary.totalBookings"),
      value: String(summary.totalBookings),
      icon: ReceiptText,
    },
    {
      title: t("customerLedger.summary.totalFreight"),
      value: formatCurrency(summary.totalFreight),
      icon: IndianRupee,
    },
    {
      title: t("customerLedger.summary.receivedAmount"),
      value: formatCurrency(summary.receivedAmount),
      icon: Wallet,
    },
    {
      title: t("customerLedger.summary.pendingAmount"),
      value: formatCurrency(summary.pendingAmount),
      icon: CreditCard,
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
                <h3 className="mt-3 text-2xl font-extrabold text-gray-900">
                  {card.value}
                </h3>
              </div>

              <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-blue-600">
                <Icon className="h-6 w-6 text-white" />
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

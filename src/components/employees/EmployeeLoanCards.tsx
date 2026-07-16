"use client";

import {
  Banknote,
  CheckCircle2,
  CreditCard,
  ReceiptText,
  TrendingDown,
  Wallet,
} from "lucide-react";
import { type EmployeeLoanSummary, formatAmount } from "./EmployeeLoans";

type Props = {
  summary: EmployeeLoanSummary;
};

type CardItem = {
  title: string;
  value: string | number;
  icon: React.ComponentType<{ className?: string }>;
  iconBgClass: string;
  iconTextClass: string;
  valueClass: string;
};

export default function EmployeeLoanCards({ summary }: Props) {
  const cards: CardItem[] = [
    {
      title: "Total Loans",
      value: summary.totalLoans,
      icon: ReceiptText,
      iconBgClass: "bg-blue-100",
      iconTextClass: "text-blue-700",
      valueClass: "text-gray-900",
    },
    {
      title: "Total Loan Amount",
      value: formatAmount(summary.totalLoanAmount),
      icon: CreditCard,
      iconBgClass: "bg-purple-100",
      iconTextClass: "text-purple-700",
      valueClass: "text-purple-700",
    },
    {
      title: "Total Recovered",
      value: formatAmount(summary.totalRecovered),
      icon: Banknote,
      iconBgClass: "bg-green-100",
      iconTextClass: "text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: "Total Remaining",
      value: formatAmount(summary.totalRemaining),
      icon: TrendingDown,
      iconBgClass: "bg-red-100",
      iconTextClass: "text-red-700",
      valueClass: "text-red-700",
    },
    {
      title: "Active Loans",
      value: summary.activeLoans,
      icon: Wallet,
      iconBgClass: "bg-orange-100",
      iconTextClass: "text-orange-700",
      valueClass: "text-orange-700",
    },
    {
      title: "Completed Loans",
      value: summary.completedLoans,
      icon: CheckCircle2,
      iconBgClass: "bg-green-100",
      iconTextClass: "text-green-700",
      valueClass: "text-green-700",
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-6">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-xl bg-white p-6 shadow-md">
            <div
              className={`flex h-12 w-12 items-center justify-center rounded-full ${card.iconBgClass}`}
            >
              <Icon className={`h-6 w-6 ${card.iconTextClass}`} />
            </div>

            <p className="mt-4 text-sm font-bold text-gray-900">
              {card.title}
            </p>

            <p className={`mt-3 text-xl font-extrabold ${card.valueClass}`}>
              {card.value}
            </p>
          </div>
        );
      })}
    </div>
  );
}
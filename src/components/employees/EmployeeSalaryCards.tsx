"use client";

import {
  Banknote,
  CircleDollarSign,
  MinusCircle,
  PlusCircle,
  ReceiptText,
  TrendingDown,
  Wallet,
  WalletCards,
} from "lucide-react";
import { type EmployeeSalarySummary, formatAmount } from "./EmployeeSalary";

type Props = {
  summary: EmployeeSalarySummary;
};

export default function EmployeeSalaryCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Records",
      value: summary.totalRecords,
      icon: ReceiptText,
      iconClass: "bg-blue-100 text-blue-700",
      valueClass: "text-gray-900",
    },
    {
      title: "Basic Salary",
      value: formatAmount(summary.totalBasicSalary),
      icon: Wallet,
      iconClass: "bg-purple-100 text-purple-700",
      valueClass: "text-purple-700",
    },
    {
      title: "Bonus",
      value: formatAmount(summary.totalBonus),
      icon: PlusCircle,
      iconClass: "bg-green-100 text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: "Deduction",
      value: formatAmount(summary.totalDeduction),
      icon: MinusCircle,
      iconClass: "bg-red-100 text-red-700",
      valueClass: "text-red-700",
    },
    {
      title: "Loan Recovery",
      value: formatAmount(summary.totalLoanRecovery),
      icon: TrendingDown,
      iconClass: "bg-orange-100 text-orange-700",
      valueClass: "text-orange-700",
    },
    {
      title: "Net Salary",
      value: formatAmount(summary.totalNetSalary),
      icon: CircleDollarSign,
      iconClass: "bg-blue-100 text-blue-700",
      valueClass: "text-blue-700",
    },
    {
      title: "Paid",
      value: formatAmount(summary.totalPaid),
      icon: Banknote,
      iconClass: "bg-green-100 text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: "Remaining",
      value: formatAmount(summary.totalRemaining),
      icon: WalletCards,
      iconClass: "bg-red-100 text-red-700",
      valueClass: "text-red-700",
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-xl bg-white p-6 shadow-md">
            <div
              className={`flex h-12 w-12 items-center justify-center rounded-full ${card.iconClass}`}
            >
              <Icon className="h-6 w-6" />
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
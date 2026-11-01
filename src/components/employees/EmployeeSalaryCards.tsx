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
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: EmployeeSalarySummary;
};

export default function EmployeeSalaryCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const cards = [
    {
      title: t("employeeSalary.cards.totalRecords"),
      value: summary.totalRecords,
      icon: ReceiptText,
      iconClass: "bg-blue-100 text-blue-700",
      valueClass: "text-gray-900",
    },
    {
      title: t("employeeSalary.fields.basicSalary"),
      value: formatAmount(summary.totalBasicSalary),
      icon: Wallet,
      iconClass: "bg-purple-100 text-purple-700",
      valueClass: "text-purple-700",
    },
    {
      title: t("employeeSalary.fields.bonus"),
      value: formatAmount(summary.totalBonus),
      icon: PlusCircle,
      iconClass: "bg-green-100 text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: t("employeeSalary.fields.deduction"),
      value: formatAmount(summary.totalDeduction),
      icon: MinusCircle,
      iconClass: "bg-red-100 text-red-700",
      valueClass: "text-red-700",
    },
    {
      title: t("employeeSalary.fields.loanRecovery"),
      value: formatAmount(summary.totalLoanRecovery),
      icon: TrendingDown,
      iconClass: "bg-orange-100 text-orange-700",
      valueClass: "text-orange-700",
    },
    {
      title: t("employeeSalary.fields.netSalary"),
      value: formatAmount(summary.totalNetSalary),
      icon: CircleDollarSign,
      iconClass: "bg-blue-100 text-blue-700",
      valueClass: "text-blue-700",
    },
    {
      title: t("common.paid"),
      value: formatAmount(summary.totalPaid),
      icon: Banknote,
      iconClass: "bg-green-100 text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: t("common.remaining"),
      value: formatAmount(summary.totalRemaining),
      icon: WalletCards,
      iconClass: "bg-red-100 text-red-700",
      valueClass: "text-red-700",
    },
  ];

  return (
    <div dir={dir} className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
            <div
              className={`flex h-11 w-11 items-center justify-center rounded-xl ${card.iconClass}`}
            >
              <Icon className="h-6 w-6" />
            </div>
            <p className="mt-4 text-sm font-bold text-gray-900">
              {card.title}
            </p>
            <p dir="ltr" className={`mt-3 text-xl font-extrabold ${card.valueClass}`}>
              {card.value}
            </p>
          </div>
        );
      })}
    </div>
  );
}

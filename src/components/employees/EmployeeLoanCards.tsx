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
import { useLanguage } from "@/contexts/LanguageContext";

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
  const { t, dir } = useLanguage();
  const cards: CardItem[] = [
    {
      title: t("employeeLoans.cards.totalLoans"),
      value: summary.totalLoans,
      icon: ReceiptText,
      iconBgClass: "bg-blue-100",
      iconTextClass: "text-blue-700",
      valueClass: "text-gray-900",
    },
    {
      title: t("employeeLoans.cards.totalLoanAmount"),
      value: formatAmount(summary.totalLoanAmount),
      icon: CreditCard,
      iconBgClass: "bg-purple-100",
      iconTextClass: "text-purple-700",
      valueClass: "text-purple-700",
    },
    {
      title: t("employeeLoans.cards.totalRecovered"),
      value: formatAmount(summary.totalRecovered),
      icon: Banknote,
      iconBgClass: "bg-green-100",
      iconTextClass: "text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: t("employeeLoans.cards.totalRemaining"),
      value: formatAmount(summary.totalRemaining),
      icon: TrendingDown,
      iconBgClass: "bg-red-100",
      iconTextClass: "text-red-700",
      valueClass: "text-red-700",
    },
    {
      title: t("employeeLoans.cards.activeLoans"),
      value: summary.activeLoans,
      icon: Wallet,
      iconBgClass: "bg-orange-100",
      iconTextClass: "text-orange-700",
      valueClass: "text-orange-700",
    },
    {
      title: t("employeeLoans.cards.completedLoans"),
      value: summary.completedLoans,
      icon: CheckCircle2,
      iconBgClass: "bg-green-100",
      iconTextClass: "text-green-700",
      valueClass: "text-green-700",
    },
  ];

  return (
    <div dir={dir} className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
            <div
                className={`flex h-11 w-11 items-center justify-center rounded-xl ${card.iconBgClass}`}
            >
              <Icon className={`h-6 w-6 ${card.iconTextClass}`} />
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

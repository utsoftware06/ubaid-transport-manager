"use client";

import {
  Banknote,
  CheckCircle2,
  CircleDollarSign,
  CreditCard,
  ShieldX,
  TrendingDown,
  Users,
  Wallet,
} from "lucide-react";
import { type EmployeeSummary, formatAmount } from "./Employees";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: EmployeeSummary;
};

export default function EmployeeCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const cards = [
    {
      title: t("employees.cards.totalEmployees"),
      value: String(summary.totalEmployees),
      icon: Users,
      color: "bg-blue-600",
      textColor: "text-gray-900",
    },
    {
      title: t("employees.cards.activeEmployees"),
      value: String(summary.activeEmployees),
      icon: CheckCircle2,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: t("employees.cards.inactiveEmployees"),
      value: String(summary.inactiveEmployees),
      icon: ShieldX,
      color: "bg-red-600",
      textColor: "text-red-700",
    },
    {
      title: t("employees.fields.monthlySalary"),
      value: formatAmount(summary.totalMonthlySalary),
      icon: Wallet,
      color: "bg-indigo-600",
      textColor: "text-gray-900",
    },
    {
      title: t("employees.cards.totalLoan"),
      value: formatAmount(summary.totalLoan),
      icon: CreditCard,
      color: "bg-purple-600",
      textColor: "text-purple-700",
    },
    {
      title: t("employees.cards.recoveredLoan"),
      value: formatAmount(summary.recoveredLoan),
      icon: Banknote,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: t("employees.cards.remainingLoan"),
      value: formatAmount(summary.remainingLoan),
      icon: TrendingDown,
      color: "bg-red-600",
      textColor: "text-red-700",
    },
    {
      title: t("employees.cards.remainingSalary"),
      value: formatAmount(summary.remainingSalary),
      icon: CircleDollarSign,
      color: "bg-orange-600",
      textColor: "text-orange-700",
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

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

type Props = {
  summary: EmployeeSummary;
};

export default function EmployeeCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Employees",
      value: String(summary.totalEmployees),
      icon: Users,
      color: "bg-blue-600",
      textColor: "text-gray-900",
    },
    {
      title: "Active Employees",
      value: String(summary.activeEmployees),
      icon: CheckCircle2,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: "Inactive Employees",
      value: String(summary.inactiveEmployees),
      icon: ShieldX,
      color: "bg-red-600",
      textColor: "text-red-700",
    },
    {
      title: "Monthly Salary",
      value: formatAmount(summary.totalMonthlySalary),
      icon: Wallet,
      color: "bg-indigo-600",
      textColor: "text-gray-900",
    },
    {
      title: "Total Loan",
      value: formatAmount(summary.totalLoan),
      icon: CreditCard,
      color: "bg-purple-600",
      textColor: "text-purple-700",
    },
    {
      title: "Recovered Loan",
      value: formatAmount(summary.recoveredLoan),
      icon: Banknote,
      color: "bg-green-600",
      textColor: "text-green-700",
    },
    {
      title: "Remaining Loan",
      value: formatAmount(summary.remainingLoan),
      icon: TrendingDown,
      color: "bg-red-600",
      textColor: "text-red-700",
    },
    {
      title: "Remaining Salary",
      value: formatAmount(summary.remainingSalary),
      icon: CircleDollarSign,
      color: "bg-orange-600",
      textColor: "text-orange-700",
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
                <h3 className={`mt-3 text-2xl font-extrabold ${card.textColor}`}>
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
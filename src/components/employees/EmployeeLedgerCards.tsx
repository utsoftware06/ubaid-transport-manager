"use client";

import {
  ArrowDownCircle,
  ArrowUpCircle,
  BadgeDollarSign,
  ReceiptText,
  Users,
  WalletCards,
} from "lucide-react";
import { type EmployeeLedgerSummary, formatAmount } from "./EmployeeLedger";

type Props = {
  summary: EmployeeLedgerSummary;
};

export default function EmployeeLedgerCards({ summary }: Props) {
  const cards = [
    {
      title: "Total Employees",
      value: summary.totalEmployees,
      icon: Users,
      iconClass: "bg-blue-100 text-blue-700",
      valueClass: "text-gray-900",
    },
    {
      title: "Total Transactions",
      value: summary.totalTransactions,
      icon: ReceiptText,
      iconClass: "bg-indigo-100 text-indigo-700",
      valueClass: "text-indigo-700",
    },
    {
      title: "Total Debit",
      value: formatAmount(summary.totalDebit),
      icon: ArrowDownCircle,
      iconClass: "bg-red-100 text-red-700",
      valueClass: "text-red-700",
    },
    {
      title: "Total Credit",
      value: formatAmount(summary.totalCredit),
      icon: ArrowUpCircle,
      iconClass: "bg-green-100 text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: "Company Payable",
      value: formatAmount(summary.companyPayable),
      icon: WalletCards,
      iconClass: "bg-orange-100 text-orange-700",
      valueClass: "text-orange-700",
    },
    {
      title: "Employee Receivable",
      value: formatAmount(summary.employeeReceivable),
      icon: BadgeDollarSign,
      iconClass: "bg-purple-100 text-purple-700",
      valueClass: "text-purple-700",
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-6">
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
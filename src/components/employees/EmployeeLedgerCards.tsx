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
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: EmployeeLedgerSummary;
};

export default function EmployeeLedgerCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const cards = [
    {
      title: t("employeeLedger.cards.totalEmployees"),
      value: summary.totalEmployees,
      icon: Users,
      iconClass: "bg-blue-100 text-blue-700",
      valueClass: "text-gray-900",
    },
    {
      title: t("employeeLedger.cards.totalTransactions"),
      value: summary.totalTransactions,
      icon: ReceiptText,
      iconClass: "bg-indigo-100 text-indigo-700",
      valueClass: "text-indigo-700",
    },
    {
      title: t("employeeLedger.cards.totalDebit"),
      value: formatAmount(summary.totalDebit),
      icon: ArrowDownCircle,
      iconClass: "bg-red-100 text-red-700",
      valueClass: "text-red-700",
    },
    {
      title: t("employeeLedger.cards.totalCredit"),
      value: formatAmount(summary.totalCredit),
      icon: ArrowUpCircle,
      iconClass: "bg-green-100 text-green-700",
      valueClass: "text-green-700",
    },
    {
      title: t("employeeLedger.cards.companyPayable"),
      value: formatAmount(summary.companyPayable),
      icon: WalletCards,
      iconClass: "bg-orange-100 text-orange-700",
      valueClass: "text-orange-700",
    },
    {
      title: t("employeeLedger.cards.employeeReceivable"),
      value: formatAmount(summary.employeeReceivable),
      icon: BadgeDollarSign,
      iconClass: "bg-purple-100 text-purple-700",
      valueClass: "text-purple-700",
    },
  ];

  return (
    <div dir={dir} className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
      {cards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
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

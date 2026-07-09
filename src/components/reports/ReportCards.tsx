"use client";

import { useEffect, useState } from "react";
import { BadgeDollarSign, TrendingUp, Truck, Wallet } from "lucide-react";
import { supabase } from "@/lib/supabase/client";

type ReportTotals = {
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
  totalTrips: number;
};

function formatCurrency(amount: number) {
  return `Rs. ${amount.toLocaleString("en-PK")}`;
}

export default function ReportCards() {
  const [totals, setTotals] = useState<ReportTotals>({
    totalIncome: 0,
    totalExpense: 0,
    netProfit: 0,
    totalTrips: 0,
  });

  useEffect(() => {
    async function loadTotals() {
      const { data: loadings } = await supabase
        .from("loadings")
        .select("id, booking_id");

      const { data: bookings } = await supabase
        .from("bookings")
        .select("id, freight");

      const { data: expenses } = await supabase
        .from("expenses")
        .select("id, loading_id");

      const { data: expenseItems } = await supabase
        .from("expense_items")
        .select("expense_id, amount");

      const bookingMap = new Map(
        (bookings ?? []).map((booking) => [
          booking.id,
          Number(booking.freight || 0),
        ])
      );

      const expenseMap = new Map<number, number>();

      (expenses ?? []).forEach((expense) => {
        const total = (expenseItems ?? [])
          .filter((item) => item.expense_id === expense.id)
          .reduce((sum, item) => sum + Number(item.amount || 0), 0);

        expenseMap.set(
          expense.loading_id,
          (expenseMap.get(expense.loading_id) || 0) + total
        );
      });

      const totalIncome = (loadings ?? []).reduce(
        (sum, loading) => sum + (bookingMap.get(loading.booking_id) || 0),
        0
      );

      const totalExpense = Array.from(expenseMap.values()).reduce(
        (sum, value) => sum + value,
        0
      );

      setTotals({
        totalIncome,
        totalExpense,
        netProfit: totalIncome - totalExpense,
        totalTrips: loadings?.length ?? 0,
      });
    }

    loadTotals();
  }, []);

  const reportCards = [
    {
      title: "Total Income",
      value: formatCurrency(totals.totalIncome),
      icon: BadgeDollarSign,
    },
    {
      title: "Total Expense",
      value: formatCurrency(totals.totalExpense),
      icon: Wallet,
    },
    {
      title: "Net Profit",
      value: formatCurrency(totals.netProfit),
      icon: TrendingUp,
    },
    {
      title: "Total Trips",
      value: totals.totalTrips.toLocaleString("en-PK"),
      icon: Truck,
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
      {reportCards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-xl bg-white p-6 shadow-md">
            <div className="mb-5 flex h-12 w-12 items-center justify-center rounded-full bg-blue-600">
              <Icon className="h-6 w-6 text-white" />
            </div>

            <p className="text-sm font-semibold text-gray-500">{card.title}</p>
            <h3 className="mt-2 text-3xl font-bold text-gray-900">
              {card.value}
            </h3>
          </div>
        );
      })}
    </div>
  );
}
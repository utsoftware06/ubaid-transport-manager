"use client";

import { useEffect, useState } from "react";
import { BadgeDollarSign, TrendingUp, Truck, Wallet } from "lucide-react";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import type { ReportFilterValues } from "./ReportFilters";

type ReportTotals = {
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
  totalTrips: number;
};

type RelatedRecord<T> = T | T[] | null;
type LoadingSummaryRecord = {
  loading_date: string;
  vehicle_id: string;
  driver_id: string;
  route: string | null;
  bookings: RelatedRecord<{ freight: number | string | null }>;
  expenses: Array<{
    expense_items: Array<{ amount: number | string | null }> | null;
  }> | null;
};

function relationOne<T>(value: RelatedRecord<T>): T | null {
  return Array.isArray(value) ? value[0] ?? null : value;
}

function numberValue(value: number | string | null | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatCurrency(amount: number) {
  return `Rs. ${amount.toLocaleString("en-PK")}`;
}

export default function ReportCards({ filters }: { filters: ReportFilterValues }) {
  const { t, dir } = useLanguage();
  const [totals, setTotals] = useState<ReportTotals>({
    totalIncome: 0,
    totalExpense: 0,
    netProfit: 0,
    totalTrips: 0,
  });
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let isMounted = true;
    async function loadTotals() {
      setIsLoading(true);
      setErrorMessage("");
      const { data, error } = await supabase
        .from("loadings")
        .select(`loading_date, vehicle_id, driver_id, route, bookings(freight), expenses(expense_items(amount))`);
      if (!isMounted) return;
      if (error) {
        console.error("Unable to load report totals:", error);
        setErrorMessage(t("reports.messages.loadError"));
        setIsLoading(false);
        return;
      }
      const routeSearch = filters.route.trim().toLowerCase();
      const loadings = ((data ?? []) as unknown as LoadingSummaryRecord[]).filter(
        (loading) =>
          (!filters.fromDate || loading.loading_date >= filters.fromDate) &&
          (!filters.toDate || loading.loading_date <= filters.toDate) &&
          (!filters.vehicle || loading.vehicle_id === filters.vehicle) &&
          (!filters.driver || loading.driver_id === filters.driver) &&
          (!routeSearch || (loading.route ?? "").toLowerCase().includes(routeSearch))
      );
      const totalIncome = loadings.reduce(
        (sum, loading) =>
          sum + numberValue(relationOne(loading.bookings)?.freight),
        0
      );
      const totalExpense = loadings.reduce(
        (sum, loading) =>
          sum +
          (loading.expenses ?? []).reduce(
            (expenseSum, expense) =>
              expenseSum +
              (expense.expense_items ?? []).reduce(
                (itemSum, item) => itemSum + numberValue(item.amount),
                0
              ),
            0
          ),
        0
      );

      setTotals({
        totalIncome,
        totalExpense,
        netProfit: totalIncome - totalExpense,
        totalTrips: loadings.length,
      });
      setIsLoading(false);
    }

    void loadTotals();
    return () => {
      isMounted = false;
    };
  }, [filters, t]);

  const reportCards = [
    {
      title: t("reports.summary.totalIncome"),
      value: formatCurrency(totals.totalIncome),
      icon: BadgeDollarSign,
    },
    {
      title: t("reports.summary.totalExpense"),
      value: formatCurrency(totals.totalExpense),
      icon: Wallet,
    },
    {
      title: t("reports.summary.netProfit"),
      value: formatCurrency(totals.netProfit),
      icon: TrendingUp,
    },
    {
      title: t("reports.summary.totalTrips"),
      value: totals.totalTrips.toLocaleString("en-PK"),
      icon: Truck,
    },
  ];

  return (
    <div dir={dir}>
      {isLoading && (
        <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("reports.loading")}
        </div>
      )}
      {errorMessage && (
        <div className="mb-4 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}
      <div aria-busy={isLoading} className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
      {reportCards.map((card) => {
        const Icon = card.icon;

        return (
          <div key={card.title} className="rounded-xl bg-white p-6 shadow-md">
            <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl bg-blue-600">
              <Icon className="h-6 w-6 text-white" />
            </div>

            <p className="text-sm font-bold text-gray-900">{card.title}</p>
            <h3 dir="ltr" className="mt-2 text-3xl font-bold text-gray-900">
              {card.value}
            </h3>
          </div>
        );
      })}
      </div>
    </div>
  );
}

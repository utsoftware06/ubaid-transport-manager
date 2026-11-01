"use client";

import { type TripSummary, formatAmount } from "./TripManagement";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: TripSummary;
  loading: boolean;
};

type CardItem = {
  label: string;
  value: string | number;
  helper: string;
  className: string;
  valueClass: string;
};

export default function TripCards({ summary, loading }: Props) {
  const { t, dir } = useLanguage();
  const cards: CardItem[] = [
    {
      label: t("tripManagement.cards.totalTrips"),
      value: summary.totalTrips,
      helper: t("tripManagement.cards.totalTripsHelp"),
      className: "border-blue-200 bg-blue-50",
      valueClass: "text-blue-700",
    },
    {
      label: t("tripManagement.cards.planned"),
      value: summary.plannedTrips,
      helper: t("tripManagement.cards.plannedHelp"),
      className: "border-gray-200 bg-gray-50",
      valueClass: "text-gray-900",
    },
    {
      label: t("tripManagement.cards.active"),
      value: summary.activeTrips,
      helper: t("tripManagement.cards.activeHelp"),
      className: "border-indigo-200 bg-indigo-50",
      valueClass: "text-indigo-700",
    },
    {
      label: t("tripManagement.cards.completed"),
      value: summary.completedTrips,
      helper: t("tripManagement.cards.completedHelp"),
      className: "border-green-200 bg-green-50",
      valueClass: "text-green-700",
    },
    {
      label: t("tripManagement.cards.cancelled"),
      value: summary.cancelledTrips,
      helper: t("tripManagement.cards.cancelledHelp"),
      className: "border-red-200 bg-red-50",
      valueClass: "text-red-700",
    },
    {
      label: t("tripManagement.cards.totalFreight"),
      value: formatAmount(summary.totalFreight),
      helper: t("tripManagement.cards.totalFreightHelp"),
      className: "border-purple-200 bg-purple-50",
      valueClass: "text-purple-700",
    },
    {
      label: t("tripManagement.cards.totalReceived"),
      value: formatAmount(summary.totalReceived),
      helper: t("tripManagement.cards.totalReceivedHelp"),
      className: "border-green-200 bg-green-50",
      valueClass: "text-green-700",
    },
    {
      label: t("tripManagement.cards.totalBalance"),
      value: formatAmount(summary.totalBalance),
      helper: t("tripManagement.cards.totalBalanceHelp"),
      className: "border-amber-200 bg-amber-50",
      valueClass: "text-amber-700",
    },
    {
      label: t("tripManagement.cards.totalExpenses"),
      value: formatAmount(summary.totalExpenses),
      helper: t("tripManagement.cards.totalExpensesHelp"),
      className: "border-red-200 bg-red-50",
      valueClass: "text-red-700",
    },
    {
      label: t("tripManagement.cards.netProfit"),
      value: formatAmount(summary.totalProfit),
      helper: t("tripManagement.cards.netProfitHelp"),
      className:
        summary.totalProfit >= 0
          ? "border-green-200 bg-green-50"
          : "border-red-200 bg-red-50",
      valueClass: summary.totalProfit >= 0 ? "text-green-700" : "text-red-700",
    },
  ];

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {t("tripManagement.cards.title")}
        </h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          {t("tripManagement.cards.description")}
        </p>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
          {Array.from({ length: 10 }).map((_, index) => (
            <div
              key={index}
              className="animate-pulse rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
            >
              <div className="h-3 w-24 rounded bg-gray-200" />
              <div className="mt-4 h-8 w-28 rounded bg-gray-200" />
              <div className="mt-4 h-3 w-full rounded bg-gray-200" />
            </div>
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
          {cards.map((card) => (
            <div
              key={card.label}
              className={`rounded-xl border p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md ${card.className}`}
            >
              <p className="text-xs font-extrabold uppercase tracking-wide text-gray-900">
                {card.label}
              </p>
              <p
                dir="ltr"
                className={`mt-3 break-words text-2xl font-extrabold ${card.valueClass}`}
              >
                {card.value}
              </p>
              <p className="mt-3 text-sm font-semibold text-gray-900">
                {card.helper}
              </p>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

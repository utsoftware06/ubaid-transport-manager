"use client";

import { formatAmount } from "./LoadingDetails";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
};

export default function LoadingSummary({
  totalIncome,
  totalExpense,
  netProfit,
}: Props) {
  const { t, dir } = useLanguage();
  const cards = [
    {
      title: t("loadings.details.totalIncome"),
      value: formatAmount(totalIncome),
      color: "text-green-700",
    },
    {
      title: t("loadings.details.totalExpense"),
      value: formatAmount(totalExpense),
      color: "text-red-700",
    },
    {
      title: t("dashboard.metrics.netProfit"),
      value: formatAmount(netProfit),
      color: netProfit >= 0 ? "text-blue-700" : "text-red-700",
    },
  ];

  return (
    <section dir={dir} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <div className="mb-5">
        <h2 className="text-lg font-extrabold text-slate-900">
          {t("loadings.details.tripSummary")}
        </h2>

        <p className="mt-1 text-sm font-medium text-slate-600">
          {t("loadings.details.summaryDescription")}
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
        {cards.map((card) => (
          <div
            key={card.title}
            className="rounded-xl border border-slate-200 bg-slate-50/60 p-4 shadow-sm"
          >
            <p className="text-sm font-semibold text-slate-600">
              {card.title}
            </p>

            <p className={`mt-2 text-xl font-extrabold ${card.color}`} dir="ltr">
              {card.value}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}

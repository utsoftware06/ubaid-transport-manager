"use client";

import {
  type VehicleDocumentSummary,
  formatAmount,
} from "./VehicleDocuments";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  summary: VehicleDocumentSummary;
  loading: boolean;
};

type CardItem = {
  label: string;
  value: string | number;
  helperText: string;
  accentClass: string;
  valueClass: string;
};

export default function VehicleDocumentCards({ summary, loading }: Props) {
  const { t, dir } = useLanguage();
  const cards: CardItem[] = [
    {
      label: t("vehicleDocuments.cards.totalDocuments"),
      value: summary.totalDocuments,
      helperText: t("vehicleDocuments.cards.allRecorded"),
      accentClass: "border-blue-200 bg-blue-50",
      valueClass: "text-blue-700",
    },
    {
      label: t("vehicleDocuments.statuses.active"),
      value: summary.activeDocuments,
      helperText: t("vehicleDocuments.cards.currentlyValid"),
      accentClass: "border-green-200 bg-green-50",
      valueClass: "text-green-700",
    },
    {
      label: t("vehicleDocuments.statuses.expiringSoon"),
      value: summary.expiringSoonDocuments,
      helperText: t("vehicleDocuments.cards.needingAttention"),
      accentClass: "border-amber-200 bg-amber-50",
      valueClass: "text-amber-700",
    },
    {
      label: t("vehicleDocuments.statuses.expired"),
      value: summary.expiredDocuments,
      helperText: t("vehicleDocuments.cards.renewalRequired"),
      accentClass: "border-red-200 bg-red-50",
      valueClass: "text-red-700",
    },
    {
      label: t("vehicleDocuments.statuses.permanent"),
      value: summary.permanentDocuments,
      helperText: t("vehicleDocuments.cards.noExpiry"),
      accentClass: "border-gray-200 bg-gray-50",
      valueClass: "text-gray-900",
    },
    {
      label: t("vehicleDocuments.cards.totalFees"),
      value: formatAmount(summary.totalFees),
      helperText: t("vehicleDocuments.cards.totalCost"),
      accentClass: "border-indigo-200 bg-indigo-50",
      valueClass: "text-indigo-700",
    },
  ];

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {t("vehicleDocuments.cards.title")}
        </h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          {t("vehicleDocuments.cards.description")}
        </p>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6">
          {Array.from({ length: 6 }).map((_, index) => (
            <div
              key={index}
              className="animate-pulse rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
            >
              <div className="h-3 w-28 rounded bg-gray-200" />
              <div className="mt-4 h-8 w-20 rounded bg-gray-200" />
              <div className="mt-4 h-3 w-full rounded bg-gray-200" />
              <div className="mt-2 h-3 w-3/4 rounded bg-gray-200" />
            </div>
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6">
          {cards.map((card) => (
            <div
              key={card.label}
              className={`rounded-xl border p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md ${card.accentClass}`}
            >
              <p className="text-xs font-extrabold uppercase tracking-wide text-gray-900">
                {card.label}
              </p>

              <p dir="ltr" className={`mt-3 text-3xl font-extrabold ${card.valueClass}`}>
                {card.value}
              </p>

              <p className="mt-3 text-sm font-semibold leading-5 text-gray-900">
                {card.helperText}
              </p>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

"use client";

import {
  type VehicleDocumentSummary,
  formatAmount,
} from "./VehicleDocuments";

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
  const cards: CardItem[] = [
    {
      label: "Total Documents",
      value: summary.totalDocuments,
      helperText: "All recorded vehicle documents",
      accentClass: "border-blue-200 bg-blue-50",
      valueClass: "text-blue-700",
    },
    {
      label: "Active",
      value: summary.activeDocuments,
      helperText: "Currently valid documents",
      accentClass: "border-green-200 bg-green-50",
      valueClass: "text-green-700",
    },
    {
      label: "Expiring Soon",
      value: summary.expiringSoonDocuments,
      helperText: "Documents needing attention",
      accentClass: "border-amber-200 bg-amber-50",
      valueClass: "text-amber-700",
    },
    {
      label: "Expired",
      value: summary.expiredDocuments,
      helperText: "Renewal required",
      accentClass: "border-red-200 bg-red-50",
      valueClass: "text-red-700",
    },
    {
      label: "Permanent",
      value: summary.permanentDocuments,
      helperText: "No expiry date",
      accentClass: "border-gray-200 bg-gray-50",
      valueClass: "text-gray-900",
    },
    {
      label: "Total Fees",
      value: formatAmount(summary.totalFees),
      helperText: "Total recorded document cost",
      accentClass: "border-indigo-200 bg-indigo-50",
      valueClass: "text-indigo-700",
    },
  ];

  return (
    <section className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          Vehicle Document Summary
        </h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Overview of document status, expiry and recorded fees.
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

              <p className={`mt-3 text-3xl font-extrabold ${card.valueClass}`}>
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
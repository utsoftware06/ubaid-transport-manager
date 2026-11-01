"use client";

import { Building2, CircleCheck, CircleX, UsersRound } from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";

type PartySummaryCardsProps = {
  total: number;
  active: number;
  inactive: number;
  cities: number;
};

export default function PartySummaryCards({
  total,
  active,
  inactive,
  cities,
}: PartySummaryCardsProps) {
  const { t } = useLanguage();
  const cards = [
    { label: t("parties.cards.total"), value: total, icon: UsersRound },
    { label: t("parties.cards.active"), value: active, icon: CircleCheck },
    { label: t("parties.cards.inactive"), value: inactive, icon: CircleX },
    { label: t("parties.cards.cities"), value: cities, icon: Building2 },
  ];

  return (
    <section
      aria-label={t("parties.cards.summary")}
      className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4"
    >
      {cards.map(({ label, value, icon: Icon }) => (
        <article
          key={label}
          className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
        >
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="font-semibold text-slate-700">{label}</p>
              <p dir="ltr" className="mt-2 text-3xl font-extrabold text-slate-900">
                {value}
              </p>
            </div>
            <span className="rounded-xl bg-blue-50 p-3 text-blue-700">
              <Icon className="h-6 w-6" aria-hidden="true" />
            </span>
          </div>
        </article>
      ))}
    </section>
  );
}

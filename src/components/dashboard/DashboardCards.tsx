"use client";

import {
  CarFront,
  UsersRound,
  type LucideIcon,
} from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  loading: boolean;
  vehicleCount: number | null;
  partyCount: number | null;
  countsLoading: boolean;
};

type MetricCard = {
  label: string;
  value: string | number;
  helper: string;
  icon: LucideIcon;
  tone: string;
  iconTone: string;
  valueTone: string;
  decorativeTone: string;
  loading?: boolean;
};

function SkeletonGrid() {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {Array.from({ length: 2 }).map((_, index) => (
        <div
          key={index}
          className="h-[150px] animate-pulse rounded-[16px] border border-slate-200 bg-white p-4"
        >
          <div className="flex items-center gap-2.5"><div className="h-[46px] w-[46px] rounded-xl bg-slate-100" /><div className="h-4 w-24 rounded bg-slate-100" /></div>
          <div className="mt-[7px] h-7 w-32 rounded bg-slate-100" />
          <div className="mt-auto h-4 w-24 rounded bg-slate-100" />
        </div>
      ))}
    </div>
  );
}

export default function DashboardCards({
  loading,
  vehicleCount,
  partyCount,
  countsLoading,
}: Props) {
  const { t, dir } = useLanguage();
  const cards: MetricCard[] = [
    {
      label: t("dashboard.shell.stats.vehicles"),
      value: vehicleCount === null ? "—" : vehicleCount.toLocaleString("en-PK"),
      helper: t("dashboard.shell.stats.allVehiclesInAdda"),
      icon: CarFront,
      tone: "border-blue-100 bg-blue-50/65",
      iconTone: "bg-blue-600 text-white",
      valueTone: "text-sky-800",
      decorativeTone: "text-blue-700/[0.12]",
      loading: countsLoading,
    },
    {
      label: t("dashboard.shell.stats.parties"),
      value: partyCount === null ? "—" : partyCount.toLocaleString("en-PK"),
      helper: t("dashboard.shell.stats.activePartiesInAdda"),
      icon: UsersRound,
      tone: "border-emerald-100 bg-emerald-50/65",
      iconTone: "bg-emerald-600 text-white",
      valueTone: "text-emerald-800",
      decorativeTone: "text-emerald-700/[0.12]",
      loading: countsLoading,
    },
  ];
  return (
    <section dir={dir} aria-label={t("dashboard.shell.stats.currentAdda")}>
      {loading ? (
        <SkeletonGrid />
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          {cards.map((card) => {
            const Icon = card.icon;
            return (
              <article
                key={card.label}
                className={[
                  "relative flex h-[150px] min-w-0 flex-col overflow-hidden rounded-[16px] border p-4 shadow-[0_3px_14px_rgb(22_47_82_/_5%)] transition duration-150 hover:-translate-y-0.5 hover:shadow-md",
                  card.tone,
                ].join(" ")}
              >
                <Icon
                  className={["pointer-events-none absolute right-[14px] bottom-[10px] h-[62px] w-[62px] rotate-[-12deg]", card.decorativeTone].join(" ")}
                  aria-hidden="true"
                />
                <div className="relative flex min-w-0 items-center gap-2.5">
                  <span className={["flex h-[46px] w-[46px] shrink-0 items-center justify-center rounded-xl shadow-sm", card.iconTone].join(" ")}>
                    <Icon className="h-6 w-6" aria-hidden="true" />
                  </span>
                  <p className="line-clamp-2 min-w-0 text-sm font-semibold leading-4 text-slate-700">{card.label}</p>
                </div>
                {card.loading ? (
                  <div
                    aria-label={t("dashboard.shell.stats.countLoading")}
                    className="relative mt-3 h-7 w-24 animate-pulse rounded-lg bg-white/80"
                  />
                ) : (
                  <p
                    dir="ltr"
                    className={["relative mt-[7px] break-words text-[28px] font-extrabold leading-[1.05] tracking-tight", card.valueTone].join(" ")}
                  >
                    {card.value}
                  </p>
                )}
                <div className="relative mt-auto pt-1">
                  <p className="text-[11px] font-medium leading-4 text-slate-500">
                    {card.helper}
                  </p>
                </div>
              </article>
            );
          })}
        </div>
      )}

    </section>
  );
}

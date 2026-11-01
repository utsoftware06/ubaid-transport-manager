"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowUpRight,
  Building2,
  CalendarDays,
  Clock3,
  RefreshCw,
  Shield,
  Truck,
} from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  isSuperAdmin: boolean;
  isLoading: boolean;
  isRefreshing: boolean;
  onRefresh: () => void;
};

function formatClock(date: Date, locale: string) {
  return new Intl.DateTimeFormat(locale, {
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

export default function DashboardHero({
  isSuperAdmin,
  isLoading,
  isRefreshing,
  onRefresh,
}: Props) {
  const { t, dir, language } = useLanguage();
  const [now, setNow] = useState<Date | null>(null);
  const locale = language === "ur" ? "ur-PK" : "en-PK";
  const heroActions = [
    ...(isSuperAdmin
      ? [
          {
            href: "/addas",
            label: t("dashboard.shell.manageAddas"),
            icon: Building2,
          },
        ]
      : []),
    {
      href: "/vehicles",
      label: t("dashboard.shell.trackVehicles"),
      icon: Truck,
    },
    {
      href: "/cashbook",
      label: t("dashboard.shell.controlAccounts"),
      icon: Shield,
    },
    {
      href: "/reports",
      label: t("dashboard.shell.generateReports"),
      icon: ArrowUpRight,
    },
  ];

  useEffect(() => {
    const updateTime = () => setNow(new Date());
    updateTime();
    const timer = window.setInterval(updateTime, 60_000);
    return () => window.clearInterval(timer);
  }, []);

  return (
    <section
      dir={dir}
      aria-label={t("dashboard.shell.heroTitle")}
      className="dashboard-hero-art relative isolate min-h-[335px] overflow-hidden rounded-[28px] border border-blue-950/10 text-white shadow-[0_24px_70px_rgb(8_31_69_/_20%)] sm:min-h-[340px] lg:min-h-[360px]"
    >
      <nav
        aria-label={t("dashboard.shell.quickActions")}
        className="absolute inset-x-0 bottom-0 z-10 grid grid-cols-2 gap-2 p-4 sm:flex sm:flex-wrap sm:p-6 lg:max-w-[72%] lg:p-7"
      >
        {heroActions.map((action) => {
          const Icon = action.icon;
          return (
            <Link
              key={action.href}
              href={action.href}
              className="group inline-flex min-h-11 items-center justify-between gap-2 rounded-xl border border-white/35 bg-slate-950/55 px-3 py-2 text-xs font-extrabold text-white shadow-lg backdrop-blur-sm transition duration-200 hover:border-white/60 hover:bg-slate-950/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white sm:text-sm"
            >
              <span className="flex min-w-0 items-center gap-2">
                <Icon className="h-4 w-4 shrink-0 text-cyan-200" aria-hidden="true" />
                <span className="truncate">{action.label}</span>
              </span>
              <ArrowUpRight
                className="h-3.5 w-3.5 shrink-0 opacity-70 transition group-hover:translate-x-0.5 group-hover:-translate-y-0.5 group-hover:opacity-100"
                aria-hidden="true"
              />
            </Link>
          );
        })}
      </nav>

      <aside className="absolute end-4 top-4 z-10 flex max-w-[calc(100%-2rem)] items-center gap-3 rounded-2xl border border-white/60 bg-white/80 p-3 text-slate-900 shadow-xl backdrop-blur-md sm:end-6 sm:top-6 sm:p-4">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-100 text-blue-800">
          <CalendarDays className="h-5 w-5" aria-hidden="true" />
        </span>
        <div>
          <p className="text-xs font-bold text-slate-600">
            {t("dashboard.shell.localTime")}
          </p>
          <p className="mt-0.5 text-xl font-black tabular-nums text-slate-950">
            {now ? formatClock(now, locale) : "--:--"}
          </p>
          <p className="text-xs font-semibold text-slate-600">
            {now
              ? new Intl.DateTimeFormat(locale, {
                  weekday: "short",
                  day: "numeric",
                  month: "short",
                  year: "numeric",
                }).format(now)
              : ""}
          </p>
          <span className="mt-2 hidden items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-blue-700 lg:inline-flex">
            <Clock3 className="h-3.5 w-3.5" aria-hidden="true" />
            {t("dashboard.shell.pakistanTime")}
          </span>
        </div>
        <button
          type="button"
          onClick={onRefresh}
          disabled={isLoading || isRefreshing}
          aria-label={isRefreshing ? t("dashboard.refreshing") : t("dashboard.refresh")}
          title={isRefreshing ? t("dashboard.refreshing") : t("dashboard.refresh")}
          className="ms-1 inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-blue-200 bg-white text-blue-700 transition hover:bg-blue-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          <RefreshCw
            className={["h-4 w-4", isRefreshing ? "animate-spin" : ""].join(" ")}
            aria-hidden="true"
          />
        </button>
      </aside>
    </section>
  );
}

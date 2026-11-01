"use client";

import type { ReactNode } from "react";
import type { AuditLogSummary } from "@/types/auditLogs";
import { useLanguage } from "@/contexts/LanguageContext";

type AuditLogsCardsProps = {
  summary: AuditLogSummary;
  loading: boolean;
};

type CardItem = {
  label: string;
  value: number;
  helper: string;
  icon: ReactNode;
  iconClassName: string;
  borderClassName: string;
};

function TotalLogsIcon() {
  return (
    <svg
      className="h-6 w-6"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M8 6h13" />
      <path d="M8 12h13" />
      <path d="M8 18h13" />
      <path d="M3 6h.01" />
      <path d="M3 12h.01" />
      <path d="M3 18h.01" />
    </svg>
  );
}

function CreatedIcon() {
  return (
    <svg
      className="h-6 w-6"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M12 5v14" />
      <path d="M5 12h14" />
      <path d="M4 4h16v16H4z" />
    </svg>
  );
}

function UpdatedIcon() {
  return (
    <svg
      className="h-6 w-6"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M21 12a9 9 0 1 1-2.64-6.36" />
      <path d="M21 3v6h-6" />
      <path d="M12 7v5l3 2" />
    </svg>
  );
}

function DeletedIcon() {
  return (
    <svg
      className="h-6 w-6"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M3 6h18" />
      <path d="M8 6V4h8v2" />
      <path d="M19 6l-1 14H6L5 6" />
      <path d="M10 11v6" />
      <path d="M14 11v6" />
    </svg>
  );
}

export default function AuditLogsCards({
  summary,
  loading,
}: AuditLogsCardsProps) {
  const { t, dir } = useLanguage();
  const cards: CardItem[] = [
    {
      label: t("auditLogs.summary.totalLogs"),
      value: summary.totalLogs,
      helper: t("auditLogs.summary.totalLogsHint"),
      icon: <TotalLogsIcon />,
      iconClassName: "bg-blue-100 text-blue-700",
      borderClassName: "border-blue-100",
    },
    {
      label: t("auditLogs.summary.created"),
      value: summary.createLogs,
      helper: t("auditLogs.summary.createdHint"),
      icon: <CreatedIcon />,
      iconClassName: "bg-green-100 text-green-700",
      borderClassName: "border-green-100",
    },
    {
      label: t("auditLogs.summary.updated"),
      value: summary.updateLogs,
      helper: t("auditLogs.summary.updatedHint"),
      icon: <UpdatedIcon />,
      iconClassName: "bg-indigo-100 text-indigo-700",
      borderClassName: "border-indigo-100",
    },
    {
      label: t("auditLogs.summary.deleted"),
      value: summary.deleteLogs,
      helper: t("auditLogs.summary.deletedHint"),
      icon: <DeletedIcon />,
      iconClassName: "bg-red-100 text-red-700",
      borderClassName: "border-red-100",
    },
  ];

  if (loading) {
    return (
      <section dir={dir} className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-4">
        {cards.map((card) => (
          <div
            key={card.label}
            className="rounded-xl border border-gray-300 bg-white p-6 shadow-md"
          >
            <div className="animate-pulse space-y-4">
              <div className="h-11 w-11 rounded-xl bg-gray-200" />
              <div className="h-4 w-28 rounded bg-gray-200" />
              <div className="h-8 w-20 rounded bg-gray-200" />
              <div className="h-3 w-40 rounded bg-gray-200" />
            </div>
          </div>
        ))}
      </section>
    );
  }

  return (
    <section dir={dir} className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-4">
      {cards.map((card) => (
        <div
          key={card.label}
          className={`rounded-xl border bg-white p-6 shadow-md transition hover:-translate-y-0.5 hover:shadow-lg ${card.borderClassName}`}
        >
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-sm font-extrabold uppercase tracking-wide text-gray-900">
                {card.label}
              </p>
              <p className="mt-3 text-3xl font-extrabold text-gray-900">
                {card.value.toLocaleString("en-PK")}
              </p>
            </div>

            <div
              className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${card.iconClassName}`}
            >
              {card.icon}
            </div>
          </div>

          <p className="mt-4 text-sm font-bold text-gray-900">{card.helper}</p>
        </div>
      ))}
    </section>
  );
}

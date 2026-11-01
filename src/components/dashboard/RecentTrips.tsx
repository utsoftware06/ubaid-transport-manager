"use client";

import Link from "next/link";
import { Eye, ListFilter } from "lucide-react";

import {
  type DashboardRecentEntry,
  formatAmount,
} from "./DashboardOverview";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  entries: DashboardRecentEntry[];
  loading: boolean;
  errorMessage: string;
};

function entryCategory(entry: DashboardRecentEntry) {
  const source = entry.referenceType?.toLowerCase() ?? "";
  if (source === "loading_advance" || source.includes("loading")) {
    return "loading";
  }
  if (source === "voucher" || source.startsWith("voucher_")) {
    return "voucher";
  }
  if (source === "manual") {
    return entry.entryType === "Cash Out" ? "expense" : "payment";
  }
  if (
    source === "payment_receipt" ||
    source.includes("payment") ||
    source === "broker_transaction" ||
    source === "employee_loan" ||
    source === "owner_gari_withdrawal" ||
    source === "workshop"
  ) {
    return "payment";
  }
  return entry.entryType === "Cash Out" ? "cashOut" : "cashIn";
}

function entryCategoryClass(category: string) {
  if (category === "loading") return "bg-sky-100 text-sky-700";
  if (category === "voucher" || category === "expense") {
    return "bg-rose-100 text-rose-700";
  }
  if (category === "payment" || category === "cashIn") {
    return "bg-emerald-100 text-emerald-700";
  }
  if (category === "cashOut") return "bg-rose-100 text-rose-700";
  return "bg-blue-100 text-blue-700";
}

export default function RecentTrips({
  entries,
  loading,
  errorMessage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const locale = language === "ur" ? "ur-PK" : "en-PK";

  return (
    <section
      dir={dir}
      className="h-full min-h-[330px] min-w-0 rounded-[16px] border border-[#e7edf5] bg-white p-4 shadow-[0_3px_14px_rgb(22_47_82_/_5%)]"
    >
      <div className="mb-2 flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2">
          <span className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-lg bg-blue-50 text-blue-700">
            <ListFilter className="h-4 w-4" aria-hidden="true" />
          </span>
          <h2 className="text-lg font-extrabold tracking-tight text-slate-900">
            {t("dashboard.shell.recent.title")}
          </h2>
        </div>
        <Link
          href="/cashbook"
          className="inline-flex shrink-0 items-center gap-1 rounded-lg px-1.5 py-1 text-[11px] font-bold text-blue-700 transition hover:bg-blue-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
        >
          {t("dashboard.shell.recent.viewAll")}
        </Link>
      </div>

      {loading ? (
        <div className="rounded-xl border border-slate-100 bg-slate-50 p-6 text-center font-bold text-slate-500">
          {t("dashboard.shell.recent.loading")}
        </div>
      ) : errorMessage ? (
        <div
          role="alert"
          className="rounded-xl border border-rose-200 bg-rose-50 p-5 text-center text-sm font-bold text-rose-700"
        >
          {errorMessage}
        </div>
      ) : entries.length === 0 ? (
        <div className="rounded-xl border border-dashed border-slate-200 bg-slate-50/70 p-6 text-center">
          <p className="font-extrabold text-slate-700">
            {t("dashboard.shell.recent.empty")}
          </p>
          <p className="mt-1 text-sm text-slate-500">
            {t("dashboard.shell.recent.emptyHint")}
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-slate-100">
          <table className="w-full min-w-0 table-fixed border-collapse bg-white text-xs">
            <colgroup>
              <col className="w-[5%]" />
              <col className="w-[15%]" />
              <col className="w-[17%]" />
              <col className="w-[32%]" />
              <col className="w-[23%]" />
              <col className="w-[8%]" />
            </colgroup>
            <thead className="h-[34px] bg-slate-50 text-[11px] uppercase leading-[14px] tracking-wide text-slate-500">
              <tr>
                <th className="px-1 py-[10px] text-center font-black">{t("dashboard.shell.recent.number")}</th>
                <th className="px-1.5 py-[10px] text-start font-black">{t("dashboard.shell.recent.date")}</th>
                <th className="px-1.5 py-[10px] text-start font-black">{t("dashboard.shell.recent.type")}</th>
                <th className="px-2 py-[10px] text-start font-black">{t("dashboard.shell.recent.descriptionColumn")}</th>
                <th className="px-1 py-[10px] text-end font-black">{t("dashboard.shell.recent.amount")}</th>
                <th className="px-1 py-[10px] text-center font-black">{t("dashboard.shell.recent.action")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {entries.map((entry, index) => {
                const category = entryCategory(entry);
                const categoryLabel = t(`dashboard.shell.recent.types.${category}`);
                return (
                  <tr key={entry.id} className="transition hover:bg-blue-50/40">
                    <td dir="ltr" className="px-1 py-[7px] text-center text-xs font-extrabold text-slate-400">
                      {String(index + 1).padStart(2, "0")}
                    </td>
                    <td dir="ltr" className="whitespace-nowrap px-1.5 py-[7px] text-xs font-bold text-slate-600">
                      {entry.entryDate
                        ? new Date(entry.entryDate + "T00:00:00").toLocaleDateString(locale)
                        : "—"}
                    </td>
                    <td className="overflow-hidden px-1.5 py-[7px]">
                      <span className={["inline-block max-w-full truncate rounded-full px-2 py-0.5 text-[11px] font-bold", entryCategoryClass(category)].join(" ")}>
                        {categoryLabel}
                      </span>
                    </td>
                    <td className="overflow-hidden px-2 py-[7px]">
                      <p className="truncate whitespace-nowrap text-xs font-bold text-slate-800">
                        {entry.description || entry.personName || "—"}
                      </p>
                    </td>
                    <td dir="ltr" className="whitespace-nowrap px-1 py-[7px] text-end text-xs font-extrabold text-slate-800">
                      <span className={entry.entryType === "Cash In" ? "text-emerald-700" : "text-rose-700"}>
                        {entry.entryType === "Cash In" ? "+ " : "− "}
                        {formatAmount(entry.amount)}
                      </span>
                    </td>
                    <td className="px-1 py-[7px] text-center">
                      <Link
                        href="/cashbook"
                        aria-label={t("dashboard.shell.recent.openCashbook")}
                        title={t("dashboard.shell.recent.openCashbook")}
                        className="inline-flex h-[30px] w-[30px] items-center justify-center rounded-lg border border-slate-200 text-slate-500 transition hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
                      >
                        <Eye className="h-4 w-4" aria-hidden="true" />
                      </Link>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

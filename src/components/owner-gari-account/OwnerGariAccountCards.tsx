import {
  BanknoteArrowDown,
  CalendarClock,
  CircleDollarSign,
  Landmark,
  WalletCards,
} from "lucide-react";

import type { AppLanguage } from "@/i18n/translations";
import type { OwnerGariMonthlyClosing } from "./types";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  report: OwnerGariMonthlyClosing | null;
  loading: boolean;
  month: string;
  dateFrom: string;
  dateTo: string;
  customRangeActive: boolean;
  language: AppLanguage;
  onMonthChange: (month: string) => void;
  t: (key: string) => string;
};

function money(value: number) {
  return "Rs. " + Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  });
}

function formatDate(value: string, language: AppLanguage) {
  const [year, month, day] = value.slice(0, 10).split("-").map(Number);
  if (!year || !month || !day) return "—";
  return new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, day)));
}

function formatMonth(value: string, language: AppLanguage) {
  const [year, month] = value.slice(0, 7).split("-").map(Number);
  if (!year || !month) return value;
  return new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, 1)));
}

export default function OwnerGariAccountCards({
  report,
  loading,
  month,
  dateFrom,
  dateTo,
  customRangeActive,
  language,
  onMonthChange,
  t,
}: Props) {
  const summary = report?.summary;
  const cards = [
    { label: t("ownerGariAccount.cards.openingBalance"), value: summary?.opening_balance ?? 0, icon: CalendarClock, tone: "bg-slate-100 text-slate-700" },
    { label: t("ownerGariAccount.monthlyClosing.totalCredits"), value: summary?.total_credits ?? 0, icon: CircleDollarSign, tone: "bg-emerald-100 text-emerald-700" },
    { label: t("ownerGariAccount.monthlyClosing.totalDebits"), value: summary?.total_debits ?? 0, icon: BanknoteArrowDown, tone: "bg-amber-100 text-amber-700" },
    { label: t("ownerGariAccount.cards.closingBalance"), value: summary?.closing_balance ?? 0, icon: WalletCards, tone: "bg-blue-100 text-blue-700" },
    { label: t("ownerGariAccount.monthlyClosing.currentBalance"), value: summary?.current_balance ?? 0, icon: WalletCards, tone: "bg-cyan-100 text-cyan-700" },
    { label: t("ownerGariAccount.monthlyClosing.netCommission"), value: summary?.owner_gari_net_commission_charge ?? 0, icon: Landmark, tone: "bg-violet-100 text-violet-700" },
  ];
  const matched = summary?.commission_reconciliation_status
    ? summary.commission_reconciliation_status === "Matched"
    : Math.abs(summary?.commission_reconciliation_difference ?? 0) < 0.005;
  const periodLabel = customRangeActive && dateFrom && dateTo
    ? formatDate(dateFrom, language) + " — " + formatDate(dateTo, language)
    : report?.period.period_mode === "custom"
      ? formatDate(report.period.period_start, language) + " — " + formatDate(report.period.period_end, language)
      : formatMonth(report?.period.period_start ?? (month + "-01"), language);

  return (
    <section className="space-y-4 rounded-2xl border border-slate-200 bg-slate-50 p-4 sm:p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-xl font-black text-slate-950">
            {t(customRangeActive ? "ownerGariAccount.monthlyClosing.customTitle" : "ownerGariAccount.monthlyClosing.title")}
          </h2>
          <p className="mt-1 text-sm font-medium text-slate-600">{periodLabel}</p>
          <p className="mt-1 text-xs font-medium text-slate-500">
            {t(customRangeActive ? "ownerGariAccount.monthlyClosing.customDescription" : "ownerGariAccount.monthlyClosing.description")}
          </p>
        </div>

        <VoiceTypingField fieldLabel={t("ownerGariAccount.monthlyClosing.month")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
          <span>{t("ownerGariAccount.monthlyClosing.month")}</span>
          <input
            type="month"
            value={month}
            disabled={customRangeActive}
            onChange={(event) => onMonthChange(event.target.value)}
            className="block rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-500"
          />
        </label></VoiceTypingField>

      </div>

      {report ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {cards.map((card) => (
            <article key={card.label} className="rounded-2xl bg-white p-4 shadow-sm">
              <div className={"mb-3 inline-flex rounded-xl p-2.5 " + card.tone}><card.icon size={21} /></div>
              <p className="font-bold text-slate-600">{card.label}</p>
              <p className={"mt-1 text-xl font-black [direction:ltr] [unicode-bidi:isolate] " + (card.value < 0 ? "text-red-700" : "text-slate-950")}>
                {money(card.value)}
              </p>
              {card.label === t("ownerGariAccount.monthlyClosing.currentBalance") && (
                <p className="mt-1 text-xs text-slate-500">
                  {t("ownerGariAccount.monthlyClosing.currentBalanceAsOf")}: {formatDate(summary?.current_balance_as_of_date ?? "", language)}
                </p>
              )}
            </article>
          ))}
        </div>
      ) : (
        <div role={loading ? "status" : undefined} className="rounded-xl bg-white p-5 text-center font-bold text-slate-600">
          {t(loading ? "common.loading" : "ownerGariAccount.monthlyClosing.selectVehicle")}
        </div>
      )}

      <div className={"flex flex-wrap items-center justify-between gap-3 rounded-xl border p-4 " + (matched ? "border-emerald-200 bg-emerald-50" : "border-amber-300 bg-amber-50")}>
        <div>
          <p className={"font-black " + (matched ? "text-emerald-800" : "text-amber-900")}>
            {t("ownerGariAccount.monthlyClosing.commissionReconciliation")}: {loading ? t("common.loading") : report ? t(matched ? "ownerGariAccount.monthlyClosing.matched" : "ownerGariAccount.monthlyClosing.difference") : "—"}
          </p>
          <p className="mt-1 text-sm text-slate-700">
            {report ? <>
              {t("ownerGariAccount.monthlyClosing.addaCommissionNet")}: {money(summary?.adda_commission_net_effect ?? 0)}
              {" · "}{t("ownerGariAccount.monthlyClosing.ownerCommissionCharge")}: {money(summary?.owner_gari_net_commission_charge ?? 0)}
            </> : t("ownerGariAccount.monthlyClosing.selectVehicle")}
          </p>
        </div>
        <p className={"text-lg font-black [direction:ltr] [unicode-bidi:isolate] " + (matched ? "text-emerald-800" : "text-amber-900")}>
          {t("ownerGariAccount.monthlyClosing.differenceAmount")}: {report ? money(summary?.commission_reconciliation_difference ?? 0) : "—"}
        </p>
      </div>

      {report && summary && (
        <div className="grid gap-x-6 gap-y-2 rounded-xl bg-white p-4 text-sm sm:grid-cols-2 xl:grid-cols-4">
          {[
            ["chakkarCredit", summary.chakkar_credits],
            ["chakkarDebit", summary.chakkar_debits],
            ["ownerWithdrawal", summary.owner_withdrawals],
            ["gariWithdrawal", summary.gari_withdrawals],
            ["voucherExpense", summary.voucher_adjustment_expenses],
            ["manualAdjustmentCredit", summary.manual_adjustment_credits],
            ["manualAdjustmentDebit", summary.manual_adjustment_debits],
            ["transactionCount", summary.transaction_count],
          ].map(([key, value]) => (
            <p key={String(key)} className="flex justify-between gap-3 text-slate-600">
              <span>{t("ownerGariAccount.monthlyClosing." + String(key))}</span>
              <strong className="text-slate-950">{key === "transactionCount" ? Number(value ?? 0).toLocaleString() : money(Number(value ?? 0))}</strong>
            </p>
          ))}
        </div>
      )}
    </section>
  );
}

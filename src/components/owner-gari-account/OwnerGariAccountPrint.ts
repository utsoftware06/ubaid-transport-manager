import { escapeHtml } from "@/lib/print/escapeHtml";

import type { AppLanguage } from "@/i18n/translations";
import type { OwnerGariMonthlyClosing } from "./types";

type PrintOptions = {
  report: OwnerGariMonthlyClosing;
  language: AppLanguage;
  dir: "ltr" | "rtl";
  t: (key: string) => string;
};

function money(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })}`;
}

function safe(value: string | null | undefined) {
  return escapeHtml(value?.trim() || "—");
}

function formatDate(value: string, language: AppLanguage) {
  const [year, month, day] = value.slice(0, 10).split("-").map(Number);
  if (!year || !month || !day) return "—";
  return new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", {
    day: "2-digit", month: "short", year: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, day)));
}

function formatMonth(value: string, language: AppLanguage) {
  const [year, month] = value.slice(0, 7).split("-").map(Number);
  if (!year || !month) return value;
  return new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", {
    month: "long", year: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, 1)));
}

export function printOwnerGariMonthlyClosing({ report, language, dir, t }: PrintOptions) {
  const popup = window.open("", "_blank", "width=1200,height=850");
  if (!popup) {
    window.alert(t("ownerGariAccount.messages.allowPopups"));
    return;
  }

  const { summary, account, transactions } = report;
  const month = report.period.period_mode === "custom"
    ? formatDate(report.period.period_start, language) + " — " + formatDate(report.period.period_end, language)
    : formatMonth(report.period.period_start, language);
  const transactionRows = transactions.map((transaction) => `<tr>
    <td>${safe(transaction.transaction_date)}</td>
    <td>${escapeHtml(t(`ownerGariAccount.transactionTypes.${transaction.transaction_type}`))}</td>
    <td>${safe(transaction.reference_no || transaction.movement_group_id)}</td>
    <td>${safe(transaction.description)}</td>
    <td class="money credit">${transaction.credit ? escapeHtml(money(transaction.credit)) : "—"}</td>
    <td class="money debit">${transaction.debit ? escapeHtml(money(transaction.debit)) : "—"}</td>
    <td class="money ${transaction.running_balance < 0 ? "negative" : ""}">${escapeHtml(money(transaction.running_balance))}</td>
  </tr>`).join("");

  const breakdown = [
    ["chakkarCredit", summary.chakkar_credits],
    ["chakkarDebit", summary.chakkar_debits],
    ["ownerWithdrawal", summary.owner_withdrawals],
    ["gariWithdrawal", summary.gari_withdrawals],
    ["voucherExpense", summary.voucher_adjustment_expenses],
    ["manualAdjustmentCredit", summary.manual_adjustment_credits],
    ["manualAdjustmentDebit", summary.manual_adjustment_debits],
    ["addaCommissionNet", summary.adda_commission_net_effect],
    ["ownerCommissionCharge", summary.owner_gari_net_commission_charge],
    ["commissionDifference", summary.commission_reconciliation_difference],
  ].map(([key, amount]) => `<div class="box"><span>${escapeHtml(t(`ownerGariAccount.monthlyClosing.${key}`))}</span><strong class="money">${escapeHtml(money(Number(amount)))}</strong></div>`).join("");

  popup.document.write(`<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head>
    <title>${escapeHtml(t("ownerGariAccount.monthlyClosing.printTitle"))}</title>
    <style>
      @page{size:A4 landscape;margin:10mm}*{box-sizing:border-box}body{font-family:Arial,sans-serif;color:#0f172a;padding:18px}
      h1,h2{text-align:center;margin:4px}.meta{text-align:center;margin:12px 0 18px}.cards,.breakdown{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin:14px 0}
      .breakdown{grid-template-columns:repeat(3,1fr)}.box{border:1px solid #cbd5e1;border-radius:8px;padding:9px}.box span{display:block;font-size:10px;font-weight:700;color:#475569}
      .box strong{display:block;margin-top:5px}.money{direction:ltr;unicode-bidi:isolate;text-align:end}.credit{color:#047857}.debit,.negative{color:#b91c1c}
      .reconciliation{border:1px solid #cbd5e1;border-radius:8px;padding:9px;margin:12px 0}table{width:100%;border-collapse:collapse;font-size:9px}
      th,td{border:1px solid #cbd5e1;padding:6px;text-align:start;vertical-align:top}th{background:#1d4ed8;color:#fff}footer{text-align:center;margin-top:16px;font-size:10px;color:#475569}
      @media print{body{padding:0}}
    </style></head><body>
    <h1>${safe(account.adda_name)}</h1>
    <h2>${escapeHtml(t("ownerGariAccount.monthlyClosing.printTitle"))}</h2>
    <div class="meta">${escapeHtml(t("ownerGariAccount.table.vehicle"))}: <strong>${safe(account.vehicle_no)}</strong> · ${escapeHtml(t("ownerGariAccount.table.owner"))}: <strong>${safe(account.owner_name)}</strong> · ${escapeHtml(t("ownerGariAccount.monthlyClosing.period"))}: <strong>${escapeHtml(month)}</strong></div>
    <div class="cards">
      <div class="box"><span>${escapeHtml(t("ownerGariAccount.cards.openingBalance"))}</span><strong class="money">${escapeHtml(money(summary.opening_balance))}</strong></div>
      <div class="box"><span>${escapeHtml(t("ownerGariAccount.monthlyClosing.totalCredits"))}</span><strong class="money">${escapeHtml(money(summary.total_credits))}</strong></div>
      <div class="box"><span>${escapeHtml(t("ownerGariAccount.monthlyClosing.totalDebits"))}</span><strong class="money">${escapeHtml(money(summary.total_debits))}</strong></div>
      <div class="box"><span>${escapeHtml(t("ownerGariAccount.cards.closingBalance"))}</span><strong class="money ${summary.closing_balance < 0 ? "negative" : ""}">${escapeHtml(money(summary.closing_balance))}</strong></div>
      <div class="box"><span>${escapeHtml(t("ownerGariAccount.monthlyClosing.currentBalance"))}</span><strong class="money ${summary.current_balance < 0 ? "negative" : ""}">${escapeHtml(money(summary.current_balance))}</strong></div>
    </div>
    <div class="breakdown">${breakdown}</div>
    <div class="reconciliation"><strong>${escapeHtml(t("ownerGariAccount.monthlyClosing.commissionReconciliation"))}:</strong> ${escapeHtml(summary.commission_reconciliation_status === "Matched" ? t("ownerGariAccount.monthlyClosing.matched") : t("ownerGariAccount.monthlyClosing.difference"))} · ${escapeHtml(t("ownerGariAccount.monthlyClosing.differenceAmount"))}: ${escapeHtml(money(summary.commission_reconciliation_difference))}</div>
    <table><thead><tr>
      <th>${escapeHtml(t("ownerGariAccount.table.date"))}</th><th>${escapeHtml(t("ownerGariAccount.table.transactionType"))}</th><th>${escapeHtml(t("ownerGariAccount.table.reference"))}</th><th>${escapeHtml(t("ownerGariAccount.table.description"))}</th><th>${escapeHtml(t("ownerGariAccount.table.credit"))}</th><th>${escapeHtml(t("ownerGariAccount.table.debit"))}</th><th>${escapeHtml(t("ownerGariAccount.table.runningBalance"))}</th>
    </tr></thead><tbody>${transactionRows || `<tr><td colspan="7">${escapeHtml(t("ownerGariAccount.table.empty"))}</td></tr>`}</tbody></table>
    <footer>${escapeHtml(t("ownerGariAccount.monthlyClosing.currentBalanceAsOf"))}: ${escapeHtml(formatDate(summary.current_balance_as_of_date, language))} · ${escapeHtml(t("ownerGariAccount.monthlyClosing.generatedAt"))}: ${escapeHtml(new Date().toLocaleString(language === "ur" ? "ur-PK" : "en-PK"))} · ${escapeHtml(t("ownerGariAccount.monthlyClosing.immutableNotice"))}</footer>
    <script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}</script>
    </body></html>`);
  popup.document.close();
}

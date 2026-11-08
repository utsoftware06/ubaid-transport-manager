import type { AppLanguage } from "@/i18n/translations";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";

import type { OwnerGariWithdrawalReceipt } from "./types";

type PrintOptions = {
  popup: Window;
  receipt: OwnerGariWithdrawalReceipt;
  language: AppLanguage;
  dir: "ltr" | "rtl";
  t: (key: string) => string;
};

function safe(value: string | null | undefined) {
  return escapeHtml(value?.trim() || "—");
}

function money(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })}`;
}

export function printOwnerGariWithdrawalReceipt({
  popup,
  receipt,
  language,
  dir,
  t,
}: PrintOptions) {
  void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head>
    <title>${escapeHtml(t("ownerGariAccount.withdrawal.receiptTitle"))}</title>
    <style>@page{size:A4 portrait;margin:16mm}*{box-sizing:border-box}body{font-family:Arial,sans-serif;color:#0f172a;padding:24px}.sheet{max-width:760px;margin:auto;border:1px solid #cbd5e1;border-radius:14px;padding:28px}h1,h2{text-align:center;margin:4px}.meta{text-align:center;color:#475569;margin:10px 0 22px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}.box{border:1px solid #cbd5e1;border-radius:8px;padding:12px}.box span{display:block;color:#64748b;font-size:11px;font-weight:700;text-transform:uppercase}.box strong{display:block;margin-top:6px}.amount{font-size:28px;color:#b91c1c;direction:ltr;unicode-bidi:isolate}.wide{grid-column:1/-1}.signatures{display:grid;grid-template-columns:1fr 1fr;gap:80px;margin-top:70px}.signature{border-top:1px solid #334155;padding-top:7px;text-align:center;font-weight:700}@media print{body{padding:0}.sheet{border:0}}</style>
    </head><body><main class="sheet">
      <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
      <h2>${escapeHtml(t("ownerGariAccount.withdrawal.receiptTitle"))}</h2>
      <div class="meta">${escapeHtml(t("ownerGariAccount.withdrawal.receiptNo"))}: ${safe(receipt.transaction_id)}</div>
      <div class="grid">
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.table.vehicle"))}</span><strong>${safe(receipt.vehicle_no)}</strong></div>
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.table.owner"))}</span><strong>${safe(receipt.owner_name)}</strong></div>
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.withdrawal.date"))}</span><strong>${safe(receipt.transaction_date)}</strong></div>
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.withdrawal.type"))}</span><strong>${escapeHtml(t(`ownerGariAccount.transactionTypes.${receipt.transaction_type}`))}</strong></div>
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.withdrawal.amount"))}</span><strong class="amount">${escapeHtml(money(receipt.amount))}</strong></div>
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.withdrawal.paymentMethod"))}</span><strong>${escapeHtml(t(`ownerGariAccount.withdrawal.paymentMethods.${receipt.payment_method}`))}</strong></div>
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.withdrawal.referenceNo"))}</span><strong>${safe(receipt.reference_no)}</strong></div>
        <div class="box"><span>${escapeHtml(t("ownerGariAccount.withdrawal.cashbookReference"))}</span><strong>${safe(receipt.cashbook_reference_id)}</strong></div>
        <div class="box wide"><span>${escapeHtml(t("ownerGariAccount.withdrawal.remarks"))}</span><strong>${safe(receipt.remarks)}</strong></div>
      </div>
      <div class="signatures">
        <div class="signature">${escapeHtml(t("ownerGariAccount.withdrawal.preparedBy"))}: ${safe(receipt.prepared_by)}</div>
        <div class="signature">${escapeHtml(t("ownerGariAccount.withdrawal.receivedBy"))}</div>
      </div>
    </main><script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}</script></body></html>`, receipt.adda_id, language === "ur" ? "ur" : "en");
}

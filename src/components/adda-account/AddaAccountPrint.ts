import type { AddaAccountEntry, AddaFinanceSettlement } from "./types";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";

export type PrintLabels = {
  expenseTitle: string;
  incomeTitle: string;
  entryType: string;
  date: string;
  category: string;
  referenceNo: string;
  description: string;
  remarks: string;
  totalAmount: string;
  settledAmount: string;
  pendingAmount: string;
  status: string;
  paymentHistory: string;
  paymentDate: string;
  event: string;
  paymentMethod: string;
  cashbookDirection: string;
  amount: string;
  settlement: string;
  reversal: string;
  createdAt: string;
  printedAt: string;
  generatedBy: string;
  noPayments: string;
  earnedAmount: string;
  realizedAmount: string;
  marginPendingAmount: string;
  receivedBasisAmount: string;
  marginReceiptNote: string;
  sourceManagedNote: string;
  issuedFinanceNoCash: string;
};

function escapeHtml(value: string | number | null | undefined) {
  return String(value ?? "—")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatDate(value: string | null | undefined) {
  if (!value) return "—";
  const parsed = new Date(value.length === 10 ? `${value}T00:00:00` : value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString("en-PK");
}

function money(value: number) {
  return `Rs. ${value.toLocaleString("en-PK", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

function field(label: string, value: string | number | null | undefined, wide = false) {
  return `<div class="field${wide ? " wide" : ""}"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value || "—")}</strong></div>`;
}

export function openAddaAccountPrintWindow() {
  return window.open("", "_blank", "popup=yes,width=900,height=760");
}

export function renderAddaAccountPrintWindow(
  printWindow: Window,
  entry: AddaAccountEntry,
  settlements: AddaFinanceSettlement[],
  statusLabel: string,
  labels: PrintLabels,
  direction: "ltr" | "rtl",
) {
  const isExpense = entry.entry_kind === "expense";
  const employeeSalaryManaged = entry.source_type === "employee_salary_generated";
  const biltyMargin = entry.source_type === "bilty_margin";
  const issuedFinance = entry.source_type === "issued_parchi_financing_commission";
  const sourceManaged = biltyMargin || entry.source_type === "bilty_loss" || employeeSalaryManaged || issuedFinance;
  const title = isExpense ? labels.expenseTitle : labels.incomeTitle;
  const settlementRows = settlements.map((item) => `
    <tr>
      <td>${escapeHtml(formatDate(item.payment_date))}</td>
      <td>${escapeHtml(item.event_type === "settlement" ? labels.settlement : labels.reversal)}</td>
      <td class="amount">${escapeHtml(money(item.amount))}</td>
      <td>${escapeHtml(item.payment_method || "—")}</td>
      <td>${escapeHtml(item.cashbook_entry_type || "—")}</td>
      <td>${escapeHtml(item.reference_no || item.reversal_reason || item.cashbook_reference_id || "—")}</td>
    </tr>`).join("");
  const printedAt = new Date().toLocaleString("en-PK");
  const html = `<!doctype html>
<html lang="${direction === "rtl" ? "ur" : "en"}" dir="${direction}">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>
    *{box-sizing:border-box}body{margin:0;background:#eef2f7;color:#0f172a;font:14px/1.45 Arial,sans-serif;padding:24px}
    .receipt{max-width:820px;margin:0 auto;background:#fff;border:1px solid #cbd5e1;border-radius:14px;padding:28px}
    header{text-align:center;border-bottom:2px solid #1e3a8a;padding-bottom:16px;margin-bottom:20px}
    h1{font-size:23px;margin:0 0 4px;color:#172554}h2{font-size:17px;letter-spacing:.04em;margin:12px 0 0}
    .adda{font-size:13px;color:#475569}.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
    .field{min-width:0;border:1px solid #dbe3ed;border-radius:8px;padding:10px 12px;overflow-wrap:anywhere}
    .field span{display:block;color:#64748b;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.04em}
    .field strong{display:block;margin-top:4px;font-size:13px;white-space:pre-wrap}.wide{grid-column:1/-1}
    .total{background:#eff6ff;border-color:#bfdbfe}.total strong{font-size:20px;color:#1d4ed8}
    .history{margin-top:22px}.history h3{font-size:14px;margin:0 0 8px}
    table{width:100%;border-collapse:collapse;font-size:11px}th,td{border:1px solid #cbd5e1;padding:7px;text-align:start;vertical-align:top}
    th{background:#eff6ff;color:#334155}.amount{white-space:nowrap;font-weight:700;direction:ltr;unicode-bidi:isolate}
    .empty{border:1px dashed #cbd5e1;border-radius:8px;padding:14px;color:#64748b;text-align:center}
    .footer{display:flex;justify-content:space-between;gap:28px;margin-top:46px}.signature{flex:1;border-top:1px solid #475569;padding-top:7px;text-align:center;font-size:11px;font-weight:700}
    .generated{text-align:center;color:#64748b;font-size:10px;margin-top:22px}
    @page{size:A4 portrait;margin:12mm}
    @media(max-width:600px){body{padding:10px}.receipt{padding:16px}.grid{grid-template-columns:1fr}.wide{grid-column:auto}table{font-size:9px}th,td{padding:4px}}
    @media print{body{padding:0;background:#fff}.receipt{max-width:none;border:0;border-radius:0;padding:0;box-shadow:none}header{break-after:avoid}.history{break-inside:avoid}tr{break-inside:avoid}}
  </style>
</head>
<body>
  <main class="receipt">
    <header><h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${escapeHtml(title)}</h2></header>
    <section class="grid">
      ${field(labels.entryType, isExpense ? "Expense" : "Income")}
      ${field(labels.date, formatDate(entry.entry_date))}
      ${field(labels.category, entry.category_name || (isExpense ? "Expense" : "Income"))}
      ${field(labels.referenceNo, entry.reference_no)}
      ${field(labels.description, entry.description, true)}
      ${field(labels.remarks, entry.remarks, true)}
      ${field(labels.totalAmount, money(entry.amount), true)}
      ${biltyMargin
        ? `${field(labels.realizedAmount, money(entry.realized_amount ?? 0))}${field(labels.marginPendingAmount, money(entry.margin_pending_amount ?? entry.amount))}${field(labels.receivedBasisAmount, money(entry.received_basis_amount ?? 0))}`
        : `${field(labels.settledAmount, sourceManaged ? "—" : money(entry.net_settled_amount))}${field(labels.pendingAmount, sourceManaged ? "—" : money(entry.pending_amount))}`}
      ${field(labels.status, statusLabel)}
      ${field(labels.createdAt, formatDate(entry.created_at))}
      ${field(labels.printedAt, printedAt)}
    </section>
    <section class="history"><h3>${escapeHtml(labels.paymentHistory)}</h3>
      ${sourceManaged
        ? `<div class="empty">${escapeHtml(biltyMargin ? labels.marginReceiptNote : issuedFinance ? labels.issuedFinanceNoCash : labels.sourceManagedNote)}</div>`
        : settlements.length ? `<table><thead><tr><th>${escapeHtml(labels.paymentDate)}</th><th>${escapeHtml(labels.event)}</th><th>${escapeHtml(labels.amount)}</th><th>${escapeHtml(labels.paymentMethod)}</th><th>${escapeHtml(labels.cashbookDirection)}</th><th>${escapeHtml(labels.referenceNo)}</th></tr></thead><tbody>${settlementRows}</tbody></table>` : `<div class="empty">${escapeHtml(labels.noPayments)}</div>`}
    </section>
    <div class="footer"><div class="signature">Paid / Received By</div><div class="signature">Authorized Signature</div></div>
    <div class="generated">${escapeHtml(labels.generatedBy)}</div>
  </main>
  <script>window.addEventListener('load',function(){window.focus();window.print()});window.addEventListener('afterprint',function(){window.close()});</script>
</body></html>`;

  void writeAddaBrandedPrintDocument(printWindow, html, entry.adda_id, direction === "rtl" ? "ur" : "en");
}

import type { OtherAddaPayment } from "./types";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";

type ReceiptInput = {
  payment: OtherAddaPayment;
  addaId: string;
  otherAddaName: string;
  currentAddaName: string | null;
  dir: "ltr" | "rtl";
};

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character] ?? character);
}

function amount(value: number | string): string {
  const text = String(value);
  if (!/^-?\d+(?:\.\d{1,2})?$/.test(text)) return `Rs. ${text}`;
  const [whole, fraction = ""] = text.replace(/^-/, "").split(".");
  const formattedWhole = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `Rs. ${text.startsWith("-") ? "-" : ""}${formattedWhole}.${fraction.padEnd(2, "0")}`;
}

function cashbookDirection(payment: OtherAddaPayment): "Cash In" | "Cash Out" {
  const isReversal = payment.event_type === "reversal";
  return (payment.side === "receivable") !== isReversal ? "Cash In" : "Cash Out";
}

function field(label: string, value: string, wide = false): string {
  return `<div class="field${wide ? " wide" : ""}"><span class="label">${escapeHtml(label)}</span><strong>${escapeHtml(value || "—")}</strong></div>`;
}

export function printOtherAddaPaymentReceipt({ payment, addaId, otherAddaName, currentAddaName, dir }: ReceiptInput): void {
  const popup = window.open("", "_blank", "width=760,height=900");
  if (!popup) {
    window.alert("Allow pop-ups for this site to print the receipt.");
    return;
  }

  const isReversal = payment.event_type === "reversal";
  const title = isReversal ? "Other Adda Payment Reversal Receipt" : "Other Adda Payment Receipt";
  const side = payment.side === "receivable" ? "LENA Received" : "DENA Paid";
  const printedAt = new Date().toLocaleString("en-PK");
  const reversalField = isReversal
    ? field("Reversed Payment ID", payment.reverses_payment_id ?? "—", true)
    : "";

  void writeAddaBrandedPrintDocument(popup, `<!doctype html>
<html lang="en" dir="${escapeHtml(dir)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>
    * { box-sizing: border-box; }
    @page { margin: 10mm; }
    html, body { margin: 0; padding: 0; width: 100%; font-family: Arial, sans-serif; color: #111; background: #fff; }
    body { padding: 8px; }
    .receipt { width: 100%; max-width: 190mm; margin: 0 auto; border: 1px solid #222; padding: 8mm; }
    .header { text-align: center; border-bottom: 2px solid #222; padding-bottom: 12px; margin-bottom: 16px; }
    h1, h2, p { margin: 0; }
    h1 { font-size: 24px; letter-spacing: .04em; }
    h2 { margin-top: 8px; font-size: 17px; }
    .current-adda { margin-top: 6px; font-size: 13px; }
    .details { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
    .field { min-width: 0; border-bottom: 1px solid #bbb; padding: 8px 2px; overflow-wrap: anywhere; }
    .field.wide { grid-column: 1 / -1; }
    .label { display: block; margin-bottom: 4px; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; }
    .field strong { display: block; font-size: 13px; font-weight: 600; white-space: pre-wrap; }
    .technical { direction: ltr; unicode-bidi: isolate; }
    .amount-field strong { font-size: 22px; font-weight: 800; }
    .footer { margin-top: 18px; border-top: 1px solid #777; padding-top: 10px; text-align: center; font-size: 11px; }
    .printed { margin-top: 8px; text-align: end; font-size: 10px; }
    .signatures { display: grid; grid-template-columns: 1fr 1fr; gap: 30px; margin-top: 42px; }
    .signature { min-height: 30px; border-top: 1px solid #222; padding-top: 6px; text-align: center; font-size: 11px; font-weight: 700; }
    @media (max-width: 90mm) {
      body { padding: 2mm; }
      .receipt { padding: 3mm; border-radius: 0; }
      .details, .signatures { grid-template-columns: 1fr; gap: 3px; }
      .field.wide { grid-column: auto; }
      .field { display: grid; grid-template-columns: 1fr; gap: 2px; }
      h1 { font-size: 20px; }
      h2 { font-size: 15px; }
      .signatures { gap: 24px; margin-top: 30px; }
    }
    @media print { body { padding: 0; } .receipt { border-color: #222; } }
  </style>
</head>
<body>
  <main class="receipt">
    <header class="header">
      <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
      <h2>${escapeHtml(title)}</h2>
    </header>
    <section class="details">
      ${field("Other Adda Name", otherAddaName, true)}
      ${field("Payment Date", payment.payment_date)}
      ${field("Side", side)}
      ${field("Cashbook Direction", cashbookDirection(payment))}
      ${field("Amount", amount(payment.amount), true).replace('class="field wide"', 'class="field wide amount-field"')}
      ${field("Payment Method", payment.payment_method)}
      ${field("Reference No", payment.reference_no ?? "—")}
      ${field("Remarks / Reversal Reason", payment.remarks ?? "—", true)}
      ${field("Event Type", isReversal ? "Reversal" : "Payment")}
      ${field("Payment ID", payment.id, true)}
      ${reversalField}
    </section>
    <div class="signatures">
      <div class="signature">Paid/Received By</div>
      <div class="signature">Authorized Signature</div>
    </div>
    <footer class="footer">${escapeHtml(currentAddaName?.trim() || (dir === "rtl" ? "اڈے کا نام دستیاب نہیں" : "Adda name unavailable"))}</footer>
    <p class="printed">Printed At: <span class="technical">${escapeHtml(printedAt)}</span></p>
  </main>
  <script>window.onload=function(){window.focus();window.print();};window.onafterprint=function(){window.close();};</script>
</body>
</html>`, addaId, dir === "rtl" ? "ur" : "en");
}

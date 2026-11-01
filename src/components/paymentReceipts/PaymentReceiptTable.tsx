"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import type { PaymentReceiptRecord } from "@/types/paymentReceipts";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  receipts: PaymentReceiptRecord[];
  addaId: string | null;
  isLoading: boolean;
  errorMessage: string;
  deletingId: string | null;
  onEdit: (receipt: PaymentReceiptRecord) => void;
  onDelete: (receipt: PaymentReceiptRecord) => void;
};

function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK")}`;
}

function paymentMethodKey(value: string) {
  return value === "Online Transfer" ? "onlineTransfer" : value.toLowerCase();
}

function receiptPartyName(receipt: PaymentReceiptRecord) {
  const booking = receipt.loadings?.bookings;
  return booking?.parties?.name ?? booking?.sender_name ?? "-";
}

export default function PaymentReceiptTable({
  receipts, addaId, isLoading, errorMessage, deletingId, onEdit, onDelete,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("payment_receipt", addaId, language === "ur" ? "ur" : "en");
  const [search, setSearch] = useState("");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [method, setMethod] = useState("");
  const [page, setPage] = useState(1);
  const [viewing, setViewing] = useState<PaymentReceiptRecord | null>(null);
  const closeRef = useRef<HTMLButtonElement>(null);

  const filtered = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    return receipts.filter((receipt) => {
      if (fromDate && receipt.receipt_date < fromDate) return false;
      if (toDate && receipt.receipt_date > toDate) return false;
      if (method && receipt.payment_method !== method) return false;
      return !keyword || [
        receipt.receipt_no,
        receipt.loadings?.loading_no,
        receiptPartyName(receipt),
        receipt.payment_method,
        receipt.remarks,
        String(receipt.amount),
      ].filter(Boolean).join(" ").toLowerCase().includes(keyword);
    });
  }, [fromDate, method, receipts, search, toDate]);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visible = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  useEffect(() => {
    if (!viewing) return;
    const previousOverflow = document.body.style.overflow;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setViewing(null);
    }
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", onKeyDown);
    closeRef.current?.focus();
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", onKeyDown);
    };
  }, [viewing]);

  function resetFilters() {
    setSearch(""); setFromDate(""); setToDate(""); setMethod(""); setPage(1);
  }

  function printReceiptLegacy(receipt: PaymentReceiptRecord) {
    const popup = window.open("", "_blank", "width=760,height=700");
    if (!popup) return alert(t("paymentReceipts.messages.allowPopups"));
    const label = (key: string) => escapeHtml(t(key));
    const value = (input: unknown) => escapeHtml(input);
    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${value(language)}" dir="${value(dir)}"><head><title>${label("paymentReceipts.print.title")}</title><style>@page{size:A5;margin:12mm}body{font-family:Arial,sans-serif;color:#111827;direction:${value(dir)};text-align:start}.receipt{border:1px solid #d1d5db;padding:24px}.header{text-align:center;border-bottom:2px solid #111827;padding-bottom:14px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:20px}.box{border-bottom:1px solid #d1d5db;padding:8px}.technical{direction:ltr;unicode-bidi:isolate}.signatures{display:grid;grid-template-columns:1fr 1fr;gap:40px;margin-top:60px}.signature{border-top:1px solid #111827;text-align:center;padding-top:8px}@media print{.receipt{border:0}}</style></head><body><div class="receipt"><div class="header"><h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${label("paymentReceipts.print.title")}</h2></div><div class="grid"><div class="box"><strong>${label("paymentReceipts.receiptNo")}:</strong> <span class="technical">${value(receipt.receipt_no)}</span></div><div class="box"><strong>${label("common.date")}:</strong> <span class="technical">${value(receipt.receipt_date)}</span></div><div class="box"><strong>${label("paymentReceipts.loading")}:</strong> <span class="technical">${value(receipt.loadings?.loading_no ?? "-")}</span></div><div class="box"><strong>${label("common.party")}:</strong> ${value(receiptPartyName(receipt))}</div><div class="box"><strong>${label("common.amount")}:</strong> <span class="technical">${value(formatAmount(receipt.amount))}</span></div><div class="box"><strong>${label("paymentReceipts.method")}:</strong> ${label(`paymentReceipts.paymentMethods.${paymentMethodKey(receipt.payment_method)}`)}</div><div class="box" style="grid-column:1/-1"><strong>${label("common.remarks")}:</strong> ${value(receipt.remarks ?? "-")}</div></div><div class="signatures"><div class="signature">${label("paymentReceipts.print.receivedBy")}</div><div class="signature">${label("paymentReceipts.print.payerSignature")}</div></div></div><script>window.onload=function(){window.focus();window.print();}</script></body></html>`, addaId, language === "ur" ? "ur" : "en");
  }

  function printFilteredReportLegacy() {
    const popup = window.open("", "_blank", "width=1100,height=800");
    if (!popup) return alert(t("paymentReceipts.messages.allowPopups"));
    const label = (key: string) => escapeHtml(t(key));
    const value = (input: unknown) => escapeHtml(input);
    const rows = filtered.map((receipt) => `<tr><td class="technical">${value(receipt.receipt_no)}</td><td class="technical">${value(receipt.receipt_date)}</td><td class="technical">${value(receipt.loadings?.loading_no ?? "-")}</td><td>${value(receiptPartyName(receipt))}</td><td class="technical">${value(formatAmount(receipt.amount))}</td><td>${label(`paymentReceipts.paymentMethods.${paymentMethodKey(receipt.payment_method)}`)}</td></tr>`).join("");
    const total = filtered.reduce((sum, receipt) => sum + receipt.amount, 0);
    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${value(language)}" dir="${value(dir)}"><head><title>${label("paymentReceipts.print.reportTitle")}</title><style>@page{size:A4 landscape;margin:12mm}body{font-family:Arial,sans-serif;color:#111827;direction:${value(dir)};text-align:start}h1,h2{text-align:center}table{width:100%;border-collapse:collapse;margin-top:24px}th,td{border:1px solid #d1d5db;padding:9px;text-align:start}th{background:#2563eb;color:#fff}.technical{direction:ltr;unicode-bidi:isolate}.total{font-weight:800}</style></head><body><h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${label("paymentReceipts.print.reportTitle")}</h2><table><thead><tr><th>${label("paymentReceipts.receiptNo")}</th><th>${label("common.date")}</th><th>${label("paymentReceipts.loading")}</th><th>${label("common.party")}</th><th>${label("common.amount")}</th><th>${label("paymentReceipts.method")}</th></tr></thead><tbody>${rows || `<tr><td colspan="6">${label("paymentReceipts.empty")}</td></tr>`}</tbody><tfoot><tr class="total"><td colspan="4">${label("common.total")}</td><td class="technical">${value(formatAmount(total))}</td><td></td></tr></tfoot></table><script>window.onload=function(){window.focus();window.print();}</script></body></html>`, addaId, language === "ur" ? "ur" : "en");
  }

  function printReceipt(receipt: PaymentReceiptRecord) {
    const methodKey = paymentMethodKey(receipt.payment_method);
    const presentation: ModulePrintPresentation = {
      documentType: "payment_receipt",
      title: printLabel("paymentReceipts.print.title"),
      documentNo: printValue(receipt.receipt_no),
      documentDate: printValue(receipt.receipt_date),
      fields: [
        { label: printLabel("paymentReceipts.loading"), value: printValue(receipt.loadings?.loading_no) },
        { label: printLabel("common.party"), value: printValue(receiptPartyName(receipt)) },
        { label: printLabel("common.amount"), value: printValue(formatAmount(receipt.amount)) },
        { label: printLabel("paymentReceipts.method"), value: printLabel(`paymentReceipts.paymentMethods.${methodKey}`) },
      ],
      remarks: printValue(receipt.remarks),
    };
    modulePrint.openPresentation(presentation, () => printReceiptLegacy(receipt), addaId);
  }

  function printFilteredReport() {
    const total = filtered.reduce((sum, receipt) => sum + receipt.amount, 0);
    const presentation: ModulePrintPresentation = {
      documentType: "payment_receipt",
      title: printLabel("paymentReceipts.print.reportTitle"),
      fields: [{ label: printLabel("common.fromDate"), value: printValue(fromDate) }, { label: printLabel("common.toDate"), value: printValue(toDate) }],
      totals: [{ label: printLabel("common.total"), value: printValue(formatAmount(total)) }],
      tables: [{
        columns: ["paymentReceipts.receiptNo", "common.date", "paymentReceipts.loading", "common.party", "common.amount", "paymentReceipts.method"].map(printLabel),
        rows: filtered.map((receipt) => [printValue(receipt.receipt_no), printValue(receipt.receipt_date), printValue(receipt.loadings?.loading_no), printValue(receiptPartyName(receipt)), printValue(formatAmount(receipt.amount)), printLabel(`paymentReceipts.paymentMethods.${paymentMethodKey(receipt.payment_method)}`)]),
      }],
    };
    modulePrint.openPresentation(presentation, printFilteredReportLegacy, addaId);
  }

  return (
    <section dir={dir} className="rounded-xl bg-white p-5 text-gray-900 shadow-md md:p-6">
      <h2 className="mb-6 text-2xl font-bold text-gray-900">{t("paymentReceipts.history")}</h2>



      <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-5">
        <VoiceTypingField fieldLabel={t("common.actions.search")} mode="text"><input type="search" aria-label={t("common.actions.search")} placeholder={t("paymentReceipts.searchPlaceholder")} value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 placeholder:text-gray-600 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100" /></VoiceTypingField>
        <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input type="date" aria-label={t("common.fromDate")} dir="ltr" value={fromDate} onChange={(e) => { setFromDate(e.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100" /></VoiceTypingField>
        <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input type="date" aria-label={t("common.toDate")} dir="ltr" value={toDate} onChange={(e) => { setToDate(e.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100" /></VoiceTypingField>
        <select aria-label={t("paymentReceipts.method")} value={method} onChange={(e) => { setMethod(e.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"><option value="">{t("paymentReceipts.allMethods")}</option>{["Cash","Bank","Cheque","Online Transfer","Account"].map((item) => <option key={item} value={item}>{t(`paymentReceipts.paymentMethods.${paymentMethodKey(item)}`)}</option>)}</select>
        <div className="flex gap-2"><button type="button" onClick={resetFilters} className="flex-1 rounded-lg border border-gray-300 bg-white px-5 py-3 font-bold text-gray-900 hover:bg-gray-50">{t("common.actions.reset")}</button><button type="button" onClick={printFilteredReport} className="flex-1 rounded-lg bg-green-600 px-5 py-3 font-bold text-white">{t("common.actions.print")}</button></div>
      </div>

      {isLoading && <div className="mt-6 rounded-lg bg-blue-50 p-6 text-center font-bold">{t("common.loading")}</div>}
      {!isLoading && errorMessage && <div className="mt-6 rounded-lg bg-red-50 p-6 text-center font-bold text-red-700">{errorMessage}</div>}
      {!isLoading && !errorMessage && (
        <div className="mt-6 overflow-x-auto rounded-lg border border-gray-300">
          <table className="w-full min-w-[1050px] border-collapse text-sm text-gray-900">
            <thead><tr className="bg-blue-600 text-white"><th className="p-3 text-start">{t("paymentReceipts.receiptNo")}</th><th className="p-3 text-start">{t("common.date")}</th><th className="p-3 text-start">{t("paymentReceipts.loading")}</th><th className="p-3 text-start">{t("common.party")}</th><th className="p-3 text-end">{t("common.amount")}</th><th className="p-3 text-start">{t("paymentReceipts.method")}</th><th className="p-3 text-start">{t("common.actions.title")}</th></tr></thead>
            <tbody>
              {visible.length === 0 && <tr><td colSpan={7} className="border p-8 text-center">{t("paymentReceipts.empty")}</td></tr>}
              {visible.map((receipt) => <tr key={receipt.id} className="border-b hover:bg-gray-50"><td dir="ltr" className="p-3 font-bold">{receipt.receipt_no}</td><td dir="ltr" className="p-3">{receipt.receipt_date}</td><td dir="ltr" className="p-3">{receipt.loadings?.loading_no ?? "-"}</td><td className="p-3">{receiptPartyName(receipt)}</td><td dir="ltr" className="p-3 text-end font-bold">{formatAmount(receipt.amount)}</td><td className="p-3">{t(`paymentReceipts.paymentMethods.${paymentMethodKey(receipt.payment_method)}`)}</td><td className="p-3"><div className="flex flex-wrap gap-2"><button type="button" aria-label={`${t("common.actions.view")} ${receipt.receipt_no}`} onClick={() => setViewing(receipt)} className="rounded bg-gray-800 px-3 py-2 text-white">{t("common.actions.view")}</button><button type="button" aria-label={`${t("common.actions.edit")} ${receipt.receipt_no}`} onClick={() => onEdit(receipt)} className="rounded bg-blue-600 px-3 py-2 text-white">{t("common.actions.edit")}</button><button type="button" aria-label={`${t("common.actions.delete")} ${receipt.receipt_no}`} disabled={deletingId !== null} onClick={() => onDelete(receipt)} className="rounded bg-red-600 px-3 py-2 text-white disabled:opacity-50">{deletingId === receipt.id ? t("common.states.deleting") : t("common.actions.delete")}</button><button type="button" aria-label={`${t("common.actions.print")} ${receipt.receipt_no}`} onClick={() => printReceipt(receipt)} className="rounded bg-green-600 px-3 py-2 text-white">{t("common.actions.print")}</button></div></td></tr>)}
            </tbody>
          </table>
        </div>
      )}
      {!isLoading && filtered.length > 0 && <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-gray-900"><span className="font-bold">{t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}</span><div className="flex gap-2"><button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button><button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button></div></div>}
      {viewing && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"><div role="dialog" aria-modal="true" aria-labelledby="receipt-details-title" className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 shadow-xl sm:p-6"><h3 id="receipt-details-title" className="text-2xl font-bold">{t("paymentReceipts.detailsTitle")}</h3><dl className="mt-5 grid grid-cols-1 gap-4 sm:grid-cols-2"><div><dt className="font-bold">{t("paymentReceipts.receiptNo")}</dt><dd dir="ltr">{viewing.receipt_no}</dd></div><div><dt className="font-bold">{t("common.date")}</dt><dd dir="ltr">{viewing.receipt_date}</dd></div><div><dt className="font-bold">{t("common.party")}</dt><dd>{receiptPartyName(viewing)}</dd></div><div><dt className="font-bold">{t("common.amount")}</dt><dd dir="ltr">{formatAmount(viewing.amount)}</dd></div><div className="sm:col-span-2"><dt className="font-bold">{t("common.remarks")}</dt><dd>{viewing.remarks ?? "-"}</dd></div></dl><div className="mt-6 flex gap-3"><button ref={closeRef} type="button" onClick={() => setViewing(null)} className="rounded-lg bg-slate-700 px-5 py-3 font-bold text-white hover:bg-slate-800">{t("common.actions.close")}</button><button type="button" onClick={() => printReceipt(viewing)} className="rounded-lg bg-emerald-600 px-5 py-3 font-bold text-white hover:bg-emerald-700">{t("common.actions.print")}</button></div></div></div>}
      {modulePrint.dialog}
    </section>
  );
}

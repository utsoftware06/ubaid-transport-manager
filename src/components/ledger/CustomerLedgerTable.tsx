"use client";

import { useMemo, useState } from "react";
import {
  type CustomerLedgerRow,
  formatCurrency,
} from "./CustomerLedger";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import type { CustomerLedgerSummary } from "./CustomerLedger";
type Props = {
  rows: CustomerLedgerRow[];
  summary: CustomerLedgerSummary;
  fromDate: string;
  toDate: string;
  isLoading: boolean;
  errorMessage: string;
};

const PAGE_SIZE = 10;

function getStatusClass(status: CustomerLedgerRow["paymentStatus"]) {
  if (status === "Paid") {
    return "bg-green-100 text-green-700 border-green-200";
  }

  if (status === "Partial") {
    return "bg-yellow-100 text-yellow-700 border-yellow-200";
  }

  return "bg-red-100 text-red-700 border-red-200";
}

export default function CustomerLedgerTable({
  rows,
  summary,
  fromDate,
  toDate,
  isLoading,
  errorMessage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const ownerAddaId = singleResolvedAddaId(rows.map((row) => row.addaId));
  const modulePrint = useModuleTransportPrint("customer_ledger", ownerAddaId, language === "ur" ? "ur" : "en");
  const [currentPage, setCurrentPage] = useState(1);
  const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const visibleRows = useMemo(
    () =>
      rows.slice(
        (safeCurrentPage - 1) * PAGE_SIZE,
        safeCurrentPage * PAGE_SIZE
      ),
    [rows, safeCurrentPage]
  );

  function handlePrintLegacy() {
    if (rows.length === 0) return;
    const printWindow = window.open("", "_blank", "width=1100,height=800");
    if (!printWindow) {
      window.alert(t("reports.messages.allowPopups"));
      return;
    }
    const rowHtml = rows
      .map(
        (row) => `<tr>
          <td class="technical">${escapeHtml(row.date)}</td>
          <td class="technical">${escapeHtml(row.bookingNo)}</td>
          <td>${escapeHtml(row.sender)}</td>
          <td>${escapeHtml(row.receiver)}</td>
          <td>${escapeHtml(row.route)}</td>
          <td class="technical">${escapeHtml(formatCurrency(row.freight))}</td>
          <td class="technical">${escapeHtml(formatCurrency(row.totalReceived))}</td>
          <td class="technical">${escapeHtml(formatCurrency(row.remainingAmount))}</td>
        </tr>`
      )
      .join("");
    const addaIds = Array.from(new Set(rows.map((row) => row.addaId).filter((id): id is string => Boolean(id))));
    void writeAddaBrandedPrintDocument(printWindow, `<!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
      <head><title>${escapeHtml(t("customerLedger.title"))}</title>
      <style>
        @page { size: A4 landscape; margin: 10mm; }
        body { font-family: Arial,sans-serif; color:#111827; direction:${dir}; }
        h1,h2 { text-align:center; }
        table { width:100%; border-collapse:collapse; font-size:12px; }
        th,td { border:1px solid #d1d5db; padding:8px; text-align:start; }
        th { background:#2563eb; color:white; }
        .technical { direction:ltr; unicode-bidi:isolate; text-align:end; }
      </style></head><body>
      <h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${escapeHtml(t("customerLedger.title"))}</h2>
      <table><thead><tr>
        <th>${escapeHtml(t("common.date"))}</th>
        <th>${escapeHtml(t("common.bookingNo"))}</th>
        <th>${escapeHtml(t("common.sender"))}</th>
        <th>${escapeHtml(t("common.receiver"))}</th>
        <th>${escapeHtml(t("common.route"))}</th>
        <th>${escapeHtml(t("common.freight"))}</th>
        <th>${escapeHtml(t("customerLedger.table.totalReceived"))}</th>
        <th>${escapeHtml(t("common.remaining"))}</th>
      </tr></thead><tbody>${rowHtml}</tbody></table>
      <script>window.onload=function(){window.print();window.onafterprint=function(){window.close();};};</script>
      </body></html>`, addaIds.length === 1 ? addaIds[0] : null, language === "ur" ? "ur" : "en");
  }
  function handlePrint() {
    const statusKeys: Record<CustomerLedgerRow["paymentStatus"], string> = { Paid: "common.paymentStatus.paid", Partial: "common.paymentStatus.partial", Unpaid: "common.paymentStatus.unpaid" };
    const presentation: ModulePrintPresentation = {
      documentType: "customer_ledger",
      title: printLabel("customerLedger.table.title"),
      subtitle: printLabel("customerLedger.description"),
      fields: [
        { label: printLabel("common.fromDate"), value: printValue(fromDate) },
        { label: printLabel("common.toDate"), value: printValue(toDate) },
        { label: printLabel("customerLedger.summary.totalBookings"), value: printValue(summary.totalBookings) },
      ],
      totals: [
        { label: printLabel("customerLedger.summary.totalFreight"), value: formatCurrency(summary.totalFreight) },
        { label: printLabel("customerLedger.summary.receivedAmount"), value: formatCurrency(summary.receivedAmount) },
        { label: printLabel("customerLedger.summary.pendingAmount"), value: formatCurrency(summary.pendingAmount) },
      ],
      tables: [{
        columns: ["common.date", "common.bookingNo", "common.sender", "common.receiver", "common.route", "common.freight", "customerLedger.table.totalReceived", "common.remaining", "common.status"].map(printLabel),
        rows: rows.map((row) => [printValue(row.date), printValue(row.bookingNo), printValue(row.sender), printValue(row.receiver), printValue(row.route), formatCurrency(row.freight), formatCurrency(row.totalReceived), formatCurrency(row.remainingAmount), printLabel(statusKeys[row.paymentStatus])]),
      }],
    };
    modulePrint.openPresentation(presentation, handlePrintLegacy, ownerAddaId);
  }
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("customerLedger.table.title")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("customerLedger.table.description")}
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrint}
          disabled={rows.length === 0}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-gray-400"
        >
          {t("common.actions.printReport")}
        </button>
      </div>

      {isLoading && (
        <div className="mt-6 rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("customerLedger.loading")}
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("customerLedger.table.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto">
          <table className="w-full min-w-[1200px] border-collapse text-left">
            <thead>
              <tr className="bg-blue-600 text-white">
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.date")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.bookingNo")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.sender")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.receiver")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.route")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  {t("common.freight")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  {t("common.advance")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  {t("common.receipts")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  {t("customerLedger.table.totalReceived")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  {t("common.remaining")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-center text-sm font-bold">
                  {t("common.status")}
                </th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {visibleRows.map((row) => (
                <tr
                  key={row.bookingId}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.date}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                    {row.bookingNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.sender}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.receiver}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.route}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatCurrency(row.freight)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatCurrency(row.advanceAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatCurrency(row.receiptAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold text-green-700">
                    {formatCurrency(row.totalReceived)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold text-red-700">
                    {formatCurrency(row.remainingAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.paymentStatus
                      )}`}
                    >
                      {t(`common.paymentStatus.${row.paymentStatus.toLowerCase()}`)}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td
                  colSpan={5}
                  className="px-4 py-4 text-sm font-extrabold"
                >
                  {t("common.total")}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold">
                  {formatCurrency(
                    rows.reduce((total, row) => total + row.freight, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold">
                  {formatCurrency(
                    rows.reduce((total, row) => total + row.advanceAmount, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold">
                  {formatCurrency(
                    rows.reduce((total, row) => total + row.receiptAmount, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold text-green-700">
                  {formatCurrency(
                    rows.reduce((total, row) => total + row.totalReceived, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold text-red-700">
                  {formatCurrency(
                    rows.reduce((total, row) => total + row.remainingAmount, 0)
                  )}
                </td>
                <td className="px-4 py-4" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <nav
          aria-label={t("common.pagination.page")}
          className="mt-5 flex flex-wrap items-center justify-center gap-3"
        >
          <button
            type="button"
            onClick={() => setCurrentPage((page) => Math.max(1, page - 1))}
            disabled={safeCurrentPage === 1}
            className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
          >
            {t("common.pagination.previous")}
          </button>
          <span dir="ltr" aria-current="page" className="font-bold text-gray-900">
            {t("common.pagination.page")} {safeCurrentPage} {t("common.pagination.of")} {totalPages}
          </span>
          <button
            type="button"
            onClick={() =>
              setCurrentPage((page) => Math.min(totalPages, page + 1))
            }
            disabled={safeCurrentPage === totalPages}
            className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
          >
            {t("common.pagination.next")}
          </button>
        </nav>
      )}
      {modulePrint.dialog}
    </div>
  );
}

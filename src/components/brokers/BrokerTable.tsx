"use client";

import { useState } from "react";
import { type BrokerRow, formatAmount } from "./Brokers";
import { useLanguage } from "@/contexts/LanguageContext";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import LedgerStatementPrintButton from "@/components/print/LedgerStatementPrint";
import { brokerLedgerPrintPresentation } from "./brokerLedgerPrintPresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  rows: BrokerRow[];
  addaId: string;
  search: string;
  setSearch: (value: string) => void;
  onEdit: (broker: BrokerRow) => void;
  onDelete: (broker: BrokerRow) => void;
  onViewLedger: (broker: BrokerRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
};

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getStatusClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") return "border-green-200 bg-green-100 text-green-700";
  return "border-blue-200 bg-blue-100 text-blue-700";
}

export default function BrokerTable({
  rows,
  addaId,
  search,
  setSearch,
  onEdit,
  onDelete,
  onViewLedger,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const [page, setPage] = useState(1);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(rows.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleRows = rows.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );
  const transactionTypeLabel = (type: string) => {
    const keys: Record<string, string> = {
      "Broker Payable": "payable",
      "Payment To Broker": "paymentTo",
      "Payment From Broker": "paymentFrom",
      "Advance To Broker": "advanceTo",
      Adjustment: "adjustment",
    };
    const key = keys[type];
    return key ? t(`brokers.transactionTypes.${key}`) : type;
  };
  const totals = rows.reduce(
    (total, broker) => ({
      opening: total.opening + broker.openingBalance,
      payable: total.payable + broker.totalPayable,
      paid: total.paid + broker.paymentToBroker,
      received: total.received + broker.paymentFromBroker,
      advanceToBroker: total.advanceToBroker + broker.advanceToBroker,
      current: total.current + broker.currentBalance,
      payableAmount: total.payableAmount + broker.payableAmount,
      advanceAmount: total.advanceAmount + broker.advanceAmount,
    }),
    {
      opening: 0,
      payable: 0,
      paid: 0,
      received: 0,
      advanceToBroker: 0,
      current: 0,
      payableAmount: 0,
      advanceAmount: 0,
    }
  );

  function handlePrintLedger(broker: BrokerRow) {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("brokers.messages.allowPopups"));
      return;
    }

    const rowsHtml =
      broker.transactions.length > 0
        ? broker.transactions
            .map(
              (transaction) => `
                <tr>
                  <td>${escapeHtml(transaction.transactionDate)}</td>
                  <td>${escapeHtml(transactionTypeLabel(transaction.transactionType))}</td>
                  <td>${escapeHtml(transaction.description)}</td>
                  <td>${escapeHtml(transaction.loadingNo)}</td>
                  <td>${escapeHtml(transaction.vehicleNo)}</td>
                  <td>${escapeHtml(transaction.driverName)}</td>
                  <td>${escapeHtml(formatAmount(transaction.amount))}</td>
                  <td>${escapeHtml(formatAmount(transaction.runningBalance))}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="8" class="empty">${escapeHtml(t("brokers.transactions.empty"))}</td></tr>`;

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("brokers.printLedger"))} - ${escapeHtml(broker.brokerName)}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 10mm; }
            body { margin: 0; color: #111827; font-family: Arial, sans-serif; direction: ${dir}; text-align: start; }
            .header { display: flex; justify-content: space-between; border-bottom: 2px solid #111827; padding-bottom: 14px; margin-bottom: 16px; }
            h1 { margin: 0; font-size: 28px; }
            h2 { margin: 4px 0 0; font-size: 18px; }
            .meta { text-align: end; font-size: 13px; line-height: 1.7; }
            .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 16px; }
            .box { border: 1px solid #d1d5db; border-radius: 8px; padding: 10px; }
            .box-title { font-size: 11px; font-weight: 700; }
            .box-value { margin-top: 4px; font-size: 15px; font-weight: 800; }
            table { width: 100%; border-collapse: collapse; font-size: 10px; }
            th { background: #2563eb; color: #fff; text-align: start; padding: 7px; border: 1px solid #2563eb; }
            td { padding: 7px; border: 1px solid #d1d5db; }
            .empty { text-align: center; font-weight: 700; padding: 16px; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(t("brokers.printLedger"))}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("brokers.broker"))}:</strong> ${escapeHtml(broker.brokerName)}</div>
              <div><strong>${escapeHtml(t("brokers.printed"))}:</strong> ${escapeHtml(new Date().toLocaleString("en-PK"))}</div>
            </div>
          </div>

          <div class="summary">
            <div class="box"><div class="box-title">${escapeHtml(t("common.openingBalance"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.openingBalance))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokers.payable"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.payableAmount))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokers.advance"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.advanceAmount))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokers.currentBalance"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.currentBalance))}</div></div>
          </div>

          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("common.date"))}</th>
                <th>${escapeHtml(t("brokers.transactions.type"))}</th>
                <th>${escapeHtml(t("common.description"))}</th>
                <th>${escapeHtml(t("paymentReceipts.loading"))}</th>
                <th>${escapeHtml(t("common.vehicle"))}</th>
                <th>${escapeHtml(t("common.driver"))}</th>
                <th>${escapeHtml(t("common.amount"))}</th>
                <th>${escapeHtml(t("brokers.runningBalance"))}</th>
              </tr>
            </thead>
            <tbody>${rowsHtml}</tbody>
          </table>

          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };
          </script>
        </body>
      </html>
    `, addaId, language === "ur" ? "ur" : "en");
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">

      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">{t("brokers.title")}</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("brokers.tableDescription")}
          </p>
        </div>

        <VoiceTypingField fieldLabel={t("brokers.searchPlaceholder")} mode="text"><input
          type="text"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(1);
          }}
          placeholder={t("brokers.searchPlaceholder")}
          className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        /></VoiceTypingField>
      </div>


      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("brokers.loading")}
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("brokers.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-300">
          <table className="w-full min-w-[1550px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("brokers.name")}</th>
                <th className="p-3 text-start font-bold">{t("brokers.contactPerson")}</th>
                <th className="p-3 text-start font-bold">{t("brokers.phone")}</th>
                <th className="p-3 text-end font-bold">{t("common.openingBalance")}</th>
                <th className="p-3 text-end font-bold">{t("brokers.cards.totalPayable")}</th>
                <th className="p-3 text-end font-bold">{t("brokers.paidToBroker")}</th>
                <th className="p-3 text-end font-bold">{t("brokers.receivedFromBroker")}</th>
                <th className="p-3 text-end font-bold">{t("brokers.advanceToBroker")}</th>
                <th className="p-3 text-end font-bold">{t("brokers.currentBalance")}</th>
                <th className="p-3 text-end font-bold">{t("brokers.payable")}</th>
                <th className="p-3 text-end font-bold">{t("brokers.advance")}</th>
                <th className="p-3 text-start font-bold">{t("common.status")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody>
              {visibleRows.map((broker) => (
                <tr
                  key={broker.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 font-bold">{broker.brokerName}</td>
                  <td className="p-3 font-semibold">{broker.contactPerson}</td>
                  <td dir="ltr" className="p-3 font-semibold">{broker.phone}</td>
                  <td className="p-3 text-right font-bold">
                    {formatAmount(broker.openingBalance)}
                  </td>
                  <td className="p-3 text-right font-bold">
                    {formatAmount(broker.totalPayable)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(broker.paymentToBroker)}
                  </td>
                  <td className="p-3 text-right font-bold text-blue-700">
                    {formatAmount(broker.paymentFromBroker)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(broker.advanceToBroker)}
                  </td>
                  <td
                    className={`p-3 text-right font-extrabold ${
                      broker.currentBalance > 0
                        ? "text-red-700"
                        : broker.currentBalance < 0
                          ? "text-green-700"
                          : "text-blue-700"
                    }`}
                  >
                    {formatAmount(broker.currentBalance)}
                  </td>
                  <td className="p-3 text-right font-extrabold text-red-700">
                    {formatAmount(broker.payableAmount)}
                  </td>
                  <td className="p-3 text-right font-extrabold text-green-700">
                    {formatAmount(broker.advanceAmount)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        broker.balanceStatus
                      )}`}
                    >
                      {t(`brokers.statuses.${broker.balanceStatus.toLowerCase()}`)}
                    </span>
                  </td>
                  <td className="min-w-[300px] p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        aria-label={`${t("common.actions.edit")} ${broker.brokerName}`}
                        onClick={() => onEdit(broker)}
                        className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white hover:bg-blue-700"
                      >
                        {t("common.actions.edit")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("common.actions.delete")} ${broker.brokerName}`}
                        onClick={() => onDelete(broker)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        {t("common.actions.delete")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("brokers.viewLedger")} ${broker.brokerName}`}
                        onClick={() => onViewLedger(broker)}
                        className="rounded-lg bg-green-600 px-3 py-2 font-semibold text-white hover:bg-green-700"
                      >
                        {t("brokers.viewLedger")}
                      </button>
                      <LedgerStatementPrintButton
                        addaId={addaId}
                        documentType="broker_ledger"
                        initialLanguage={language === "ur" ? "ur" : "en"}
                        makePresentation={(printLanguage) => brokerLedgerPrintPresentation(broker, broker.transactions, broker.transactions, addaId, printLanguage)}
                        fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"}
                        onLegacyPrint={() => handlePrintLedger(broker)}
                      >
                        <button
                          type="button"
                          aria-label={`${t("common.actions.printLedger")} ${broker.brokerName}`}
                          className="rounded-lg bg-gray-900 px-3 py-2 font-semibold text-white hover:bg-gray-800"
                        >
                          {t("common.actions.printLedger")}
                        </button>
                      </LedgerStatementPrintButton>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-white text-gray-900">
                <td colSpan={3} className="p-3 font-extrabold">
                  {t("common.total")}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totals.opening)}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totals.payable)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totals.paid)}
                </td>
                <td className="p-3 text-right font-extrabold text-blue-700">
                  {formatAmount(totals.received)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totals.advanceToBroker)}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totals.current)}
                </td>
                <td className="p-3 text-right font-extrabold text-red-700">
                  {formatAmount(totals.payableAmount)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totals.advanceAmount)}
                </td>
                <td colSpan={2} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-gray-900">
          <span className="font-bold">
            {t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}
          </span>
          <div className="flex gap-2">
            <button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">
              {t("common.pagination.previous")}
            </button>
            <button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">
              {t("common.pagination.next")}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

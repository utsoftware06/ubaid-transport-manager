"use client";

import { useMemo, useState } from "react";
import {
  type BrokerRow,
  type BrokerTransactionRow,
  formatAmount,
  getTransactionEffect,
} from "./Brokers";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import LedgerStatementPrintButton from "@/components/print/LedgerStatementPrint";
import { brokerLedgerPrintPresentation } from "./brokerLedgerPrintPresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import BrokerLoadingHistory from "@/components/brokers/BrokerLoadingHistory";
import BrokerParchiAccount from "@/components/brokers/BrokerParchiAccount";

type Props = {
  broker: BrokerRow;
  addaId: string;
  onClose: () => void;
  onEditTransaction: (transaction: BrokerTransactionRow) => void;
  onDeleteTransaction: (transaction: BrokerTransactionRow) => void;
  isDeleting: boolean;
};

function getStatusClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") return "border-green-200 bg-green-100 text-green-700";
  return "border-blue-200 bg-blue-100 text-blue-700";
}

function isDebit(transaction: BrokerTransactionRow) {
  return getTransactionEffect(transaction.transactionType, transaction.amount) > 0;
}

export default function BrokerLedger({
  broker,
  addaId,
  onClose,
  onEditTransaction,
  onDeleteTransaction,
  isDeleting,
}: Props) {
  const { t, dir, language } = useLanguage();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [transactionTypeFilter, setTransactionTypeFilter] = useState("");
  const [paymentMethodFilter, setPaymentMethodFilter] = useState("");
  const filteredTransactions = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    return broker.transactions.filter((transaction) => {
      if (fromDate && transaction.transactionDate < fromDate) return false;
      if (toDate && transaction.transactionDate > toDate) return false;
      if (transactionTypeFilter && transaction.transactionType !== transactionTypeFilter) return false;
      if (paymentMethodFilter && transaction.paymentMethod !== paymentMethodFilter) return false;
      if (!keyword) return true;
      return [
        transaction.description,
        transaction.referenceNo,
        transaction.loadingNo,
        transaction.vehicleNo,
        transaction.driverName,
      ].join(" ").toLowerCase().includes(keyword);
    });
  }, [broker.transactions, fromDate, paymentMethodFilter, search, toDate, transactionTypeFilter]);
  const pageSize = 10;
  const totalPages = Math.max(
    1,
    Math.ceil(filteredTransactions.length / pageSize)
  );
  const currentPage = Math.min(page, totalPages);
  const visibleTransactions = filteredTransactions.slice(
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
  const paymentMethodLabel = (method: string) => {
    const keys: Record<string, string> = {
      Cash: "cash",
      Bank: "bank",
      Cheque: "cheque",
      "Online Transfer": "onlineTransfer",
      Account: "account",
    };
    const key = keys[method];
    return key ? t(`brokers.paymentMethods.${key}`) : method;
  };
  const statusLabel = (status: string) =>
    t(`brokers.statuses.${status.toLowerCase()}`);

  function handlePrintEntry(transaction: BrokerTransactionRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert(t("brokerLedger.messages.allowEntryPopups"));
      return;
    }

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("brokerLedger.print.entryTitle"))} - ${escapeHtml(broker.brokerName)}</title>
          <style>
            body { margin: 0; padding: 32px; color: #111827; font-family: Arial, sans-serif; direction: ${dir}; text-align: start; }
            .slip { max-width: 850px; margin: 0 auto; border: 1px solid #d1d5db; border-radius: 10px; padding: 28px; }
            .header { display: flex; justify-content: space-between; border-bottom: 2px solid #111827; padding-bottom: 18px; margin-bottom: 22px; }
            h1 { margin: 0; font-size: 28px; }
            h2 { margin: 6px 0 0; font-size: 18px; }
            .details { display: grid; grid-template-columns: repeat(2, 1fr); gap: 14px 24px; font-size: 15px; }
            .details div { border-bottom: 1px solid #e5e7eb; padding-bottom: 8px; }
            .technical { direction: ltr; unicode-bidi: isolate; }
          </style>
        </head>
        <body>
          <div class="slip">
            <div class="header">
              <div>
                <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
                <h2>${escapeHtml(t("brokerLedger.print.transactionTitle"))}</h2>
              </div>
              <div>
                <strong>${escapeHtml(t("common.date"))}:</strong> <span class="technical">${escapeHtml(transaction.transactionDate)}</span>
              </div>
            </div>
            <div class="details">
              <div><strong>${escapeHtml(t("brokers.broker"))}:</strong> ${escapeHtml(broker.brokerName)}</div>
              <div><strong>${escapeHtml(t("brokers.transactions.type"))}:</strong> ${escapeHtml(transactionTypeLabel(transaction.transactionType))}</div>
              <div><strong>${escapeHtml(t("common.amount"))}:</strong> <span class="technical">${escapeHtml(formatAmount(transaction.amount))}</span></div>
              <div><strong>${escapeHtml(t("brokerLedger.payment"))}:</strong> ${escapeHtml(paymentMethodLabel(transaction.paymentMethod))}</div>
              <div><strong>${escapeHtml(t("brokerLedger.reference"))}:</strong> <span class="technical">${escapeHtml(transaction.referenceNo)}</span></div>
              <div><strong>${escapeHtml(t("paymentReceipts.loading"))}:</strong> <span class="technical">${escapeHtml(transaction.loadingNo)}</span></div>
              <div><strong>${escapeHtml(t("common.vehicle"))}:</strong> <span class="technical">${escapeHtml(transaction.vehicleNo)}</span></div>
              <div><strong>${escapeHtml(t("common.driver"))}:</strong> ${escapeHtml(transaction.driverName)}</div>
              <div><strong>${escapeHtml(t("common.description"))}:</strong> ${escapeHtml(transaction.description)}</div>
              <div><strong>${escapeHtml(t("common.remarks"))}:</strong> ${escapeHtml(transaction.remarks)}</div>
              <div><strong>${escapeHtml(t("brokers.runningBalance"))}:</strong> <span class="technical">${escapeHtml(formatAmount(transaction.runningBalance))}</span></div>
            </div>
          </div>
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

  function handlePrintLedger() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("brokerLedger.messages.allowLedgerPopups"));
      return;
    }

    const rowsHtml =
      filteredTransactions.length > 0
        ? filteredTransactions
            .map((transaction) => {
              const debit = isDebit(transaction) ? transaction.amount : 0;
              const credit = !isDebit(transaction) ? transaction.amount : 0;

              return `
                <tr>
                  <td class="technical">${escapeHtml(transaction.transactionDate)}</td>
                  <td>${escapeHtml(transactionTypeLabel(transaction.transactionType))}</td>
                  <td>${escapeHtml(transaction.description)}</td>
                  <td class="technical">${escapeHtml(transaction.loadingNo)}</td>
                  <td class="technical">${escapeHtml(transaction.vehicleNo)}</td>
                  <td>${escapeHtml(transaction.driverName)}</td>
                  <td>${escapeHtml(paymentMethodLabel(transaction.paymentMethod))}</td>
                  <td class="technical">${escapeHtml(transaction.referenceNo)}</td>
                  <td class="technical">${debit ? escapeHtml(formatAmount(debit)) : "-"}</td>
                  <td class="technical">${credit ? escapeHtml(formatAmount(credit)) : "-"}</td>
                  <td class="technical">${escapeHtml(formatAmount(transaction.runningBalance))}</td>
                </tr>
              `;
            })
            .join("")
        : `<tr><td colspan="11" class="empty">${escapeHtml(t("brokerLedger.empty"))}</td></tr>`;

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("brokerLedger.title"))} - ${escapeHtml(broker.brokerName)}</title>
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
            .technical, .box-value { direction: ltr; unicode-bidi: isolate; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(t("brokerLedger.title"))}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("brokers.broker"))}:</strong> ${escapeHtml(broker.brokerName)}</div>
              <div><strong>${escapeHtml(t("brokers.phone"))}:</strong> <span class="technical">${escapeHtml(broker.phone)}</span></div>
              <div><strong>${escapeHtml(t("brokers.printed"))}:</strong> <span class="technical">${escapeHtml(new Date().toLocaleString("en-PK"))}</span></div>
            </div>
          </div>

          <div class="summary">
            <div class="box"><div class="box-title">${escapeHtml(t("common.openingBalance"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.openingBalance))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokerLedger.totalPayable"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.totalPayable))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokerLedger.totalPaid"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.paymentToBroker + broker.advanceToBroker))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokerLedger.totalReceived"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.paymentFromBroker))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokers.advance"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.advanceAmount))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("brokers.currentBalance"))}</div><div class="box-value">${escapeHtml(formatAmount(broker.currentBalance))}</div></div>
            <div class="box"><div class="box-title">${escapeHtml(t("common.status"))}</div><div class="box-value">${escapeHtml(statusLabel(broker.balanceStatus))}</div></div>
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
                <th>${escapeHtml(t("brokerLedger.payment"))}</th>
                <th>${escapeHtml(t("brokerLedger.reference"))}</th>
                <th>${escapeHtml(t("brokerLedger.debit"))}</th>
                <th>${escapeHtml(t("brokerLedger.credit"))}</th>
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
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("brokerLedger.title")}: {broker.brokerName}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("brokerLedger.contact")}: {broker.contactPerson} | {t("brokers.phone")}:{" "}
            <span dir="ltr">{broker.phone}</span>
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          <LedgerStatementPrintButton addaId={addaId} documentType="broker_ledger" initialLanguage={language} makePresentation={(printLanguage) => brokerLedgerPrintPresentation(broker, filteredTransactions, broker.transactions, addaId, printLanguage, false, { fromDate, toDate })} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={handlePrintLedger}>
            <button type="button" className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white hover:bg-gray-800">{t("brokerLedger.printFull")}</button>
          </LedgerStatementPrintButton>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 hover:bg-gray-300"
          >
            {t("common.actions.close")}
          </button>
        </div>
      </div>

      <div className="mb-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("brokerLedger.opening")}</p>
          <p dir="ltr" className="mt-2 text-lg font-extrabold text-gray-900">
            {formatAmount(broker.openingBalance)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("brokers.payable")}</p>
          <p dir="ltr" className="mt-2 text-lg font-extrabold text-red-700">
            {formatAmount(broker.payableAmount)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("brokers.advance")}</p>
          <p dir="ltr" className="mt-2 text-lg font-extrabold text-green-700">
            {formatAmount(broker.advanceAmount)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("brokers.currentBalance")}</p>
          <p
            dir="ltr"
            className={`mt-2 text-lg font-extrabold ${
              broker.currentBalance > 0
                ? "text-red-700"
                : broker.currentBalance < 0
                  ? "text-green-700"
                  : "text-blue-700"
            }`}
          >
            {formatAmount(broker.currentBalance)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("common.status")}</p>
          <span
            className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
              broker.balanceStatus
            )}`}
          >
            {statusLabel(broker.balanceStatus)}
          </span>
        </div>
      </div>

      <BrokerParchiAccount key={`parchi:${addaId}:${broker.id}`} addaId={addaId} brokerId={broker.id} />
      <BrokerLoadingHistory key={`${addaId}:${broker.id}`} addaId={addaId} brokerId={broker.id} />

      <section aria-labelledby="broker-generic-transactions-title">
      <h3 id="broker-generic-transactions-title" className="mb-3 text-lg font-bold text-gray-950">
        {t("brokers.genericTransactionsTitle")}
      </h3>

      <div className="mb-6 grid grid-cols-1 gap-4 rounded-xl border border-gray-300 bg-white p-4 shadow-sm md:grid-cols-2 xl:grid-cols-5">
        <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input type="date" dir="ltr" aria-label={t("common.fromDate")} value={fromDate} onChange={(event) => { setFromDate(event.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100" /></VoiceTypingField>
        <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input type="date" dir="ltr" aria-label={t("common.toDate")} value={toDate} onChange={(event) => { setToDate(event.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100" /></VoiceTypingField>
        <select aria-label={t("brokers.transactions.type")} value={transactionTypeFilter} onChange={(event) => { setTransactionTypeFilter(event.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100">
          <option value="">{t("common.all")}</option>
          {["Broker Payable", "Payment To Broker", "Payment From Broker", "Advance To Broker", "Adjustment"].map((type) => <option key={type} value={type}>{transactionTypeLabel(type)}</option>)}
        </select>
        <select aria-label={t("brokers.transactions.paymentMethod")} value={paymentMethodFilter} onChange={(event) => { setPaymentMethodFilter(event.target.value); setPage(1); }} className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100">
          <option value="">{t("common.all")}</option>
          {["Cash", "Bank", "Cheque", "Online Transfer", "Account"].map((method) => <option key={method} value={method}>{paymentMethodLabel(method)}</option>)}
        </select>

        <div className="flex gap-2">
          <VoiceTypingField fieldLabel={t("common.actions.search")} mode="text"><input type="search" aria-label={t("common.actions.search")} placeholder={t("common.actions.search")} value={search} onChange={(event) => { setSearch(event.target.value); setPage(1); }} className="min-w-0 flex-1 rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100" /></VoiceTypingField>
          <button type="button" onClick={() => { setSearch(""); setFromDate(""); setToDate(""); setTransactionTypeFilter(""); setPaymentMethodFilter(""); setPage(1); }} className="rounded-l
      g border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hov
      er:bg-gray-50">{t("common.actions.reset")}</button>
        </div>

      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-300">
        <table className="w-full min-w-[1450px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-start font-bold">{t("common.date")}</th>
              <th className="p-3 text-start font-bold">{t("brokers.transactions.type")}</th>
              <th className="p-3 text-start font-bold">{t("common.description")}</th>
              <th className="p-3 text-start font-bold">{t("paymentReceipts.loading")}</th>
              <th className="p-3 text-start font-bold">{t("common.vehicle")}</th>
              <th className="p-3 text-start font-bold">{t("common.driver")}</th>
              <th className="p-3 text-start font-bold">{t("brokers.transactions.paymentMethod")}</th>
              <th className="p-3 text-start font-bold">{t("brokers.transactions.referenceNo")}</th>
              <th className="p-3 text-end font-bold">{t("brokerLedger.debit")}</th>
              <th className="p-3 text-end font-bold">{t("brokerLedger.credit")}</th>
              <th className="p-3 text-end font-bold">{t("brokers.runningBalance")}</th>
              <th className="p-3 text-start font-bold">{t("common.status")}</th>
              <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
            </tr>
          </thead>

          <tbody>
            {filteredTransactions.length === 0 && (
              <tr>
                <td
                  colSpan={13}
                  className="p-8 text-center text-sm font-bold text-gray-900"
                >
                  {t("brokerLedger.empty")}
                </td>
              </tr>
            )}

            {visibleTransactions.map((transaction) => {
              const debit = isDebit(transaction) ? transaction.amount : 0;
              const credit = !isDebit(transaction) ? transaction.amount : 0;
              const status =
                transaction.runningBalance > 0
                  ? "Payable"
                  : transaction.runningBalance < 0
                    ? "Advance"
                    : "Settled";

              return (
                <tr
                  key={transaction.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td dir="ltr" className="p-3 font-semibold">
                    {transaction.transactionDate}
                  </td>
                  <td className="p-3 font-bold">
                    {transactionTypeLabel(transaction.transactionType)}
                  </td>
                  <td className="max-w-[260px] p-3 font-semibold">
                    {transaction.description}
                  </td>
                  <td dir="ltr" className="p-3 font-semibold">{transaction.loadingNo}</td>
                  <td dir="ltr" className="p-3 font-semibold">{transaction.vehicleNo}</td>
                  <td className="p-3 font-semibold">{transaction.driverName}</td>
                  <td dir="ltr" className="p-3 font-semibold">
                    {paymentMethodLabel(transaction.paymentMethod)}
                  </td>
                  <td className="p-3 font-semibold">
                    {transaction.referenceNo}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-red-700">
                    {debit ? formatAmount(debit) : "-"}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-green-700">
                    {credit ? formatAmount(credit) : "-"}
                  </td>
                  <td
                    dir="ltr"
                    className={`p-3 text-end font-extrabold ${
                      transaction.runningBalance > 0
                        ? "text-red-700"
                        : transaction.runningBalance < 0
                          ? "text-green-700"
                          : "text-blue-700"
                    }`}
                  >
                    {formatAmount(transaction.runningBalance)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        status
                      )}`}
                    >
                      {statusLabel(status)}
                    </span>
                  </td>
                  <td className="min-w-[230px] p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        aria-label={`${t("common.actions.edit")} ${transaction.referenceNo}`}
                        onClick={() => onEditTransaction(transaction)}
                        className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white hover:bg-blue-700"
                      >
                        {t("common.actions.edit")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("common.actions.delete")} ${transaction.referenceNo}`}
                        onClick={() => onDeleteTransaction(transaction)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        {t("common.actions.delete")}
                      </button>
                      <LedgerStatementPrintButton addaId={addaId} documentType="broker_ledger" initialLanguage={language} makePresentation={(printLanguage) => brokerLedgerPrintPresentation(broker, [transaction], broker.transactions, addaId, printLanguage, true)} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={() => handlePrintEntry(transaction)}>
                        <button type="button" aria-label={`${t("brokerLedger.printEntry")} ${transaction.referenceNo}`} className="rounded-lg bg-gray-900 px-3 py-2 font-semibold text-white hover:bg-gray-800">{t("brokerLedger.printEntry")}</button>
                      </LedgerStatementPrintButton>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {filteredTransactions.length > 0 && (
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
      </section>
    </div>
  );
}

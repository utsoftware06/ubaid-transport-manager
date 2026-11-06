"use client";

import {
  type PetrolPumpOption,
  type PetrolPumpPaymentRow,
  formatAmount,
} from "./PetrolPumpPayments";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import ManualDieselPaymentCorrectionPanel from "./ManualDieselPaymentCorrectionPanel";
import type { ManualDieselCorrectionHistoryView, ManualDieselLinkedPaymentView } from "./manualDieselPaymentTypes";

type Props = {
  rows: PetrolPumpPaymentRow[];
  addaId: string | null;
  search: string;
  setSearch: (value: string) => void;
  onEdit: (row: PetrolPumpPaymentRow) => void;
  onDelete: (row: PetrolPumpPaymentRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
  pumps: PetrolPumpOption[];
  manualDieselLinks: ManualDieselLinkedPaymentView[];
  correctionHistory: ManualDieselCorrectionHistoryView[];
  correctionSetupState: "ready" | "not_deployed" | "error" | "needs_adda";
  correctionLoadError?: string;
  canCorrectManualDieselPayments: boolean;
  onCorrectManualDieselPayment: (payment: ManualDieselLinkedPaymentView) => void;
};

function getStatusTextClass(status: string) {
  if (status === "Payable") return "text-red-700";
  if (status === "Advance") return "text-green-700";
  return "text-blue-700";
}

function getStatusBadgeClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") {
    return "border-green-200 bg-green-100 text-green-700";
  }

  return "border-blue-200 bg-blue-100 text-blue-700";
}

function getBalanceTextClass(balance: number) {
  if (balance > 0) return "text-red-700";
  if (balance < 0) return "text-green-700";
  return "text-blue-700";
}

export default function PetrolPumpPaymentTable({
  rows,
  addaId,
  search,
  setSearch,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
  pumps,
  manualDieselLinks,
  correctionHistory,
  correctionSetupState,
  correctionLoadError,
  canCorrectManualDieselPayments,
  onCorrectManualDieselPayment,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("petrol_pump", addaId, language);
  const statusLabel = (status: string) =>
    t(`petrolPumpPayments.statuses.${status.toLowerCase()}`);
  const methodLabel = (method: string) =>
    t(`petrolPumpPayments.paymentMethods.${method === "Online Transfer" ? "onlineTransfer" : method.toLowerCase()}`);
  const totalPayments = rows.reduce((total, row) => total + row.amount, 0);

  const linkedByPayment = new Map(manualDieselLinks.map((link) => [link.paymentId, link]));

  function getPump(row: PetrolPumpPaymentRow) {
    return pumps.find((item) => item.id === row.petrolPumpId) ?? null;
  }

  function handlePrintReceipt(row: PetrolPumpPaymentRow) {
    const receiptRows: Array<[string, string]> = [
      [t("common.date"), row.paymentDate], [t("petrolPumpPayments.fields.reference"), row.referenceNo],
      [t("petrolPumpPayments.fields.pump"), row.pumpName], [t("petrolPumps.fields.ownerName"), row.ownerName],
      [t("petrolPumpPayments.fields.paymentMethod"), methodLabel(row.paymentMethod)], [t("petrolPumpPayments.fields.remarks"), row.remarks],
      [t("petrolPumpPayments.fields.advanceUsed"), formatAmount(row.advanceUsed)], [t("petrolPumpPayments.fields.paymentNow"), formatAmount(row.paymentNow)],
      [t("common.total"), formatAmount(row.amount)], [t("common.remaining"), formatAmount(row.remainingPayable)], [t("common.status"), statusLabel(row.settlementStatus)],
    ];
    const linkedPayment = linkedByPayment.get(row.id);
    if (linkedPayment) receiptRows.push([
      t("petrolPumpPayments.correction.columns.voucher"),
      `${linkedPayment.voucherNumber} · ${linkedPayment.vehicleNo} · Diesel #${linkedPayment.dieselEntryId}`,
    ]);
    const body = `<div class="details">${receiptRows.map(([label,value])=>`<div><strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</div>`).join("")}</div>`;
    modulePrint.open(t("petrolPumpPayments.print.receiptTitle"), body, () => legacyPrintReceipt(row));
  }

  function legacyPrintReceipt(row: PetrolPumpPaymentRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert(t("petrolPumpPayments.messages.allowReceiptPopups"));
      return;
    }

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
        <head>
          <title>${escapeHtml(t("petrolPumpPayments.print.receiptTitle"))} - ${escapeHtml(row.pumpName)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .receipt {
              max-width: 850px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 28px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 18px;
              margin-bottom: 22px;
            }
            h1 { margin: 0; font-size: 28px; color: #111827; }
            h2 { margin: 6px 0 0; font-size: 18px; color: #111827; }
            .meta { text-align: end; font-size: 14px; line-height: 1.7; }
            .details {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 14px 24px;
              font-size: 15px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
            .amount {
              margin-top: 24px;
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 16px;
              font-size: 24px;
              font-weight: 800;
              text-align: center;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 40px;
              margin-top: 60px;
              font-size: 14px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 8px;
              text-align: center;
            }
          </style>
        </head>
        <body dir="${escapeHtml(dir)}">
          <div class="receipt">
            <div class="header">
              <div>
                <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
                <h2>${escapeHtml(t("petrolPumpPayments.print.receiptTitle"))}</h2>
              </div>
              <div class="meta">
                <div><strong>${escapeHtml(t("common.date"))}:</strong> <span dir="ltr">${escapeHtml(row.paymentDate)}</span></div>
                <div><strong>${escapeHtml(t("petrolPumpPayments.fields.reference"))}:</strong> <span dir="ltr">${escapeHtml(row.referenceNo)}</span></div>
              </div>
            </div>

            <div class="details">
              <div><strong>${escapeHtml(t("petrolPumpPayments.fields.pump"))}:</strong> ${escapeHtml(row.pumpName)}</div>
              <div><strong>${escapeHtml(t("petrolPumps.fields.ownerName"))}:</strong> ${escapeHtml(row.ownerName)}</div>
              <div><strong>${escapeHtml(t("petrolPumpPayments.fields.paymentMethod"))}:</strong> ${escapeHtml(methodLabel(row.paymentMethod))}</div>
              <div><strong>${escapeHtml(t("petrolPumpPayments.fields.remarks"))}:</strong> ${escapeHtml(row.remarks)}</div>
            </div>

            <div class="amount" dir="ltr">${escapeHtml(formatAmount(row.amount))}</div>
            <div>${escapeHtml(t("petrolPumpPayments.fields.advanceUsed"))}: <span dir="ltr">${escapeHtml(formatAmount(row.advanceUsed))}</span></div>
            <div>${escapeHtml(t("petrolPumpPayments.fields.paymentNow"))}: <span dir="ltr">${escapeHtml(formatAmount(row.paymentNow))}</span></div>

            <div class="signatures">
              <div class="signature">${escapeHtml(t("petrolPumpPayments.print.preparedBy"))}</div>
              <div class="signature">${escapeHtml(t("petrolPumpPayments.print.receivedBy"))}</div>
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

  function handlePrintReport() {
    const body = `<div class="grid"><div><strong>${escapeHtml(t("common.total"))}:</strong> ${escapeHtml(formatAmount(totalPayments))}</div></div><h2>${escapeHtml(t("petrolPumpPayments.print.paymentDetails"))}</h2><table><thead><tr>${["common.date","petrolPumpPayments.fields.pump","petrolPumpPayments.fields.paymentNow","common.total","common.status","petrolPumpPayments.fields.paymentMethod","petrolPumpPayments.fields.reference","common.remarks"].map(key=>`<th>${escapeHtml(t(key))}</th>`).join("")}</tr></thead><tbody>${rows.map(row=>`<tr><td>${escapeHtml(row.paymentDate)}</td><td>${escapeHtml(row.pumpName)}</td><td>${escapeHtml(formatAmount(row.paymentNow))}</td><td>${escapeHtml(formatAmount(row.amount))}</td><td>${escapeHtml(statusLabel(row.settlementStatus))}</td><td>${escapeHtml(methodLabel(row.paymentMethod))}</td><td>${escapeHtml(row.referenceNo)}</td><td>${escapeHtml(row.remarks)}</td></tr>`).join("")}</tbody></table><h2>${escapeHtml(t("petrolPumpPayments.print.balanceSummary"))}</h2><table><thead><tr>${["petrolPumpPayments.fields.pump","petrolPumps.fields.openingBalance","petrolPumps.cards.totalDiesel","petrolPumpPayments.fields.manualPayments","petrolPumpPayments.fields.payableAmount","petrolPumpPayments.fields.advanceAmount","common.status"].map(key=>`<th>${escapeHtml(t(key))}</th>`).join("")}</tr></thead><tbody>${pumps.map(pump=>`<tr><td>${escapeHtml(pump.pumpName)}</td><td>${escapeHtml(formatAmount(pump.openingBalance))}</td><td>${escapeHtml(formatAmount(pump.totalDiesel))}</td><td>${escapeHtml(formatAmount(pump.manualPayments))}</td><td>${escapeHtml(formatAmount(pump.payableAmount))}</td><td>${escapeHtml(formatAmount(pump.advanceAmount))}</td><td>${escapeHtml(statusLabel(pump.balanceStatus))}</td></tr>`).join("")}</tbody></table>`;
    modulePrint.open(t("petrolPumpPayments.print.reportTitle"), body, legacyPrintReport);
  }

  function legacyPrintReport() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("petrolPumpPayments.messages.allowReportPopups"));
      return;
    }

    const paymentRows =
      rows.length > 0
        ? rows
            .map((row) => {
              const pump = getPump(row);
              const currentBalance = pump?.currentBalance ?? 0;
              const payableAmount = pump?.payableAmount ?? 0;
              const advanceAmount = pump?.advanceAmount ?? 0;
              const status = pump?.balanceStatus ?? "Paid";

              return `
                <tr>
                  <td>${escapeHtml(row.paymentDate || "-")}</td>
                  <td>${escapeHtml(row.pumpName)}</td>
                  <td>${escapeHtml(row.ownerName)}</td>
                  <td>${escapeHtml(formatAmount(row.advanceUsed))}</td>
                  <td>${escapeHtml(formatAmount(row.paymentNow))}</td>
                  <td>${escapeHtml(formatAmount(row.amount))}</td>
                  <td class="${getStatusTextClass(status)}">${escapeHtml(
                    formatAmount(currentBalance)
                  )}</td>
                  <td class="text-red-700">${escapeHtml(
                    formatAmount(payableAmount)
                  )}</td>
                  <td class="text-green-700">${escapeHtml(
                    formatAmount(advanceAmount)
                  )}</td>
                  <td class="${getStatusTextClass(status)}">${escapeHtml(
                    statusLabel(status)
                  )}</td>
                  <td>${escapeHtml(methodLabel(row.paymentMethod))}</td>
                  <td>${escapeHtml(row.referenceNo)}</td>
                  <td>${escapeHtml(row.remarks)}</td>
                </tr>
              `;
            })
            .join("")
        : `<tr><td colspan="11" class="empty">${escapeHtml(t("petrolPumpPayments.empty"))}</td></tr>`;

    const pumpRows =
      pumps.length > 0
        ? pumps
            .map(
              (pump) => `
                <tr>
                  <td>${escapeHtml(pump.pumpName)}</td>
                  <td>${escapeHtml(formatAmount(pump.openingBalance))}</td>
                  <td>${escapeHtml(formatAmount(pump.totalDiesel))}</td>
                  <td>${escapeHtml(formatAmount(pump.manualPayments))}</td>
                  <td>${escapeHtml(formatAmount(pump.payableAmount))}</td>
                  <td>${escapeHtml(formatAmount(pump.advanceAmount))}</td>
                  <td class="${getStatusTextClass(pump.balanceStatus)}">${escapeHtml(
                    statusLabel(pump.balanceStatus)
                  )}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="7" class="empty">${escapeHtml(t("petrolPumpPayments.print.noBalances"))}</td></tr>`;

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
        <head>
          <title>${escapeHtml(t("petrolPumpPayments.print.reportTitle"))}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 10mm; }
            body {
              margin: 0;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 2px solid #111827;
              padding-bottom: 14px;
              margin-bottom: 16px;
            }
            h1 { margin: 0; font-size: 28px; color: #111827; }
            h2 { margin: 4px 0 0; font-size: 18px; color: #111827; }
            .meta {
              text-align: end;
              font-size: 13px;
              line-height: 1.7;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 10px;
              margin-bottom: 20px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: start;
              padding: 7px;
              border: 1px solid #2563eb;
              white-space: nowrap;
            }
            td {
              padding: 7px;
              border: 1px solid #d1d5db;
              color: #111827;
            }
            tfoot td {
              background: #f9fafb;
              font-weight: 800;
            }
            .section-title {
              margin: 18px 0 8px;
              font-size: 17px;
              font-weight: 800;
            }
            .empty {
              text-align: center;
              font-weight: 700;
              padding: 16px;
            }
            .text-red-700 { color: #b91c1c; font-weight: 800; }
            .text-green-700 { color: #047857; font-weight: 800; }
            .text-blue-700 { color: #1d4ed8; font-weight: 800; }
          </style>
        </head>
        <body dir="${escapeHtml(dir)}">
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(t("petrolPumpPayments.print.reportTitle"))}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("petrolPumpPayments.print.printed"))}:</strong> <span dir="ltr">${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</span></div>
              <div><strong>${escapeHtml(t("common.total"))}:</strong> <span dir="ltr">${escapeHtml(formatAmount(totalPayments))}</span></div>
            </div>
          </div>

          <div class="section-title">${escapeHtml(t("petrolPumpPayments.print.balanceSummary"))}</div>
          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("petrolPumpPayments.fields.pump"))}</th>
                <th>${escapeHtml(t("petrolPumps.fields.openingBalance"))}</th>
                <th>${escapeHtml(t("petrolPumps.cards.totalDiesel"))}</th>
                <th>${escapeHtml(t("petrolPumps.cards.totalPaid"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.statuses.payable"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.statuses.advance"))}</th>
                <th>${escapeHtml(t("common.status"))}</th>
              </tr>
            </thead>
            <tbody>${pumpRows}</tbody>
          </table>

          <div class="section-title">${escapeHtml(t("petrolPumpPayments.print.paymentDetails"))}</div>
          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("common.date"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.pump"))}</th>
                <th>${escapeHtml(t("petrolPumps.fields.ownerName"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.advanceUsed"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.paymentNow"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.totalSettlement"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.currentBalance"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.statuses.payable"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.statuses.advance"))}</th>
                <th>${escapeHtml(t("common.status"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.paymentMethod"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.reference"))}</th>
                <th>${escapeHtml(t("petrolPumpPayments.fields.remarks"))}</th>
              </tr>
            </thead>
            <tbody>${paymentRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="3">${escapeHtml(t("common.total"))}</td>
                <td>${escapeHtml(formatAmount(totalPayments))}</td>
                <td colspan="7"></td>
              </tr>
            </tfoot>
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
          <h2 className="text-2xl font-bold text-gray-900">
            {t("petrolPumpPayments.recordsTitle")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("petrolPumpPayments.recordsDescription")}
          </p>
        </div>


        <div className="flex flex-col gap-3 sm:flex-row">
          <VoiceTypingField fieldLabel={t("petrolPumpPayments.placeholders.search")} mode="text"><input
            type="text"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder={t("petrolPumpPayments.placeholders.search")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 lg:w-80"
          /></VoiceTypingField>

          <button
            type="button"
            onClick={handlePrintReport}
            className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
          >
            {t("petrolPumpPayments.actions.printReport")}
          </button>
        </div>

      </div>

      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("petrolPumpPayments.loading")}
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("petrolPumpPayments.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1700px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("common.date")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumpPayments.fields.pump")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumps.fields.ownerName")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumpPayments.fields.advanceUsed")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumpPayments.fields.paymentNow")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumpPayments.fields.totalSettlement")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumpPayments.fields.currentBalance")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumpPayments.statuses.payable")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumpPayments.statuses.advance")}</th>
                <th className="p-3 text-start font-bold">{t("common.status")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumpPayments.fields.paymentMethod")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumpPayments.fields.reference")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumpPayments.correction.columns.voucher")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumpPayments.fields.remarks")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => {
                const pump = getPump(row);
                const currentBalance = pump?.currentBalance ?? 0;
                const payableAmount = pump?.payableAmount ?? 0;
                const advanceAmount = pump?.advanceAmount ?? 0;
                const status = pump?.balanceStatus ?? "Paid";

                return (
                  <tr
                    key={row.id}
                    className="border-b border-gray-200 hover:bg-gray-50"
                  >
                    <td className="p-3 font-semibold">{row.paymentDate}</td>
                    <td className="p-3 font-bold">{row.pumpName}</td>
                    <td className="p-3 font-semibold">{row.ownerName}</td>
                    <td dir="ltr" className="p-3 text-right font-extrabold text-blue-700">
                      {formatAmount(row.advanceUsed)}
                    </td>
                    <td dir="ltr" className="p-3 text-right font-extrabold text-green-700">
                      {formatAmount(row.paymentNow)}
                    </td>
                    <td dir="ltr" className="p-3 text-right font-extrabold text-slate-900">
                      {formatAmount(row.amount)}
                    </td>
                    <td
                      className={`p-3 text-right font-extrabold ${getBalanceTextClass(
                        currentBalance
                      )}`}
                    >
                      <div>{formatAmount(currentBalance)}</div>
                      <div className="mt-1 text-xs font-bold text-gray-900">
                        {t("petrolPumpPayments.fields.latestBalance")}
                      </div>
                    </td>
                    <td className="p-3 text-right font-extrabold text-red-700">
                      {formatAmount(payableAmount)}
                    </td>
                    <td className="p-3 text-right font-extrabold text-green-700">
                      {formatAmount(advanceAmount)}
                    </td>
                    <td className="p-3">
                      <span
                        className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusBadgeClass(
                          status
                        )}`}
                      >
                        {statusLabel(status)}
                      </span>
                    </td>
                    <td className="p-3 font-semibold">{methodLabel(row.paymentMethod)}</td>
                    <td dir="ltr" className="p-3 font-semibold">{row.referenceNo}</td>
                    <td className="p-3 font-semibold">
                      {linkedByPayment.has(row.id) ? (
                        <div>
                          <div>{linkedByPayment.get(row.id)?.voucherNumber} · {linkedByPayment.get(row.id)?.vehicleNo}</div>
                          <div className="text-xs text-slate-600">{t("petrolPumpPayments.correction.columns.diesel")} #{linkedByPayment.get(row.id)?.dieselEntryId}</div>
                        </div>
                      ) : "—"}
                    </td>
                    <td className="max-w-[260px] p-3 font-semibold">
                      {row.remarks}
                    </td>
                    <td className="min-w-[240px] p-3">
                      <div className="flex flex-wrap gap-2">
                        {!linkedByPayment.has(row.id) && <button
                          type="button"
                          onClick={() => onEdit(row)}
                          aria-label={`${t("common.edit")} ${row.pumpName}`}
                          className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                        >
                          {t("common.edit")}
                        </button>}

                        {!linkedByPayment.has(row.id) && <button
                          type="button"
                          onClick={() => onDelete(row)}
                          aria-label={`${t("common.delete")} ${row.pumpName}`}
                          disabled={isDeleting}
                          className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                        >
                          {t("common.delete")}
                        </button>}

                        {linkedByPayment.has(row.id) && canCorrectManualDieselPayments && (
                          <button
                            type="button"
                            onClick={() => onCorrectManualDieselPayment(linkedByPayment.get(row.id)!)}
                            aria-label={`${t("petrolPumpPayments.correction.correct")} ${linkedByPayment.get(row.id)?.voucherNumber}`}
                            className="rounded-lg bg-amber-700 px-3 py-2 font-semibold text-white transition hover:bg-amber-800"
                          >
                            {t("petrolPumpPayments.correction.correct")}
                          </button>
                        )}

                        <button
                          type="button"
                          onClick={() => handlePrintReceipt(row)}
                          aria-label={`${t("petrolPumpPayments.actions.printReceipt")} ${row.pumpName}`}
                          className="rounded-lg bg-gray-900 px-3 py-2 font-semibold text-white transition hover:bg-gray-800"
                        >
                          {t("petrolPumpPayments.actions.printReceipt")}
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={3} className="p-3 font-extrabold">
                  {t("common.total")}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totalPayments)}
                </td>
                <td colSpan={11} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
      <ManualDieselPaymentCorrectionPanel
        links={manualDieselLinks}
        history={correctionHistory}
        canCorrect={canCorrectManualDieselPayments}
        setupState={correctionSetupState}
        loadError={correctionLoadError}
        onCorrect={onCorrectManualDieselPayment}
      />
      {modulePrint.dialog}
    </div>
  );
}

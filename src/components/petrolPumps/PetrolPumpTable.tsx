"use client";

import {
  type PetrolPumpRow,
  type PetrolPumpDieselEntry,
  formatAmount,
} from "./PetrolPumps";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  rows: PetrolPumpRow[];
  addaId: string | null;
  search: string;
  setSearch: (value: string) => void;
  onEdit: (row: PetrolPumpRow) => void;
  onDelete: (row: PetrolPumpRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
};

function getPrintRows(entries: PetrolPumpDieselEntry[], empty: string) {
  if (entries.length === 0) {
    return `<tr><td colspan="10" class="empty">${escapeHtml(empty)}</td></tr>`;
  }

  return entries
    .map(
      (entry) => `
        <tr>
          <td>${escapeHtml(entry.entryDate || "-")}</td>
          <td>${escapeHtml(entry.vehicleNo || "-")}</td>
          <td>${escapeHtml(entry.loadingNo || "-")}</td>
          <td>${escapeHtml(entry.slipNo || "-")}</td>
          <td>${entry.liters}</td>
          <td>${escapeHtml(formatAmount(entry.rate))}</td>
          <td>${escapeHtml(formatAmount(entry.totalAmount))}</td>
          <td>${escapeHtml(formatAmount(entry.paidAmount))}</td>
          <td>${escapeHtml(formatAmount(entry.remainingAmount))}</td>
          <td>${escapeHtml(entry.paymentStatus)}</td>
        </tr>
      `
    )
    .join("");
}

export default function PetrolPumpTable({
  rows,
  addaId,
  search,
  setSearch,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("petrol_pump", addaId, language);
  const totalOpening = rows.reduce(
    (total, row) => total + row.openingBalance,
    0
  );
  const totalDiesel = rows.reduce((total, row) => total + row.totalDiesel, 0);
  const totalPaid = rows.reduce((total, row) => total + row.totalPaid, 0);
  const totalBalance = rows.reduce(
    (total, row) => total + row.currentBalance,
    0
  );

  function handlePrintLedger(row: PetrolPumpRow) {
    const body = `<div class="details">${[
      [t("petrolPumps.fields.pumpName"), row.pumpName], [t("petrolPumps.fields.ownerName"), row.ownerName], [t("petrolPumps.fields.phone"), row.phone],
      [t("petrolPumps.fields.address"), row.address], [t("petrolPumps.fields.openingBalance"), formatAmount(row.openingBalance)],
      [t("petrolPumps.cards.totalDiesel"), formatAmount(row.totalDiesel)], [t("petrolPumps.cards.totalPaid"), formatAmount(row.totalPaid)],
      [t("petrolPumps.fields.currentBalance"), formatAmount(row.currentBalance)],
    ].map(([label,value])=>`<div><strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</div>`).join("")}</div><table><thead><tr>${["common.date","common.vehicle","diesel.fields.loading","diesel.fields.slipNo","diesel.fields.liters","diesel.fields.rate","common.total","common.paid","common.remaining","common.status"].map(key=>`<th>${escapeHtml(t(key))}</th>`).join("")}</tr></thead><tbody>${getPrintRows(row.dieselEntries, t("petrolPumps.empty"))}</tbody></table>`;
    modulePrint.open(t("petrolPumps.print.ledgerTitle"), body, () => legacyHandlePrintLedger(row));
  }

  function legacyHandlePrintLedger(row: PetrolPumpRow) {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("petrolPumps.messages.allowPopups"));
      return;
    }

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
        <head>
          <title>${escapeHtml(t("petrolPumps.print.ledgerTitle"))} - ${escapeHtml(row.pumpName)}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 12mm; }
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
              color: #111827;
            }
            .details {
              display: grid;
              grid-template-columns: repeat(4, 1fr);
              gap: 10px;
              margin-bottom: 16px;
            }
            .box {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
            }
            .box-title {
              font-size: 11px;
              font-weight: 700;
              color: #111827;
            }
            .box-value {
              margin-top: 4px;
              font-size: 15px;
              font-weight: 800;
              color: #111827;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 10px;
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
              vertical-align: top;
            }
            .empty {
              text-align: center;
              font-weight: 700;
              padding: 18px;
            }
          </style>
        </head>
        <body dir="${escapeHtml(dir)}">
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(t("petrolPumps.print.ledgerTitle"))}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("petrolPumps.fields.pumpName"))}:</strong> ${escapeHtml(row.pumpName)}</div>
              <div><strong>${escapeHtml(t("petrolPumps.print.printed"))}:</strong> <span dir="ltr">${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</span></div>
            </div>
          </div>

          <div class="details">
            <div class="box">
              <div class="box-title">${escapeHtml(t("petrolPumps.fields.ownerName"))}</div>
              <div class="box-value">${escapeHtml(row.ownerName)}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("petrolPumps.fields.phone"))}</div>
              <div class="box-value" dir="ltr">${escapeHtml(row.phone)}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("petrolPumps.fields.address"))}</div>
              <div class="box-value">${escapeHtml(row.address)}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("petrolPumps.fields.openingBalance"))}</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.openingBalance)
              )}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("petrolPumps.cards.totalDiesel"))}</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.totalDiesel)
              )}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("petrolPumps.cards.totalPaid"))}</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.totalPaid)
              )}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("petrolPumps.fields.currentBalance"))}</div>
              <div class="box-value">${escapeHtml(
                formatAmount(row.currentBalance)
              )}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("common.date"))}</th>
                <th>${escapeHtml(t("common.vehicle"))}</th>
                <th>${escapeHtml(t("common.loadingNo"))}</th>
                <th>${escapeHtml(t("petrolPumps.print.slipNo"))}</th>
                <th>${escapeHtml(t("petrolPumps.print.litres"))}</th>
                <th>${escapeHtml(t("petrolPumps.print.rate"))}</th>
                <th>${escapeHtml(t("common.total"))}</th>
                <th>${escapeHtml(t("common.paid"))}</th>
                <th>${escapeHtml(t("common.remaining"))}</th>
                <th>${escapeHtml(t("common.status"))}</th>
              </tr>
            </thead>
            <tbody>${getPrintRows(row.dieselEntries, t("petrolPumps.print.noDieselEntries"))}</tbody>
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
            {t("petrolPumps.recordsTitle")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("petrolPumps.recordsDescription")}
          </p>
        </div>

        <VoiceTypingField fieldLabel={t("petrolPumps.placeholders.search")} mode="text"><input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t("petrolPumps.placeholders.search")}
          className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        /></VoiceTypingField>
      </div>


      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("petrolPumps.loading")}
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("petrolPumps.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1200px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("petrolPumps.fields.pumpName")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumps.fields.ownerName")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumps.fields.phone")}</th>
                <th className="p-3 text-start font-bold">{t("petrolPumps.fields.address")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumps.fields.openingBalance")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumps.cards.totalDiesel")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumps.cards.totalPaid")}</th>
                <th className="p-3 text-end font-bold">{t("petrolPumps.fields.currentBalance")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 font-bold text-gray-900">
                    {row.pumpName}
                  </td>
                  <td dir="ltr" className="p-3 font-semibold text-gray-900">
                    {row.ownerName}
                  </td>
                  <td className="p-3 font-semibold text-gray-900">
                    {row.phone}
                  </td>
                  <td className="max-w-[260px] p-3 font-semibold text-gray-900">
                    {row.address}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(row.openingBalance)}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(row.totalDiesel)}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {formatAmount(row.totalPaid)}
                  </td>
                  <td
                    className={`p-3 text-right font-extrabold ${
                      row.currentBalance > 0
                        ? "text-red-700"
                        : "text-green-700"
                    }`}
                  >
                    {formatAmount(row.currentBalance)}
                  </td>
                  <td className="min-w-[230px] p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => onEdit(row)}
                        aria-label={`${t("common.edit")} ${row.pumpName}`}
                        className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                      >
                        {t("common.edit")}
                      </button>

                      <button
                        type="button"
                        onClick={() => onDelete(row)}
                        aria-label={`${t("common.delete")} ${row.pumpName}`}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        {t("common.delete")}
                      </button>

                      <button
                        type="button"
                        onClick={() => handlePrintLedger(row)}
                        aria-label={`${t("petrolPumps.actions.printLedger")} ${row.pumpName}`}
                        className="rounded-lg bg-gray-900 px-3 py-2 font-semibold text-white transition hover:bg-gray-800"
                      >
                        {t("petrolPumps.actions.printLedger")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={4} className="p-3 font-extrabold">
                  {t("common.total")}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totalOpening)}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(totalDiesel)}
                </td>
                <td className="p-3 text-right font-extrabold text-green-700">
                  {formatAmount(totalPaid)}
                </td>
                <td
                  className={`p-3 text-right font-extrabold ${
                    totalBalance > 0 ? "text-red-700" : "text-green-700"
                  }`}
                >
                  {formatAmount(totalBalance)}
                </td>
                <td />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
      {modulePrint.dialog}
    </div>
  );
}

"use client";

import {
  type DieselEntryRow,
  type DieselFilterValues,
  formatAmount,
  formatLiters,
} from "./Diesel";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";

type Props = {
  rows: DieselEntryRow[];
  isLoading: boolean;
  errorMessage: string;
  filters: DieselFilterValues;
  addaId: string | null;
};

function getStatusClass(status: string) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

export default function DieselTable({
  rows,
  isLoading,
  errorMessage,
  filters,
  addaId,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("diesel", addaId, language);
  const statusLabel = (status: string) =>
    t(`common.paymentStatus.${status.toLowerCase()}`);
  const dateRange = () => {
    if (filters.fromDate && filters.toDate) {
      return `${filters.fromDate} ${t("diesel.print.to")} ${filters.toDate}`;
    }
    if (filters.fromDate) return `${t("common.fromDate")}: ${filters.fromDate}`;
    if (filters.toDate) return `${t("diesel.print.upTo")}: ${filters.toDate}`;
    return t("diesel.print.allDates");
  };
  const totalLiters = rows.reduce((total, row) => total + row.liters, 0);
  const totalAmount = rows.reduce((total, row) => total + row.totalAmount, 0);
  const totalPaid = rows.reduce((total, row) => total + row.paidAmount, 0);
  const totalRemaining = rows.reduce(
    (total, row) => total + row.remainingAmount,
    0
  );

  function printRows(printRowsList: DieselEntryRow[]) {
    if (printRowsList.length === 0) {
      return `<tr><td colspan="15" class="empty">${escapeHtml(t("diesel.empty"))}</td></tr>`;
    }

    return printRowsList
      .map(
        (row) => `
          <tr>
            <td class="technical">${escapeHtml(row.entryDate || "-")}</td>
            <td class="technical">${escapeHtml(row.expenseNo || "-")}</td>
            <td>${escapeHtml(row.pumpName || "-")}</td>
            <td class="technical">${escapeHtml(row.vehicleNo || "-")}</td>
            <td>${escapeHtml(row.vehicleOwner || "-")}</td>
            <td>${escapeHtml(row.driverName || "-")}</td>
            <td class="technical">${escapeHtml(row.loadingNo || "-")}</td>
            <td>${escapeHtml(row.route || "-")}</td>
            <td class="technical">${escapeHtml(row.slipNo || "-")}</td>
            <td class="technical">${escapeHtml(formatLiters(row.liters))}</td>
            <td class="technical">${escapeHtml(formatAmount(row.rate))}</td>
            <td class="technical">${escapeHtml(formatAmount(row.totalAmount))}</td>
            <td class="technical">${escapeHtml(formatAmount(row.paidAmount))}</td>
            <td class="technical">${escapeHtml(formatAmount(row.remainingAmount))}</td>
            <td>${escapeHtml(statusLabel(row.paymentStatus))}</td>
          </tr>
        `
      )
      .join("");
  }

  function handlePrintEntry(row: DieselEntryRow) {
    const body = `<div class="details">${[
      [t("common.date"), row.entryDate], [t("diesel.fields.expenseNo"), row.expenseNo], [t("diesel.fields.petrolPump"), row.pumpName],
      [t("diesel.fields.pumpOwner"), row.pumpOwner], [t("common.vehicle"), row.vehicleNo], [t("diesel.fields.vehicleOwner"), row.vehicleOwner],
      [t("common.driver"), row.driverName], [t("diesel.fields.loading"), row.loadingNo], [t("common.route"), row.route], [t("diesel.fields.slipNo"), row.slipNo],
      [t("diesel.fields.liters"), formatLiters(row.liters)], [t("diesel.fields.rate"), formatAmount(row.rate)], [t("common.total"), formatAmount(row.totalAmount)],
      [t("common.paid"), formatAmount(row.paidAmount)], [t("common.remaining"), formatAmount(row.remainingAmount)], [t("common.status"), statusLabel(row.paymentStatus)], [t("common.remarks"), row.remarks],
    ].map(([label,value])=>`<div><strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</div>`).join("")}</div>`;
    modulePrint.open(t("diesel.print.entryTitle"), body, () => legacyPrintEntry(row));
  }

  function legacyPrintEntry(row: DieselEntryRow) {
    const printWindow = window.open("", "_blank", "width=1000,height=800");

    if (!printWindow) {
      alert(t("diesel.messages.allowEntryPopups"));
      return;
    }

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("diesel.print.entryTitle"))} - ${escapeHtml(row.slipNo)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 28px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
              direction: ${dir};
              text-align: start;
            }
            .slip {
              max-width: 900px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 24px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 16px;
              margin-bottom: 18px;
            }
            h1 { margin: 0; font-size: 28px; color: #111827; }
            h2 { margin: 4px 0 0; font-size: 18px; color: #111827; }
            .meta { text-align: end; line-height: 1.7; font-size: 14px; }
            .details {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 12px 24px;
              font-size: 14px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
            .technical { direction: ltr; unicode-bidi: isolate; }
          </style>
        </head>
        <body>
          <div class="slip">
            <div class="header">
              <div>
                <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
                <h2>${escapeHtml(t("diesel.print.entryTitle"))}</h2>
              </div>
              <div class="meta">
                <div><strong>${escapeHtml(t("common.date"))}:</strong> <span class="technical">${escapeHtml(row.entryDate)}</span></div>
                <div><strong>${escapeHtml(t("diesel.fields.expenseNo"))}:</strong> <span class="technical">${escapeHtml(row.expenseNo)}</span></div>
              </div>
            </div>

            <div class="details">
              <div><strong>${escapeHtml(t("diesel.fields.petrolPump"))}:</strong> ${escapeHtml(row.pumpName)}</div>
              <div><strong>${escapeHtml(t("diesel.fields.pumpOwner"))}:</strong> ${escapeHtml(row.pumpOwner)}</div>
              <div><strong>${escapeHtml(t("common.vehicle"))}:</strong> <span class="technical">${escapeHtml(row.vehicleNo)}</span></div>
              <div><strong>${escapeHtml(t("diesel.fields.vehicleOwner"))}:</strong> ${escapeHtml(row.vehicleOwner)}</div>
              <div><strong>${escapeHtml(t("common.driver"))}:</strong> ${escapeHtml(row.driverName)}</div>
              <div><strong>${escapeHtml(t("diesel.fields.loading"))}:</strong> <span class="technical">${escapeHtml(row.loadingNo)}</span></div>
              <div><strong>${escapeHtml(t("common.route"))}:</strong> ${escapeHtml(row.route)}</div>
              <div><strong>${escapeHtml(t("diesel.fields.slipNo"))}:</strong> <span class="technical">${escapeHtml(row.slipNo)}</span></div>
              <div><strong>${escapeHtml(t("diesel.fields.liters"))}:</strong> <span class="technical">${escapeHtml(formatLiters(row.liters))}</span></div>
              <div><strong>${escapeHtml(t("diesel.fields.rate"))}:</strong> <span class="technical">${escapeHtml(formatAmount(row.rate))}</span></div>
              <div><strong>${escapeHtml(t("common.total"))}:</strong> <span class="technical">${escapeHtml(formatAmount(row.totalAmount))}</span></div>
              <div><strong>${escapeHtml(t("common.paid"))}:</strong> <span class="technical">${escapeHtml(formatAmount(row.paidAmount))}</span></div>
              <div><strong>${escapeHtml(t("common.remaining"))}:</strong> <span class="technical">${escapeHtml(formatAmount(row.remainingAmount))}</span></div>
              <div><strong>${escapeHtml(t("common.status"))}:</strong> ${escapeHtml(statusLabel(row.paymentStatus))}</div>
              <div><strong>${escapeHtml(t("common.remarks"))}:</strong> ${escapeHtml(row.remarks)}</div>
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
    const body = `<div class="grid">${[
      [t("diesel.print.dateRange"), dateRange()], [t("diesel.cards.totalEntries"), String(rows.length)], [t("diesel.cards.totalLiters"), formatLiters(totalLiters)],
      [t("diesel.cards.totalAmount"), formatAmount(totalAmount)], [t("diesel.cards.totalPaid"), formatAmount(totalPaid)], [t("diesel.cards.totalRemaining"), formatAmount(totalRemaining)],
    ].map(([label,value])=>`<div><strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</div>`).join("")}</div><table><thead><tr>${["common.date","diesel.fields.expenseNo","diesel.fields.pump","common.vehicle","common.owner","common.driver","diesel.fields.loading","common.route","diesel.fields.slipNo","diesel.fields.liters","diesel.fields.rate","common.total","common.paid","common.remaining","common.status"].map(key=>`<th>${escapeHtml(t(key))}</th>`).join("")}</tr></thead><tbody>${printRows(rows)}</tbody></table>`;
    modulePrint.open(t("diesel.print.reportTitle"), body, legacyPrintReport);
  }

  function legacyPrintReport() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("diesel.messages.allowReportPopups"));
      return;
    }

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("diesel.print.reportTitle"))}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 10mm; }
            body {
              margin: 0;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
              direction: ${dir};
              text-align: start;
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
            .summary {
              display: grid;
              grid-template-columns: repeat(5, 1fr);
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
              font-size: 9px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: start;
              padding: 6px;
              border: 1px solid #2563eb;
              white-space: nowrap;
            }
            td {
              padding: 6px;
              border: 1px solid #d1d5db;
              color: #111827;
              vertical-align: top;
            }
            tfoot td {
              background: #f9fafb;
              font-weight: 800;
              white-space: nowrap;
            }
            .empty {
              text-align: center;
              font-weight: 700;
              padding: 18px;
            }
            .technical, .box-value, tfoot td { direction: ltr; unicode-bidi: isolate; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(t("diesel.print.reportTitle"))}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("diesel.print.dateRange"))}:</strong> <span class="technical">${escapeHtml(dateRange())}</span></div>
              <div><strong>${escapeHtml(t("diesel.print.printed"))}:</strong> <span class="technical">${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</span></div>
            </div>
          </div>

          <div class="summary">
            <div class="box">
              <div class="box-title">${escapeHtml(t("diesel.cards.totalEntries"))}</div>
              <div class="box-value">${rows.length}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("diesel.cards.totalLiters"))}</div>
              <div class="box-value">${escapeHtml(formatLiters(totalLiters))}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("diesel.cards.totalAmount"))}</div>
              <div class="box-value">${escapeHtml(formatAmount(totalAmount))}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("diesel.cards.totalPaid"))}</div>
              <div class="box-value">${escapeHtml(formatAmount(totalPaid))}</div>
            </div>
            <div class="box">
              <div class="box-title">${escapeHtml(t("diesel.cards.totalRemaining"))}</div>
              <div class="box-value">${escapeHtml(formatAmount(totalRemaining))}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("common.date"))}</th>
                <th>${escapeHtml(t("diesel.fields.expenseNo"))}</th>
                <th>${escapeHtml(t("diesel.fields.pump"))}</th>
                <th>${escapeHtml(t("common.vehicle"))}</th>
                <th>${escapeHtml(t("common.owner"))}</th>
                <th>${escapeHtml(t("common.driver"))}</th>
                <th>${escapeHtml(t("diesel.fields.loading"))}</th>
                <th>${escapeHtml(t("common.route"))}</th>
                <th>${escapeHtml(t("diesel.fields.slipNo"))}</th>
                <th>${escapeHtml(t("diesel.fields.liters"))}</th>
                <th>${escapeHtml(t("diesel.fields.rate"))}</th>
                <th>${escapeHtml(t("common.total"))}</th>
                <th>${escapeHtml(t("common.paid"))}</th>
                <th>${escapeHtml(t("common.remaining"))}</th>
                <th>${escapeHtml(t("common.status"))}</th>
              </tr>
            </thead>
            <tbody>${printRows(rows)}</tbody>
            <tfoot>
              <tr>
                <td colspan="9">${escapeHtml(t("common.total"))}</td>
                <td>${escapeHtml(formatLiters(totalLiters))}</td>
                <td></td>
                <td>${escapeHtml(formatAmount(totalAmount))}</td>
                <td>${escapeHtml(formatAmount(totalPaid))}</td>
                <td>${escapeHtml(formatAmount(totalRemaining))}</td>
                <td></td>
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
            {t("diesel.entriesTitle")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("diesel.entriesDescription")}
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintReport}
          className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
        >
          {t("diesel.actions.printReport")}
        </button>
      </div>

      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("diesel.loading")}
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("diesel.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1700px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("common.date")}</th>
                <th className="p-3 text-start font-bold">{t("diesel.fields.expenseNo")}</th>
                <th className="p-3 text-start font-bold">{t("diesel.fields.pump")}</th>
                <th className="p-3 text-start font-bold">{t("common.vehicle")}</th>
                <th className="p-3 text-start font-bold">{t("common.owner")}</th>
                <th className="p-3 text-start font-bold">{t("common.driver")}</th>
                <th className="p-3 text-start font-bold">{t("diesel.fields.loading")}</th>
                <th className="p-3 text-start font-bold">{t("common.route")}</th>
                <th className="p-3 text-start font-bold">{t("diesel.fields.slipNo")}</th>
                <th className="p-3 text-end font-bold">{t("diesel.fields.liters")}</th>
                <th className="p-3 text-end font-bold">{t("diesel.fields.rate")}</th>
                <th className="p-3 text-end font-bold">{t("diesel.fields.totalAmount")}</th>
                <th className="p-3 text-end font-bold">{t("common.paid")}</th>
                <th className="p-3 text-end font-bold">{t("common.remaining")}</th>
                <th className="p-3 text-start font-bold">{t("common.status")}</th>
                <th className="p-3 text-start font-bold">{t("common.remarks")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td dir="ltr" className="p-3 font-semibold">{row.entryDate || "-"}</td>
                  <td dir="ltr" className="p-3 font-bold">{row.expenseNo}</td>
                  <td className="p-3 font-semibold">{row.pumpName}</td>
                  <td dir="ltr" className="p-3 font-bold">{row.vehicleNo}</td>
                  <td className="p-3 font-semibold">{row.vehicleOwner}</td>
                  <td className="p-3 font-semibold">{row.driverName}</td>
                  <td dir="ltr" className="p-3 font-semibold">{row.loadingNo}</td>
                  <td className="p-3 font-semibold">{row.route}</td>
                  <td dir="ltr" className="p-3 font-semibold">{row.slipNo}</td>
                  <td dir="ltr" className="p-3 text-end font-bold">
                    {formatLiters(row.liters)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold">
                    {formatAmount(row.rate)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-extrabold">
                    {formatAmount(row.totalAmount)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-extrabold text-green-700">
                    {formatAmount(row.paidAmount)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-extrabold text-red-700">
                    {formatAmount(row.remainingAmount)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.paymentStatus
                      )}`}
                    >
                      {statusLabel(row.paymentStatus)}
                    </span>
                  </td>
                  <td className="max-w-[260px] p-3 font-semibold">
                    {row.remarks}
                  </td>
                  <td className="p-3">
                    <button
                      type="button"
                      onClick={() => handlePrintEntry(row)}
                      aria-label={`${t("diesel.actions.printEntry")} ${row.expenseNo}`}
                      className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white transition hover:bg-gray-800"
                    >
                      {t("diesel.actions.printEntry")}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={9} className="p-3 font-extrabold">
                  {t("common.total")}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold">
                  {formatLiters(totalLiters)}
                </td>
                <td />
                <td dir="ltr" className="p-3 text-end font-extrabold">
                  {formatAmount(totalAmount)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-green-700">
                  {formatAmount(totalPaid)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-red-700">
                  {formatAmount(totalRemaining)}
                </td>
                <td colSpan={3} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
      {modulePrint.dialog}
    </div>
  );
}

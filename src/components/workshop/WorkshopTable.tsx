"use client";

import { useEffect, useRef, useState, type Dispatch, type SetStateAction } from "react";
import {
  type VehicleOption,
  type WorkshopEntryRow,
  type WorkshopFilterValues,
  type WorkshopPaymentStatus,
  formatAmount,
} from "./Workshop";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { getWorkTypeLabel } from "./workshopWorkTypes";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  rows: WorkshopEntryRow[];
  addaId: string | null;
  filters: WorkshopFilterValues;
  setFilters: Dispatch<SetStateAction<WorkshopFilterValues>>;
  vehicles: VehicleOption[];
  onReset: () => void;
  onEdit: (row: WorkshopEntryRow) => void;
  onDelete: (row: WorkshopEntryRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
};

function updateFilter<K extends keyof WorkshopFilterValues>(
  setFilters: Dispatch<SetStateAction<WorkshopFilterValues>>,
  key: K,
  value: WorkshopFilterValues[K]
) {
  setFilters((previous) => ({
    ...previous,
    [key]: value,
  }));
}

function getStatusClass(status: WorkshopPaymentStatus) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

export default function WorkshopTable({
  rows,
  addaId,
  filters,
  setFilters,
  vehicles,
  onReset,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("workshop", addaId, language);
  const [page, setPage] = useState(1);
  const [viewing, setViewing] = useState<WorkshopEntryRow | null>(null);
  const closeRef = useRef<HTMLButtonElement | null>(null);
  useEffect(() => {
    if (!viewing) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus();
    const close = (event: KeyboardEvent) => { if (event.key === "Escape") setViewing(null); };
    document.addEventListener("keydown", close);
    return () => { document.removeEventListener("keydown", close); document.body.style.overflow = overflow; previous?.focus(); };
  }, [viewing]);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(rows.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleRows = rows.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );
  const handleFilterChange = <K extends keyof WorkshopFilterValues>(
    key: K,
    value: WorkshopFilterValues[K]
  ) => {
    updateFilter(setFilters, key, value);
    setPage(1);
  };
  const statusLabel = (status: WorkshopPaymentStatus) =>
    t(`workshop.statuses.${status.toLowerCase()}`);
  const dateRange = () => {
    if (filters.fromDate && filters.toDate) return `${filters.fromDate} ${t("workshop.print.to")} ${filters.toDate}`;
    if (filters.fromDate) return `${t("workshop.filters.from")} ${filters.fromDate}`;
    if (filters.toDate) return `${t("workshop.filters.upTo")} ${filters.toDate}`;
    return t("workshop.filters.allDates");
  };
  const totalParts = rows.reduce((total, row) => total + row.partsCost, 0);
  const totalLabour = rows.reduce((total, row) => total + row.labourCost, 0);
  const totalCost = rows.reduce((total, row) => total + row.totalCost, 0);
  const totalPaid = rows.reduce((total, row) => total + row.paidAmount, 0);
  const totalRemaining = rows.reduce(
    (total, row) => total + row.remainingAmount,
    0
  );

  function legacyOpenPrintWindow(title: string, printableRows: WorkshopEntryRow[]) {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("workshop.messages.allowPopups"));
      return;
    }

    const partsTotal = printableRows.reduce(
      (total, row) => total + row.partsCost,
      0
    );
    const labourTotal = printableRows.reduce(
      (total, row) => total + row.labourCost,
      0
    );
    const costTotal = printableRows.reduce(
      (total, row) => total + row.totalCost,
      0
    );
    const paidTotal = printableRows.reduce(
      (total, row) => total + row.paidAmount,
      0
    );
    const remainingTotal = printableRows.reduce(
      (total, row) => total + row.remainingAmount,
      0
    );

    const tableRows =
      printableRows.length > 0
        ? printableRows
            .map(
              (row) => `
                <tr>
                  <td>${escapeHtml(row.workDate || "-")}</td>
                  <td>${escapeHtml(row.vehicleNo)}</td>
                  <td>${escapeHtml(row.ownerName)}</td>
                  <td>${escapeHtml(row.workshopName || "-")}</td>
                  <td>${escapeHtml(row.mechanicName || "-")}</td>
                  <td>${escapeHtml(row.workItems.length ? row.workItems.map((item)=>getWorkTypeLabel(item.workType,t)).join(", ") : row.workType || "-")}</td>
                  <td>${escapeHtml(row.billNo || "-")}</td>
                  <td>${escapeHtml(formatAmount(row.partsCost))}</td>
                  <td>${escapeHtml(formatAmount(row.labourCost))}</td>
                  <td>${escapeHtml(formatAmount(row.totalCost))}</td>
                  <td>${escapeHtml(formatAmount(row.paidAmount))}</td>
                  <td>${escapeHtml(formatAmount(row.remainingAmount))}</td>
                  <td>${escapeHtml(statusLabel(row.paymentStatus))}</td>
                  <td>${escapeHtml(row.nextServiceDate || "-")}</td>
                  <td>${escapeHtml(String(row.odometer || "-"))}</td>
                  <td>${escapeHtml(row.remarks || "-")}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="16" class="empty">${escapeHtml(t("workshop.empty"))}</td></tr>`;
    const selectedEntry = printableRows.length === 1 ? printableRows[0] : null;
    const itemDetails = selectedEntry && selectedEntry.workItems.length > 0
      ? `<section style="margin-top:20px"><h2>${escapeHtml(t("workshop.workItems.title"))}</h2><table><thead><tr><th>#</th><th>${escapeHtml(t("workshop.workItems.workType"))}</th><th>${escapeHtml(t("workshop.workItems.quantity"))}</th><th>${escapeHtml(t("workshop.workItems.rate"))}</th><th>${escapeHtml(t("workshop.workItems.amount"))}</th><th>${escapeHtml(t("workshop.workItems.remarks"))}</th></tr></thead><tbody>${selectedEntry.workItems.map((item,index)=>`<tr><td>${index+1}</td><td>${escapeHtml(getWorkTypeLabel(item.workType,t))}</td><td dir="ltr">${escapeHtml(item.quantity)}</td><td dir="ltr">${escapeHtml(formatAmount(Number(item.rate)))}</td><td dir="ltr">${escapeHtml(formatAmount(item.amount))}</td><td>${escapeHtml(item.remarks||"-")}</td></tr>`).join("")}</tbody></table></section>`
      : "";
    const voucherDetails = selectedEntry
      ? `<div class="box" style="margin-bottom:16px"><div class="box-title">${escapeHtml(t("expenses.workshopLink.voucherStatus"))}</div><div class="box-value">${escapeHtml(t(selectedEntry.voucherId ? "expenses.workshopLink.attached" : "expenses.workshopLink.notAttached"))}${selectedEntry.voucherId ? ` — ${escapeHtml(t("expenses.workshopLink.voucherNo"))}: <span dir="ltr">${escapeHtml(selectedEntry.voucherNo || selectedEntry.voucherId)}</span> · ${escapeHtml(t("expenses.workshopLink.voucherDate"))}: <span dir="ltr">${escapeHtml(selectedEntry.voucherDate || "-")}</span>` : ""}</div></div>`
      : "";

    const ownerAddaId = getSingleOwnerAddaId(printableRows);
    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
        <head>
          <title>${escapeHtml(title)}</title>
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
            h1 {
              margin: 0;
              font-size: 28px;
              color: #111827;
            }
            h2 {
              margin: 4px 0 0;
              font-size: 18px;
              color: #111827;
            }
            .meta {
              text-align: right;
              font-size: 13px;
              line-height: 1.7;
              color: #111827;
            }
            .summary {
              display: grid;
              grid-template-columns: 1fr;
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
            }
            .box-value {
              margin-top: 4px;
              font-size: 16px;
              font-weight: 800;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 9px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: left;
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
              padding: 16px;
            }
          </style>
        </head>
        <body dir="${escapeHtml(dir)}">
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(title)}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("workshop.print.dateRange"))}:</strong> <span dir="ltr">${escapeHtml(
                dateRange()
              )}</span></div>
              <div><strong>${escapeHtml(t("workshop.print.printed"))}:</strong> <span dir="ltr">${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</span></div>
            </div>
          </div>

          <div class="summary">
            <div class="box">
              <div class="box-title">${escapeHtml(t("workshop.cards.totalJobs"))}</div>
              <div class="box-value">${printableRows.length}</div>
            </div>
          </div>
          ${voucherDetails}

          <table>
            <thead>
              <tr>
                ${["date","vehicle","owner","workshop","mechanic","workType","billNo","parts","labour","total","paid","remaining","status","nextService","odometer","remarks"].map((key) => `<th>${escapeHtml(t(`workshop.print.columns.${key}`))}</th>`).join("")}
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="7">${escapeHtml(t("common.total"))}</td>
                <td>${escapeHtml(formatAmount(partsTotal))}</td>
                <td>${escapeHtml(formatAmount(labourTotal))}</td>
                <td>${escapeHtml(formatAmount(costTotal))}</td>
                <td>${escapeHtml(formatAmount(paidTotal))}</td>
                <td>${escapeHtml(formatAmount(remainingTotal))}</td>
                <td colspan="4"></td>
              </tr>
            </tfoot>
          </table>
          ${itemDetails}

          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };
          </script>
        </body>
      </html>
    `, ownerAddaId, language === "ur" ? "ur" : "en");
  }

  function getSingleOwnerAddaId(printableRows: WorkshopEntryRow[]): string | null {
    if (!printableRows.length || printableRows.some((row) => !row.addaId)) return null;
    const owners = Array.from(new Set(printableRows.map((row) => row.addaId)));
    return owners.length === 1 ? owners[0] ?? null : null;
  }

  function openPrintWindow(title: string, printableRows: WorkshopEntryRow[]) {
    const labels = ["common.date", "common.vehicle", "common.owner", "workshop.master.fields.name", "workshop.fields.mechanicName", "workshop.table.billNo", "common.status", "common.remarks"];
    const fields = printableRows.map((row) => {
      const values = [row.workDate || "-", row.vehicleNo, row.ownerName, row.workshopName || "-", row.mechanicName || "-", row.billNo || "-", statusLabel(row.paymentStatus), row.remarks || "-"];
      const details = labels.map((key, index) => `<div><strong>${escapeHtml(t(key))}:</strong> ${escapeHtml(String(values[index]))}</div>`).join("");
      const voucher = row.voucherId
        ? `${t("expenses.workshopLink.attached")} · ${t("expenses.workshopLink.voucherNo")}: ${row.voucherNo || row.voucherId} · ${t("expenses.workshopLink.voucherDate")}: ${row.voucherDate || "-"}`
        : t("expenses.workshopLink.notAttached");
      return `<section class="grid">${details}<div><strong>${escapeHtml(t("expenses.workshopLink.voucherStatus"))}:</strong> ${escapeHtml(voucher)}</div></section>`;
    }).join("");
    const headers = ["common.date", "common.vehicle", "common.owner", "workshop.master.fields.name", "workshop.table.mechanic", "workshop.table.workType", "workshop.table.billNo", "workshop.table.partsCost", "workshop.table.labourCost", "common.total", "common.paid", "common.remaining", "common.status", "common.remarks"];
    const table = `<table><thead><tr>${headers.map((key) => `<th>${escapeHtml(t(key))}</th>`).join("")}</tr></thead><tbody>${printableRows.map((row) => `<tr><td>${escapeHtml(row.workDate || "-")}</td><td>${escapeHtml(row.vehicleNo)}</td><td>${escapeHtml(row.ownerName)}</td><td>${escapeHtml(row.workshopName || "-")}</td><td>${escapeHtml(row.mechanicName || "-")}</td><td>${escapeHtml(row.workItems.length ? row.workItems.map((item) => getWorkTypeLabel(item.workType, t)).join(", ") : row.workType || "-")}</td><td>${escapeHtml(row.billNo || "-")}</td><td>${escapeHtml(formatAmount(row.partsCost))}</td><td>${escapeHtml(formatAmount(row.labourCost))}</td><td>${escapeHtml(formatAmount(row.totalCost))}</td><td>${escapeHtml(formatAmount(row.paidAmount))}</td><td>${escapeHtml(formatAmount(row.remainingAmount))}</td><td>${escapeHtml(statusLabel(row.paymentStatus))}</td><td>${escapeHtml(row.remarks || "-")}</td></tr>`).join("")}</tbody></table>`;
    const selectedEntry = printableRows.length === 1 ? printableRows[0] : null;
    const itemTable = selectedEntry?.workItems.length ? `<h2>${escapeHtml(t("workshop.workItems.title"))}</h2><table><thead><tr>${["workType", "quantity", "rate", "amount", "remarks"].map((key) => `<th>${escapeHtml(t(`workshop.workItems.${key}`))}</th>`).join("")}</tr></thead><tbody>${selectedEntry.workItems.map((item) => `<tr><td>${escapeHtml(getWorkTypeLabel(item.workType, t))}</td><td>${escapeHtml(String(item.quantity))}</td><td>${escapeHtml(formatAmount(Number(item.rate)))}</td><td>${escapeHtml(formatAmount(item.amount))}</td><td>${escapeHtml(item.remarks || "-")}</td></tr>`).join("")}</tbody></table>` : "";
    const body = `${fields}${table}${itemTable}`;
    modulePrint.open(title, body, () => legacyOpenPrintWindow(title, printableRows), getSingleOwnerAddaId(printableRows));
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("workshop.recordsTitle")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("workshop.recordsDescription")}
          </p>
        </div>

        <button
          type="button"
          onClick={() => openPrintWindow(t("workshop.print.reportTitle"), rows)}
          className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
        >
          {t("common.actions.printReport")}
        </button>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">

        <div>
          <label htmlFor="workshop-from-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.filters.fromDate")}
          </label>
          <VoiceTypingField fieldLabel="workshop from date" mode="date"><input
            id="workshop-from-date"
            type="date"
            value={filters.fromDate}
            onChange={(event) =>
              handleFilterChange("fromDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="workshop-to-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.filters.toDate")}
          </label>
          <VoiceTypingField fieldLabel="workshop to date" mode="date"><input
            id="workshop-to-date"
            type="date"
            value={filters.toDate}
            onChange={(event) =>
              handleFilterChange("toDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="workshop-vehicle-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.vehicle")}
          </label>
          <select
            id="workshop-vehicle-filter"
            value={filters.vehicleId}
            onChange={(event) =>
              handleFilterChange("vehicleId", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("workshop.filters.allVehicles")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="workshop-payment-status" className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.paymentStatus")}
          </label>
          <select
            id="workshop-payment-status"
            value={filters.paymentStatus}
            onChange={(event) =>
              handleFilterChange("paymentStatus", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("workshop.filters.allStatuses")}</option>
            <option value="Paid">{t("workshop.statuses.paid")}</option>
            <option value="Partial">{t("workshop.statuses.partial")}</option>
            <option value="Unpaid">{t("workshop.statuses.unpaid")}</option>
          </select>
        </div>


        <div className="md:col-span-2">
          <label htmlFor="workshop-search" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.actions.search")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.placeholders.search")} mode="text"><input
            id="workshop-search"
            type="text"
            value={filters.search}
            onChange={(event) =>
              handleFilterChange("search", event.target.value)
            }
            placeholder={t("workshop.placeholders.search")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>

      </div>

      <div className="mt-4 flex justify-end">
        <button
          type="button"
          onClick={() => {
            onReset();
            setPage(1);
          }}
          className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
        >
          {t("common.reset")}
        </button>
      </div>

      {isLoading && (
        <div className="mt-6 rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("workshop.loading")}
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("workshop.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-lg border border-gray-300">
          <table className="w-full min-w-[1700px] border-collapse text-left">
            <thead>
              <tr className="bg-blue-600 text-white">
                {["date","vehicle","owner","workshop","mechanic","workType","billNo","partsCost","labourCost","totalCost","paid","remaining","status","nextService","odometer","remarks","actions"].map((heading) => (
                  <th
                    key={heading}
                    className="whitespace-nowrap px-4 py-3 text-sm font-bold"
                  >
                    {t(`workshop.table.${heading}`)}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {visibleRows.map((row) => (
                <tr
                  key={row.id}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.workDate || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                    {row.vehicleNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.ownerName}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.workshopName || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.mechanicName || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.workItems.length > 0 ? `${getWorkTypeLabel(row.workItems[0].workType,t)}${row.workItems.length>1 ? ` +${row.workItems.length-1}` : ""}` : row.workType || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.billNo || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatAmount(row.partsCost)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatAmount(row.labourCost)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold">
                    {formatAmount(row.totalCost)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold text-green-700">
                    {formatAmount(row.paidAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-extrabold text-red-700">
                    {formatAmount(row.remainingAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.paymentStatus
                      )}`}
                    >
                      {statusLabel(row.paymentStatus)}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.nextServiceDate || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.odometer || "-"}
                  </td>
                  <td className="min-w-[220px] px-4 py-3 text-sm font-semibold">
                    {row.remarks || "-"}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <div className="flex items-center gap-2">
                      <button type="button" aria-label={`${t("common.view")} ${row.vehicleNo}`} onClick={() => setViewing(row)} className="rounded-lg bg-slate-700 px-3 py-2 text-xs font-bold text-white hover:bg-slate-800">{t("common.view")}</button>
                      <button
                        type="button"
                        aria-label={`${t("common.edit")} ${row.vehicleNo}`}
                        onClick={() => onEdit(row)}
                        className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700"
                      >
                        {t("common.edit")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("common.delete")} ${row.vehicleNo}`}
                        onClick={() => onDelete(row)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        {t("common.delete")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("common.actions.print")} ${row.vehicleNo}`}
                        onClick={() =>
                          openPrintWindow(t("workshop.print.entryTitle"), [row])
                        }
                        className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-gray-800"
                      >
                        {t("common.actions.print")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-white text-gray-900">
                <td colSpan={7} className="px-4 py-4 text-sm font-extrabold">
                  {t("common.total")}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(totalParts)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(totalLabour)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(totalCost)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold text-green-700">
                  {formatAmount(totalPaid)}
                </td>
                <td className="whitespace-nowrap px-4 py-4 text-right text-sm font-extrabold text-red-700">
                  {formatAmount(totalRemaining)}
                </td>
                <td colSpan={5} />
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
      {viewing && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="presentation" onMouseDown={(event)=>{if(event.target===event.currentTarget)setViewing(null)}}><section role="dialog" aria-modal="true" aria-labelledby="workshop-items-dialog-title" className="max-h-[90vh] w-full max-w-4xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 shadow-xl sm:p-6"><div className="flex items-start justify-between gap-3"><div><h2 id="workshop-items-dialog-title" className="text-2xl font-black text-gray-900">{t("workshop.workItems.detailsTitle")}</h2><p className="font-semibold text-gray-700">{viewing.vehicleNo} — {viewing.workshopName}</p></div><button ref={closeRef} type="button" aria-label={t("common.actions.close")} onClick={()=>setViewing(null)} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-black text-gray-900">×</button></div><div className="mt-4 rounded-lg border border-blue-200 bg-blue-50 p-4 font-bold text-gray-900"><span>{t("expenses.workshopLink.voucherStatus")}: </span><strong className={viewing.voucherId ? "text-blue-800" : "text-gray-700"}>{t(viewing.voucherId ? "expenses.workshopLink.attached" : "expenses.workshopLink.notAttached")}</strong>{viewing.voucherId && <span className="ms-4" dir="ltr">{t("expenses.workshopLink.voucherNo")}: {viewing.voucherNo || viewing.voucherId} · {t("expenses.workshopLink.voucherDate")}: {viewing.voucherDate || "-"}</span>}</div><div className="mt-5 overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-blue-600 text-white"><tr><th className="p-3">#</th>{["workType","quantity","rate","amount","remarks"].map((key)=><th key={key} className="p-3 text-start">{t(`workshop.workItems.${key}`)}</th>)}</tr></thead><tbody>{viewing.workItems.length ? viewing.workItems.map((item,index)=><tr key={item.clientId} className="border-b"><td className="p-3">{index+1}</td><td className="p-3 font-bold">{getWorkTypeLabel(item.workType,t)}</td><td dir="ltr" className="p-3">{item.quantity}</td><td dir="ltr" className="p-3">{formatAmount(Number(item.rate))}</td><td dir="ltr" className="p-3 font-bold">{formatAmount(item.amount)}</td><td className="p-3">{item.remarks||"-"}</td></tr>) : <tr><td colSpan={6} className="p-5 text-center font-semibold">{viewing.workType}</td></tr>}</tbody></table></div><div className="mt-4 text-end text-xl font-black">{t("workshop.workItems.grandTotal")}: <span dir="ltr">{formatAmount(viewing.totalCost)}</span></div></section></div>}
      {modulePrint.dialog}
    </div>
  );
}

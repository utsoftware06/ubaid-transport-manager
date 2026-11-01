"use client";

import { useState, type Dispatch, type SetStateAction } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import {
  type CashbookEntryRow,
  type CashbookFilterValues,
  type CashbookEntryType,
  type CashbookPersonType,
  type CashbookPaymentMethod,
  type VehicleOption,
  type DriverOption,
  formatAmount,
  isManualCashbookEntry,
} from "./Cashbook";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  rows: CashbookEntryRow[];
  addaId: string | null;
  filters: CashbookFilterValues;
  setFilters: Dispatch<SetStateAction<CashbookFilterValues>>;
  onReset: () => void;
  onSync: () => void;
  isSyncing: boolean;
  isLoading: boolean;
  errorMessage: string;
  vehicles: VehicleOption[];
  drivers: DriverOption[];
  deletingId: string | null;
  onEdit: (row: CashbookEntryRow) => void;
  onDelete: (row: CashbookEntryRow) => void;
};

const entryTypes: CashbookEntryType[] = ["Cash In", "Cash Out"];

const personTypes: CashbookPersonType[] = [
  "Customer",
  "Driver",
  "Vehicle Owner",
  "Broker",
  "Adda",
  "Petrol Pump",
  "Workshop",
  "Other",
];

const paymentMethods: CashbookPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

function updateFilter<K extends keyof CashbookFilterValues>(
  setFilters: Dispatch<SetStateAction<CashbookFilterValues>>,
  key: K,
  value: CashbookFilterValues[K]
) {
  setFilters((previous) => ({
    ...previous,
    [key]: value,
  }));
}

function getTypeBadgeClass(entryType: CashbookEntryType) {
  if (entryType === "Cash In") {
    return "border-green-200 bg-green-100 text-green-700";
  }

  return "border-red-200 bg-red-100 text-red-700";
}

export default function CashbookTable({
  rows,
  addaId,
  filters,
  setFilters,
  onReset,
  onSync,
  isSyncing,
  isLoading,
  errorMessage,
  vehicles,
  drivers,
  deletingId,
  onEdit,
  onDelete,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("cashbook", addaId, language === "ur" ? "ur" : "en");
  const entryTypeLabel = (type: CashbookEntryType) =>
    t(`cashbook.entryTypes.${type === "Cash In" ? "cashIn" : "cashOut"}`);
  const personTypeLabel = (type: CashbookPersonType) => {
    const keys: Record<CashbookPersonType, string> = {
      Customer: "customer",
      Driver: "driver",
      "Vehicle Owner": "vehicleOwner",
      Broker: "broker",
      Adda: "adda",
      "Petrol Pump": "petrolPump",
      Workshop: "workshop",
      Other: "other",
    };
    return t(`cashbook.personTypes.${keys[type]}`);
  };
  const paymentMethodLabel = (method: CashbookPaymentMethod) => {
    const keys: Record<CashbookPaymentMethod, string> = {
      Cash: "cash",
      Bank: "bank",
      Cheque: "cheque",
      "Online Transfer": "onlineTransfer",
      Account: "account",
    };
    return t(`cashbook.paymentMethods.${keys[method]}`);
  };
  const dateRangeLabel = () => {
    if (filters.fromDate && filters.toDate) {
      return `${filters.fromDate} ${t("cashbook.print.to")} ${filters.toDate}`;
    }
    if (filters.fromDate) {
      return `${t("common.fromDate")}: ${filters.fromDate}`;
    }
    if (filters.toDate) {
      return `${t("cashbook.print.upTo")}: ${filters.toDate}`;
    }
    return t("cashbook.print.allDates");
  };
  const totalCashIn = rows
    .filter((row) => row.entryType === "Cash In")
    .reduce((total, row) => total + row.amount, 0);
  const totalCashOut = rows
    .filter((row) => row.entryType === "Cash Out")
    .reduce((total, row) => total + row.amount, 0);
  const finalRunningBalance = rows.at(-1)?.runningBalance ?? 0;
  const [page, setPage] = useState(1);
  const pageSize = 10;
  const totalPages = Math.max(1, Math.ceil(rows.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const visibleRows = rows.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize
  );
  function handleFilterChange<K extends keyof CashbookFilterValues>(
    key: K,
    value: CashbookFilterValues[K]
  ) {
    updateFilter(setFilters, key, value);
    setPage(1);
  }

  function handlePrintCashbookLegacy() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("cashbook.messages.allowPopups"));
      return;
    }

    const tableRows =
      rows.length > 0
        ? rows
            .map(
              (row) => `
                <tr>
                  <td class="technical">${escapeHtml(row.entryDate || "-")}</td>
                  <td>${escapeHtml(entryTypeLabel(row.entryType))}</td>
                  <td>${escapeHtml(personTypeLabel(row.personType))}</td>
                  <td>${escapeHtml(row.personName || "-")}</td>
                  <td class="technical">${escapeHtml(row.vehicleNo || "-")}</td>
                  <td>${escapeHtml(row.driverName || "-")}</td>
                  <td class="technical">${escapeHtml(row.loadingNo || "-")}</td>
                  <td>${escapeHtml(paymentMethodLabel(row.paymentMethod))}</td>
                  <td>${escapeHtml(row.description || "-")}</td>
                  <td class="cash-in">${
                    row.entryType === "Cash In"
                      ? escapeHtml(formatAmount(row.amount))
                      : "-"
                  }</td>
                  <td class="cash-out">${
                    row.entryType === "Cash Out"
                      ? escapeHtml(formatAmount(row.amount))
                      : "-"
                  }</td>
                  <td class="${
                    row.runningBalance >= 0 ? "balance-green" : "balance-red"
                  }">${escapeHtml(formatAmount(row.runningBalance))}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="12" class="empty">${escapeHtml(t("cashbook.empty"))}</td></tr>`;

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("cashbook.print.reportTitle"))}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 12mm; }
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
              padding-bottom: 16px;
              margin-bottom: 18px;
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
              text-align: end;
              font-size: 13px;
              line-height: 1.7;
              color: #111827;
            }
            .summary {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 12px;
              margin-bottom: 18px;
            }
            .summary-box {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
            }
            .summary-title {
              font-size: 12px;
              font-weight: 700;
              color: #111827;
            }
            .summary-value {
              margin-top: 5px;
              font-size: 17px;
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
            .cash-in,
            .balance-green {
              color: #047857;
              font-weight: 700;
              white-space: nowrap;
            }
            .cash-out,
            .balance-red {
              color: #b91c1c;
              font-weight: 700;
              white-space: nowrap;
            }
            .empty {
              text-align: center;
              font-weight: 700;
              padding: 18px;
            }
            tfoot td {
              background: #f9fafb;
              font-weight: 800;
              white-space: nowrap;
            }
            .technical,
            .summary-value,
            .cash-in,
            .cash-out,
            .balance-green,
            .balance-red {
              direction: ltr;
              unicode-bidi: isolate;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(t("cashbook.print.reportTitle"))}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("cashbook.print.dateRange"))}:</strong> <span class="technical">${escapeHtml(
                dateRangeLabel()
              )}</span></div>
              <div><strong>${escapeHtml(t("cashbook.print.printed"))}:</strong> <span class="technical">${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</span></div>
            </div>
          </div>

          <div class="summary">
            <div class="summary-box">
              <div class="summary-title">${escapeHtml(t("cashbook.cards.totalCashIn"))}</div>
              <div class="summary-value">${escapeHtml(
                formatAmount(totalCashIn)
              )}</div>
            </div>
            <div class="summary-box">
              <div class="summary-title">${escapeHtml(t("cashbook.cards.totalCashOut"))}</div>
              <div class="summary-value">${escapeHtml(
                formatAmount(totalCashOut)
              )}</div>
            </div>
            <div class="summary-box">
              <div class="summary-title">${escapeHtml(t("cashbook.closingBalance"))}</div>
              <div class="summary-value">${escapeHtml(
                formatAmount(finalRunningBalance)
              )}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("common.date"))}</th>
                <th>${escapeHtml(t("cashbook.fields.entryType"))}</th>
                <th>${escapeHtml(t("cashbook.fields.personType"))}</th>
                <th>${escapeHtml(t("cashbook.fields.personName"))}</th>
                <th>${escapeHtml(t("common.vehicle"))}</th>
                <th>${escapeHtml(t("common.driver"))}</th>
                <th>${escapeHtml(t("cashbook.fields.loading"))}</th>
                <th>${escapeHtml(t("cashbook.fields.paymentMethod"))}</th>
                <th>${escapeHtml(t("common.description"))}</th>
                <th>${escapeHtml(t("cashbook.entryTypes.cashIn"))}</th>
                <th>${escapeHtml(t("cashbook.entryTypes.cashOut"))}</th>
                <th>${escapeHtml(t("cashbook.runningBalance"))}</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="9">${escapeHtml(t("common.total"))}</td>
                <td class="cash-in">${escapeHtml(formatAmount(totalCashIn))}</td>
                <td class="cash-out">${escapeHtml(
                  formatAmount(totalCashOut)
                )}</td>
                <td class="${
                  finalRunningBalance >= 0 ? "balance-green" : "balance-red"
                }">${escapeHtml(formatAmount(finalRunningBalance))}</td>
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

  function handlePrintCashbook() {
    if (!addaId) return;
    const personKeys: Record<CashbookPersonType, string> = {
      Customer: "customer", Driver: "driver", "Vehicle Owner": "vehicleOwner", Broker: "broker",
      Adda: "adda", "Petrol Pump": "petrolPump", Workshop: "workshop", Other: "other",
    };
    const methodKeys: Record<CashbookPaymentMethod, string> = {
      Cash: "cash", Bank: "bank", Cheque: "cheque", "Online Transfer": "onlineTransfer", Account: "account",
    };
    const dateLabel = filters.fromDate && filters.toDate ? `${filters.fromDate} — ${filters.toDate}`
      : filters.fromDate ? `${filters.fromDate} ${t("common.fromDate")}`
        : filters.toDate ? `${t("cashbook.print.upTo")}: ${filters.toDate}` : t("cashbook.print.allDates");
    const presentation: ModulePrintPresentation = {
      documentType: "cashbook",
      title: printLabel("cashbook.print.reportTitle"),
      fields: [{ label: printLabel("cashbook.print.dateRange"), value: dateLabel }],
      totals: [
        { label: printLabel("cashbook.cards.totalCashIn"), value: formatAmount(totalCashIn) },
        { label: printLabel("cashbook.cards.totalCashOut"), value: formatAmount(totalCashOut) },
        { label: printLabel("cashbook.closingBalance"), value: formatAmount(finalRunningBalance) },
      ],
      tables: [{
        columns: ["common.date", "cashbook.fields.entryType", "cashbook.fields.personType", "cashbook.fields.personName", "common.vehicle", "common.driver", "cashbook.fields.loading", "cashbook.fields.paymentMethod", "common.description", "cashbook.entryTypes.cashIn", "cashbook.entryTypes.cashOut", "cashbook.runningBalance"].map(printLabel),
        rows: rows.map((row) => [
          printValue(row.entryDate), printLabel(row.entryType === "Cash In" ? "cashbook.entryTypes.cashIn" : "cashbook.entryTypes.cashOut"),
          printLabel(`cashbook.personTypes.${personKeys[row.personType]}`), printValue(row.personName), printValue(row.vehicleNo), printValue(row.driverName), printValue(row.loadingNo),
          printLabel(`cashbook.paymentMethods.${methodKeys[row.paymentMethod]}`), printValue(row.description),
          row.entryType === "Cash In" ? formatAmount(row.amount) : "—", row.entryType === "Cash Out" ? formatAmount(row.amount) : "—", formatAmount(row.runningBalance),
        ]),
      }],
    };
    modulePrint.openPresentation(presentation, handlePrintCashbookLegacy, addaId);
  }

  return (
    <>
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("cashbook.entriesTitle")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("cashbook.entriesDescription")}
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={handlePrintCashbook}
            className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
          >
            {t("cashbook.actions.print")}
          </button>
          <button
            type="button"
            onClick={onSync}
            disabled={isSyncing}
            className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
          >
            {isSyncing
              ? t("cashbook.states.syncing")
              : t("cashbook.actions.syncAutoEntries")}
          </button>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">

        <div>
          <label htmlFor="cashbook-from-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.fromDate")}
          </label>
          <VoiceTypingField fieldLabel="cashbook from date" mode="date"><input
            id="cashbook-from-date"
            type="date"
            value={filters.fromDate}
            onChange={(event) =>
              handleFilterChange("fromDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="cashbook-to-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.toDate")}
          </label>
          <VoiceTypingField fieldLabel="cashbook to date" mode="date"><input
            id="cashbook-to-date"
            type="date"
            value={filters.toDate}
            onChange={(event) =>
              handleFilterChange("toDate", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="cashbook-entry-type-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.entryType")}
          </label>
          <select
            id="cashbook-entry-type-filter"
            value={filters.entryType}
            onChange={(event) =>
              handleFilterChange("entryType", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("cashbook.all")}</option>
            {entryTypes.map((type) => (
              <option key={type} value={type}>
                {entryTypeLabel(type)}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="cashbook-person-type-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.personType")}
          </label>
          <select
            id="cashbook-person-type-filter"
            value={filters.personType}
            onChange={(event) =>
              handleFilterChange("personType", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("cashbook.all")}</option>
            {personTypes.map((type) => (
              <option key={type} value={type}>
                {personTypeLabel(type)}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="cashbook-payment-method-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.paymentMethod")}
          </label>
          <select
            id="cashbook-payment-method-filter"
            value={filters.paymentMethod}
            onChange={(event) =>
              handleFilterChange("paymentMethod", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("cashbook.all")}</option>
            {paymentMethods.map((method) => (
              <option key={method} value={method}>
                {paymentMethodLabel(method)}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="cashbook-search" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.actions.search")}
          </label>
          <VoiceTypingField fieldLabel={t("cashbook.placeholders.search")} mode="text"><input
            id="cashbook-search"
            type="text"
            value={filters.search}
            onChange={(event) =>
              handleFilterChange("search", event.target.value)
            }
            placeholder={t("cashbook.placeholders.search")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="cashbook-vehicle-filter" className="mb-2 block text-sm font-bold text-gray-900">{t("common.vehicle")}</label>
          <select id="cashbook-vehicle-filter" value={filters.vehicleId} onChange={(event) => handleFilterChange("vehicleId", event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100">
            <option value="">{t("cashbook.filters.allVehicles")}</option>
            {vehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicleNo}</option>)}
          </select>
        </div>

        <div>
          <label htmlFor="cashbook-driver-filter" className="mb-2 block text-sm font-bold text-gray-900">{t("common.driver")}</label>
          <select id="cashbook-driver-filter" value={filters.driverId} onChange={(event) => handleFilterChange("driverId", event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100">
            <option value="">{t("cashbook.filters.allDrivers")}</option>
            {drivers.map((driver) => <option key={driver.id} value={driver.id}>{driver.name}</option>)}
          </select>
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
          {t("common.actions.reset")}
        </button>
      </div>

      {isLoading && (
        <div className="mt-6 rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("cashbook.loading")}
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("cashbook.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-lg border border-gray-300">
          <table className="w-full min-w-[1300px] border-collapse text-start">
            <thead>
              <tr className="bg-blue-600 text-white">
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.date")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("cashbook.fields.entryType")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("cashbook.fields.personType")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("cashbook.fields.personName")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.vehicle")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("common.driver")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("cashbook.fields.loading")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  {t("cashbook.fields.paymentMethod")}
                </th>
                <th className="px-4 py-3 text-sm font-bold">
                  {t("common.description")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-end text-sm font-bold">
                  {t("cashbook.entryTypes.cashIn")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-end text-sm font-bold">
                  {t("cashbook.entryTypes.cashOut")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-end text-sm font-bold">
                  {t("cashbook.runningBalance")}
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-start text-sm font-bold">
                  {t("common.actions.title")}
                </th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {visibleRows.map((row) => (
                <tr
                  key={row.id}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td dir="ltr" className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.entryDate}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getTypeBadgeClass(
                        row.entryType
                      )}`}
                    >
                      {entryTypeLabel(row.entryType)}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {personTypeLabel(row.personType)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                    {row.personName}
                  </td>
                  <td dir="ltr" className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.vehicleNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.driverName}
                  </td>
                  <td dir="ltr" className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.loadingNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {paymentMethodLabel(row.paymentMethod)}
                  </td>
                  <td className="min-w-[260px] px-4 py-3 text-sm font-semibold">
                    <div>{row.description}</div>
                    {row.referenceType && (
                      <div className="mt-1 text-xs font-bold text-gray-900">
                        {t("cashbook.fields.reference")}:{" "}
                        <span>
                          {row.referenceType === "payment_receipt"
                            ? t("cashbook.sources.partyPayment")
                            : row.referenceType === "loading_advance"
                              ? t("cashbook.sources.loadingAdvance")
                              : row.referenceType === "voucher"
                                ? t("cashbook.sources.voucher")
                                : row.referenceType === "petrol_pump_payment"
                                  ? t("cashbook.sources.petrolPumpPayment")
                                  : <span dir="ltr">{row.referenceType}</span>}
                        </span>
                      </div>
                    )}
                  </td>
                  <td dir="ltr" className="whitespace-nowrap px-4 py-3 text-end text-sm font-extrabold text-green-700">
                    {row.entryType === "Cash In"
                      ? formatAmount(row.amount)
                      : "-"}
                  </td>
                  <td dir="ltr" className="whitespace-nowrap px-4 py-3 text-end text-sm font-extrabold text-red-700">
                    {row.entryType === "Cash Out"
                      ? formatAmount(row.amount)
                      : "-"}
                  </td>
                  <td
                    dir="ltr"
                    className={`whitespace-nowrap px-4 py-3 text-end text-sm font-extrabold ${
                      row.runningBalance >= 0
                        ? "text-green-700"
                        : "text-red-700"
                    }`}
                  >
                    {formatAmount(row.runningBalance)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">
                    {isManualCashbookEntry(row) ? (
                      <div className="flex gap-2">
                        <button type="button" aria-label={`${t("common.actions.edit")} ${row.personName}`} onClick={() => onEdit(row)} className="rounded bg-blue-600 px-3 py-2 font-bold text-white">{t("common.actions.edit")}</button>
                        <button type="button" aria-label={`${t("common.actions.delete")} ${row.personName}`} disabled={deletingId !== null} onClick={() => onDelete(row)} className="rounded bg-red-600 px-3 py-2 font-bold text-white disabled:opacity-50">{deletingId === row.id ? t("common.states.deleting") : t("common.actions.delete")}</button>
                      </div>
                    ) : (
                      <div className="max-w-48 whitespace-normal rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs font-bold text-blue-800">
                        <span>{t("cashbook.syncedEntry")}</span>
                        <span className="mt-1 block font-semibold text-gray-900">
                          {t("cashbook.messages.syncedEntryLocked")}
                        </span>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-white text-gray-900">
                <td colSpan={9} className="px-4 py-4 text-sm font-extrabold">
                  {t("common.total")}
                </td>
                <td dir="ltr" className="whitespace-nowrap px-4 py-4 text-end text-sm font-extrabold text-green-700">
                  {formatAmount(totalCashIn)}
                </td>
                <td dir="ltr" className="whitespace-nowrap px-4 py-4 text-end text-sm font-extrabold text-red-700">
                  {formatAmount(totalCashOut)}
                </td>
                <td
                  dir="ltr"
                  className={`whitespace-nowrap px-4 py-4 text-end text-sm font-extrabold ${
                    finalRunningBalance >= 0
                      ? "text-green-700"
                      : "text-red-700"
                  }`}
                >
                  {formatAmount(finalRunningBalance)}
                </td>
                <td className="px-4 py-4" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-gray-900">
          <span className="font-bold">{t("common.pagination.page")} {currentPage} {t("common.pagination.of")} {totalPages}</span>
          <div className="flex gap-2"><button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button><button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded border border-gray-300 bg-white px-4 py-2 font-bold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button></div>
        </div>
      )}
    </div>
    {modulePrint.dialog}
    </>
  );
}

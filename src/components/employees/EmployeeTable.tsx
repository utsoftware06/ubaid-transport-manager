"use client";

import { type Dispatch, type SetStateAction, useMemo } from "react";
import {
  type EmployeeRow,
  type EmployeeStatus,
  type EmployeeType,
  formatAmount,
} from "./Employees";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  addaId: string | null;
  rows: EmployeeRow[];
  reportRows: EmployeeRow[];
  search: string;
  setSearch: (value: string) => void;
  typeFilter: EmployeeType | "All";
  setTypeFilter: (value: EmployeeType | "All") => void;
  statusFilter: EmployeeStatus | "All";
  setStatusFilter: (value: EmployeeStatus | "All") => void;
  onResetFilters: () => void;
  onView: (row: EmployeeRow) => void;
  onEdit: (row: EmployeeRow) => void;
  onDelete: (row: EmployeeRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
  currentPage: number;
  totalPages: number;
  setPage: Dispatch<SetStateAction<number>>;
};

const employeeTypes: EmployeeType[] = [
  "Driver",
  "Munshi",
  "Accountant",
  "Loader",
  "Office Staff",
  "Helper",
  "Cleaner",
  "Security Guard",
  "Mechanic",
  "Other",
];

function getStatusClass(status: string) {
  if (status === "Active") {
    return "border-green-200 bg-green-100 text-green-700";
  }

  return "border-red-200 bg-red-100 text-red-700";
}

export default function EmployeeTable({
  addaId,
  rows,
  reportRows,
  search,
  setSearch,
  typeFilter,
  setTypeFilter,
  statusFilter,
  setStatusFilter,
  onResetFilters,
  onView,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
  currentPage,
  totalPages,
  setPage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("employee", addaId, language === "ur" ? "ur" : "en");
  const employeeTypeLabel = (type: EmployeeType) => {
    const keys: Record<EmployeeType, string> = {
      Driver: "driver",
      Munshi: "munshi",
      Accountant: "accountant",
      Loader: "loader",
      "Office Staff": "officeStaff",
      Helper: "helper",
      Cleaner: "cleaner",
      "Security Guard": "securityGuard",
      Mechanic: "mechanic",
      Other: "other",
    };
    return t(`employees.types.${keys[type]}`);
  };
  const statusLabel = (status: EmployeeStatus) =>
    t(`employees.statuses.${status.toLowerCase()}`);
  const totals = useMemo(
    () =>
      reportRows.reduce(
        (total, row) => ({
          monthlySalary: total.monthlySalary + row.monthlySalary,
          totalLoan: total.totalLoan + row.totalLoan,
          recoveredLoan: total.recoveredLoan + row.recoveredLoan,
          remainingLoan: total.remainingLoan + row.remainingLoan,
          salaryGenerated: total.salaryGenerated + row.totalSalaryGenerated,
          salaryPaid: total.salaryPaid + row.totalSalaryPaid,
          remainingSalary: total.remainingSalary + row.remainingSalary,
        }),
        {
          monthlySalary: 0,
          totalLoan: 0,
          recoveredLoan: 0,
          remainingLoan: 0,
          salaryGenerated: 0,
          salaryPaid: 0,
          remainingSalary: 0,
        }
      ),
    [reportRows]
  );
  const pageNumbers = Array.from({ length: totalPages }, (_, index) => index + 1);

  function handlePrintReportLegacy() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("employees.messages.allowPopups"));
      return;
    }

    const tableRows =
      reportRows.length > 0
        ? reportRows
            .map(
              (row) => `
                <tr>
                  <td>${escapeHtml(row.employeeName)}</td>
                  <td>${escapeHtml(employeeTypeLabel(row.employeeType))}</td>
                  <td>${escapeHtml(row.driverName)}</td>
                  <td class="technical">${escapeHtml(row.phone)}</td>
                  <td class="technical">${escapeHtml(row.cnic)}</td>
                  <td class="technical">${escapeHtml(row.joiningDate || "-")}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.monthlySalary))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.totalLoan))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.recoveredLoan))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.remainingLoan))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.totalSalaryGenerated))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.totalSalaryPaid))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.remainingSalary))}</td>
                  <td>${escapeHtml(statusLabel(row.status))}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="14" class="empty">${escapeHtml(t("employees.empty"))}</td></tr>`;

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("employees.print.reportTitle"))}</title>
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
            .technical, tfoot td { direction: ltr; unicode-bidi: isolate; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <h2>${escapeHtml(t("employees.print.reportTitle"))}</h2>
            </div>
            <div class="meta">
              <div><strong>${escapeHtml(t("employees.print.printed"))}:</strong> <span class="technical">${escapeHtml(
                new Date().toLocaleString("en-PK")
              )}</span></div>
              <div><strong>${escapeHtml(t("employees.cards.totalEmployees"))}:</strong> <span class="technical">${reportRows.length}</span></div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("employees.fields.name"))}</th>
                <th>${escapeHtml(t("employees.fields.type"))}</th>
                <th>${escapeHtml(t("common.driver"))}</th>
                <th>${escapeHtml(t("employees.fields.phone"))}</th>
                <th>${escapeHtml(t("employees.fields.cnic"))}</th>
                <th>${escapeHtml(t("employees.fields.joiningDate"))}</th>
                <th>${escapeHtml(t("employees.fields.monthlySalary"))}</th>
                <th>${escapeHtml(t("employees.cards.totalLoan"))}</th>
                <th>${escapeHtml(t("employees.cards.recoveredLoan"))}</th>
                <th>${escapeHtml(t("employees.cards.remainingLoan"))}</th>
                <th>${escapeHtml(t("employees.fields.salaryGenerated"))}</th>
                <th>${escapeHtml(t("employees.fields.salaryPaid"))}</th>
                <th>${escapeHtml(t("employees.cards.remainingSalary"))}</th>
                <th>${escapeHtml(t("common.status"))}</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="6">${escapeHtml(t("common.total"))}</td>
                <td>${escapeHtml(formatAmount(totals.monthlySalary))}</td>
                <td>${escapeHtml(formatAmount(totals.totalLoan))}</td>
                <td>${escapeHtml(formatAmount(totals.recoveredLoan))}</td>
                <td>${escapeHtml(formatAmount(totals.remainingLoan))}</td>
                <td>${escapeHtml(formatAmount(totals.salaryGenerated))}</td>
                <td>${escapeHtml(formatAmount(totals.salaryPaid))}</td>
                <td>${escapeHtml(formatAmount(totals.remainingSalary))}</td>
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

  function handlePrintReport() {
    const typeKey: Record<EmployeeType, string> = {
      Driver: "driver", Munshi: "munshi", Accountant: "accountant", Loader: "loader",
      "Office Staff": "officeStaff", Helper: "helper", Cleaner: "cleaner",
      "Security Guard": "securityGuard", Mechanic: "mechanic", Other: "other",
    };
    const presentation: ModulePrintPresentation = {
      documentType: "employee",
      title: printLabel("employees.print.reportTitle"),
      subtitle: printLabel("employees.recordsTitle"),
      fields: [{ label: printLabel("employees.cards.totalEmployees"), value: printValue(reportRows.length) }],
      tables: [{
        columns: [printLabel("employees.fields.name"), printLabel("employees.fields.type"), printLabel("common.driver"), printLabel("employees.fields.phone"), printLabel("employees.fields.cnic"), printLabel("employees.fields.joiningDate"), printLabel("employees.fields.monthlySalary"), printLabel("employees.cards.totalLoan"), printLabel("employees.cards.recoveredLoan"), printLabel("employees.cards.remainingLoan"), printLabel("employees.fields.salaryGenerated"), printLabel("employees.fields.salaryPaid"), printLabel("employees.cards.remainingSalary"), printLabel("common.status")],
        rows: reportRows.map((row) => [printValue(row.employeeName), printLabel(`employees.types.${typeKey[row.employeeType]}`), printValue(row.driverName), printValue(row.phone), printValue(row.cnic), printValue(row.joiningDate), printValue(formatAmount(row.monthlySalary)), printValue(formatAmount(row.totalLoan)), printValue(formatAmount(row.recoveredLoan)), printValue(formatAmount(row.remainingLoan)), printValue(formatAmount(row.totalSalaryGenerated)), printValue(formatAmount(row.totalSalaryPaid)), printValue(formatAmount(row.remainingSalary)), printLabel(`employees.statuses.${row.status.toLowerCase()}`)]),
      }],
      totals: [
        { label: printLabel("employees.fields.monthlySalary"), value: printValue(formatAmount(totals.monthlySalary)) },
        { label: printLabel("employees.cards.totalLoan"), value: printValue(formatAmount(totals.totalLoan)) },
        { label: printLabel("employees.cards.recoveredLoan"), value: printValue(formatAmount(totals.recoveredLoan)) },
        { label: printLabel("employees.cards.remainingLoan"), value: printValue(formatAmount(totals.remainingLoan)) },
        { label: printLabel("employees.fields.salaryGenerated"), value: printValue(formatAmount(totals.salaryGenerated)) },
        { label: printLabel("employees.fields.salaryPaid"), value: printValue(formatAmount(totals.salaryPaid)) },
        { label: printLabel("employees.cards.remainingSalary"), value: printValue(formatAmount(totals.remainingSalary)) },
      ],
    };
    modulePrint.openPresentation(presentation, handlePrintReportLegacy, addaId);
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("employees.recordsTitle")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("employees.recordsDescription")}
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={handlePrintReport}
            aria-label={t("employees.actions.printReport")}
            className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white transition hover:bg-gray-800"
          >
            {t("employees.actions.printReport")}
          </button>
        </div>
      </div>

      <div className="mb-6 grid grid-cols-1 gap-3 rounded-xl border border-gray-300 bg-white p-4 shadow-sm sm:grid-cols-2 lg:grid-cols-4">

        <div>
          <label
            htmlFor="employee-search"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("common.actions.search")}
          </label>
          <VoiceTypingField fieldLabel={t("employees.placeholders.search")} mode="text"><input
            id="employee-search"
            type="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder={t("employees.placeholders.search")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label
            htmlFor="employee-type-filter"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("employees.fields.type")}
          </label>
          <select
            id="employee-type-filter"
            value={typeFilter}
            onChange={(event) =>
              setTypeFilter(event.target.value as EmployeeType | "All")
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="All">{t("employees.filters.allTypes")}</option>
            {employeeTypes.map((type) => (
              <option key={type} value={type}>
                {employeeTypeLabel(type)}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label
            htmlFor="employee-status-filter"
            className="mb-2 block text-sm font-bold text-gray-900"
          >
            {t("common.status")}
          </label>
          <select
            id="employee-status-filter"
            value={statusFilter}
            onChange={(event) =>
              setStatusFilter(event.target.value as EmployeeStatus | "All")
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="All">{t("employees.filters.allStatuses")}</option>
            <option value="Active">{statusLabel("Active")}</option>
            <option value="Inactive">{statusLabel("Inactive")}</option>
          </select>
        </div>

        <div className="flex items-end">
          <button
            type="button"
            onClick={onResetFilters}
            className="w-full rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            {t("common.actions.reset")}
          </button>
        </div>
      </div>

      {isLoading && (
        <div className="rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("employees.loading")}
        </div>
      )}

      {modulePrint.dialog}

      {!isLoading && errorMessage && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && reportRows.length === 0 && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          {t("employees.empty")}
        </div>
      )}

      {!isLoading && !errorMessage && reportRows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[1800px] border-collapse bg-white text-sm text-gray-900">
            <caption className="sr-only">{t("employees.recordsTitle")}</caption>
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("employees.fields.name")}</th>
                <th className="p-3 text-start font-bold">{t("employees.fields.type")}</th>
                <th className="p-3 text-start font-bold">{t("common.driver")}</th>
                <th className="p-3 text-start font-bold">{t("employees.fields.phone")}</th>
                <th className="p-3 text-start font-bold">{t("employees.fields.cnic")}</th>
                <th className="p-3 text-start font-bold">{t("employees.fields.joiningDate")}</th>
                <th className="p-3 text-end font-bold">{t("employees.fields.monthlySalary")}</th>
                <th className="p-3 text-end font-bold">{t("employees.cards.totalLoan")}</th>
                <th className="p-3 text-end font-bold">{t("employees.cards.recoveredLoan")}</th>
                <th className="p-3 text-end font-bold">{t("employees.cards.remainingLoan")}</th>
                <th className="p-3 text-end font-bold">{t("employees.fields.salaryGenerated")}</th>
                <th className="p-3 text-end font-bold">{t("employees.fields.salaryPaid")}</th>
                <th className="p-3 text-end font-bold">{t("employees.cards.remainingSalary")}</th>
                <th className="p-3 text-start font-bold">{t("common.status")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 font-bold">{row.employeeName}</td>
                  <td className="p-3 font-semibold">{employeeTypeLabel(row.employeeType)}</td>
                  <td className="p-3 font-semibold">{row.driverName}</td>
                  <td dir="ltr" className="p-3 font-semibold">{row.phone}</td>
                  <td dir="ltr" className="p-3 font-semibold">{row.cnic}</td>
                  <td dir="ltr" className="p-3 font-semibold">
                    {row.joiningDate || "-"}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold">
                    {formatAmount(row.monthlySalary)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-purple-700">
                    {formatAmount(row.totalLoan)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-green-700">
                    {formatAmount(row.recoveredLoan)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-red-700">
                    {formatAmount(row.remainingLoan)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold">
                    {formatAmount(row.totalSalaryGenerated)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-green-700">
                    {formatAmount(row.totalSalaryPaid)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-orange-700">
                    {formatAmount(row.remainingSalary)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.status
                      )}`}
                    >
                      {statusLabel(row.status)}
                    </span>
                  </td>
                  <td className="min-w-[150px] p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => onView(row)}
                        aria-label={`${t("common.actions.details")}: ${row.employeeName}`}
                        className="rounded-lg bg-gray-800 px-3 py-2 font-semibold text-white transition hover:bg-gray-900"
                      >
                        {t("common.actions.details")}
                      </button>

                      <button
                        type="button"
                        onClick={() => onEdit(row)}
                        aria-label={`${t("common.actions.edit")}: ${row.employeeName}`}
                        className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                      >
                        {t("common.actions.edit")}
                      </button>

                      <button
                        type="button"
                        onClick={() => onDelete(row)}
                        aria-label={`${t("common.actions.delete")}: ${row.employeeName}`}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        {t("common.actions.delete")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td colSpan={6} className="p-3 font-extrabold">
                  {t("common.total")}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold">
                  {formatAmount(totals.monthlySalary)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-purple-700">
                  {formatAmount(totals.totalLoan)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-green-700">
                  {formatAmount(totals.recoveredLoan)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-red-700">
                  {formatAmount(totals.remainingLoan)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold">
                  {formatAmount(totals.salaryGenerated)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-green-700">
                  {formatAmount(totals.salaryPaid)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-orange-700">
                  {formatAmount(totals.remainingSalary)}
                </td>
                <td colSpan={2} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}

      {!isLoading && !errorMessage && reportRows.length > 0 && (
        <nav
          aria-label={t("common.pagination.page")}
          className="mt-5 flex flex-col items-center justify-between gap-3 sm:flex-row"
        >
          <span className="font-semibold text-gray-900">
            {t("common.pagination.page")}{" "}
            <span dir="ltr">{currentPage}</span> {t("common.pagination.of")}{" "}
            <span dir="ltr">{totalPages}</span>
          </span>

          <div className="flex flex-wrap items-center justify-center gap-2">
            <button
              type="button"
              aria-label={t("common.pagination.previous")}
              disabled={currentPage === 1}
              onClick={() => setPage((value) => Math.max(1, value - 1))}
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
            >
              {t("common.pagination.previous")}
            </button>

            {pageNumbers.map((pageNumber) => (
              <button
                key={pageNumber}
                type="button"
                aria-label={`${t("common.pagination.page")} ${pageNumber}`}
                aria-current={pageNumber === currentPage ? "page" : undefined}
                onClick={() => setPage(pageNumber)}
                className={`h-10 min-w-10 rounded-lg border px-3 font-bold ${
                  pageNumber === currentPage
                    ? "border-blue-600 bg-blue-600 text-white"
                    : "border-gray-300 bg-white text-gray-900"
                }`}
              >
                <span dir="ltr">{pageNumber}</span>
              </button>
            ))}

            <button
              type="button"
              aria-label={t("common.pagination.next")}
              disabled={currentPage === totalPages}
              onClick={() =>
                setPage((value) => Math.min(totalPages, value + 1))
              }
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600"
            >
              {t("common.pagination.next")}
            </button>
          </div>
        </nav>
      )}
    </div>
  );
}

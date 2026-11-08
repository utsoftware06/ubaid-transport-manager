"use client";

import { type Dispatch, type SetStateAction, useState } from "react";
import EmployeeAccountingDetails from "./EmployeeAccountingDetails";
import {
  type EmployeeSalaryRow,
  type SalaryMethodFilter,
  type SalaryPaymentMethod,
  type SalaryStatusFilter,
  formatAmount,
} from "./EmployeeSalary";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  addaId: string | null;
  rows: EmployeeSalaryRow[];
  reportRows: EmployeeSalaryRow[];
  search: string;
  setSearch: (value: string) => void;
  statusFilter: SalaryStatusFilter;
  setStatusFilter: (value: SalaryStatusFilter) => void;
  methodFilter: SalaryMethodFilter;
  setMethodFilter: (value: SalaryMethodFilter) => void;
  onResetFilters: () => void;
  currentPage: number;
  totalPages: number;
  setPage: Dispatch<SetStateAction<number>>;
  onEdit: (row: EmployeeSalaryRow) => void;
  onDelete: (row: EmployeeSalaryRow) => void;
  onPrintSlip: (row: EmployeeSalaryRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
};

function statusClass(status: EmployeeSalaryRow["paymentStatus"]) {
  if (status === "Paid") return "bg-green-100 text-green-700";
  if (status === "Partial") return "bg-orange-100 text-orange-700";
  return "bg-red-100 text-red-700";
}

export default function EmployeeSalaryTable({
  addaId,
  rows,
  reportRows,
  search,
  setSearch,
  statusFilter,
  setStatusFilter,
  methodFilter,
  setMethodFilter,
  onResetFilters,
  currentPage,
  totalPages,
  setPage,
  onEdit,
  onDelete,
  onPrintSlip,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("employee", addaId, language === "ur" ? "ur" : "en");
  const [viewingRow, setViewingRow] = useState<EmployeeSalaryRow | null>(null);
  const statusLabel = (status: string) =>
    t(`common.paymentStatus.${status.toLowerCase()}`);
  const paymentMethodLabel = (method: string) => {
    const keys: Record<string, string> = {
      Cash: "cash",
      Bank: "bank",
      Cheque: "cheque",
      "Online Transfer": "onlineTransfer",
      Account: "account",
    };
    const key = keys[method];
    return key ? t(`employeeSalary.paymentMethods.${key}`) : method;
  };
  const totals = reportRows.reduce(
    (total, row) => {
      total.basic += row.basicSalary;
      total.bonus += row.bonus;
      total.deduction += row.deduction;
      total.loanRecovery += row.loanRecovery;
      total.advanceRecovery += row.advanceRecovery;
      total.net += row.netSalary;
      total.paid += row.paidAmount;
      total.remaining += row.remainingAmount;
      return total;
    },
    {
      basic: 0,
      bonus: 0,
      deduction: 0,
      loanRecovery: 0,
      advanceRecovery: 0,
      net: 0,
      paid: 0,
      remaining: 0,
    }
  );

  function handlePrintReportLegacy() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("employeeSalary.messages.allowReportPopups"));
      return;
    }

    const bodyRows =
      reportRows.length > 0
        ? reportRows
            .map(
              (row) => `
                <tr>
                  <td class="technical">${escapeHtml(row.salaryMonth)}</td>
                  <td>${escapeHtml(row.employeeName)}</td>
                  <td>${escapeHtml(row.employeeType)}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.basicSalary))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.bonus))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.deduction))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.loanRecovery))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.advanceRecovery))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.netSalary))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.paidAmount))}</td>
                  <td class="technical">${escapeHtml(formatAmount(row.remainingAmount))}</td>
                  <td>${escapeHtml(statusLabel(row.paymentStatus))}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="12" class="empty">${escapeHtml(t("employeeSalary.empty"))}</td></tr>`;

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("employeeSalary.print.reportTitle"))}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 12mm; }
            body { margin: 0; color: #111827; font-family: Arial, sans-serif; direction: ${dir}; text-align: start; }
            .header {
              display: flex;
              justify-content: space-between;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 14px;
              margin-bottom: 18px;
            }
            h1 { margin: 0; font-size: 26px; font-weight: 800; }
            .subtitle { margin-top: 5px; font-size: 15px; font-weight: 700; }
            .printed { text-align: end; font-size: 13px; font-weight: 700; line-height: 1.6; }
            table { width: 100%; border-collapse: collapse; font-size: 10px; }
            th { background: #2563eb; color: #fff; padding: 7px; border: 1px solid #2563eb; text-align: start; }
            td { padding: 6px; border: 1px solid #d1d5db; color: #111827; }
            tfoot td { background: #f3f4f6; font-weight: 900; }
            .empty { text-align: center; padding: 16px; font-weight: 800; }
            .technical, tfoot td { direction: ltr; unicode-bidi: isolate; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
              <div class="subtitle">${escapeHtml(t("employeeSalary.print.reportTitle"))}</div>
            </div>
            <div class="printed">
              <div>${escapeHtml(t("employeeSalary.print.printed"))}: <span class="technical">${escapeHtml(new Date().toLocaleString("en-PK"))}</span></div>
              <div>${escapeHtml(t("employeeSalary.cards.totalRecords"))}: <span class="technical">${reportRows.length}</span></div>
            </div>
          </div>
          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("employeeSalary.fields.salaryMonth"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.employee"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.type"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.basicSalary"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.bonus"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.deduction"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.loanRecovery"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.advanceRecovery"))}</th>
                <th>${escapeHtml(t("employeeSalary.fields.netSalary"))}</th>
                <th>${escapeHtml(t("common.paid"))}</th>
                <th>${escapeHtml(t("common.remaining"))}</th>
                <th>${escapeHtml(t("common.status"))}</th>
              </tr>
            </thead>
            <tbody>${bodyRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="3">${escapeHtml(t("employeeSalary.totals"))}</td>
                <td>${escapeHtml(formatAmount(totals.basic))}</td>
                <td>${escapeHtml(formatAmount(totals.bonus))}</td>
                <td>${escapeHtml(formatAmount(totals.deduction))}</td>
                <td>${escapeHtml(formatAmount(totals.loanRecovery))}</td>
                <td>${escapeHtml(formatAmount(totals.advanceRecovery))}</td>
                <td>${escapeHtml(formatAmount(totals.net))}</td>
                <td>${escapeHtml(formatAmount(totals.paid))}</td>
                <td>${escapeHtml(formatAmount(totals.remaining))}</td>
                <td></td>
              </tr>
            </tfoot>
          </table>
          <script>
            window.onload = function () { window.print(); };
            window.onafterprint = function () { window.close(); };
          </script>
        </body>
      </html>
    `, addaId, language === "ur" ? "ur" : "en");
  }

  function handlePrintReport() {
    const presentation: ModulePrintPresentation = {
      documentType: "employee",
      title: printLabel("employeeSalary.print.reportTitle"),
      subtitle: printLabel("employeeSalary.recordsTitle"),
      fields: [{ label: printLabel("employeeSalary.cards.totalRecords"), value: printValue(reportRows.length) }],
      tables: [{
        columns: [printLabel("employeeSalary.fields.salaryMonth"), printLabel("employeeSalary.fields.employee"), printLabel("employeeSalary.fields.type"), printLabel("employeeSalary.fields.basicSalary"), printLabel("employeeSalary.fields.bonus"), printLabel("employeeSalary.fields.deduction"), printLabel("employeeSalary.fields.loanRecovery"), printLabel("employeeSalary.fields.advanceRecovery"), printLabel("employeeSalary.fields.netSalary"), printLabel("common.paid"), printLabel("common.remaining"), printLabel("common.status")],
        rows: reportRows.map((row) => [printValue(row.salaryMonth), printValue(row.employeeName), printValue(row.employeeType), printValue(formatAmount(row.basicSalary)), printValue(formatAmount(row.bonus)), printValue(formatAmount(row.deduction)), printValue(formatAmount(row.loanRecovery)), printValue(formatAmount(row.advanceRecovery)), printValue(formatAmount(row.netSalary)), printValue(formatAmount(row.paidAmount)), printValue(formatAmount(row.remainingAmount)), printLabel(`common.paymentStatus.${row.paymentStatus.toLowerCase()}`)]),
      }],
      totals: [
        { label: printLabel("employeeSalary.fields.basicSalary"), value: printValue(formatAmount(totals.basic)) },
        { label: printLabel("employeeSalary.fields.bonus"), value: printValue(formatAmount(totals.bonus)) },
        { label: printLabel("employeeSalary.fields.deduction"), value: printValue(formatAmount(totals.deduction)) },
        { label: printLabel("employeeSalary.fields.loanRecovery"), value: printValue(formatAmount(totals.loanRecovery)) },
        { label: printLabel("employeeSalary.fields.advanceRecovery"), value: printValue(formatAmount(totals.advanceRecovery)) },
        { label: printLabel("employeeSalary.fields.netSalary"), value: printValue(formatAmount(totals.net)) },
        { label: printLabel("common.paid"), value: printValue(formatAmount(totals.paid)) },
        { label: printLabel("common.remaining"), value: printValue(formatAmount(totals.remaining)) },
      ],
    };
    modulePrint.openPresentation(presentation, handlePrintReportLegacy, addaId);
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("employeeSalary.recordsTitle")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("employeeSalary.recordsDescription")}
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintReport}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700"
        >
          {t("employeeSalary.actions.printReport")}
        </button>
      </div>


      <div className="mb-5 grid grid-cols-1 gap-3 rounded-xl border border-gray-300 bg-white p-4 shadow-sm sm:grid-cols-2 xl:grid-cols-4">
        <VoiceTypingField fieldLabel={t("employeeSalary.placeholders.search")} mode="text"><input
          type="search"
          aria-label={t("employeeSalary.placeholders.search")}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t("employeeSalary.placeholders.search")}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
        /></VoiceTypingField>
        <select
          aria-label={t("employeeSalary.filters.paymentStatus")}
          value={statusFilter}
          onChange={(event) =>
            setStatusFilter(event.target.value as SalaryStatusFilter)
          }
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="All">{t("employeeSalary.filters.allStatuses")}</option>
          <option value="Paid">{statusLabel("Paid")}</option>
          <option value="Partial">{statusLabel("Partial")}</option>
          <option value="Unpaid">{statusLabel("Unpaid")}</option>
        </select>
        <select
          aria-label={t("employeeSalary.fields.paymentMethod")}
          value={methodFilter}
          onChange={(event) =>
            setMethodFilter(event.target.value as SalaryMethodFilter)
          }
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="All">{t("employeeSalary.filters.allMethods")}</option>
          {(["Cash", "Bank", "Cheque", "Online Transfer", "Account"] as SalaryPaymentMethod[]).map(
            (method) => (
              <option key={method} value={method}>
                {paymentMethodLabel(method)}
              </option>
            )
          )}
        </select>
        <button
          type="button"
          onClick={onResetFilters}
          className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 hover:bg-gray-300"
        >
          {t("common.actions.reset")}
        </button>
      </div>


      {errorMessage && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {isLoading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          {t("employeeSalary.loading")}
        </div>
      ) : reportRows.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          {t("employeeSalary.empty")}
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1800px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("employeeSalary.fields.salaryMonth")}</th>
                <th className="p-3 text-start font-bold">{t("employeeSalary.fields.employee")}</th>
                <th className="p-3 text-start font-bold">{t("employeeSalary.fields.type")}</th>
                <th className="p-3 text-end font-bold">{t("employeeSalary.fields.basicSalary")}</th>
                <th className="p-3 text-end font-bold">{t("employeeSalary.fields.bonus")}</th>
                <th className="p-3 text-end font-bold">{t("employeeSalary.fields.deduction")}</th>
                <th className="p-3 text-end font-bold">{t("employeeSalary.fields.loanRecovery")}</th>
                <th className="p-3 text-end font-bold">{t("employeeSalary.fields.advanceRecovery")}</th>
                <th className="p-3 text-end font-bold">{t("employeeSalary.fields.netSalary")}</th>
                <th className="p-3 text-end font-bold">{t("common.paid")}</th>
                <th className="p-3 text-end font-bold">{t("common.remaining")}</th>
                <th className="p-3 text-start font-bold">{t("common.status")}</th>
                <th className="p-3 text-start font-bold">{t("employeeSalary.fields.paymentMethod")}</th>
                <th className="p-3 text-start font-bold">{t("employeeSalary.fields.referenceNo")}</th>
                <th className="p-3 text-start font-bold">{t("common.remarks")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr key={row.id} className="hover:bg-blue-50">
                  <td dir="ltr" className="p-3 font-medium text-gray-900">{row.salaryMonth}</td>
                  <td className="p-3 font-bold text-gray-900">{row.employeeName}</td>
                  <td className="p-3 font-medium text-gray-900">{row.employeeType}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-gray-900">{formatAmount(row.basicSalary)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-green-700">{formatAmount(row.bonus)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-red-700">{formatAmount(row.deduction)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-orange-700">{formatAmount(row.loanRecovery)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-red-700">{formatAmount(row.advanceRecovery)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-blue-700">{formatAmount(row.netSalary)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-green-700">{formatAmount(row.paidAmount)}</td>
                  <td dir="ltr" className="p-3 text-end font-bold text-red-700">{formatAmount(row.remainingAmount)}</td>
                  <td className="p-3">
                    <span className={`rounded-full px-3 py-1 text-xs font-extrabold ${statusClass(row.paymentStatus)}`}>
                      {statusLabel(row.paymentStatus)}
                    </span>
                  </td>
                  <td className="p-3 font-medium text-gray-900">{paymentMethodLabel(row.paymentMethod)}</td>
                  <td dir="ltr" className="p-3 font-medium text-gray-900">{row.referenceNo || "-"}</td>
                  <td className="max-w-[260px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">{row.remarks || "-"}</div>
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button type="button" aria-label={`${t("common.actions.details")}: ${row.employeeName}`} onClick={() => setViewingRow(row)} className="rounded-lg bg-gray-700 px-3 py-2 text-xs font-bold text-white hover:bg-gray-800">
                        {t("common.actions.details")}
                      </button>
                      <button type="button" aria-label={`${t("common.actions.edit")}: ${row.employeeName}`} onClick={() => onEdit(row)} className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700">
                        {t("common.actions.edit")}
                      </button>
                      <button type="button" aria-label={`${t("common.actions.delete")}: ${row.employeeName}`} onClick={() => onDelete(row)} disabled={isDeleting} className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:cursor-not-allowed">
                        {t("common.actions.delete")}
                      </button>
                      <button type="button" aria-label={`${t("employeeSalary.actions.printSlip")}: ${row.employeeName}`} onClick={() => onPrintSlip(row)} className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-black">
                        {t("employeeSalary.actions.printSlip")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td colSpan={3} className="p-3 text-end font-extrabold text-gray-900">
                  {t("employeeSalary.totals")}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-gray-900">{formatAmount(totals.basic)}</td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-green-700">{formatAmount(totals.bonus)}</td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-red-700">{formatAmount(totals.deduction)}</td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-orange-700">{formatAmount(totals.loanRecovery)}</td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-red-700">{formatAmount(totals.advanceRecovery)}</td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-blue-700">{formatAmount(totals.net)}</td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-green-700">{formatAmount(totals.paid)}</td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-red-700">{formatAmount(totals.remaining)}</td>
                <td colSpan={5} className="p-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}

      {!isLoading && !errorMessage && reportRows.length > 0 && (
        <nav aria-label={t("common.pagination.page")} className="mt-5 flex flex-wrap items-center justify-between gap-3">
          <span className="font-semibold">{t("common.pagination.page")} <span dir="ltr">{currentPage}</span> {t("common.pagination.of")} <span dir="ltr">{totalPages}</span></span>
          <div className="flex flex-wrap gap-2">
            <button type="button" aria-label={t("common.pagination.previous")} disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.previous")}</button>
            {Array.from({ length: totalPages }, (_, index) => index + 1).map((pageNumber) => (
              <button key={pageNumber} type="button" aria-label={`${t("common.pagination.page")} ${pageNumber}`} aria-current={pageNumber === currentPage ? "page" : undefined} onClick={() => setPage(pageNumber)} className={`h-10 min-w-10 rounded-lg border px-3 font-bold ${pageNumber === currentPage ? "border-blue-600 bg-blue-600 text-white" : "border-gray-300 bg-white text-gray-900"}`}><span dir="ltr">{pageNumber}</span></button>
            ))}
            <button type="button" aria-label={t("common.pagination.next")} disabled={currentPage === totalPages} onClick={() => setPage((value) => Math.min(totalPages, value + 1))} className="rounded-lg border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-900 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-600">{t("common.pagination.next")}</button>
          </div>
        </nav>
      )}

      {viewingRow && (
        <EmployeeAccountingDetails
          title={t("employeeSalary.detailsTitle")}
          description={viewingRow.employeeName}
          onClose={() => setViewingRow(null)}
          details={[
            { label: t("employeeSalary.fields.salaryMonth"), value: viewingRow.salaryMonth, technical: true },
            { label: t("employeeSalary.fields.employee"), value: viewingRow.employeeName },
            { label: t("employeeSalary.fields.type"), value: viewingRow.employeeType },
            { label: t("employeeSalary.fields.basicSalary"), value: formatAmount(viewingRow.basicSalary), technical: true },
            { label: t("employeeSalary.fields.bonus"), value: formatAmount(viewingRow.bonus), technical: true },
            { label: t("employeeSalary.fields.deduction"), value: formatAmount(viewingRow.deduction), technical: true },
            { label: t("employeeSalary.fields.loanRecovery"), value: formatAmount(viewingRow.loanRecovery), technical: true },
            { label: t("employeeSalary.fields.advanceRecovery"), value: formatAmount(viewingRow.advanceRecovery), technical: true },
            { label: t("employeeSalary.fields.netSalary"), value: formatAmount(viewingRow.netSalary), technical: true },
            { label: t("common.paid"), value: formatAmount(viewingRow.paidAmount), technical: true },
            { label: t("common.remaining"), value: formatAmount(viewingRow.remainingAmount), technical: true },
            { label: t("common.status"), value: statusLabel(viewingRow.paymentStatus) },
            { label: t("employeeSalary.fields.paymentMethod"), value: paymentMethodLabel(viewingRow.paymentMethod) },
            { label: t("employeeSalary.fields.referenceNo"), value: viewingRow.referenceNo, technical: true },
            { label: t("common.remarks"), value: viewingRow.remarks },
          ]}
        />
      )}
      {modulePrint.dialog}
    </div>
  );
}

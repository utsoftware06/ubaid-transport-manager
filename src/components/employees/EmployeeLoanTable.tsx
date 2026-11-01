"use client";

import { type Dispatch, type SetStateAction, useState } from "react";
import EmployeeAccountingDetails from "./EmployeeAccountingDetails";
import {
  type EmployeeLoanRow,
  type EmployeeLoanStatusFilter,
  formatAmount,
} from "./EmployeeLoans";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { usePrintAddaName } from "@/lib/print/usePrintAddaName";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  addaId: string | null;
  rows: EmployeeLoanRow[];
  reportRows: EmployeeLoanRow[];
  search: string;
  setSearch: (value: string) => void;
  statusFilter: EmployeeLoanStatusFilter;
  setStatusFilter: (value: EmployeeLoanStatusFilter) => void;
  onResetFilters: () => void;
  currentPage: number;
  totalPages: number;
  setPage: Dispatch<SetStateAction<number>>;
  onEdit: (row: EmployeeLoanRow) => void;
  onDelete: (row: EmployeeLoanRow) => void;
  isDeleting: boolean;
  isLoading: boolean;
  errorMessage: string;
};

function getStatusBadgeClass(status: EmployeeLoanRow["status"]) {
  if (status === "Completed") {
    return "bg-green-100 text-green-700";
  }

  return "bg-orange-100 text-orange-700";
}

export default function EmployeeLoanTable({
  addaId,
  rows,
  reportRows,
  search,
  setSearch,
  statusFilter,
  setStatusFilter,
  onResetFilters,
  currentPage,
  totalPages,
  setPage,
  onEdit,
  onDelete,
  isDeleting,
  isLoading,
  errorMessage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const addaName = usePrintAddaName(addaId, language === "ur" ? "ur" : "en");
  const modulePrint = useModuleTransportPrint("employee", addaId, language === "ur" ? "ur" : "en");
  const [viewingRow, setViewingRow] = useState<EmployeeLoanRow | null>(null);
  const statusLabel = (status: EmployeeLoanRow["status"]) =>
    t(`employeeLoans.statuses.${status.toLowerCase()}`);
  const paymentMethodLabel = (method: EmployeeLoanRow["paymentMethod"]) =>
    t(
      `employeeLoans.paymentMethods.${
        method === "Online Transfer" ? "onlineTransfer" : method.toLowerCase()
      }`
    );
  const totalLoanAmount = reportRows.reduce((total, row) => total + row.loanAmount, 0);
  const totalMonthlyInstallment = reportRows.reduce(
    (total, row) => total + row.monthlyInstallment,
    0
  );
  const totalRecovered = reportRows.reduce(
    (total, row) => total + row.recoveredAmount,
    0
  );
  const totalRemaining = reportRows.reduce(
    (total, row) => total + row.remainingAmount,
    0
  );

  function handlePrintReceiptLegacy(row: EmployeeLoanRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert(t("employeeLoans.messages.allowReceiptPopups"));
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
        <head>
          <title>${escapeHtml(t("employeeLoans.print.receiptTitle"))} - ${escapeHtml(row.employeeName)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              background: #ffffff;
              color: #111827;
              font-family: Arial, sans-serif;
            }
            .receipt {
              max-width: 850px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 12px;
              padding: 28px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 18px;
              margin-bottom: 24px;
            }
            h1 {
              margin: 0;
              color: #111827;
              font-size: 28px;
              font-weight: 800;
            }
            .subtitle {
              margin-top: 6px;
              color: #111827;
              font-size: 15px;
              font-weight: 600;
            }
            .meta {
              text-align: end;
              color: #111827;
              font-size: 14px;
              line-height: 1.7;
            }
            .grid {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 14px 22px;
            }
            .field {
              border: 1px solid #e5e7eb;
              border-radius: 8px;
              padding: 12px;
              background: #f9fafb;
            }
            .label {
              color: #111827;
              font-size: 12px;
              font-weight: 700;
              text-transform: uppercase;
            }
            .value {
              margin-top: 6px;
              color: #111827;
              font-size: 16px;
              font-weight: 800;
            }
            .status {
              display: inline-block;
              border-radius: 999px;
              padding: 5px 12px;
              font-size: 13px;
              font-weight: 800;
              ${
                row.status === "Completed"
                  ? "background:#dcfce7;color:#15803d;"
                  : "background:#ffedd5;color:#c2410c;"
              }
            }
            .remarks {
              grid-column: 1 / -1;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 42px;
              margin-top: 64px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 10px;
              text-align: center;
              color: #111827;
              font-size: 14px;
              font-weight: 700;
            }
            @media print {
              body { padding: 0; }
              .receipt {
                border: none;
                border-radius: 0;
              }
            }
          </style>
        </head>
        <body dir="${escapeHtml(dir)}">
          <div class="receipt">
            <div class="header">
              <div>
                <h1>${escapeHtml(addaName)}</h1>
                <div class="subtitle">${escapeHtml(t("employeeLoans.print.receiptTitle"))}</div>
              </div>
              <div class="meta">
                <div><strong>${escapeHtml(t("employeeLoans.fields.loanDate"))}:</strong> <span dir="ltr">${escapeHtml(row.loanDate || "-")}</span></div>
                <div><strong>${escapeHtml(t("employeeLoans.fields.reference"))}:</strong> <span dir="ltr">${escapeHtml(row.referenceNo || "-")}</span></div>
              </div>
            </div>

            <div class="grid">
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.employeeName"))}</div>
                <div class="value">${escapeHtml(row.employeeName)}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.employeeType"))}</div>
                <div class="value">${escapeHtml(row.employeeType)}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.loanDate"))}</div>
                <div class="value" dir="ltr">${escapeHtml(row.loanDate || "-")}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.loanAmount"))}</div>
                <div class="value" dir="ltr">${escapeHtml(formatAmount(row.loanAmount))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.monthlyInstallment"))}</div>
                <div class="value" dir="ltr">${escapeHtml(formatAmount(row.monthlyInstallment))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.recoveredAmount"))}</div>
                <div class="value" dir="ltr">${escapeHtml(formatAmount(row.recoveredAmount))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.remainingAmount"))}</div>
                <div class="value" dir="ltr">${escapeHtml(formatAmount(row.remainingAmount))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.paymentMethod"))}</div>
                <div class="value">${escapeHtml(paymentMethodLabel(row.paymentMethod))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.referenceNo"))}</div>
                <div class="value" dir="ltr">${escapeHtml(row.referenceNo || "-")}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeLoans.fields.status"))}</div>
                <div class="value"><span class="status">${escapeHtml(statusLabel(row.status))}</span></div>
              </div>
              <div class="field remarks">
                <div class="label">${escapeHtml(t("employeeLoans.fields.remarks"))}</div>
                <div class="value">${escapeHtml(row.remarks || "-")}</div>
              </div>
            </div>

            <div class="signatures">
              <div class="signature">${escapeHtml(t("employeeLoans.print.preparedBy"))}</div>
              <div class="signature">${escapeHtml(t("employeeLoans.print.receivedBy"))}</div>
            </div>
          </div>

          <script>
            window.onload = function () {
              window.print();
            };
            window.onafterprint = function () {
              window.close();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  function handlePrintReceipt(row: EmployeeLoanRow) {
    const presentation: ModulePrintPresentation = {
      documentType: "employee",
      title: printLabel("employeeLoans.print.receiptTitle"),
      documentNo: printValue(row.referenceNo || row.id),
      documentDate: printValue(row.loanDate),
      fields: [
        { label: printLabel("employeeLoans.fields.employee"), value: printValue(row.employeeName) },
        { label: printLabel("employeeLoans.fields.type"), value: printValue(row.employeeType) },
        { label: printLabel("employeeLoans.fields.loanAmount"), value: printValue(formatAmount(row.loanAmount)) },
        { label: printLabel("employeeLoans.fields.monthlyInstallment"), value: printValue(formatAmount(row.monthlyInstallment)) },
        { label: printLabel("employeeLoans.fields.recoveredAmount"), value: printValue(formatAmount(row.recoveredAmount)) },
        { label: printLabel("employeeLoans.fields.remainingAmount"), value: printValue(formatAmount(row.remainingAmount)) },
        { label: printLabel("common.status"), value: printLabel(`employeeLoans.statuses.${row.status.toLowerCase()}`) },
        { label: printLabel("employeeLoans.fields.paymentMethod"), value: printValue(paymentMethodLabel(row.paymentMethod)) },
        { label: printLabel("employeeLoans.fields.referenceNo"), value: printValue(row.referenceNo) },
      ],
      remarks: printValue(row.remarks),
    };
    modulePrint.openPresentation(presentation, () => handlePrintReceiptLegacy(row), addaId);
  }

  function handlePrintReportLegacy() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("employeeLoans.messages.allowReportPopups"));
      return;
    }

    const tableRows =
      reportRows.length > 0
        ? reportRows
            .map(
              (row) => `
                <tr>
                  <td>${escapeHtml(row.employeeName)}</td>
                  <td>${escapeHtml(row.employeeType)}</td>
                  <td>${escapeHtml(row.loanDate || "-")}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.loanAmount))}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.monthlyInstallment))}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.recoveredAmount))}</td>
                  <td class="amount">${escapeHtml(formatAmount(row.remainingAmount))}</td>
                  <td>${escapeHtml(paymentMethodLabel(row.paymentMethod))}</td>
                  <td>${escapeHtml(row.referenceNo || "-")}</td>
                  <td>${escapeHtml(statusLabel(row.status))}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="10" class="empty">${escapeHtml(t("employeeLoans.empty"))}</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
        <head>
          <title>${escapeHtml(t("employeeLoans.print.reportTitle"))}</title>
          <style>
            * { box-sizing: border-box; }
            @page {
              size: A4 landscape;
              margin: 12mm;
            }
            body {
              margin: 0;
              color: #111827;
              background: #ffffff;
              font-family: Arial, sans-serif;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 14px;
              margin-bottom: 18px;
            }
            h1 {
              margin: 0;
              color: #111827;
              font-size: 26px;
              font-weight: 800;
            }
            .subtitle {
              margin-top: 5px;
              color: #111827;
              font-size: 15px;
              font-weight: 700;
            }
            .printed {
              color: #111827;
              font-size: 13px;
              font-weight: 700;
              text-align: end;
              line-height: 1.6;
            }
            .summary {
              display: grid;
              grid-template-columns: repeat(4, 1fr);
              gap: 10px;
              margin-bottom: 18px;
            }
            .card {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
              background: #f9fafb;
            }
            .card-title {
              color: #111827;
              font-size: 11px;
              font-weight: 800;
              text-transform: uppercase;
            }
            .card-value {
              margin-top: 5px;
              color: #111827;
              font-size: 16px;
              font-weight: 900;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 11px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              border: 1px solid #2563eb;
              padding: 8px;
              text-align: start;
              font-weight: 800;
            }
            td {
              border: 1px solid #d1d5db;
              padding: 7px;
              color: #111827;
              vertical-align: top;
            }
            tfoot td {
              background: #f3f4f6;
              color: #111827;
              font-weight: 900;
            }
            .amount {
              text-align: right;
              white-space: nowrap;
            }
            .empty {
              text-align: center;
              font-weight: 800;
              padding: 18px;
            }
          </style>
        </head>
        <body dir="${escapeHtml(dir)}">
          <div class="header">
            <div>
              <h1>${escapeHtml(addaName)}</h1>
              <div class="subtitle">${escapeHtml(t("employeeLoans.print.reportTitle"))}</div>
            </div>
            <div class="printed">
              <div>${escapeHtml(t("employeeLoans.print.printed"))}: <span dir="ltr">${escapeHtml(new Date().toLocaleString())}</span></div>
              <div>${escapeHtml(t("employeeLoans.fields.totalRecords"))}: <span dir="ltr">${reportRows.length}</span></div>
            </div>
          </div>

          <div class="summary">
            <div class="card">
              <div class="card-title">${escapeHtml(t("employeeLoans.fields.loanAmount"))}</div>
              <div class="card-value">${escapeHtml(formatAmount(totalLoanAmount))}</div>
            </div>
            <div class="card">
              <div class="card-title">${escapeHtml(t("employeeLoans.fields.monthlyInstallmentTotal"))}</div>
              <div class="card-value">${escapeHtml(formatAmount(totalMonthlyInstallment))}</div>
            </div>
            <div class="card">
              <div class="card-title">${escapeHtml(t("employeeLoans.fields.recoveredAmount"))}</div>
              <div class="card-value">${escapeHtml(formatAmount(totalRecovered))}</div>
            </div>
            <div class="card">
              <div class="card-title">${escapeHtml(t("employeeLoans.fields.remainingAmount"))}</div>
              <div class="card-value">${escapeHtml(formatAmount(totalRemaining))}</div>
            </div>
          </div>

          <table>
            <thead>
              <tr>
                <th>${escapeHtml(t("employeeLoans.fields.employee"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.type"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.loanDate"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.loanAmount"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.monthlyInstallment"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.recovered"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.remaining"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.paymentMethod"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.reference"))}</th>
                <th>${escapeHtml(t("employeeLoans.fields.status"))}</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="3">${escapeHtml(t("employeeLoans.totals"))}</td>
                <td class="amount">${escapeHtml(formatAmount(totalLoanAmount))}</td>
                <td class="amount">${escapeHtml(formatAmount(totalMonthlyInstallment))}</td>
                <td class="amount">${escapeHtml(formatAmount(totalRecovered))}</td>
                <td class="amount">${escapeHtml(formatAmount(totalRemaining))}</td>
                <td colspan="3"></td>
              </tr>
            </tfoot>
          </table>

          <script>
            window.onload = function () {
              window.print();
            };
            window.onafterprint = function () {
              window.close();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  function handlePrintReport() {
    const presentation: ModulePrintPresentation = {
      documentType: "employee",
      title: printLabel("employeeLoans.print.reportTitle"),
      fields: [{ label: printLabel("employeeLoans.cards.totalLoans"), value: printValue(reportRows.length) }],
      tables: [{
        columns: [printLabel("employeeLoans.fields.loanDate"), printLabel("employeeLoans.fields.employee"), printLabel("employeeLoans.fields.type"), printLabel("employeeLoans.fields.loanAmount"), printLabel("employeeLoans.fields.monthlyInstallment"), printLabel("employeeLoans.fields.recoveredAmount"), printLabel("employeeLoans.fields.remainingAmount"), printLabel("common.status"), printLabel("employeeLoans.fields.paymentMethod"), printLabel("employeeLoans.fields.referenceNo"), printLabel("common.remarks")],
        rows: reportRows.map((row) => [printValue(row.loanDate), printValue(row.employeeName), printValue(row.employeeType), printValue(formatAmount(row.loanAmount)), printValue(formatAmount(row.monthlyInstallment)), printValue(formatAmount(row.recoveredAmount)), printValue(formatAmount(row.remainingAmount)), printLabel(`employeeLoans.statuses.${row.status.toLowerCase()}`), printValue(paymentMethodLabel(row.paymentMethod)), printValue(row.referenceNo), printValue(row.remarks)]),
      }],
      totals: [
        { label: printLabel("employeeLoans.fields.loanAmount"), value: printValue(formatAmount(totalLoanAmount)) },
        { label: printLabel("employeeLoans.fields.monthlyInstallment"), value: printValue(formatAmount(totalMonthlyInstallment)) },
        { label: printLabel("employeeLoans.fields.recoveredAmount"), value: printValue(formatAmount(totalRecovered)) },
        { label: printLabel("employeeLoans.fields.remainingAmount"), value: printValue(formatAmount(totalRemaining)) },
      ],
    };
    modulePrint.openPresentation(presentation, handlePrintReportLegacy, addaId);
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("employeeLoans.recordsTitle")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("employeeLoans.recordsDescription")}
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintReport}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-blue-700"
        >
          {t("employeeLoans.actions.printReport")}
        </button>
      </div>


      <div className="mb-5 grid grid-cols-1 gap-3 rounded-xl border border-gray-300 bg-white p-4 shadow-sm sm:grid-cols-3">
        <VoiceTypingField fieldLabel={t("employeeLoans.placeholders.search")} mode="text"><input
          type="search"
          aria-label={t("employeeLoans.placeholders.search")}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t("employeeLoans.placeholders.search")}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
        /></VoiceTypingField>
        <select
          aria-label={t("employeeLoans.fields.status")}
          value={statusFilter}
          onChange={(event) =>
            setStatusFilter(event.target.value as EmployeeLoanStatusFilter)
          }
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="All">{t("employeeLoans.filters.allStatuses")}</option>
          <option value="Active">{statusLabel("Active")}</option>
          <option value="Completed">{statusLabel("Completed")}</option>
        </select>
        <button type="button" onClick={onResetFilters} className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 hover:bg-gray-300">
          {t("common.actions.reset")}
        </button>
      </div>


      {errorMessage && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {isLoading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center text-base font-bold text-gray-900">
          {t("employeeLoans.loading")}
        </div>
      ) : reportRows.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center text-base font-bold text-gray-900">
          {t("employeeLoans.empty")}
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1500px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("employeeLoans.fields.employee")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLoans.fields.employeeType")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLoans.fields.loanDate")}</th>
                <th className="p-3 text-end font-bold">{t("employeeLoans.fields.loanAmount")}</th>
                <th className="p-3 text-right font-bold">
                  {t("employeeLoans.fields.monthlyInstallment")}
                </th>
                <th className="p-3 text-end font-bold">{t("employeeLoans.fields.recoveredAmount")}</th>
                <th className="p-3 text-end font-bold">{t("employeeLoans.fields.remainingAmount")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLoans.fields.paymentMethod")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLoans.fields.referenceNo")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLoans.fields.remarks")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLoans.fields.status")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr key={row.id} className="hover:bg-blue-50">
                  <td className="p-3 font-bold text-gray-900">
                    {row.employeeName}
                  </td>
                  <td dir="ltr" className="p-3 font-medium text-gray-900">
                    {row.employeeType}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.loanDate || "-"}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-gray-900">
                    {formatAmount(row.loanAmount)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-gray-900">
                    {formatAmount(row.monthlyInstallment)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-green-700">
                    {formatAmount(row.recoveredAmount)}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-red-700">
                    {formatAmount(row.remainingAmount)}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {paymentMethodLabel(row.paymentMethod)}
                  </td>
                  <td dir="ltr" className="p-3 font-medium text-gray-900">
                    {row.referenceNo || "-"}
                  </td>
                  <td className="max-w-[260px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">
                      {row.remarks || "-"}
                    </div>
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full px-3 py-1 text-xs font-extrabold ${getStatusBadgeClass(
                        row.status
                      )}`}
                    >
                      {statusLabel(row.status)}
                    </span>
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        aria-label={`${t("common.actions.details")}: ${row.employeeName}`}
                        onClick={() => setViewingRow(row)}
                        className="rounded-lg bg-gray-700 px-3 py-2 text-xs font-bold text-white hover:bg-gray-800"
                      >
                        {t("common.actions.details")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("common.actions.edit")}: ${row.employeeName}`}
                        onClick={() => onEdit(row)}
                        className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-blue-700"
                      >
                        {t("common.edit")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("common.actions.delete")}: ${row.employeeName}`}
                        onClick={() => onDelete(row)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        {t("common.delete")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("employeeLoans.actions.printReceipt")}: ${row.employeeName}`}
                        onClick={() => handlePrintReceipt(row)}
                        className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white transition hover:bg-black"
                      >
                        {t("employeeLoans.actions.printReceipt")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td
                  colSpan={3}
                  className="p-3 text-end text-sm font-extrabold text-gray-900"
                >
                  {t("employeeLoans.totals")}
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-gray-900">
                  {formatAmount(totalLoanAmount)}
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-gray-900">
                  {formatAmount(totalMonthlyInstallment)}
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-green-700">
                  {formatAmount(totalRecovered)}
                </td>
                <td className="p-3 text-right text-sm font-extrabold text-red-700">
                  {formatAmount(totalRemaining)}
                </td>
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
          title={t("employeeLoans.detailsTitle")}
          description={viewingRow.employeeName}
          onClose={() => setViewingRow(null)}
          details={[
            { label: t("employeeLoans.fields.employee"), value: viewingRow.employeeName },
            { label: t("employeeLoans.fields.employeeType"), value: viewingRow.employeeType },
            { label: t("employeeLoans.fields.loanDate"), value: viewingRow.loanDate, technical: true },
            { label: t("employeeLoans.fields.loanAmount"), value: formatAmount(viewingRow.loanAmount), technical: true },
            { label: t("employeeLoans.fields.monthlyInstallment"), value: formatAmount(viewingRow.monthlyInstallment), technical: true },
            { label: t("employeeLoans.fields.recoveredAmount"), value: formatAmount(viewingRow.recoveredAmount), technical: true },
            { label: t("employeeLoans.fields.remainingAmount"), value: formatAmount(viewingRow.remainingAmount), technical: true },
            { label: t("employeeLoans.fields.paymentMethod"), value: paymentMethodLabel(viewingRow.paymentMethod) },
            { label: t("employeeLoans.fields.referenceNo"), value: viewingRow.referenceNo, technical: true },
            { label: t("employeeLoans.fields.remarks"), value: viewingRow.remarks },
            { label: t("employeeLoans.fields.status"), value: statusLabel(viewingRow.status) },
          ]}
        />
      )}
      {modulePrint.dialog}
    </div>
  );
}

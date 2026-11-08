"use client";

import { type Dispatch, type SetStateAction, useState } from "react";
import EmployeeAccountingDetails from "./EmployeeAccountingDetails";
import {
  type EmployeeLedgerFilterValues,
  type EmployeeLedgerTransactionRow,
  formatAmount,
} from "./EmployeeLedger";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { bilingual, printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";

type Props = {
  addaId: string | null;
  rows: EmployeeLedgerTransactionRow[];
  reportRows: EmployeeLedgerTransactionRow[];
  isLoading: boolean;
  errorMessage: string;
  filters: EmployeeLedgerFilterValues;
  currentPage: number;
  totalPages: number;
  setPage: Dispatch<SetStateAction<number>>;
};

function getStatusClass(balance: number) {
  if (balance > 0) return "bg-red-100 text-red-700";
  if (balance < 0) return "bg-purple-100 text-purple-700";
  return "bg-blue-100 text-blue-700";
}

function getBalanceTextClass(balance: number) {
  if (balance > 0) return "text-red-700";
  if (balance < 0) return "text-purple-700";
  return "text-blue-700";
}

function sortRowsByEmployeeLedgerOrder(
  rows: EmployeeLedgerTransactionRow[]
): EmployeeLedgerTransactionRow[] {
  return [...rows].sort((first, second) => {
    const dateCompare = first.transactionDate.localeCompare(
      second.transactionDate
    );

    if (dateCompare !== 0) return dateCompare;

    const createdAtCompare = first.createdAt.localeCompare(second.createdAt);

    if (createdAtCompare !== 0) return createdAtCompare;

    return first.id - second.id;
  });
}

function getLatestEmployeeBalances(rows: EmployeeLedgerTransactionRow[]) {
  const latestBalanceByEmployee = new Map<string, number>();
  const sortedRows = [...rows].sort((first, second) => {
    const employeeCompare = first.employeeId.localeCompare(second.employeeId);

    if (employeeCompare !== 0) return employeeCompare;

    const dateCompare = first.transactionDate.localeCompare(
      second.transactionDate
    );

    if (dateCompare !== 0) return dateCompare;

    const createdAtCompare = first.createdAt.localeCompare(second.createdAt);

    if (createdAtCompare !== 0) return createdAtCompare;

    return first.id - second.id;
  });

  sortedRows.forEach((row) => {
    latestBalanceByEmployee.set(row.employeeId, row.runningBalance);
  });

  let companyPayable = 0;
  let employeeReceivable = 0;
  let netClosingBalance = 0;

  latestBalanceByEmployee.forEach((balance) => {
    netClosingBalance += balance;

    if (balance > 0) {
      companyPayable += balance;
    }

    if (balance < 0) {
      employeeReceivable += Math.abs(balance);
    }
  });

  return {
    companyPayable,
    employeeReceivable,
    netClosingBalance,
  };
}

export default function EmployeeLedgerTable({
  addaId,
  rows,
  reportRows,
  isLoading,
  errorMessage,
  filters,
  currentPage,
  totalPages,
  setPage,
}: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("employee", addaId, language === "ur" ? "ur" : "en");
  const [viewingRow, setViewingRow] =
    useState<EmployeeLedgerTransactionRow | null>(null);
  const getBalanceStatus = (balance: number) => {
    if (balance > 0) return t("employeeLedger.statuses.payable");
    if (balance < 0) return t("employeeLedger.statuses.receivable");
    return t("employeeLedger.statuses.settled");
  };
  const transactionTypeLabel = (type: string) => {
    const keyByType: Record<string, string> = {
      "Salary Generated": "salaryGenerated",
      "Salary Paid": "salaryPaid",
      "Employee Loan": "employeeLoan",
      "Loan Recovery": "loanRecovery",
      "Advance Salary": "advanceSalary",
      "Advance Recovery": "advanceRecovery",
      "Adjustment Debit": "adjustmentDebit",
      "Adjustment Credit": "adjustmentCredit",
    };
    const key = keyByType[type];
    return key ? t(`employeeLedger.transactionTypes.${key}`) : type;
  };
  const totalDebit = reportRows.reduce((total, row) => total + row.debit, 0);
  const totalCredit = reportRows.reduce((total, row) => total + row.credit, 0);
  const latestBalances = getLatestEmployeeBalances(reportRows);
  const netClosingBalance = latestBalances.netClosingBalance;

  function getPrintableRows(targetRows: EmployeeLedgerTransactionRow[]) {
    return targetRows
      .map(
        (row) => `
          <tr>
            <td dir="ltr">${escapeHtml(row.transactionDate)}</td>
            <td>${escapeHtml(row.employeeName)}</td>
            <td>${escapeHtml(row.employeeType)}</td>
            <td>${escapeHtml(transactionTypeLabel(row.transactionType))}</td>
            <td>${escapeHtml(row.description || "-")}</td>
            <td>${escapeHtml(row.paymentMethod || "-")}</td>
            <td dir="ltr">${escapeHtml(row.referenceNo || "-")}</td>
            <td dir="ltr" class="amount debit">${escapeHtml(formatAmount(row.debit))}</td>
            <td dir="ltr" class="amount credit">${escapeHtml(formatAmount(row.credit))}</td>
            <td dir="ltr" class="amount">${escapeHtml(formatAmount(row.runningBalance))}</td>
            <td>${escapeHtml(getBalanceStatus(row.runningBalance))}</td>
          </tr>
        `
      )
      .join("");
  }

  function openPrintWindow(title: string, html: string) {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert(t("employeeLedger.messages.allowPopups"));
      return;
    }

    const content = html.includes(PRINT_ADDA_NAME_TOKEN) ? html : `<h1>${PRINT_ADDA_NAME_TOKEN}</h1>${html}`;
    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
        <head>
          <title>${escapeHtml(title)}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 12mm; }
            body { margin: 0; color: #111827; font-family: Arial, sans-serif; }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 24px;
              border-bottom: 3px solid #2563eb;
              padding-bottom: 14px;
              margin-bottom: 18px;
            }
            h1 { margin: 0; font-size: 26px; font-weight: 800; }
            .subtitle { margin-top: 5px; font-size: 15px; font-weight: 700; }
            .meta { text-align: end; font-size: 13px; font-weight: 700; line-height: 1.6; }
            .summary {
              display: grid;
              grid-template-columns: repeat(var(--columns, 3), 1fr);
              gap: 10px;
              margin-bottom: 18px;
            }
            .card {
              border: 1px solid #d1d5db;
              border-radius: 8px;
              padding: 10px;
              background: #f9fafb;
            }
            .label { font-size: 11px; font-weight: 800; text-transform: uppercase; }
            .value { margin-top: 5px; font-size: 16px; font-weight: 900; }
            table { width: 100%; border-collapse: collapse; font-size: 10px; }
            th { background: #2563eb; color: #fff; padding: 7px; border: 1px solid #2563eb; text-align: start; }
            td { padding: 6px; border: 1px solid #d1d5db; color: #111827; vertical-align: top; }
            tfoot td { background: #f3f4f6; font-weight: 900; }
            .amount { direction: ltr; text-align: right; white-space: nowrap; }
            .debit { color: #b91c1c; font-weight: 800; }
            .credit { color: #15803d; font-weight: 800; }
            .signatures {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 48px;
              margin-top: 52px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 10px;
              text-align: center;
              font-size: 14px;
              font-weight: 700;
            }
          </style>
        </head>
        <body dir="${escapeHtml(dir)}">
          ${content}
          <script>
            window.onload = function () { window.print(); };
            window.onafterprint = function () { window.close(); };
          </script>
        </body>
      </html>
    `, addaId, language === "ur" ? "ur" : "en");
  }

  function handlePrintEntry(row: EmployeeLedgerTransactionRow) {
    const status = getBalanceStatus(row.runningBalance);

    modulePrint.openPresentation({
      documentType: "employee",
      title: printLabel("employeeLedger.print.entryTitle"),
      documentNo: printValue(row.referenceNo),
      documentDate: printValue(row.transactionDate),
      fields: [
        { label: printLabel("employeeLedger.fields.employee"), value: printValue(row.employeeName) },
        { label: printLabel("employeeLedger.fields.type"), value: printValue(row.employeeType) },
        { label: printLabel("employeeLedger.fields.transactionType"), value: printValue(transactionTypeLabel(row.transactionType)) },
        { label: printLabel("employeeLedger.fields.description"), value: printValue(row.description) },
        { label: printLabel("employeeLedger.fields.paymentMethod"), value: printValue(row.paymentMethod) },
        { label: printLabel("employeeLedger.fields.status"), value: printValue(status) },
      ],
      totals: [
        { label: printLabel("employeeLedger.fields.debit"), value: printValue(formatAmount(row.debit)) },
        { label: printLabel("employeeLedger.fields.credit"), value: printValue(formatAmount(row.credit)) },
        { label: printLabel("employeeLedger.fields.runningBalance"), value: printValue(formatAmount(row.runningBalance)) },
      ],
      remarks: printValue(row.remarks),
    }, () => openPrintWindow(`${t("employeeLedger.print.entryTitle")} - ${row.employeeName}`, `<table><tbody><tr><th>${escapeHtml(t("employeeLedger.fields.employee"))}</th><td>${escapeHtml(row.employeeName)}</td></tr><tr><th>${escapeHtml(t("employeeLedger.fields.transactionType"))}</th><td>${escapeHtml(transactionTypeLabel(row.transactionType))}</td></tr><tr><th>${escapeHtml(t("employeeLedger.fields.amount"))}</th><td>${escapeHtml(formatAmount(row.amount))}</td></tr><tr><th>${escapeHtml(t("employeeLedger.fields.debit"))}</th><td>${escapeHtml(formatAmount(row.debit))}</td></tr><tr><th>${escapeHtml(t("employeeLedger.fields.credit"))}</th><td>${escapeHtml(formatAmount(row.credit))}</td></tr><tr><th>${escapeHtml(t("employeeLedger.fields.runningBalance"))}</th><td>${escapeHtml(formatAmount(row.runningBalance))}</td></tr></tbody></table>`), addaId);
    return;

    openPrintWindow(
      `${t("employeeLedger.print.entryTitle")} - ${row.employeeName}`,
      `
        <div class="header">
          <div>
            <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
            <div class="subtitle">${escapeHtml(t("employeeLedger.print.entryTitle"))}</div>
          </div>
          <div class="meta">
            <div>${escapeHtml(t("employeeLedger.fields.date"))}: <span dir="ltr">${escapeHtml(row.transactionDate)}</span></div>
            <div>${escapeHtml(t("employeeLedger.fields.employee"))}: ${escapeHtml(row.employeeName)}</div>
          </div>
        </div>

        <div class="summary" style="--columns: 3;">
          <div class="card">
            <div class="label">${escapeHtml(t("employeeLedger.fields.debit"))}</div>
            <div class="value" dir="ltr">${escapeHtml(formatAmount(row.debit))}</div>
          </div>
          <div class="card">
            <div class="label">${escapeHtml(t("employeeLedger.fields.credit"))}</div>
            <div class="value" dir="ltr">${escapeHtml(formatAmount(row.credit))}</div>
          </div>
          <div class="card">
            <div class="label">${escapeHtml(t("employeeLedger.fields.runningBalance"))}</div>
            <div class="value" dir="ltr">${escapeHtml(formatAmount(row.runningBalance))}</div>
          </div>
        </div>

        <table>
          <tbody>
            <tr><th>${escapeHtml(t("employeeLedger.fields.employee"))}</th><td>${escapeHtml(row.employeeName)}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.employeeType"))}</th><td>${escapeHtml(row.employeeType)}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.transactionDate"))}</th><td dir="ltr">${escapeHtml(row.transactionDate)}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.transactionType"))}</th><td>${escapeHtml(transactionTypeLabel(row.transactionType))}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.description"))}</th><td>${escapeHtml(row.description || "-")}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.paymentMethod"))}</th><td>${escapeHtml(row.paymentMethod || "-")}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.reference"))}</th><td dir="ltr">${escapeHtml(row.referenceNo || "-")}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.status"))}</th><td>${escapeHtml(status)}</td></tr>
            <tr><th>${escapeHtml(t("employeeLedger.fields.remarks"))}</th><td>${escapeHtml(row.remarks || "-")}</td></tr>
          </tbody>
        </table>

        <div class="signatures">
          <div class="signature">${escapeHtml(t("employeeLedger.print.preparedBy"))}</div>
          <div class="signature">${escapeHtml(t("employeeLedger.print.employeeSignature"))}</div>
        </div>
      `
    );
  }

  function handlePrintEmployeeLedger(row: EmployeeLedgerTransactionRow) {
    const employeeRows = sortRowsByEmployeeLedgerOrder(
      reportRows.filter((item) => item.employeeId === row.employeeId)
    );
    const firstEmployeeRow = employeeRows[0] ?? null;
    const lastEmployeeRow = employeeRows[employeeRows.length - 1] ?? null;
    const openingBalance = firstEmployeeRow
      ? firstEmployeeRow.runningBalance -
        firstEmployeeRow.debit +
        firstEmployeeRow.credit
      : 0;
    const periodDebit = employeeRows.reduce(
      (total, item) => total + item.debit,
      0
    );
    const periodCredit = employeeRows.reduce(
      (total, item) => total + item.credit,
      0
    );
    const closingBalance = lastEmployeeRow?.runningBalance ?? 0;

    const presentation: ModulePrintPresentation = {
      documentType: "employee",
      title: printLabel("employeeLedger.title"),
      subtitle: bilingual(row.employeeName, row.employeeName),
      fields: [
        { label: printLabel("employeeLedger.fields.type"), value: printValue(row.employeeType) },
        { label: printLabel("employeeLedger.print.dateRange"), value: printValue(`${filters.fromDate || t("employeeLedger.filters.all")} — ${filters.toDate || t("employeeLedger.filters.all")}`) },
      ],
      totals: [
        { label: printLabel("employeeLedger.fields.openingBalance"), value: printValue(formatAmount(openingBalance)) },
        { label: printLabel("employeeLedger.fields.periodDebit"), value: printValue(formatAmount(periodDebit)) },
        { label: printLabel("employeeLedger.fields.periodCredit"), value: printValue(formatAmount(periodCredit)) },
        { label: printLabel("employeeLedger.fields.closingBalance"), value: printValue(formatAmount(closingBalance)) },
      ],
      tables: [{
        columns: [printLabel("employeeLedger.fields.date"), printLabel("employeeLedger.fields.employee"), printLabel("employeeLedger.fields.type"), printLabel("employeeLedger.fields.transactionType"), printLabel("employeeLedger.fields.description"), printLabel("employeeLedger.fields.paymentMethod"), printLabel("employeeLedger.fields.reference"), printLabel("employeeLedger.fields.debit"), printLabel("employeeLedger.fields.credit"), printLabel("employeeLedger.fields.runningBalance"), printLabel("employeeLedger.fields.status")],
        rows: employeeRows.map((item) => [printValue(item.transactionDate), printValue(item.employeeName), printValue(item.employeeType), printValue(transactionTypeLabel(item.transactionType)), printValue(item.description), printValue(item.paymentMethod), printValue(item.referenceNo), printValue(formatAmount(item.debit)), printValue(formatAmount(item.credit)), printValue(formatAmount(item.runningBalance)), printValue(getBalanceStatus(item.runningBalance))]),
      }],
    };
    modulePrint.openPresentation(presentation, () => openPrintWindow(`${t("employeeLedger.title")} - ${row.employeeName}`, `<table><tbody>${getPrintableRows(employeeRows)}</tbody></table>`), addaId);
    return;

    openPrintWindow(
      `${t("employeeLedger.title")} - ${row.employeeName}`,
      `
        <div class="header">
          <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
            <div class="subtitle">${escapeHtml(t("employeeLedger.title"))}</div>
          </div>
          <div class="meta">
            <div>${escapeHtml(t("employeeLedger.fields.employee"))}: ${escapeHtml(row.employeeName)}</div>
            <div>${escapeHtml(t("employeeLedger.fields.type"))}: ${escapeHtml(row.employeeType)}</div>
            <div>${escapeHtml(t("employeeLedger.print.dateRange"))}: <span dir="ltr">${escapeHtml(filters.fromDate || t("employeeLedger.filters.all"))} ${escapeHtml(t("employeeLedger.print.to"))} ${escapeHtml(filters.toDate || t("employeeLedger.filters.all"))}</span></div>
          </div>
        </div>

        <div class="summary" style="--columns: 4;">
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.fields.openingBalance"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(openingBalance))}</div></div>
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.fields.periodDebit"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(periodDebit))}</div></div>
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.fields.periodCredit"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(periodCredit))}</div></div>
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.fields.closingBalance"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(closingBalance))}</div></div>
        </div>

        <table>
          <thead>
            <tr>
              <th>${escapeHtml(t("employeeLedger.fields.date"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.employee"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.type"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.transactionType"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.description"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.paymentMethod"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.reference"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.debit"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.credit"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.runningBalance"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.status"))}</th>
            </tr>
          </thead>
          <tbody>${getPrintableRows(employeeRows)}</tbody>
          <tfoot>
            <tr>
              <td colspan="7">${escapeHtml(t("employeeLedger.totals"))}</td>
              <td class="amount debit">${escapeHtml(formatAmount(periodDebit))}</td>
              <td class="amount credit">${escapeHtml(formatAmount(periodCredit))}</td>
              <td class="amount">${escapeHtml(formatAmount(closingBalance))}</td>
              <td>${escapeHtml(getBalanceStatus(closingBalance))}</td>
            </tr>
          </tfoot>
        </table>
      `
    );
  }

  function handlePrintFullReport() {
    const presentation: ModulePrintPresentation = {
      documentType: "employee",
      title: printLabel("employeeLedger.print.reportTitle"),
      fields: [
        { label: printLabel("employeeLedger.print.dateRange"), value: printValue(`${filters.fromDate || t("employeeLedger.filters.all")} — ${filters.toDate || t("employeeLedger.filters.all")}`) },
        { label: printLabel("employeeLedger.fields.totalRecords"), value: printValue(reportRows.length) },
      ],
      totals: [
        { label: printLabel("employeeLedger.cards.totalDebit"), value: printValue(formatAmount(totalDebit)) },
        { label: printLabel("employeeLedger.cards.totalCredit"), value: printValue(formatAmount(totalCredit)) },
        { label: printLabel("employeeLedger.cards.companyPayable"), value: printValue(formatAmount(latestBalances.companyPayable)) },
        { label: printLabel("employeeLedger.cards.employeeReceivable"), value: printValue(formatAmount(latestBalances.employeeReceivable)) },
        { label: printLabel("employeeLedger.fields.netClosingBalance"), value: printValue(formatAmount(netClosingBalance)) },
      ],
      tables: [{
        columns: [printLabel("employeeLedger.fields.date"), printLabel("employeeLedger.fields.employee"), printLabel("employeeLedger.fields.type"), printLabel("employeeLedger.fields.transactionType"), printLabel("employeeLedger.fields.description"), printLabel("employeeLedger.fields.paymentMethod"), printLabel("employeeLedger.fields.reference"), printLabel("employeeLedger.fields.debit"), printLabel("employeeLedger.fields.credit"), printLabel("employeeLedger.fields.runningBalance"), printLabel("employeeLedger.fields.status")],
        rows: reportRows.map((item) => [printValue(item.transactionDate), printValue(item.employeeName), printValue(item.employeeType), printValue(transactionTypeLabel(item.transactionType)), printValue(item.description), printValue(item.paymentMethod), printValue(item.referenceNo), printValue(formatAmount(item.debit)), printValue(formatAmount(item.credit)), printValue(formatAmount(item.runningBalance)), printValue(getBalanceStatus(item.runningBalance))]),
      }],
    };
    modulePrint.openPresentation(presentation, () => openPrintWindow(t("employeeLedger.print.reportTitle"), `<table><tbody>${getPrintableRows(reportRows)}</tbody></table>`), addaId);
    return;
    openPrintWindow(
      t("employeeLedger.print.reportTitle"),
      `
        <div class="header">
          <div>
              <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
            <div class="subtitle">${escapeHtml(t("employeeLedger.print.reportTitle"))}</div>
          </div>
          <div class="meta">
            <div>${escapeHtml(t("employeeLedger.print.printed"))}: <span dir="ltr">${escapeHtml(new Date().toLocaleString())}</span></div>
            <div>${escapeHtml(t("employeeLedger.print.dateRange"))}: <span dir="ltr">${escapeHtml(filters.fromDate || t("employeeLedger.filters.all"))} ${escapeHtml(t("employeeLedger.print.to"))} ${escapeHtml(filters.toDate || t("employeeLedger.filters.all"))}</span></div>
            <div>${escapeHtml(t("employeeLedger.fields.totalRecords"))}: <span dir="ltr">${reportRows.length}</span></div>
          </div>
        </div>

        <div class="summary" style="--columns: 5;">
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.cards.totalDebit"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(totalDebit))}</div></div>
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.cards.totalCredit"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(totalCredit))}</div></div>
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.cards.companyPayable"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(latestBalances.companyPayable))}</div></div>
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.cards.employeeReceivable"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(latestBalances.employeeReceivable))}</div></div>
          <div class="card"><div class="label">${escapeHtml(t("employeeLedger.fields.netClosingBalance"))}</div><div class="value" dir="ltr">${escapeHtml(formatAmount(netClosingBalance))}</div></div>
        </div>

        <table>
          <thead>
            <tr>
              <th>${escapeHtml(t("employeeLedger.fields.date"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.employee"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.type"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.transactionType"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.description"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.paymentMethod"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.reference"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.debit"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.credit"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.runningBalance"))}</th>
              <th>${escapeHtml(t("employeeLedger.fields.status"))}</th>
            </tr>
          </thead>
          <tbody>${getPrintableRows(reportRows)}</tbody>
          <tfoot>
            <tr>
              <td colspan="7">${escapeHtml(t("employeeLedger.totals"))}</td>
              <td class="amount debit">${escapeHtml(formatAmount(totalDebit))}</td>
              <td class="amount credit">${escapeHtml(formatAmount(totalCredit))}</td>
              <td class="amount">${escapeHtml(formatAmount(netClosingBalance))}</td>
              <td>${escapeHtml(getBalanceStatus(netClosingBalance))}</td>
            </tr>
          </tfoot>
        </table>
      `
    );
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("employeeLedger.recordsTitle")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("employeeLedger.recordsDescription")}
          </p>
        </div>

        <button
          type="button"
          onClick={handlePrintFullReport}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white hover:bg-blue-700"
        >
          {t("employeeLedger.actions.printFullReport")}
        </button>
      </div>

      {errorMessage && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {isLoading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          {t("employeeLedger.loading")}
        </div>
      ) : reportRows.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center font-bold text-gray-900">
          {t("employeeLedger.empty")}
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1700px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.date")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.employee")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.type")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.transactionType")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.description")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.paymentMethod")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.reference")}</th>
                <th className="p-3 text-end font-bold">{t("employeeLedger.fields.debit")}</th>
                <th className="p-3 text-end font-bold">{t("employeeLedger.fields.credit")}</th>
                <th className="p-3 text-end font-bold">{t("employeeLedger.fields.runningBalance")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.status")}</th>
                <th className="p-3 text-start font-bold">{t("employeeLedger.fields.remarks")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr key={row.id} className="hover:bg-blue-50">
                  <td dir="ltr" className="p-3 font-medium text-gray-900">
                    {row.transactionDate || "-"}
                  </td>
                  <td className="p-3 font-bold text-gray-900">
                    {row.employeeName}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.employeeType}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {transactionTypeLabel(row.transactionType)}
                  </td>
                  <td className="max-w-[280px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">
                      {row.description || "-"}
                    </div>
                  </td>
                  <td dir="ltr" className="p-3 font-medium text-gray-900">
                    {row.paymentMethod || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {row.referenceNo || "-"}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-red-700">
                    {row.debit > 0 ? formatAmount(row.debit) : "-"}
                  </td>
                  <td dir="ltr" className="p-3 text-end font-bold text-green-700">
                    {row.credit > 0 ? formatAmount(row.credit) : "-"}
                  </td>
                  <td
                    dir="ltr"
                    className={`p-3 text-end font-extrabold ${getBalanceTextClass(
                      row.runningBalance
                    )}`}
                  >
                    {formatAmount(row.runningBalance)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-extrabold ${getStatusClass(
                        row.runningBalance
                      )}`}
                    >
                      {getBalanceStatus(row.runningBalance)}
                    </span>
                  </td>
                  <td className="max-w-[240px] p-3 font-medium text-gray-900">
                    <div className="whitespace-normal break-words">
                      {row.remarks || "-"}
                    </div>
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
                        aria-label={`${t("employeeLedger.actions.printEntry")}: ${row.employeeName}`}
                        onClick={() => handlePrintEntry(row)}
                        className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white hover:bg-black"
                      >
                        {t("employeeLedger.actions.printEntry")}
                      </button>
                      <button
                        type="button"
                        aria-label={`${t("employeeLedger.actions.printEmployeeLedger")}: ${row.employeeName}`}
                        onClick={() => handlePrintEmployeeLedger(row)}
                        className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white hover:bg-blue-700"
                      >
                        {t("employeeLedger.actions.printEmployeeLedger")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td
                  colSpan={7}
                  className="p-3 text-end font-extrabold text-gray-900"
                >
                  {t("employeeLedger.totals")}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-red-700">
                  {formatAmount(totalDebit)}
                </td>
                <td dir="ltr" className="p-3 text-end font-extrabold text-green-700">
                  {formatAmount(totalCredit)}
                </td>
                <td
                  dir="ltr"
                  className={`p-3 text-end font-extrabold ${getBalanceTextClass(
                    netClosingBalance
                  )}`}
                >
                  {formatAmount(netClosingBalance)}
                </td>
                <td className="p-3">
                  <span
                    className={`rounded-full px-3 py-1 text-xs font-extrabold ${getStatusClass(
                      netClosingBalance
                    )}`}
                  >
                    {getBalanceStatus(netClosingBalance)}
                  </span>
                </td>
                <td colSpan={2} className="p-3" />
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
          title={t("employeeLedger.detailsTitle")}
          description={viewingRow.employeeName}
          onClose={() => setViewingRow(null)}
          details={[
            { label: t("employeeLedger.fields.date"), value: viewingRow.transactionDate, technical: true },
            { label: t("employeeLedger.fields.employee"), value: viewingRow.employeeName },
            { label: t("employeeLedger.fields.type"), value: viewingRow.employeeType },
            { label: t("employeeLedger.fields.transactionType"), value: transactionTypeLabel(viewingRow.transactionType) },
            { label: t("employeeLedger.fields.description"), value: viewingRow.description },
            { label: t("employeeLedger.fields.amount"), value: formatAmount(viewingRow.amount), technical: true },
            { label: t("employeeLedger.fields.debit"), value: formatAmount(viewingRow.debit), technical: true },
            { label: t("employeeLedger.fields.credit"), value: formatAmount(viewingRow.credit), technical: true },
            { label: t("employeeLedger.fields.runningBalance"), value: formatAmount(viewingRow.runningBalance), technical: true },
            { label: t("employeeLedger.fields.paymentMethod"), value: viewingRow.paymentMethod },
            { label: t("employeeLedger.fields.reference"), value: viewingRow.referenceNo, technical: true },
            { label: t("employeeLedger.fields.remarks"), value: viewingRow.remarks },
          ]}
        />
      )}
      {modulePrint.dialog}
    </div>
  );
}

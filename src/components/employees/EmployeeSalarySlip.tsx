"use client";

import { useEffect } from "react";
import { type EmployeeSalaryRow, formatAmount } from "./EmployeeSalary";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";

type Props = {
  row: EmployeeSalaryRow;
  addaId: string | null;
  onClose: () => void;
};

export default function EmployeeSalarySlip({ row, addaId, onClose }: Props) {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("employee", addaId, language === "ur" ? "ur" : "en");
  const statusLabel = t(
    `common.paymentStatus.${row.paymentStatus.toLowerCase()}`
  );
  const paymentMethodKeys: Record<string, string> = {
    Cash: "cash",
    Bank: "bank",
    Cheque: "cheque",
    "Online Transfer": "onlineTransfer",
    Account: "account",
  };
  const paymentMethodKey = paymentMethodKeys[row.paymentMethod];
  const paymentMethodLabel = paymentMethodKey
    ? t(`employeeSalary.paymentMethods.${paymentMethodKey}`)
    : row.paymentMethod;

  function printLegacy() {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert(t("employeeSalary.messages.allowSlipPopups"));
      onClose();
      return;
    }

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${language}" dir="${dir}">
        <head>
          <title>${escapeHtml(t("employeeSalary.print.slipTitle"))} - ${escapeHtml(row.employeeName)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              background: #ffffff;
              color: #111827;
              font-family: Arial, sans-serif;
              direction: ${dir};
              text-align: start;
            }
            .slip {
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
              font-size: 28px;
              font-weight: 800;
              color: #111827;
            }
            .subtitle {
              margin-top: 6px;
              color: #111827;
              font-size: 15px;
              font-weight: 700;
            }
            .meta {
              text-align: end;
              color: #111827;
              font-size: 14px;
              font-weight: 700;
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
              font-weight: 800;
              text-transform: uppercase;
            }
            .value {
              margin-top: 6px;
              color: #111827;
              font-size: 16px;
              font-weight: 800;
            }
            .remarks {
              grid-column: 1 / -1;
            }
            .status {
              display: inline-block;
              border-radius: 999px;
              padding: 5px 12px;
              font-size: 13px;
              font-weight: 800;
              ${
                row.paymentStatus === "Paid"
                  ? "background:#dcfce7;color:#15803d;"
                  : row.paymentStatus === "Partial"
                    ? "background:#ffedd5;color:#c2410c;"
                    : "background:#fee2e2;color:#b91c1c;"
              }
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 48px;
              margin-top: 64px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 10px;
              text-align: center;
              font-size: 14px;
              font-weight: 700;
              color: #111827;
            }
            .technical { direction: ltr; unicode-bidi: isolate; }
            @media print {
              body { padding: 0; }
              .slip { border: none; border-radius: 0; }
            }
          </style>
        </head>
        <body>
          <div class="slip">
            <div class="header">
              <div>
                <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
                <div class="subtitle">${escapeHtml(t("employeeSalary.print.slipTitle"))}</div>
              </div>
              <div class="meta">
                <div><strong>${escapeHtml(t("employeeSalary.fields.salaryMonth"))}:</strong> <span class="technical">${escapeHtml(row.salaryMonth)}</span></div>
                <div><strong>${escapeHtml(t("employeeSalary.fields.referenceNo"))}:</strong> <span class="technical">${escapeHtml(row.referenceNo || "-")}</span></div>
              </div>
            </div>

            <div class="grid">
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.employee"))}</div>
                <div class="value">${escapeHtml(row.employeeName)}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.type"))}</div>
                <div class="value">${escapeHtml(row.employeeType)}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.salaryMonth"))}</div>
                <div class="value technical">${escapeHtml(row.salaryMonth)}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.basicSalary"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.basicSalary))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.bonus"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.bonus))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.deduction"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.deduction))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.loanRecovery"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.loanRecovery))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.advanceRecovery"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.advanceRecovery))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.netSalary"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.netSalary))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("common.paid"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.paidAmount))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("common.remaining"))}</div>
                <div class="value technical">${escapeHtml(formatAmount(row.remainingAmount))}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("common.status"))}</div>
                <div class="value"><span class="status">${escapeHtml(statusLabel)}</span></div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.paymentMethod"))}</div>
                <div class="value">${escapeHtml(paymentMethodLabel)}</div>
              </div>
              <div class="field">
                <div class="label">${escapeHtml(t("employeeSalary.fields.referenceNo"))}</div>
                <div class="value technical">${escapeHtml(row.referenceNo || "-")}</div>
              </div>
              <div class="field remarks">
                <div class="label">${escapeHtml(t("common.remarks"))}</div>
                <div class="value">${escapeHtml(row.remarks || "-")}</div>
              </div>
            </div>

            <div class="signatures">
              <div class="signature">${escapeHtml(t("employeeSalary.print.preparedBy"))}</div>
              <div class="signature">${escapeHtml(t("employeeSalary.print.receivedBy"))}</div>
            </div>
          </div>

          <script>
            window.onload = function () { window.print(); };
            window.onafterprint = function () { window.close(); };
          </script>
        </body>
      </html>
    `, addaId, language === "ur" ? "ur" : "en");
    onClose();
  }

  useEffect(() => {
    const presentation: ModulePrintPresentation = {
      documentType: "employee",
      title: printLabel("employeeSalary.print.slipTitle"),
      documentNo: printValue(row.referenceNo),
      documentDate: printValue(row.salaryMonth),
      fields: [
        { label: printLabel("employeeSalary.fields.employee"), value: printValue(row.employeeName) },
        { label: printLabel("employeeSalary.fields.type"), value: printValue(row.employeeType) },
        { label: printLabel("employeeSalary.fields.salaryMonth"), value: printValue(row.salaryMonth) },
        { label: printLabel("employeeSalary.fields.basicSalary"), value: printValue(formatAmount(row.basicSalary)) },
        { label: printLabel("employeeSalary.fields.bonus"), value: printValue(formatAmount(row.bonus)) },
        { label: printLabel("employeeSalary.fields.deduction"), value: printValue(formatAmount(row.deduction)) },
        { label: printLabel("employeeSalary.fields.loanRecovery"), value: printValue(formatAmount(row.loanRecovery)) },
        { label: printLabel("employeeSalary.fields.advanceRecovery"), value: printValue(formatAmount(row.advanceRecovery)) },
        { label: printLabel("employeeSalary.fields.netSalary"), value: printValue(formatAmount(row.netSalary)) },
        { label: printLabel("common.paid"), value: printValue(formatAmount(row.paidAmount)) },
        { label: printLabel("common.remaining"), value: printValue(formatAmount(row.remainingAmount)) },
        { label: printLabel("common.status"), value: printLabel(`common.paymentStatus.${row.paymentStatus.toLowerCase()}`) },
        { label: printLabel("employeeSalary.fields.paymentMethod"), value: printValue(paymentMethodLabel) },
        { label: printLabel("employeeSalary.fields.referenceNo"), value: printValue(row.referenceNo) },
      ],
      remarks: printValue(row.remarks),
    };
    modulePrint.openPresentation(presentation, printLegacy, addaId);
  // The selected immutable salary row is the complete print payload.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [row.id]);

  return <>{modulePrint.dialog}</>;
}

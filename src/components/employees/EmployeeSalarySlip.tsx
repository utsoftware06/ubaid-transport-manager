"use client";

import { useEffect } from "react";
import { type EmployeeSalaryRow, formatAmount } from "./EmployeeSalary";

type Props = {
  row: EmployeeSalaryRow;
  onClose: () => void;
};

function escapeHtml(value: string | number) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export default function EmployeeSalarySlip({ row, onClose }: Props) {
  useEffect(() => {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert("Please allow popups to print the salary slip.");
      onClose();
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Salary Slip - ${escapeHtml(row.employeeName)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              background: #ffffff;
              color: #111827;
              font-family: Arial, sans-serif;
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
              text-align: right;
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
                <h1>UT Software</h1>
                <div class="subtitle">Employee Salary Slip</div>
              </div>
              <div class="meta">
                <div><strong>Salary Month:</strong> ${escapeHtml(row.salaryMonth)}</div>
                <div><strong>Reference:</strong> ${escapeHtml(row.referenceNo || "-")}</div>
              </div>
            </div>

            <div class="grid">
              <div class="field">
                <div class="label">Employee</div>
                <div class="value">${escapeHtml(row.employeeName)}</div>
              </div>
              <div class="field">
                <div class="label">Employee Type</div>
                <div class="value">${escapeHtml(row.employeeType)}</div>
              </div>
              <div class="field">
                <div class="label">Salary Month</div>
                <div class="value">${escapeHtml(row.salaryMonth)}</div>
              </div>
              <div class="field">
                <div class="label">Basic Salary</div>
                <div class="value">${escapeHtml(formatAmount(row.basicSalary))}</div>
              </div>
              <div class="field">
                <div class="label">Bonus</div>
                <div class="value">${escapeHtml(formatAmount(row.bonus))}</div>
              </div>
              <div class="field">
                <div class="label">Deduction</div>
                <div class="value">${escapeHtml(formatAmount(row.deduction))}</div>
              </div>
              <div class="field">
                <div class="label">Loan Recovery</div>
                <div class="value">${escapeHtml(formatAmount(row.loanRecovery))}</div>
              </div>
              <div class="field">
                <div class="label">Advance Recovery</div>
                <div class="value">${escapeHtml(formatAmount(row.advanceRecovery))}</div>
              </div>
              <div class="field">
                <div class="label">Net Salary</div>
                <div class="value">${escapeHtml(formatAmount(row.netSalary))}</div>
              </div>
              <div class="field">
                <div class="label">Paid</div>
                <div class="value">${escapeHtml(formatAmount(row.paidAmount))}</div>
              </div>
              <div class="field">
                <div class="label">Remaining</div>
                <div class="value">${escapeHtml(formatAmount(row.remainingAmount))}</div>
              </div>
              <div class="field">
                <div class="label">Status</div>
                <div class="value"><span class="status">${escapeHtml(row.paymentStatus)}</span></div>
              </div>
              <div class="field">
                <div class="label">Payment Method</div>
                <div class="value">${escapeHtml(row.paymentMethod)}</div>
              </div>
              <div class="field">
                <div class="label">Reference</div>
                <div class="value">${escapeHtml(row.referenceNo || "-")}</div>
              </div>
              <div class="field remarks">
                <div class="label">Remarks</div>
                <div class="value">${escapeHtml(row.remarks || "-")}</div>
              </div>
            </div>

            <div class="signatures">
              <div class="signature">Prepared By</div>
              <div class="signature">Received By</div>
            </div>
          </div>

          <script>
            window.onload = function () { window.print(); };
            window.onafterprint = function () { window.close(); };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
    onClose();
  }, [row, onClose]);

  return null;
}
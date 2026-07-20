"use client";

import { useState } from "react";
import {
  formatAmount,
  type VehicleDocumentSummary,
  type VehicleDocumentWithStatus,
} from "./VehicleDocuments";

type Props = {
  documents: VehicleDocumentWithStatus[];
  summary: VehicleDocumentSummary;
  selectedDocument: VehicleDocumentWithStatus | null;
};

type PrintMode = "all" | "single";

function formatDate(value: string | null) {
  if (!value) return "-";

  const date = new Date(`${value}T00:00:00`);

  if (Number.isNaN(date.getTime())) return "-";

  return date.toLocaleDateString("en-PK", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function displayValue(value: string | null) {
  if (!value || !value.trim()) return "-";
  return value;
}

function formatDaysRemaining(document: VehicleDocumentWithStatus) {
  if (document.status === "Permanent" || document.daysRemaining === null) {
    return "-";
  }

  if (document.daysRemaining < 0) {
    const expiredDays = Math.abs(document.daysRemaining);
    return `Expired ${expiredDays} ${expiredDays === 1 ? "day" : "days"} ago`;
  }

  if (document.daysRemaining === 0) {
    return "Expires today";
  }

  return `${document.daysRemaining} ${
    document.daysRemaining === 1 ? "day" : "days"
  }`;
}

function getPrintedDateTime() {
  return new Date().toLocaleString("en-PK", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default function VehicleDocumentPrint({
  documents,
  summary,
  selectedDocument,
}: Props) {
  const [printMode, setPrintMode] = useState<PrintMode>("all");

  function printAfterRender() {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        window.print();
      });
    });
  }

  function handlePrintAll() {
    setPrintMode("all");
    printAfterRender();
  }

  function handlePrintSelected() {
    if (!selectedDocument) return;

    setPrintMode("single");
    printAfterRender();
  }

  return (
    <>
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">
              Vehicle Document Printing
            </h2>
            <p className="mt-2 text-sm font-medium text-gray-900">
              Print filtered records or the currently selected vehicle document.
            </p>

            <div className="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p className="text-xs font-bold uppercase text-gray-900">
                  Filtered Records
                </p>
                <p className="mt-2 text-xl font-extrabold text-gray-900">
                  {documents.length}
                </p>
              </div>

              <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p className="text-xs font-bold uppercase text-gray-900">
                  Total Fees
                </p>
                <p className="mt-2 text-xl font-extrabold text-blue-700">
                  {formatAmount(summary.totalFees)}
                </p>
              </div>

              <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p className="text-xs font-bold uppercase text-gray-900">
                  Selected
                </p>
                <p className="mt-2 text-base font-extrabold text-gray-900">
                  {selectedDocument
                    ? `${selectedDocument.vehicleNo} - ${selectedDocument.document_type}`
                    : "None"}
                </p>
              </div>
            </div>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row lg:flex-col">
            <button
              type="button"
              onClick={handlePrintAll}
              className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-blue-700"
            >
              Print All Records
            </button>

            <button
              type="button"
              onClick={handlePrintSelected}
              disabled={!selectedDocument}
              className="rounded-lg bg-gray-900 px-6 py-3 text-sm font-bold text-white transition hover:bg-black disabled:cursor-not-allowed disabled:bg-gray-500"
            >
              Print Selected Document
            </button>
          </div>
        </div>
      </div>

      <section className="vehicle-document-print-area">
        {printMode === "all" && (
          <div className="print-document">
            <div className="print-header">
              <div>
                <h1>Vehicle Documents Report</h1>
                <p>UT Software</p>
              </div>
              <div className="print-meta">
                <p>
                  <strong>Generated:</strong> {getPrintedDateTime()}
                </p>
                <p>
                  <strong>Total Records:</strong> {documents.length}
                </p>
              </div>
            </div>

            <div className="print-summary print-summary-six">
              <div>
                <span>Total Documents</span>
                <strong>{summary.totalDocuments}</strong>
              </div>
              <div>
                <span>Active</span>
                <strong>{summary.activeDocuments}</strong>
              </div>
              <div>
                <span>Expiring Soon</span>
                <strong>{summary.expiringSoonDocuments}</strong>
              </div>
              <div>
                <span>Expired</span>
                <strong>{summary.expiredDocuments}</strong>
              </div>
              <div>
                <span>Permanent</span>
                <strong>{summary.permanentDocuments}</strong>
              </div>
              <div>
                <span>Total Fees</span>
                <strong>{formatAmount(summary.totalFees)}</strong>
              </div>
            </div>

            {documents.length === 0 ? (
              <div className="print-empty">No vehicle document records found.</div>
            ) : (
              <table className="print-table">
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Vehicle</th>
                    <th>Owner</th>
                    <th>Document Type</th>
                    <th>Document Number</th>
                    <th>Issue Date</th>
                    <th>Expiry Date</th>
                    <th>Status</th>
                    <th>Days Remaining</th>
                    <th>Fee</th>
                    <th>Authority</th>
                    <th>Payment Method</th>
                  </tr>
                </thead>
                <tbody>
                  {documents.map((document, index) => (
                    <tr key={document.id}>
                      <td>{index + 1}</td>
                      <td>{displayValue(document.vehicleNo)}</td>
                      <td>{displayValue(document.ownerName)}</td>
                      <td>{document.document_type}</td>
                      <td>{displayValue(document.document_number)}</td>
                      <td>{formatDate(document.issue_date)}</td>
                      <td>{formatDate(document.expiry_date)}</td>
                      <td>{document.status}</td>
                      <td>{formatDaysRemaining(document)}</td>
                      <td className="print-amount">
                        {formatAmount(document.fee_amount)}
                      </td>
                      <td>{displayValue(document.authority_name)}</td>
                      <td>{displayValue(document.payment_method)}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot>
                  <tr>
                    <td colSpan={9}>Total Fee Amount</td>
                    <td className="print-amount">
                      {formatAmount(summary.totalFees)}
                    </td>
                    <td colSpan={2}></td>
                  </tr>
                </tfoot>
              </table>
            )}
          </div>
        )}

        {printMode === "single" && selectedDocument && (
          <div className="print-document print-single-document">
            <div className="print-header">
              <div>
                <h1>Vehicle Document Record</h1>
                <p>UT Software</p>
              </div>
              <div className="print-meta">
                <p>
                  <strong>Printed On:</strong> {getPrintedDateTime()}
                </p>
                <p>
                  <strong>Status:</strong> {selectedDocument.status}
                </p>
              </div>
            </div>

            <div className="print-detail-grid">
              <div>
                <span>Vehicle</span>
                <strong>{displayValue(selectedDocument.vehicleNo)}</strong>
              </div>
              <div>
                <span>Owner</span>
                <strong>{displayValue(selectedDocument.ownerName)}</strong>
              </div>
              <div>
                <span>Document Type</span>
                <strong>{selectedDocument.document_type}</strong>
              </div>
              <div>
                <span>Document Number</span>
                <strong>{displayValue(selectedDocument.document_number)}</strong>
              </div>
              <div>
                <span>Issue Date</span>
                <strong>{formatDate(selectedDocument.issue_date)}</strong>
              </div>
              <div>
                <span>Expiry Date</span>
                <strong>{formatDate(selectedDocument.expiry_date)}</strong>
              </div>
              <div>
                <span>Status</span>
                <strong>{selectedDocument.status}</strong>
              </div>
              <div>
                <span>Days Remaining</span>
                <strong>{formatDaysRemaining(selectedDocument)}</strong>
              </div>
              <div>
                <span>Fee Amount</span>
                <strong>{formatAmount(selectedDocument.fee_amount)}</strong>
              </div>
              <div>
                <span>Payment Method</span>
                <strong>{displayValue(selectedDocument.payment_method)}</strong>
              </div>
              <div>
                <span>Reference Number</span>
                <strong>{displayValue(selectedDocument.reference_no)}</strong>
              </div>
              <div>
                <span>Authority / Department</span>
                <strong>{displayValue(selectedDocument.authority_name)}</strong>
              </div>
              <div className="print-detail-full">
                <span>Attachment URL</span>
                <strong>{displayValue(selectedDocument.attachment_url)}</strong>
              </div>
              <div className="print-detail-full">
                <span>Remarks</span>
                <strong>{displayValue(selectedDocument.remarks)}</strong>
              </div>
            </div>
          </div>
        )}
      </section>

      <style jsx global>{`
        .vehicle-document-print-area {
          display: none;
        }

        @media print {
          @page {
            size: A4 landscape;
            margin: 10mm;
          }

          html,
          body {
            background: #ffffff !important;
          }

          body * {
            visibility: hidden !important;
          }

          .vehicle-document-print-area,
          .vehicle-document-print-area * {
            visibility: visible !important;
          }

          .vehicle-document-print-area {
            display: block !important;
            position: absolute !important;
            inset: 0 auto auto 0 !important;
            width: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
            background: #ffffff !important;
            color: #000000 !important;
            font-family: Arial, sans-serif !important;
          }

          .print-document {
            display: block !important;
            width: 100% !important;
            background: #ffffff !important;
            color: #000000 !important;
            box-shadow: none !important;
            border: 0 !important;
            page-break-inside: auto;
          }

          .print-header {
            display: flex !important;
            justify-content: space-between !important;
            gap: 24px !important;
            border-bottom: 3px solid #000000 !important;
            padding-bottom: 12px !important;
            margin-bottom: 14px !important;
          }

          .print-header h1 {
            margin: 0 !important;
            color: #000000 !important;
            font-size: 24px !important;
            font-weight: 800 !important;
          }

          .print-header p {
            margin: 4px 0 0 !important;
            color: #000000 !important;
            font-size: 12px !important;
            font-weight: 700 !important;
          }

          .print-meta {
            text-align: right !important;
            color: #000000 !important;
            font-size: 12px !important;
            font-weight: 700 !important;
            line-height: 1.5 !important;
          }

          .print-summary {
            display: grid !important;
            gap: 8px !important;
            margin-bottom: 14px !important;
          }

          .print-summary-six {
            grid-template-columns: repeat(6, minmax(0, 1fr)) !important;
          }

          .print-summary div,
          .print-detail-grid div {
            border: 1px solid #000000 !important;
            padding: 8px !important;
            background: #ffffff !important;
            color: #000000 !important;
            break-inside: avoid !important;
          }

          .print-summary span,
          .print-detail-grid span {
            display: block !important;
            margin-bottom: 4px !important;
            color: #000000 !important;
            font-size: 10px !important;
            font-weight: 800 !important;
            text-transform: uppercase !important;
          }

          .print-summary strong,
          .print-detail-grid strong {
            display: block !important;
            color: #000000 !important;
            font-size: 13px !important;
            font-weight: 800 !important;
            word-break: break-word !important;
          }

          .print-table {
            width: 100% !important;
            border-collapse: collapse !important;
            color: #000000 !important;
            font-size: 9px !important;
          }

          .print-table thead {
            display: table-header-group !important;
          }

          .print-table tr {
            break-inside: avoid !important;
            page-break-inside: avoid !important;
          }

          .print-table th,
          .print-table td {
            border: 1px solid #000000 !important;
            padding: 5px !important;
            color: #000000 !important;
            text-align: left !important;
            vertical-align: top !important;
          }

          .print-table th {
            background: #e5e7eb !important;
            font-weight: 800 !important;
          }

          .print-table tfoot td {
            background: #f3f4f6 !important;
            font-weight: 900 !important;
          }

          .print-amount {
            text-align: right !important;
            white-space: nowrap !important;
          }

          .print-empty {
            border: 1px solid #000000 !important;
            padding: 18px !important;
            color: #000000 !important;
            font-size: 14px !important;
            font-weight: 800 !important;
            text-align: center !important;
          }

          .print-single-document {
            max-width: 850px !important;
            margin: 0 auto !important;
          }

          .print-detail-grid {
            display: grid !important;
            grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
            gap: 10px !important;
          }

          .print-detail-full {
            grid-column: 1 / -1 !important;
          }

          button,
          a[href]:not(.print-detail-grid a) {
            box-shadow: none !important;
          }
        }
      `}</style>
    </>
  );
}
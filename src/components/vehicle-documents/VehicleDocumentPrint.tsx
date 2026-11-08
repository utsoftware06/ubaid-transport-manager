"use client";

import { forwardRef, useCallback, useImperativeHandle, useState } from "react";
import {
  formatAmount,
  type VehicleDocumentSummary,
  type VehicleDocumentWithStatus,
} from "./VehicleDocuments";
import { useLanguage } from "@/contexts/LanguageContext";
import PrintAddaLogo from "@/components/print/PrintAddaLogo";
import { usePrintBranding } from "@/lib/print/usePrintAddaName";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { bilingual, printValue, modulePrintLabel, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import { resolveSingleVehicleDocumentOwnerAddaId } from "./ownership";
import { waitForPrintImages } from "@/lib/print/printAssets";

type Props = {
  documents: VehicleDocumentWithStatus[];
  summary: VehicleDocumentSummary;
  selectedDocument: VehicleDocumentWithStatus | null;
};

export type VehicleDocumentPrintHandle = {
  printSelected: (document: VehicleDocumentWithStatus) => void;
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

function getPrintedDateTime() {
  return new Date().toLocaleString("en-PK", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

const VehicleDocumentPrint = forwardRef<VehicleDocumentPrintHandle, Props>(function VehicleDocumentPrint({
  documents,
  summary,
  selectedDocument,
}: Props, ref) {
  const { t, dir, language } = useLanguage();
  const [printMode, setPrintMode] = useState<PrintMode>("all");
  const [printDocument, setPrintDocument] = useState<VehicleDocumentWithStatus | null>(null);
  const activeDocument = printDocument ?? selectedDocument;
  const sourceDocuments = printMode === "single" && activeDocument ? [activeDocument] : documents;
  const ownerAddaId = resolveSingleVehicleDocumentOwnerAddaId(sourceDocuments.map((document) => document.ownerAddaId));
  const branding = usePrintBranding(ownerAddaId);
  const addaName = branding?.addaName.trim() || (language === "ur" ? "اڈے کا نام دستیاب نہیں" : "Adda name unavailable");
  const { openPresentation, dialog } = useModuleTransportPrint("vehicle_document", ownerAddaId, language === "ur" ? "ur" : "en");
  const statusLabel = (status: VehicleDocumentWithStatus["status"]) =>
    t(`vehicleDocuments.statuses.${status === "Expiring Soon" ? "expiringSoon" : status.toLowerCase()}`);
  const documentTypeLabel = (type: string) =>
    t(`vehicleDocuments.documentTypes.${type.replaceAll(" ", "").replace(/^./, (character) => character.toLowerCase())}`);
  const formatDaysRemaining = useCallback((document: VehicleDocumentWithStatus) => {
    if (document.status === "Permanent" || document.daysRemaining === null) return "-";
    if (document.daysRemaining < 0) {
      const days = Math.abs(document.daysRemaining);
      return `${t("vehicleDocuments.days.expired")} ${days} ${t(days === 1 ? "vehicleDocuments.days.day" : "vehicleDocuments.days.days")} ${t("vehicleDocuments.days.ago")}`;
    }
    if (document.daysRemaining === 0) return t("vehicleDocuments.days.expiresToday");
    return `${document.daysRemaining} ${t(document.daysRemaining === 1 ? "vehicleDocuments.days.day" : "vehicleDocuments.days.days")}`;
  }, [t]);

  function printAfterRender() {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        void waitForPrintImages(document).then(() => window.print());
      });
    });
  }

  function handlePrintAll() {
    const owner = resolveSingleVehicleDocumentOwnerAddaId(documents.map((document) => document.ownerAddaId));
    if (!owner) return;
    setPrintMode("all");
    setPrintDocument(null);
    const p = (key: string) => bilingual(modulePrintLabel("en", key), modulePrintLabel("ur", key));
    const presentation: ModulePrintPresentation = {
      documentType: "vehicle_document",
      title: p("vehicleDocuments.print.reportTitle"),
      subtitle: p("vehicleDocuments.print.filteredRecords"),
      fields: [],
      tables: [{
        title: p("vehicleDocuments.print.reportTitle"),
        columns: [p("common.vehicle"), p("common.owner"), p("vehicleDocuments.fields.documentType"), p("vehicleDocuments.fields.documentNumber"), p("vehicleDocuments.fields.issueDate"), p("vehicleDocuments.fields.expiryDate"), p("common.status"), p("vehicleDocuments.fields.daysRemaining"), p("vehicleDocuments.print.fee"), p("vehicleDocuments.fields.authority"), p("vehicleDocuments.fields.paymentMethod")],
        rows: documents.map((document) => [printValue(document.vehicleNo), printValue(document.ownerName), p(`vehicleDocuments.documentTypes.${document.document_type.replaceAll(" ", "").replace(/^./, (character) => character.toLowerCase())}`), printValue(document.document_number), printValue(formatDate(document.issue_date)), printValue(formatDate(document.expiry_date)), p(`vehicleDocuments.statuses.${document.status === "Expiring Soon" ? "expiringSoon" : document.status.toLowerCase()}`), printValue(formatDaysRemaining(document)), printValue(formatAmount(document.fee_amount)), printValue(document.authority_name), printValue(document.payment_method)]),
      }],
      totals: [
        { label: p("vehicleDocuments.cards.totalDocuments"), value: printValue(summary.totalDocuments) },
        { label: p("vehicleDocuments.statuses.active"), value: printValue(summary.activeDocuments) },
        { label: p("vehicleDocuments.statuses.expiringSoon"), value: printValue(summary.expiringSoonDocuments) },
        { label: p("vehicleDocuments.statuses.expired"), value: printValue(summary.expiredDocuments) },
        { label: p("vehicleDocuments.statuses.permanent"), value: printValue(summary.permanentDocuments) },
        { label: p("vehicleDocuments.cards.totalFees"), value: printValue(formatAmount(summary.totalFees)) },
      ],
    };
    openPresentation(presentation, () => { setPrintMode("all"); setPrintDocument(null); printAfterRender(); }, owner);
  }

  const handlePrintSelected = useCallback((document: VehicleDocumentWithStatus | null = selectedDocument) => {
    if (!document) return;

    const owner = document.ownerAddaId;
    if (!owner) return;
    setPrintMode("single");
    setPrintDocument(document);
    const p = (key: string) => bilingual(modulePrintLabel("en", key), modulePrintLabel("ur", key));
    const presentation: ModulePrintPresentation = {
      documentType: "vehicle_document",
      title: p("vehicleDocuments.fields.documentNumber"),
      documentNo: printValue(document.document_number),
      documentDate: printValue(formatDate(document.issue_date)),
      fields: [
        { label: p("common.vehicle"), value: printValue(document.vehicleNo) },
        { label: p("common.owner"), value: printValue(document.ownerName) },
        { label: p("vehicleDocuments.fields.documentType"), value: p(`vehicleDocuments.documentTypes.${document.document_type.replaceAll(" ", "").replace(/^./, (character) => character.toLowerCase())}`) },
        { label: p("vehicleDocuments.fields.expiryDate"), value: printValue(formatDate(document.expiry_date)) },
        { label: p("common.status"), value: p(`vehicleDocuments.statuses.${document.status === "Expiring Soon" ? "expiringSoon" : document.status.toLowerCase()}`) },
        { label: p("vehicleDocuments.fields.daysRemaining"), value: printValue(formatDaysRemaining(document)) },
        { label: p("vehicleDocuments.fields.authority"), value: printValue(document.authority_name) },
        { label: p("vehicleDocuments.fields.paymentMethod"), value: printValue(document.payment_method) },
        { label: p("common.reference"), value: printValue(document.reference_no) },
      ],
      totals: [{ label: p("vehicleDocuments.print.fee"), value: printValue(formatAmount(document.fee_amount)) }],
      remarks: printValue(document.remarks),
    };
    openPresentation(presentation, () => { setPrintMode("single"); setPrintDocument(document); printAfterRender(); }, owner);
  }, [openPresentation, selectedDocument, formatDaysRemaining]);

  useImperativeHandle(ref, () => ({ printSelected: (document) => handlePrintSelected(document) }), [handlePrintSelected]);

  return (
    <>
      <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">
              {t("vehicleDocuments.print.title")}
            </h2>
            <p className="mt-2 text-sm font-medium text-gray-900">
              {t("vehicleDocuments.print.description")}
            </p>

            <div className="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                <p className="text-xs font-bold uppercase text-gray-900">
                  {t("vehicleDocuments.print.filteredRecords")}
                </p>
                <p className="mt-2 text-xl font-extrabold text-gray-900">
                  {documents.length}
                </p>
              </div>

              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                <p className="text-xs font-bold uppercase text-gray-900">
                  {t("vehicleDocuments.cards.totalFees")}
                </p>
                <p className="mt-2 text-xl font-extrabold text-blue-700">
                  {formatAmount(summary.totalFees)}
                </p>
              </div>

              <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
                <p className="text-xs font-bold uppercase text-gray-900">
                  {t("vehicleDocuments.print.selected")}
                </p>
                <p className="mt-2 text-base font-extrabold text-gray-900">
                  {selectedDocument
                    ? `${selectedDocument.vehicleNo} - ${selectedDocument.document_type}`
                    : t("vehicleDocuments.print.none")}
                </p>
              </div>
            </div>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row lg:flex-col">
            <button
              type="button"
              onClick={handlePrintAll}
              disabled={!resolveSingleVehicleDocumentOwnerAddaId(documents.map((document) => document.ownerAddaId))}
              className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-blue-700"
            >
              {t("vehicleDocuments.print.printAll")}
            </button>

            <button
              type="button"
              onClick={() => handlePrintSelected()}
              disabled={!selectedDocument?.ownerAddaId}
              className="rounded-lg bg-gray-900 px-6 py-3 text-sm font-bold text-white transition hover:bg-black disabled:cursor-not-allowed disabled:bg-gray-500"
            >
              {t("vehicleDocuments.print.printSelected")}
            </button>
          </div>
        </div>
      </div>

      <section dir={dir} className="vehicle-document-print-area">
        {printMode === "all" && (
          <div className="print-document">
            <div className="print-header">
              <div>
                <PrintAddaLogo branding={branding} />
                <h1>{t("vehicleDocuments.print.reportTitle")}</h1>
                <p>{addaName}</p>
              </div>
              <div className="print-meta">
                <p>
                  <strong>{t("vehicleDocuments.print.generated")}:</strong> <span dir="ltr">{getPrintedDateTime()}</span>
                </p>
                <p>
                  <strong>{t("vehicleDocuments.print.totalRecords")}:</strong> {documents.length}
                </p>
              </div>
            </div>

            <div className="print-summary print-summary-six">
              <div>
                <span>{t("vehicleDocuments.cards.totalDocuments")}</span>
                <strong>{summary.totalDocuments}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.statuses.active")}</span>
                <strong>{summary.activeDocuments}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.statuses.expiringSoon")}</span>
                <strong>{summary.expiringSoonDocuments}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.statuses.expired")}</span>
                <strong>{summary.expiredDocuments}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.statuses.permanent")}</span>
                <strong>{summary.permanentDocuments}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.cards.totalFees")}</span>
                <strong>{formatAmount(summary.totalFees)}</strong>
              </div>
            </div>

            {documents.length === 0 ? (
              <div className="print-empty">{t("vehicleDocuments.empty")}</div>
            ) : (
              <table className="print-table">
                <thead>
                  <tr>
                    <th>#</th>
                    <th>{t("common.vehicle")}</th>
                    <th>{t("common.owner")}</th>
                    <th>{t("vehicleDocuments.fields.documentType")}</th>
                    <th>{t("vehicleDocuments.fields.documentNumber")}</th>
                    <th>{t("vehicleDocuments.fields.issueDate")}</th>
                    <th>{t("vehicleDocuments.fields.expiryDate")}</th>
                    <th>{t("common.status")}</th>
                    <th>{t("vehicleDocuments.fields.daysRemaining")}</th>
                    <th>{t("vehicleDocuments.print.fee")}</th>
                    <th>{t("vehicleDocuments.fields.authority")}</th>
                    <th>{t("vehicleDocuments.fields.paymentMethod")}</th>
                  </tr>
                </thead>
                <tbody>
                  {documents.map((document, index) => (
                    <tr key={document.id}>
                      <td>{index + 1}</td>
                      <td>{displayValue(document.vehicleNo)}</td>
                      <td>{displayValue(document.ownerName)}</td>
                      <td>{documentTypeLabel(document.document_type)}</td>
                      <td>{displayValue(document.document_number)}</td>
                      <td>{formatDate(document.issue_date)}</td>
                      <td>{formatDate(document.expiry_date)}</td>
                      <td>{statusLabel(document.status)}</td>
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
                    <td colSpan={9}>{t("vehicleDocuments.cards.totalFees")}</td>
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

        {printMode === "single" && activeDocument && (
          <div className="print-document print-single-document">
            <div className="print-header">
              <div>
                <PrintAddaLogo branding={branding} />
                <h1>{t("vehicleDocuments.print.recordTitle")}</h1>
                <p>{addaName}</p>
              </div>
              <div className="print-meta">
                <p>
                  <strong>{t("vehicleDocuments.print.printedOn")}:</strong> <span dir="ltr">{getPrintedDateTime()}</span>
                </p>
                <p>
                  <strong>{t("common.status")}:</strong> {statusLabel(activeDocument.status)}
                </p>
              </div>
            </div>

            <div className="print-detail-grid">
              <div>
                <span>{t("common.vehicle")}</span>
                <strong>{displayValue(activeDocument.vehicleNo)}</strong>
              </div>
              <div>
                <span>{t("common.owner")}</span>
                <strong>{displayValue(activeDocument.ownerName)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.documentType")}</span>
                <strong>{documentTypeLabel(activeDocument.document_type)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.documentNumber")}</span>
                <strong>{displayValue(activeDocument.document_number)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.issueDate")}</span>
                <strong>{formatDate(activeDocument.issue_date)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.expiryDate")}</span>
                <strong>{formatDate(activeDocument.expiry_date)}</strong>
              </div>
              <div>
                <span>{t("common.status")}</span>
                <strong>{statusLabel(activeDocument.status)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.daysRemaining")}</span>
                <strong>{formatDaysRemaining(activeDocument)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.feeAmount")}</span>
                <strong>{formatAmount(activeDocument.fee_amount)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.paymentMethod")}</span>
                <strong>{displayValue(activeDocument.payment_method)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.referenceNumber")}</span>
                <strong>{displayValue(activeDocument.reference_no)}</strong>
              </div>
              <div>
                <span>{t("vehicleDocuments.fields.authority")}</span>
                <strong>{displayValue(activeDocument.authority_name)}</strong>
              </div>
              <div className="print-detail-full">
                <span>{t("vehicleDocuments.fields.attachmentUrl")}</span>
                <strong>{displayValue(activeDocument.attachment_url)}</strong>
              </div>
              <div className="print-detail-full">
                <span>{t("common.remarks")}</span>
                <strong>{displayValue(activeDocument.remarks)}</strong>
              </div>
            </div>
          </div>
        )}
      </section>
      {dialog}

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
});

VehicleDocumentPrint.displayName = "VehicleDocumentPrint";
export default VehicleDocumentPrint;

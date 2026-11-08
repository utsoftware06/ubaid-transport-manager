"use client";

import {
  formatAmount,
  type VehicleDocumentWithStatus,
} from "./VehicleDocuments";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  documents: VehicleDocumentWithStatus[];
  loading: boolean;
  saving: boolean;
  error: string;
  onSelect: (document: VehicleDocumentWithStatus) => void;
  onPrint: (document: VehicleDocumentWithStatus) => void;
  onDelete: (id: string) => Promise<boolean>;
  onRefresh: () => Promise<void>;
};

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

function getStatusBadgeClass(status: VehicleDocumentWithStatus["status"]) {
  if (status === "Permanent") {
    return "bg-gray-100 text-gray-700";
  }

  if (status === "Active") {
    return "bg-green-100 text-green-700";
  }

  if (status === "Expiring Soon") {
    return "bg-amber-100 text-amber-700";
  }

  return "bg-red-100 text-red-700";
}

export default function VehicleDocumentTable({
  documents,
  loading,
  saving,
  error,
  onSelect,
  onPrint,
  onDelete,
  onRefresh,
}: Props) {
  const { t, dir } = useLanguage();
  const statusLabel = (status: VehicleDocumentWithStatus["status"]) =>
    t(`vehicleDocuments.statuses.${status === "Expiring Soon" ? "expiringSoon" : status.toLowerCase()}`);
  const documentTypeLabel = (type: string) =>
    t(`vehicleDocuments.documentTypes.${type.replaceAll(" ", "").replace(/^./, (character) => character.toLowerCase())}`);
  const formatDaysRemaining = (document: VehicleDocumentWithStatus) => {
    if (document.status === "Permanent" || document.daysRemaining === null) return "-";
    if (document.daysRemaining < 0) {
      const days = Math.abs(document.daysRemaining);
      return `${t("vehicleDocuments.days.expired")} ${days} ${t(days === 1 ? "vehicleDocuments.days.day" : "vehicleDocuments.days.days")} ${t("vehicleDocuments.days.ago")}`;
    }
    if (document.daysRemaining === 0) return t("vehicleDocuments.days.expiresToday");
    return `${document.daysRemaining} ${t(document.daysRemaining === 1 ? "vehicleDocuments.days.day" : "vehicleDocuments.days.days")}`;
  };
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {t("vehicleDocuments.recordsTitle")}
          </h2>
          <p className="mt-2 text-sm font-medium text-gray-900">
            {t("vehicleDocuments.recordsDescription")}
          </p>
        </div>

        <button
          type="button"
          onClick={() => {
            void onRefresh();
          }}
          disabled={loading || saving}
          className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {loading ? t("vehicleDocuments.actions.refreshing") : t("common.actions.refresh")}
        </button>
      </div>

      {error && (
        <div className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {error}
        </div>
      )}

      {saving && (
        <div className="mb-5 rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          {t("vehicleDocuments.savingChanges")}
        </div>
      )}

      {loading ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8">
          <div className="space-y-3">
            <div className="h-4 w-1/3 rounded bg-gray-200" />
            <div className="h-4 w-full rounded bg-gray-200" />
            <div className="h-4 w-5/6 rounded bg-gray-200" />
            <div className="h-4 w-4/6 rounded bg-gray-200" />
          </div>
          <p className="mt-5 text-center text-sm font-bold text-gray-900">
            {t("vehicleDocuments.loading")}
          </p>
        </div>
      ) : documents.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="text-base font-extrabold text-gray-900">
            {t("vehicleDocuments.empty")}
          </p>
          <p className="mt-2 text-sm font-bold text-gray-900">
            {t("vehicleDocuments.emptyHelp")}
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="min-w-[1600px] w-full border-collapse bg-white text-sm text-gray-900">
            <thead className="sticky top-0 z-10 bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">#</th>
                <th className="p-3 text-start font-bold">{t("common.vehicle")}</th>
                <th className="p-3 text-start font-bold">{t("common.owner")}</th>
                <th className="p-3 text-start font-bold">{t("vehicleDocuments.fields.documentType")}</th>
                <th className="p-3 text-start font-bold">{t("vehicleDocuments.fields.documentNumber")}</th>
                <th className="p-3 text-start font-bold">{t("vehicleDocuments.fields.issueDate")}</th>
                <th className="p-3 text-start font-bold">{t("vehicleDocuments.fields.expiryDate")}</th>
                <th className="p-3 text-start font-bold">{t("common.status")}</th>
                <th className="p-3 text-start font-bold">{t("vehicleDocuments.fields.daysRemaining")}</th>
                <th className="p-3 text-end font-bold">{t("vehicleDocuments.fields.feeAmount")}</th>
                <th className="p-3 text-start font-bold">{t("vehicleDocuments.fields.authority")}</th>
                <th className="p-3 text-start font-bold">{t("vehicleDocuments.fields.paymentMethod")}</th>
                <th className="p-3 text-start font-bold">{t("common.actions.title")}</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {documents.map((document, index) => (
                <tr key={document.id} className="hover:bg-blue-50">
                  <td className="p-3 font-bold text-gray-900">{index + 1}</td>
                  <td className="p-3 font-bold text-gray-900">
                    {document.vehicleNo || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {document.ownerName || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {documentTypeLabel(document.document_type)}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {document.document_number || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {formatDate(document.issue_date)}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {formatDate(document.expiry_date)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full px-3 py-1 text-xs font-extrabold ${getStatusBadgeClass(
                        document.status
                      )}`}
                    >
                      {statusLabel(document.status)}
                    </span>
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {formatDaysRemaining(document)}
                  </td>
                  <td className="p-3 text-right font-bold text-gray-900">
                    {formatAmount(document.fee_amount)}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {document.authority_name || "-"}
                  </td>
                  <td className="p-3 font-medium text-gray-900">
                    {document.payment_method || "-"}
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => onSelect(document)}
                        disabled={saving}
                        title={t("vehicleDocuments.actions.edit")}
                        className="rounded-lg bg-blue-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
                      >
                        {t("common.edit")}
                      </button>

                      <button
                        type="button"
                        onClick={() => {
                          void onDelete(document.id);
                        }}
                        disabled={saving}
                        title={t("vehicleDocuments.actions.delete")}
                        className="rounded-lg bg-red-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        {t("common.delete")}
                      </button>

                      {document.attachment_url && (
                        <a
                          href={document.attachment_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          title={t("vehicleDocuments.actions.openAttachment")}
                          className="rounded-lg bg-green-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-green-700"
                        >
                          {t("vehicleDocuments.actions.openAttachment")}
                        </a>
                      )}

                      <button
                        type="button"
                        onClick={() => onPrint(document)}
                        disabled={saving || !document.ownerAddaId}
                        title={t("vehicleDocuments.actions.printSelected")}
                        className="rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white transition hover:bg-black disabled:cursor-not-allowed"
                      >
                        {t("common.actions.print")}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot className="bg-gray-100">
              <tr>
                <td
                  colSpan={9}
                  className="p-3 text-right font-extrabold text-gray-900"
                >
                  {t("vehicleDocuments.cards.totalFees")}
                </td>
                <td className="p-3 text-right font-extrabold text-gray-900">
                  {formatAmount(
                    documents.reduce(
                      (total, document) => total + document.fee_amount,
                      0
                    )
                  )}
                </td>
                <td colSpan={3} className="p-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}

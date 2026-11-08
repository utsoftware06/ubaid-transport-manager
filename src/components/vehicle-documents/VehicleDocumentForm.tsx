"use client";

import { useEffect, useState } from "react";
import {
  VEHICLE_DOCUMENT_TYPES,
  type VehicleDocumentPayload,
  type VehicleDocumentType,
  type VehicleDocumentWithStatus,
  type VehicleOption,
} from "./VehicleDocuments";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  vehicles: VehicleOption[];
  selectedDocument: VehicleDocumentWithStatus | null;
  saving: boolean;
  error: string;
  onCreate: (payload: VehicleDocumentPayload) => Promise<boolean>;
  onUpdate: (id: string, payload: VehicleDocumentPayload) => Promise<boolean>;
  onCancel: () => void;
};

type PaymentMethod = "Cash" | "Bank" | "Cheque" | "Online Transfer" | "Account";

type FormErrors = {
  vehicleId?: string;
  documentType?: string;
  feeAmount?: string;
  expiryDate?: string;
};

const paymentMethods: PaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

export default function VehicleDocumentForm({
  vehicles,
  selectedDocument,
  saving,
  error,
  onCreate,
  onUpdate,
  onCancel,
}: Props) {
  const { t, dir } = useLanguage();
  const documentTypeLabel = (type: VehicleDocumentType) =>
    t(`vehicleDocuments.documentTypes.${type.replaceAll(" ", "").replace(/^./, (character) => character.toLowerCase())}`);
  const [vehicleId, setVehicleId] = useState("");
  const [documentType, setDocumentType] = useState<VehicleDocumentType | "">("");
  const [documentNumber, setDocumentNumber] = useState("");
  const [issueDate, setIssueDate] = useState("");
  const [expiryDate, setExpiryDate] = useState("");
  const [feeAmount, setFeeAmount] = useState("0");
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod | "">("");
  const [referenceNo, setReferenceNo] = useState("");
  const [authorityName, setAuthorityName] = useState("");
  const [attachmentUrl, setAttachmentUrl] = useState("");
  const [remarks, setRemarks] = useState("");
  const [formErrors, setFormErrors] = useState<FormErrors>({});

  const isEditing = Boolean(selectedDocument);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      if (!selectedDocument) {
        resetForm();
        return;
      }

      setVehicleId(selectedDocument.vehicle_id);
      setDocumentType(selectedDocument.document_type);
      setDocumentNumber(selectedDocument.document_number ?? "");
      setIssueDate(selectedDocument.issue_date ?? "");
      setExpiryDate(selectedDocument.expiry_date ?? "");
      setFeeAmount(String(selectedDocument.fee_amount ?? 0));
      setPaymentMethod((selectedDocument.payment_method as PaymentMethod) ?? "");
      setReferenceNo(selectedDocument.reference_no ?? "");
      setAuthorityName(selectedDocument.authority_name ?? "");
      setAttachmentUrl(selectedDocument.attachment_url ?? "");
      setRemarks(selectedDocument.remarks ?? "");
      setFormErrors({});
    }, 0);

    return () => window.clearTimeout(timer);
  }, [selectedDocument]);

  function resetForm() {
    setVehicleId("");
    setDocumentType("");
    setDocumentNumber("");
    setIssueDate("");
    setExpiryDate("");
    setFeeAmount("0");
    setPaymentMethod("");
    setReferenceNo("");
    setAuthorityName("");
    setAttachmentUrl("");
    setRemarks("");
    setFormErrors({});
  }

  function validateForm() {
    const nextErrors: FormErrors = {};
    const feeValue = Number(feeAmount || 0);

    if (!vehicleId) {
      nextErrors.vehicleId = t("vehicleDocuments.validation.vehicleRequired");
    }

    if (!documentType) {
      nextErrors.documentType = t("vehicleDocuments.validation.typeRequired");
    }

    if (!Number.isFinite(feeValue) || feeValue < 0) {
      nextErrors.feeAmount = t("vehicleDocuments.validation.feeNonNegative");
    }

    if (issueDate && expiryDate && expiryDate < issueDate) {
      nextErrors.expiryDate = t("vehicleDocuments.validation.expiryBeforeIssue");
    }

    setFormErrors(nextErrors);

    return Object.keys(nextErrors).length === 0;
  }

  function buildPayload(): VehicleDocumentPayload {
    return {
      vehicle_id: vehicleId,
      document_type: documentType || "Other",
      document_number: documentNumber.trim() || null,
      issue_date: issueDate || null,
      expiry_date: expiryDate || null,
      fee_amount: Number(feeAmount || 0),
      payment_method: paymentMethod || null,
      reference_no: referenceNo.trim() || null,
      authority_name: authorityName.trim() || null,
      attachment_url: attachmentUrl.trim() || null,
      remarks: remarks.trim() || null,
    };
  }

  async function handleSubmit() {
    if (!validateForm()) return;

    const payload = buildPayload();

    const success =
      selectedDocument && isEditing
        ? await onUpdate(selectedDocument.id, payload)
        : await onCreate(payload);

    if (success) {
      resetForm();
    }
  }

  function handleCancel() {
    resetForm();
    onCancel();
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {isEditing ? t("vehicleDocuments.actions.edit") : t("vehicleDocuments.actions.add")}
        </h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          {t("vehicleDocuments.formDescription")}
        </p>
      </div>

      {error && (
        <div className="mb-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.vehicle")}
          </label>
          <select
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          >
            <option value="">{t("vehicleDocuments.placeholders.selectVehicle")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo} - {vehicle.ownerName || t("vehicleDocuments.noOwner")}
              </option>
            ))}
          </select>
          {formErrors.vehicleId && (
            <p className="mt-2 text-sm font-bold text-red-700">
              {formErrors.vehicleId}
            </p>
          )}
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.documentType")}
          </label>
          <select
            value={documentType}
            onChange={(event) =>
              setDocumentType(event.target.value as VehicleDocumentType)
            }
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          >
            <option value="">{t("vehicleDocuments.placeholders.selectType")}</option>
            {VEHICLE_DOCUMENT_TYPES.map((type) => (
              <option key={type} value={type}>
                {documentTypeLabel(type)}
              </option>
            ))}
          </select>
          {formErrors.documentType && (
            <p className="mt-2 text-sm font-bold text-red-700">
              {formErrors.documentType}
            </p>
          )}
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.documentNumber")}
          </label>
          <VoiceTypingField fieldLabel={t("vehicleDocuments.placeholders.documentNumber")} mode="identifier"><input
            type="text"
            value={documentNumber}
            onChange={(event) => setDocumentNumber(event.target.value)}
            disabled={saving}
            placeholder={t("vehicleDocuments.placeholders.documentNumber")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          /></VoiceTypingField>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.authority")}
          </label>
          <VoiceTypingField fieldLabel={t("vehicleDocuments.fields.authority")} value={authorityName} onValueChange={setAuthorityName} contextKey={selectedDocument?.id ?? vehicleId}>
            <input
              type="text"
              value={authorityName}
              onChange={(event) => setAuthorityName(event.target.value)}
              disabled={saving}
              placeholder={t("vehicleDocuments.placeholders.authority")}
              className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            />
          </VoiceTypingField>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.issueDate")}
          </label>
          <VoiceTypingField fieldLabel={t("vehicleDocuments.fields.issueDate")} mode="date"><input
            type="date"
            dir="ltr"
            value={issueDate}
            onChange={(event) => setIssueDate(event.target.value)}
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          /></VoiceTypingField>
        </div>



        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.expiryDate")}
          </label>
          <VoiceTypingField fieldLabel={t("vehicleDocuments.fields.expiryDate")} mode="date"><input
            type="date"
            dir="ltr"
            value={expiryDate}
            onChange={(event) => setExpiryDate(event.target.value)}
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          /></VoiceTypingField>
          {formErrors.expiryDate && (
            <p className="mt-2 text-sm font-bold text-red-700">
              {formErrors.expiryDate}
            </p>
          )}
        </div>



        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.feeAmount")}
          </label>
          <p className="mb-2 text-xs font-medium text-slate-600">
            {t("vehicleDocuments.fields.feeRecordOnly")}
          </p>
          <VoiceTypingField fieldLabel={t("vehicleDocuments.placeholders.feeAmount")} mode="amount"><input
            type="number"
            min="0"
            value={feeAmount}
            onChange={(event) => setFeeAmount(event.target.value)}
            disabled={saving}
            placeholder={t("vehicleDocuments.placeholders.feeAmount")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          /></VoiceTypingField>
          {formErrors.feeAmount && (
            <p className="mt-2 text-sm font-bold text-red-700">
              {formErrors.feeAmount}
            </p>
          )}
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.paymentMethod")}
          </label>
          <select
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as PaymentMethod)
            }
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          >
            <option value="">{t("vehicleDocuments.placeholders.selectPaymentMethod")}</option>
            {paymentMethods.map((method) => (
              <option key={method} value={method}>
                {t(`vehicleDocuments.paymentMethods.${method === "Online Transfer" ? "onlineTransfer" : method.toLowerCase()}`)}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.referenceNumber")}
          </label>
          <VoiceTypingField fieldLabel={t("vehicleDocuments.placeholders.referenceNumber")} mode="identifier"><input
            type="text"
            value={referenceNo}
            onChange={(event) => setReferenceNo(event.target.value)}
            disabled={saving}
            placeholder={t("vehicleDocuments.placeholders.referenceNumber")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          /></VoiceTypingField>
        </div>



        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("vehicleDocuments.fields.attachmentUrl")}
          </label>
          <VoiceTypingField fieldLabel="https://..." mode="url"><input
            type="url"
            value={attachmentUrl}
            onChange={(event) => setAttachmentUrl(event.target.value)}
            disabled={saving}
            placeholder="https://..."
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          /></VoiceTypingField>
        </div>


        <div className="lg:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.remarks")}
          </label>
          <VoiceTypingField fieldLabel={t("common.remarks")} value={remarks} onValueChange={setRemarks} contextKey={selectedDocument?.id ?? vehicleId}>
            <textarea
              value={remarks}
              onChange={(event) => setRemarks(event.target.value)}
              disabled={saving}
              rows={4}
              placeholder={t("vehicleDocuments.placeholders.remarks")}
              className="w-full resize-none rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            />
          </VoiceTypingField>
        </div>
      </div>

      <div className="mt-8 flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          onClick={handleSubmit}
          disabled={saving}
          className="rounded-lg bg-blue-600 px-8 py-3 font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {saving
            ? isEditing
              ? t("vehicleDocuments.actions.updating")
              : t("common.saving")
            : isEditing
              ? t("vehicleDocuments.actions.update")
              : t("vehicleDocuments.actions.save")}
        </button>

        {isEditing && (
          <button
            type="button"
            onClick={handleCancel}
            disabled={saving}
            className="rounded-lg border border-gray-300 bg-white px-8 py-3 font-bold text-gray-900 transition hover:bg-gray-100 disabled:cursor-not-allowed"
          >
            {t("common.actions.cancel")}
          </button>
        )}
      </div>
    </div>
  );
}

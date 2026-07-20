"use client";

import { useEffect, useState } from "react";
import {
  VEHICLE_DOCUMENT_TYPES,
  type VehicleDocumentPayload,
  type VehicleDocumentType,
  type VehicleDocumentWithStatus,
  type VehicleOption,
} from "./VehicleDocuments";

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
      nextErrors.vehicleId = "Vehicle is required.";
    }

    if (!documentType) {
      nextErrors.documentType = "Document Type is required.";
    }

    if (!Number.isFinite(feeValue) || feeValue < 0) {
      nextErrors.feeAmount = "Fee Amount must be zero or greater.";
    }

    if (issueDate && expiryDate && expiryDate < issueDate) {
      nextErrors.expiryDate = "Expiry Date cannot be before Issue Date.";
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
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {isEditing ? "Edit Vehicle Document" : "Add Vehicle Document"}
        </h2>
        <p className="mt-2 text-sm font-medium text-gray-900">
          Record vehicle documents, expiry dates, fees, authority details and
          attachment links.
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
            Vehicle
          </label>
          <select
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          >
            <option value="">Select Vehicle</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo} - {vehicle.ownerName || "No Owner"}
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
            Document Type
          </label>
          <select
            value={documentType}
            onChange={(event) =>
              setDocumentType(event.target.value as VehicleDocumentType)
            }
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          >
            <option value="">Select Document Type</option>
            {VEHICLE_DOCUMENT_TYPES.map((type) => (
              <option key={type} value={type}>
                {type}
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
            Document Number
          </label>
          <input
            type="text"
            value={documentNumber}
            onChange={(event) => setDocumentNumber(event.target.value)}
            disabled={saving}
            placeholder="Document Number"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Authority / Department
          </label>
          <input
            type="text"
            value={authorityName}
            onChange={(event) => setAuthorityName(event.target.value)}
            disabled={saving}
            placeholder="Authority / Department"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Issue Date
          </label>
          <input
            type="date"
            value={issueDate}
            onChange={(event) => setIssueDate(event.target.value)}
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Expiry Date
          </label>
          <input
            type="date"
            value={expiryDate}
            onChange={(event) => setExpiryDate(event.target.value)}
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
          {formErrors.expiryDate && (
            <p className="mt-2 text-sm font-bold text-red-700">
              {formErrors.expiryDate}
            </p>
          )}
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Fee Amount
          </label>
          <input
            type="number"
            min="0"
            value={feeAmount}
            onChange={(event) => setFeeAmount(event.target.value)}
            disabled={saving}
            placeholder="Fee Amount"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
          {formErrors.feeAmount && (
            <p className="mt-2 text-sm font-bold text-red-700">
              {formErrors.feeAmount}
            </p>
          )}
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Method
          </label>
          <select
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as PaymentMethod)
            }
            disabled={saving}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          >
            <option value="">Select Payment Method</option>
            {paymentMethods.map((method) => (
              <option key={method} value={method}>
                {method}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Reference Number
          </label>
          <input
            type="text"
            value={referenceNo}
            onChange={(event) => setReferenceNo(event.target.value)}
            disabled={saving}
            placeholder="Reference Number"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Attachment URL
          </label>
          <input
            type="url"
            value={attachmentUrl}
            onChange={(event) => setAttachmentUrl(event.target.value)}
            disabled={saving}
            placeholder="https://..."
            className="w-full rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
        </div>

        <div className="lg:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Remarks
          </label>
          <textarea
            value={remarks}
            onChange={(event) => setRemarks(event.target.value)}
            disabled={saving}
            rows={4}
            placeholder="Remarks"
            className="w-full resize-none rounded-lg border border-gray-300 bg-white p-3 text-base font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
          />
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
              ? "Updating..."
              : "Saving..."
            : isEditing
              ? "Update Document"
              : "Save Document"}
        </button>

        {isEditing && (
          <button
            type="button"
            onClick={handleCancel}
            disabled={saving}
            className="rounded-lg border border-gray-300 bg-white px-8 py-3 font-bold text-gray-900 transition hover:bg-gray-100 disabled:cursor-not-allowed"
          >
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}
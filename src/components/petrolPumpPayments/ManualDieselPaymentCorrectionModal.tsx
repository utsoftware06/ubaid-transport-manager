"use client";

import { useState, type FormEvent } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import type { ManualDieselCorrectionAction } from "@/lib/expenses/manualDieselPaymentCorrection";
import type { ManualDieselLinkedPaymentView } from "./manualDieselPaymentTypes";

type Props = {
  payment: ManualDieselLinkedPaymentView;
  isSaving: boolean;
  onCancel: () => void;
  onSubmit: (input: {
    action: ManualDieselCorrectionAction;
    reason: string;
    replacementDate?: string;
    replacementAmount?: string;
    replacementMethod?: string;
    replacementReference?: string;
    replacementRemarks?: string;
  }) => void;
};

export default function ManualDieselPaymentCorrectionModal({
  payment,
  isSaving,
  onCancel,
  onSubmit,
}: Props) {
  const { t, dir } = useLanguage();
  const [action, setAction] = useState<ManualDieselCorrectionAction>("void");
  const [reason, setReason] = useState("");
  const [replacementDate, setReplacementDate] = useState(payment.paymentDate);
  const [replacementAmount, setReplacementAmount] = useState(String(payment.paidAmount));
  const [replacementMethod, setReplacementMethod] = useState(payment.paymentMethod);
  const [replacementReference, setReplacementReference] = useState(payment.referenceNo ?? "");
  const [replacementRemarks, setReplacementRemarks] = useState(payment.paymentRemarks ?? "");

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!reason.trim()) return;
    onSubmit({
      action,
      reason,
      ...(action === "replace"
        ? { replacementDate, replacementAmount, replacementMethod, replacementReference, replacementRemarks }
        : {}),
    });
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center overflow-y-auto bg-slate-950/60 p-4" role="presentation">
      <form
        dir={dir}
        role="dialog"
        aria-modal="true"
        aria-labelledby="manual-diesel-correction-title"
        onSubmit={submit}
        className="my-auto w-full max-w-2xl space-y-4 rounded-2xl bg-white p-5 shadow-2xl sm:p-7"
      >
        <div>
          <h2 id="manual-diesel-correction-title" className="text-xl font-black text-slate-950">
            {t("petrolPumpPayments.correction.title")}
          </h2>
          <p className="mt-2 text-sm font-semibold text-slate-700">
            {payment.voucherNumber} · {payment.vehicleNo} · {t("petrolPumpPayments.correction.columns.diesel")} #{payment.dieselEntryId}
          </p>
          <p className="mt-1 text-sm text-slate-600">
            {t("petrolPumpPayments.correction.currentPayment")}: {payment.paymentDate} · Rs. {payment.paidAmount.toLocaleString("en-PK")} · {payment.paymentMethod}
          </p>
          <p className="mt-1 text-sm font-bold text-amber-800">
            {t("petrolPumpPayments.correction.paymentOnlyNotice")}
          </p>
        </div>

        <fieldset className="grid gap-3 sm:grid-cols-2">
          <legend className="mb-2 font-bold text-slate-900">{t("petrolPumpPayments.correction.action")}</legend>
          <label className="flex cursor-pointer items-start gap-3 rounded-lg border p-3">
            <input type="radio" name="manual-diesel-correction-action" value="void" checked={action === "void"} onChange={() => setAction("void")} />
            <span><strong className="block">{t("petrolPumpPayments.correction.void")}</strong><span className="text-sm text-slate-600">{t("petrolPumpPayments.correction.voidHelp")}</span></span>
          </label>
          <label className="flex cursor-pointer items-start gap-3 rounded-lg border p-3">
            <input type="radio" name="manual-diesel-correction-action" value="replace" checked={action === "replace"} onChange={() => setAction("replace")} />
            <span><strong className="block">{t("petrolPumpPayments.correction.replace")}</strong><span className="text-sm text-slate-600">{t("petrolPumpPayments.correction.replaceHelp")}</span></span>
          </label>
        </fieldset>

        {action === "replace" && (
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-sm font-bold text-slate-800">{t("petrolPumpPayments.fields.paymentDate")}
              <input type="date" required value={replacementDate} onChange={(event) => setReplacementDate(event.target.value)} className="mt-1 w-full rounded-lg border p-3" />
            </label>
            <label className="text-sm font-bold text-slate-800">{t("petrolPumpPayments.correction.replacementAmount")}
              <input type="number" required min="0.01" step="0.01" value={replacementAmount} onChange={(event) => setReplacementAmount(event.target.value)} className="mt-1 w-full rounded-lg border p-3" />
            </label>
            <label className="text-sm font-bold text-slate-800">{t("petrolPumpPayments.fields.paymentMethod")}
              <select required value={replacementMethod} onChange={(event) => setReplacementMethod(event.target.value)} className="mt-1 w-full rounded-lg border bg-white p-3">
                <option value="Cash">{t("petrolPumpPayments.paymentMethods.cash")}</option>
                <option value="Bank">{t("petrolPumpPayments.paymentMethods.bank")}</option>
                <option value="Cheque">{t("petrolPumpPayments.paymentMethods.cheque")}</option>
                <option value="Online Transfer">{t("petrolPumpPayments.paymentMethods.onlineTransfer")}</option>
              </select>
            </label>
            <label className="text-sm font-bold text-slate-800">{t("petrolPumpPayments.fields.reference")}
              <input value={replacementReference} onChange={(event) => setReplacementReference(event.target.value)} className="mt-1 w-full rounded-lg border p-3" />
            </label>
            <label className="text-sm font-bold text-slate-800 sm:col-span-2">{t("petrolPumpPayments.fields.remarks")}
              <textarea value={replacementRemarks} onChange={(event) => setReplacementRemarks(event.target.value)} rows={2} className="mt-1 w-full rounded-lg border p-3" />
            </label>
          </div>
        )}

        <label className="block text-sm font-bold text-slate-800">
          {t("petrolPumpPayments.correction.reasonRequired")}
          <textarea required maxLength={2000} value={reason} onChange={(event) => setReason(event.target.value)} rows={3} className="mt-1 w-full rounded-lg border p-3" />
        </label>
        <div className="flex flex-wrap justify-end gap-3">
          <button type="button" onClick={onCancel} disabled={isSaving} className="rounded-lg border px-4 py-2 font-bold disabled:opacity-60">{t("common.cancel")}</button>
          <button type="submit" disabled={isSaving || !reason.trim()} className="rounded-lg bg-red-700 px-4 py-2 font-bold text-white disabled:opacity-60">
            {isSaving ? t("petrolPumpPayments.correction.saving") : t("petrolPumpPayments.correction.confirm")}
          </button>
        </div>
      </form>
    </div>
  );
}

"use client";

import {
  type PetrolPumpOption,
  type PetrolPumpPaymentRow,
  type PetrolPumpPaymentMethod,
  formatAmount,
} from "./PetrolPumpPayments";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  paymentDate: string;
  setPaymentDate: (value: string) => void;
  petrolPumpId: string;
  setPetrolPumpId: (value: string) => void;
  advanceUsed: string;
  setAdvanceUsed: (value: string) => void;
  paymentNow: string;
  setPaymentNow: (value: string) => void;
  paymentMethod: PetrolPumpPaymentMethod;
  setPaymentMethod: (value: PetrolPumpPaymentMethod) => void;
  referenceNo: string;
  setReferenceNo: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  pumps: PetrolPumpOption[];
  selectedPump: PetrolPumpOption | null;
  editingPayment: PetrolPumpPaymentRow | null;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

const paymentMethods: PetrolPumpPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
];

function getStatus(payable: number, advance: number) {
  if (payable > 0) return "Payable";
  if (advance > 0) return "Advance";
  return "Paid";
}

function getStatusClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") return "border-green-200 bg-green-100 text-green-700";
  return "border-blue-200 bg-blue-100 text-blue-700";
}

export default function PetrolPumpPaymentForm({
  paymentDate,
  setPaymentDate,
  petrolPumpId,
  setPetrolPumpId,
  advanceUsed,
  setAdvanceUsed,
  paymentNow,
  setPaymentNow,
  paymentMethod,
  setPaymentMethod,
  referenceNo,
  setReferenceNo,
  remarks,
  setRemarks,
  pumps,
  selectedPump,
  editingPayment,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const { t, dir } = useLanguage();
  const availableAdvanceBefore = editingPayment
    ? editingPayment.availableAdvanceBefore
    : selectedPump?.advanceAmount ?? 0;
  const currentPayableBefore = editingPayment
    ? editingPayment.currentPayableBefore
    : selectedPump?.payableAmount ?? 0;
  const advanceUsedAmount = Number(advanceUsed || 0);
  const paymentNowAmount = Number(paymentNow || 0);
  const totalSettlement = advanceUsedAmount + paymentNowAmount;
  const payableAfterPayment = Math.max(
    currentPayableBefore - totalSettlement,
    0
  );
  const newAdvanceFromOverpayment = Math.max(
    totalSettlement - currentPayableBefore,
    0
  );
  const remainingExistingAdvance = Math.max(
    availableAdvanceBefore - advanceUsedAmount,
    0
  );
  const advanceAfterPayment =
    remainingExistingAdvance + newAdvanceFromOverpayment;
  const statusAfterPayment = getStatus(
    payableAfterPayment,
    advanceAfterPayment
  );

  return (
    <form
      dir={dir}
      onSubmit={(event) => {
        event.preventDefault();
        onSave();
      }}
      className="rounded-xl bg-white p-6 shadow-md md:p-8"
    >
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? t("petrolPumpPayments.actions.edit") : t("petrolPumpPayments.actions.add")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("petrolPumpPayments.formDescription")}
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            {t("common.cancelEdit")}
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">

        <div>
          <label htmlFor="petrol-pump-payment-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumpPayments.fields.paymentDate")}
          </label>
          <VoiceTypingField fieldLabel="petrol pump payment date" mode="date"><input
            id="petrol-pump-payment-date"
            type="date"
            dir="ltr"
            value={paymentDate}
            onChange={(event) => setPaymentDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="petrol-pump-payment-pump" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumpPayments.fields.pump")}
          </label>
          <select
            id="petrol-pump-payment-pump"
            value={petrolPumpId}
            disabled={isEditing}
            onChange={(event) => {
              const nextId = event.target.value;
              setPetrolPumpId(nextId);
              const nextPump = pumps.find((pump) => pump.id === nextId);
              setAdvanceUsed(
                String(
                  Math.min(
                    nextPump?.advanceAmount ?? 0,
                    nextPump?.payableAmount ?? 0
                  )
                )
              );
              setPaymentNow("0");
            }}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("petrolPumpPayments.placeholders.selectPump")}</option>
            {pumps.map((pump) => (
              <option key={pump.id} value={pump.id}>
                {pump.pumpName} - {pump.ownerName}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="petrol-pump-payment-advance-used" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumpPayments.fields.advanceUsed")}
          </label>
          <VoiceTypingField fieldLabel={t("petrolPumpPayments.fields.advanceUsed")} mode="amount"><input
            id="petrol-pump-payment-advance-used"
            type="number"
            min="0"
            max={Math.min(availableAdvanceBefore, currentPayableBefore)}
            value={advanceUsed}
            onChange={(event) => setAdvanceUsed(event.target.value)}
            placeholder="0"
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
          <p className="mt-2 text-sm font-semibold text-slate-700">
            {t("petrolPumpPayments.fields.availableAdvance")}:{" "}
            <span dir="ltr">{formatAmount(availableAdvanceBefore)}</span>
          </p>
        </div>



        <div>
          <label htmlFor="petrol-pump-payment-now" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumpPayments.fields.paymentNow")}
          </label>
          <VoiceTypingField fieldLabel={t("petrolPumpPayments.fields.paymentNow")} mode="amount"><input
            id="petrol-pump-payment-now"
            type="number"
            min="0"
            value={paymentNow}
            onChange={(event) => setPaymentNow(event.target.value)}
            placeholder="0"
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
          <p className="mt-2 text-sm font-semibold text-slate-700">
            {t("petrolPumpPayments.fields.currentPayable")}:{" "}
            <span dir="ltr">{formatAmount(currentPayableBefore)}</span>
          </p>
        </div>


        <div>
          <label htmlFor="petrol-pump-payment-method" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumpPayments.fields.paymentMethod")}
          </label>
          <select
            id="petrol-pump-payment-method"
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as PetrolPumpPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {paymentMethods.map((method) => (
              <option key={method} value={method}>
                {t(`petrolPumpPayments.paymentMethods.${method === "Online Transfer" ? "onlineTransfer" : method.toLowerCase()}`)}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="petrol-pump-payment-reference" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumpPayments.fields.reference")}
          </label>
          <VoiceTypingField fieldLabel={t("petrolPumpPayments.placeholders.reference")} mode="identifier"><input
            id="petrol-pump-payment-reference"
            type="text"
            value={referenceNo}
            onChange={(event) => setReferenceNo(event.target.value)}
            placeholder={t("petrolPumpPayments.placeholders.reference")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="petrol-pump-payment-remarks" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumpPayments.fields.remarks")}
          </label>
          <VoiceTypingField fieldLabel={t("petrolPumpPayments.fields.remarks")} value={remarks} onValueChange={setRemarks} contextKey={petrolPumpId}>
            <input
              id="petrol-pump-payment-remarks"
              type="text"
              value={remarks}
              onChange={(event) => setRemarks(event.target.value)}
              placeholder={t("petrolPumpPayments.placeholders.remarks")}
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>
      </div>

      {selectedPump && (
        <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("petrolPumps.fields.openingBalance")}</p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {formatAmount(selectedPump.openingBalance)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("petrolPumps.cards.totalDiesel")}</p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {formatAmount(selectedPump.totalDiesel)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">
              {t("petrolPumpPayments.fields.dieselPaid")}
            </p>
            <p className="mt-2 text-lg font-extrabold text-blue-700">
              {formatAmount(selectedPump.dieselPaid)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("petrolPumpPayments.fields.manualPayments")}</p>
            <p className="mt-2 text-lg font-extrabold text-green-700">
              {formatAmount(selectedPump.manualPayments)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("petrolPumpPayments.fields.currentBalance")}</p>
            <p
              className={`mt-2 text-lg font-extrabold ${
                selectedPump.currentBalance > 0
                  ? "text-red-700"
                  : selectedPump.currentBalance < 0
                    ? "text-green-700"
                    : "text-blue-700"
              }`}
            >
              {formatAmount(selectedPump.currentBalance)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("petrolPumpPayments.fields.status")}</p>
            <span
              className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                selectedPump.balanceStatus
              )}`}
            >
              {t(`petrolPumpPayments.statuses.${selectedPump.balanceStatus.toLowerCase()}`)}
            </span>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("petrolPumpPayments.fields.payableAmount")}</p>
            <p className="mt-2 text-lg font-extrabold text-red-700">
              {formatAmount(selectedPump.payableAmount)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("petrolPumpPayments.fields.advanceAmount")}</p>
            <p className="mt-2 text-lg font-extrabold text-green-700">
              {formatAmount(selectedPump.advanceAmount)}
            </p>
          </div>

          <div className="rounded-lg border border-blue-300 bg-blue-50 p-4 md:col-span-2 xl:col-span-4">
            <p className="text-lg font-extrabold text-gray-900">
              {t("petrolPumpPayments.fields.settlementSummary")}
            </p>
            <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
              {[
                ["availableAdvanceBefore", availableAdvanceBefore],
                ["currentPayableBefore", currentPayableBefore],
                ["advanceUsed", advanceUsedAmount],
                ["paymentNow", paymentNowAmount],
                ["totalSettlement", totalSettlement],
                ["remainingPayable", payableAfterPayment],
                ["remainingAdvance", advanceAfterPayment],
              ].map(([key, value]) => (
                <div key={String(key)} className="rounded-lg border border-slate-300 bg-white p-3">
                  <p className="text-sm font-bold text-slate-700">
                    {t(`petrolPumpPayments.fields.${key}`)}
                  </p>
                  <p dir="ltr" className="mt-1 text-lg font-extrabold text-slate-900">
                    {formatAmount(Number(value))}
                  </p>
                </div>
              ))}
              <div className="rounded-lg border border-slate-300 bg-white p-3">
                <p className="text-sm font-bold text-slate-700">
                  {t("petrolPumpPayments.fields.status")}
                </p>
                <span
                  className={`mt-2 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                    statusAfterPayment
                  )}`}
                >
                  {t(`petrolPumpPayments.statuses.${statusAfterPayment.toLowerCase()}`)}
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="mt-6 flex justify-end">
        <button
          type="submit"
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? t("common.saving")
            : isEditing
              ? t("petrolPumpPayments.actions.update")
              : t("petrolPumpPayments.actions.save")}
        </button>
      </div>
    </form>
  );
}

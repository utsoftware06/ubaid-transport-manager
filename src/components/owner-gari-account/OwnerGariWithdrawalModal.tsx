import { BanknoteArrowDown, X } from "lucide-react";
import { type FormEvent, useMemo, useState } from "react";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

import {
  OWNER_GARI_PAYMENT_METHODS,
  OWNER_GARI_WITHDRAWAL_TYPES,
  type OwnerGariPaymentMethod,
  type OwnerGariWithdrawalInput,
  type OwnerGariWithdrawalType,
  type VehicleOption,
} from "./types";

type Props = {
  vehicles: VehicleOption[];
  initialVehicleId: string;
  idempotencyKey: string;
  saving: boolean;
  onClose: () => void;
  onSubmit: (input: OwnerGariWithdrawalInput) => Promise<void>;
  t: (key: string) => string;
};

function today() {
  const value = new Date();
  const offset = value.getTimezoneOffset();
  return new Date(value.getTime() - offset * 60_000).toISOString().slice(0, 10);
}

export default function OwnerGariWithdrawalModal({
  vehicles,
  initialVehicleId,
  idempotencyKey,
  saving,
  onClose,
  onSubmit,
  t,
}: Props) {
  const [vehicleId, setVehicleId] = useState(initialVehicleId);
  const [withdrawalDate, setWithdrawalDate] = useState(today);
  const [withdrawalType, setWithdrawalType] =
    useState<OwnerGariWithdrawalType>("owner_withdrawal");
  const [amount, setAmount] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<OwnerGariPaymentMethod>("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");

  const selectedVehicle = useMemo(
    () => vehicles.find((vehicle) => vehicle.id === vehicleId) ?? null,
    [vehicleId, vehicles]
  );

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving) return;
    await onSubmit({
      vehicleId,
      withdrawalDate,
      withdrawalType,
      amount,
      paymentMethod,
      referenceNo,
      remarks,
      idempotencyKey,
    });
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/60 p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="owner-gari-withdrawal-title"
    >
      <form
        onSubmit={submit}
        className="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-2xl bg-white shadow-2xl"
      >
        <div className="flex items-center justify-between border-b border-slate-200 p-5">
          <div>
            <div className="mb-3 inline-flex rounded-xl bg-red-100 p-3 text-red-700">
              <BanknoteArrowDown size={24} />
            </div>
            <h2 id="owner-gari-withdrawal-title" className="text-2xl font-black text-slate-950">
              {t("ownerGariAccount.withdrawal.title")}
            </h2>
            <p className="mt-1 font-medium text-slate-600">
              {t("ownerGariAccount.withdrawal.cashbookNotice")}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            aria-label={t("common.actions.close")}
            className="rounded-lg p-2 text-slate-600 hover:bg-slate-100 disabled:opacity-50"
          >
            <X size={22} />
          </button>
        </div>

        <div className="grid gap-4 p-5 sm:grid-cols-2">
          <label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("ownerGariAccount.filters.vehicle")}</span>
            <select
              required
              value={vehicleId}
              onChange={(event) => setVehicleId(event.target.value)}
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            >
              <option value="">{t("ownerGariAccount.filters.selectVehicle")}</option>
              {vehicles.map((vehicle) => (
                <option key={vehicle.id} value={vehicle.id}>
                  {vehicle.vehicle_no || "—"}
                  {vehicle.owner_name ? ` — ${vehicle.owner_name}` : ""}
                </option>
              ))}
            </select>
          </label>

          <div className="rounded-xl border border-blue-200 bg-blue-50 p-4">
            <p className="text-xs font-black uppercase tracking-wide text-blue-600">
              {t("ownerGariAccount.table.owner")}
            </p>
            <p className="mt-2 font-black text-blue-950">
              {selectedVehicle?.owner_name?.trim() || "—"}
            </p>
          </div>


          <VoiceTypingField fieldLabel={t("ownerGariAccount.withdrawal.date")} mode="date"><label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("ownerGariAccount.withdrawal.date")}</span>
            <input
              required
              type="date"
              value={withdrawalDate}
              onChange={(event) => setWithdrawalDate(event.target.value)}
              className="w-full rounded-xl border border-slate-300 px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>


          <label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("ownerGariAccount.withdrawal.type")}</span>
            <select
              value={withdrawalType}
              onChange={(event) => setWithdrawalType(event.target.value as OwnerGariWithdrawalType)}
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            >
              {OWNER_GARI_WITHDRAWAL_TYPES.map((type) => (
                <option key={type} value={type}>
                  {t(`ownerGariAccount.transactionTypes.${type}`)}
                </option>
              ))}
            </select>
          </label>


          <VoiceTypingField fieldLabel={t("ownerGariAccount.withdrawal.amount")} mode="amount"><label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("ownerGariAccount.withdrawal.amount")}</span>
            <input
              required
              type="number"
              min="0.01"
              step="0.01"
              inputMode="decimal"
              value={amount}
              onChange={(event) => setAmount(event.target.value)}
              className="w-full rounded-xl border border-slate-300 px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>


          <label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("ownerGariAccount.withdrawal.paymentMethod")}</span>
            <select
              value={paymentMethod}
              onChange={(event) => setPaymentMethod(event.target.value as OwnerGariPaymentMethod)}
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            >
              {OWNER_GARI_PAYMENT_METHODS.map((method) => (
                <option key={method} value={method}>
                  {t(`ownerGariAccount.withdrawal.paymentMethods.${method}`)}
                </option>
              ))}
            </select>
          </label>


          <VoiceTypingField fieldLabel={t("ownerGariAccount.withdrawal.referenceNo")} mode="identifier"><label className="space-y-1 text-sm font-bold text-slate-700">
            <span>{t("ownerGariAccount.withdrawal.referenceNo")}</span>
            <input
              maxLength={200}
              value={referenceNo}
              onChange={(event) => setReferenceNo(event.target.value)}
              className="w-full rounded-xl border border-slate-300 px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>


          <label className="space-y-1 text-sm font-bold text-slate-700 sm:col-span-2">
            <span>{t("ownerGariAccount.withdrawal.remarks")}</span>
            <VoiceTypingField fieldLabel={t("ownerGariAccount.withdrawal.remarks")} value={remarks} onValueChange={setRemarks} contextKey={vehicleId}>
              <textarea
                rows={3}
                maxLength={2000}
                value={remarks}
                onChange={(event) => setRemarks(event.target.value)}
                className="w-full rounded-xl border border-slate-300 px-3 py-3 text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              />
            </VoiceTypingField>
          </label>
        </div>

        <div className="flex justify-end gap-3 border-t border-slate-200 p-5">
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            className="rounded-xl border border-slate-300 px-4 py-3 font-bold text-slate-700 hover:bg-slate-50 disabled:opacity-50"
          >
            {t("common.actions.cancel")}
          </button>
          <button
            type="submit"
            disabled={saving || !vehicleId || !withdrawalDate || Number(amount) <= 0}
            className="inline-flex items-center gap-2 rounded-xl bg-red-700 px-5 py-3 font-black text-white hover:bg-red-800 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <BanknoteArrowDown size={18} />
            {saving
              ? t("ownerGariAccount.withdrawal.saving")
              : t("ownerGariAccount.withdrawal.save")}
          </button>
        </div>
      </form>
    </div>
  );
}

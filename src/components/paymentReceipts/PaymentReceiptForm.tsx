import type { PaymentReceiptLoading } from "@/types/paymentReceipts";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  loadingId: string;
  setLoadingId: (value: string) => void;
  receiptNo: string;
  setReceiptNo: (value: string) => void;
  receiptDate: string;
  setReceiptDate: (value: string) => void;
  amount: string;
  setAmount: (value: string) => void;
  paymentMethod: string;
  setPaymentMethod: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  loadings: PaymentReceiptLoading[];
  onSave: () => void;
  onCancel: () => void;
  isEditing: boolean;
  lockLoading: boolean;
  isSaving: boolean;
};

function formatAmount(value: number | string | null | undefined) {
  return Number(value ?? 0).toLocaleString("en-PK");
}

export default function PaymentReceiptForm({
  loadingId,
  setLoadingId,
  receiptNo,
  setReceiptNo,
  receiptDate,
  setReceiptDate,
  amount,
  setAmount,
  paymentMethod,
  setPaymentMethod,
  remarks,
  setRemarks,
  loadings,
  onSave,
  onCancel,
  isEditing,
  lockLoading,
  isSaving,
}: Props) {
  const { t, dir } = useLanguage();
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <h2 className="mb-6 text-2xl font-bold text-gray-900">
        {t(isEditing ? "paymentReceipts.edit" : "paymentReceipts.create")}
      </h2>




      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        <VoiceTypingField fieldLabel={t("paymentReceipts.receiptNo")} mode="identifier"><input
          aria-label={t("paymentReceipts.receiptNo")}
          dir="ltr"
          placeholder={t("paymentReceipts.receiptNo")}
          value={receiptNo}
          onChange={(e) => setReceiptNo(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        /></VoiceTypingField>

        <VoiceTypingField fieldLabel={t("common.date")} mode="date"><input
          type="date"
          aria-label={t("common.date")}
          dir="ltr"
          value={receiptDate}
          onChange={(e) => setReceiptDate(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        /></VoiceTypingField>

        <select
          aria-label={t("paymentReceipts.selectLoading")}
          value={loadingId}
          onChange={(e) => setLoadingId(e.target.value)}
          disabled={isSaving || lockLoading}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 md:col-span-2"
        >
          <option value="">{t("paymentReceipts.selectLoading")}</option>

          {loadings.map((loading) => {
            const booking = loading.bookings;

            return (
              <option key={loading.id} value={loading.id}>
                {loading.loading_no ?? "-"} |{" "}
                {booking?.parties?.name ?? booking?.sender_name ?? "-"} |
                {t("common.freight")} Rs. {formatAmount(booking?.freight)} | {t("common.remaining")} Rs.{" "}
                {formatAmount(loading.remaining_amount)}
              </option>
            );
          })}
        </select>

        <VoiceTypingField fieldLabel={t("paymentReceipts.receivedAmount")} mode="amount"><input
          type="number"
          aria-label={t("paymentReceipts.receivedAmount")}
          dir="ltr"
          min="0"
          step="any"
          placeholder={t("paymentReceipts.receivedAmount")}
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        /></VoiceTypingField>

        <select
          aria-label={t("paymentReceipts.method")}
          value={paymentMethod}
          onChange={(e) => setPaymentMethod(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        >
          <option value="Cash">{t("paymentReceipts.paymentMethods.cash")}</option>
          <option value="Bank">{t("paymentReceipts.paymentMethods.bank")}</option>
          <option value="Cheque">{t("paymentReceipts.paymentMethods.cheque")}</option>
          <option value="Online Transfer">
            {t("paymentReceipts.paymentMethods.onlineTransfer")}
          </option>
          <option value="Account">{t("paymentReceipts.paymentMethods.account")}</option>
        </select>

        <VoiceTypingField fieldLabel={t("common.remarks")} value={remarks} onValueChange={setRemarks} contextKey={loadingId}>
          <textarea
            aria-label={t("common.remarks")}
            placeholder={t("common.remarks")}
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            disabled={isSaving}
              className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 md:col-span-2"
          />
        </VoiceTypingField>

      </div>


      <div className="mt-6 flex flex-wrap gap-3">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-6 py-3 font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
        >
          {isSaving
            ? t("common.saving")
            : t(isEditing ? "common.actions.update" : "paymentReceipts.save")}
        </button>
        {isEditing && (
          <button type="button" onClick={onCancel} disabled={isSaving} className="rounded-lg border border-gray-300 bg-white px-6 py-3 font-bold">
            {t("common.actions.cancel")}
          </button>
        )}
      </div>
    </div>
  );
}

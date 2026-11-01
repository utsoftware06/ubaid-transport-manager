import type { PackingLoadingRecord as LoadingRecord } from "@/types/packing";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type PackingFormProps = {
  packingSlipNo: string;
  setPackingSlipNo: (value: string) => void;
  packingDate: string;
  setPackingDate: (value: string) => void;
  loadingId: string;
  setLoadingId: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  loadings: LoadingRecord[];
  selectedLoading: LoadingRecord | null;
  onSave: () => void;
  isSaving?: boolean;
  isEditing?: boolean;
  onCancelEdit?: () => void;
};

export default function PackingForm({
  packingSlipNo,
  setPackingSlipNo,
  packingDate,
  setPackingDate,
  loadingId,
  setLoadingId,
  remarks,
  setRemarks,
  loadings,
  selectedLoading,
  onSave,
  isSaving = false,
  isEditing = false,
  onCancelEdit,
}: PackingFormProps) {
  const { t, dir } = useLanguage();
  return (
    <div dir={dir}>
      <div className="mb-8 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-3xl font-bold text-gray-900">
            {isEditing ? t("packing.edit") : t("packing.create")}
          </h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            {t("packing.formDescription")}
          </p>
        </div>

        {isEditing && onCancelEdit && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-semibold text-gray-900 transition hover:bg-gray-50"
          >
            {t("common.cancelEdit")}
          </button>
        )}
      </div>



      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        <VoiceTypingField fieldLabel={t("packing.slipNumber")} mode="identifier"><input
          type="text"
          dir="ltr"
          placeholder={t("packing.slipNumber")}
          value={packingSlipNo}
          onChange={(event) => setPackingSlipNo(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        /></VoiceTypingField>

        <VoiceTypingField fieldLabel={t("packing.date")} mode="date"><input
          type="date"
          dir="ltr"
          value={packingDate}
          onChange={(event) => setPackingDate(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        /></VoiceTypingField>

        <select
          value={loadingId}
          onChange={(event) => setLoadingId(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 md:col-span-2"
        >
          <option value="">{t("packing.selectLoading")}</option>
          {loadings.map((loading) => (
            <option key={loading.id} value={loading.id}>
              {loading.loading_no} - {loading.vehicles?.vehicle_no ?? t("packing.noVehicle")} -{" "}
              {loading.route}
            </option>
          ))}
        </select>

        <VoiceTypingField fieldLabel={t("common.remarks")} value={remarks} onValueChange={setRemarks} contextKey={loadingId}>
        <textarea
          placeholder={t("common.remarks")}
          value={remarks}
          onChange={(event) => setRemarks(event.target.value)}
          rows={3}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 md:col-span-2"
        />
        </VoiceTypingField>

      </div>


      {selectedLoading && (
        <div className="mt-8 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("common.vehicle")}</p>
            <p dir="ltr" className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.vehicles?.vehicle_no ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("common.driver")}</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.drivers?.name ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("common.route")}</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.route || "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
            <p className="text-sm font-bold text-gray-900">{t("common.loadingDate")}</p>
            <p dir="ltr" className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.loading_date || "-"}
            </p>
          </div>
        </div>
      )}

      <button
        type="button"
        onClick={onSave}
        disabled={isSaving}
        className="mt-8 rounded-lg bg-blue-600 px-8 py-3 font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
      >
        {isSaving
          ? t("common.saving")
          : isEditing
            ? t("packing.update")
            : t("packing.save")}
      </button>
    </div>
  );
}

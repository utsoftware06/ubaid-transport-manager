import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import type { LoadingItem, LoadingRecord } from "@/types/loading";

type LoadingItemsProps = {
  loadingId: string;
  selectedLoading: LoadingRecord | null;
  itemName: string;
  setItemName: (value: string) => void;
  quantity: string;
  setQuantity: (value: string) => void;
  weight: string;
  setWeight: (value: string) => void;
  unit: string;
  setUnit: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  loadingItems: LoadingItem[];
  onAddItem: () => void;
  onEditItem: (item: LoadingItem) => void;
  onDeleteItem: (item: LoadingItem) => void;
  onCancelEdit: () => void;
  isEditing: boolean;
  isSaving?: boolean;
};

export default function LoadingItems({
  loadingId,
  selectedLoading,
  itemName,
  setItemName,
  quantity,
  setQuantity,
  weight,
  setWeight,
  unit,
  setUnit,
  remarks,
  setRemarks,
  loadingItems,
  onAddItem,
  onEditItem,
  onDeleteItem,
  onCancelEdit,
  isEditing,
  isSaving = false,
}: LoadingItemsProps) {
  const { t, dir } = useLanguage();
  const totalQuantity = loadingItems.reduce(
    (total, item) => total + Number(item.quantity || 0),
    0
  );
  const totalWeight = loadingItems.reduce(
    (total, item) => total + Number(item.weight || 0),
    0
  );

  return (
    <div dir={dir} className="mt-10 rounded-xl border border-gray-300 bg-white p-6 shadow-md">
      <div className="mb-6 flex flex-col justify-between gap-3 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">{t("loadings.items.addTitle")}</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("loadings.items.currentLoading")}: <span dir="ltr">{selectedLoading?.loading_no ?? loadingId}</span>
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3 text-sm font-semibold text-gray-900 md:grid-cols-4">
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            {t("loadings.items.items")}: {loadingItems.length}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            {t("loadings.items.qty")}: {totalQuantity}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            {t("common.weight")}: {totalWeight}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            {t("common.unit")}: {unit}
          </div>
        </div>
      </div>



      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
        <VoiceTypingField fieldLabel={t("loadings.items.itemName")} value={itemName} onValueChange={setItemName} contextKey={loadingId}>
          <input
            type="text"
            aria-label={t("loadings.items.itemName")}
            placeholder={t("loadings.items.itemName")}
            value={itemName}
            onChange={(event) => setItemName(event.target.value)}
            className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
          />
        </VoiceTypingField>

        <VoiceTypingField fieldLabel={t("common.quantity")} mode="number"><input
          type="number"
          aria-label={t("common.quantity")}
          min="0"
          step="any"
          placeholder={t("common.quantity")}
          value={quantity}
          onChange={(event) => setQuantity(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        /></VoiceTypingField>

        <VoiceTypingField fieldLabel={t("common.weight")} mode="number"><input
          type="number"
          aria-label={t("common.weight")}
          min="0"
          step="any"
          placeholder={t("common.weight")}
          value={weight}
          onChange={(event) => setWeight(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        /></VoiceTypingField>

        <select
          aria-label={t("common.unit")}
          value={unit}
          onChange={(event) => setUnit(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        >
          <option value="Kg">{t("loadings.units.kg")}</option>
          <option value="Ton">{t("loadings.units.ton")}</option>
          <option value="Bag">{t("loadings.units.bag")}</option>
          <option value="Piece">{t("loadings.units.piece")}</option>
          <option value="Carton">{t("loadings.units.carton")}</option>
        </select>

        <VoiceTypingField fieldLabel={t("common.remarks")} value={remarks} onValueChange={setRemarks} contextKey={loadingId}>
          <input
            type="text"
            aria-label={t("common.remarks")}
            placeholder={t("common.remarks")}
            value={remarks}
            onChange={(event) => setRemarks(event.target.value)}
            className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
          />
        </VoiceTypingField>

      </div>


      <div className="mt-6 flex flex-wrap gap-3">
        <button
          type="button"
          onClick={onAddItem}
          disabled={isSaving}
          className="rounded-lg bg-green-600 px-6 py-3 font-semibold text-white transition hover:bg-green-700 disabled:cursor-not-allowed disabled:bg-green-400"
        >
          {isSaving
            ? t("loadings.items.adding")
            : t(isEditing ? "loadings.items.update" : "loadings.items.add")}
        </button>
        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            disabled={isSaving}
            className="rounded-lg border border-gray-300 bg-white px-6 py-3 font-semibold"
          >
            {t("common.actions.cancel")}
          </button>
        )}
      </div>

      {loadingItems.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-lg border border-gray-200">
          <table className="w-full min-w-[720px] bg-white text-sm">
            <thead className="bg-green-700 text-white">
              <tr>
                <th className="p-3 text-start">{t("common.item")}</th>
                <th className="p-3 text-end">{t("common.quantity")}</th>
                <th className="p-3 text-end">{t("common.weight")}</th>
                <th className="p-3 text-start">{t("common.unit")}</th>
                <th className="p-3 text-start">{t("common.actions.title")}</th>
              </tr>
            </thead>
            <tbody>
              {loadingItems.map((item) => (
                <tr key={item.id} className="border-b">
                  <td className="p-3">{item.item_name}</td>
                  <td dir="ltr" className="p-3 text-end">{item.quantity}</td>
                  <td dir="ltr" className="p-3 text-end">{item.weight}</td>
                  <td className="p-3">{t(`loadings.units.${item.unit.toLowerCase()}`)}</td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-2">
                      <button type="button" aria-label={`${t("common.actions.edit")} ${item.item_name}`} disabled={isSaving} onClick={() => onEditItem(item)} className="rounded bg-blue-600 px-3 py-2 font-semibold text-white">{t("common.actions.edit")}</button>
                      <button type="button" aria-label={`${t("common.actions.delete")} ${item.item_name}`} disabled={isSaving} onClick={() => onDeleteItem(item)} className="rounded bg-red-600 px-3 py-2 font-semibold text-white">{t("common.actions.delete")}</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

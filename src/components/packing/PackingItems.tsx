import type {
  PackingLoadingItem as LoadingItem,
  PackingLoadingRecord as LoadingRecord,
} from "@/types/packing";
import { useLanguage } from "@/contexts/LanguageContext";

type PackingItemsProps = {
  selectedLoading: LoadingRecord | null;
  loadingItems: LoadingItem[];
};

function getUnitLabel(unit: string, t: (key: string) => string): string {
  const unitKey = {
    Kg: "kg",
    Ton: "ton",
    Bag: "bag",
    Piece: "piece",
  }[unit];

  return unitKey ? t(`packing.units.${unitKey}`) : unit;
}

export default function PackingItems({
  selectedLoading,
  loadingItems,
}: PackingItemsProps) {
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
          <h2 className="text-2xl font-bold text-gray-900">{t("packing.items.title")}</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("packing.items.loadedFrom")}:{" "}
            {selectedLoading?.loading_no ?? "-"}
          </p>
        </div>

        <div className="grid grid-cols-1 gap-3 text-sm font-semibold text-gray-900 sm:grid-cols-3">
          <div className="rounded-lg border border-gray-300 bg-white px-4 py-3 shadow-sm">
            {t("common.items")}: <span dir="ltr">{loadingItems.length}</span>
          </div>
          <div className="rounded-lg border border-gray-300 bg-white px-4 py-3 shadow-sm">
            {t("packing.items.qty")}: <span dir="ltr">{totalQuantity}</span>
          </div>
          <div className="rounded-lg border border-gray-300 bg-white px-4 py-3 shadow-sm">
            {t("common.weight")}: <span dir="ltr">{totalWeight}</span>
          </div>
        </div>
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-300 bg-white">
        <table className="w-full min-w-[760px] border-collapse text-sm text-gray-900">
          <thead className="bg-green-600 text-white">
            <tr>
              <th className="p-3 text-start font-bold">{t("packing.items.itemName")}</th>
              <th className="p-3 text-end font-bold">{t("common.quantity")}</th>
              <th className="p-3 text-end font-bold">{t("common.weight")}</th>
              <th className="p-3 text-start font-bold">{t("common.unit")}</th>
              <th className="p-3 text-start font-bold">{t("common.remarks")}</th>
            </tr>
          </thead>

          <tbody className="bg-white text-gray-900">
            {loadingItems.length === 0 && (
              <tr>
                <td
                  colSpan={5}
                  className="p-6 text-center text-base font-semibold text-gray-900"
                >
                  {t("packing.items.empty")}
                </td>
              </tr>
            )}

            {loadingItems.map((item) => (
              <tr
                key={item.id}
                className="border-b border-gray-200 hover:bg-gray-50"
              >
                <td className="p-3 font-semibold text-gray-900">
                  {item.item_name}
                </td>
                <td dir="ltr" className="p-3 text-end font-semibold text-gray-900">
                  {item.quantity}
                </td>
                <td dir="ltr" className="p-3 text-end font-semibold text-gray-900">
                  {item.weight}
                </td>
                <td className="p-3 font-semibold text-gray-900">
                  {getUnitLabel(item.unit, t)}
                </td>
                <td className="p-3 font-semibold text-gray-900">
                  {item.remarks || "-"}
                </td>
              </tr>
            ))}
          </tbody>

          {loadingItems.length > 0 && (
            <tfoot className="border-t-2 border-gray-300 bg-white text-gray-900">
              <tr>
                <td className="p-3 font-bold">{t("common.total")}</td>
                <td dir="ltr" className="p-3 text-end font-bold">{totalQuantity}</td>
                <td dir="ltr" className="p-3 text-end font-bold">{totalWeight}</td>
                <td className="p-3 font-bold" colSpan={2}></td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </div>
  );
}

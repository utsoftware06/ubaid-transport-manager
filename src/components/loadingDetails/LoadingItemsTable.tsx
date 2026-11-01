"use client";

import type { LoadingGoodsItem } from "./LoadingDetails";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = {
  items: LoadingGoodsItem[];
};

export default function LoadingItemsTable({ items }: Props) {
  const { t, dir } = useLanguage();
  return (
    <section dir={dir} className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <div className="mb-4">
        <h2 className="text-lg font-extrabold text-slate-900">
          {t("loadings.details.itemsTitle")}
        </h2>
        <p className="mt-1 text-sm font-medium text-slate-600">
          {t("loadings.details.itemsDescription")}
        </p>
      </div>

      {items.length === 0 ? (
        <div className="rounded-xl border border-slate-200 bg-slate-50 p-6 text-center">
          <p className="font-semibold text-slate-700">
            {t("loadings.details.noItems")}
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-slate-200">
          <table className="min-w-full border-collapse text-sm text-slate-800">
            <thead>
              <tr className="bg-slate-50 text-slate-700">
                <th className="border-b border-slate-200 px-4 py-2.5 text-start font-bold">
                  {t("common.item")}
                </th>
                <th className="border-b border-slate-200 px-4 py-2.5 text-end font-bold">
                  {t("common.quantity")}
                </th>
                <th className="border-b border-slate-200 px-4 py-2.5 text-end font-bold">
                  {t("common.weight")}
                </th>
                <th className="border-b border-slate-200 px-4 py-2.5 text-start font-bold">
                  {t("common.unit")}
                </th>
                <th className="border-b border-slate-200 px-4 py-2.5 text-start font-bold">
                  {t("common.remarks")}
                </th>
              </tr>
            </thead>

            <tbody className="divide-y divide-slate-100 bg-white text-slate-800">
              {items.map((item) => (
                <tr
                  key={item.id}
                  className="bg-white text-slate-800 transition-colors hover:bg-blue-50/40"
                >
                  <td className="px-4 py-2.5 font-semibold text-slate-900">
                    {item.itemName}
                  </td>
                  <td className="px-4 py-2.5 text-end font-semibold text-slate-900" dir="ltr">
                    {item.quantity || "-"}
                  </td>
                  <td className="px-4 py-2.5 text-end font-semibold text-slate-900" dir="ltr">
                    {item.weight || "-"}
                  </td>
                  <td className="px-4 py-2.5 font-semibold text-slate-900">
                    {item.unit}
                  </td>
                  <td className="px-4 py-2.5 font-semibold text-slate-900">
                    {item.remarks}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

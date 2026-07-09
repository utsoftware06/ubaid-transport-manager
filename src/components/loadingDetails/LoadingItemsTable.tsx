"use client";

import type { LoadingGoodsItem } from "./LoadingDetails";

type Props = {
  items: LoadingGoodsItem[];
};

export default function LoadingItemsTable({ items }: Props) {
  return (
    <section className="rounded-xl bg-white p-6 shadow-md">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-gray-900">
          Loading Items
        </h2>
        <p className="mt-1 text-sm font-medium text-gray-700">
          Goods, quantity, weight aur remarks ki detail.
        </p>
      </div>

      {items.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center">
          <p className="font-semibold text-gray-900">
            No loading items found.
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full border-collapse text-sm text-gray-900">
            <thead>
              <tr className="bg-gray-100 text-gray-900">
                <th className="border border-gray-300 px-4 py-3 text-left font-bold">
                  Item
                </th>
                <th className="border border-gray-300 px-4 py-3 text-right font-bold">
                  Quantity
                </th>
                <th className="border border-gray-300 px-4 py-3 text-right font-bold">
                  Weight
                </th>
                <th className="border border-gray-300 px-4 py-3 text-left font-bold">
                  Unit
                </th>
                <th className="border border-gray-300 px-4 py-3 text-left font-bold">
                  Remarks
                </th>
              </tr>
            </thead>

            <tbody className="bg-white text-gray-900">
              {items.map((item) => (
                <tr
                  key={item.id}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {item.itemName}
                  </td>
                  <td className="border border-gray-200 px-4 py-3 text-right font-semibold text-gray-900">
                    {item.quantity || "-"}
                  </td>
                  <td className="border border-gray-200 px-4 py-3 text-right font-semibold text-gray-900">
                    {item.weight || "-"}
                  </td>
                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
                    {item.unit}
                  </td>
                  <td className="border border-gray-200 px-4 py-3 font-semibold text-gray-900">
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
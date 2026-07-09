type LoadingItem = {
  id: number;
  loading_id: number;
  item_name: string;
  quantity: number;
  weight: number;
  unit: string;
  remarks: string | null;
};

type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  vehicles?: {
    vehicle_no: string;
  } | null;
  drivers?: {
    name: string;
  } | null;
};

type PackingItemsProps = {
  selectedLoading: LoadingRecord | null;
  loadingItems: LoadingItem[];
};

export default function PackingItems({
  selectedLoading,
  loadingItems,
}: PackingItemsProps) {
  const totalQuantity = loadingItems.reduce(
    (total, item) => total + Number(item.quantity || 0),
    0
  );
  const totalWeight = loadingItems.reduce(
    (total, item) => total + Number(item.weight || 0),
    0
  );

  return (
    <div className="mt-10 rounded-xl border border-gray-200 bg-gray-50 p-6">
      <div className="mb-6 flex flex-col justify-between gap-3 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Packing Items</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Items loaded automatically from Loading:{" "}
            {selectedLoading?.loading_no ?? "-"}
          </p>
        </div>

        <div className="grid grid-cols-1 gap-3 text-sm font-semibold text-gray-900 sm:grid-cols-3">
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            Items: {loadingItems.length}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            Qty: {totalQuantity}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            Weight: {totalWeight}
          </div>
        </div>
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
        <table className="w-full min-w-[760px] border-collapse text-sm text-gray-900">
          <thead className="bg-green-600 text-white">
            <tr>
              <th className="p-3 text-left font-bold">Item Name</th>
              <th className="p-3 text-right font-bold">Quantity</th>
              <th className="p-3 text-right font-bold">Weight</th>
              <th className="p-3 text-left font-bold">Unit</th>
              <th className="p-3 text-left font-bold">Remarks</th>
            </tr>
          </thead>

          <tbody className="bg-white text-gray-900">
            {loadingItems.length === 0 && (
              <tr>
                <td
                  colSpan={5}
                  className="p-6 text-center text-base font-semibold text-gray-900"
                >
                  No loading items found.
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
                <td className="p-3 text-right font-semibold text-gray-900">
                  {item.quantity}
                </td>
                <td className="p-3 text-right font-semibold text-gray-900">
                  {item.weight}
                </td>
                <td className="p-3 font-semibold text-gray-900">{item.unit}</td>
                <td className="p-3 font-semibold text-gray-900">
                  {item.remarks || "-"}
                </td>
              </tr>
            ))}
          </tbody>

          {loadingItems.length > 0 && (
            <tfoot className="bg-gray-50 text-gray-900">
              <tr>
                <td className="p-3 font-bold">Total</td>
                <td className="p-3 text-right font-bold">{totalQuantity}</td>
                <td className="p-3 text-right font-bold">{totalWeight}</td>
                <td className="p-3 font-bold" colSpan={2}></td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </div>
  );
}
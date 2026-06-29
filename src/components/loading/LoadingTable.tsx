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
  loading_items?: LoadingItem[];
};

type LoadingTableProps = {
  loadings: LoadingRecord[];
  search: string;
  setSearch: (value: string) => void;
  onView: (loading: LoadingRecord) => void;
  onEdit: (loading: LoadingRecord) => void;
  onDelete: (loading: LoadingRecord) => void;
  onPrint: (loading: LoadingRecord) => void;
  isDeleting?: boolean;
};

export default function LoadingTable({
  loadings,
  search,
  setSearch,
  onView,
  onEdit,
  onDelete,
  onPrint,
  isDeleting = false,
}: LoadingTableProps) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">My Loadings</h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            Complete loading records with goods and actions.
          </p>
        </div>

        <input
          type="text"
          placeholder="Search Loading, Vehicle, Driver, Route or Item..."
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        />
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-200">
        <table className="w-full min-w-[1180px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-left font-bold">Loading No</th>
              <th className="p-3 text-left font-bold">Date</th>
              <th className="p-3 text-left font-bold">Vehicle</th>
              <th className="p-3 text-left font-bold">Driver</th>
              <th className="p-3 text-left font-bold">Route</th>
              <th className="p-3 text-left font-bold">Item</th>
              <th className="p-3 text-right font-bold">Quantity</th>
              <th className="p-3 text-right font-bold">Weight</th>
              <th className="p-3 text-left font-bold">Unit</th>
              <th className="p-3 text-left font-bold">Remarks</th>
              <th className="p-3 text-left font-bold">Actions</th>
            </tr>
          </thead>

          <tbody className="bg-white text-gray-900">
            {loadings.length === 0 && (
              <tr>
                <td
                  colSpan={11}
                  className="p-8 text-center text-base font-semibold text-gray-900"
                >
                  No loading records found.
                </td>
              </tr>
            )}

            {loadings.map((loading) => {
              const items = loading.loading_items ?? [];
              const rows =
                items.length > 0
                  ? items
                  : [
                      {
                        id: 0,
                        loading_id: loading.id,
                        item_name: "-",
                        quantity: 0,
                        weight: 0,
                        unit: "-",
                        remarks: "-",
                      },
                    ];

              return rows.map((item, index) => {
                const isFirstRow = index === 0;
                const rowSpan = rows.length;

                return (
                  <tr
                    key={`${loading.id}-${item.id}-${index}`}
                    className="border-b border-gray-200 hover:bg-gray-50"
                  >
                    {isFirstRow && (
                      <>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-bold text-gray-900"
                        >
                          {loading.loading_no}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {loading.loading_date}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {loading.vehicles?.vehicle_no ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {loading.drivers?.name ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {loading.route}
                        </td>
                      </>
                    )}

                    <td className="p-3 font-semibold text-gray-900">
                      {item.item_name}
                    </td>
                    <td className="p-3 text-right font-semibold text-gray-900">
                      {item.quantity || "-"}
                    </td>
                    <td className="p-3 text-right font-semibold text-gray-900">
                      {item.weight || "-"}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {item.unit}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {item.remarks || "-"}
                    </td>

                    {isFirstRow && (
                      <td
                        rowSpan={rowSpan}
                        className="min-w-[220px] p-3 align-top"
                      >
                        <div className="flex flex-wrap gap-2">
                          <button
                            type="button"
                            onClick={() => onView(loading)}
                            className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                          >
                            👁 View
                          </button>

                          <button
                            type="button"
                            onClick={() => onEdit(loading)}
                            className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                          >
                            ✏ Edit
                          </button>

                          <button
                            type="button"
                            onClick={() => onDelete(loading)}
                            disabled={isDeleting}
                            className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-400"
                          >
                            🗑 Delete
                          </button>

                          <button
                            type="button"
                            onClick={() => onPrint(loading)}
                            className="rounded-lg bg-green-600 px-3 py-2 font-semibold text-white transition hover:bg-green-700"
                          >
                            🖨 Print Loading Slip
                          </button>
                        </div>
                      </td>
                    )}
                  </tr>
                );
              });
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
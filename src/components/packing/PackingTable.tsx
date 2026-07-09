type PackingSlipItem = {
  id: number;
  packing_slip_id: number;
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

type PackingSlipRecord = {
  id: number;
  packing_slip_no: string;
  packing_date: string;
  loading_id: number | string;
  remarks: string | null;
  loadings?: LoadingRecord | null;
  packing_slip_items?: PackingSlipItem[];
};

type PackingTableProps = {
  packingSlips: PackingSlipRecord[];
  search: string;
  setSearch: (value: string) => void;
  onView: (packingSlip: PackingSlipRecord) => void;
  onEdit: (packingSlip: PackingSlipRecord) => void;
  onDelete: (packingSlip: PackingSlipRecord) => void;
  onPrint: (packingSlip: PackingSlipRecord) => void;
  isDeleting?: boolean;
};

export default function PackingTable({
  packingSlips,
  search,
  setSearch,
  onView,
  onEdit,
  onDelete,
  onPrint,
  isDeleting = false,
}: PackingTableProps) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Packing Slips</h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            Complete packing records with loading, goods, and actions.
          </p>
        </div>

        <input
          type="text"
          placeholder="Search Packing Slip, Loading, Vehicle, Driver, Route or Item..."
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        />
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-200">
        <table className="w-full min-w-[1280px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-left font-bold">Packing Slip No</th>
              <th className="p-3 text-left font-bold">Packing Date</th>
              <th className="p-3 text-left font-bold">Loading No</th>
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
            {packingSlips.length === 0 && (
              <tr>
                <td
                  colSpan={12}
                  className="p-8 text-center text-base font-semibold text-gray-900"
                >
                  No packing slip records found.
                </td>
              </tr>
            )}

            {packingSlips.map((packingSlip) => {
              const items = packingSlip.packing_slip_items ?? [];
              const rows =
                items.length > 0
                  ? items
                  : [
                      {
                        id: 0,
                        packing_slip_id: packingSlip.id,
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
                    key={`${packingSlip.id}-${item.id}-${index}`}
                    className="border-b border-gray-200 hover:bg-gray-50"
                  >
                    {isFirstRow && (
                      <>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-bold text-gray-900"
                        >
                          {packingSlip.packing_slip_no}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.packing_date}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.loading_no ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.vehicles?.vehicle_no ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.drivers?.name ?? "-"}
                        </td>
                        <td
                          rowSpan={rowSpan}
                          className="border-r border-gray-200 p-3 align-top font-semibold text-gray-900"
                        >
                          {packingSlip.loadings?.route ?? "-"}
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
                      {item.remarks || packingSlip.remarks || "-"}
                    </td>

                    {isFirstRow && (
                      <td
                        rowSpan={rowSpan}
                        className="min-w-[230px] p-3 align-top"
                      >
                        <div className="flex flex-wrap gap-2">
                          <button
                            type="button"
                            onClick={() => onView(packingSlip)}
                            className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                          >
                            👁 View
                          </button>

                          <button
                            type="button"
                            onClick={() => onEdit(packingSlip)}
                            className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                          >
                            ✏ Edit
                          </button>

                          <button
                            type="button"
                            onClick={() => onDelete(packingSlip)}
                            disabled={isDeleting}
                            className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-400"
                          >
                            🗑 Delete
                          </button>

                          <button
                            type="button"
                            onClick={() => onPrint(packingSlip)}
                            className="rounded-lg bg-green-600 px-3 py-2 font-semibold text-white transition hover:bg-green-700"
                          >
                            🖨 Print Packing Slip
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
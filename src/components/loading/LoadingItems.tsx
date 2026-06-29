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

type LoadingItemsProps = {
  loadingId: number;
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
  isSaving = false,
}: LoadingItemsProps) {
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
          <h2 className="text-2xl font-bold text-gray-900">Add Loading Item</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Current Loading: {selectedLoading?.loading_no ?? loadingId}
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3 text-sm font-semibold text-gray-900 md:grid-cols-4">
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            Items: {loadingItems.length}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            Qty: {totalQuantity}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            Weight: {totalWeight}
          </div>
          <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
            Unit: {unit}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
        <input
          type="text"
          placeholder="Item Name"
          value={itemName}
          onChange={(event) => setItemName(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        />

        <input
          type="number"
          placeholder="Quantity"
          value={quantity}
          onChange={(event) => setQuantity(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        />

        <input
          type="number"
          placeholder="Weight"
          value={weight}
          onChange={(event) => setWeight(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        />

        <select
          value={unit}
          onChange={(event) => setUnit(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        >
          <option>Kg</option>
          <option>Ton</option>
          <option>Bag</option>
          <option>Piece</option>
          <option>Carton</option>
        </select>

        <input
          type="text"
          placeholder="Remarks"
          value={remarks}
          onChange={(event) => setRemarks(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-green-600 focus:outline-none focus:ring-2 focus:ring-green-100"
        />
      </div>

      <button
        type="button"
        onClick={onAddItem}
        disabled={isSaving}
        className="mt-6 rounded-lg bg-green-600 px-6 py-3 font-semibold text-white transition hover:bg-green-700 disabled:cursor-not-allowed disabled:bg-green-400"
      >
        {isSaving ? "Adding..." : "Add Item"}
      </button>
    </div>
  );
}
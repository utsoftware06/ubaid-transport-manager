"use client";

type Props = {
  itemName: string;
  setItemName: (v: string) => void;

  quantity: string;
  setQuantity: (v: string) => void;

  weight: string;
  setWeight: (v: string) => void;

  unit: string;
  setUnit: (v: string) => void;

  remarks: string;
  setRemarks: (v: string) => void;

  handleAddItem: () => void;
};

export default function LoadingItems({
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
  handleAddItem,
}: Props) {
  return (
    <div className="mt-10 bg-gray-50 rounded-xl p-6 border">

      <h2 className="text-2xl font-bold mb-6 text-gray-900">
        Add Loading Item
      </h2>

      <div className="grid grid-cols-5 gap-4">

        <input
          type="text"
          placeholder="Item Name"
          value={itemName}
          onChange={(e) => setItemName(e.target.value)}
          className="border rounded-lg p-3 text-gray-900"
        />

        <input
          type="number"
          placeholder="Quantity"
          value={quantity}
          onChange={(e) => setQuantity(e.target.value)}
          className="border rounded-lg p-3 text-gray-900"
        />

        <input
          type="number"
          placeholder="Weight"
          value={weight}
          onChange={(e) => setWeight(e.target.value)}
          className="border rounded-lg p-3 text-gray-900"
        />

        <select
          value={unit}
          onChange={(e) => setUnit(e.target.value)}
          className="border rounded-lg p-3 text-gray-900"
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
          onChange={(e) => setRemarks(e.target.value)}
          className="border rounded-lg p-3 text-gray-900"
        />

      </div>

      <button
        onClick={handleAddItem}
        className="mt-6 bg-green-600 hover:bg-green-700 text-white px-6 py-3 rounded-lg"
      >
        Add Item
      </button>

    </div>
  );
}
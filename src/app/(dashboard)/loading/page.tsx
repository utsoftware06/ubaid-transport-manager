"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
export default function LoadingPage() {
    const [loadingNo, setLoadingNo] = useState("");
const [loadingDate, setLoadingDate] = useState("");

const [vehicleId, setVehicleId] = useState("");
const [driverId, setDriverId] = useState("");

const [route, setRoute] = useState("");

const [vehicles, setVehicles] = useState([]);
const [drivers, setDrivers] = useState([]);
const [loadings, setLoadings] = useState<any[]>([]);
const [search, setSearch] = useState("");
const [itemName, setItemName] = useState("");
const [quantity, setQuantity] = useState("");
const [weight, setWeight] = useState("");
const [unit, setUnit] = useState("Kg");
const [remarks, setRemarks] = useState("");

const [loadingItems, setLoadingItems] = useState<any[]>([]);
const [loadingId, setLoadingId] = useState<number | null>(null);

async function loadVehicles() {
  const { data } = await supabase
    .from("vehicles")
    .select("*")
    .order("vehicle_no");

  if (data) setVehicles(data);
}

async function loadDrivers() {
  const { data } = await supabase
    .from("drivers")
    .select("*")
    .order("name");

  if (data) setDrivers(data);
}

async function loadLoadings() {
  const { data } = await supabase
    .from("loadings")
    .select(`
      *,
      vehicles(vehicle_no),
      drivers(name)
    `)
    .order("id", { ascending: false });

  if (data) {
    setLoadings(data);
  }
}
useEffect(() => {
  loadVehicles();
  loadDrivers();
  loadLoadings();
}, []);
useEffect(() => {
  if (loadingId) {
    loadLoadingItems();
  }
}, [loadingId]);
async function handleSaveLoading() {
 const { data, error } = await supabase
  .from("loadings")
  .insert({
    loading_no: loadingNo,
    loading_date: loadingDate,
    vehicle_id: vehicleId,
    driver_id: driverId,
    route: route,
  })
  .select();

console.log("DATA:", data);
console.log("ERROR:", error);
 if (error) {
  console.log("SAVE ERROR:", error);
  alert(JSON.stringify(error, null, 2));
  return;
}
console.log("SAVE DATA:", data);
if (data && data.length > 0) {
  setLoadingId(data[0].id);
}

  alert("Loading saved successfully!");
  await loadLoadings();

  setLoadingNo("");
  setLoadingDate("");
  setVehicleId("");
  setDriverId("");
  setRoute("");
}
async function loadLoadingItems() {
  if (!loadingId) return;

  const { data } = await supabase
    .from("loading_items")
    .select("*")
    .eq("loading_id", loadingId)
    .order("id", { ascending: false });

  if (data) {
    setLoadingItems(data);
  }
}
async function handleAddItem() {
  const { error } = await supabase
    .from("loading_items")
    .insert({
      loading_id: loadingId,
      item_name: itemName,
      quantity: Number(quantity),
      weight: Number(weight),
      unit: unit,
      remarks: remarks,
    });

  if (error) {
    alert(error.message);
    return;
  }

alert("Item Added Successfully!");
  await loadLoadingItems();

  setItemName("");
  setQuantity("");
  setWeight("");
  setUnit("Kg");
  setRemarks("");
}
  return (
    <div className="max-w-7xl mx-auto">
      <h1 className="text-4xl font-bold mb-8 text-gray-900">
        🚛 Loading Management
      </h1>

      <div className="bg-white rounded-xl shadow-md p-8">
        <h2 className="text-3xl font-bold mb-8 text-gray-900">
          Create New Loading
        </h2>

        <div className="grid grid-cols-2 gap-6">
         <input
  type="text"
  placeholder="Loading Number"
  value={loadingNo}
  onChange={(e) => setLoadingNo(e.target.value)}
  className="w-full border p-3 rounded-lg text-gray-700 placeholder:text-gray-500"
/>

          <input
  type="date"
  value={loadingDate}
  onChange={(e) => setLoadingDate(e.target.value)}
  className="w-full border p-3 rounded-lg text-gray-700"
/>
         <select
  value={vehicleId}
  onChange={(e) => setVehicleId(e.target.value)}
  className="w-full border p-3 rounded-lg text-gray-700"
>
  <option value="">Select Vehicle</option>

  {vehicles.map((vehicle: any) => (
    <option key={vehicle.id} value={vehicle.id}>
      {vehicle.vehicle_no}
    </option>
  ))}
</select>

          <select
  value={driverId}
  onChange={(e) => setDriverId(e.target.value)}
  className="w-full border p-3 rounded-lg text-gray-700"
>
  <option value="">Select Driver</option>

 {drivers.map((driver: any) => (
  <option key={driver.id} value={driver.id}>
    {driver.name}
  </option>
))}
</select>

       <input
  type="text"
  placeholder="Route"
  value={route}
  onChange={(e) => setRoute(e.target.value)}
  className="w-full border p-3 rounded-lg text-gray-700 placeholder:text-gray-500 col-span-2"
/>
        </div>

       <button
  onClick={handleSaveLoading}
  className="mt-8 bg-blue-600 hover:bg-blue-700 text-white px-8 py-3 rounded-lg font-semibold transition"
>
  Save & Next
</button>
{loadingId && (
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
)}
{loadingId && loadingItems.length > 0 && (
  <div className="mt-8 bg-white rounded-xl border p-6">
    <h2 className="text-2xl font-bold mb-4 text-gray-900">
      Loading Items
    </h2>

    <table className="w-full border">
      <thead className="bg-green-600 text-white">
        <tr>
          <th className="p-3">Item</th>
          <th className="p-3">Qty</th>
          <th className="p-3">Weight</th>
          <th className="p-3">Unit</th>
          <th className="p-3">Remarks</th>
        </tr>
      </thead>

      <tbody>
        {loadingItems.map((item: any) => (
          <tr key={item.id} className="border-b">
            <td className="p-3">{item.item_name}</td>
            <td className="p-3">{item.quantity}</td>
            <td className="p-3">{item.weight}</td>
            <td className="p-3">{item.unit}</td>
            <td className="p-3">{item.remarks}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)}
<div className="mt-10">
  <h2 className="text-2xl font-bold mb-4 text-gray-900">My Loadings</h2>

  <input
    type="text"
    placeholder="Search Loading..."
    value={search}
    onChange={(e) => setSearch(e.target.value)}
    className="w-full border rounded-lg p-3 mb-4 bg-white text-gray-900 placeholder:text-gray-500"
  />

  <div className="overflow-x-auto">
<table className="w-full border border-gray-200 bg-white text-gray-900">      <thead className="bg-blue-600 text-white">
        <tr>
          <th className="p-3 text-left">Loading No</th>
          <th className="p-3 text-left">Date</th>
          <th className="p-3 text-left">Vehicle</th>
          <th className="p-3 text-left">Driver</th>
          <th className="p-3 text-left">Route</th>
        </tr>
      </thead>

     <tbody className="bg-white text-gray-900">
        {loadings
          .filter((item: any) =>
            item.loading_no
              ?.toLowerCase()
              .includes(search.toLowerCase())
          )
          .map((item: any) => (
            <tr
              key={item.id}
              className="border-b hover:bg-gray-50 text-gray-900"
            >
              <td className="p-3 font-medium text-gray-900">
  {item.loading_no}
</td>

<td className="p-3 font-medium text-gray-900">
  {item.loading_date}
</td>

<td className="p-3 font-medium text-gray-900">
  {item.vehicles?.vehicle_no}
</td>

<td className="p-3 font-medium text-gray-900">
  {item.drivers?.name}
</td>

<td className="p-3 font-medium text-gray-900">
  {item.route}
</td>
            </tr>
          ))}
      </tbody>
    </table>
  </div>
</div>
      </div>
    </div>
  );
}
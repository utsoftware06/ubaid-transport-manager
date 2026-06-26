"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";

export default function VehiclesPage() {
  const [vehicleNo, setVehicleNo] = useState("");
  const [vehicleType, setVehicleType] = useState("");
  const [model, setModel] = useState("");
  const [ownerName, setOwnerName] = useState("");
  const [vehicles, setVehicles] = useState<any[]>([]);

  async function loadVehicles() {
    const { data, error } = await supabase
      .from("vehicles")
      .select("*")
      .order("created_at", { ascending: false });

    if (!error && data) {
      setVehicles(data);
    }
  }

  useEffect(() => {
    loadVehicles();
  }, []);

  async function handleCreateVehicle(
    e: React.FormEvent<HTMLFormElement>
  ) {
    e.preventDefault();

    const { error } = await supabase
      .from("vehicles")
      .insert({
        vehicle_no: vehicleNo,
        vehicle_type: vehicleType,
        model,
        owner_name: ownerName,
      });

    if (error) {
      alert(error.message);
      return;
    }

    alert("Vehicle saved successfully!");

    setVehicleNo("");
    setVehicleType("");
    setModel("");
    setOwnerName("");

    await loadVehicles();
  }

  return (
    <main className="min-h-screen bg-gray-100 p-8 text-gray-900">
      <div className="max-w-xl mx-auto bg-white p-8 rounded-xl shadow-lg border border-gray-200">
        <h1 className="text-3xl font-bold text-center mb-8 text-gray-900">
          Add New Vehicle
        </h1>

        <form
          onSubmit={handleCreateVehicle}
          className="space-y-4"
        >
          <input
            type="text"
            placeholder="Vehicle Number"
            value={vehicleNo}
            onChange={(e) => setVehicleNo(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          <input
            type="text"
            placeholder="Vehicle Type"
            value={vehicleType}
            onChange={(e) => setVehicleType(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          <input
            type="text"
            placeholder="Model"
            value={model}
            onChange={(e) => setModel(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          <input
            type="text"
            placeholder="Owner Name"
            value={ownerName}
            onChange={(e) => setOwnerName(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          <button
            type="submit"
            className="w-full bg-blue-600 hover:bg-blue-700 text-white p-3 rounded-lg font-semibold"
          >
            Save Vehicle
          </button>
        </form>

        <div className="mt-10">
          <h2 className="text-2xl font-bold mb-4 text-gray-900">
            My Vehicles
          </h2>

          {vehicles.length === 0 ? (
            <p className="text-gray-600">
              No vehicles found.
            </p>
          ) : (
            <div className="space-y-4">
              {vehicles.map((vehicle) => (
                <div
                  key={vehicle.id}
                  className="border border-gray-300 rounded-lg p-4 bg-white shadow-sm"
                >
                  <h3 className="text-xl font-semibold text-gray-900">
                    {vehicle.vehicle_no}
                  </h3>

                  <p className="text-gray-700">
                    Type: {vehicle.vehicle_type}
                  </p>

                  <p className="text-gray-700">
                    Model: {vehicle.model}
                  </p>

                  <p className="text-gray-700">
                    Owner: {vehicle.owner_name}
                  </p>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </main>
  );
}
"use client";

import { useState, useEffect } from "react";
import { supabase } from "@/lib/supabase/client";

export default function DriversPage() {
  const [addaId, setAddaId] = useState("");
  const [addas, setAddas] = useState<any[]>([]);

  const [name, setName] = useState("");
  const [fatherName, setFatherName] = useState("");
  const [cnic, setCnic] = useState("");
  const [phone, setPhone] = useState("");
  const [licenseNo, setLicenseNo] = useState("");
  const [address, setAddress] = useState("");

  useEffect(() => {
    loadAddas();
  }, []);

  async function loadAddas() {
    const { data } = await supabase
      .from("addas")
      .select("*")
      .order("name");

    if (data) {
      setAddas(data);
    }
  }

  async function handleSaveDriver(
    e: React.FormEvent<HTMLFormElement>
  ) {
    e.preventDefault();

   const { data, error } = await supabase
  .from("drivers")
  .insert({
    adda_id: addaId,
    name,
    father_name: fatherName,
    cnic,
    phone,
    license_no: licenseNo,
    address,
  })
  .select();

console.log("DATA:", data);
console.log("ERROR:", error);

if (error) {
  alert(error.message);
  return;
}

    alert("Driver saved successfully!");

    setAddaId("");
    setName("");
    setFatherName("");
    setCnic("");
    setPhone("");
    setLicenseNo("");
    setAddress("");
  }

  return (
    <main className="min-h-screen bg-gray-100 p-8 text-gray-900">
      <div className="max-w-xl mx-auto bg-white p-8 rounded-xl shadow-lg border border-gray-200">
        <h1 className="text-3xl font-bold text-center mb-8 text-gray-900">
          Add New Driver
        </h1>

        <form
          onSubmit={handleSaveDriver}
          className="space-y-4"
        >

          <select
            value={addaId}
            onChange={(e) => setAddaId(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900"
            required
          >
            <option value="">Select Adda</option>

            {addas.map((adda: any) => (
              <option key={adda.id} value={adda.id}>
                {adda.name}
              </option>
            ))}
          </select>

          <input
            type="text"
            placeholder="Driver Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900"
            required
          />

          <input
            type="text"
            placeholder="Father Name"
            value={fatherName}
            onChange={(e) => setFatherName(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900"
          />

          <input
            type="text"
            placeholder="CNIC"
            value={cnic}
            onChange={(e) => setCnic(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900"
          />

          <input
            type="text"
            placeholder="Phone Number"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900"
          />

          <input
            type="text"
            placeholder="License Number"
            value={licenseNo}
            onChange={(e) => setLicenseNo(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900"
          />

          <input
            type="text"
            placeholder="Address"
            value={address}
            onChange={(e) => setAddress(e.target.value)}
            className="w-full border border-gray-300 p-3 rounded-lg bg-white text-gray-900"
          />

          <button
            type="submit"
            className="w-full bg-green-600 hover:bg-green-700 text-white p-3 rounded-lg font-semibold"
          >
            Save Driver
          </button>

        </form>
      </div>
    </main>
  );
}
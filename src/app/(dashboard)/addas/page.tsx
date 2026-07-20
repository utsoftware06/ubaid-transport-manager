"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";

type AddaRecord = {
  id: number;
  adda_name: string;
  city: string | null;
  address: string | null;
  phone: string | null;
  created_at: string | null;
};

export default function AddasPage() {
  const [addaName, setAddaName] = useState("");
  const [city, setCity] = useState("");
  const [address, setAddress] = useState("");
  const [phone, setPhone] = useState("");

  const [addas, setAddas] = useState<AddaRecord[]>([]);
  const [search, setSearch] = useState("");

  const filteredAddas = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return addas;

    return addas.filter((adda) => {
      const searchableText = [
        adda.adda_name,
        adda.city ?? "",
        adda.address ?? "",
        adda.phone ?? "",
      ]
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [addas, search]);

  async function loadAddas() {
    const { data, error } = await supabase
      .from("addas")
      .select("*")
      .order("id", { ascending: false });

    if (error) {
      alert(error.message);
      return;
    }

    if (data) {
      setAddas(data as AddaRecord[]);
    }
  }

  useEffect(() => {
    loadAddas();
  }, []);

  async function handleSaveAdda() {
    if (!addaName.trim()) {
      alert("Adda Name is required.");
      return;
    }

    const { error } = await supabase.from("addas").insert({
      adda_name: addaName.trim(),
      city: city.trim(),
      address: address.trim(),
      phone: phone.trim(),
    });

    if (error) {
      alert(error.message);
      return;
    }

    alert("Adda saved successfully!");

    setAddaName("");
    setCity("");
    setAddress("");
    setPhone("");

    await loadAddas();
  }

  return (
    <div className="max-w-7xl mx-auto">
      <h1 className="text-4xl font-bold mb-8 text-gray-900">
        Adda Management
      </h1>

      <div className="bg-white rounded-xl shadow-md p-8">
        <h2 className="text-3xl font-bold mb-8 text-gray-900">
          Create New Adda
        </h2>

        <div className="grid grid-cols-2 gap-6">
          <input
            type="text"
            placeholder="Adda Name"
            value={addaName}
            onChange={(event) => setAddaName(event.target.value)}
            className="w-full border p-3 rounded-lg text-gray-700 placeholder:text-gray-500"
          />

          <input
            type="text"
            placeholder="City"
            value={city}
            onChange={(event) => setCity(event.target.value)}
            className="w-full border p-3 rounded-lg text-gray-700 placeholder:text-gray-500"
          />

          <input
            type="text"
            placeholder="Phone"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            className="w-full border p-3 rounded-lg text-gray-700 placeholder:text-gray-500"
          />

          <input
            type="text"
            placeholder="Address"
            value={address}
            onChange={(event) => setAddress(event.target.value)}
            className="w-full border p-3 rounded-lg text-gray-700 placeholder:text-gray-500"
          />
        </div>

        <button
          onClick={handleSaveAdda}
          className="mt-8 bg-blue-600 hover:bg-blue-700 text-white px-8 py-3 rounded-lg font-semibold transition"
        >
          Save Adda
        </button>

        <div className="mt-10">
          <h2 className="text-2xl font-bold mb-4 text-gray-900">My Addas</h2>

          <input
            type="text"
            placeholder="Search Adda..."
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className="w-full border rounded-lg p-3 mb-4 bg-white text-gray-900 placeholder:text-gray-500"
          />

          <div className="overflow-x-auto">
            <table className="w-full border border-gray-200 bg-white text-gray-900">
              <thead className="bg-blue-600 text-white">
                <tr>
                  <th className="p-3 text-left">Adda Name</th>
                  <th className="p-3 text-left">City</th>
                  <th className="p-3 text-left">Phone</th>
                  <th className="p-3 text-left">Address</th>
                </tr>
              </thead>

              <tbody className="bg-white text-gray-900">
                {filteredAddas.map((adda) => (
                  <tr
                    key={adda.id}
                    className="border-b hover:bg-gray-50 text-gray-900"
                  >
                    <td className="p-3 font-medium text-gray-900">
                      {adda.adda_name}
                    </td>

                    <td className="p-3 font-medium text-gray-900">
                      {adda.city}
                    </td>

                    <td className="p-3 font-medium text-gray-900">
                      {adda.phone}
                    </td>

                    <td className="p-3 font-medium text-gray-900">
                      {adda.address}
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
"use client";

import { useEffect, useMemo, useState } from "react";
import LoadingForm from "@/components/loading/LoadingForm";
import LoadingItems from "@/components/loading/LoadingItems";
import LoadingTable from "@/components/loading/LoadingTable";
import { supabase } from "@/lib/supabase/client";

type Vehicle = {
  id: number;
  vehicle_no: string;
};

type Driver = {
  id: number;
  name: string;
};

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
  vehicle_id: number | string;
  driver_id: number | string;
  route: string;
  vehicles?: {
    vehicle_no: string;
  } | null;
  drivers?: {
    name: string;
  } | null;
  loading_items?: LoadingItem[];
};

export default function LoadingPage() {
  const [loadingNo, setLoadingNo] = useState("");
  const [loadingDate, setLoadingDate] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [driverId, setDriverId] = useState("");
  const [route, setRoute] = useState("");

  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [loadingItems, setLoadingItems] = useState<LoadingItem[]>([]);

  const [search, setSearch] = useState("");
  const [itemName, setItemName] = useState("");
  const [quantity, setQuantity] = useState("");
  const [weight, setWeight] = useState("");
  const [unit, setUnit] = useState("Kg");
  const [remarks, setRemarks] = useState("");

  const [loadingId, setLoadingId] = useState<number | null>(null);
  const [editingLoadingId, setEditingLoadingId] = useState<number | null>(null);
  const [isSavingLoading, setIsSavingLoading] = useState(false);
  const [isSavingItem, setIsSavingItem] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  const selectedLoading = useMemo(() => {
    if (!loadingId) return null;
    return loadings.find((loading) => loading.id === loadingId) ?? null;
  }, [loadingId, loadings]);

  const filteredLoadings = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return loadings;

    return loadings.filter((loading) => {
      const searchableText = [
        loading.loading_no,
        loading.loading_date,
        loading.vehicles?.vehicle_no,
        loading.drivers?.name,
        loading.route,
        ...(loading.loading_items ?? []).flatMap((item) => [
          item.item_name,
          String(item.quantity ?? ""),
          String(item.weight ?? ""),
          item.unit,
          item.remarks ?? "",
        ]),
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [loadings, search]);

  useEffect(() => {
    loadVehicles();
    loadDrivers();
    loadLoadings();
  }, []);

  useEffect(() => {
    if (loadingId) {
      loadLoadingItems(loadingId);
    } else {
      setLoadingItems([]);
    }
  }, [loadingId]);

  async function loadVehicles() {
    const { data, error } = await supabase
      .from("vehicles")
      .select("*")
      .order("vehicle_no");

    if (error) {
      alert(error.message);
      return;
    }

    if (data) setVehicles(data as Vehicle[]);
  }

  async function loadDrivers() {
    const { data, error } = await supabase
      .from("drivers")
      .select("*")
      .order("name");

    if (error) {
      alert(error.message);
      return;
    }

    if (data) setDrivers(data as Driver[]);
  }

  async function loadLoadings() {
    const { data, error } = await supabase
      .from("loadings")
      .select(
        `
        *,
        vehicles(vehicle_no),
        drivers(name),
        loading_items(*)
      `
      )
      .order("id", { ascending: false });

    if (error) {
      alert(error.message);
      return;
    }

    if (data) setLoadings(data as LoadingRecord[]);
  }

  async function loadLoadingItems(currentLoadingId = loadingId) {
    if (!currentLoadingId) return;

    const { data, error } = await supabase
      .from("loading_items")
      .select("*")
      .eq("loading_id", currentLoadingId)
      .order("id", { ascending: false });

    if (error) {
      alert(error.message);
      return;
    }

    if (data) setLoadingItems(data as LoadingItem[]);
  }

  function resetLoadingForm() {
    setLoadingNo("");
    setLoadingDate("");
    setVehicleId("");
    setDriverId("");
    setRoute("");
    setEditingLoadingId(null);
  }

  function resetItemForm() {
    setItemName("");
    setQuantity("");
    setWeight("");
    setUnit("Kg");
    setRemarks("");
  }

  function validateLoadingForm() {
    if (!loadingNo.trim()) {
      alert("Loading Number is required.");
      return false;
    }

    if (!loadingDate) {
      alert("Loading Date is required.");
      return false;
    }

    if (!vehicleId) {
      alert("Please select a vehicle.");
      return false;
    }

    if (!driverId) {
      alert("Please select a driver.");
      return false;
    }

    if (!route.trim()) {
      alert("Route is required.");
      return false;
    }

    return true;
  }

  function validateItemForm() {
    if (!loadingId) {
      alert("Please save or select a loading first.");
      return false;
    }

    if (!itemName.trim()) {
      alert("Item Name is required.");
      return false;
    }

    if (!quantity || Number(quantity) <= 0) {
      alert("Quantity must be greater than zero.");
      return false;
    }

    if (!weight || Number(weight) <= 0) {
      alert("Weight must be greater than zero.");
      return false;
    }

    if (!unit.trim()) {
      alert("Unit is required.");
      return false;
    }

    return true;
  }

  async function handleSaveLoading() {
    if (!validateLoadingForm()) return;

    setIsSavingLoading(true);

    if (editingLoadingId) {
      const { error } = await supabase
        .from("loadings")
        .update({
          loading_no: loadingNo.trim(),
          loading_date: loadingDate,
          vehicle_id: vehicleId,
          driver_id: driverId,
          route: route.trim(),
        })
        .eq("id", editingLoadingId);

      setIsSavingLoading(false);

      if (error) {
        alert(error.message);
        return;
      }

      setLoadingId(editingLoadingId);
      alert("Loading updated successfully!");
      await loadLoadings();
      resetLoadingForm();
      return;
    }

    const { data, error } = await supabase
      .from("loadings")
      .insert({
        loading_no: loadingNo.trim(),
        loading_date: loadingDate,
        vehicle_id: vehicleId,
        driver_id: driverId,
        route: route.trim(),
      })
      .select();

    setIsSavingLoading(false);

    if (error) {
      alert(error.message);
      return;
    }

    if (data && data.length > 0) {
      setLoadingId(data[0].id);
    }

    alert("Loading saved successfully!");
    await loadLoadings();
    resetLoadingForm();
  }

  async function handleAddItem() {
    if (!validateItemForm()) return;

    setIsSavingItem(true);

    const { error } = await supabase.from("loading_items").insert({
      loading_id: loadingId,
      item_name: itemName.trim(),
      quantity: Number(quantity),
      weight: Number(weight),
      unit,
      remarks: remarks.trim(),
    });

    setIsSavingItem(false);

    if (error) {
      alert(error.message);
      return;
    }

    alert("Item Added Successfully!");
    await loadLoadingItems();
    await loadLoadings();
    resetItemForm();
  }

  function handleViewLoading(loading: LoadingRecord) {
    setLoadingId(loading.id);
    setEditingLoadingId(null);

    alert(
      `Loading No: ${loading.loading_no}\nDate: ${
        loading.loading_date
      }\nVehicle: ${loading.vehicles?.vehicle_no ?? "-"}\nDriver: ${
        loading.drivers?.name ?? "-"
      }\nRoute: ${loading.route}\nItems: ${loading.loading_items?.length ?? 0}`
    );
  }

  function handleEditLoading(loading: LoadingRecord) {
    setLoadingId(loading.id);
    setEditingLoadingId(loading.id);
    setLoadingNo(loading.loading_no ?? "");
    setLoadingDate(loading.loading_date ?? "");
    setVehicleId(String(loading.vehicle_id ?? ""));
    setDriverId(String(loading.driver_id ?? ""));
    setRoute(loading.route ?? "");
  }

  async function handleDeleteLoading(loading: LoadingRecord) {
    const confirmed = window.confirm(
      `Delete loading ${loading.loading_no}? This will also delete its loading items.`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    const { error: itemsError } = await supabase
      .from("loading_items")
      .delete()
      .eq("loading_id", loading.id);

    if (itemsError) {
      setIsDeleting(false);
      alert(itemsError.message);
      return;
    }

    const { error: loadingError } = await supabase
      .from("loadings")
      .delete()
      .eq("id", loading.id);

    setIsDeleting(false);

    if (loadingError) {
      alert(loadingError.message);
      return;
    }

    if (loadingId === loading.id) {
      setLoadingId(null);
      resetItemForm();
    }

    if (editingLoadingId === loading.id) {
      resetLoadingForm();
    }

    alert("Loading deleted successfully!");
    await loadLoadings();
  }

  function handlePrintLoadingSlip(loading: LoadingRecord) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert("Please allow popups to print the loading slip.");
      return;
    }

    const items = loading.loading_items ?? [];
    const totalQuantity = items.reduce(
      (total, item) => total + Number(item.quantity || 0),
      0
    );
    const totalWeight = items.reduce(
      (total, item) => total + Number(item.weight || 0),
      0
    );

    const itemRows =
      items.length > 0
        ? items
            .map(
              (item, index) => `
                <tr>
                  <td>${index + 1}</td>
                  <td>${item.item_name ?? ""}</td>
                  <td>${item.quantity ?? ""}</td>
                  <td>${item.weight ?? ""}</td>
                  <td>${item.unit ?? ""}</td>
                  <td>${item.remarks ?? ""}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="6" class="empty">No items found</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Loading Slip - ${loading.loading_no}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .slip {
              max-width: 900px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 28px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 18px;
              margin-bottom: 22px;
            }
            h1 {
              margin: 0;
              font-size: 28px;
              color: #111827;
            }
            .subtitle {
              margin-top: 6px;
              font-size: 14px;
              color: #111827;
            }
            .meta {
              text-align: right;
              font-size: 14px;
              line-height: 1.7;
              color: #111827;
            }
            .details {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 12px 24px;
              margin-bottom: 24px;
              font-size: 15px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 14px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: left;
              padding: 10px;
              border: 1px solid #2563eb;
            }
            td {
              padding: 10px;
              border: 1px solid #d1d5db;
              color: #111827;
            }
            tfoot td {
              font-weight: 700;
              background: #f9fafb;
            }
            .empty {
              text-align: center;
              font-weight: 700;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 24px;
              margin-top: 52px;
              font-size: 14px;
              color: #111827;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 8px;
              text-align: center;
            }
            @media print {
              body { padding: 0; }
              .slip {
                border: none;
                border-radius: 0;
              }
            }
          </style>
        </head>
        <body>
          <div class="slip">
            <div class="header">
              <div>
                <h1>Loading Slip</h1>
                <div class="subtitle">Transport Management System</div>
              </div>
              <div class="meta">
                <div><strong>Loading No:</strong> ${loading.loading_no}</div>
                <div><strong>Date:</strong> ${loading.loading_date}</div>
              </div>
            </div>

            <div class="details">
              <div><strong>Vehicle:</strong> ${loading.vehicles?.vehicle_no ?? "-"}</div>
              <div><strong>Driver:</strong> ${loading.drivers?.name ?? "-"}</div>
              <div><strong>Route:</strong> ${loading.route ?? "-"}</div>
              <div><strong>Total Items:</strong> ${items.length}</div>
            </div>

            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Item</th>
                  <th>Quantity</th>
                  <th>Weight</th>
                  <th>Unit</th>
                  <th>Remarks</th>
                </tr>
              </thead>
              <tbody>${itemRows}</tbody>
              <tfoot>
                <tr>
                  <td colspan="2">Total</td>
                  <td>${totalQuantity}</td>
                  <td>${totalWeight}</td>
                  <td colspan="2"></td>
                </tr>
              </tfoot>
            </table>

            <div class="signatures">
              <div class="signature">Prepared By</div>
              <div class="signature">Driver Signature</div>
              <div class="signature">Manager Signature</div>
            </div>
          </div>

          <script>
            window.onload = function () {
              window.print();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  return (
    <div className="mx-auto max-w-7xl space-y-8">
      <div>
        <h1 className="text-4xl font-bold text-gray-900">
          🚛 Loading Management
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Create loadings, add goods, search records, and print loading slips.
        </p>
      </div>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <LoadingForm
          loadingNo={loadingNo}
          setLoadingNo={setLoadingNo}
          loadingDate={loadingDate}
          setLoadingDate={setLoadingDate}
          vehicleId={vehicleId}
          setVehicleId={setVehicleId}
          driverId={driverId}
          setDriverId={setDriverId}
          route={route}
          setRoute={setRoute}
          vehicles={vehicles}
          drivers={drivers}
          onSave={handleSaveLoading}
          isSaving={isSavingLoading}
          isEditing={Boolean(editingLoadingId)}
          onCancelEdit={resetLoadingForm}
        />

        {loadingId && (
          <LoadingItems
            loadingId={loadingId}
            selectedLoading={selectedLoading}
            itemName={itemName}
            setItemName={setItemName}
            quantity={quantity}
            setQuantity={setQuantity}
            weight={weight}
            setWeight={setWeight}
            unit={unit}
            setUnit={setUnit}
            remarks={remarks}
            setRemarks={setRemarks}
            loadingItems={loadingItems}
            onAddItem={handleAddItem}
            isSaving={isSavingItem}
          />
        )}
      </div>

      <LoadingTable
        loadings={filteredLoadings}
        search={search}
        setSearch={setSearch}
        onView={handleViewLoading}
        onEdit={handleEditLoading}
        onDelete={handleDeleteLoading}
        onPrint={handlePrintLoadingSlip}
        isDeleting={isDeleting}
      />
    </div>
  );
}
"use client";

import { useEffect, useMemo, useState } from "react";
import PackingForm from "@/components/packing/PackingForm";
import PackingItems from "@/components/packing/PackingItems";
import PackingTable from "@/components/packing/PackingTable";
import { supabase } from "@/lib/supabase/client";

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

type PackingSlipItem = {
  id: number;
  packing_slip_id: number;
  item_name: string;
  quantity: number;
  weight: number;
  unit: string;
  remarks: string | null;
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

export default function PackingPage() {
  const [packingSlipNo, setPackingSlipNo] = useState("");
  const [packingDate, setPackingDate] = useState("");
  const [loadingId, setLoadingId] = useState("");
  const [remarks, setRemarks] = useState("");

  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [packingSlips, setPackingSlips] = useState<PackingSlipRecord[]>([]);
  const [loadingItems, setLoadingItems] = useState<LoadingItem[]>([]);

  const [search, setSearch] = useState("");
  const [editingPackingSlipId, setEditingPackingSlipId] = useState<number | null>(
    null
  );
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  const selectedLoading = useMemo(() => {
    if (!loadingId) return null;
    return loadings.find((loading) => String(loading.id) === loadingId) ?? null;
  }, [loadingId, loadings]);

  const filteredPackingSlips = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return packingSlips;

    return packingSlips.filter((packingSlip) => {
      const loading = packingSlip.loadings;
      const searchableText = [
        packingSlip.packing_slip_no,
        packingSlip.packing_date,
        packingSlip.remarks ?? "",
        loading?.loading_no,
        loading?.loading_date,
        loading?.vehicles?.vehicle_no,
        loading?.drivers?.name,
        loading?.route,
        ...(packingSlip.packing_slip_items ?? []).flatMap((item) => [
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
  }, [packingSlips, search]);

  useEffect(() => {
    loadLoadings();
    loadPackingSlips();
  }, []);

  useEffect(() => {
    if (loadingId) {
      loadLoadingItems(Number(loadingId));
    } else {
      setLoadingItems([]);
    }
  }, [loadingId]);

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

  async function loadLoadingItems(currentLoadingId: number) {
    const { data, error } = await supabase
      .from("loading_items")
      .select("*")
      .eq("loading_id", currentLoadingId)
      .order("id", { ascending: true });

    if (error) {
      alert(error.message);
      return;
    }

    if (data) setLoadingItems(data as LoadingItem[]);
  }

  async function loadPackingSlips() {
    const { data, error } = await supabase
      .from("packing_slips")
      .select(
        `
        *,
        loadings(
          *,
          vehicles(vehicle_no),
          drivers(name)
        ),
        packing_slip_items(*)
      `
      )
      .order("id", { ascending: false });

    if (error) {
      alert(error.message);
      return;
    }

    if (data) setPackingSlips(data as PackingSlipRecord[]);
  }

  function resetForm() {
    setPackingSlipNo("");
    setPackingDate("");
    setLoadingId("");
    setRemarks("");
    setLoadingItems([]);
    setEditingPackingSlipId(null);
  }

  function validatePackingForm() {
    if (!packingSlipNo.trim()) {
      alert("Packing Slip Number is required.");
      return false;
    }

    if (!packingDate) {
      alert("Packing Date is required.");
      return false;
    }

    if (!loadingId) {
      alert("Please select a loading.");
      return false;
    }

    if (loadingItems.length === 0) {
      alert("Selected loading has no items to pack.");
      return false;
    }

    return true;
  }

  async function copyLoadingItemsToPackingSlip(packingSlipId: number) {
    const itemsToInsert = loadingItems.map((item) => ({
      packing_slip_id: packingSlipId,
      item_name: item.item_name,
      quantity: Number(item.quantity),
      weight: Number(item.weight),
      unit: item.unit,
      remarks: item.remarks ?? "",
    }));

    const { error } = await supabase
      .from("packing_slip_items")
      .insert(itemsToInsert);

    if (error) {
      alert(error.message);
      return false;
    }

    return true;
  }

  async function handleSavePackingSlip() {
    if (!validatePackingForm()) return;

    setIsSaving(true);

    if (editingPackingSlipId) {
      const { error: updateError } = await supabase
        .from("packing_slips")
        .update({
          packing_slip_no: packingSlipNo.trim(),
          packing_date: packingDate,
          loading_id: loadingId,
          remarks: remarks.trim(),
        })
        .eq("id", editingPackingSlipId);

      if (updateError) {
        setIsSaving(false);
        alert(updateError.message);
        return;
      }

      const { error: deleteItemsError } = await supabase
        .from("packing_slip_items")
        .delete()
        .eq("packing_slip_id", editingPackingSlipId);

      if (deleteItemsError) {
        setIsSaving(false);
        alert(deleteItemsError.message);
        return;
      }

      const copied = await copyLoadingItemsToPackingSlip(editingPackingSlipId);
      setIsSaving(false);

      if (!copied) return;

      alert("Packing Slip updated successfully!");
      await loadPackingSlips();
      resetForm();
      return;
    }

    const { data, error } = await supabase
      .from("packing_slips")
      .insert({
        packing_slip_no: packingSlipNo.trim(),
        packing_date: packingDate,
        loading_id: loadingId,
        remarks: remarks.trim(),
      })
      .select();

    if (error) {
      setIsSaving(false);
      alert(error.message);
      return;
    }

    if (!data || data.length === 0) {
      setIsSaving(false);
      alert("Packing Slip was not saved.");
      return;
    }

    const copied = await copyLoadingItemsToPackingSlip(data[0].id);
    setIsSaving(false);

    if (!copied) return;

    alert("Packing Slip saved successfully!");
    await loadPackingSlips();
    resetForm();
  }

  function handleViewPackingSlip(packingSlip: PackingSlipRecord) {
    alert(
      `Packing Slip No: ${packingSlip.packing_slip_no}\nDate: ${
        packingSlip.packing_date
      }\nLoading No: ${packingSlip.loadings?.loading_no ?? "-"}\nVehicle: ${
        packingSlip.loadings?.vehicles?.vehicle_no ?? "-"
      }\nDriver: ${packingSlip.loadings?.drivers?.name ?? "-"}\nRoute: ${
        packingSlip.loadings?.route ?? "-"
      }\nItems: ${packingSlip.packing_slip_items?.length ?? 0}`
    );
  }

  async function handleEditPackingSlip(packingSlip: PackingSlipRecord) {
    setEditingPackingSlipId(packingSlip.id);
    setPackingSlipNo(packingSlip.packing_slip_no ?? "");
    setPackingDate(packingSlip.packing_date ?? "");
    setLoadingId(String(packingSlip.loading_id ?? ""));
    setRemarks(packingSlip.remarks ?? "");

    if (packingSlip.loading_id) {
      await loadLoadingItems(Number(packingSlip.loading_id));
    }
  }

  async function handleDeletePackingSlip(packingSlip: PackingSlipRecord) {
    const confirmed = window.confirm(
      `Delete packing slip ${packingSlip.packing_slip_no}? This will also delete its packing items.`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    const { error: itemsError } = await supabase
      .from("packing_slip_items")
      .delete()
      .eq("packing_slip_id", packingSlip.id);

    if (itemsError) {
      setIsDeleting(false);
      alert(itemsError.message);
      return;
    }

    const { error: slipError } = await supabase
      .from("packing_slips")
      .delete()
      .eq("id", packingSlip.id);

    setIsDeleting(false);

    if (slipError) {
      alert(slipError.message);
      return;
    }

    if (editingPackingSlipId === packingSlip.id) {
      resetForm();
    }

    alert("Packing Slip deleted successfully!");
    await loadPackingSlips();
  }

  function handlePrintPackingSlip(packingSlip: PackingSlipRecord) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert("Please allow popups to print the packing slip.");
      return;
    }

    const items = packingSlip.packing_slip_items ?? [];
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
          <title>Packing Slip - ${packingSlip.packing_slip_no}</title>
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
                <h1>Packing Slip</h1>
                <div class="subtitle">Transport Management System</div>
              </div>
              <div class="meta">
                <div><strong>Packing Slip No:</strong> ${packingSlip.packing_slip_no}</div>
                <div><strong>Date:</strong> ${packingSlip.packing_date}</div>
              </div>
            </div>

            <div class="details">
              <div><strong>Loading No:</strong> ${packingSlip.loadings?.loading_no ?? "-"}</div>
              <div><strong>Loading Date:</strong> ${packingSlip.loadings?.loading_date ?? "-"}</div>
              <div><strong>Vehicle:</strong> ${packingSlip.loadings?.vehicles?.vehicle_no ?? "-"}</div>
              <div><strong>Driver:</strong> ${packingSlip.loadings?.drivers?.name ?? "-"}</div>
              <div><strong>Route:</strong> ${packingSlip.loadings?.route ?? "-"}</div>
              <div><strong>Total Items:</strong> ${items.length}</div>
              <div><strong>Remarks:</strong> ${packingSlip.remarks ?? "-"}</div>
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
              <div class="signature">Checked By</div>
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
          📦 Packing Slip Management
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Create packing slips from completed loadings and print professional
          packing records.
        </p>
      </div>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <PackingForm
          packingSlipNo={packingSlipNo}
          setPackingSlipNo={setPackingSlipNo}
          packingDate={packingDate}
          setPackingDate={setPackingDate}
          loadingId={loadingId}
          setLoadingId={setLoadingId}
          remarks={remarks}
          setRemarks={setRemarks}
          loadings={loadings}
          selectedLoading={selectedLoading}
          onSave={handleSavePackingSlip}
          isSaving={isSaving}
          isEditing={Boolean(editingPackingSlipId)}
          onCancelEdit={resetForm}
        />

        {loadingId && (
          <PackingItems
            selectedLoading={selectedLoading}
            loadingItems={loadingItems}
          />
        )}
      </div>

      <PackingTable
        packingSlips={filteredPackingSlips}
        search={search}
        setSearch={setSearch}
        onView={handleViewPackingSlip}
        onEdit={handleEditPackingSlip}
        onDelete={handleDeletePackingSlip}
        onPrint={handlePrintPackingSlip}
        isDeleting={isDeleting}
      />
    </div>
  );
}
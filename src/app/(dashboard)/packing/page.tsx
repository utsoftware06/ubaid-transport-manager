"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import PackingForm from "@/components/packing/PackingForm";
import PackingItems from "@/components/packing/PackingItems";
import PackingTable from "@/components/packing/PackingTable";
import { supabase } from "@/lib/supabase/client";
import type {
  PackingLoadingItem as LoadingItem,
  PackingLoadingRecord as LoadingRecord,
  PackingSlipRecord,
} from "@/types/packing";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

export default function PackingPage() {
  const { t, dir, language } = useLanguage();
  const modulePrint = useModuleTransportPrint("packing_slip", null, language === "ur" ? "ur" : "en");
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
  const saveLockRef = useRef(false);
  const deleteLockRef = useRef(false);

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

  const loadLoadings = useCallback(async () => {
    const { data, error } = await supabase
      .from("loadings")
      .select(
        `
        *,
        vehicles(vehicle_no,adda_id),
        bookings(adda_id),
        drivers(name),
        loading_items(*)
      `
      )
      .order("id", { ascending: false });

    if (error) {
      console.error("Unable to load packing loadings:", error);
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (data) setLoadings(data as LoadingRecord[]);
  }, [t]);

  const loadLoadingItems = useCallback(async (currentLoadingId: number) => {
    const { data, error } = await supabase
      .from("loading_items")
      .select("*")
      .eq("loading_id", currentLoadingId)
      .order("id", { ascending: true });

    if (error) {
      console.error("Unable to load loading items for packing:", error);
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (data) setLoadingItems(data as LoadingItem[]);
  }, [t]);

  const loadPackingSlips = useCallback(async () => {
    const { data, error } = await supabase
      .from("packing_slips")
      .select(
        `
        *,
        loadings(
          *,
          vehicles(vehicle_no,adda_id),
          bookings(adda_id),
          drivers(name)
        ),
        packing_slip_items(*)
      `
      )
      .order("id", { ascending: false });

    if (error) {
      console.error("Unable to load packing slips:", error);
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (data) setPackingSlips(data as PackingSlipRecord[]);
  }, [t]);

  useEffect(() => {
    const loadTimer = window.setTimeout(() => {
      void loadLoadings();
      void loadPackingSlips();
    }, 0);

    return () => {
      window.clearTimeout(loadTimer);
    };
  }, [loadLoadings, loadPackingSlips]);

  const handleLoadingIdChange = useCallback(
    (value: string) => {
      setLoadingId(value);

      if (value) {
        void loadLoadingItems(Number(value));
      } else {
        setLoadingItems([]);
      }
    },
    [loadLoadingItems]
  );

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
      alert(t("packing.validation.numberRequired"));
      return false;
    }

    if (!packingDate) {
      alert(t("packing.validation.dateRequired"));
      return false;
    }

    if (!loadingId) {
      alert(t("packing.validation.loadingRequired"));
      return false;
    }

    if (loadingItems.length === 0) {
      alert(t("packing.validation.noItems"));
      return false;
    }

    const hasInvalidItem = loadingItems.some((item) => {
      const quantity = Number(item.quantity);
      const weight = Number(item.weight);
      return (
        !Number.isFinite(quantity) ||
        quantity <= 0 ||
        !Number.isFinite(weight) ||
        weight < 0
      );
    });

    if (hasInvalidItem) {
      alert(t("packing.validation.invalidItems"));
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
      console.error("Unable to copy packing items:", error);
      alert(t("common.messages.saveFailed"));
      return false;
    }

    return true;
  }

  async function handleSavePackingSlip() {
    if (saveLockRef.current) return;
    if (!validatePackingForm()) return;

    saveLockRef.current = true;
    setIsSaving(true);
    try {
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

        if (updateError) throw updateError;

        const { error: deleteItemsError } = await supabase
          .from("packing_slip_items")
          .delete()
          .eq("packing_slip_id", editingPackingSlipId);

        if (deleteItemsError) throw deleteItemsError;

        const copied = await copyLoadingItemsToPackingSlip(editingPackingSlipId);
        if (!copied) return;

        alert(t("packing.messages.updated"));
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

      if (error) throw error;
      if (!data || data.length === 0) {
        alert(t("packing.messages.saveFailed"));
        return;
      }

      const copied = await copyLoadingItemsToPackingSlip(data[0].id);
      if (!copied) return;

      alert(t("packing.messages.saved"));
      await loadPackingSlips();
      resetForm();
    } catch (error) {
      console.error("Unable to save packing slip:", error);
      alert(t("common.messages.saveFailed"));
    } finally {
      saveLockRef.current = false;
      setIsSaving(false);
    }
  }

  function handleViewPackingSlip(packingSlip: PackingSlipRecord) {
    alert(
      `${t("packing.slipNo")}: ${packingSlip.packing_slip_no}\n${t("common.date")}: ${
        packingSlip.packing_date
      }\n${t("common.loadingNo")}: ${packingSlip.loadings?.loading_no ?? "-"}\n${t("common.vehicle")}: ${
        packingSlip.loadings?.vehicles?.vehicle_no ?? "-"
      }\n${t("common.driver")}: ${packingSlip.loadings?.drivers?.name ?? "-"}\n${t("common.route")}: ${
        packingSlip.loadings?.route ?? "-"
      }\n${t("common.items")}: ${packingSlip.packing_slip_items?.length ?? 0}`
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
    if (deleteLockRef.current) return;
    const confirmed = window.confirm(
      `${t("packing.deleteConfirm")} ${packingSlip.packing_slip_no}?`
    );

    if (!confirmed) return;

    deleteLockRef.current = true;
    setIsDeleting(true);
    try {
      const { error: itemsError } = await supabase
        .from("packing_slip_items")
        .delete()
        .eq("packing_slip_id", packingSlip.id);

      if (itemsError) throw itemsError;

      const { error: slipError } = await supabase
        .from("packing_slips")
        .delete()
        .eq("id", packingSlip.id);

      if (slipError) throw slipError;

      if (editingPackingSlipId === packingSlip.id) resetForm();

      alert(t("packing.messages.deleted"));
      await loadPackingSlips();
    } catch (error) {
      console.error("Unable to delete packing slip:", error);
      alert(t("common.messages.deleteFailed"));
    } finally {
      deleteLockRef.current = false;
      setIsDeleting(false);
    }
  }

  function handlePrintPackingSlipLegacy(packingSlip: PackingSlipRecord) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert(t("packing.messages.allowPopups"));
      return;
    }

    const label = (key: string) => escapeHtml(t(key));
    const value = (input: unknown) => escapeHtml(input);
    const unitLabel = (unit: string) => {
      const unitKey = {
        Kg: "kg",
        Ton: "ton",
        Bag: "bag",
        Piece: "piece",
      }[unit];

      return unitKey ? label(`packing.units.${unitKey}`) : value(unit);
    };
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
                  <td class="technical">${index + 1}</td>
                  <td>${value(item.item_name)}</td>
                  <td class="technical">${value(item.quantity)}</td>
                  <td class="technical">${value(item.weight)}</td>
                  <td>${unitLabel(item.unit)}</td>
                  <td>${value(item.remarks)}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="6" class="empty">${label("packing.items.empty")}</td></tr>`;

    const loading = packingSlip.loadings;
    const booking = Array.isArray(loading?.bookings) ? loading.bookings[0] : loading?.bookings;
    const vehicle = Array.isArray(loading?.vehicles) ? loading.vehicles[0] : loading?.vehicles;
    const ownerAddaId = loading?.booking_id != null
      ? booking?.adda_id ?? null
      : vehicle?.adda_id ?? null;
    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${value(language)}" dir="${value(dir)}">
        <head>
          <title>${label("packing.print")} - ${value(packingSlip.packing_slip_no)}</title>
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
              text-align: end;
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
              text-align: start;
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
            .technical { direction: ltr; unicode-bidi: isolate; }
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
                <h1>${label("packing.print")}</h1>
                <div class="subtitle">${PRINT_ADDA_NAME_TOKEN}</div>
              </div>
              <div class="meta">
                <div><strong>${label("packing.slipNo")}:</strong> <span class="technical">${value(packingSlip.packing_slip_no)}</span></div>
                <div><strong>${label("common.date")}:</strong> <span class="technical">${value(packingSlip.packing_date)}</span></div>
              </div>
            </div>

            <div class="details">
              <div><strong>${label("common.loadingNo")}:</strong> <span class="technical">${value(packingSlip.loadings?.loading_no ?? "-")}</span></div>
              <div><strong>${label("common.loadingDate")}:</strong> <span class="technical">${value(packingSlip.loadings?.loading_date ?? "-")}</span></div>
              <div><strong>${label("common.vehicle")}:</strong> <span class="technical">${value(packingSlip.loadings?.vehicles?.vehicle_no ?? "-")}</span></div>
              <div><strong>${label("common.driver")}:</strong> ${value(packingSlip.loadings?.drivers?.name ?? "-")}</div>
              <div><strong>${label("common.route")}:</strong> ${value(packingSlip.loadings?.route ?? "-")}</div>
              <div><strong>${label("packing.items.totalItems")}:</strong> <span class="technical">${items.length}</span></div>
              <div><strong>${label("common.remarks")}:</strong> ${value(packingSlip.remarks ?? "-")}</div>
            </div>

            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>${label("common.item")}</th>
                  <th>${label("common.quantity")}</th>
                  <th>${label("common.weight")}</th>
                  <th>${label("common.unit")}</th>
                  <th>${label("common.remarks")}</th>
                </tr>
              </thead>
              <tbody>${itemRows}</tbody>
              <tfoot>
                <tr>
                  <td colspan="2">${label("common.total")}</td>
                  <td class="technical">${totalQuantity}</td>
                  <td class="technical">${totalWeight}</td>
                  <td colspan="2"></td>
                </tr>
              </tfoot>
            </table>

            <div class="signatures">
              <div class="signature">${label("packing.printLabels.preparedBy")}</div>
              <div class="signature">${label("packing.printLabels.checkedBy")}</div>
              <div class="signature">${label("packing.printLabels.managerSignature")}</div>
            </div>
          </div>

          <script>
            window.onload = function () {
              window.print();
            };
          </script>
        </body>
      </html>
    `, ownerAddaId, language === "ur" ? "ur" : "en");
  }

  function handlePrintPackingSlip(packingSlip: PackingSlipRecord) {
    const loading = packingSlip.loadings;
    const booking = Array.isArray(loading?.bookings) ? loading.bookings[0] : loading?.bookings;
    const vehicle = Array.isArray(loading?.vehicles) ? loading.vehicles[0] : loading?.vehicles;
    const ownerAddaId = loading?.booking_id != null ? booking?.adda_id ?? null : vehicle?.adda_id ?? null;
    const items = packingSlip.packing_slip_items ?? [];
    const presentation: ModulePrintPresentation = {
      documentType: "packing_slip",
      title: printLabel("packing.print"),
      documentNo: printValue(packingSlip.packing_slip_no),
      documentDate: printValue(packingSlip.packing_date),
      fields: [
        { label: printLabel("common.loadingNo"), value: printValue(loading?.loading_no) },
        { label: printLabel("common.loadingDate"), value: printValue(loading?.loading_date) },
        { label: printLabel("common.vehicle"), value: printValue(vehicle?.vehicle_no) },
        { label: printLabel("common.driver"), value: printValue(loading?.drivers?.name) },
        { label: printLabel("common.route"), value: printValue(loading?.route) },
        { label: printLabel("packing.items.totalItems"), value: String(items.length) },
      ],
      tables: [{
        title: printLabel("common.item"),
        columns: [printLabel("common.item"), printLabel("common.quantity"), printLabel("common.weight"), printLabel("common.unit"), printLabel("common.remarks")],
        rows: items.map((item) => [printValue(item.item_name), printValue(item.quantity), printValue(item.weight), printValue(item.unit), printValue(item.remarks)]),
      }],
      remarks: printValue(packingSlip.remarks),
    };
    modulePrint.openPresentation(presentation, () => handlePrintPackingSlipLegacy(packingSlip), ownerAddaId);
  }

  return (
    <div dir={dir} className="ut-module-page mx-auto max-w-7xl space-y-5">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="package" accent="orange" title={t("packing.title")} description={t("packing.description")} />
      </header>

      <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
        <PackingForm
          packingSlipNo={packingSlipNo}
          setPackingSlipNo={setPackingSlipNo}
          packingDate={packingDate}
          setPackingDate={setPackingDate}
          loadingId={loadingId}
          setLoadingId={handleLoadingIdChange}
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
      {modulePrint.dialog}
    </div>
  );
}

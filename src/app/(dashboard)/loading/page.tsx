"use client";

import { useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import LoadingForm from "@/components/loading/LoadingForm";
import LoadingItems from "@/components/loading/LoadingItems";
import LoadingTable from "@/components/loading/LoadingTable";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import type {
  LoadingBooking as Booking,
  LoadingDriver as Driver,
  LoadingItem,
  LoadingRecord,
  LoadingVehicle as Vehicle,
} from "@/types/loading";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";

function singleRelation<T>(relation: T | T[] | null | undefined): T | null {
  return Array.isArray(relation) ? relation[0] ?? null : relation ?? null;
}

export default function LoadingPage() {
  const { t, dir, language } = useLanguage();
  const [loadingNo, setLoadingNo] = useState("");
  const [loadingDate, setLoadingDate] = useState("");
  const [bookingId, setBookingId] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [driverId, setDriverId] = useState("");
  const [route, setRoute] = useState("");
  const [advanceAmount, setAdvanceAmount] = useState("");

  const [bookings, setBookings] = useState<Booking[]>([]);
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

  const [loadingId, setLoadingId] = useState<string | null>(null);
  const [editingItemId, setEditingItemId] = useState<string | null>(null);
  const [editingLoadingId, setEditingLoadingId] = useState<string | null>(null);
  const [isSavingLoading, setIsSavingLoading] = useState(false);
  const [isSavingItem, setIsSavingItem] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [isLoadingData, setIsLoadingData] = useState(true);
  const [tenantBookingIds, setTenantBookingIds] = useState<string[]>([]);
  const [profileRole, setProfileRole] = useState<string | null>(null);
  const [addas, setAddas] = useState<Array<{ id: string; name: string }>>([]);
  const [selectedAddaId, setSelectedAddaId] = useState("");
  const loadingCreateRequestId = useRef<string | null>(null);
  const modulePrint = useModuleTransportPrint("loading", selectedAddaId || null, language === "ur" ? "ur" : "en");

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
        loading.bookings?.booking_no,
        loading.bookings?.sender_name,
        loading.bookings?.receiver_name,
        loading.vehicles?.vehicle_no,
        loading.drivers?.name,
        loading.route,
        String(loading.bookings?.freight ?? ""),
        String(loading.advance_amount ?? ""),
        String(loading.remaining_amount ?? ""),
        loading.payment_status ?? "",
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

  const loadInitialData = useEffectEvent(async () => {
    setIsLoadingData(true);
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        throw authError ?? new Error("Authenticated user is unavailable.");
      }
      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("role, adda_id")
        .eq("id", authData.user.id)
        .maybeSingle();
      if (profileError || !profile) {
        throw profileError ?? new Error("Authenticated profile is unavailable.");
      }
      setProfileRole(profile.role);

      let addaId = profile.adda_id ? String(profile.adda_id) : "";
      if (profile.role === "super_admin") {
        const { data: addaRows, error: addasError } = await supabase
          .from("addas")
          .select("id, name")
          .order("name");
        if (addasError) throw addasError;
        setAddas((addaRows ?? []).map((adda) => ({ id: String(adda.id), name: adda.name })));
        addaId = selectedAddaId;
      }
      if (!addaId) {
        setBookings([]);
        setVehicles([]);
        setDrivers([]);
        setLoadings([]);
        setTenantBookingIds([]);
        return;
      }
      const bookingIds = await loadBookings(addaId);
      await Promise.all([
        loadVehicles(addaId),
        loadDrivers(addaId),
        loadLoadings(bookingIds),
      ]);
    } catch (loadError) {
      console.error("Unable to load tenant-scoped loading data:", loadError);
      alert(t("common.messages.loadFailed"));
    } finally {
      setIsLoadingData(false);
    }
  });

  useEffect(() => {
    const timer = window.setTimeout(() => void loadInitialData(), 0);
    return () => window.clearTimeout(timer);
  }, [selectedAddaId]);

  const syncLoadingItems = useEffectEvent(async (currentLoadingId: string) => {
    await loadLoadingItems(currentLoadingId);
  });

  useEffect(() => {
    const syncTimer = window.setTimeout(() => {
      if (loadingId) {
        void syncLoadingItems(loadingId);
      } else {
        setLoadingItems([]);
      }
    }, 0);

    return () => window.clearTimeout(syncTimer);
  }, [loadingId]);

  async function loadCurrentAddaId(): Promise<string> {
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) {
      throw authError ?? new Error("Authenticated user is unavailable.");
    }
    const { data, error } = await supabase
      .from("profiles")
      .select("adda_id, role")
      .eq("id", authData.user.id)
      .maybeSingle();
    if (error || !data) {
      throw error ?? new Error("Authenticated user has no Adda.");
    }
    const addaId = data.role === "super_admin" ? selectedAddaId : data.adda_id;
    if (!addaId) throw new Error("An explicit Adda selection is required.");
    return String(addaId);
  }

  async function loadBookings(addaId: string): Promise<string[]> {
    const { data, error } = await supabase
      .from("bookings")
      .select("id, adda_id, booking_no, sender_name, receiver_name, freight, party_id, parties(name)")
      .eq("adda_id", addaId)
      .order("booking_no", { ascending: false });

    if (error) throw error;
    const rows: Booking[] = (data ?? []).map((booking) => ({
      id: String(booking.id),
      adda_id: booking.adda_id,
      booking_no: booking.booking_no,
      sender_name: booking.sender_name,
      receiver_name: booking.receiver_name,
      freight: booking.freight,
      party_id: booking.party_id,
      parties: singleRelation(booking.parties),
    }));
    const ids = rows.map((booking) => booking.id);
    setBookings(rows);
    setTenantBookingIds(ids);
    return ids;
  }

  async function loadVehicles(addaId: string) {
    const { data, error } = await supabase
      .from("vehicles")
      .select("id, vehicle_no")
      .eq("adda_id", addaId)
      .order("vehicle_no");

    if (error) throw error;
    setVehicles((data ?? []) as Vehicle[]);
  }

  async function loadDrivers(addaId: string) {
    const { data, error } = await supabase
      .from("drivers")
      .select("id, name")
      .eq("adda_id", addaId)
      .order("name");

    if (error) throw error;
    setDrivers((data ?? []) as Driver[]);
  }

  async function loadLoadings(bookingIds = tenantBookingIds) {
    if (bookingIds.length === 0) {
      setLoadings([]);
      return;
    }
    const { data, error } = await supabase
      .from("loadings")
      .select(
        `
        *,
        bookings(adda_id, booking_no, sender_name, receiver_name, freight, party_id, parties(name)),
        vehicles(vehicle_no),
        drivers(name),
        loading_items(*)
      `
      )
      .in("booking_id", bookingIds)
      .order("id", { ascending: false });

    if (error) throw error;
    const rows: LoadingRecord[] = (data ?? []).map((loading) => {
      const booking = singleRelation(loading.bookings);
      return {
        ...loading,
        bookings: booking
          ? {
              ...booking,
              parties: singleRelation(booking.parties),
            }
          : null,
        vehicles: singleRelation(loading.vehicles),
        drivers: singleRelation(loading.drivers),
      } as LoadingRecord;
    });
    setLoadings(rows);
  }

  async function loadLoadingItems(currentLoadingId = loadingId) {
    if (!currentLoadingId) return;

    const { data, error } = await supabase
      .from("loading_items")
      .select("*")
      .eq("loading_id", currentLoadingId)
      .order("id", { ascending: false });

    if (error) {
      console.error("Unable to load loading items:", error);
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (data) setLoadingItems(data as LoadingItem[]);
  }

  function resetLoadingForm() {
    setLoadingNo("");
    setLoadingDate("");
    setBookingId("");
    setVehicleId("");
    setDriverId("");
    setRoute("");
    setAdvanceAmount("");
    setEditingLoadingId(null);
    loadingCreateRequestId.current = null;
  }

  function resetItemForm() {
    setEditingItemId(null);
    setItemName("");
    setQuantity("");
    setWeight("");
    setUnit("Kg");
    setRemarks("");
  }

  function validateLoadingForm() {
    if (!loadingNo.trim()) {
      alert(t("loadings.validation.numberRequired"));
      return false;
    }

    if (!loadingDate) {
      alert(t("loadings.validation.dateRequired"));
      return false;
    }

    if (!bookingId) {
      alert(t("loadings.validation.bookingRequired"));
      return false;
    }

    if (!tenantBookingIds.includes(bookingId)) {
      alert(t("loadings.validation.bookingRequired"));
      return false;
    }

    if (!vehicleId) {
      alert(t("loadings.validation.vehicleRequired"));
      return false;
    }

    if (!driverId) {
      alert(t("loadings.validation.driverRequired"));
      return false;
    }

    if (!route.trim()) {
      alert(t("loadings.validation.routeRequired"));
      return false;
    }

    if (advanceAmount && Number(advanceAmount) < 0) {
      alert(t("loadings.validation.advanceNonNegative"));
      return false;
    }

    return true;
  }

  function validateItemForm() {
    if (!loadingId) {
      alert(t("loadings.validation.saveFirst"));
      return false;
    }

    if (!itemName.trim()) {
      alert(t("loadings.validation.itemRequired"));
      return false;
    }

    if (!quantity || Number(quantity) <= 0) {
      alert(t("loadings.validation.quantityPositive"));
      return false;
    }

    if (!weight || Number(weight) <= 0) {
      alert(t("loadings.validation.weightPositive"));
      return false;
    }

    if (!unit.trim()) {
      alert(t("loadings.validation.unitRequired"));
      return false;
    }

    const normalizedName = itemName.trim().toLowerCase();
    if (
      loadingItems.some(
        (item) =>
          item.id !== editingItemId &&
          item.item_name.trim().toLowerCase() === normalizedName &&
          item.unit === unit
      )
    ) {
      alert(t("loadings.validation.duplicateItem"));
      return false;
    }

    return true;
  }

  function getPaymentValues() {
    const selectedBooking = bookings.find((booking) => booking.id === bookingId);
    const totalFreight = Number(selectedBooking?.freight ?? 0);
    const advance = Number(advanceAmount || 0);
    const remaining = Math.max(totalFreight - advance, 0);

    let paymentStatus = "Unpaid";

    if (advance <= 0) {
      paymentStatus = "Unpaid";
    } else if (advance >= totalFreight) {
      paymentStatus = "Paid";
    } else {
      paymentStatus = "Partial";
    }

    return {
      advance,
      remaining,
      paymentStatus,
    };
  }

  async function handleSaveLoading() {
    if (isSavingLoading || !validateLoadingForm()) return;

    const { advance, remaining, paymentStatus } = getPaymentValues();

    setIsSavingLoading(true);

    if (editingLoadingId) {
      const { error } = await supabase
        .from("loadings")
        .update({
          loading_no: loadingNo.trim(),
          loading_date: loadingDate,
          booking_id: bookingId,
          vehicle_id: vehicleId,
          driver_id: driverId,
          route: route.trim(),
          advance_amount: advance,
          remaining_amount: remaining,
          payment_status: paymentStatus,
        })
        .eq("id", editingLoadingId)
        .in("booking_id", tenantBookingIds);

      setIsSavingLoading(false);

      if (error) {
        console.error("Unable to update loading:", error);
        const backendMessage = String(error.message ?? "").toUpperCase();
        alert(backendMessage.includes("BILTY_FINANCIAL_FIELDS_LOCKED_AFTER_LOADING_MARGIN")
          ? t("loadings.messages.marginFinancialLocked")
          : backendMessage.includes("LOADING_MARGIN_BOOKING_LINK_LOCKED") || backendMessage.includes("LOADING_MARGIN_RECOGNIZED_DELETE_BLOCKED")
            ? t("loadings.messages.marginSourceLocked")
            : t("common.messages.saveFailed"));
        return;
      }

      setLoadingId(editingLoadingId);
      alert(t("loadings.messages.updatedSuccessfully"));
      await loadLoadings();
      resetLoadingForm();
      return;
    }

    const requestId = loadingCreateRequestId.current ?? crypto.randomUUID();
    loadingCreateRequestId.current = requestId;
    let createdLoadingId: unknown = null;
    let createError: { message?: string; code?: string } | null = null;
    try {
      const addaId = await loadCurrentAddaId();
      const response = await supabase.rpc("create_loading_with_adda_margin", {
        p_adda_id: addaId,
        p_loading_no: loadingNo.trim(),
        p_loading_date: loadingDate,
        p_booking_id: bookingId,
        p_vehicle_id: vehicleId,
        p_driver_id: driverId,
        p_route: route.trim(),
        p_advance_amount: advance,
        p_remaining_amount: remaining,
        p_payment_status: paymentStatus,
        p_items: [],
        p_request_id: requestId,
      } as never);
      createdLoadingId = response.data;
      createError = response.error;
    } catch (requestError) {
      setIsSavingLoading(false);
      console.error("Unable to save loading:", requestError);
      alert(t("common.messages.saveFailed"));
      return;
    }

    setIsSavingLoading(false);

    if (createError) {
      console.error("Unable to save loading:", createError);
      const backendMessage = String(createError.message ?? "").toUpperCase();
      const messageKey = backendMessage.includes("LOADING_MARGIN_BOOKING_ADDA_REQUIRED")
        ? "loadings.messages.bookingAddaRequired"
        : createError.code === "23505" || backendMessage.includes("BOOKING_ALREADY_HAS_LOADING") || backendMessage.includes("BOOKING_ALREADY_HAS_DIFFERENT_LOADING")
          ? "loadings.messages.loadingAlreadyExists"
          : backendMessage.includes("TENANT_MISMATCH") || backendMessage.includes("VEHICLE_ADDA_MISMATCH") || backendMessage.includes("DRIVER_ADDA_MISMATCH")
            ? "loadings.messages.tenantMismatch"
            : "common.messages.saveFailed";
      alert(t(messageKey));
      return;
    }

    if (createdLoadingId !== null) setLoadingId(String(createdLoadingId));

    alert(t("loadings.messages.savedSuccessfully"));
    await loadLoadings();
    resetLoadingForm();
  }

  async function handleAddItem() {
    if (isSavingItem || !validateItemForm()) return;

    setIsSavingItem(true);

    const values = {
      loading_id: loadingId,
      item_name: itemName.trim(),
      quantity: Number(quantity),
      weight: Number(weight),
      unit,
      remarks: remarks.trim(),
    };
    const { error } = editingItemId
      ? await supabase
          .from("loading_items")
          .update(values)
          .eq("id", editingItemId)
          .eq("loading_id", loadingId)
      : await supabase.from("loading_items").insert(values);

    setIsSavingItem(false);

    if (error) {
      console.error("Unable to add loading item:", error);
      alert(t("common.messages.saveFailed"));
      return;
    }

    alert(
      t(
        editingItemId
          ? "loadings.messages.itemUpdated"
          : "loadings.messages.itemAdded"
      )
    );
    await loadLoadingItems();
    await loadLoadings();
    resetItemForm();
  }

  function handleEditItem(item: LoadingItem) {
    setEditingItemId(item.id);
    setItemName(item.item_name);
    setQuantity(String(item.quantity));
    setWeight(String(item.weight));
    setUnit(item.unit);
    setRemarks(item.remarks ?? "");
  }

  async function handleDeleteItem(item: LoadingItem) {
    if (
      isSavingItem ||
      !loadingId ||
      item.loading_id !== loadingId ||
      !window.confirm(t("loadings.items.deleteConfirm"))
    ) {
      return;
    }
    setIsSavingItem(true);
    const { error } = await supabase
      .from("loading_items")
      .delete()
      .eq("id", item.id)
      .eq("loading_id", loadingId);
    if (error) {
      console.error("Unable to delete loading item:", error);
      alert(t("common.messages.deleteFailed"));
    } else {
      if (editingItemId === item.id) resetItemForm();
      await Promise.all([loadLoadingItems(loadingId), loadLoadings()]);
      alert(t("loadings.messages.itemDeleted"));
    }
    setIsSavingItem(false);
  }

  function handleViewLoading(loading: LoadingRecord) {
    setLoadingId(loading.id);
    setEditingLoadingId(null);

    alert(
      `${t("common.loadingNo")}: ${loading.loading_no}\n${t("common.date")}: ${
        loading.loading_date
      }\n${t("common.booking")}: ${loading.bookings?.booking_no ?? "-"}\n${t("common.vehicle")}: ${
        loading.vehicles?.vehicle_no ?? "-"
      }\n${t("common.driver")}: ${loading.drivers?.name ?? "-"}\n${t("common.route")}: ${
        loading.route
      }\n${t("common.party")}: ${loading.bookings?.parties?.name ?? loading.bookings?.sender_name ?? "-"}\n${t("common.freight")}: ${loading.bookings?.freight ?? 0}\n${t("common.advance")}: ${
        loading.advance_amount ?? 0
      }\n${t("common.remaining")}: ${loading.remaining_amount ?? 0}\n${t(
        "printLabels.paymentStatus"
      )}: ${t(
        `common.paymentStatus.${String(
          loading.payment_status ?? "unpaid"
        ).toLowerCase()}`
      )}\n${t("common.items")}: ${loading.loading_items?.length ?? 0}`
    );
  }

  function handleEditLoading(loading: LoadingRecord) {
    setLoadingId(loading.id);
    setEditingLoadingId(loading.id);
    setLoadingNo(loading.loading_no ?? "");
    setLoadingDate(loading.loading_date ?? "");
    setBookingId(loading.booking_id ?? "");
    setVehicleId(String(loading.vehicle_id ?? ""));
    setDriverId(String(loading.driver_id ?? ""));
    setRoute(loading.route ?? "");
    setAdvanceAmount(String(loading.advance_amount ?? 0));
  }

  async function handleDeleteLoading(loading: LoadingRecord) {
    if (isDeleting || !loading.booking_id || !tenantBookingIds.includes(loading.booking_id)) {
      return;
    }
    const confirmed = window.confirm(
      `${t("loadings.deleteConfirm")} ${loading.loading_no}?`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    let loadingError: { message?: string; code?: string } | null = null;
    try {
      const addaId = await loadCurrentAddaId();
      const response = await supabase.rpc("delete_loading_if_unrecognized", {
        p_adda_id: addaId,
        p_loading_id: Number(loading.id),
      } as never);
      loadingError = response.error;
    } catch (error) {
      loadingError = { message: error instanceof Error ? error.message : String(error) };
    }

    setIsDeleting(false);

    if (loadingError) {
      console.error("Unable to delete loading:", loadingError);
      const backendMessage = String(loadingError.message ?? "").toUpperCase();
      alert(backendMessage.includes("LOADING_MARGIN_RECOGNIZED_DELETE_BLOCKED")
        ? t("loadings.messages.marginSourceLocked")
        : backendMessage.includes("TENANT_MISMATCH")
          ? t("loadings.messages.tenantMismatch")
          : t("common.messages.deleteFailed"));
      return;
    }

    if (loadingId === loading.id) {
      setLoadingId(null);
      resetItemForm();
    }

    if (editingLoadingId === loading.id) {
      resetLoadingForm();
    }

    alert(t("loadings.messages.deletedSuccessfully"));
    await loadLoadings();

    setLoadings((prev) => prev.filter((item) => item.id !== loading.id));
  }

  function handlePrintLoadingSlipLegacy(loading: LoadingRecord) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert(t("loadings.messages.allowPopups"));
      return;
    }

    const label = (key: string) => escapeHtml(t(key));
    const value = (input: unknown) => escapeHtml(input);
    const htmlLanguage = value(language);
    const htmlDirection = value(dir);
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
                  <td>${value(item.item_name)}</td>
                  <td class="technical">${value(item.quantity)}</td>
                  <td class="technical">${value(item.weight)}</td>
                  <td>${value(item.unit)}</td>
                  <td>${value(item.remarks)}</td>
                </tr>
              `
            )
            .join("")
        : `<tr><td colspan="6" class="empty">${label("loadings.details.noItems")}</td></tr>`;

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html lang="${htmlLanguage}" dir="${htmlDirection}">
        <head>
          <title>${label("printLabels.loadingSlip")} - ${value(loading.loading_no)}</title>
          <style>
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
              direction: ${htmlDirection};
              text-align: start;
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
                <h1>${label("printLabels.loadingSlip")}</h1>
                <div class="subtitle">${PRINT_ADDA_NAME_TOKEN}</div>
              </div>
              <div class="meta">
                <div><strong>${label("common.loadingNo")}:</strong> <span class="technical">${value(loading.loading_no)}</span></div>
                <div><strong>${label("common.date")}:</strong> <span class="technical">${value(loading.loading_date)}</span></div>
              </div>
            </div>

            <div class="details">
              <div><strong>${label("common.booking")}:</strong> <span class="technical">${value(loading.bookings?.booking_no ?? "-")}</span></div>
              <div><strong>${label("common.party")}:</strong> ${value(loading.bookings?.parties?.name ?? loading.bookings?.sender_name ?? "-")}</div>
              <div><strong>${label("common.vehicle")}:</strong> <span class="technical">${value(loading.vehicles?.vehicle_no ?? "-")}</span></div>
              <div><strong>${label("common.driver")}:</strong> ${value(loading.drivers?.name ?? "-")}</div>
              <div><strong>${label("common.route")}:</strong> ${value(loading.route ?? "-")}</div>
              <div><strong>${label("common.freight")}:</strong> <span class="technical">${value(loading.bookings?.freight ?? 0)}</span></div>
              <div><strong>${label("common.advance")}:</strong> <span class="technical">${value(loading.advance_amount ?? 0)}</span></div>
              <div><strong>${label("common.remaining")}:</strong> <span class="technical">${value(loading.remaining_amount ?? 0)}</span></div>
              <div><strong>${label("printLabels.paymentStatus")}:</strong> ${label(`common.paymentStatus.${String(loading.payment_status ?? "unpaid").toLowerCase()}`)}</div>
              <div><strong>${label("printLabels.totalItems")}:</strong> ${items.length}</div>
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
                  <td>${totalQuantity}</td>
                  <td>${totalWeight}</td>
                  <td colspan="2"></td>
                </tr>
              </tfoot>
            </table>

            <div class="signatures">
              <div class="signature">${label("printLabels.preparedBy")}</div>
              <div class="signature">${label("printLabels.driverSignature")}</div>
              <div class="signature">${label("printLabels.managerSignature")}</div>
            </div>
          </div>

          <script>
            window.onload = function () {
              window.print();
            };
          </script>
        </body>
      </html>
    `, loading.bookings?.adda_id ?? null, language === "ur" ? "ur" : "en");
  }

  function handlePrintLoadingSlip(loading: LoadingRecord) {
    const items = loading.loading_items ?? [];
    const ownerAddaId = loading.booking_id != null ? loading.bookings?.adda_id ?? null : null;
    const presentation: ModulePrintPresentation = {
      documentType: "loading",
      title: printLabel("printLabels.loadingSlip"),
      documentNo: printValue(loading.loading_no),
      documentDate: printValue(loading.loading_date),
      fields: [
        { label: printLabel("common.booking"), value: printValue(loading.bookings?.booking_no) },
        { label: printLabel("common.party"), value: printValue(loading.bookings?.parties?.name ?? loading.bookings?.sender_name) },
        { label: printLabel("common.vehicle"), value: printValue(loading.vehicles?.vehicle_no) },
        { label: printLabel("common.driver"), value: printValue(loading.drivers?.name) },
        { label: printLabel("common.route"), value: printValue(loading.route) },
        { label: printLabel("common.freight"), value: printValue(loading.bookings?.freight) },
        { label: printLabel("common.advance"), value: printValue(loading.advance_amount) },
        { label: printLabel("common.remaining"), value: printValue(loading.remaining_amount) },
        { label: printLabel("printLabels.paymentStatus"), value: printValue(t(`common.paymentStatus.${String(loading.payment_status ?? "unpaid").toLowerCase()}`)) },
      ],
      tables: [{
        title: printLabel("common.items"),
        columns: [printLabel("common.item"), printLabel("common.quantity"), printLabel("common.weight"), printLabel("common.unit"), printLabel("common.remarks")],
        rows: items.map((item) => [printValue(item.item_name), printValue(item.quantity), printValue(item.weight), printValue(item.unit), printValue(item.remarks)]),
      }],
    };
    modulePrint.openPresentation(presentation, () => handlePrintLoadingSlipLegacy(loading), ownerAddaId);
  }

  return (
    <div dir={dir} className="mx-auto max-w-7xl space-y-8">
      <div>
        <h1 className="text-4xl font-bold text-gray-900">
          {t("loadings.title")}
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          {t("loadings.description")}
        </p>
      </div>

      {profileRole === "super_admin" && (
        <section className="rounded-2xl border border-blue-100 bg-white p-4 shadow-sm">
          <label htmlFor="loading-adda-scope" className="block max-w-xl text-sm font-bold text-slate-700">
            {t("common.selectAdda")}
            <select
              id="loading-adda-scope"
              className="mt-2 h-10 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              value={selectedAddaId}
              onChange={(event) => {
                setSelectedAddaId(event.target.value);
                setBookingId("");
                setLoadingId(null);
                setEditingLoadingId(null);
                setBookings([]);
                setVehicles([]);
                setDrivers([]);
                setLoadings([]);
                setLoadingItems([]);
                setTenantBookingIds([]);
              }}
            >
              <option value="">{t("common.selectAdda")}</option>
              {addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}
            </select>
          </label>
        </section>
      )}

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <LoadingForm
          loadingNo={loadingNo}
          setLoadingNo={setLoadingNo}
          loadingDate={loadingDate}
          setLoadingDate={setLoadingDate}
          bookingId={bookingId}
          setBookingId={(value) => {
            setBookingId(value);
            setAdvanceAmount("");
          }}
          bookings={bookings}
          vehicleId={vehicleId}
          setVehicleId={setVehicleId}
          driverId={driverId}
          setDriverId={setDriverId}
          route={route}
          setRoute={setRoute}
          advanceAmount={advanceAmount}
          setAdvanceAmount={setAdvanceAmount}
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
            onEditItem={handleEditItem}
            onDeleteItem={handleDeleteItem}
            onCancelEdit={resetItemForm}
            isEditing={Boolean(editingItemId)}
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
        isLoading={isLoadingData}
      />
      {modulePrint.dialog}
    </div>
  );
}

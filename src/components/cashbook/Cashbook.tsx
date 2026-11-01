"use client";

import { useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import CashbookForm from "@/components/cashbook/CashbookForm";
import CashbookCards from "@/components/cashbook/CashbookCards";
import CashbookTable from "@/components/cashbook/CashbookTable";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

export type CashbookEntryType = "Cash In" | "Cash Out";

export type CashbookPersonType =
  | "Customer"
  | "Driver"
  | "Vehicle Owner"
  | "Broker"
  | "Adda"
  | "Petrol Pump"
  | "Workshop"
  | "Other";

export type CashbookPaymentMethod =
  | "Cash"
  | "Bank"
  | "Cheque"
  | "Online Transfer"
  | "Account";

export type CashbookFilterValues = {
  fromDate: string;
  toDate: string;
  entryType: string;
  personType: string;
  paymentMethod: string;
  vehicleId: string;
  driverId: string;
  search: string;
};

export type CashbookEntryRow = {
  id: string;
  entryDate: string;
  entryType: CashbookEntryType;
  personType: CashbookPersonType;
  personName: string;
  vehicleId: string | null;
  vehicleNo: string;
  driverId: string | null;
  driverName: string;
  loadingId: string | null;
  loadingNo: string;
  paymentMethod: CashbookPaymentMethod;
  amount: number;
  description: string;
  referenceType: string | null;
  referenceId: string | null;
  createdAt: string;
  runningBalance: number;
};

export function isManualCashbookEntry(
  entry: Pick<CashbookEntryRow, "referenceType" | "referenceId">
): boolean {
  return (
    entry.referenceId === null &&
    (entry.referenceType === null || entry.referenceType === "manual")
  );
}

export type CashbookSummary = {
  openingBalance: number;
  totalCashIn: number;
  totalCashOut: number;
  closingBalance: number;
};

export type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

export type DriverOption = {
  id: string;
  name: string;
};

export type LoadingOption = {
  id: string;
  loadingNo: string;
  route: string;
  vehicleId: string | null;
  driverId: string | null;
  vehicleNo: string;
  driverName: string;
  bookingId: string | null;
  senderName: string;
};

type DatabaseRow = Record<string, unknown>;

type CashbookEntryRecord = {
  id: string;
  entry_date: string;
  entry_type: CashbookEntryType;
  person_type: CashbookPersonType;
  person_name: string;
  vehicle_id: string | number | null;
  driver_id: string | number | null;
  loading_id: string | number | null;
  payment_method: CashbookPaymentMethod;
  amount: number;
  description: string;
  reference_type: string | null;
  reference_id: string | null;
  created_at: string;
};

const defaultFilters: CashbookFilterValues = {
  fromDate: "",
  toDate: "",
  entryType: "",
  personType: "",
  paymentMethod: "",
  vehicleId: "",
  driverId: "",
  search: "",
};

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function toNumber(value: unknown) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function toStringValue(value: unknown) {
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  return "";
}

function normalizeId(value: unknown) {
  const id = toStringValue(value);
  return id || null;
}

function toEntryType(value: unknown): CashbookEntryType {
  return value === "Cash Out" ? "Cash Out" : "Cash In";
}

function toPersonType(value: unknown): CashbookPersonType {
  const personType = toStringValue(value);

  if (
    personType === "Customer" ||
    personType === "Driver" ||
    personType === "Vehicle Owner" ||
    personType === "Broker" ||
    personType === "Adda" ||
    personType === "Petrol Pump" ||
    personType === "Workshop" ||
    personType === "Other"
  ) {
    return personType;
  }

  return "Other";
}

function toPaymentMethod(value: unknown): CashbookPaymentMethod {
  const paymentMethod = toStringValue(value);

  if (
    paymentMethod === "Cash" ||
    paymentMethod === "Bank" ||
    paymentMethod === "Cheque" ||
    paymentMethod === "Online Transfer" ||
    paymentMethod === "Account"
  ) {
    return paymentMethod;
  }

  return "Cash";
}

function mapCashbookEntry(row: DatabaseRow): CashbookEntryRecord {
  return {
    id: toStringValue(row.id),
    entry_date: toStringValue(row.entry_date),
    entry_type: toEntryType(row.entry_type),
    person_type: toPersonType(row.person_type),
    person_name: toStringValue(row.person_name),
    vehicle_id: normalizeId(row.vehicle_id),
    driver_id: normalizeId(row.driver_id),
    loading_id: normalizeId(row.loading_id),
    payment_method: toPaymentMethod(row.payment_method),
    amount: toNumber(row.amount),
    description: toStringValue(row.description),
    reference_type: toStringValue(row.reference_type) || null,
    reference_id: toStringValue(row.reference_id) || null,
    created_at: toStringValue(row.created_at),
  };
}

function mapVehicle(row: DatabaseRow): VehicleOption {
  return {
    id: toStringValue(row.id),
    vehicleNo: toStringValue(row.vehicle_no) || "-",
    ownerName: toStringValue(row.owner_name) || "-",
  };
}

function mapDriver(row: DatabaseRow): DriverOption {
  return {
    id: toStringValue(row.id),
    name: toStringValue(row.name) || "-",
  };
}

function getSingleRelation<T>(relation: T | T[] | null | undefined): T | null {
  if (Array.isArray(relation)) {
    return relation[0] ?? null;
  }

  return relation ?? null;
}

function mapLoading(row: DatabaseRow): LoadingOption {
  const vehicle = getSingleRelation(
    row.vehicles as { vehicle_no?: unknown } | { vehicle_no?: unknown }[] | null
  );
  const driver = getSingleRelation(
    row.drivers as { name?: unknown } | { name?: unknown }[] | null
  );
  const booking = getSingleRelation(
    row.bookings as
      | { sender_name?: unknown }
      | { sender_name?: unknown }[]
      | null
  );

  return {
    id: toStringValue(row.id),
    loadingNo: toStringValue(row.loading_no) || "-",
    route: toStringValue(row.route) || "-",
    vehicleId: normalizeId(row.vehicle_id),
    driverId: normalizeId(row.driver_id),
    vehicleNo: toStringValue(vehicle?.vehicle_no) || "-",
    driverName: toStringValue(driver?.name) || "-",
    bookingId: normalizeId(row.booking_id),
    senderName: toStringValue(booking?.sender_name) || "Customer",
  };
}

export default function Cashbook() {
  const { t, dir } = useLanguage();
  const [entryDate, setEntryDate] = useState("");
  const [entryType, setEntryType] = useState<CashbookEntryType>("Cash In");
  const [personType, setPersonType] = useState<CashbookPersonType>("Customer");
  const [personName, setPersonName] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [driverId, setDriverId] = useState("");
  const [loadingId, setLoadingId] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<CashbookPaymentMethod>("Cash");
  const [amount, setAmount] = useState("");
  const [description, setDescription] = useState("");

  const [entries, setEntries] = useState<CashbookEntryRecord[]>([]);
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [drivers, setDrivers] = useState<DriverOption[]>([]);
  const [loadings, setLoadings] = useState<LoadingOption[]>([]);
  const [currentAddaId, setCurrentAddaId] = useState<string | null>(null);
  const [filters, setFilters] = useState<CashbookFilterValues>(defaultFilters);

  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState("");
  const saveInProgressRef = useRef(false);
  const deleteInProgressRef = useRef(false);
  const syncInProgressRef = useRef(false);

  const initialDataLoader = useEffectEvent(async () => {
    setIsLoading(true);
    setErrorMessage("");
    try {
      const addaId = await loadCurrentAddaId();
      setCurrentAddaId(addaId);
      const loadingIds = await loadLoadings(addaId);
      await Promise.all([
        loadCashbookEntries(addaId),
        loadVehicles(addaId),
        loadDrivers(addaId),
      ]);
      if (loadingIds.length === 0) setLoadings([]);
    } catch (error) {
      console.error("Unable to load Cashbook data:", error);
      setErrorMessage(t("cashbook.messages.loadFailed"));
    } finally {
      setIsLoading(false);
    }
  });

  useEffect(() => {
    const timer = window.setTimeout(() => void initialDataLoader(), 0);
    return () => window.clearTimeout(timer);
  }, []);

  async function loadCurrentAddaId() {
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) throw authError ?? new Error("No user.");
    const { data, error } = await supabase
      .from("profiles").select("adda_id").eq("id", authData.user.id).maybeSingle();
    if (error || !data?.adda_id) throw error ?? new Error("No Adda.");
    return String(data.adda_id);
  }

  async function loadCashbookEntries(addaId: string) {
    const { data, error } = await supabase.rpc("get_cashbook_entries", {
      p_adda_id: addaId,
    });

    if (error) {
      console.error("Unable to load cashbook entries:", error);
      setErrorMessage(t("cashbook.messages.loadFailed"));
      setEntries([]);
      return;
    }

    setEntries(((data ?? []) as DatabaseRow[]).map(mapCashbookEntry));
  }

  async function loadVehicles(addaId: string) {
    const { data, error } = await supabase
      .from("vehicles")
      .select("id, vehicle_no, owner_name")
      .eq("adda_id", addaId)
      .order("vehicle_no", { ascending: true });

    if (error) {
      console.error("Unable to load Cashbook vehicles:", error);
      setErrorMessage(t("cashbook.messages.loadFailed"));
      setVehicles([]);
      return;
    }

    setVehicles(((data ?? []) as DatabaseRow[]).map(mapVehicle));
  }

  async function loadDrivers(addaId: string) {
    const { data, error } = await supabase
      .from("drivers")
      .select("id, name")
      .eq("adda_id", addaId)
      .order("name", { ascending: true });

    if (error) {
      console.error("Unable to load Cashbook drivers:", error);
      setErrorMessage(t("cashbook.messages.loadFailed"));
      setDrivers([]);
      return;
    }

    setDrivers(((data ?? []) as DatabaseRow[]).map(mapDriver));
  }

  async function loadLoadings(addaId: string): Promise<string[]> {
    const { data: bookingRows, error: bookingError } = await supabase
      .from("bookings").select("id").eq("adda_id", addaId);
    if (bookingError) throw bookingError;
    const bookingIds = (bookingRows ?? []).map((booking) => String(booking.id));
    if (bookingIds.length === 0) {
      setLoadings([]);
      return [];
    }
    const { data, error } = await supabase
      .from("loadings")
      .select(
        `
        id,
        loading_no,
        vehicle_id,
        driver_id,
        booking_id,
        route,
        vehicles(vehicle_no),
        drivers(name),
        bookings(sender_name)
      `
      )
      .in("booking_id", bookingIds)
      .order("loading_no", { ascending: false });

    if (error) {
      console.error("Unable to load Cashbook loadings:", error);
      setErrorMessage(t("cashbook.messages.loadFailed"));
      setLoadings([]);
      return [];
    }

    const rows = ((data ?? []) as DatabaseRow[]).map(mapLoading);
    setLoadings(rows);
    return rows.map((loading) => loading.id);
  }

  function resetForm() {
    setEditingId(null);
    setEntryDate("");
    setEntryType("Cash In");
    setPersonType("Customer");
    setPersonName("");
    setVehicleId("");
    setDriverId("");
    setLoadingId("");
    setPaymentMethod("Cash");
    setAmount("");
    setDescription("");
  }

  function validateForm() {
    if (!entryDate) {
      alert(t("cashbook.validation.dateRequired"));
      return false;
    }

    if (!entryType) {
      alert(t("cashbook.validation.entryTypeRequired"));
      return false;
    }

    if (!personType) {
      alert(t("cashbook.validation.personTypeRequired"));
      return false;
    }

    if (!personName.trim()) {
      alert(t("cashbook.validation.personNameRequired"));
      return false;
    }

    if (!paymentMethod) {
      alert(t("cashbook.validation.paymentMethodRequired"));
      return false;
    }

    const numericAmount = Number(amount);
    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      alert(t("cashbook.validation.amountPositive"));
      return false;
    }

    if (!description.trim()) {
      alert(t("cashbook.validation.descriptionRequired"));
      return false;
    }

    return true;
  }

  async function handleSaveEntry() {
    if (saveInProgressRef.current || isSaving || !validateForm()) return;

    saveInProgressRef.current = true;
    setIsSaving(true);

    const values = {
      p_entry_date: entryDate,
      p_entry_type: entryType,
      p_person_type: personType,
      p_person_name: personName.trim(),
      p_vehicle_id: vehicleId || null,
      p_driver_id: driverId || null,
      p_loading_id: loadingId ? Number(loadingId) : null,
      p_payment_method: paymentMethod,
      p_amount: Number(amount),
      p_description: description.trim(),
      p_adda_id: currentAddaId,
      p_id: editingId ? Number(editingId) : null,
    };
    try {
      if (!currentAddaId) throw new Error("No Adda.");
      const { error } = await supabase.rpc("save_manual_cashbook_entry", values);

      if (error) {
        console.error("Unable to save Cashbook entry:", error);
        alert(t("cashbook.messages.saveFailed"));
        return;
      }

      alert(t(editingId ? "cashbook.messages.updated" : "cashbook.messages.saved"));
      resetForm();
      await loadCashbookEntries(currentAddaId);
    } catch (error) {
      console.error("Unable to save Cashbook entry:", error);
      alert(t("cashbook.messages.saveFailed"));
    } finally {
      saveInProgressRef.current = false;
      setIsSaving(false);
    }
  }

  function handleEditEntry(row: CashbookEntryRow) {
    if (!isManualCashbookEntry(row)) {
      alert(t("cashbook.messages.syncedEntryLocked"));
      return;
    }
    setEditingId(row.id);
    setEntryDate(row.entryDate);
    setEntryType(row.entryType);
    setPersonType(row.personType);
    setPersonName(row.personName);
    setVehicleId(row.vehicleId ?? "");
    setDriverId(row.driverId ?? "");
    setLoadingId(row.loadingId ?? "");
    setPaymentMethod(row.paymentMethod);
    setAmount(String(row.amount));
    setDescription(row.description);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function handleDeleteEntry(row: CashbookEntryRow) {
    if (deleteInProgressRef.current || deletingId || !isManualCashbookEntry(row)) {
      if (!isManualCashbookEntry(row)) alert(t("cashbook.messages.syncedEntryLocked"));
      return;
    }
    if (!window.confirm(t("cashbook.messages.deleteConfirm"))) return;
    deleteInProgressRef.current = true;
    setDeletingId(row.id);
    try {
      if (!currentAddaId) throw new Error("No Adda.");
      const { error } = await supabase.rpc("delete_manual_cashbook_entry", {
        p_id: Number(row.id),
        p_adda_id: currentAddaId,
      });
      if (error) {
        console.error("Unable to delete Cashbook entry:", error);
        alert(t(error.code === "23503" ? "cashbook.messages.linkedRecords" : "cashbook.messages.deleteFailed"));
      } else {
        setEntries((current) => current.filter((entry) => entry.id !== row.id));
        if (editingId === row.id) resetForm();
        alert(t("cashbook.messages.deleted"));
      }
    } catch (error) {
      console.error("Unable to delete Cashbook entry:", error);
      alert(t("cashbook.messages.deleteFailed"));
    } finally {
      deleteInProgressRef.current = false;
      setDeletingId(null);
    }
  }

  async function handleSyncAutoEntries() {
    if (syncInProgressRef.current) return;
    syncInProgressRef.current = true;
    setIsSyncing(true);
    setErrorMessage("");

    try {
      if (!currentAddaId) throw new Error("No Adda.");
      await loadCashbookEntries(currentAddaId);
      alert(t("cashbook.messages.synced"));
    } catch (error) {
      console.error("Unable to sync Cashbook:", error);
      const message = t("cashbook.messages.syncFailed");
      setErrorMessage(message);
      alert(message);
    } finally {
      syncInProgressRef.current = false;
      setIsSyncing(false);
    }
  }

  function handleResetFilters() {
    setFilters(defaultFilters);
  }

  const enrichedRows = useMemo<CashbookEntryRow[]>(() => {
    const sortedEntries = [...entries].sort((first, second) => {
      const firstDate = `${first.entry_date || ""} ${first.created_at || ""}`;
      const secondDate = `${second.entry_date || ""} ${second.created_at || ""}`;
      return firstDate.localeCompare(secondDate);
    });

    let runningBalance = 0;

    return sortedEntries.map((entry) => {
      const vehicle = vehicles.find(
        (item) => item.id === normalizeId(entry.vehicle_id)
      );
      const driver = drivers.find(
        (item) => item.id === normalizeId(entry.driver_id)
      );
      const loading = loadings.find(
        (item) => item.id === normalizeId(entry.loading_id)
      );

      runningBalance +=
        entry.entry_type === "Cash In" ? entry.amount : -entry.amount;

      return {
        id: entry.id,
        entryDate: entry.entry_date,
        entryType: entry.entry_type,
        personType: entry.person_type,
        personName: entry.person_name,
        vehicleId: normalizeId(entry.vehicle_id),
        vehicleNo: vehicle?.vehicleNo ?? loading?.vehicleNo ?? "-",
        driverId: normalizeId(entry.driver_id),
        driverName: driver?.name ?? loading?.driverName ?? "-",
        loadingId: normalizeId(entry.loading_id),
        loadingNo: loading?.loadingNo ?? "-",
        paymentMethod: entry.payment_method,
        amount: entry.amount,
        description:
          entry.reference_type === "payment_receipt"
            ? t("cashbook.sources.partyPayment")
            : entry.reference_type === "loading_advance"
              ? t("cashbook.sources.loadingAdvance")
              : entry.reference_type === "voucher"
                ? t("cashbook.sources.voucher")
                : entry.reference_type === "petrol_pump_payment"
                  ? t("cashbook.sources.petrolPumpPayment")
                  : entry.description,
        referenceType: entry.reference_type,
        referenceId: entry.reference_id,
        createdAt: entry.created_at,
        runningBalance,
      };
    });
  }, [drivers, entries, loadings, t, vehicles]);

  const filteredRows = useMemo(() => {
    const keyword = filters.search.trim().toLowerCase();

    return enrichedRows.filter((row) => {
      if (filters.fromDate && row.entryDate < filters.fromDate) {
        return false;
      }

      if (filters.toDate && row.entryDate > filters.toDate) {
        return false;
      }

      if (filters.entryType && row.entryType !== filters.entryType) {
        return false;
      }

      if (filters.personType && row.personType !== filters.personType) {
        return false;
      }

      if (
        filters.paymentMethod &&
        row.paymentMethod !== filters.paymentMethod
      ) {
        return false;
      }
      if (filters.vehicleId && row.vehicleId !== filters.vehicleId) return false;
      if (filters.driverId && row.driverId !== filters.driverId) return false;

      if (!keyword) {
        return true;
      }

      const searchableText = [
        row.personName,
        row.vehicleNo,
        row.driverName,
        row.loadingNo,
        row.description,
        row.referenceType ?? "",
        row.paymentMethod,
      ]
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [enrichedRows, filters]);

  const summary = useMemo<CashbookSummary>(() => {
    const openingBalance = 0;
    const totalCashIn = filteredRows
      .filter((row) => row.entryType === "Cash In")
      .reduce((total, row) => total + row.amount, 0);
    const totalCashOut = filteredRows
      .filter((row) => row.entryType === "Cash Out")
      .reduce((total, row) => total + row.amount, 0);
    const closingBalance = openingBalance + totalCashIn - totalCashOut;

    return {
      openingBalance,
      totalCashIn,
      totalCashOut,
      closingBalance,
    };
  }, [filteredRows]);

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <ModulePageHeading icon="cashbook" accent="gold" title={t("cashbook.title")} description={t("cashbook.description")} />

          <button
            type="button"
            onClick={handleSyncAutoEntries}
            disabled={isSyncing}
            className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
          >
            {isSyncing
              ? t("cashbook.states.syncing")
              : t("cashbook.actions.syncAutoEntries")}
          </button>
        </div>
      </div>

      <CashbookCards summary={summary} />

      <CashbookForm
        voiceContextKey={`${currentAddaId ?? ""}:${editingId ?? "new"}`}
        entryDate={entryDate}
        setEntryDate={setEntryDate}
        entryType={entryType}
        setEntryType={setEntryType}
        personType={personType}
        setPersonType={setPersonType}
        personName={personName}
        setPersonName={setPersonName}
        vehicleId={vehicleId}
        setVehicleId={setVehicleId}
        driverId={driverId}
        setDriverId={setDriverId}
        loadingId={loadingId}
        setLoadingId={setLoadingId}
        paymentMethod={paymentMethod}
        setPaymentMethod={setPaymentMethod}
        amount={amount}
        setAmount={setAmount}
        description={description}
        setDescription={setDescription}
        vehicles={vehicles}
        drivers={drivers}
        loadings={loadings}
        onSave={handleSaveEntry}
        onCancel={resetForm}
        isEditing={Boolean(editingId)}
        isSaving={isSaving}
      />

      <CashbookTable
        rows={filteredRows}
        addaId={currentAddaId}
        filters={filters}
        setFilters={setFilters}
        onReset={handleResetFilters}
        onSync={handleSyncAutoEntries}
        isSyncing={isSyncing}
        isLoading={isLoading}
        errorMessage={errorMessage}
        vehicles={vehicles}
        drivers={drivers}
        deletingId={deletingId}
        onEdit={handleEditEntry}
        onDelete={handleDeleteEntry}
      />
    </div>
  );
}

"use client";

import { useEffect, useMemo, useState } from "react";
import CashbookForm from "@/components/cashbook/CashbookForm";
import CashbookCards from "@/components/cashbook/CashbookCards";
import CashbookTable from "@/components/cashbook/CashbookTable";
import { supabase } from "@/lib/supabase/client";

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

type PaymentReceiptRecord = {
  id: string;
  receipt_no: string;
  receipt_date: string;
  loading_id: string | number | null;
  amount: number;
  payment_method: CashbookPaymentMethod;
  remarks: string;
};

type ExpenseRecord = {
  id: string;
  loading_id: string | number | null;
  expense_date: string;
  created_at: string;
};

type ExpenseItemRecord = {
  expense_id: string;
  expense_type: string;
  amount: number;
  remarks: string;
};

const defaultFilters: CashbookFilterValues = {
  fromDate: "",
  toDate: "",
  entryType: "",
  personType: "",
  paymentMethod: "",
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

function toReferenceId(value: unknown) {
  return toStringValue(value);
}

function toDatabaseRelationId(value: string) {
  if (!value) return null;
  return /^\d+$/.test(value) ? Number(value) : value;
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

function mapPaymentReceipt(row: DatabaseRow): PaymentReceiptRecord {
  return {
    id: toStringValue(row.id),
    receipt_no: toStringValue(row.receipt_no),
    receipt_date: toStringValue(row.receipt_date),
    loading_id: normalizeId(row.loading_id),
    amount: toNumber(row.amount),
    payment_method: toPaymentMethod(row.payment_method),
    remarks: toStringValue(row.remarks),
  };
}

function mapExpense(row: DatabaseRow): ExpenseRecord {
  return {
    id: toStringValue(row.id),
    loading_id: normalizeId(row.loading_id),
    expense_date:
      toStringValue(row.expense_date) ||
      toStringValue(row.date) ||
      toStringValue(row.created_at),
    created_at: toStringValue(row.created_at),
  };
}

function mapExpenseItem(row: DatabaseRow): ExpenseItemRecord {
  return {
    expense_id: toStringValue(row.expense_id),
    expense_type: toStringValue(row.expense_type) || "Expense",
    amount: toNumber(row.amount),
    remarks: toStringValue(row.remarks),
  };
}

export default function Cashbook() {
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
  const [filters, setFilters] = useState<CashbookFilterValues>(defaultFilters);

  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    loadInitialData();
  }, []);

  async function loadInitialData() {
    setIsLoading(true);
    setErrorMessage("");

    await Promise.all([
      loadCashbookEntries(),
      loadVehicles(),
      loadDrivers(),
      loadLoadings(),
    ]);

    setIsLoading(false);
  }

  async function loadCashbookEntries() {
    const { data, error } = await supabase
      .from("cashbook_entries")
      .select("*")
      .order("entry_date", { ascending: true })
      .order("created_at", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setEntries([]);
      return;
    }

    setEntries(((data ?? []) as DatabaseRow[]).map(mapCashbookEntry));
  }

  async function loadVehicles() {
    const { data, error } = await supabase
      .from("vehicles")
      .select("id, vehicle_no, owner_name")
      .order("vehicle_no", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setVehicles([]);
      return;
    }

    setVehicles(((data ?? []) as DatabaseRow[]).map(mapVehicle));
  }

  async function loadDrivers() {
    const { data, error } = await supabase
      .from("drivers")
      .select("id, name")
      .order("name", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setDrivers([]);
      return;
    }

    setDrivers(((data ?? []) as DatabaseRow[]).map(mapDriver));
  }

  async function loadLoadings() {
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
      .order("loading_no", { ascending: false });

    if (error) {
      setErrorMessage(error.message);
      setLoadings([]);
      return;
    }

    setLoadings(((data ?? []) as DatabaseRow[]).map(mapLoading));
  }

  function resetForm() {
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
      alert("Date is required.");
      return false;
    }

    if (!entryType) {
      alert("Entry type is required.");
      return false;
    }

    if (!personType) {
      alert("Person type is required.");
      return false;
    }

    if (!personName.trim()) {
      alert("Person name is required.");
      return false;
    }

    if (!paymentMethod) {
      alert("Payment method is required.");
      return false;
    }

    if (!amount || Number(amount) <= 0) {
      alert("Amount must be greater than 0.");
      return false;
    }

    if (!description.trim()) {
      alert("Description is required.");
      return false;
    }

    return true;
  }

  async function handleSaveEntry() {
    if (!validateForm()) return;

    setIsSaving(true);

    const { error } = await supabase.from("cashbook_entries").insert({
      entry_date: entryDate,
      entry_type: entryType,
      person_type: personType,
      person_name: personName.trim(),
      vehicle_id: toDatabaseRelationId(vehicleId),
      driver_id: toDatabaseRelationId(driverId),
      loading_id: toDatabaseRelationId(loadingId),
      payment_method: paymentMethod,
      amount: Number(amount),
      description: description.trim(),
      reference_type: "manual",
      reference_id: null,
    });

    setIsSaving(false);

    if (error) {
      alert(error.message);
      return;
    }

    alert("Cashbook entry saved successfully!");
    resetForm();
    await loadCashbookEntries();
  }

  async function fetchPaymentReceipts() {
    const { data, error } = await supabase
      .from("payment_receipts")
      .select("id, receipt_no, receipt_date, loading_id, amount, payment_method, remarks");

    if (error) {
      throw new Error(error.message);
    }

    return ((data ?? []) as DatabaseRow[]).map(mapPaymentReceipt);
  }

  async function fetchExpenses() {
    const { data, error } = await supabase
      .from("expenses")
      .select("*");

    if (error) {
      throw new Error(error.message);
    }

    return ((data ?? []) as DatabaseRow[]).map(mapExpense);
  }

  async function fetchExpenseItems() {
    const { data, error } = await supabase
      .from("expense_items")
      .select("expense_id, expense_type, amount, remarks");

    if (error) {
      throw new Error(error.message);
    }

    return ((data ?? []) as DatabaseRow[]).map(mapExpenseItem);
  }

  async function fetchExistingReferences() {
    const { data, error } = await supabase
      .from("cashbook_entries")
      .select("reference_type, reference_id")
      .not("reference_type", "is", null)
      .not("reference_id", "is", null);

    if (error) {
      throw new Error(error.message);
    }

    return new Set(
      ((data ?? []) as DatabaseRow[]).map(
        (row) =>
          `${toStringValue(row.reference_type)}:${toStringValue(
            row.reference_id
          )}`
      )
    );
  }

  async function handleSyncAutoEntries() {
    setIsSyncing(true);
    setErrorMessage("");

    try {
      const [paymentReceipts, expenses, expenseItems, existingReferences] =
        await Promise.all([
          fetchPaymentReceipts(),
          fetchExpenses(),
          fetchExpenseItems(),
          fetchExistingReferences(),
        ]);

      const entriesToInsert: DatabaseRow[] = [];

      paymentReceipts.forEach((receipt) => {
        const referenceId = toReferenceId(receipt.id);
        const referenceKey = `payment_receipt:${referenceId}`;

        if (existingReferences.has(referenceKey)) return;

        const loading = loadings.find(
          (item) => item.id === normalizeId(receipt.loading_id)
        );

        entriesToInsert.push({
          entry_date: receipt.receipt_date,
          entry_type: "Cash In",
          person_type: "Customer",
          person_name: loading?.senderName || "Customer",
          vehicle_id: toDatabaseRelationId(loading?.vehicleId ?? ""),
          driver_id: toDatabaseRelationId(loading?.driverId ?? ""),
          loading_id: toDatabaseRelationId(normalizeId(receipt.loading_id) ?? ""),
          payment_method: receipt.payment_method,
          amount: receipt.amount,
          description: `Freight payment received against receipt ${
            receipt.receipt_no || referenceId
          }`,
          reference_type: "payment_receipt",
          reference_id: referenceId,
        });
      });

      expenses.forEach((expense) => {
        const referenceId = toReferenceId(expense.id);
        const referenceKey = `expense:${referenceId}`;

        if (existingReferences.has(referenceKey)) return;

        const loading = loadings.find(
          (item) => item.id === normalizeId(expense.loading_id)
        );
        const items = expenseItems.filter(
          (item) => item.expense_id === expense.id
        );

        const totalExpense = items.reduce(
          (total, item) => total + item.amount,
          0
        );

        if (totalExpense <= 0) return;

        const expenseNames = Array.from(
          new Set(items.map((item) => item.expense_type).filter(Boolean))
        ).join(", ");

        entriesToInsert.push({
          entry_date: expense.expense_date || expense.created_at,
          entry_type: "Cash Out",
          person_type: "Other",
          person_name: expenseNames || "Expense",
          vehicle_id: toDatabaseRelationId(loading?.vehicleId ?? ""),
          driver_id: toDatabaseRelationId(loading?.driverId ?? ""),
          loading_id: toDatabaseRelationId(normalizeId(expense.loading_id) ?? ""),
          payment_method: "Cash",
          amount: totalExpense,
          description: `${expenseNames || "Expense"}${
            loading?.loadingNo ? ` against loading ${loading.loadingNo}` : ""
          }`,
          reference_type: "expense",
          reference_id: referenceId,
        });
      });

      if (entriesToInsert.length > 0) {
        const { error } = await supabase
          .from("cashbook_entries")
          .insert(entriesToInsert);

        if (error) {
          throw new Error(error.message);
        }
      }

      await loadCashbookEntries();
      alert("Cashbook auto entries synced successfully!");
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to sync cashbook.";
      setErrorMessage(message);
      alert(message);
    } finally {
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
        description: entry.description,
        referenceType: entry.reference_type,
        referenceId: entry.reference_id,
        createdAt: entry.created_at,
        runningBalance,
      };
    });
  }, [drivers, entries, loadings, vehicles]);

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
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">Cashbook</h1>
            <p className="mt-2 text-base font-medium text-gray-900">
              Complete daily office cash khata for cash received, cash paid,
              advances, expenses and automatic freight receipts.
            </p>
          </div>

          <button
            type="button"
            onClick={handleSyncAutoEntries}
            disabled={isSyncing}
            className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
          >
            {isSyncing ? "Syncing..." : "Sync Auto Entries"}
          </button>
        </div>
      </div>

      <CashbookCards summary={summary} />

      <CashbookForm
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
        isSaving={isSaving}
      />

      <CashbookTable
        rows={filteredRows}
        filters={filters}
        setFilters={setFilters}
        onReset={handleResetFilters}
        onSync={handleSyncAutoEntries}
        isSyncing={isSyncing}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}
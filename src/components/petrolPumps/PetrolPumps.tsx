"use client";

import { useEffect, useMemo, useState } from "react";
import PetrolPumpForm from "@/components/petrolPumps/PetrolPumpForm";
import PetrolPumpCards from "@/components/petrolPumps/PetrolPumpCards";
import PetrolPumpTable from "@/components/petrolPumps/PetrolPumpTable";
import { supabase } from "@/lib/supabase/client";

export type PetrolPumpDieselEntry = {
  id: number;
  petrolPumpId: string;
  entryDate: string;
  vehicleNo: string;
  loadingNo: string;
  slipNo: string;
  liters: number;
  rate: number;
  totalAmount: number;
  paidAmount: number;
  remainingAmount: number;
  paymentStatus: string;
};

export type PetrolPumpRow = {
  id: string;
  pumpName: string;
  ownerName: string;
  phone: string;
  address: string;
  openingBalance: number;
  totalDiesel: number;
  totalPaid: number;
  currentBalance: number;
  createdAt: string;
  dieselEntries: PetrolPumpDieselEntry[];
};

export type PetrolPumpSummary = {
  totalPumps: number;
  totalOpeningBalance: number;
  totalDiesel: number;
  totalPaid: number;
  totalOutstanding: number;
};

export type PetrolPumpFilterValues = {
  search: string;
};

type PetrolPumpDatabaseRow = {
  id: string;
  pump_name: string | null;
  owner_name: string | null;
  phone: string | null;
  address: string | null;
  opening_balance: number | string | null;
  created_at: string | null;
};

type PetrolPumpPaymentDatabaseRow = {
  id: number;
  petrol_pump_id: string | null;
  amount: number | string | null;
};

type VehicleRelation = {
  vehicle_no: string | null;
};

type LoadingRelation = {
  loading_no: string | null;
};

type RelatedRecord<T> = T | T[] | null;

type DieselEntryDatabaseRow = {
  id: number;
  petrol_pump_id: string | null;
  entry_date: string | null;
  vehicle_id: string | null;
  loading_id: number | null;
  slip_no: string | null;
  liters: number | string | null;
  rate: number | string | null;
  total_amount: number | string | null;
  paid_amount: number | string | null;
  remaining_amount: number | string | null;
  payment_status: string | null;
  vehicles?: RelatedRecord<VehicleRelation>;
  loadings?: RelatedRecord<LoadingRelation>;
};

const defaultSearch = "";

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function getSingleRelation<T>(relation: RelatedRecord<T>): T | null {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation ?? null;
}

export default function PetrolPumps() {
  const [pumpName, setPumpName] = useState("");
  const [ownerName, setOwnerName] = useState("");
  const [phone, setPhone] = useState("");
  const [address, setAddress] = useState("");
  const [openingBalance, setOpeningBalance] = useState("");

  const [pumps, setPumps] = useState<PetrolPumpDatabaseRow[]>([]);
  const [dieselEntries, setDieselEntries] = useState<
    PetrolPumpDieselEntry[]
  >([]);
  const [payments, setPayments] = useState<PetrolPumpPaymentDatabaseRow[]>([]);
  const [search, setSearch] = useState(defaultSearch);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    loadInitialData();
  }, []);

  async function loadInitialData() {
    setIsLoading(true);
    setErrorMessage("");

    await Promise.all([loadPetrolPumps(), loadDieselEntries(), loadPayments()]);

    setIsLoading(false);
  }

  async function loadPetrolPumps() {
    const { data, error } = await supabase
      .from("petrol_pumps")
      .select(
        "id, pump_name, owner_name, phone, address, opening_balance, created_at"
      )
      .order("pump_name", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setPumps([]);
      return;
    }

    setPumps((data ?? []) as PetrolPumpDatabaseRow[]);
  }

  async function loadDieselEntries() {
    const { data, error } = await supabase
      .from("diesel_entries")
      .select(
        `
        id,
        petrol_pump_id,
        entry_date,
        vehicle_id,
        loading_id,
        slip_no,
        liters,
        rate,
        total_amount,
        paid_amount,
        remaining_amount,
        payment_status,
        vehicles(vehicle_no),
        loadings(loading_no)
      `
      )
      .order("entry_date", { ascending: false });

    if (error) {
      setErrorMessage(error.message);
      setDieselEntries([]);
      return;
    }

    setDieselEntries(
      ((data ?? []) as DieselEntryDatabaseRow[]).map((entry) => {
        const vehicle = getSingleRelation(entry.vehicles ?? null);
        const loading = getSingleRelation(entry.loadings ?? null);

        return {
          id: entry.id,
          petrolPumpId: entry.petrol_pump_id ?? "",
          entryDate: entry.entry_date ?? "",
          vehicleNo: vehicle?.vehicle_no ?? "-",
          loadingNo: loading?.loading_no ?? "-",
          slipNo: entry.slip_no ?? "-",
          liters: toNumber(entry.liters),
          rate: toNumber(entry.rate),
          totalAmount: toNumber(entry.total_amount),
          paidAmount: toNumber(entry.paid_amount),
          remainingAmount: toNumber(entry.remaining_amount),
          paymentStatus: entry.payment_status ?? "Unpaid",
        };
      })
    );
  }

  async function loadPayments() {
    const { data, error } = await supabase
      .from("petrol_pump_payments")
      .select("id, petrol_pump_id, amount");

    if (error) {
      setErrorMessage(error.message);
      setPayments([]);
      return;
    }

    setPayments((data ?? []) as PetrolPumpPaymentDatabaseRow[]);
  }

  function resetForm() {
    setPumpName("");
    setOwnerName("");
    setPhone("");
    setAddress("");
    setOpeningBalance("");
    setEditingId(null);
  }

  function validateForm() {
    if (!pumpName.trim()) {
      alert("Pump name is required.");
      return false;
    }

    if (Number(openingBalance || 0) < 0) {
      alert("Opening balance cannot be negative.");
      return false;
    }

    return true;
  }

  async function handleSave() {
    if (!validateForm()) return;

    setIsSaving(true);

    const payload = {
      pump_name: pumpName.trim(),
      owner_name: ownerName.trim(),
      phone: phone.trim(),
      address: address.trim(),
      opening_balance: Number(openingBalance || 0),
    };

    const result = editingId
      ? await supabase.from("petrol_pumps").update(payload).eq("id", editingId)
      : await supabase.from("petrol_pumps").insert(payload);

    setIsSaving(false);

    if (result.error) {
      alert(result.error.message);
      return;
    }

    alert(
      editingId
        ? "Petrol pump updated successfully!"
        : "Petrol pump saved successfully!"
    );

    resetForm();
    await loadPetrolPumps();
  }

  function handleEdit(row: PetrolPumpRow) {
    setEditingId(row.id);
    setPumpName(row.pumpName);
    setOwnerName(row.ownerName === "-" ? "" : row.ownerName);
    setPhone(row.phone === "-" ? "" : row.phone);
    setAddress(row.address === "-" ? "" : row.address);
    setOpeningBalance(String(row.openingBalance));
  }

  async function handleDelete(row: PetrolPumpRow) {
    if (row.dieselEntries.length > 0) {
      alert(
        "This petrol pump cannot be deleted because diesel records are linked with it."
      );
      return;
    }

    const confirmed = window.confirm(`Delete petrol pump ${row.pumpName}?`);

    if (!confirmed) return;

    setIsDeleting(true);

    const { error } = await supabase
      .from("petrol_pumps")
      .delete()
      .eq("id", row.id);

    setIsDeleting(false);

    if (error) {
      alert(error.message);
      return;
    }

    if (editingId === row.id) resetForm();

    alert("Petrol pump deleted successfully!");
    await loadPetrolPumps();
  }

  const rows = useMemo<PetrolPumpRow[]>(() => {
    return pumps.map((pump) => {
      const linkedDiesel = dieselEntries.filter(
        (entry) => entry.petrolPumpId === pump.id
      );
      const linkedPayments = payments.filter(
        (payment) => payment.petrol_pump_id === pump.id
      );

      const opening = toNumber(pump.opening_balance);
      const totalDiesel = linkedDiesel.reduce(
        (total, entry) => total + entry.totalAmount,
        0
      );
      const manualPayments = linkedPayments.reduce(
        (total, payment) => total + toNumber(payment.amount),
        0
      );
      const currentBalance = opening + totalDiesel - manualPayments;

      return {
        id: pump.id,
        pumpName: pump.pump_name ?? "-",
        ownerName: pump.owner_name ?? "-",
        phone: pump.phone ?? "-",
        address: pump.address ?? "-",
        openingBalance: opening,
        totalDiesel,
        totalPaid: manualPayments,
        currentBalance,
        createdAt: pump.created_at ?? "",
        dieselEntries: linkedDiesel,
      };
    });
  }, [dieselEntries, payments, pumps]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return rows;

    return rows.filter((row) =>
      [row.pumpName, row.ownerName, row.phone, row.address]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [rows, search]);

  const summary = useMemo<PetrolPumpSummary>(() => {
    return filteredRows.reduce(
      (total, row) => ({
        totalPumps: total.totalPumps + 1,
        totalOpeningBalance:
          total.totalOpeningBalance + row.openingBalance,
        totalDiesel: total.totalDiesel + row.totalDiesel,
        totalPaid: total.totalPaid + row.totalPaid,
        totalOutstanding: total.totalOutstanding + row.currentBalance,
      }),
      {
        totalPumps: 0,
        totalOpeningBalance: 0,
        totalDiesel: 0,
        totalPaid: 0,
        totalOutstanding: 0,
      }
    );
  }, [filteredRows]);

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">
          Petrol Pump Management
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Manage petrol pumps, opening balances, diesel totals, actual payments
          and outstanding balances.
        </p>
      </div>

      <PetrolPumpCards summary={summary} />

      <PetrolPumpForm
        pumpName={pumpName}
        setPumpName={setPumpName}
        ownerName={ownerName}
        setOwnerName={setOwnerName}
        phone={phone}
        setPhone={setPhone}
        address={address}
        setAddress={setAddress}
        openingBalance={openingBalance}
        setOpeningBalance={setOpeningBalance}
        onSave={handleSave}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      <PetrolPumpTable
        rows={filteredRows}
        search={search}
        setSearch={setSearch}
        onEdit={handleEdit}
        onDelete={handleDelete}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}
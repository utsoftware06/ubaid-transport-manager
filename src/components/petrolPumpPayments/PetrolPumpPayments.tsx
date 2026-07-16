"use client";

import { useEffect, useMemo, useState } from "react";
import PetrolPumpPaymentForm from "@/components/petrolPumpPayments/PetrolPumpPaymentForm";
import PetrolPumpPaymentTable from "@/components/petrolPumpPayments/PetrolPumpPaymentTable";
import { supabase } from "@/lib/supabase/client";

export type PumpBalanceStatus = "Payable" | "Settled" | "Advance";

export type PetrolPumpPaymentMethod =
  | "Cash"
  | "Bank"
  | "Cheque"
  | "Online Transfer";

export type PetrolPumpOption = {
  id: string;
  pumpName: string;
  ownerName: string;
  openingBalance: number;
  totalDiesel: number;
  dieselPaid: number;
  manualPayments: number;
  currentBalance: number;
  payableAmount: number;
  advanceAmount: number;
  balanceStatus: PumpBalanceStatus;
};

export type PetrolPumpPaymentRow = {
  id: number;
  petrolPumpId: string;
  paymentDate: string;
  pumpName: string;
  ownerName: string;
  amount: number;
  paymentMethod: PetrolPumpPaymentMethod;
  referenceNo: string;
  remarks: string;
  createdAt: string;
};

type PetrolPumpDatabaseRow = {
  id: string;
  pump_name: string | null;
  owner_name: string | null;
  opening_balance: number | string | null;
};

type DieselEntryDatabaseRow = {
  id: number;
  petrol_pump_id: string | null;
  total_amount: number | string | null;
  paid_amount: number | string | null;
  remaining_amount: number | string | null;
  entry_date: string | null;
};

type PetrolPumpPaymentDatabaseRow = {
  id: number;
  petrol_pump_id: string | null;
  payment_date: string | null;
  amount: number | string | null;
  payment_method: string | null;
  reference_no: string | null;
  remarks: string | null;
  created_at: string | null;
};

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function toPaymentMethod(value: string | null): PetrolPumpPaymentMethod {
  if (
    value === "Cash" ||
    value === "Bank" ||
    value === "Cheque" ||
    value === "Online Transfer"
  ) {
    return value;
  }

  return "Cash";
}

function getBalanceStatus(balance: number): PumpBalanceStatus {
  if (balance > 0) return "Payable";
  if (balance < 0) return "Advance";
  return "Settled";
}

export default function PetrolPumpPayments() {
  const [paymentDate, setPaymentDate] = useState("");
  const [petrolPumpId, setPetrolPumpId] = useState("");
  const [amount, setAmount] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<PetrolPumpPaymentMethod>("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");

  const [pumpRows, setPumpRows] = useState<PetrolPumpDatabaseRow[]>([]);
  const [dieselEntries, setDieselEntries] = useState<
    DieselEntryDatabaseRow[]
  >([]);
  const [payments, setPayments] = useState<PetrolPumpPaymentDatabaseRow[]>([]);
  const [search, setSearch] = useState("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingOriginalAmount, setEditingOriginalAmount] = useState(0);
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

    await Promise.all([loadPumps(), loadDieselEntries(), loadPayments()]);

    setIsLoading(false);
  }

  async function loadPumps() {
    const { data, error } = await supabase
      .from("petrol_pumps")
      .select("id, pump_name, owner_name, opening_balance")
      .order("pump_name", { ascending: true });

    if (error) {
      setErrorMessage(error.message);
      setPumpRows([]);
      return;
    }

    setPumpRows((data ?? []) as PetrolPumpDatabaseRow[]);
  }

  async function loadDieselEntries() {
    const { data, error } = await supabase
      .from("diesel_entries")
      .select("id, petrol_pump_id, total_amount, paid_amount, remaining_amount, entry_date");

    if (error) {
      setErrorMessage(error.message);
      setDieselEntries([]);
      return;
    }

    setDieselEntries((data ?? []) as DieselEntryDatabaseRow[]);
  }

  async function loadPayments() {
    const { data, error } = await supabase
      .from("petrol_pump_payments")
      .select(
        "id, petrol_pump_id, payment_date, amount, payment_method, reference_no, remarks, created_at"
      )
      .order("payment_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (error) {
      setErrorMessage(error.message);
      setPayments([]);
      return;
    }

    setPayments((data ?? []) as PetrolPumpPaymentDatabaseRow[]);
  }

  const pumps = useMemo<PetrolPumpOption[]>(() => {
    return pumpRows.map((pump) => {
      const linkedDiesel = dieselEntries.filter(
        (entry) => entry.petrol_pump_id === pump.id
      );
      const linkedPayments = payments.filter(
        (payment) => payment.petrol_pump_id === pump.id
      );

      const openingBalance = toNumber(pump.opening_balance);
      const totalDiesel = linkedDiesel.reduce(
        (total, entry) => total + toNumber(entry.total_amount),
        0
      );
      const dieselPaid = linkedDiesel.reduce(
        (total, entry) => total + toNumber(entry.paid_amount),
        0
      );
      const manualPayments = linkedPayments.reduce(
        (total, payment) => total + toNumber(payment.amount),
        0
      );
      const currentBalance = openingBalance + totalDiesel - manualPayments;

      return {
        id: pump.id,
        pumpName: pump.pump_name ?? "-",
        ownerName: pump.owner_name ?? "-",
        openingBalance,
        totalDiesel,
        dieselPaid,
        manualPayments,
        currentBalance,
        payableAmount: currentBalance > 0 ? currentBalance : 0,
        advanceAmount: currentBalance < 0 ? Math.abs(currentBalance) : 0,
        balanceStatus: getBalanceStatus(currentBalance),
      };
    });
  }, [dieselEntries, payments, pumpRows]);

  const paymentRows = useMemo<PetrolPumpPaymentRow[]>(() => {
    return payments.map((payment) => {
      const pump = pumps.find((item) => item.id === payment.petrol_pump_id);

      return {
        id: payment.id,
        petrolPumpId: payment.petrol_pump_id ?? "",
        paymentDate: payment.payment_date ?? "",
        pumpName: pump?.pumpName ?? "-",
        ownerName: pump?.ownerName ?? "-",
        amount: toNumber(payment.amount),
        paymentMethod: toPaymentMethod(payment.payment_method),
        referenceNo: payment.reference_no ?? "-",
        remarks: payment.remarks ?? "-",
        createdAt: payment.created_at ?? "",
      };
    });
  }, [payments, pumps]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return paymentRows;

    return paymentRows.filter((row) =>
      [
        row.pumpName,
        row.ownerName,
        row.paymentMethod,
        row.referenceNo,
        row.remarks,
        String(row.amount),
        row.paymentDate,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [paymentRows, search]);

  const selectedPump = useMemo(() => {
    return pumps.find((pump) => pump.id === petrolPumpId) ?? null;
  }, [petrolPumpId, pumps]);

  function resetForm() {
    setPaymentDate("");
    setPetrolPumpId("");
    setAmount("");
    setPaymentMethod("Cash");
    setReferenceNo("");
    setRemarks("");
    setEditingId(null);
    setEditingOriginalAmount(0);
  }

  function validateForm() {
    if (!paymentDate) {
      alert("Payment date is required.");
      return false;
    }

    if (!petrolPumpId) {
      alert("Please select a petrol pump.");
      return false;
    }

    if (!amount || Number(amount) <= 0) {
      alert("Amount must be greater than 0.");
      return false;
    }

    if (!paymentMethod) {
      alert("Payment method is required.");
      return false;
    }

    return true;
  }

  async function syncCashbookEntry(paymentId: number) {
    const selected = pumps.find((pump) => pump.id === petrolPumpId);

    if (!selected) {
      throw new Error("Selected petrol pump was not found for Cashbook sync.");
    }

    const payload = {
      entry_date: paymentDate,
      entry_type: "Cash Out",
      person_type: "Petrol Pump",
      person_name: selected.pumpName,
      vehicle_id: null,
      driver_id: null,
      loading_id: null,
      payment_method: paymentMethod,
      amount: Number(amount),
      description: `Payment to petrol pump ${selected.pumpName}`,
      reference_type: "petrol_pump_payment",
      reference_id: String(paymentId),
    };

    const { data: existingEntry, error: checkError } = await supabase
      .from("cashbook_entries")
      .select("id")
      .eq("reference_type", "petrol_pump_payment")
      .eq("reference_id", String(paymentId))
      .maybeSingle();

    if (checkError) {
      throw new Error(checkError.message);
    }

    if (existingEntry) {
      const { error } = await supabase
        .from("cashbook_entries")
        .update(payload)
        .eq("id", existingEntry.id);

      if (error) throw new Error(error.message);
      return;
    }

    const { error } = await supabase.from("cashbook_entries").insert(payload);

    if (error) throw new Error(error.message);
  }

  async function deleteLinkedCashbookEntry(paymentId: number) {
    const { error } = await supabase
      .from("cashbook_entries")
      .delete()
      .eq("reference_type", "petrol_pump_payment")
      .eq("reference_id", String(paymentId));

    if (error) throw new Error(error.message);
  }

  async function handleSave() {
    if (!validateForm()) return;

    setIsSaving(true);

    try {
      if (editingId) {
        const { error } = await supabase
          .from("petrol_pump_payments")
          .update({
            petrol_pump_id: petrolPumpId,
            payment_date: paymentDate,
            amount: Number(amount),
            payment_method: paymentMethod,
            reference_no: referenceNo.trim(),
            remarks: remarks.trim(),
          })
          .eq("id", editingId);

        if (error) throw new Error(error.message);

        await syncCashbookEntry(editingId);

        alert("Petrol pump payment updated successfully!");
        resetForm();
        await Promise.all([loadPayments(), loadDieselEntries()]);
        return;
      }

      const { data, error } = await supabase
        .from("petrol_pump_payments")
        .insert({
          petrol_pump_id: petrolPumpId,
          payment_date: paymentDate,
          amount: Number(amount),
          payment_method: paymentMethod,
          reference_no: referenceNo.trim(),
          remarks: remarks.trim(),
        })
        .select("id")
        .single();

      if (error) throw new Error(error.message);

      await syncCashbookEntry(Number(data.id));

      alert("Petrol pump payment saved successfully!");
      resetForm();
      await Promise.all([loadPayments(), loadDieselEntries()]);
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to save payment.";
      alert(message);
    } finally {
      setIsSaving(false);
    }
  }

  function handleEdit(row: PetrolPumpPaymentRow) {
    setEditingId(row.id);
    setEditingOriginalAmount(row.amount);
    setPaymentDate(row.paymentDate);
    setPetrolPumpId(row.petrolPumpId);
    setAmount(String(row.amount));
    setPaymentMethod(row.paymentMethod);
    setReferenceNo(row.referenceNo === "-" ? "" : row.referenceNo);
    setRemarks(row.remarks === "-" ? "" : row.remarks);
  }

  async function handleDelete(row: PetrolPumpPaymentRow) {
    const confirmed = window.confirm(
      `Delete payment for ${row.pumpName} (${formatAmount(row.amount)})?`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    try {
      await deleteLinkedCashbookEntry(row.id);

      const { error } = await supabase
        .from("petrol_pump_payments")
        .delete()
        .eq("id", row.id);

      if (error) throw new Error(error.message);

      if (editingId === row.id) resetForm();

      alert("Petrol pump payment deleted successfully!");
      await Promise.all([loadPayments(), loadDieselEntries()]);
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unable to delete payment.";
      alert(message);
    } finally {
      setIsDeleting(false);
    }
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">
          Petrol Pump Payments
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Record petrol pump payments, allow advance payments and sync paid
          amounts with Cashbook.
        </p>
      </div>

      <PetrolPumpPaymentForm
        paymentDate={paymentDate}
        setPaymentDate={setPaymentDate}
        petrolPumpId={petrolPumpId}
        setPetrolPumpId={setPetrolPumpId}
        amount={amount}
        setAmount={setAmount}
        paymentMethod={paymentMethod}
        setPaymentMethod={setPaymentMethod}
        referenceNo={referenceNo}
        setReferenceNo={setReferenceNo}
        remarks={remarks}
        setRemarks={setRemarks}
        pumps={pumps}
        selectedPump={selectedPump}
        editingOriginalAmount={editingOriginalAmount}
        onSave={handleSave}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      <PetrolPumpPaymentTable
        rows={filteredRows}
        search={search}
        setSearch={setSearch}
        onEdit={handleEdit}
        onDelete={handleDelete}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
        pumps={pumps}
      />
    </div>
  );
}
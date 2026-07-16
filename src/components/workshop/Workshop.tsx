"use client";

import { useEffect, useMemo, useState } from "react";
import WorkshopForm from "@/components/workshop/WorkshopForm";
import WorkshopCards from "@/components/workshop/WorkshopCards";
import WorkshopTable from "@/components/workshop/WorkshopTable";
import { supabase } from "@/lib/supabase/client";

export type WorkshopPaymentStatus = "Paid" | "Partial" | "Unpaid";

export type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

export type WorkshopEntryRow = {
  id: number;
  workDate: string;
  vehicleId: string;
  vehicleNo: string;
  ownerName: string;
  workshopName: string;
  mechanicName: string;
  workType: string;
  billNo: string;
  partsCost: number;
  labourCost: number;
  totalCost: number;
  paidAmount: number;
  remainingAmount: number;
  paymentStatus: WorkshopPaymentStatus;
  nextServiceDate: string;
  odometer: number;
  remarks: string;
  createdAt: string;
};

export type WorkshopSummary = {
  totalJobs: number;
  totalCost: number;
  paidAmount: number;
  remainingAmount: number;
};

export type WorkshopFilterValues = {
  fromDate: string;
  toDate: string;
  vehicleId: string;
  paymentStatus: string;
  search: string;
};

type VehicleRelation = {
  vehicle_no: string | null;
  owner_name: string | null;
};

type RelatedRecord<T> = T | T[] | null;

type WorkshopDatabaseRow = {
  id: number;
  work_date: string | null;
  vehicle_id: string | null;
  workshop_name: string | null;
  mechanic_name: string | null;
  work_type: string | null;
  bill_no: string | null;
  parts_cost: number | string | null;
  labour_cost: number | string | null;
  total_cost: number | string | null;
  paid_amount: number | string | null;
  remaining_amount: number | string | null;
  payment_status: string | null;
  next_service_date: string | null;
  odometer: number | string | null;
  remarks: string | null;
  created_at: string | null;
  vehicles: RelatedRecord<VehicleRelation>;
};

type WorkshopInsertResult = {
  id: number;
};

type CashbookEntryRecord = {
  id: string | number;
};

type CashbookSyncPayload = {
  workshopEntryId: number;
  workDate: string;
  vehicleId: string;
  workshopName: string;
  workType: string;
  paidAmount: number;
};

const defaultFilters: WorkshopFilterValues = {
  fromDate: "",
  toDate: "",
  vehicleId: "",
  paymentStatus: "",
  search: "",
};

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function getSingleRelation<T>(relation: RelatedRecord<T>): T | null {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation ?? null;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function getPaymentStatus(
  paidAmount: number,
  totalCost: number
): WorkshopPaymentStatus {
  if (paidAmount <= 0) return "Unpaid";
  if (paidAmount >= totalCost) return "Paid";
  return "Partial";
}

function mapPaymentStatus(value: string | null): WorkshopPaymentStatus {
  if (value === "Paid" || value === "Partial" || value === "Unpaid") {
    return value;
  }

  return "Unpaid";
}

export default function Workshop() {
  const [workDate, setWorkDate] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [workshopName, setWorkshopName] = useState("");
  const [mechanicName, setMechanicName] = useState("");
  const [workType, setWorkType] = useState("");
  const [billNo, setBillNo] = useState("");
  const [partsCost, setPartsCost] = useState("");
  const [labourCost, setLabourCost] = useState("");
  const [paidAmount, setPaidAmount] = useState("");
  const [nextServiceDate, setNextServiceDate] = useState("");
  const [odometer, setOdometer] = useState("");
  const [remarks, setRemarks] = useState("");

  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [entries, setEntries] = useState<WorkshopEntryRow[]>([]);
  const [filters, setFilters] =
    useState<WorkshopFilterValues>(defaultFilters);
  const [editingId, setEditingId] = useState<number | null>(null);
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

    await Promise.all([loadVehicles(), loadEntries()]);

    setIsLoading(false);
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

    setVehicles(
      (data ?? []).map((vehicle) => ({
        id: String(vehicle.id),
        vehicleNo: vehicle.vehicle_no ?? "-",
        ownerName: vehicle.owner_name ?? "-",
      }))
    );
  }

  async function loadEntries() {
    const { data, error } = await supabase
      .from("workshop_entries")
      .select(
        `
        id,
        work_date,
        vehicle_id,
        workshop_name,
        mechanic_name,
        work_type,
        bill_no,
        parts_cost,
        labour_cost,
        total_cost,
        paid_amount,
        remaining_amount,
        payment_status,
        next_service_date,
        odometer,
        remarks,
        created_at,
        vehicles(vehicle_no, owner_name)
      `
      )
      .order("work_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (error) {
      setErrorMessage(error.message);
      setEntries([]);
      return;
    }

    setEntries(
      ((data ?? []) as WorkshopDatabaseRow[]).map((entry) => {
        const vehicle = getSingleRelation(entry.vehicles);
        const totalCost =
          toNumber(entry.total_cost) ||
          toNumber(entry.parts_cost) + toNumber(entry.labour_cost);
        const paid = toNumber(entry.paid_amount);
        const remaining = Math.max(totalCost - paid, 0);

        return {
          id: entry.id,
          workDate: entry.work_date ?? "",
          vehicleId: entry.vehicle_id ?? "",
          vehicleNo: vehicle?.vehicle_no ?? "-",
          ownerName: vehicle?.owner_name ?? "-",
          workshopName: entry.workshop_name ?? "",
          mechanicName: entry.mechanic_name ?? "",
          workType: entry.work_type ?? "",
          billNo: entry.bill_no ?? "",
          partsCost: toNumber(entry.parts_cost),
          labourCost: toNumber(entry.labour_cost),
          totalCost,
          paidAmount: paid,
          remainingAmount: remaining,
          paymentStatus: mapPaymentStatus(entry.payment_status),
          nextServiceDate: entry.next_service_date ?? "",
          odometer: toNumber(entry.odometer),
          remarks: entry.remarks ?? "",
          createdAt: entry.created_at ?? "",
        };
      })
    );
  }

  function getVehicleNumber(currentVehicleId: string) {
    return (
      vehicles.find((vehicle) => vehicle.id === currentVehicleId)?.vehicleNo ??
      "-"
    );
  }

  async function findLinkedCashbookEntry(workshopEntryId: number) {
    const { data, error } = await supabase
      .from("cashbook_entries")
      .select("id")
      .eq("reference_type", "workshop")
      .eq("reference_id", String(workshopEntryId))
      .maybeSingle();

    if (error) {
      throw new Error(error.message);
    }

    return data as CashbookEntryRecord | null;
  }

  async function deleteLinkedCashbookEntry(workshopEntryId: number) {
    const { error } = await supabase
      .from("cashbook_entries")
      .delete()
      .eq("reference_type", "workshop")
      .eq("reference_id", String(workshopEntryId));

    if (error) {
      throw new Error(error.message);
    }
  }

  async function syncWorkshopCashbookEntry(payload: CashbookSyncPayload) {
    const linkedCashbookEntry = await findLinkedCashbookEntry(
      payload.workshopEntryId
    );

    if (payload.paidAmount <= 0) {
      if (linkedCashbookEntry) {
        await deleteLinkedCashbookEntry(payload.workshopEntryId);
      }

      return;
    }

    const vehicleNo = getVehicleNumber(payload.vehicleId);
    const cashbookPayload = {
      entry_date: payload.workDate,
      entry_type: "Cash Out",
      person_type: "Workshop",
      person_name: payload.workshopName,
      vehicle_id: payload.vehicleId,
      driver_id: null,
      loading_id: null,
      payment_method: "Cash",
      amount: payload.paidAmount,
      description: `Workshop payment for ${vehicleNo} - ${payload.workType}`,
      reference_type: "workshop",
      reference_id: String(payload.workshopEntryId),
    };

    if (linkedCashbookEntry) {
      const { error } = await supabase
        .from("cashbook_entries")
        .update(cashbookPayload)
        .eq("id", linkedCashbookEntry.id);

      if (error) {
        throw new Error(error.message);
      }

      return;
    }

    const { error } = await supabase
      .from("cashbook_entries")
      .insert(cashbookPayload);

    if (error) {
      throw new Error(error.message);
    }
  }

  function resetForm() {
    setWorkDate("");
    setVehicleId("");
    setWorkshopName("");
    setMechanicName("");
    setWorkType("");
    setBillNo("");
    setPartsCost("");
    setLabourCost("");
    setPaidAmount("");
    setNextServiceDate("");
    setOdometer("");
    setRemarks("");
    setEditingId(null);
  }

  function validateForm() {
    const parts = Number(partsCost || 0);
    const labour = Number(labourCost || 0);
    const paid = Number(paidAmount || 0);
    const meter = Number(odometer || 0);
    const total = parts + labour;

    if (!workDate) {
      alert("Work date is required.");
      return false;
    }

    if (!vehicleId) {
      alert("Vehicle is required.");
      return false;
    }

    if (!workshopName.trim()) {
      alert("Workshop name is required.");
      return false;
    }

    if (!workType.trim()) {
      alert("Work type is required.");
      return false;
    }

    if (parts < 0) {
      alert("Parts cost cannot be negative.");
      return false;
    }

    if (labour < 0) {
      alert("Labour cost cannot be negative.");
      return false;
    }

    if (paid < 0) {
      alert("Paid amount cannot be negative.");
      return false;
    }

    if (paid > total) {
      alert("Paid amount cannot be greater than total cost.");
      return false;
    }

    if (meter < 0) {
      alert("Odometer cannot be negative.");
      return false;
    }

    return true;
  }

  async function handleSave() {
    if (!validateForm()) return;

    const parts = Number(partsCost || 0);
    const labour = Number(labourCost || 0);
    const paid = Number(paidAmount || 0);
    const total = parts + labour;
    const remaining = Math.max(total - paid, 0);
    const paymentStatus = getPaymentStatus(paid, total);

    setIsSaving(true);

    const payload = {
      work_date: workDate,
      vehicle_id: vehicleId,
      workshop_name: workshopName.trim(),
      mechanic_name: mechanicName.trim(),
      work_type: workType.trim(),
      bill_no: billNo.trim(),
      parts_cost: parts,
      labour_cost: labour,
      total_cost: total,
      paid_amount: paid,
      remaining_amount: remaining,
      payment_status: paymentStatus,
      next_service_date: nextServiceDate || null,
      odometer: odometer ? Number(odometer) : null,
      remarks: remarks.trim(),
    };

    if (editingId) {
      const { error } = await supabase
        .from("workshop_entries")
        .update(payload)
        .eq("id", editingId);

      setIsSaving(false);

      if (error) {
        alert(error.message);
        return;
      }

      try {
        await syncWorkshopCashbookEntry({
          workshopEntryId: editingId,
          workDate,
          vehicleId,
          workshopName: workshopName.trim(),
          workType: workType.trim(),
          paidAmount: paid,
        });

        alert("Workshop entry updated successfully!");
      } catch (cashbookError) {
        const message =
          cashbookError instanceof Error
            ? cashbookError.message
            : "Cashbook sync failed after workshop update.";
        alert(`Workshop entry updated, but Cashbook sync failed: ${message}`);
      }

      resetForm();
      await loadEntries();
      return;
    }

    const { data, error } = await supabase
      .from("workshop_entries")
      .insert(payload)
      .select("id")
      .single();

    setIsSaving(false);

    if (error) {
      alert(error.message);
      return;
    }

    const insertedEntry = data as WorkshopInsertResult | null;

    if (!insertedEntry) {
      alert("Workshop entry saved, but returned ID was not found.");
      await loadEntries();
      return;
    }

    try {
      await syncWorkshopCashbookEntry({
        workshopEntryId: insertedEntry.id,
        workDate,
        vehicleId,
        workshopName: workshopName.trim(),
        workType: workType.trim(),
        paidAmount: paid,
      });

      alert("Workshop entry saved successfully!");
    } catch (cashbookError) {
      const message =
        cashbookError instanceof Error
          ? cashbookError.message
          : "Cashbook sync failed after workshop save.";
      alert(`Workshop entry saved, but Cashbook sync failed: ${message}`);
    }

    resetForm();
    await loadEntries();
  }

  function handleEdit(row: WorkshopEntryRow) {
    setEditingId(row.id);
    setWorkDate(row.workDate);
    setVehicleId(row.vehicleId);
    setWorkshopName(row.workshopName);
    setMechanicName(row.mechanicName);
    setWorkType(row.workType);
    setBillNo(row.billNo);
    setPartsCost(String(row.partsCost));
    setLabourCost(String(row.labourCost));
    setPaidAmount(String(row.paidAmount));
    setNextServiceDate(row.nextServiceDate);
    setOdometer(row.odometer ? String(row.odometer) : "");
    setRemarks(row.remarks);
  }

  async function handleDelete(row: WorkshopEntryRow) {
    const confirmed = window.confirm(
      `Delete workshop entry for ${row.vehicleNo}?`
    );

    if (!confirmed) return;

    setIsDeleting(true);

    try {
      await deleteLinkedCashbookEntry(row.id);
    } catch (cashbookError) {
      setIsDeleting(false);
      const message =
        cashbookError instanceof Error
          ? cashbookError.message
          : "Unable to delete linked Cashbook entry.";
      alert(`Cashbook delete failed: ${message}`);
      return;
    }

    const { error } = await supabase
      .from("workshop_entries")
      .delete()
      .eq("id", row.id);

    setIsDeleting(false);

    if (error) {
      alert(error.message);
      return;
    }

    if (editingId === row.id) resetForm();

    alert("Workshop entry deleted successfully!");
    await loadEntries();
  }

  const filteredRows = useMemo(() => {
    const keyword = filters.search.trim().toLowerCase();

    return entries.filter((row) => {
      if (filters.fromDate && row.workDate < filters.fromDate) return false;
      if (filters.toDate && row.workDate > filters.toDate) return false;
      if (filters.vehicleId && row.vehicleId !== filters.vehicleId) {
        return false;
      }
      if (
        filters.paymentStatus &&
        row.paymentStatus !== filters.paymentStatus
      ) {
        return false;
      }

      if (!keyword) return true;

      return [
        row.vehicleNo,
        row.ownerName,
        row.workshopName,
        row.mechanicName,
        row.workType,
        row.billNo,
        row.remarks,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword);
    });
  }, [entries, filters]);

  const summary = useMemo<WorkshopSummary>(() => {
    return filteredRows.reduce(
      (total, row) => ({
        totalJobs: total.totalJobs + 1,
        totalCost: total.totalCost + row.totalCost,
        paidAmount: total.paidAmount + row.paidAmount,
        remainingAmount: total.remainingAmount + row.remainingAmount,
      }),
      {
        totalJobs: 0,
        totalCost: 0,
        paidAmount: 0,
        remainingAmount: 0,
      }
    );
  }, [filteredRows]);

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">
              Workshop Management
            </h1>
            <p className="mt-2 text-base font-medium text-gray-900">
              Track vehicle repair work, parts cost, labour cost, payments and
              upcoming service dates.
            </p>
          </div>

          {editingId && (
            <button
              type="button"
              onClick={resetForm}
              className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
            >
              Cancel Edit
            </button>
          )}
        </div>
      </div>

      <WorkshopCards summary={summary} />

      <WorkshopForm
        workDate={workDate}
        setWorkDate={setWorkDate}
        vehicleId={vehicleId}
        setVehicleId={setVehicleId}
        workshopName={workshopName}
        setWorkshopName={setWorkshopName}
        mechanicName={mechanicName}
        setMechanicName={setMechanicName}
        workType={workType}
        setWorkType={setWorkType}
        billNo={billNo}
        setBillNo={setBillNo}
        partsCost={partsCost}
        setPartsCost={setPartsCost}
        labourCost={labourCost}
        setLabourCost={setLabourCost}
        paidAmount={paidAmount}
        setPaidAmount={setPaidAmount}
        nextServiceDate={nextServiceDate}
        setNextServiceDate={setNextServiceDate}
        odometer={odometer}
        setOdometer={setOdometer}
        remarks={remarks}
        setRemarks={setRemarks}
        vehicles={vehicles}
        onSave={handleSave}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      <WorkshopTable
        rows={filteredRows}
        filters={filters}
        setFilters={setFilters}
        vehicles={vehicles}
        onReset={() => setFilters(defaultFilters)}
        onEdit={handleEdit}
        onDelete={handleDelete}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}
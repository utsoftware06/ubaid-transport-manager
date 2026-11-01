"use client";

import { useCallback, useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import WorkshopForm from "@/components/workshop/WorkshopForm";
import WorkshopCards from "@/components/workshop/WorkshopCards";
import WorkshopTable from "@/components/workshop/WorkshopTable";
import WorkshopMaster from "@/components/workshop/WorkshopMaster";
import WorkshopAccount from "@/components/workshop/WorkshopAccount";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { WORKSHOP_WORK_TYPE_GROUPS, createWorkshopWorkItem, getWorkTypeLabel, type WorkshopWorkItem } from "./workshopWorkTypes";
import {
  readManualVoucherSourceEditContext,
  returnToManualVoucherAfterSourceEdit,
  type ManualVoucherSourceEditContext,
} from "@/lib/manualVoucherSourceEdit";

export type WorkshopPaymentStatus = "Paid" | "Partial" | "Unpaid";

export type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

export type WorkshopEntryRow = {
  id: number;
  addaId: string | null;
  workDate: string;
  vehicleId: string;
  vehicleNo: string;
  ownerName: string;
  workshopName: string;
  workshopId: string;
  mechanicName: string;
  workType: string;
  workItems: WorkshopWorkItem[];
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
  voucherId: number | null;
  voucherNo: string;
  voucherDate: string;
};

export type WorkshopOption = {
  id: string;
  addaId: string;
  workshopName: string;
  ownerName: string;
  phone: string;
  address: string;
  openingBalance: number;
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
  adda_id: string | null;
  work_date: string | null;
  vehicle_id: string | null;
  workshop_name: string | null;
  workshop_id: string | null;
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
  workshop_entry_items: Array<{ id: number; line_no: number; work_type: string; category: string | null; quantity: number | string; rate: number | string; amount: number | string; remarks: string | null }> | null;
};

type WorkshopVoucherLinkRow = {
  workshop_entry_id: number;
  voucher_id: number;
};

type WorkshopVoucherRecord = {
  id: number;
  expense_no: string | null;
  expense_date: string | null;
};

type WorkshopDatabaseMasterRow = {
  id: string;
  adda_id: string;
  workshop_name: string | null;
  owner_name: string | null;
  phone: string | null;
  address: string | null;
  opening_balance: number | string | null;
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

function mapPaymentStatus(value: string | null): WorkshopPaymentStatus {
  if (value === "Paid" || value === "Partial" || value === "Unpaid") {
    return value;
  }

  return "Unpaid";
}

export default function Workshop() {
  const { t, dir } = useLanguage();
  const [workDate, setWorkDate] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [workshopName, setWorkshopName] = useState("");
  const [workshopId, setWorkshopId] = useState("");
  const [mechanicName, setMechanicName] = useState("");
  const [workItems, setWorkItems] = useState<WorkshopWorkItem[]>([createWorkshopWorkItem()]);
  const [billNo, setBillNo] = useState("");
  const [partsCost, setPartsCost] = useState("");
  const [labourCost, setLabourCost] = useState("");
  const [paidAmount, setPaidAmount] = useState("");
  const [nextServiceDate, setNextServiceDate] = useState("");
  const [odometer, setOdometer] = useState("");
  const [remarks, setRemarks] = useState("");

  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [workshops, setWorkshops] = useState<WorkshopOption[]>([]);
  const [profileAddaId, setProfileAddaId] = useState("");
  const [activeSection, setActiveSection] = useState<"entries" | "master" | "account">("entries");
  const [entries, setEntries] = useState<WorkshopEntryRow[]>([]);
  const [filters, setFilters] =
    useState<WorkshopFilterValues>(defaultFilters);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [manualSourceEditContext, setManualSourceEditContext] = useState<ManualVoucherSourceEditContext | null>(null);
  const manualSourceEditAppliedRef = useRef(false);
  const saveLockRef = useRef(false);
  const deleteLockRef = useRef(false);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setManualSourceEditContext(readManualVoucherSourceEditContext("workshop"));
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  const loadVehicles = useCallback(async () => {
    const { data, error } = await supabase
      .from("vehicles")
      .select("id, vehicle_no, owner_name")
      .order("vehicle_no", { ascending: true });

    if (error) {
      console.error("Failed to load workshop vehicles:", error);
      setErrorMessage(t("workshop.messages.loadFailed"));
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
  }, [t]);

  const loadWorkshops = useCallback(async () => {
    const { data, error } = await supabase
      .from("workshops")
      .select("id, adda_id, workshop_name, owner_name, phone, address, opening_balance")
      .order("workshop_name", { ascending: true });

    if (error) {
      console.error("Failed to load Workshop Master:", error);
      setErrorMessage(t("workshop.messages.loadFailed"));
      setWorkshops([]);
      return;
    }

    setWorkshops(
      ((data ?? []) as WorkshopDatabaseMasterRow[]).map((workshop) => ({
        id: workshop.id,
        addaId: workshop.adda_id,
        workshopName: workshop.workshop_name ?? "-",
        ownerName: workshop.owner_name ?? "",
        phone: workshop.phone ?? "",
        address: workshop.address ?? "",
        openingBalance: toNumber(workshop.opening_balance),
      }))
    );
  }, [t]);

  const loadProfileAdda = useCallback(async () => {
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) return;
    const { data, error } = await supabase
      .from("profiles")
      .select("adda_id, is_active")
      .eq("id", authData.user.id)
      .maybeSingle();

    if (error || data?.is_active !== true) {
      if (error) console.error("Failed to resolve Workshop Adda:", error);
      setProfileAddaId("");
      return;
    }
    setProfileAddaId(data.adda_id ?? "");
  }, []);

  const loadEntries = useCallback(async () => {
    const { data, error } = await supabase
      .from("workshop_entries")
      .select(
        `
        id,
        adda_id,
        work_date,
        vehicle_id,
        workshop_id,
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
        vehicles(vehicle_no, owner_name),
        workshop_entry_items(id, line_no, work_type, category, quantity, rate, amount, remarks)
      `
      )
      .order("work_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Failed to load workshop entries:", error);
      setErrorMessage(t("workshop.messages.loadFailed"));
      setEntries([]);
      return;
    }

    const workshopRows = (data ?? []) as WorkshopDatabaseRow[];
    const workshopEntryIds = workshopRows.map((entry) => entry.id);
    const { data: linkData, error: linkError } = workshopEntryIds.length === 0
      ? { data: [] as WorkshopVoucherLinkRow[], error: null }
      : await supabase
          .from("voucher_workshop_entries")
          .select("workshop_entry_id, voucher_id")
          .in("workshop_entry_id", workshopEntryIds);
    if (linkError) {
      console.error("Failed to resolve Workshop Voucher attachments:", linkError);
      setErrorMessage(t("workshop.messages.loadFailed"));
      setEntries([]);
      return;
    }

    const links = (linkData ?? []) as WorkshopVoucherLinkRow[];
    const voucherIds = Array.from(new Set(links.map((link) => link.voucher_id)));
    const { data: voucherData, error: voucherError } = voucherIds.length === 0
      ? { data: [] as WorkshopVoucherRecord[], error: null }
      : await supabase
          .from("expenses")
          .select("id, expense_no, expense_date")
          .in("id", voucherIds);
    if (voucherError) {
      console.error("Failed to resolve attached Voucher metadata:", voucherError);
      setErrorMessage(t("workshop.messages.loadFailed"));
      setEntries([]);
      return;
    }

    const linksByWorkshopEntry = new Map(links.map((link) => [link.workshop_entry_id, link]));
    const vouchersById = new Map(
      ((voucherData ?? []) as WorkshopVoucherRecord[]).map((voucher) => [voucher.id, voucher])
    );

    if (process.env.NODE_ENV === "development") {
      console.debug("Resolved Workshop Voucher attachments", links.map((link) => {
        const voucher = vouchersById.get(link.voucher_id);
        return {
          workshopEntryId: link.workshop_entry_id,
          linkRow: link,
          voucherId: link.voucher_id,
          voucherNo: voucher?.expense_no ?? null,
          voucherDate: voucher?.expense_date ?? null,
          resolvedStatus: "attached",
        };
      }));
    }

    setEntries(
      workshopRows.map((entry) => {
        const vehicle = getSingleRelation(entry.vehicles);
        const totalCost =
          toNumber(entry.total_cost) ||
          toNumber(entry.parts_cost) + toNumber(entry.labour_cost);
        const paid = toNumber(entry.paid_amount);
        const remaining = Math.max(totalCost - paid, 0);
        const voucherLink = linksByWorkshopEntry.get(entry.id);
        const voucher = voucherLink ? vouchersById.get(voucherLink.voucher_id) : undefined;

        return {
          id: entry.id,
          addaId: entry.adda_id ?? null,
          workDate: entry.work_date ?? "",
          vehicleId: entry.vehicle_id ?? "",
          vehicleNo: vehicle?.vehicle_no ?? "-",
          ownerName: vehicle?.owner_name ?? "-",
          workshopName: entry.workshop_name ?? "",
          workshopId: entry.workshop_id ?? "",
          mechanicName: entry.mechanic_name ?? "",
          workType: entry.work_type ?? "",
          workItems: (entry.workshop_entry_items ?? []).sort((a,b)=>a.line_no-b.line_no).map((item) => ({ id:item.id, clientId:String(item.id), workType:item.work_type, category:item.category ?? "", quantity:String(item.quantity), rate:String(item.rate), amount:toNumber(item.amount), remarks:item.remarks ?? "" })),
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
          voucherId: voucherLink?.voucher_id ?? null,
          voucherNo: voucher?.expense_no ?? "",
          voucherDate: voucher?.expense_date ?? "",
        };
      })
    );
  }, [t]);

  const loadInitialData = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage("");
    await Promise.all([loadVehicles(), loadWorkshops(), loadProfileAdda(), loadEntries()]);
    setIsLoading(false);
  }, [loadEntries, loadProfileAdda, loadVehicles, loadWorkshops]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadInitialData(), 0);
    return () => window.clearTimeout(timer);
  }, [loadInitialData]);

  const applyManualSourceEditContext = useEffectEvent(() => {
    if (isLoading || !manualSourceEditContext || manualSourceEditAppliedRef.current) return;
    manualSourceEditAppliedRef.current = true;
    const timer = window.setTimeout(() => {
      const sourceEntryId = Number(manualSourceEditContext.sourceEntryId);
      const sourceEntry = entries.find((entry) => entry.id === sourceEntryId);
      if (!sourceEntry || sourceEntry.voucherId !== manualSourceEditContext.voucherId) {
        setErrorMessage(t("workshop.messages.manualSourceUnavailable"));
        return;
      }
      setActiveSection("entries");
      handleEdit(sourceEntry);
    }, 0);
    return () => window.clearTimeout(timer);
  });

  useEffect(() => {
    applyManualSourceEditContext();
  }, [entries, isLoading, manualSourceEditContext]);

  function resetForm() {
    setWorkDate("");
    setVehicleId("");
    setWorkshopId("");
    setWorkshopName("");
    setMechanicName("");
    setWorkItems([createWorkshopWorkItem()]);
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
    const paid = Number(paidAmount || 0);
    const meter = Number(odometer || 0);
    const total = workItems.reduce((sum, item) => sum + item.amount, 0);

    if (!workDate) {
      alert(t("workshop.validation.dateRequired"));
      return false;
    }

    if (!vehicleId) {
      alert(t("workshop.validation.vehicleRequired"));
      return false;
    }

    if (!workshopId || !workshopName.trim()) {
      alert(t("workshop.validation.workshopRequired"));
      return false;
    }

    if (workItems.length === 0) {
      alert(t("workshop.workItems.validation.atLeastOne"));
      return false;
    }
    const supportedTypes = new Set(WORKSHOP_WORK_TYPE_GROUPS.flatMap(([, types]) => [...types]));
    for (const item of workItems) {
      const quantity=Number(item.quantity); const rate=Number(item.rate); const amount=quantity*rate;
      if (!supportedTypes.has(item.workType as never)) { alert(t("workshop.workItems.validation.workType")); return false; }
      if (!Number.isFinite(quantity) || quantity<=0) { alert(t("workshop.workItems.validation.quantity")); return false; }
      if (!Number.isFinite(rate) || rate<0 || !Number.isFinite(amount)) { alert(t("workshop.workItems.validation.rate")); return false; }
    }
    if (!Number.isFinite(total) || total<=0) { alert(t("workshop.workItems.validation.total")); return false; }

    if (!Number.isFinite(paid) || paid < 0) {
      alert(t("workshop.validation.paidNonNegative"));
      return false;
    }

    if (paid > total) {
      alert(t("workshop.validation.paidExceedsTotal"));
      return false;
    }

    if (!Number.isFinite(meter) || meter < 0) {
      alert(t("workshop.validation.odometerNonNegative"));
      return false;
    }

    return true;
  }

  async function handleSave() {
    if (saveLockRef.current) return;
    if (!validateForm()) return;

    const paid = Number(paidAmount || 0);
    saveLockRef.current = true;
    setIsSaving(true);

    try {
      const payload = { p_entry_id:editingId, p_work_date:workDate, p_vehicle_id:vehicleId, p_workshop_id:workshopId, p_mechanic_name:mechanicName.trim()||null, p_bill_no:billNo.trim()||null, p_paid_amount:paid, p_next_service_date:nextServiceDate||null, p_odometer:odometer?Number(odometer):null, p_remarks:remarks.trim()||null, p_parts_cost:editingId?Number(partsCost||0):0, p_labour_cost:editingId?Number(labourCost||0):0, p_items:workItems.map((item)=>({work_type:item.workType,category:item.category,quantity:Number(item.quantity),rate:Number(item.rate),remarks:item.remarks.trim()||null})) };
      const isManualSourceEdit = Boolean(
        manualSourceEditContext && editingId === Number(manualSourceEditContext.sourceEntryId)
      );
      const { data, error } = isManualSourceEdit
        ? await supabase.rpc("save_manual_voucher_workshop_source_entry", {
            p_voucher_id: manualSourceEditContext!.voucherId,
            ...payload,
          })
        : await supabase.rpc("save_workshop_entry_with_items", payload);
      if (error) {
        console.error("Failed to save Workshop Entry items:",error);
        const message = t(editingId?"workshop.messages.updateFailed":"workshop.messages.saveFailed");
        alert(isManualSourceEdit ? `${message}\n${error.message}` : message);
        return;
      }
      const savedEntryId=Number(data);
      if (!Number.isSafeInteger(savedEntryId)) { alert(t("workshop.messages.idMissing")); return; }
      alert(t(editingId ? "workshop.messages.updated" : "workshop.messages.saved"));

      resetForm();
      if (isManualSourceEdit && manualSourceEditContext) {
        returnToManualVoucherAfterSourceEdit(manualSourceEditContext);
        return;
      }
      await loadEntries();
    } catch (error) {
      console.error("Unexpected error while saving workshop entry:", error);
      alert(t("workshop.messages.saveFailed"));
    } finally {
      saveLockRef.current = false;
      setIsSaving(false);
    }
  }

  function handleEdit(row: WorkshopEntryRow) {
    setEditingId(row.id);
    setWorkDate(row.workDate);
    setVehicleId(row.vehicleId);
    setWorkshopId(row.workshopId);
    setWorkshopName(row.workshopName);
    setMechanicName(row.mechanicName);
    setWorkItems(row.workItems.length ? row.workItems : [{ ...createWorkshopWorkItem(), workType:"other_work", category:"other", quantity:"1", rate:String(row.totalCost), amount:row.totalCost, remarks:row.workType }]);
    setBillNo(row.billNo);
    setPartsCost(String(row.partsCost));
    setLabourCost(String(row.labourCost));
    setPaidAmount(String(row.paidAmount));
    setNextServiceDate(row.nextServiceDate);
    setOdometer(row.odometer ? String(row.odometer) : "");
    setRemarks(row.remarks);
  }

  async function handleDelete(row: WorkshopEntryRow) {
    if (deleteLockRef.current) return;
    const confirmed = window.confirm(
      `${t("workshop.messages.deleteConfirm")} ${row.vehicleNo}?`
    );

    if (!confirmed) return;

    deleteLockRef.current = true;
    setIsDeleting(true);

    try {
      const { error } = await supabase.rpc("delete_workshop_entry_with_cashbook", {
        p_entry_id: row.id,
      });

      if (error) {
        console.error("Failed to delete workshop entry:", error);
        alert(t("workshop.messages.deleteFailed"));
        return;
      }

      if (editingId === row.id) resetForm();

      alert(t("workshop.messages.deleted"));
      await loadEntries();
    } catch (error) {
      console.error("Unexpected error while deleting workshop entry:", error);
      alert(t("workshop.messages.deleteFailed"));
    } finally {
      deleteLockRef.current = false;
      setIsDeleting(false);
    }
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
        row.workItems.map((item) => getWorkTypeLabel(item.workType, t)).join(" "),
        row.billNo,
        row.remarks,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword);
    });
  }, [entries, filters, t]);

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

  function handleWorkshopChange(nextWorkshopId: string) {
    setWorkshopId(nextWorkshopId);
    setWorkshopName(
      workshops.find((workshop) => workshop.id === nextWorkshopId)?.workshopName ?? ""
    );
  }

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <ModulePageHeading icon="workshop" accent="red" title={t("workshop.title")} description={t("workshop.description")} />

          {editingId && (
            <button
              type="button"
              onClick={resetForm}
              className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
            >
              {t("common.cancelEdit")}
            </button>
          )}
        </div>
      </div>

      <nav className="flex flex-wrap gap-2 rounded-xl border border-gray-200 bg-white p-3 shadow-sm" aria-label={t("workshop.sections.navigation")}>
        {(["entries", "master", "account"] as const).map((section) => (
          <button
            key={section}
            type="button"
            onClick={() => setActiveSection(section)}
            aria-current={activeSection === section ? "page" : undefined}
            className={`rounded-lg px-5 py-3 text-sm font-bold transition ${activeSection === section ? "bg-blue-600 text-white" : "border border-gray-300 bg-white text-gray-900 hover:bg-blue-50"}`}
          >
            {t(`workshop.sections.${section}`)}
          </button>
        ))}
      </nav>

      {activeSection === "master" && (
        <WorkshopMaster
          workshops={workshops}
          profileAddaId={profileAddaId}
          onChanged={loadWorkshops}
        />
      )}

      {activeSection === "account" && (
        <WorkshopAccount
          workshops={workshops}
          entries={entries}
          onAccountingChanged={async () => {
            await Promise.all([loadEntries(), loadWorkshops()]);
          }}
        />
      )}

      {activeSection === "entries" && (
        <>

      <WorkshopCards summary={summary} />

      <WorkshopForm
        workDate={workDate}
        setWorkDate={setWorkDate}
        vehicleId={vehicleId}
        setVehicleId={setVehicleId}
        workshopName={workshopName}
        workshopId={workshopId}
        onWorkshopChange={handleWorkshopChange}
        workshops={workshops}
        mechanicName={mechanicName}
        setMechanicName={setMechanicName}
        workItems={workItems}
        setWorkItems={setWorkItems}
        billNo={billNo}
        setBillNo={setBillNo}
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
        addaId={profileAddaId || null}
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
        </>
      )}
    </div>
  );
}

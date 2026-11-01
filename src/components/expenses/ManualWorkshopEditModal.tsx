"use client";

import { useEffect, useMemo, useState } from "react";
import WorkshopForm from "@/components/workshop/WorkshopForm";
import type { VehicleOption, WorkshopOption } from "@/components/workshop/Workshop";
import { WORKSHOP_WORK_TYPE_GROUPS, createWorkshopWorkItem, getWorkCategory, type WorkshopWorkItem } from "@/components/workshop/workshopWorkTypes";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";

type Props = {
  voucherId: number;
  sourceEntryId: number;
  addaId: string;
  vehicleId: string;
  vehicleNo: string;
  onClose: () => void;
  onSaved: () => Promise<void>;
};

type WorkshopSourceRow = {
  id: number;
  adda_id: string;
  work_date: string | null;
  vehicle_id: string | null;
  workshop_id: string | null;
  workshop_name: string | null;
  mechanic_name: string | null;
  bill_no: string | null;
  parts_cost: number | string | null;
  labour_cost: number | string | null;
  total_cost: number | string | null;
  paid_amount: number | string | null;
  work_type: string | null;
  next_service_date: string | null;
  odometer: number | string | null;
  remarks: string | null;
  workshop_entry_items: Array<{
    id: number;
    line_no: number;
    work_type: string;
    category: string | null;
    quantity: number | string;
    rate: number | string;
    amount: number | string;
    remarks: string | null;
  }> | null;
};

type WorkshopMasterRow = {
  id: string;
  adda_id: string;
  workshop_name: string | null;
  owner_name: string | null;
  phone: string | null;
  address: string | null;
  opening_balance: number | string | null;
};

type FormState = {
  workDate: string;
  vehicleId: string;
  workshopId: string;
  workshopName: string;
  mechanicName: string;
  workItems: WorkshopWorkItem[];
  billNo: string;
  partsCost: string;
  labourCost: string;
  paidAmount: string;
  nextServiceDate: string;
  odometer: string;
  remarks: string;
};

const numberValue = (value: number | string | null | undefined) => Number(value ?? 0);

export default function ManualWorkshopEditModal({
  voucherId,
  sourceEntryId,
  addaId,
  vehicleId,
  vehicleNo,
  onClose,
  onSaved,
}: Props) {
  const { t, dir } = useLanguage();
  const [form, setForm] = useState<FormState | null>(null);
  const [workshops, setWorkshops] = useState<WorkshopOption[]>([]);
  const [sourceVehicle, setSourceVehicle] = useState<VehicleOption | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let active = true;
    const load = async () => {
      setLoading(true);
      setErrorMessage("");
      const [sourceResult, mastersResult, vehicleResult] = await Promise.all([
        supabase
          .from("workshop_entries")
          .select("id, adda_id, work_date, vehicle_id, workshop_id, workshop_name, mechanic_name, bill_no, work_type, parts_cost, labour_cost, total_cost, paid_amount, next_service_date, odometer, remarks, workshop_entry_items(id, line_no, work_type, category, quantity, rate, amount, remarks)")
          .eq("id", sourceEntryId)
          .maybeSingle(),
        supabase
          .from("workshops")
          .select("id, adda_id, workshop_name, owner_name, phone, address, opening_balance")
          .eq("adda_id", addaId)
          .order("workshop_name", { ascending: true }),
        supabase
          .from("vehicles")
          .select("id, adda_id, vehicle_no, owner_name")
          .eq("id", vehicleId)
          .eq("adda_id", addaId)
          .maybeSingle(),
      ]);
      if (!active) return;
      if (sourceResult.error || !sourceResult.data) {
        setErrorMessage(sourceResult.error?.message ?? t("workshop.messages.loadFailed"));
        setLoading(false);
        return;
      }

      const source = sourceResult.data as unknown as WorkshopSourceRow;
      if (source.adda_id !== addaId || source.vehicle_id !== vehicleId) {
        setErrorMessage("The Workshop source no longer matches this Manual Voucher's Adda and vehicle.");
        setLoading(false);
        return;
      }
      if (vehicleResult.error || !vehicleResult.data) {
        setErrorMessage(vehicleResult.error?.message ?? "The Manual Voucher vehicle could not be verified.");
        setLoading(false);
        return;
      }
      setSourceVehicle({
        id: String(vehicleResult.data.id),
        vehicleNo: vehicleResult.data.vehicle_no ?? vehicleNo ?? "-",
        ownerName: vehicleResult.data.owner_name ?? "",
      });

      const masterRows = mastersResult.error
        ? []
        : ((mastersResult.data ?? []) as unknown as WorkshopMasterRow[]);
      const mappedMasters: WorkshopOption[] = masterRows.map((row) => ({
        id: String(row.id),
        addaId: row.adda_id,
        workshopName: row.workshop_name ?? "-",
        ownerName: row.owner_name ?? "",
        phone: row.phone ?? "",
        address: row.address ?? "",
        openingBalance: numberValue(row.opening_balance),
      }));
      if (source.workshop_id && !mappedMasters.some((row) => row.id === source.workshop_id)) {
        mappedMasters.push({
          id: source.workshop_id,
          addaId,
          workshopName: source.workshop_name ?? "-",
          ownerName: "",
          phone: "",
          address: "",
          openingBalance: 0,
        });
      }
      setWorkshops(mappedMasters);

      const savedItems = [...(source.workshop_entry_items ?? [])]
        .sort((left, right) => left.line_no - right.line_no)
        .map((item) => ({
          id: item.id,
          clientId: String(item.id),
          workType: item.work_type,
          category: item.category ?? getWorkCategory(item.work_type),
          quantity: String(item.quantity),
          rate: String(item.rate),
          amount: numberValue(item.amount),
          remarks: item.remarks ?? "",
        }));
      const totalCost = numberValue(source.total_cost) || numberValue(source.parts_cost) + numberValue(source.labour_cost);
      const workItems = savedItems.length > 0
        ? savedItems
        : [{ ...createWorkshopWorkItem(), workType: source.work_type ?? "other_work", category: getWorkCategory(source.work_type ?? "other_work"), rate: String(totalCost), amount: totalCost, remarks: source.work_type ?? "" }];

      setForm({
        workDate: source.work_date ?? "",
        vehicleId: source.vehicle_id ?? "",
        workshopId: source.workshop_id ?? "",
        workshopName: source.workshop_name ?? "",
        mechanicName: source.mechanic_name ?? "",
        workItems,
        billNo: source.bill_no ?? "",
        partsCost: String(numberValue(source.parts_cost)),
        labourCost: String(numberValue(source.labour_cost)),
        paidAmount: String(numberValue(source.paid_amount)),
        nextServiceDate: source.next_service_date ?? "",
        odometer: source.odometer == null ? "" : String(source.odometer),
        remarks: source.remarks ?? "",
      });
      setLoading(false);
    };
    void load();
    return () => { active = false; };
  }, [addaId, sourceEntryId, t, vehicleId, vehicleNo]);

  const vehicles = useMemo<VehicleOption[]>(() => sourceVehicle ? [sourceVehicle] : [], [sourceVehicle]);
  const total = form?.workItems.reduce((sum, item) => sum + item.amount, 0) ?? 0;

  function change<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((current) => current ? { ...current, [key]: value } : current);
  }

  async function save() {
    if (!form || saving) return;
    setErrorMessage("");
    if (!form.workDate) {
      setErrorMessage(t("workshop.validation.dateRequired"));
      return;
    }
    if (!form.vehicleId) {
      setErrorMessage(t("workshop.validation.vehicleRequired"));
      return;
    }
    if (form.vehicleId !== vehicleId) {
      setErrorMessage("The linked Workshop vehicle must remain the Manual Voucher vehicle.");
      return;
    }
    if (!form.workshopId || !form.workshopName.trim()) {
      setErrorMessage(t("workshop.validation.workshopRequired"));
      return;
    }
    if (form.workItems.length === 0) {
      setErrorMessage(t("workshop.workItems.validation.atLeastOne"));
      return;
    }
    const supportedTypes = new Set(WORKSHOP_WORK_TYPE_GROUPS.flatMap(([, types]) => [...types]));
    for (const item of form.workItems) {
      const quantity = Number(item.quantity);
      const rate = Number(item.rate);
      if (!supportedTypes.has(item.workType as never)) {
        setErrorMessage(t("workshop.workItems.validation.workType"));
        return;
      }
      if (!Number.isFinite(quantity) || quantity <= 0) {
        setErrorMessage(t("workshop.workItems.validation.quantity"));
        return;
      }
      if (!Number.isFinite(rate) || rate < 0 || !Number.isFinite(quantity * rate)) {
        setErrorMessage(t("workshop.workItems.validation.rate"));
        return;
      }
    }
    if (!Number.isFinite(total) || total <= 0) {
      setErrorMessage(t("workshop.workItems.validation.total"));
      return;
    }
    const paidAmount = Number(form.paidAmount || 0);
    if (!Number.isFinite(paidAmount) || paidAmount < 0) {
      setErrorMessage(t("workshop.validation.paidNonNegative"));
      return;
    }
    if (paidAmount > total) {
      setErrorMessage(t("workshop.validation.paidExceedsTotal"));
      return;
    }
    if (form.odometer && (!Number.isFinite(Number(form.odometer)) || Number(form.odometer) < 0)) {
      setErrorMessage(t("workshop.validation.odometerNonNegative"));
      return;
    }
    setSaving(true);
    let closeAfterSave = false;
    try {
      const { data, error } = await supabase.rpc("save_manual_voucher_workshop_source_entry", {
        p_voucher_id: voucherId,
        p_entry_id: sourceEntryId,
        p_work_date: form.workDate,
        p_vehicle_id: form.vehicleId,
        p_workshop_id: form.workshopId,
        p_mechanic_name: form.mechanicName.trim() || null,
        p_bill_no: form.billNo.trim() || null,
        p_paid_amount: paidAmount,
        p_next_service_date: form.nextServiceDate || null,
        p_odometer: form.odometer ? Number(form.odometer) : null,
        p_remarks: form.remarks.trim() || null,
        p_parts_cost: Number(form.partsCost || 0),
        p_labour_cost: Number(form.labourCost || 0),
        p_items: form.workItems.map((item) => ({
          work_type: item.workType,
          category: item.category,
          quantity: Number(item.quantity),
          rate: Number(item.rate),
          remarks: item.remarks.trim() || null,
        })),
      });
      if (error) throw new Error(error.message);
      if (Number(data) !== sourceEntryId) throw new Error("Workshop edit returned a different source ID.");
      await onSaved();
      closeAfterSave = true;
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : t("workshop.messages.updateFailed"));
    } finally {
      setSaving(false);
    }
    if (closeAfterSave) onClose();
  }

  const vehicleOptions = vehicles;

  return (
    <div className="fixed inset-0 z-[100] flex items-start justify-center overflow-y-auto bg-slate-950/60 p-3 pt-6 sm:p-6" role="presentation">
      <section role="dialog" aria-modal="true" aria-label={t("workshop.actions.edit")} dir={dir} className="w-full max-w-6xl rounded-2xl bg-slate-100 p-3 shadow-2xl sm:p-5">
        <div className="mb-3 flex items-center justify-between gap-3 rounded-xl bg-white px-4 py-3">
          <h2 className="text-lg font-black text-slate-950">{t("workshop.actions.edit")}</h2>
          <button type="button" onClick={onClose} disabled={saving} className="rounded-lg border border-slate-300 px-3 py-2 font-bold text-slate-800 disabled:opacity-50">{t("common.actions.cancel")}</button>
        </div>
        {errorMessage && <p role="alert" className="mb-3 rounded-lg border border-red-300 bg-red-50 p-3 text-sm font-bold text-red-800">{errorMessage}</p>}
        {loading ? (
          <div className="rounded-xl bg-white p-8 text-center font-bold text-slate-700">{t("common.states.loading")}</div>
        ) : form ? (
          <WorkshopForm
            workDate={form.workDate}
            setWorkDate={(value) => change("workDate", value)}
            vehicleId={form.vehicleId}
            setVehicleId={(value) => change("vehicleId", value)}
            workshopName={form.workshopName}
            workshopId={form.workshopId}
            onWorkshopChange={(value) => {
              const selected = workshops.find((workshop) => workshop.id === value);
              setForm((current) => current ? { ...current, workshopId: value, workshopName: selected?.workshopName ?? current.workshopName } : current);
            }}
            workshops={workshops}
            mechanicName={form.mechanicName}
            setMechanicName={(value) => change("mechanicName", value)}
            workItems={form.workItems}
            setWorkItems={(value) => change("workItems", value)}
            billNo={form.billNo}
            setBillNo={(value) => change("billNo", value)}
            paidAmount={form.paidAmount}
            setPaidAmount={(value) => change("paidAmount", value)}
            nextServiceDate={form.nextServiceDate}
            setNextServiceDate={(value) => change("nextServiceDate", value)}
            odometer={form.odometer}
            setOdometer={(value) => change("odometer", value)}
            remarks={form.remarks}
            setRemarks={(value) => change("remarks", value)}
            vehicles={vehicleOptions}
            onSave={() => void save()}
            isSaving={saving}
            isEditing
            onCancelEdit={onClose}
            vehicleLocked
          />
        ) : null}
      </section>
    </div>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import DieselCards from "@/components/diesel/DieselCards";
import DieselFilters from "@/components/diesel/DieselFilters";
import DieselTable from "@/components/diesel/DieselTable";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { supabase } from "@/lib/supabase/client";

export type DieselPaymentStatus = "Paid" | "Partial" | "Unpaid";

export type PetrolPumpOption = {
  id: string;
  pumpName: string;
};

export type VehicleOption = {
  id: string;
  vehicleNo: string;
};

export type DieselFilterValues = {
  fromDate: string;
  toDate: string;
  petrolPumpId: string;
  vehicleId: string;
  paymentStatus: string;
  search: string;
};

export type DieselEntryRow = {
  id: number;
  expenseId: number;
  expenseItemId: number;
  entryDate: string;
  petrolPumpId: string;
  pumpName: string;
  pumpOwner: string;
  vehicleId: string;
  vehicleNo: string;
  vehicleOwner: string;
  driverName: string;
  loadingNo: string;
  route: string;
  expenseNo: string;
  slipNo: string;
  liters: number;
  rate: number;
  totalAmount: number;
  paidAmount: number;
  remainingAmount: number;
  paymentStatus: DieselPaymentStatus;
  remarks: string;
  createdAt: string;
};

export type DieselSummary = {
  totalEntries: number;
  totalLiters: number;
  totalAmount: number;
  totalPaid: number;
  totalRemaining: number;
};

type RelatedRecord<T> = T | T[] | null;

type PetrolPumpRelation = {
  pump_name: string | null;
  owner_name: string | null;
};

type VehicleRelation = {
  vehicle_no: string | null;
  owner_name: string | null;
};

type DriverRelation = {
  name: string | null;
};

type LoadingRelation = {
  loading_no: string | null;
  route: string | null;
};

type ExpenseRelation = {
  expense_no: string | null;
};

type DieselDatabaseRow = {
  id: number;
  expense_id: number | string | null;
  expense_item_id: number | string | null;
  entry_date: string | null;
  petrol_pump_id: string | null;
  vehicle_id: string | null;
  driver_id: string | null;
  loading_id: number | string | null;
  slip_no: string | null;
  liters: number | string | null;
  rate: number | string | null;
  total_amount: number | string | null;
  paid_amount: number | string | null;
  remaining_amount: number | string | null;
  payment_status: string | null;
  remarks: string | null;
  created_at: string | null;
  petrol_pumps?: RelatedRecord<PetrolPumpRelation>;
  vehicles?: RelatedRecord<VehicleRelation>;
  drivers?: RelatedRecord<DriverRelation>;
  loadings?: RelatedRecord<LoadingRelation>;
  expenses?: RelatedRecord<ExpenseRelation>;
};

const defaultFilters: DieselFilterValues = {
  fromDate: "",
  toDate: "",
  petrolPumpId: "",
  vehicleId: "",
  paymentStatus: "",
  search: "",
};

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

export function formatLiters(value: number) {
  return `${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 2,
  })} L`;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function getSingleRelation<T>(relation: RelatedRecord<T> | undefined): T | null {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation ?? null;
}

function mapPaymentStatus(value: string | null): DieselPaymentStatus {
  if (value === "Paid" || value === "Partial" || value === "Unpaid") {
    return value;
  }

  return "Unpaid";
}

export default function Diesel() {
  const { t, dir } = useLanguage();
  const [addaId, setAddaId] = useState<string | null>(null);
  const [rows, setRows] = useState<DieselEntryRow[]>([]);
  const [filters, setFilters] = useState<DieselFilterValues>(defaultFilters);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  const loadDieselEntries = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage("");

    const auth = await supabase.auth.getUser();
    if (!auth.data.user) { setErrorMessage(t("diesel.messages.loadFailed")); setRows([]); setIsLoading(false); return; }
    const profile = await supabase.from("profiles").select("adda_id,is_active").eq("id", auth.data.user.id).maybeSingle();
    if (profile.error || !profile.data?.is_active || !profile.data.adda_id) { setErrorMessage(t("diesel.messages.loadFailed")); setRows([]); setIsLoading(false); return; }
    setAddaId(String(profile.data.adda_id));

    const { data, error } = await supabase
      .from("diesel_entries")
      .select(
        `
        id,
        expense_id,
        expense_item_id,
        entry_date,
        petrol_pump_id,
        vehicle_id,
        driver_id,
        loading_id,
        slip_no,
        liters,
        rate,
        total_amount,
        paid_amount,
        remaining_amount,
        payment_status,
        remarks,
        created_at,
        petrol_pumps(pump_name, owner_name),
        vehicles(vehicle_no, owner_name),
        drivers(name),
        loadings(loading_no, route),
        expenses(expense_no)
      `
      )
      .order("entry_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Unable to load Diesel entries:", error);
      setErrorMessage(t("diesel.messages.loadFailed"));
      setRows([]);
      setIsLoading(false);
      return;
    }

    setRows(
      ((data ?? []) as DieselDatabaseRow[]).map((entry) => {
        const pump = getSingleRelation(entry.petrol_pumps);
        const vehicle = getSingleRelation(entry.vehicles);
        const driver = getSingleRelation(entry.drivers);
        const loading = getSingleRelation(entry.loadings);
        const expense = getSingleRelation(entry.expenses);

        return {
          id: entry.id,
          expenseId: toNumber(entry.expense_id),
          expenseItemId: toNumber(entry.expense_item_id),
          entryDate: entry.entry_date ?? "",
          petrolPumpId: entry.petrol_pump_id ?? "",
          pumpName: pump?.pump_name ?? "-",
          pumpOwner: pump?.owner_name ?? "-",
          vehicleId: entry.vehicle_id ?? "",
          vehicleNo: vehicle?.vehicle_no ?? "-",
          vehicleOwner: vehicle?.owner_name ?? "-",
          driverName: driver?.name ?? "-",
          loadingNo: loading?.loading_no ?? "-",
          route: loading?.route ?? "-",
          expenseNo: expense?.expense_no ?? "-",
          slipNo: entry.slip_no ?? "-",
          liters: toNumber(entry.liters),
          rate: toNumber(entry.rate),
          totalAmount: toNumber(entry.total_amount),
          paidAmount: toNumber(entry.paid_amount),
          remainingAmount: toNumber(entry.remaining_amount),
          paymentStatus: mapPaymentStatus(entry.payment_status),
          remarks: entry.remarks ?? "-",
          createdAt: entry.created_at ?? "",
        };
      })
    );

    setIsLoading(false);
  }, [t]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void loadDieselEntries();
    }, 0);

    return () => window.clearTimeout(timer);
  }, [loadDieselEntries]);

  const petrolPumps = useMemo<PetrolPumpOption[]>(() => {
    const options = new Map<string, PetrolPumpOption>();

    rows.forEach((row) => {
      if (!row.petrolPumpId) return;

      options.set(row.petrolPumpId, {
        id: row.petrolPumpId,
        pumpName: row.pumpName,
      });
    });

    return Array.from(options.values()).sort((a, b) =>
      a.pumpName.localeCompare(b.pumpName)
    );
  }, [rows]);

  const vehicles = useMemo<VehicleOption[]>(() => {
    const options = new Map<string, VehicleOption>();

    rows.forEach((row) => {
      if (!row.vehicleId) return;

      options.set(row.vehicleId, {
        id: row.vehicleId,
        vehicleNo: row.vehicleNo,
      });
    });

    return Array.from(options.values()).sort((a, b) =>
      a.vehicleNo.localeCompare(b.vehicleNo)
    );
  }, [rows]);

  const filteredRows = useMemo(() => {
    const keyword = filters.search.trim().toLowerCase();

    return rows.filter((row) => {
      if (filters.fromDate && row.entryDate < filters.fromDate) return false;
      if (filters.toDate && row.entryDate > filters.toDate) return false;

      if (
        filters.petrolPumpId &&
        row.petrolPumpId !== filters.petrolPumpId
      ) {
        return false;
      }

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
        row.pumpName,
        row.pumpOwner,
        row.vehicleNo,
        row.vehicleOwner,
        row.driverName,
        row.loadingNo,
        row.route,
        row.expenseNo,
        row.slipNo,
        row.remarks,
        row.paymentStatus,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword);
    });
  }, [filters, rows]);

  const summary = useMemo<DieselSummary>(() => {
    return filteredRows.reduce(
      (total, row) => ({
        totalEntries: total.totalEntries + 1,
        totalLiters: total.totalLiters + row.liters,
        totalAmount: total.totalAmount + row.totalAmount,
        totalPaid: total.totalPaid + row.paidAmount,
        totalRemaining: total.totalRemaining + row.remainingAmount,
      }),
      {
        totalEntries: 0,
        totalLiters: 0,
        totalAmount: 0,
        totalPaid: 0,
        totalRemaining: 0,
      }
    );
  }, [filteredRows]);

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="diesel" accent="green" title={t("diesel.title")} description={t("diesel.description")} />
      </header>

      <DieselCards summary={summary} />

      <DieselFilters
        filters={filters}
        setFilters={setFilters}
        petrolPumps={petrolPumps}
        vehicles={vehicles}
        onReset={() => setFilters(defaultFilters)}
      />

      <DieselTable
        rows={filteredRows}
        isLoading={isLoading}
        errorMessage={errorMessage}
        filters={filters}
        addaId={addaId}
      />
    </div>
  );
}

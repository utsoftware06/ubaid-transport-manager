"use client";

import {
  useEffect,
  useMemo,
  useState,
  type ComponentType,
  type Dispatch,
  type SetStateAction,
} from "react";
import VehicleLedgerCards from "@/components/vehicleLedger/VehicleLedgerCards";
import VehicleLedgerFilters from "@/components/vehicleLedger/VehicleLedgerFilters";
import VehicleLedgerTable from "@/components/vehicleLedger/VehicleLedgerTable";
import VehicleTripsModal from "@/components/vehicleLedger/VehicleTripsModal";
import { supabase } from "@/lib/supabase/client";

export type VehicleFilterType =
  | "all"
  | "today"
  | "week"
  | "month"
  | "sixMonths"
  | "year"
  | "custom";

export type VehicleLedgerFilterValues = {
  vehicleId: string;
  vehicle: string;
  filterType: VehicleFilterType;
  fromDate: string;
  toDate: string;
  search: string;
};

export type VehicleTrip = {
  id: string;
  loadingNo: string;
  date: string;
  driverName: string;
  ownerName: string;
  route: string;
  income: number;
  expense: number;
  profit: number;
};

export type VehicleReport = {
  vehicleId: string;
  vehicleNo: string;
  ownerName: string;
  totalTrips: number;
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
  trips: VehicleTrip[];
};

export type VehicleLedgerSummary = {
  totalVehicles: number;
  totalTrips: number;
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
};

type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

type VehicleRelation = {
  vehicle_no: string | null;
  owner_name: string | null;
};

type DriverRelation = {
  name: string | null;
};

type BookingRelation = {
  freight: number | string | null;
};

type ExpenseItemRelation = {
  amount: number | string | null;
};

type ExpenseRelation = {
  expense_items: ExpenseItemRelation[] | null;
};

type RelatedRecord<T> = T | T[] | null;

type LoadingWithRelations = {
  id: string;
  loading_no: string | null;
  loading_date: string | null;
  route: string | null;
  vehicle_id: string | null;
  driver_id: string | null;
  booking_id: string | null;
  vehicles: RelatedRecord<VehicleRelation>;
  drivers: RelatedRecord<DriverRelation>;
  bookings: RelatedRecord<BookingRelation>;
  expenses: ExpenseRelation[] | null;
};

type VehicleLedgerCardsProps = {
  summary: VehicleLedgerSummary;
};

type VehicleLedgerFiltersProps = {
  filters: VehicleLedgerFilterValues;
  setFilters: Dispatch<SetStateAction<VehicleLedgerFilterValues>>;
  vehicleOptions: VehicleOption[];
};

type VehicleLedgerTableProps = {
  reports: VehicleReport[];
  onViewTrips: (vehicleReport: VehicleReport) => void;
};

type VehicleTripsModalProps = {
  vehicleReport: VehicleReport;
  onClose: () => void;
};

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function getSingleRelation<T>(relation: RelatedRecord<T>): T | null {
  if (Array.isArray(relation)) {
    return relation[0] ?? null;
  }

  return relation ?? null;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function isDateInRange(dateValue: string, filters: VehicleLedgerFilterValues) {
  if (!dateValue) return false;

  const loadingDate = new Date(`${dateValue}T00:00:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let fromDate: Date | null = null;
  let toDate: Date | null = today;

  if (filters.filterType === "all") {
    return true;
  }

  if (filters.filterType === "today") {
    fromDate = new Date(today);
  }

  if (filters.filterType === "week") {
    fromDate = new Date(today);
    fromDate.setDate(today.getDate() - 6);
  }

  if (filters.filterType === "month") {
    fromDate = new Date(today.getFullYear(), today.getMonth(), 1);
  }

  if (filters.filterType === "sixMonths") {
    fromDate = new Date(today);
    fromDate.setMonth(today.getMonth() - 6);
  }

  if (filters.filterType === "year") {
    fromDate = new Date(today.getFullYear(), 0, 1);
  }

  if (filters.filterType === "custom") {
    fromDate = filters.fromDate
      ? new Date(`${filters.fromDate}T00:00:00`)
      : null;
    toDate = filters.toDate ? new Date(`${filters.toDate}T00:00:00`) : null;
  }

  if (fromDate && loadingDate < fromDate) {
    return false;
  }

  if (toDate && loadingDate > toDate) {
    return false;
  }

  return true;
}

export default function VehicleLedger() {
  const [loadings, setLoadings] = useState<LoadingWithRelations[]>([]);
  const [filters, setFilters] = useState<VehicleLedgerFilterValues>({
    vehicleId: "",
    vehicle: "",
    filterType: "all",
    fromDate: "",
    toDate: "",
    search: "",
  });
  const [selectedVehicleReport, setSelectedVehicleReport] =
    useState<VehicleReport | null>(null);

  const CardsComponent =
    VehicleLedgerCards as ComponentType<VehicleLedgerCardsProps>;
  const FiltersComponent =
    VehicleLedgerFilters as ComponentType<VehicleLedgerFiltersProps>;
  const TableComponent =
    VehicleLedgerTable as ComponentType<VehicleLedgerTableProps>;
  const TripsModalComponent =
    VehicleTripsModal as ComponentType<VehicleTripsModalProps>;

  useEffect(() => {
    loadVehicleLedgerData();
  }, []);

  async function loadVehicleLedgerData() {
    const { data, error } = await supabase
      .from("loadings")
      .select(
        `
        id,
        loading_no,
        loading_date,
        route,
        vehicle_id,
        driver_id,
        booking_id,
        vehicles(vehicle_no, owner_name),
        drivers(name),
        bookings(freight),
        expenses(
          expense_items(amount)
        )
      `
      )
      .order("loading_date", { ascending: false });

    if (error) {
      alert(error.message);
      setLoadings([]);
      return;
    }

    setLoadings((data ?? []) as LoadingWithRelations[]);
  }

  function getLoadingIncome(loading: LoadingWithRelations) {
    const booking = getSingleRelation(loading.bookings);
    return toNumber(booking?.freight);
  }

  function getLoadingExpense(loading: LoadingWithRelations) {
    return (loading.expenses ?? []).reduce((expenseTotal, expense) => {
      const itemTotal = (expense.expense_items ?? []).reduce(
        (itemSum, item) => itemSum + toNumber(item.amount),
        0
      );

      return expenseTotal + itemTotal;
    }, 0);
  }

  const vehicleOptions = useMemo<VehicleOption[]>(() => {
    const vehicles = new Map<string, VehicleOption>();

    loadings.forEach((loading) => {
      if (!loading.vehicle_id) return;

      const vehicle = getSingleRelation(loading.vehicles);
      const vehicleNo = vehicle?.vehicle_no?.trim() || "Without Vehicle";
      const ownerName = vehicle?.owner_name?.trim() || "-";

      if (!vehicles.has(loading.vehicle_id)) {
        vehicles.set(loading.vehicle_id, {
          id: loading.vehicle_id,
          vehicleNo,
          ownerName,
        });
      }
    });

    return Array.from(vehicles.values()).sort((a, b) =>
      a.vehicleNo.localeCompare(b.vehicleNo)
    );
  }, [loadings]);

  const filteredLoadings = useMemo(() => {
    const selectedVehicle = (filters.vehicleId || filters.vehicle)
      .trim()
      .toLowerCase();
    const searchKeyword = filters.search.trim().toLowerCase();

    return loadings.filter((loading) => {
      const vehicle = getSingleRelation(loading.vehicles);
      const driver = getSingleRelation(loading.drivers);

      const vehicleId = loading.vehicle_id ?? "";
      const vehicleNo = vehicle?.vehicle_no ?? "";
      const ownerName = vehicle?.owner_name ?? "";
      const driverName = driver?.name ?? "";
      const loadingNo = loading.loading_no ?? "";
      const route = loading.route ?? "";
      const loadingDate = loading.loading_date ?? "";

      if (!isDateInRange(loadingDate, filters)) {
        return false;
      }

      if (
        selectedVehicle &&
        vehicleId.toLowerCase() !== selectedVehicle &&
        vehicleNo.toLowerCase() !== selectedVehicle
      ) {
        return false;
      }

      if (searchKeyword) {
        const searchableText = [
          vehicleNo,
          ownerName,
          loadingNo,
          loadingDate,
          driverName,
          route,
          String(getLoadingIncome(loading)),
          String(getLoadingExpense(loading)),
        ]
          .join(" ")
          .toLowerCase();

        return searchableText.includes(searchKeyword);
      }

      return true;
    });
  }, [filters, loadings]);

  const reports = useMemo<VehicleReport[]>(() => {
    const reportMap = new Map<string, VehicleReport>();

    filteredLoadings.forEach((loading) => {
      const vehicle = getSingleRelation(loading.vehicles);
      const driver = getSingleRelation(loading.drivers);

      const vehicleId = loading.vehicle_id ?? "without-vehicle";
      const vehicleNo = vehicle?.vehicle_no?.trim() || "Without Vehicle";
      const ownerName = vehicle?.owner_name?.trim() || "-";
      const income = getLoadingIncome(loading);
      const expense = getLoadingExpense(loading);
      const profit = income - expense;

      const trip: VehicleTrip = {
        id: loading.id,
        loadingNo: loading.loading_no ?? "-",
        date: loading.loading_date?.slice(0, 10) ?? "-",
        driverName: driver?.name ?? "-",
        ownerName,
        route: loading.route ?? "-",
        income,
        expense,
        profit,
      };

      const existingReport = reportMap.get(vehicleId);

      if (existingReport) {
        existingReport.totalTrips += 1;
        existingReport.totalIncome += income;
        existingReport.totalExpense += expense;
        existingReport.netProfit += profit;
        existingReport.trips.push(trip);
        return;
      }

      reportMap.set(vehicleId, {
        vehicleId,
        vehicleNo,
        ownerName,
        totalTrips: 1,
        totalIncome: income,
        totalExpense: expense,
        netProfit: profit,
        trips: [trip],
      });
    });

    return Array.from(reportMap.values()).sort((a, b) =>
      a.vehicleNo.localeCompare(b.vehicleNo)
    );
  }, [filteredLoadings]);

  const summary = useMemo<VehicleLedgerSummary>(() => {
    return reports.reduce(
      (total, report) => ({
        totalVehicles: total.totalVehicles + 1,
        totalTrips: total.totalTrips + report.totalTrips,
        totalIncome: total.totalIncome + report.totalIncome,
        totalExpense: total.totalExpense + report.totalExpense,
        netProfit: total.netProfit + report.netProfit,
      }),
      {
        totalVehicles: 0,
        totalTrips: 0,
        totalIncome: 0,
        totalExpense: 0,
        netProfit: 0,
      }
    );
  }, [reports]);

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">Vehicle Ledger</h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Track vehicle-wise trips, freight income, expenses and net profit.
        </p>
      </div>

      <CardsComponent summary={summary} />

      <FiltersComponent
        filters={filters}
        setFilters={setFilters}
        vehicleOptions={vehicleOptions}
      />

      <TableComponent
        reports={reports}
        onViewTrips={(vehicleReport) => setSelectedVehicleReport(vehicleReport)}
      />

      {selectedVehicleReport && (
        <TripsModalComponent
          vehicleReport={selectedVehicleReport}
          onClose={() => setSelectedVehicleReport(null)}
        />
      )}
    </div>
  );
}
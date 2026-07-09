"use client";

import { useEffect, useMemo, useState } from "react";
import OwnerLedgerCards from "@/components/ownerLedger/OwnerLedgerCards";
import OwnerLedgerFilters from "@/components/ownerLedger/OwnerLedgerFilters";
import OwnerLedgerTable from "@/components/ownerLedger/OwnerLedgerTable";
import OwnerTripsModal from "@/components/ownerLedger/OwnerTripsModal";
import { supabase } from "@/lib/supabase/client";

export type OwnerFilterType =
  | "all"
  | "today"
  | "week"
  | "month"
  | "sixMonths"
  | "year"
  | "custom";

export type OwnerLedgerFilterValues = {
  ownerName: string;
  filterType: OwnerFilterType;
  fromDate: string;
  toDate: string;
  search: string;
};

export type OwnerTrip = {
  id: string;
  loadingNo: string;
  date: string;
  vehicleNo: string;
  driverName: string;
  route: string;
  income: number;
  expense: number;
  profit: number;
};

export type OwnerReport = {
  ownerName: string;
  totalTrips: number;
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
  trips: OwnerTrip[];
};

export type OwnerLedgerSummary = {
  totalOwners: number;
  totalTrips: number;
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
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

function isDateInRange(dateValue: string, filters: OwnerLedgerFilterValues) {
  if (!dateValue) return false;

  const loadingDate = new Date(`${dateValue.slice(0, 10)}T00:00:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let fromDate: Date | null = null;
  let toDate: Date | null = today;

  if (filters.filterType === "all") return true;

  if (filters.filterType === "today") fromDate = new Date(today);

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

  if (fromDate && loadingDate < fromDate) return false;
  if (toDate && loadingDate > toDate) return false;

  return true;
}

export default function OwnerLedger() {
  const [loadings, setLoadings] = useState<LoadingWithRelations[]>([]);
  const [filters, setFilters] = useState<OwnerLedgerFilterValues>({
    ownerName: "",
    filterType: "all",
    fromDate: "",
    toDate: "",
    search: "",
  });
  const [selectedOwnerReport, setSelectedOwnerReport] =
    useState<OwnerReport | null>(null);

  useEffect(() => {
    async function loadOwnerLedgerData() {
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

    void loadOwnerLedgerData();
  }, []);

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

  const ownerOptions = useMemo(() => {
    const owners = new Set<string>();

    loadings.forEach((loading) => {
      const vehicle = getSingleRelation(loading.vehicles);
      const ownerName = vehicle?.owner_name?.trim();

      if (ownerName) owners.add(ownerName);
    });

    return Array.from(owners).sort((a, b) => a.localeCompare(b));
  }, [loadings]);

  const filteredLoadings = useMemo(() => {
    const ownerKeyword = filters.ownerName.trim().toLowerCase();
    const searchKeyword = filters.search.trim().toLowerCase();

    return loadings.filter((loading) => {
      const vehicle = getSingleRelation(loading.vehicles);
      const driver = getSingleRelation(loading.drivers);

      const ownerName = vehicle?.owner_name?.trim() || "Without Owner";
      const vehicleNo = vehicle?.vehicle_no ?? "";
      const driverName = driver?.name ?? "";
      const loadingNo = loading.loading_no ?? "";
      const route = loading.route ?? "";
      const loadingDate = loading.loading_date ?? "";

      if (!isDateInRange(loadingDate, filters)) return false;
      if (ownerKeyword && ownerName.toLowerCase() !== ownerKeyword) {
        return false;
      }

      if (searchKeyword) {
        const searchableText = [
          ownerName,
          loadingNo,
          loadingDate,
          vehicleNo,
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

  const reports = useMemo<OwnerReport[]>(() => {
    const reportMap = new Map<string, OwnerReport>();

    filteredLoadings.forEach((loading) => {
      const vehicle = getSingleRelation(loading.vehicles);
      const driver = getSingleRelation(loading.drivers);

      const ownerName = vehicle?.owner_name?.trim() || "Without Owner";
      const income = getLoadingIncome(loading);
      const expense = getLoadingExpense(loading);
      const profit = income - expense;

      const trip: OwnerTrip = {
        id: loading.id,
        loadingNo: loading.loading_no ?? "-",
        date: loading.loading_date?.slice(0, 10) ?? "-",
        vehicleNo: vehicle?.vehicle_no ?? "-",
        driverName: driver?.name ?? "-",
        route: loading.route ?? "-",
        income,
        expense,
        profit,
      };

      const existingReport = reportMap.get(ownerName);

      if (existingReport) {
        existingReport.totalTrips += 1;
        existingReport.totalIncome += income;
        existingReport.totalExpense += expense;
        existingReport.netProfit += profit;
        existingReport.trips.push(trip);
        return;
      }

      reportMap.set(ownerName, {
        ownerName,
        totalTrips: 1,
        totalIncome: income,
        totalExpense: expense,
        netProfit: profit,
        trips: [trip],
      });
    });

    return Array.from(reportMap.values()).sort((a, b) =>
      a.ownerName.localeCompare(b.ownerName)
    );
  }, [filteredLoadings]);

  const summary = useMemo<OwnerLedgerSummary>(() => {
    return reports.reduce(
      (total, report) => ({
        totalOwners: total.totalOwners + 1,
        totalTrips: total.totalTrips + report.totalTrips,
        totalIncome: total.totalIncome + report.totalIncome,
        totalExpense: total.totalExpense + report.totalExpense,
        netProfit: total.netProfit + report.netProfit,
      }),
      {
        totalOwners: 0,
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
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Owner Ledger</h1>
          <p className="mt-2 text-base font-medium text-gray-900">
            Track owner-wise trips, freight income, expenses and net profit.
          </p>
        </div>
      </div>

      <OwnerLedgerCards summary={summary} />

      <OwnerLedgerFilters
        filters={filters}
        setFilters={setFilters}
        ownerOptions={ownerOptions}
      />

      <OwnerLedgerTable
        reports={reports}
        onViewTrips={(ownerReport) => setSelectedOwnerReport(ownerReport)}
      />

      {selectedOwnerReport && (
        <OwnerTripsModal
          ownerReport={selectedOwnerReport}
          onClose={() => setSelectedOwnerReport(null)}
        />
      )}
    </div>
  );
}
"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import DriverLedgerCards from "./DriverLedgerCards";
import DriverLedgerFilters from "./DriverLedgerFilters";
import DriverLedgerTable from "./DriverLedgerTable";

export type RelatedRecord<T> = T | T[] | null;

export type DriverOption = {
  id: string;
  name: string;
};

export type BookingRelation = {
  freight: number | string | null;
};

export type ExpenseItemRelation = {
  amount: number | string | null;
};

export type ExpenseRelation = {
  expense_items: ExpenseItemRelation[] | null;
};

export type LoadingLedgerRecord = {
  id: number | string;
  loading_no: string | null;
  loading_date: string | null;
  route: string | null;
  driver_id: string | null;
  bookings: RelatedRecord<BookingRelation>;
  expenses: ExpenseRelation[] | null;
};

export type DriverLedgerRow = {
  id: number | string;
  loadingNo: string;
  date: string;
  route: string;
  income: number;
  expense: number;
  balance: number;
};

export type DriverLedgerSummary = {
  totalTrips: number;
  totalIncome: number;
  totalExpense: number;
  netBalance: number;
};

export type DriverLedgerFilterValues = {
  driverId: string;
  fromDate: string;
  toDate: string;
  search: string;
};

const emptyFilters: DriverLedgerFilterValues = {
  driverId: "",
  fromDate: "",
  toDate: "",
  search: "",
};

function getSingleRelation<T>(relation: RelatedRecord<T>): T | null {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation;
}

function toNumber(value: number | string | null | undefined): number {
  const parsedValue = Number(value ?? 0);
  return Number.isFinite(parsedValue) ? parsedValue : 0;
}

function getLoadingIncome(loading: LoadingLedgerRecord): number {
  const booking = getSingleRelation(loading.bookings);
  return toNumber(booking?.freight);
}

function getLoadingExpense(loading: LoadingLedgerRecord): number {
  return (loading.expenses ?? []).reduce(
    (expenseTotal, expense) =>
      expenseTotal +
      (expense.expense_items ?? []).reduce(
        (itemTotal, item) => itemTotal + toNumber(item.amount),
        0
      ),
    0
  );
}

export default function DriverLedger() {
  const [drivers, setDrivers] = useState<DriverOption[]>([]);
  const [loadings, setLoadings] = useState<LoadingLedgerRecord[]>([]);
  const [filterValues, setFilterValues] =
    useState<DriverLedgerFilterValues>(emptyFilters);
  const [appliedFilters, setAppliedFilters] =
    useState<DriverLedgerFilterValues>(emptyFilters);

  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let isMounted = true;

    async function fetchLedgerData() {
      setIsLoading(true);
      setErrorMessage("");

      const [driversRes, loadingsRes] = await Promise.all([
        supabase
          .from("drivers")
          .select("id, name")
          .order("name", { ascending: true }),

        supabase
          .from("loadings")
          .select(
            `
            id,
            loading_no,
            loading_date,
            route,
            driver_id,
            bookings(freight),
            expenses(
              expense_items(amount)
            )
          `
          )
          .order("id", { ascending: false }),
      ]);

      if (!isMounted) return;

      if (driversRes.error || loadingsRes.error) {
        setErrorMessage(
          driversRes.error?.message ||
            loadingsRes.error?.message ||
            "Unable to load driver ledger."
        );
        setDrivers([]);
        setLoadings([]);
        setIsLoading(false);
        return;
      }

      setDrivers((driversRes.data ?? []) as DriverOption[]);
      setLoadings((loadingsRes.data ?? []) as unknown as LoadingLedgerRecord[]);
      setIsLoading(false);
    }

    void fetchLedgerData();

    return () => {
      isMounted = false;
    };
  }, []);

  const selectedDriver = useMemo(() => {
    return (
      drivers.find((driver) => driver.id === appliedFilters.driverId) ?? null
    );
  }, [drivers, appliedFilters.driverId]);

  const ledgerRows = useMemo<DriverLedgerRow[]>(() => {
    return loadings
      .filter((loading) => {
        if (appliedFilters.driverId && loading.driver_id !== appliedFilters.driverId) {
          return false;
        }

        const loadingDate = loading.loading_date?.slice(0, 10) ?? "";

        if (appliedFilters.fromDate && loadingDate < appliedFilters.fromDate) {
          return false;
        }

        if (appliedFilters.toDate && loadingDate > appliedFilters.toDate) {
          return false;
        }

        const searchText = appliedFilters.search.trim().toLowerCase();

        if (searchText) {
          const combinedText = `${loading.loading_no ?? ""} ${
            loading.route ?? ""
          } ${loadingDate}`.toLowerCase();

          if (!combinedText.includes(searchText)) return false;
        }

        return true;
      })
      .map((loading) => {
        const income = getLoadingIncome(loading);
        const expense = getLoadingExpense(loading);

        return {
          id: loading.id,
          loadingNo: loading.loading_no ?? String(loading.id),
          date: loading.loading_date?.slice(0, 10) ?? "-",
          route: loading.route ?? "-",
          income,
          expense,
          balance: income - expense,
        };
      });
  }, [loadings, appliedFilters]);

  const summary = useMemo<DriverLedgerSummary>(() => {
    return ledgerRows.reduce(
      (total, row) => {
        total.totalTrips += 1;
        total.totalIncome += row.income;
        total.totalExpense += row.expense;
        total.netBalance = total.totalIncome - total.totalExpense;
        return total;
      },
      {
        totalTrips: 0,
        totalIncome: 0,
        totalExpense: 0,
        netBalance: 0,
      }
    );
  }, [ledgerRows]);

  function handleSearch() {
    setAppliedFilters(filterValues);
  }

  function handleReset() {
    setFilterValues(emptyFilters);
    setAppliedFilters(emptyFilters);
  }

  return (
    <section className="space-y-6">
      <div className="rounded-xl bg-white p-6 shadow-md">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Driver Ledger</h1>
          <p className="mt-1 text-sm font-medium text-gray-700">
            Driver wise trips, income, expense aur balance report.
          </p>
        </div>

        <div className="mt-6">
          <DriverLedgerFilters
            drivers={drivers}
            filterValues={filterValues}
            setFilterValues={setFilterValues}
            onSearch={handleSearch}
            onReset={handleReset}
          />
        </div>
      </div>

      {isLoading && (
        <div className="rounded-xl bg-white p-8 text-center font-semibold text-gray-900 shadow-md">
          Loading driver ledger...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-6 text-red-700 shadow-md">
          <p className="font-bold">Unable to load driver ledger.</p>
          <p className="mt-1 text-sm font-medium">{errorMessage}</p>
        </div>
      )}

      {!isLoading && !errorMessage && (
        <>
          <DriverLedgerCards summary={summary} />

          <DriverLedgerTable
            rows={ledgerRows}
            selectedDriverName={selectedDriver?.name ?? "All Drivers"}
          />
        </>
      )}
    </section>
  );
}
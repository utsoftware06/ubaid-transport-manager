"use client";

import { useEffect, useMemo, useState } from "react";
import DashboardCards from "@/components/dashboard/DashboardCards";
import DashboardFilters from "@/components/dashboard/DashboardFilters";
import IncomeExpenseChart from "@/components/dashboard/IncomeExpenseChart";
import RecentTrips from "@/components/dashboard/RecentTrips";
import { supabase } from "@/lib/supabase/client";

export type DashboardDateFilter =
  | "today"
  | "last7Days"
  | "thisMonth"
  | "last6Months"
  | "thisYear"
  | "custom";

export type DashboardTripStatus =
  | "Planned"
  | "Loading"
  | "In Transit"
  | "Delivered"
  | "Completed"
  | "Cancelled";

export type DashboardTrip = {
  id: string;
  addaId: string;
  tripNo: string;
  tripDate: string;
  customerName: string;
  loadingFrom: string;
  deliveryTo: string;
  freightAmount: number;
  receivedAmount: number;
  paymentBalance: number;
  totalExpense: number;
  netProfit: number;
  tripStatus: DashboardTripStatus;
  createdAt: string;
  vehicleId: string | null;
  driverId: string | null;
  vehicleNo: string;
  ownerName: string;
  driverName: string;
};

export type DashboardMetricSummary = {
  totalTrips: number;
  totalFreight: number;
  cashReceived: number;
  expenses: number;
  netProfit: number;
  pendingBalance: number;
};

export type DashboardOverallSummary = {
  activeTrips: number;
  completedTrips: number;
  cancelledTrips: number;
  totalPendingBalance: number;
};

export type DashboardSummary = {
  today: DashboardMetricSummary;
  month: DashboardMetricSummary;
  filtered: DashboardMetricSummary;
  overall: DashboardOverallSummary;
};

type CurrentContext = {
  userId: string;
  addaId: string;
};

type ProfileRow = {
  adda_id: string | null;
};

type VehicleRelation = {
  vehicle_no: string | null;
  owner_name: string | null;
};

type DriverRelation = {
  name: string | null;
};

type RelationValue<T> = T | T[] | null;

type TripDbRow = {
  id: string;
  adda_id: string;
  trip_no: string | null;
  trip_date: string | null;
  customer_name: string | null;
  loading_from: string | null;
  delivery_to: string | null;
  freight_amount: number | string | null;
  received_amount: number | string | null;
  payment_balance: number | string | null;
  total_expense: number | string | null;
  net_profit: number | string | null;
  trip_status: string | null;
  created_at: string | null;
  vehicle_id: string | null;
  driver_id: string | null;
  vehicles?: RelationValue<VehicleRelation>;
  drivers?: RelationValue<DriverRelation>;
};

export function formatAmount(value: number) {
  return `Rs. ${Math.round(Number(value || 0)).toLocaleString("en-PK")}`;
}

function toNumber(value: number | string | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function readRelation<T>(value: RelationValue<T> | undefined) {
  if (!value) return null;
  return Array.isArray(value) ? value[0] ?? null : value;
}

function toTripStatus(value: string | null): DashboardTripStatus {
  if (
    value === "Loading" ||
    value === "In Transit" ||
    value === "Delivered" ||
    value === "Completed" ||
    value === "Cancelled"
  ) {
    return value;
  }

  return "Planned";
}

function getLocalDate(value: string) {
  const date = new Date(`${value}T00:00:00`);
  date.setHours(0, 0, 0, 0);
  return date;
}

function getToday() {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return today;
}

function isSameDay(value: string, date: Date) {
  const current = getLocalDate(value);
  return current.getTime() === date.getTime();
}

function isThisMonth(value: string) {
  const date = getLocalDate(value);
  const today = getToday();

  return (
    date.getFullYear() === today.getFullYear() &&
    date.getMonth() === today.getMonth()
  );
}

function isInFilterRange(
  tripDate: string,
  filter: DashboardDateFilter,
  fromDate: string,
  toDate: string
) {
  if (!tripDate) return false;

  const date = getLocalDate(tripDate);
  const today = getToday();

  if (Number.isNaN(date.getTime())) return false;

  if (filter === "today") {
    return isSameDay(tripDate, today);
  }

  if (filter === "last7Days") {
    const start = new Date(today);
    start.setDate(start.getDate() - 6);
    return date >= start && date <= today;
  }

  if (filter === "thisMonth") {
    return isThisMonth(tripDate);
  }

  if (filter === "last6Months") {
    const start = new Date(today);
    start.setMonth(start.getMonth() - 6);
    return date >= start && date <= today;
  }

  if (filter === "thisYear") {
    return date.getFullYear() === today.getFullYear();
  }

  if (filter === "custom") {
    if (fromDate && date < getLocalDate(fromDate)) return false;
    if (toDate && date > getLocalDate(toDate)) return false;
    return true;
  }

  return true;
}

function buildMetricSummary(trips: DashboardTrip[]): DashboardMetricSummary {
  return trips.reduce(
    (summary, trip) => {
      summary.totalTrips += 1;
      summary.totalFreight += trip.freightAmount;
      summary.cashReceived += trip.receivedAmount;
      summary.expenses += trip.totalExpense;
      summary.netProfit += trip.netProfit;
      summary.pendingBalance += trip.paymentBalance;
      return summary;
    },
    {
      totalTrips: 0,
      totalFreight: 0,
      cashReceived: 0,
      expenses: 0,
      netProfit: 0,
      pendingBalance: 0,
    }
  );
}

export default function DashboardOverview() {
  const [trips, setTrips] = useState<DashboardTrip[]>([]);
  const [dateFilter, setDateFilter] =
    useState<DashboardDateFilter>("thisMonth");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  const filteredTrips = useMemo(() => {
    return trips.filter((trip) =>
      isInFilterRange(trip.tripDate, dateFilter, fromDate, toDate)
    );
  }, [dateFilter, fromDate, toDate, trips]);

  const recentTrips = useMemo(() => {
    return [...filteredTrips]
      .sort((first, second) => {
        const dateCompare = second.tripDate.localeCompare(first.tripDate);
        if (dateCompare !== 0) return dateCompare;
        return second.createdAt.localeCompare(first.createdAt);
      })
      .slice(0, 10);
  }, [filteredTrips]);

  const summary = useMemo<DashboardSummary>(() => {
    const today = getToday();
    const todayTrips = trips.filter((trip) => isSameDay(trip.tripDate, today));
    const monthTrips = trips.filter((trip) => isThisMonth(trip.tripDate));

    const overall = trips.reduce(
      (total, trip) => {
        if (
          trip.tripStatus === "Loading" ||
          trip.tripStatus === "In Transit" ||
          trip.tripStatus === "Delivered"
        ) {
          total.activeTrips += 1;
        }

        if (trip.tripStatus === "Completed") total.completedTrips += 1;
        if (trip.tripStatus === "Cancelled") total.cancelledTrips += 1;

        total.totalPendingBalance += trip.paymentBalance;
        return total;
      },
      {
        activeTrips: 0,
        completedTrips: 0,
        cancelledTrips: 0,
        totalPendingBalance: 0,
      }
    );

    return {
      today: buildMetricSummary(todayTrips),
      month: buildMetricSummary(monthTrips),
      filtered: buildMetricSummary(filteredTrips),
      overall,
    };
  }, [filteredTrips, trips]);

  useEffect(() => {
    loadDashboard();
  }, []);

  async function loadCurrentContext(): Promise<CurrentContext> {
    const { data: authData, error: authError } = await supabase.auth.getUser();

    if (authError) {
      throw new Error(authError.message || "Unable to verify current user.");
    }

    const userId = authData.user?.id;

    if (!userId) {
      throw new Error("No authenticated user found. Please log in again.");
    }

    const { data: profileData, error: profileError } = await supabase
      .from("profiles")
      .select("adda_id")
      .eq("id", userId)
      .maybeSingle();

    if (profileError) {
      throw new Error(profileError.message || "Unable to load user profile.");
    }

    const profile = profileData as ProfileRow | null;
    const addaId = profile?.adda_id;

    if (!addaId) {
      throw new Error("No adda is assigned to the current user.");
    }

    return {
      userId,
      addaId,
    };
  }

  async function loadTrips(addaId: string) {
    const { data, error } = await supabase
      .from("trips")
      .select(
        `
        id,
        adda_id,
        trip_no,
        trip_date,
        customer_name,
        loading_from,
        delivery_to,
        freight_amount,
        received_amount,
        payment_balance,
        total_expense,
        net_profit,
        trip_status,
        created_at,
        vehicle_id,
        driver_id,
        vehicles(vehicle_no, owner_name),
        drivers(name)
      `
      )
      .eq("adda_id", addaId)
      .order("trip_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (error) {
      throw new Error(error.message || "Unable to load dashboard trips.");
    }

    const rows = (data ?? []) as TripDbRow[];

    setTrips(
      rows.map((trip) => {
        const vehicle = readRelation(trip.vehicles);
        const driver = readRelation(trip.drivers);

        return {
          id: trip.id,
          addaId: trip.adda_id,
          tripNo: trip.trip_no ?? "",
          tripDate: trip.trip_date ?? "",
          customerName: trip.customer_name ?? "",
          loadingFrom: trip.loading_from ?? "",
          deliveryTo: trip.delivery_to ?? "",
          freightAmount: toNumber(trip.freight_amount),
          receivedAmount: toNumber(trip.received_amount),
          paymentBalance: toNumber(trip.payment_balance),
          totalExpense: toNumber(trip.total_expense),
          netProfit: toNumber(trip.net_profit),
          tripStatus: toTripStatus(trip.trip_status),
          createdAt: trip.created_at ?? "",
          vehicleId: trip.vehicle_id,
          driverId: trip.driver_id,
          vehicleNo: vehicle?.vehicle_no ?? "-",
          ownerName: vehicle?.owner_name ?? "-",
          driverName: driver?.name ?? "-",
        };
      })
    );
  }

  async function loadDashboard() {
    setIsLoading(true);
    setErrorMessage("");

    try {
      const context = await loadCurrentContext();
      await loadTrips(context.addaId);
    } catch (error) {
      setErrorMessage(
        error instanceof Error
          ? error.message
          : "Unable to load dashboard data."
      );
    } finally {
      setIsLoading(false);
    }
  }

  async function handleRefresh() {
    setIsRefreshing(true);
    setErrorMessage("");

    try {
      const context = await loadCurrentContext();
      await loadTrips(context.addaId);
    } catch (error) {
      setErrorMessage(
        error instanceof Error
          ? error.message
          : "Unable to refresh dashboard data."
      );
    } finally {
      setIsRefreshing(false);
    }
  }

  function handleResetFilters() {
    setDateFilter("thisMonth");
    setFromDate("");
    setToDate("");
  }

  return (
    <div className="mx-auto max-w-7xl space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">
              Transport Business Dashboard
            </h1>
            <p className="mt-2 text-base font-medium text-gray-900">
              Track trips, freight, cash received, expenses, pending balances
              and net profit.
            </p>
          </div>

          <button
            type="button"
            onClick={() => {
              void handleRefresh();
            }}
            disabled={isLoading || isRefreshing}
            className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed"
          >
            {isRefreshing ? "Refreshing..." : "Refresh"}
          </button>
        </div>

        {errorMessage && (
          <div className="mt-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
            {errorMessage}
          </div>
        )}
      </div>

      <DashboardFilters
        dateFilter={dateFilter}
        setDateFilter={setDateFilter}
        fromDate={fromDate}
        setFromDate={setFromDate}
        toDate={toDate}
        setToDate={setToDate}
        onReset={handleResetFilters}
      />

      <DashboardCards summary={summary} loading={isLoading} />

      <IncomeExpenseChart
        trips={filteredTrips}
        summary={summary.filtered}
        loading={isLoading}
      />

      <RecentTrips
        trips={recentTrips}
        loading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}
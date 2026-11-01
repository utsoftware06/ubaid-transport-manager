"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowUpRight,
  BarChart3,
  PackageOpen,
  ReceiptText,
  TrendingUp,
  Truck,
  UsersRound,
} from "lucide-react";
import DashboardCards from "@/components/dashboard/DashboardCards";
import DashboardHero from "@/components/dashboard/DashboardHero";
import IncomeExpenseChart from "@/components/dashboard/IncomeExpenseChart";
import RecentTrips from "@/components/dashboard/RecentTrips";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";

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

export type DashboardRecentEntry = {
  id: string;
  entryDate: string;
  entryType: "Cash In" | "Cash Out";
  personName: string;
  description: string;
  amount: number;
  referenceType: string | null;
  createdAt: string;
};

type CurrentContext = {
  userId: string;
  addaId: string;
  role: string | null;
};

type ProfileRow = {
  adda_id: string | null;
  role: string | null;
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

type CashbookDbRow = {
  id: string | number;
  entry_date: string | null;
  entry_type: string | null;
  person_name: string | null;
  description: string | null;
  amount: number | string | null;
  reference_type: string | null;
  created_at: string | null;
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

function metricRows(
  summary: DashboardMetricSummary,
  t: (key: string) => string
) {
  return [
    { label: t("dashboard.metrics.totalTrips"), value: summary.totalTrips },
    { label: t("dashboard.metrics.totalFreight"), value: formatAmount(summary.totalFreight) },
    { label: t("dashboard.metrics.cashReceived"), value: formatAmount(summary.cashReceived) },
    { label: t("dashboard.metrics.expenses"), value: formatAmount(summary.expenses) },
    { label: t("dashboard.metrics.netProfit"), value: formatAmount(summary.netProfit) },
    { label: t("dashboard.metrics.pendingBalance"), value: formatAmount(summary.pendingBalance) },
  ];
}

function overallMetricRows(
  summary: DashboardOverallSummary,
  t: (key: string) => string
) {
  return [
    { label: t("dashboard.metrics.activeTrips"), value: summary.activeTrips },
    { label: t("dashboard.metrics.completedTrips"), value: summary.completedTrips },
    { label: t("dashboard.metrics.cancelledTrips"), value: summary.cancelledTrips },
    { label: t("dashboard.metrics.totalPendingBalance"), value: formatAmount(summary.totalPendingBalance) },
  ];
}

export default function DashboardOverview() {
  const { t, dir } = useLanguage();
  const [trips, setTrips] = useState<DashboardTrip[]>([]);
  const [recentEntries, setRecentEntries] = useState<DashboardRecentEntry[]>([]);
  const [vehicleCount, setVehicleCount] = useState<number | null>(null);
  const [partyCount, setPartyCount] = useState<number | null>(null);
  const [countsLoading, setCountsLoading] = useState(true);
  const [recentEntriesLoading, setRecentEntriesLoading] = useState(true);
  const [recentEntriesError, setRecentEntriesError] = useState("");
  const [profileRole, setProfileRole] = useState<string | null>(null);
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

  const loadCurrentContext = useCallback(async (): Promise<CurrentContext> => {
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
      .select("adda_id, role")
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
      role: profile?.role ?? null,
    };
  }, []);

  const loadTrips = useCallback(async (addaId: string) => {
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
  }, []);

  const loadTenantCounts = useCallback(async (addaId: string) => {
    setCountsLoading(true);
    setVehicleCount(null);
    setPartyCount(null);
    try {
      const [vehicleResult, partyResult] = await Promise.all([
        supabase
          .from("vehicles")
          .select("id", { count: "exact", head: true })
          .eq("adda_id", addaId),
        supabase
          .from("parties")
          .select("id", { count: "exact", head: true })
          .eq("adda_id", addaId)
          .eq("is_active", true),
      ]);

      if (vehicleResult.error) {
        console.error("Unable to load dashboard vehicle count:", vehicleResult.error);
      } else {
        setVehicleCount(vehicleResult.count ?? null);
      }

      if (partyResult.error) {
        console.error("Unable to load dashboard Party count:", partyResult.error);
      } else {
        setPartyCount(partyResult.count ?? null);
      }
    } catch (error) {
      console.error("Unable to load dashboard counts:", error);
    } finally {
      setCountsLoading(false);
    }
  }, []);

  const loadRecentEntries = useCallback(async (addaId: string) => {
    setRecentEntriesLoading(true);
    setRecentEntriesError("");

    try {
      const { data, error } = await supabase.rpc("get_cashbook_entries", {
        p_adda_id: addaId,
      });

      if (error) throw error;

      const rows = ((data ?? []) as CashbookDbRow[])
        .map((row): DashboardRecentEntry => {
          const amount = Number(row.amount ?? 0);
          return {
            id: String(row.id),
            entryDate: row.entry_date ?? "",
            entryType: row.entry_type === "Cash Out" ? "Cash Out" : "Cash In",
            personName: row.person_name ?? "",
            description: row.description ?? "",
            amount: Number.isFinite(amount) ? amount : 0,
            referenceType: row.reference_type,
            createdAt: row.created_at ?? "",
          };
        })
        .sort((first, second) => {
          const dateOrder = second.entryDate.localeCompare(first.entryDate);
          if (dateOrder !== 0) return dateOrder;
          const createdOrder = second.createdAt.localeCompare(first.createdAt);
          if (createdOrder !== 0) return createdOrder;
          return second.id.localeCompare(first.id, undefined, { numeric: true });
        })
        .slice(0, 5);

      setRecentEntries(rows);
    } catch (error) {
      console.error("Unable to load recent Cashbook entries:", error);
      setRecentEntries([]);
      setRecentEntriesError(t("dashboard.shell.recent.loadError"));
    } finally {
      setRecentEntriesLoading(false);
    }
  }, [t]);

  const loadDashboard = useCallback(async () => {
    setCountsLoading(true);
    setRecentEntriesLoading(true);
    try {
      const context = await loadCurrentContext();
      setProfileRole(context.role);
      await Promise.all([
        loadTrips(context.addaId),
        loadTenantCounts(context.addaId),
        loadRecentEntries(context.addaId),
      ]);
    } catch (error) {
      console.error("Unable to load dashboard:", error);
      setErrorMessage(t("dashboard.messages.loadError"));
      setCountsLoading(false);
      setRecentEntriesLoading(false);
    } finally {
      setIsLoading(false);
    }
  }, [loadCurrentContext, loadRecentEntries, loadTenantCounts, loadTrips, t]);

  useEffect(() => {
    const loadTimer = window.setTimeout(() => {
      void loadDashboard();
    }, 0);

    return () => {
      window.clearTimeout(loadTimer);
    };
  }, [loadDashboard]);

  async function handleRefresh() {
    setIsRefreshing(true);
    setErrorMessage("");

    try {
      const context = await loadCurrentContext();
      setProfileRole(context.role);
      await Promise.all([
        loadTrips(context.addaId),
        loadTenantCounts(context.addaId),
        loadRecentEntries(context.addaId),
      ]);
    } catch (error) {
      console.error("Unable to refresh dashboard:", error);
      setErrorMessage(t("dashboard.messages.refreshError"));
      setCountsLoading(false);
      setRecentEntriesLoading(false);
    } finally {
      setIsRefreshing(false);
    }
  }

  function handleResetFilters() {
    setDateFilter("thisMonth");
    setFromDate("");
    setToDate("");
  }

  const quickActions = [
    {
      href: "/parties",
      label: t("dashboard.shell.quick.addParty"),
      icon: UsersRound,
      tone: "bg-purple-600 text-white",
      surface: "bg-purple-50/70 hover:bg-purple-50",
      borderTone: "border-purple-100 hover:border-purple-200",
    },
    {
      href: "/loading",
      label: t("dashboard.shell.quick.addLoading"),
      icon: PackageOpen,
      tone: "bg-orange-600 text-white",
      surface: "bg-orange-50/70 hover:bg-orange-50",
      borderTone: "border-orange-100 hover:border-orange-200",
    },
    {
      href: "/expenses",
      label: t("dashboard.shell.quick.addVoucher"),
      icon: ReceiptText,
      tone: "bg-emerald-600 text-white",
      surface: "bg-emerald-50/70 hover:bg-emerald-50",
      borderTone: "border-emerald-100 hover:border-emerald-200",
    },
    {
      href: "/vehicles",
      label: t("dashboard.shell.quick.addVehicle"),
      icon: Truck,
      tone: "bg-blue-600 text-white",
      surface: "bg-blue-50/60 hover:bg-blue-50",
      borderTone: "border-blue-100 hover:border-blue-200",
    },
    {
      href: "/reports",
      label: t("dashboard.shell.quick.viewReports"),
      icon: BarChart3,
      tone: "bg-violet-600 text-white",
      surface: "bg-violet-50/70 hover:bg-violet-50",
      borderTone: "border-violet-100 hover:border-violet-200",
    },
  ];
  const analyticsSections = [
    {
      title: t("dashboard.sections.filteredPeriod"),
      rows: metricRows(summary.filtered, t),
    },
    {
      title: t("dashboard.sections.today"),
      rows: metricRows(summary.today, t),
    },
    {
      title: t("dashboard.sections.thisMonth"),
      rows: metricRows(summary.month, t),
    },
    {
      title: t("dashboard.sections.overall"),
      rows: overallMetricRows(summary.overall, t),
    },
  ];

  return (
    <div dir={dir} className="mx-auto w-full max-w-[1680px] min-w-0 space-y-[18px]">
      <DashboardHero
        isSuperAdmin={profileRole === "super_admin"}
        isLoading={isLoading}
        isRefreshing={isRefreshing}
        onRefresh={() => {
          void handleRefresh();
        }}
      />
      {errorMessage && (
        <div
          role="alert"
          className="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-bold text-rose-700"
        >
          {errorMessage}
        </div>
      )}
      <DashboardCards
        summary={summary}
        loading={isLoading}
        vehicleCount={vehicleCount}
        partyCount={partyCount}
        countsLoading={countsLoading}
      />
      <div className="grid min-w-0 items-stretch gap-4 xl:grid-cols-[minmax(0,13fr)_minmax(0,12fr)]">
        <IncomeExpenseChart
          trips={filteredTrips}
          summary={summary.filtered}
          loading={isLoading}
          dateFilter={dateFilter}
          setDateFilter={setDateFilter}
          fromDate={fromDate}
          setFromDate={setFromDate}
          toDate={toDate}
          setToDate={setToDate}
          onReset={handleResetFilters}
        />
        <RecentTrips
          entries={recentEntries}
          loading={recentEntriesLoading}
          errorMessage={recentEntriesError}
        />
      </div>
      <section
        aria-label={t("dashboard.shell.quick.title")}
        className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5"
      >
        {quickActions.map((action) => {
            const Icon = action.icon;
            return (
              <Link
                key={action.href}
                href={action.href}
                className={["group relative flex h-[110px] flex-col items-start justify-between overflow-hidden rounded-[14px] border p-4 transition duration-150 hover:-translate-y-0.5 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500", action.surface, action.borderTone].join(" ")}
              >
                <span className={["flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-[13px] shadow-[0_4px_10px_rgb(15_23_42_/_14%)] transition duration-150 group-hover:scale-105", action.tone].join(" ")}>
                  <Icon className="h-6 w-6" strokeWidth={2.5} aria-hidden="true" />
                </span>
                <span className="min-w-0 text-base font-bold leading-5 text-slate-800">
                  {action.label}
                </span>
                <span className="absolute end-4 top-4 flex h-[34px] w-[34px] items-center justify-center rounded-full bg-white/80 text-slate-600 transition group-hover:bg-white group-hover:text-blue-700">
                  <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
                </span>
              </Link>
            );
        })}
      </section>
      <details className="rounded-xl border border-slate-200/60 bg-white/50 px-3 py-2">
        <summary className="flex cursor-pointer list-none items-center gap-2 text-[11px] font-bold text-slate-500 outline-none focus-visible:ring-2 focus-visible:ring-blue-500">
          <TrendingUp className="h-3.5 w-3.5 text-slate-400" aria-hidden="true" />
          {t("dashboard.shell.stats.moreAnalytics")}
        </summary>
        <div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          {analyticsSections.map((section) => (
            <div key={section.title} className="rounded-2xl border border-slate-100 bg-white p-4">
              <h3 className="text-sm font-black text-slate-800">{section.title}</h3>
              <div className="mt-3 space-y-2">
                {section.rows.map((row) => (
                  <div key={row.label} className="flex items-start justify-between gap-3 text-xs">
                    <span className="font-semibold text-slate-500">{row.label}</span>
                    <span dir="ltr" className="text-end font-extrabold text-slate-800">{row.value}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </details>
    </div>
  );
}

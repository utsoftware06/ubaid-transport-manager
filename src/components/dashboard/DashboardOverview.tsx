"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowUpRight,
  BarChart3,
  PackageOpen,
  ReceiptText,
  Truck,
  UsersRound,
} from "lucide-react";
import DashboardCards from "@/components/dashboard/DashboardCards";
import DashboardHero from "@/components/dashboard/DashboardHero";
import RecentTrips from "@/components/dashboard/RecentTrips";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";

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

export default function DashboardOverview() {
  const { t, dir } = useLanguage();
  const [recentEntries, setRecentEntries] = useState<DashboardRecentEntry[]>([]);
  const [vehicleCount, setVehicleCount] = useState<number | null>(null);
  const [partyCount, setPartyCount] = useState<number | null>(null);
  const [countsLoading, setCountsLoading] = useState(true);
  const [recentEntriesLoading, setRecentEntriesLoading] = useState(true);
  const [recentEntriesError, setRecentEntriesError] = useState("");
  const [profileRole, setProfileRole] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

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
  }, [loadCurrentContext, loadRecentEntries, loadTenantCounts, t]);

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
        loading={isLoading}
        vehicleCount={vehicleCount}
        partyCount={partyCount}
        countsLoading={countsLoading}
      />
      <RecentTrips
        entries={recentEntries}
        loading={recentEntriesLoading}
        errorMessage={recentEntriesError}
      />
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
    </div>
  );
}

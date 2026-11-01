"use client";

import { useEffect, useMemo, useState } from "react";
import LoadingHeader from "@/components/loadingDetails/LoadingHeader";
import LoadingInfoCard from "@/components/loadingDetails/LoadingInfoCard";
import LoadingItemsTable from "@/components/loadingDetails/LoadingItemsTable";
import ExpenseBreakdown from "@/components/loadingDetails/ExpenseBreakdown";
import LoadingSummary from "@/components/loadingDetails/LoadingSummary";
import LoadingPrint from "@/components/loadingDetails/LoadingPrint";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";

type Props = {
  loadingId: string;
};

type RelatedRecord<T> = T | T[] | null;

type VehicleRelation = {
  vehicle_no: string | null;
  owner_name: string | null;
};

type DriverRelation = {
  name: string | null;
};

type BookingRelation = {
  freight: number | string | null;
  sender_name: string | null;
  adda_id: string | null;
  parties: RelatedRecord<{ name: string | null }>;
};

type LoadingItemRelation = {
  id: string | number;
  item_name: string | null;
  quantity: number | string | null;
  weight: number | string | null;
  unit: string | null;
  remarks: string | null;
};

type ExpenseItemRelation = {
  id: string | number;
  expense_type?: string | null;
  amount: number | string | null;
  remarks?: string | null;
};

type ExpenseRelation = {
  id: string | number;
  expense_items: ExpenseItemRelation[] | null;
};

type LoadingRelationRecord = {
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
  loading_items: LoadingItemRelation[] | null;
  expenses: ExpenseRelation[] | null;
};

export type LoadingGoodsItem = {
  id: string;
  itemName: string;
  quantity: number;
  weight: number;
  unit: string;
  remarks: string;
};

export type LoadingExpenseItem = {
  id: string;
  expenseName: string;
  amount: number;
  remarks: string;
};

export type LoadingDetailsData = {
  id: string;
  addaId: string | null;
  loadingNo: string;
  loadingDate: string;
  vehicleNo: string;
  ownerName: string;
  driverName: string;
  partyName: string;
  route: string;
  freight: number;
  totalIncome: number;
  totalExpense: number;
  netProfit: number;
  items: LoadingGoodsItem[];
  expenses: LoadingExpenseItem[];
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

export default function LoadingDetails({ loadingId }: Props) {
  const { t, dir } = useLanguage();
  const [loading, setLoading] = useState<LoadingRelationRecord | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    async function loadLoadingDetails() {
      if (!loadingId) {
        setLoading(null);
        setErrorMessage(t("loadings.details.idRequired"));
        setIsLoading(false);
        return;
      }

      setIsLoading(true);
      setErrorMessage("");

      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        console.error("Unable to verify loading details user:", authError);
        setErrorMessage(t("loadings.details.loadErrorHint"));
        setIsLoading(false);
        return;
      }
      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("adda_id")
        .eq("id", authData.user.id)
        .maybeSingle();
      if (profileError || !profile?.adda_id) {
        console.error("Unable to resolve loading details tenant:", profileError);
        setErrorMessage(t("loadings.details.loadErrorHint"));
        setIsLoading(false);
        return;
      }

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
          bookings!inner(freight, sender_name, adda_id, parties(name)),
          loading_items(
            id,
            item_name,
            quantity,
            weight,
            unit,
            remarks
          ),
          expenses(
            id,
            expense_items(
              id,
              expense_type,
              amount,
              remarks
            )
          )
        `
        )
        .eq("id", loadingId)
        .eq("bookings.adda_id", profile.adda_id)
        .single();

      if (error) {
        console.error("Unable to load loading details:", error);
        setLoading(null);
        setErrorMessage(t("loadings.details.loadErrorHint"));
        setIsLoading(false);
        return;
      }

      setLoading(data as LoadingRelationRecord);
      setIsLoading(false);
    }

    void loadLoadingDetails();
  }, [loadingId, t]);

  const loadingDetails = useMemo<LoadingDetailsData | null>(() => {
    if (!loading) return null;

    const vehicle = getSingleRelation(loading.vehicles);
    const driver = getSingleRelation(loading.drivers);
    const booking = getSingleRelation(loading.bookings);

    const items = (loading.loading_items ?? []).map((item) => ({
      id: String(item.id),
      itemName: item.item_name?.trim() || "-",
      quantity: toNumber(item.quantity),
      weight: toNumber(item.weight),
      unit: item.unit?.trim() || "-",
      remarks: item.remarks?.trim() || "-",
    }));

    const expenses = (loading.expenses ?? []).flatMap((expense) =>
      (expense.expense_items ?? []).map((item) => ({
        id: String(item.id),
        expenseName:
          item.expense_type?.trim() || t("loadings.details.genericExpense"),
        amount: toNumber(item.amount),
        remarks: item.remarks?.trim() || "-",
      }))
    );

    const freight = toNumber(booking?.freight);
    const totalExpense = expenses.reduce(
      (total, item) => total + item.amount,
      0
    );
    const netProfit = freight - totalExpense;

    return {
      id: loading.id,
      addaId: booking?.adda_id ?? null,
      loadingNo: loading.loading_no ?? "-",
      loadingDate: loading.loading_date?.slice(0, 10) ?? "-",
      vehicleNo: vehicle?.vehicle_no ?? "-",
      ownerName: vehicle?.owner_name ?? "-",
      driverName: driver?.name ?? "-",
      partyName:
        getSingleRelation(booking?.parties ?? null)?.name ??
        booking?.sender_name ??
        "-",
      route: loading.route ?? "-",
      freight,
      totalIncome: freight,
      totalExpense,
      netProfit,
      items,
      expenses,
    };
  }, [loading, t]);

  if (isLoading) {
    return (
      <div dir={dir} className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
        <div className="text-lg font-bold text-gray-900">
          {t("loadings.details.loading")}
        </div>
        <p className="mt-2 text-sm font-medium text-gray-900">
          {t("loadings.details.loadingHint")}
        </p>
      </div>
    );
  }

  if (errorMessage) {
    return (
      <div dir={dir} className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
        <div className="text-lg font-bold text-red-600">
          {t("loadings.details.loadError")}
        </div>
        <p className="mt-2 text-sm font-medium text-gray-900">
          {errorMessage}
        </p>
      </div>
    );
  }

  if (!loadingDetails) {
    return (
      <div dir={dir} className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
        <div className="text-lg font-bold text-gray-900">
          {t("loadings.details.notFound")}
        </div>
        <p className="mt-2 text-sm font-medium text-gray-900">
          {t("loadings.details.notFoundHint")}
        </p>
      </div>
    );
  }

  return (
    <div dir={dir} className="space-y-5">
      <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <LoadingHeader loading={loadingDetails} />

          <LoadingPrint
            loading={loadingDetails}
            expenses={loadingDetails.expenses}
            totalIncome={loadingDetails.totalIncome}
            totalExpense={loadingDetails.totalExpense}
            netProfit={loadingDetails.netProfit}
          />
        </div>
      </div>

      <LoadingInfoCard loading={loadingDetails} />

      <LoadingItemsTable items={loadingDetails.items} />

      <ExpenseBreakdown
        expenses={loadingDetails.expenses}
        totalExpense={loadingDetails.totalExpense}
      />

      <LoadingSummary
        totalIncome={loadingDetails.totalIncome}
        totalExpense={loadingDetails.totalExpense}
        netProfit={loadingDetails.netProfit}
      />
    </div>
  );
}

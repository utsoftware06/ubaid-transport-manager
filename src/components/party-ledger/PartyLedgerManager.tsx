"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import PartyLedgerCards from "./PartyLedgerCards";
import PartyLedgerFilters from "./PartyLedgerFilters";
import PartyLedgerPrint from "./PartyLedgerPrint";
import PartyLedgerTable from "./PartyLedgerTable";
import PartyTripsModal from "./PartyTripsModal";
import type {
  PartyLedgerAdda,
  PartyLedgerFilters as FilterValues,
  PartyLedgerOption,
  PartyLedgerReport,
  PartyLedgerSummary,
  PartyPaymentStatus,
  PartyTripRow,
} from "./types";

type RelatedRecord<T> = T | T[] | null;

type ProfileRow = {
  role: string | null;
  adda_id: string | null;
  is_active: boolean | null;
};

type PartyRelation = {
  id: string;
  name: string | null;
  adda_id: string | null;
};

type BookingRow = {
  id: string;
  adda_id: string | null;
  party_id: string | null;
  booking_no: string | null;
  booking_date: string | null;
  freight: number | string | null;
  advance_bilty: number | string | null;
  parties: RelatedRecord<PartyRelation>;
};

type VehicleRelation = {
  vehicle_no: string | null;
};

type DriverRelation = {
  name: string | null;
};

type LoadingRow = {
  id: string | number;
  loading_no: string | null;
  loading_date: string | null;
  booking_id: string | null;
  route: string | null;
  vehicles: RelatedRecord<VehicleRelation>;
  drivers: RelatedRecord<DriverRelation>;
};

type BiltyPaymentRow = {
  bilty_id: string | null;
  amount: number | string | null;
};

const emptyFilters: FilterValues = {
  addaId: "",
  partyId: "",
  period: "all",
  fromDate: "",
  toDate: "",
  search: "",
  paymentStatus: "all",
};

function singleRelation<T>(relation: RelatedRecord<T> | undefined): T | null {
  return Array.isArray(relation) ? relation[0] ?? null : relation ?? null;
}

function toNumber(value: number | string | null | undefined): number {
  const number = Number(value ?? 0);
  return Number.isFinite(number) ? number : 0;
}

function paymentStatus(received: number, remaining: number): PartyPaymentStatus {
  if (received <= 0) return "unpaid";
  if (remaining <= 0) return "paid";
  return "partial";
}

function dateMatches(dateValue: string, filters: FilterValues): boolean {
  if (!dateValue) return false;
  if (filters.period === "all") return true;

  const date = new Date(`${dateValue.slice(0, 10)}T00:00:00`);
  if (Number.isNaN(date.getTime())) return false;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  let from: Date | null = null;
  let to: Date | null = today;

  if (filters.period === "today") from = new Date(today);
  if (filters.period === "last7Days") {
    from = new Date(today);
    from.setDate(today.getDate() - 6);
  }
  if (filters.period === "thisMonth") {
    from = new Date(today.getFullYear(), today.getMonth(), 1);
  }
  if (filters.period === "last6Months") {
    from = new Date(today);
    from.setMonth(today.getMonth() - 6);
  }
  if (filters.period === "thisYear") {
    from = new Date(today.getFullYear(), 0, 1);
  }
  if (filters.period === "custom") {
    from = filters.fromDate
      ? new Date(`${filters.fromDate}T00:00:00`)
      : null;
    to = filters.toDate ? new Date(`${filters.toDate}T00:00:00`) : null;
  }

  return (!from || date >= from) && (!to || date <= to);
}

export default function PartyLedgerManager() {
  const { t, dir } = useLanguage();
  const [allTrips, setAllTrips] = useState<PartyTripRow[]>([]);
  const [addas, setAddas] = useState<PartyLedgerAdda[]>([]);
  const [parties, setParties] = useState<PartyLedgerOption[]>([]);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [assignedAddaId, setAssignedAddaId] = useState<string | null>(null);
  const [filters, setFilters] = useState<FilterValues>(emptyFilters);
  const [selectedPartyId, setSelectedPartyId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  const loadLedger = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage("");
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        throw authError ?? new Error("Party Ledger user is unavailable");
      }

      const { data: profileData, error: profileError } = await supabase
        .from("profiles")
        .select("role, adda_id, is_active")
        .eq("id", authData.user.id)
        .single();
      if (profileError) throw profileError;
      const profile = profileData as ProfileRow;
      const superAdmin =
        profile.is_active === true && profile.role === USER_ROLES.superAdmin;
      const addaAdmin =
        profile.is_active === true && profile.role === USER_ROLES.addaAdmin;
      if (!superAdmin && (!addaAdmin || !profile.adda_id)) {
        throw new Error("Party Ledger access is unavailable");
      }

      setIsSuperAdmin(superAdmin);
      setAssignedAddaId(profile.adda_id);
      if (!superAdmin && profile.adda_id) {
        setFilters((current) => ({ ...current, addaId: profile.adda_id ?? "" }));
      }

      let bookingQuery = supabase
        .from("bookings")
        .select(
          "id, adda_id, party_id, booking_no, booking_date, freight, advance_bilty, parties!inner(id, name, adda_id)"
        )
        .not("party_id", "is", null);
      if (!superAdmin && profile.adda_id) {
        bookingQuery = bookingQuery.eq("adda_id", profile.adda_id);
      }

      const [addaResult, bookingResult] = await Promise.all([
        supabase.from("addas").select("id, name").order("name"),
        bookingQuery,
      ]);
      if (addaResult.error) throw addaResult.error;
      if (bookingResult.error) throw bookingResult.error;

      const addaRows = (addaResult.data ?? []).map((adda) => ({
        id: String(adda.id),
        name: String(adda.name ?? "-"),
      }));
      setAddas(addaRows);
      const addaNameMap = new Map(addaRows.map((adda) => [adda.id, adda.name]));

      const bookings = (bookingResult.data ?? []) as BookingRow[];
      const validBookings = bookings.filter((booking) => {
        const party = singleRelation(booking.parties);
        const isValid =
          Boolean(booking.party_id) &&
          Boolean(booking.adda_id) &&
          party?.id === booking.party_id &&
          party.adda_id === booking.adda_id;
        if (!isValid) {
          console.error("Party Ledger ignored a cross-Adda or invalid Booking Party relation.");
        }
        return isValid;
      });
      const bookingIds = validBookings.map((booking) => booking.id);
      if (bookingIds.length === 0) {
        setParties([]);
        setAllTrips([]);
        return;
      }

      const { data: loadingData, error: loadingError } = await supabase
        .from("loadings")
        .select(
          "id, loading_no, loading_date, booking_id, route, vehicles(vehicle_no), drivers(name)"
        )
        .in("booking_id", bookingIds)
        .order("loading_date", { ascending: false });
      if (loadingError) throw loadingError;
      const loadings = (loadingData ?? []) as LoadingRow[];

      let biltyPayments: BiltyPaymentRow[] = [];
      if (bookingIds.length > 0) {
        const { data: paymentData, error: paymentError } = await supabase
          .from("bilty_payments")
          .select("bilty_id, amount")
          .in("bilty_id", bookingIds)
          .eq("payment_side", "party_broker");
        if (paymentError) throw paymentError;
        biltyPayments = (paymentData ?? []) as BiltyPaymentRow[];
      }

      const laterReceivedByBooking = new Map<string, number>();
      biltyPayments.forEach((payment) => {
        if (payment.bilty_id === null) return;
        const bookingId = String(payment.bilty_id);
        laterReceivedByBooking.set(
          bookingId,
          (laterReceivedByBooking.get(bookingId) ?? 0) + toNumber(payment.amount)
        );
      });

      const bookingMap = new Map(
        validBookings.map((booking) => [booking.id, booking])
      );
      const tripRows = loadings.flatMap<PartyTripRow>((loading) => {
        const booking = loading.booking_id
          ? bookingMap.get(loading.booking_id)
          : null;
        if (!booking?.party_id || !booking.adda_id) return [];
        const party = singleRelation(booking.parties);
        if (!party) return [];
        const vehicle = singleRelation(loading.vehicles);
        const driver = singleRelation(loading.drivers);
        const advance = toNumber(booking.advance_bilty);
        const receiptPayments = laterReceivedByBooking.get(booking.id) ?? 0;
        const totalReceived = advance + receiptPayments;
        const freight = toNumber(booking.freight);
        const remaining = Math.max(freight - totalReceived, 0);

        return [{
          id: String(loading.id),
          partyId: party.id,
          partyName: party.name?.trim() || t("partyLedger.states.unknownParty"),
          addaId: booking.adda_id,
          addaName:
            addaNameMap.get(booking.adda_id) ??
            t("partyLedger.states.unknownAdda"),
          loadingId: String(loading.id),
          loadingNo: loading.loading_no ?? "-",
          loadingDate: loading.loading_date?.slice(0, 10) ?? "",
          bookingId: booking.id,
          bookingNo: booking.booking_no ?? "-",
          route: loading.route ?? "-",
          vehicleNo: vehicle?.vehicle_no ?? "-",
          driverName: driver?.name ?? "-",
          freight,
          advance,
          receiptPayments,
          totalReceived,
          remaining,
          paymentStatus: paymentStatus(totalReceived, remaining),
        }];
      });

      const partyMap = new Map<string, PartyLedgerOption>();
      tripRows.forEach((trip) => {
        partyMap.set(trip.partyId, {
          id: trip.partyId,
          name: trip.partyName,
          addaId: trip.addaId,
        });
      });
      setParties(
        Array.from(partyMap.values()).sort((first, second) =>
          first.name.localeCompare(second.name)
        )
      );
      setAllTrips(tripRows);
    } catch (error) {
      console.error("Unable to load Party Ledger:", error);
      setAllTrips([]);
      setParties([]);
      setErrorMessage(t("partyLedger.messages.loadFailed"));
    } finally {
      setIsLoading(false);
    }
  }, [t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadLedger(), 0);
    return () => window.clearTimeout(timer);
  }, [loadLedger]);

  const invalidDateRange =
    filters.period === "custom" &&
    Boolean(filters.fromDate) &&
    Boolean(filters.toDate) &&
    filters.fromDate > filters.toDate;

  const filteredTrips = useMemo(() => {
    if (invalidDateRange) return [];
    const keyword = filters.search.trim().toLocaleLowerCase();
    return allTrips.filter((trip) => {
      if (filters.addaId && trip.addaId !== filters.addaId) return false;
      if (filters.partyId && trip.partyId !== filters.partyId) return false;
      if (
        filters.paymentStatus !== "all" &&
        trip.paymentStatus !== filters.paymentStatus
      ) return false;
      if (!dateMatches(trip.loadingDate, filters)) return false;
      if (!keyword) return true;
      return [
        trip.partyName,
        trip.addaName,
        trip.loadingNo,
        trip.bookingNo,
        trip.route,
        trip.vehicleNo,
        trip.driverName,
        String(trip.freight),
        String(trip.totalReceived),
        String(trip.remaining),
      ]
        .join(" ")
        .toLocaleLowerCase()
        .includes(keyword);
    });
  }, [allTrips, filters, invalidDateRange]);

  const reports = useMemo<PartyLedgerReport[]>(() => {
    const reportMap = new Map<
      string,
      { report: PartyLedgerReport; bookingIds: Set<string> }
    >();

    filteredTrips.forEach((trip) => {
      const existing = reportMap.get(trip.partyId);
      if (!existing) {
        reportMap.set(trip.partyId, {
          bookingIds: new Set([trip.bookingId]),
          report: {
            partyId: trip.partyId,
            partyName: trip.partyName,
            addaId: trip.addaId,
            addaName: trip.addaName,
            totalBookings: 1,
            totalTrips: 1,
            totalFreight: trip.freight,
            totalAdvance: trip.advance,
            totalReceiptPayments: trip.receiptPayments,
            totalReceived: trip.totalReceived,
            remainingBalance: 0,
            paymentStatus: "unpaid",
            trips: [trip],
          },
        });
        return;
      }

      existing.report.totalTrips += 1;
      existing.report.totalAdvance += trip.advance;
      existing.report.totalReceiptPayments += trip.receiptPayments;
      existing.report.totalReceived += trip.totalReceived;
      existing.report.trips.push(trip);
      if (!existing.bookingIds.has(trip.bookingId)) {
        existing.bookingIds.add(trip.bookingId);
        existing.report.totalBookings += 1;
        existing.report.totalFreight += trip.freight;
      }
    });

    return Array.from(reportMap.values())
      .map(({ report }) => {
        const remainingBalance = Math.max(
          report.totalFreight - report.totalReceived,
          0
        );
        return {
          ...report,
          remainingBalance,
          paymentStatus: paymentStatus(
            report.totalReceived,
            remainingBalance
          ),
        };
      })
      .sort((first, second) => first.partyName.localeCompare(second.partyName));
  }, [filteredTrips]);

  const summary = useMemo<PartyLedgerSummary>(
    () =>
      reports.reduce(
        (total, report) => ({
          totalParties: total.totalParties + 1,
          totalTrips: total.totalTrips + report.totalTrips,
          totalFreight: total.totalFreight + report.totalFreight,
          totalReceived: total.totalReceived + report.totalReceived,
          totalRemaining: total.totalRemaining + report.remainingBalance,
          paidParties:
            total.paidParties + (report.paymentStatus === "paid" ? 1 : 0),
          partialParties:
            total.partialParties +
            (report.paymentStatus === "partial" ? 1 : 0),
          unpaidParties:
            total.unpaidParties + (report.paymentStatus === "unpaid" ? 1 : 0),
        }),
        {
          totalParties: 0,
          totalTrips: 0,
          totalFreight: 0,
          totalReceived: 0,
          totalRemaining: 0,
          paidParties: 0,
          partialParties: 0,
          unpaidParties: 0,
        }
      ),
    [reports]
  );

  const dateRange = useMemo(() => {
    if (filters.period === "custom") {
      return `${filters.fromDate || t("common.dateFilters.allTime")} — ${
        filters.toDate || t("common.dateFilters.allTime")
      }`;
    }
    if (filters.period === "all") {
      return t("common.dateFilters.allTime");
    }
    return t(`common.dateFilters.${filters.period}`);
  }, [filters.fromDate, filters.period, filters.toDate, t]);

  const selectedReport =
    reports.find((report) => report.partyId === selectedPartyId) ?? null;

  function resetFilters() {
    setFilters({
      ...emptyFilters,
      addaId: isSuperAdmin ? "" : assignedAddaId ?? "",
    });
  }

  return (
    <main dir={dir} className="ut-module-page mx-auto max-w-[1600px] space-y-6 text-slate-900">
      <header className="flex flex-col justify-between gap-4 rounded-xl border border-slate-200 bg-white p-6 shadow-sm sm:flex-row sm:items-center">
        <ModulePageHeading icon="ledger" accent="purple" title={t("partyLedger.title")} description={t("partyLedger.description")} />
        <PartyLedgerPrint reports={reports} summary={summary} dateRange={dateRange} period={{ period: filters.period, fromDate: filters.fromDate, toDate: filters.toDate }} />
      </header>

      <PartyLedgerCards summary={summary} />
      <PartyLedgerFilters
        filters={filters}
        addas={addas}
        parties={parties}
        showAddaFilter={isSuperAdmin}
        invalidDateRange={invalidDateRange}
        onChange={setFilters}
        onReset={resetFilters}
      />
      <PartyLedgerTable
        key={[
          filters.addaId,
          filters.partyId,
          filters.period,
          filters.fromDate,
          filters.toDate,
          filters.search,
          filters.paymentStatus,
        ].join("|")}
        reports={reports}
        isLoading={isLoading}
        errorMessage={errorMessage}
        onViewTrips={(report) => setSelectedPartyId(report.partyId)}
        dateRange={dateRange}
        period={{ period: filters.period, fromDate: filters.fromDate, toDate: filters.toDate }}
      />

      {selectedReport && (
        <PartyTripsModal
          report={selectedReport}
          dateRange={dateRange}
          period={{ period: filters.period, fromDate: filters.fromDate, toDate: filters.toDate }}
          onClose={() => setSelectedPartyId(null)}
        />
      )}
    </main>
  );
}

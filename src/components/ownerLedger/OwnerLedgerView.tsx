"use client";

import { useMemo, useState } from "react";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { useLanguage } from "@/contexts/LanguageContext";
import type { VehicleTrip } from "@/components/vehicleLedger/VehicleLedger";
import { buildVehicleReports, isVehicleTripDateInRange, matchesBiltyVoucherNumber, summarizeVehicleTrips } from "@/components/vehicleLedger/reporting";
import OwnerLedgerCards from "@/components/ownerLedger/OwnerLedgerCards";
import OwnerLedgerFilters from "@/components/ownerLedger/OwnerLedgerFilters";
import OwnerLedgerTable from "@/components/ownerLedger/OwnerLedgerTable";
import OwnerTripsModal from "@/components/ownerLedger/OwnerTripsModal";
import OwnerPrint from "@/components/ownerLedger/OwnerPrint";
import type { OwnerLedgerFilterValues, OwnerLedgerSummary, OwnerReport, OwnerVehicleOption } from "@/components/ownerLedger/types";

type Props = { trips: VehicleTrip[]; isLoading: boolean };

function getOwnerDisplayName(trip: VehicleTrip, withoutOwnerLabel: string) {
  const ownerName = trip.ownerName.trim();
  return ownerName && ownerName !== "—" ? ownerName : withoutOwnerLabel;
}

export default function OwnerLedgerView({ trips, isLoading }: Props) {
  const { t, dir } = useLanguage();
  const [filters, setFilters] = useState<OwnerLedgerFilterValues>({
    ownerName: "",
    vehicleId: "",
    filterType: "all",
    fromDate: "",
    toDate: "",
    search: "",
    paymentStatus: "",
    biltyVoucherNo: "",
  });
  const [selectedOwnerName, setSelectedOwnerName] = useState<string | null>(null);
  const hasInvalidDateRange = filters.filterType === "custom"
    && Boolean(filters.fromDate)
    && Boolean(filters.toDate)
    && filters.fromDate > filters.toDate;

  const withoutOwnerLabel = t("ownerLedger.withoutOwner");
  const ownerOptions = useMemo(() => Array.from(new Set(trips.map((trip) => getOwnerDisplayName(trip, withoutOwnerLabel)))).sort((left, right) => left.localeCompare(right)), [trips, withoutOwnerLabel]);
  const vehicleOptions = useMemo<OwnerVehicleOption[]>(() => {
    const byId = new Map<string, OwnerVehicleOption>();
    for (const trip of trips) {
      if (!trip.vehicleId || byId.has(trip.vehicleId)) continue;
      byId.set(trip.vehicleId, { id: trip.vehicleId, vehicleNo: trip.vehicleNo });
    }
    return Array.from(byId.values()).sort((left, right) => left.vehicleNo.localeCompare(right.vehicleNo));
  }, [trips]);
  const paymentStatuses = useMemo(() => Array.from(new Set(trips.map((trip) => trip.paymentStatus))).sort(), [trips]);

  const filteredTrips = useMemo(() => {
    if (hasInvalidDateRange) return [];
    const ownerFilter = filters.ownerName.trim().toLowerCase();
    const vehicleFilter = filters.vehicleId;
    const search = filters.search.trim().toLowerCase();
    return trips.filter((trip) => {
      const ownerName = getOwnerDisplayName(trip, withoutOwnerLabel);
      if (!isVehicleTripDateInRange(trip.date, filters)) return false;
      if (ownerFilter && ownerName.toLowerCase() !== ownerFilter) return false;
      if (vehicleFilter && trip.vehicleId !== vehicleFilter) return false;
      if (filters.paymentStatus && trip.paymentStatus !== filters.paymentStatus) return false;
      if (filters.biltyVoucherNo.trim() && !matchesBiltyVoucherNumber(trip, filters.biltyVoucherNo)) return false;
      if (!search) return true;
      const searchable = [ownerName, trip.vehicleNo, trip.loadingNo, trip.biltyNo, ...trip.biltyNumbers,
        trip.voucherNo, trip.date, trip.tripType, trip.driverName, trip.route, trip.loadedThrough,
        trip.collectFrom, ...trip.expenseItems.flatMap((item) => [item.category, item.source])]
        .join(" ").toLowerCase();
      return searchable.includes(search);
    });
  }, [filters, hasInvalidDateRange, trips, withoutOwnerLabel]);

  const reports = useMemo<OwnerReport[]>(() => {
    const tripsByOwner = new Map<string, VehicleTrip[]>();
    for (const trip of filteredTrips) {
      const ownerName = getOwnerDisplayName(trip, withoutOwnerLabel);
      const rows = tripsByOwner.get(ownerName) ?? [];
      rows.push(trip);
      tripsByOwner.set(ownerName, rows);
    }
    return Array.from(tripsByOwner, ([ownerName, ownerTrips]) => {
      const totals = summarizeVehicleTrips(ownerTrips);
      const { totalExpense, ...vehicleTotals } = totals;
      return {
        ownerName,
        totalVehicles: new Set(ownerTrips.map((trip) => trip.vehicleId).filter(Boolean)).size,
        ...vehicleTotals,
        totalExpenses: totalExpense,
        vehicles: buildVehicleReports(ownerTrips),
        trips: [...ownerTrips].sort((left, right) => right.date.localeCompare(left.date) || left.id.localeCompare(right.id)),
      };
    }).sort((left, right) => left.ownerName.localeCompare(right.ownerName));
  }, [filteredTrips, withoutOwnerLabel]);

  const summary = useMemo<OwnerLedgerSummary>(() => reports.reduce((total, report) => ({
    totalOwners: total.totalOwners + 1,
    totalVehicles: total.totalVehicles + report.totalVehicles,
    totalTrips: total.totalTrips + report.totalTrips,
    totalVehicleFreight: total.totalVehicleFreight + report.totalVehicleFreight,
    totalReceived: total.totalReceived + report.totalReceived,
    totalParchiVehicleWithheld: total.totalParchiVehicleWithheld + report.totalParchiVehicleWithheld,
    totalVehicleEntitlementSettled: total.totalVehicleEntitlementSettled + report.totalVehicleEntitlementSettled,
    totalOutstanding: total.totalOutstanding + report.totalOutstanding,
    totalExpenses: total.totalExpenses + report.totalExpenses,
    netVehicleEarnings: total.netVehicleEarnings + report.netVehicleEarnings,
  }), {
    totalOwners: 0,
    totalVehicles: 0,
    totalTrips: 0,
    totalVehicleFreight: 0,
    totalReceived: 0,
    totalParchiVehicleWithheld: 0,
    totalVehicleEntitlementSettled: 0,
    totalOutstanding: 0,
    totalExpenses: 0,
    netVehicleEarnings: 0,
  }), [reports]);

  const selectedOwnerReport = reports.find((report) => report.ownerName === selectedOwnerName) ?? null;
  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="ledger" accent="purple" title={t("ownerLedger.title")} description={t("ownerLedger.pageDescription")} />
      </header>
      {isLoading ? <div className="rounded-xl bg-white p-8 text-center font-semibold text-gray-700">{t("ownerLedger.loading")}</div> : <>
        <OwnerLedgerCards summary={summary} />
        <OwnerLedgerFilters filters={filters} setFilters={setFilters} ownerOptions={ownerOptions} vehicleOptions={vehicleOptions} paymentStatuses={paymentStatuses} />
        {hasInvalidDateRange && <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">{t("reports.validation.invalidDateRange")}</div>}
        <div className="flex justify-end"><OwnerPrint reports={reports} summary={summary} period={{ filterType: filters.filterType, fromDate: filters.fromDate, toDate: filters.toDate }} /></div>
        <OwnerLedgerTable key={JSON.stringify(filters)} reports={reports} onViewTrips={(report) => setSelectedOwnerName(report.ownerName)} />
      </>}
      {selectedOwnerReport && <OwnerTripsModal ownerReport={selectedOwnerReport} period={{ filterType: filters.filterType, fromDate: filters.fromDate, toDate: filters.toDate }} onClose={() => setSelectedOwnerName(null)} />}
    </div>
  );
}

import type { PrintLanguage } from "@/lib/print/types";
import { translateLedgerPrint, type LedgerPrintPresentation, type LedgerPrintTable } from "@/components/print/LedgerStatementPrint";
import { formatAmount } from "./reporting";
import type { VehicleFilterType, VehicleReport, VehicleTrip } from "./VehicleLedger";

function optionalAmount(value: number | null) { return value === null ? "—" : formatAmount(value); }

export function vehicleLedgerPrintPresentation(report: VehicleReport, language: PrintLanguage, period?: { filterType: VehicleFilterType; fromDate: string; toDate: string }): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  const periodLabel = period
    ? period.filterType === "custom"
      ? `${period.fromDate || tr("common.dateFilters.allTime")} — ${period.toDate || tr("common.dateFilters.allTime")}`
      : tr(`vehicleLedger.filters.${period.filterType === "all" ? "allTime" : period.filterType === "week" ? "last7Days" : period.filterType === "month" ? "thisMonth" : period.filterType === "sixMonths" ? "last6Months" : period.filterType === "year" ? "thisYear" : period.filterType}`)
    : null;
  const legs: LedgerPrintTable = {
    title: tr("vehicleLedger.fields.sideTripType"),
    columns: [tr("vehicleLedger.fields.biltyNo"), tr("vehicleLedger.fields.sideTripType"), tr("common.date"), tr("common.route"), tr("common.driver"), tr("vehicleLedger.fields.rawVehicleFreight"), tr("vehicleLedger.fields.brokerCommission"), tr("vehicleLedger.fields.overweightCharges"), tr("vehicleLedger.fields.loloCharges"), tr("vehicleLedger.fields.detainCharges"), tr("vehicleLedger.fields.adjustedVehicleFreight"), tr("vehicleLedger.fields.advanceVehicle"), tr("vehicleLedger.fields.laterVehiclePayments"), tr("vehicleLedger.fields.totalVehiclePaid"), tr("vehicleLedger.fields.parchiWithheldCommission"), tr("vehicleLedger.fields.vehicleEntitlementSettled"), tr("vehicleLedger.fields.vehicleBalance"), tr("vehicleLedger.fields.paymentStatus")],
    rows: report.trips.flatMap((trip) => (trip.freightLegs ?? []).map((leg) => [leg.biltyNo || "—", leg.side || "—", leg.bookingDate || "—", leg.route || "—", leg.loadingDrivers.length ? leg.loadingDrivers.map((assignment) => `${assignment.loadingId}: ${assignment.driverName || tr("driverLedger.notRecorded")}`).join(" · ") : leg.driverName || tr("driverLedger.notRecorded"), formatAmount(leg.rawVehicleFreight), formatAmount(leg.brokerCommission), formatAmount(leg.overweightCharges), formatAmount(leg.loloCharges), formatAmount(leg.detainCharges), formatAmount(leg.adjustedVehicleFreight), formatAmount(leg.advanceVehicle), formatAmount(leg.laterVehiclePayments), formatAmount(leg.totalVehiclePaid), formatAmount(leg.parchiVehicleWithheld), formatAmount(leg.totalVehicleEntitlementSettled), formatAmount(leg.balance), tr(`vehicleLedger.filters.status.${leg.paymentStatus.toLowerCase()}`)])),
  };
  const trips: LedgerPrintTable = {
    title: tr("vehicleLedger.title"),
    columns: [tr("common.date"), tr("vehicleLedger.fields.voucherNo"), tr("vehicleLedger.fields.tripType"), tr("common.route"), tr("common.driver"), tr("vehicleLedger.fields.manualFreight"), tr("vehicleLedger.fields.advanceVehicle"), tr("vehicleLedger.fields.laterVehiclePayments"), tr("vehicleLedger.fields.totalVehiclePaid"), tr("vehicleLedger.fields.parchiWithheldCommission"), tr("vehicleLedger.fields.vehicleEntitlementSettled"), tr("vehicleLedger.fields.vehicleBalance"), tr("vehicleLedger.fields.totalTripExpenses"), tr("vehicleLedger.fields.netVehicleEarnings"), tr("vehicleLedger.fields.paymentStatus")],
    rows: report.trips.map((trip) => [trip.date || "—", trip.sourceType === "manual" ? trip.voucherNo || "—" : trip.biltyNo || "—", trip.tripType || "—", trip.route || "—", trip.driverName || tr("driverLedger.notRecorded"), formatAmount(trip.income), optionalAmount(trip.advanceVehicle), optionalAmount(trip.laterVehiclePayments), optionalAmount(trip.totalVehiclePaid), formatAmount(trip.parchiVehicleWithheld), optionalAmount(trip.totalVehicleEntitlementSettled), optionalAmount(trip.vehicleBalance), formatAmount(trip.totalExpense), formatAmount(trip.profit), tr(trip.paymentStatus === "Not tracked" ? "vehicleLedger.fields.notTracked" : `vehicleLedger.filters.status.${trip.paymentStatus.toLowerCase()}`)]),
  };
  const expenses: LedgerPrintTable = {
    title: tr("vehicleLedger.modal.tripExpenses"),
    columns: [tr("vehicleLedger.fields.voucherNo"), tr("common.date"), tr("vehicleLedger.fields.category"), tr("vehicleLedger.fields.source"), tr("vehicleLedger.fields.amount")],
    rows: report.trips.flatMap((trip: VehicleTrip) => trip.expenseItems.map((item) => [trip.sourceType === "manual" ? trip.voucherNo : trip.biltyNo, trip.date || "—", item.category || "—", item.source || "—", formatAmount(item.amount)])),
    emptyMessage: tr("vehicleLedger.modal.noTripExpenses"),
  };
  return {
    documentType: "vehicle_ledger",
    title: tr("vehicleLedger.title"),
    subtitle: report.ownerName,
    reference: report.vehicleNo,
    fields: [
      { label: tr("common.vehicle"), value: report.vehicleNo },
      ...(report.ownerName && report.ownerName !== "—" ? [{ label: tr("common.owner"), value: report.ownerName }] : []),
      { label: tr("vehicleLedger.cards.totalTrips"), value: String(report.totalTrips), direction: "ltr" },
      ...(periodLabel ? [{ label: tr("common.date"), value: periodLabel }] : []),
    ],
    summary: [
      { label: tr("vehicleLedger.cards.totalVehicleFreight"), value: formatAmount(report.totalVehicleFreight) },
      { label: tr("vehicleLedger.cards.totalReceived"), value: formatAmount(report.totalReceived) },
      { label: tr("vehicleLedger.cards.parchiVehicleWithheld"), value: formatAmount(report.totalParchiVehicleWithheld) },
      { label: tr("vehicleLedger.cards.vehicleEntitlementSettled"), value: formatAmount(report.totalVehicleEntitlementSettled) },
      { label: tr("vehicleLedger.cards.totalOutstanding"), value: formatAmount(report.totalOutstanding) },
      { label: tr("vehicleLedger.cards.totalExpense"), value: formatAmount(report.totalExpense) },
      { label: tr("vehicleLedger.cards.netVehicleEarnings"), value: formatAmount(report.netVehicleEarnings) },
    ],
    tables: [trips, ...(legs.rows.length ? [legs] : []), expenses],
  };
}

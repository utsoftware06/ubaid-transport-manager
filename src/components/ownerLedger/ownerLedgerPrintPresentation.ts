import type { PrintLanguage } from "@/lib/print/types";
import { translateLedgerPrint, type LedgerPrintPresentation, type LedgerPrintTable } from "@/components/print/LedgerStatementPrint";
import { formatAmount } from "@/components/vehicleLedger/reporting";
import type { OwnerLedgerSummary, OwnerReport } from "./types";
import type { VehicleFilterType } from "@/components/vehicleLedger/VehicleLedger";

export function ownerLedgerPrintPresentation(reports: OwnerReport[], summary: OwnerLedgerSummary, language: PrintLanguage, period?: { filterType: VehicleFilterType; fromDate: string; toDate: string }): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  const periodLabel = period
    ? period.filterType === "custom"
      ? `${period.fromDate || tr("common.dateFilters.allTime")} — ${period.toDate || tr("common.dateFilters.allTime")}`
      : tr(`common.dateFilters.${period.filterType === "all" ? "allTime" : period.filterType === "week" ? "last7Days" : period.filterType === "month" ? "thisMonth" : period.filterType === "sixMonths" ? "last6Months" : period.filterType === "year" ? "thisYear" : period.filterType}`)
    : null;
  const tables: LedgerPrintTable[] = [];
  for (const report of reports) {
    tables.push({
      title: `${tr("ownerLedger.title")} · ${report.ownerName}`,
      columns: [tr("common.date"), tr("vehicleLedger.fields.voucherNo"), tr("vehicleLedger.fields.tripType"), tr("common.vehicle"), tr("common.route"), tr("common.driver"), tr("vehicleLedger.fields.manualFreight"), tr("vehicleLedger.fields.advanceVehicle"), tr("vehicleLedger.fields.totalVehiclePaid"), tr("vehicleLedger.fields.parchiWithheldCommission"), tr("vehicleLedger.fields.vehicleEntitlementSettled"), tr("vehicleLedger.fields.vehicleBalance"), tr("vehicleLedger.fields.totalTripExpenses"), tr("vehicleLedger.fields.netVehicleEarnings")],
      rows: report.trips.map((trip) => [trip.date || "—", trip.sourceType === "manual" ? trip.voucherNo || "—" : trip.biltyNo || "—", trip.tripType || "—", trip.vehicleNo || "—", trip.route || "—", trip.driverName || tr("driverLedger.notRecorded"), formatAmount(trip.income), trip.advanceVehicle === null ? "—" : formatAmount(trip.advanceVehicle), trip.totalVehiclePaid === null ? "—" : formatAmount(trip.totalVehiclePaid), formatAmount(trip.parchiVehicleWithheld), trip.totalVehicleEntitlementSettled === null ? tr("vehicleLedger.fields.notTracked") : formatAmount(trip.totalVehicleEntitlementSettled), trip.vehicleBalance === null ? "—" : formatAmount(trip.vehicleBalance), formatAmount(trip.totalExpense), formatAmount(trip.profit)]),
    });
    for (const vehicle of report.vehicles) {
      const legRows = vehicle.trips.flatMap((trip) => (trip.freightLegs ?? []).map((leg) => [
        vehicle.vehicleNo, trip.sourceType === "manual" ? trip.voucherNo : trip.biltyNo, leg.side, leg.biltyNo || "—", leg.route || "—", leg.loadedThrough || "—", leg.collectFrom || "—", formatAmount(leg.rawVehicleFreight), `−${formatAmount(leg.brokerCommission)}`, `+${formatAmount(leg.overweightCharges)}`, `+${formatAmount(leg.loloCharges)}`, `+${formatAmount(leg.detainCharges)}`, formatAmount(leg.adjustedVehicleFreight), formatAmount(leg.advanceVehicle), formatAmount(leg.laterVehiclePayments), formatAmount(leg.totalVehiclePaid), formatAmount(leg.parchiVehicleWithheld), formatAmount(leg.totalVehicleEntitlementSettled), formatAmount(leg.balance), tr(`vehicleLedger.filters.status.${leg.paymentStatus.toLowerCase()}`),
      ]));
      if (legRows.length) tables.push({
        title: `${vehicle.vehicleNo} · ${tr("vehicleLedger.fields.sideTripType")}`,
        columns: [tr("common.vehicle"), tr("vehicleLedger.fields.voucherNo"), tr("vehicleLedger.fields.sideTripType"), tr("vehicleLedger.fields.biltyNo"), tr("common.route"), tr("vehicleLedger.fields.loadedThrough"), tr("vehicleLedger.fields.collectFrom"), tr("vehicleLedger.fields.rawVehicleFreight"), `${tr("vehicleLedger.fields.brokerCommission")} (−)`, `${tr("vehicleLedger.fields.overweightCharges")} (+)`, `${tr("vehicleLedger.fields.loloCharges")} (+)`, `${tr("vehicleLedger.fields.detainCharges")} (+)`, tr("vehicleLedger.fields.adjustedVehicleFreight"), tr("vehicleLedger.fields.advanceVehicle"), tr("vehicleLedger.fields.laterVehiclePayments"), tr("vehicleLedger.fields.totalVehiclePaid"), tr("vehicleLedger.fields.parchiWithheldCommission"), tr("vehicleLedger.fields.vehicleEntitlementSettled"), tr("vehicleLedger.fields.vehicleBalance"), tr("vehicleLedger.fields.paymentStatus")],
        rows: legRows,
      });
    }
  }
  return {
    documentType: "owner_ledger",
    title: tr("ownerLedger.print.reportTitle"),
    fields: [{ label: tr("ownerLedger.summary.totalOwners"), value: String(summary.totalOwners), direction: "ltr" }, { label: tr("ownerLedger.summary.totalVehicles"), value: String(summary.totalVehicles), direction: "ltr" }, { label: tr("ownerLedger.summary.totalTrips"), value: String(summary.totalTrips), direction: "ltr" }, ...(periodLabel ? [{ label: tr("common.date"), value: periodLabel }] : [])],
    summary: [
      { label: tr("ownerLedger.summary.totalVehicleFreight"), value: formatAmount(summary.totalVehicleFreight) },
      { label: tr("ownerLedger.summary.totalReceived"), value: formatAmount(summary.totalReceived) },
      { label: tr("vehicleLedger.cards.parchiVehicleWithheld"), value: formatAmount(summary.totalParchiVehicleWithheld) },
      { label: tr("vehicleLedger.cards.vehicleEntitlementSettled"), value: formatAmount(summary.totalVehicleEntitlementSettled) },
      { label: tr("ownerLedger.summary.totalOutstanding"), value: formatAmount(summary.totalOutstanding) },
      { label: tr("ownerLedger.summary.totalExpense"), value: formatAmount(summary.totalExpenses) },
      { label: tr("ownerLedger.summary.netVehicleEarnings"), value: formatAmount(summary.netVehicleEarnings) },
    ],
    tables,
  };
}

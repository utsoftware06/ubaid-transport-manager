import type { VehicleTrip } from "@/components/vehicleLedger/VehicleLedger";
import type { PrintLanguage } from "@/lib/print/types";
import { translateLedgerPrint, type LedgerPrintPresentation } from "@/components/print/LedgerStatementPrint";
import type { DriverAccountBalance } from "./DriverLedgerView";

const money = (value: number) => `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
export type DriverActivityPrintRow = { trip: VehicleTrip; driverName: string; legLabel: string; salaryEarnings: number; kharcha: number; kharchaStatus: "attributed" | "unallocated" | "none" };
export type DriverAccountPrintRow = { driverName: string; opening: number; earnings: number; payments: number; balance: DriverAccountBalance };
export type DriverAccountEventPrintRow = { date: string; driverName: string; kind: "earning" | "payment"; detail: string; earning: number; payment: number; advance: number };
export type DriverLedgerPrintSummary = { totalDrivers: number; totalChakkars: number; totalLegs: number; driverKharcha: number; salaryEarnings: number; driverPayments: number; driverAccountBalance: number };

export function driverLedgerPrintPresentation(data: { summary: DriverLedgerPrintSummary; activities: DriverActivityPrintRow[]; accounts: DriverAccountPrintRow[]; events: DriverAccountEventPrintRow[]; fromDate: string; toDate: string }, language: PrintLanguage): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  return {
    documentType: "driver_ledger",
    title: tr("driverLedger.title"),
    subtitle: [data.fromDate, data.toDate].filter(Boolean).join(" — "),
    fields: [
      { label: tr("driverLedger.summary.totalDrivers"), value: String(data.summary.totalDrivers), direction: "ltr" },
      { label: tr("driverLedger.summary.totalChakkars"), value: String(data.summary.totalChakkars), direction: "ltr" },
      { label: tr("driverLedger.summary.totalTripLegs"), value: String(data.summary.totalLegs), direction: "ltr" },
      ...(data.fromDate ? [{ label: tr("common.fromDate"), value: data.fromDate, direction: "ltr" as const }] : []),
      ...(data.toDate ? [{ label: tr("common.toDate"), value: data.toDate, direction: "ltr" as const }] : []),
    ],
    summary: [
      { label: tr("driverLedger.summary.driverKharcha"), value: money(data.summary.driverKharcha) },
      { label: tr("driverLedger.summary.salaryEarnings"), value: money(data.summary.salaryEarnings) },
      { label: tr("driverLedger.summary.driverPayments"), value: money(data.summary.driverPayments) },
      { label: tr("driverLedger.summary.driverAccountBalance"), value: money(data.summary.driverAccountBalance) },
    ],
    tables: [
      {
        title: tr("driverLedger.activity.title"),
        columns: [tr("driverLedger.table.date"), tr("driverLedger.table.chakkar"), tr("driverLedger.table.vehicle"), tr("driverLedger.table.tripLeg"), tr("driverLedger.table.route"), tr("driverLedger.table.driver"), tr("driverLedger.table.driverKharcha"), tr("driverLedger.table.salaryEarnings")],
        rows: data.activities.map((row) => [row.trip.date || "—", row.trip.sourceType === "manual" ? row.trip.voucherNo : row.trip.biltyNo, row.trip.vehicleNo || "—", row.legLabel || "—", row.trip.route || "—", row.driverName, `${tr(`driverLedger.kharcha.${row.kharchaStatus}`)}${row.kharcha ? ` · ${money(row.kharcha)}` : ""}`, money(row.salaryEarnings)]),
        emptyMessage: tr("driverLedger.table.empty"),
      },
      {
        title: tr("driverLedger.account.title"),
        columns: [tr("driverLedger.account.driver"), tr("driverLedger.account.opening"), tr("driverLedger.account.salaryEarnings"), tr("driverLedger.account.driverPayments"), tr("driverLedger.account.payable"), tr("driverLedger.account.recoverable"), tr("driverLedger.account.balance")],
        rows: data.accounts.map((row) => [row.driverName, money(row.opening), money(row.earnings), money(row.payments), money(row.balance.payable), money(row.balance.recoverable), money(row.balance.balance)]),
        emptyMessage: tr("driverLedger.account.noAccountForUnrecorded"),
      },
      {
        title: tr("driverLedger.account.history"),
        columns: [tr("driverLedger.account.date"), tr("driverLedger.account.driver"), tr("driverLedger.account.type"), tr("driverLedger.account.eventDescription"), tr("driverLedger.account.salaryEarnings"), tr("driverLedger.account.driverPayments"), tr("driverLedger.account.advanceAdjustment")],
        rows: data.events.map((event) => [event.date, event.driverName, tr(`driverLedger.account.${event.kind}`), event.detail || "—", money(event.earning), money(event.payment), money(event.advance)]),
        emptyMessage: tr("driverLedger.account.empty"),
      },
    ],
  };
}

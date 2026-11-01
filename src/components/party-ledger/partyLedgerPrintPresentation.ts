import type { PrintLanguage } from "@/lib/print/types";
import { translateLedgerPrint, type LedgerPrintPresentation } from "@/components/print/LedgerStatementPrint";
import type { PartyLedgerPeriod, PartyLedgerReport, PartyLedgerSummary } from "./types";

const amount = (value: number) => `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 0 })}`;

export function partyLedgerPrintPresentation(reports: PartyLedgerReport[], summary: PartyLedgerSummary | undefined, dateRange: string, language: PrintLanguage, period?: { period: PartyLedgerPeriod; fromDate: string; toDate: string }): LedgerPrintPresentation {
  const tr = (key: string) => translateLedgerPrint(language, key);
  const rangeLabel = period
    ? period.period === "custom"
      ? `${period.fromDate || tr("common.dateFilters.allTime")} — ${period.toDate || tr("common.dateFilters.allTime")}`
      : tr(`common.dateFilters.${period.period === "all" ? "allTime" : period.period}`)
    : dateRange;
  const single = reports.length === 1 ? reports[0] : null;
  const tables = reports.map((report) => ({
    title: report.partyName,
    columns: [tr("common.date"), tr("common.loadingNo"), tr("common.bookingNo"), tr("common.route"), tr("common.vehicle"), tr("common.driver"), tr("common.freight"), tr("common.advance"), tr("partyLedger.fields.receiptPayments"), tr("partyLedger.fields.totalReceived"), tr("partyLedger.fields.remaining"), tr("partyLedger.fields.status")],
    rows: [
      ...report.trips.map((trip) => [trip.loadingDate || "—", trip.loadingNo || "—", trip.bookingNo || "—", trip.route || "—", trip.vehicleNo || "—", trip.driverName || "—", amount(trip.freight), amount(trip.advance), amount(trip.receiptPayments), amount(trip.totalReceived), amount(trip.remaining), tr(`partyLedger.status.${trip.paymentStatus}`)]),
      [tr("common.total"), "", "", "", "", "", amount(report.totalFreight), amount(report.totalAdvance), amount(report.totalReceiptPayments), amount(report.totalReceived), amount(report.remainingBalance), tr(`partyLedger.status.${report.paymentStatus}`)],
    ],
    emptyMessage: tr("partyLedger.states.empty"),
  }));
  return {
    documentType: "party_ledger",
    title: tr(single ? "partyLedger.print.statementTitle" : "partyLedger.print.mainTitle"),
    subtitle: `${tr("partyLedger.print.dateRange")}: ${rangeLabel}`,
    reference: single?.partyName,
    fields: [
      ...(single ? [{ label: tr("common.party"), value: single.partyName }, { label: tr("partyLedger.fields.adda"), value: single.addaName }] : []),
      { label: tr("partyLedger.print.dateRange"), value: rangeLabel },
      { label: tr("partyLedger.fields.totalTrips"), value: String(single?.totalTrips ?? summary?.totalTrips ?? 0), direction: "ltr" },
    ],
    summary: [
      { label: tr("partyLedger.fields.totalFreight"), value: amount(single?.totalFreight ?? summary?.totalFreight ?? 0) },
      ...(single ? [
        { label: tr("partyLedger.fields.totalAdvance"), value: amount(single.totalAdvance) },
        { label: tr("partyLedger.fields.receiptPayments"), value: amount(single.totalReceiptPayments) },
      ] : []),
      { label: tr("partyLedger.fields.totalReceived"), value: amount(single?.totalReceived ?? summary?.totalReceived ?? 0) },
      { label: tr("partyLedger.fields.remaining"), value: amount(single?.remainingBalance ?? summary?.totalRemaining ?? 0) },
    ],
    tables,
  };
}

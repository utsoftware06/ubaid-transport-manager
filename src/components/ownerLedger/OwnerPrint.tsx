"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import { printOwnerLedger } from "@/components/ownerLedger/printOwnerLedger";
import type { OwnerLedgerSummary, OwnerReport } from "@/components/ownerLedger/types";
import LedgerStatementPrintButton, { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { ownerLedgerPrintPresentation } from "./ownerLedgerPrintPresentation";
import type { VehicleFilterType } from "@/components/vehicleLedger/VehicleLedger";

type Props = { reports: OwnerReport[]; summary: OwnerLedgerSummary; period: { filterType: VehicleFilterType; fromDate: string; toDate: string } };

export default function OwnerPrint({ reports, summary, period }: Props) {
  const { t, dir, language } = useLanguage();
  const addaId = singleResolvedAddaId(reports.flatMap((report) => report.trips.map((trip) => trip.addaId)));
  const unavailableReason = reports.length && !addaId ? (language === "ur" ? "ایک ہی تصدیق شدہ اڈے کی رپورٹ منتخب کریں۔" : "Filter the report to one verified Adda before printing.") : undefined;
  return <>
    <LedgerStatementPrintButton addaId={addaId} documentType="owner_ledger" initialLanguage={language} makePresentation={(printLanguage) => ownerLedgerPrintPresentation(reports, summary, printLanguage, period)} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={() => printOwnerLedger(reports, summary, t, dir, language)} unavailableReason={unavailableReason}>
      <button type="button" disabled={reports.length === 0 || !addaId} title={unavailableReason} className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-gray-400">{t("ownerLedger.actions.printAll")}</button>
    </LedgerStatementPrintButton>
    {unavailableReason ? <p className="text-xs font-semibold text-amber-800">{unavailableReason}</p> : null}
  </>;
}

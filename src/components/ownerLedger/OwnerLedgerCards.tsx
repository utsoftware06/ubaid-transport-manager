"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import { formatAmount } from "@/components/vehicleLedger/reporting";
import type { OwnerLedgerSummary } from "@/components/ownerLedger/types";

export default function OwnerLedgerCards({ summary }: { summary: OwnerLedgerSummary }) {
  const { t, dir } = useLanguage();
  const cards = [
    [t("ownerLedger.summary.totalOwners"), summary.totalOwners.toLocaleString("en-PK")],
    [t("ownerLedger.summary.totalVehicles"), summary.totalVehicles.toLocaleString("en-PK")],
    [t("ownerLedger.summary.totalTrips"), summary.totalTrips.toLocaleString("en-PK")],
    [t("ownerLedger.summary.totalVehicleFreight"), formatAmount(summary.totalVehicleFreight)],
    [t("ownerLedger.summary.totalReceived"), formatAmount(summary.totalReceived)],
    [t("vehicleLedger.cards.parchiVehicleWithheld"), formatAmount(summary.totalParchiVehicleWithheld)],
    [t("vehicleLedger.cards.vehicleEntitlementSettled"), formatAmount(summary.totalVehicleEntitlementSettled)],
    [t("ownerLedger.summary.totalOutstanding"), formatAmount(summary.totalOutstanding)],
    [t("ownerLedger.summary.totalExpense"), formatAmount(summary.totalExpenses)],
    [t("ownerLedger.summary.netVehicleEarnings"), formatAmount(summary.netVehicleEarnings)],
  ];
  return <section dir={dir} className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
    {cards.map(([title, value], index) => <article key={title} className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <p className="text-sm font-semibold text-gray-600">{title}</p>
      <p className={`mt-3 text-2xl font-bold ${index === 7 ? summary.netVehicleEarnings >= 0 ? "text-emerald-700" : "text-red-700" : "text-gray-900"}`}>{value}</p>
    </article>)}
  </section>;
}

"use client";

import type { VehicleLedgerSummary } from "./VehicleLedger";
import { formatAmount } from "./reporting";
import { useLanguage } from "@/contexts/LanguageContext";

type Props = { summary: VehicleLedgerSummary };

export default function VehicleLedgerCards({ summary }: Props) {
  const { t, dir } = useLanguage();
  const cards = [
    { title: t("vehicleLedger.cards.totalVehicles"), value: summary.totalVehicles.toLocaleString("en-PK") },
    { title: t("vehicleLedger.cards.totalTrips"), value: summary.totalTrips.toLocaleString("en-PK") },
    { title: t("vehicleLedger.cards.totalVehicleFreight"), value: formatAmount(summary.totalVehicleFreight) },
    { title: t("vehicleLedger.cards.totalReceived"), value: formatAmount(summary.totalReceived) },
    { title: t("vehicleLedger.cards.parchiVehicleWithheld"), value: formatAmount(summary.totalParchiVehicleWithheld) },
    { title: t("vehicleLedger.cards.vehicleEntitlementSettled"), value: formatAmount(summary.totalVehicleEntitlementSettled) },
    { title: t("vehicleLedger.cards.totalOutstanding"), value: formatAmount(summary.totalOutstanding) },
    { title: t("vehicleLedger.cards.totalExpense"), value: formatAmount(summary.totalExpense) },
    { title: t("vehicleLedger.cards.netVehicleEarnings"), value: formatAmount(summary.netVehicleEarnings) },
  ];

  return (
    <section dir={dir}>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4 2xl:grid-cols-5">
        {cards.map((card) => (
          <article key={card.title} className="rounded-xl border border-gray-300 bg-white p-5 shadow-md">
            <p className="text-sm font-semibold text-gray-700">{card.title}</p>
            <p dir="ltr" className="mt-3 text-xl font-bold text-gray-900">{card.value}</p>
          </article>
        ))}
      </div>
      <p className="mt-2 text-xs font-medium text-gray-600">{t("vehicleLedger.cards.paymentScope")}</p>
    </section>
  );
}

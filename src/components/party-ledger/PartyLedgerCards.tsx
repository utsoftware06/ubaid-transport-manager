"use client";

import { Banknote, CircleCheck, CircleDashed, CircleX, ReceiptText, Truck, UsersRound, Wallet } from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";
import type { PartyLedgerSummary } from "./types";

type Props = {
  summary: PartyLedgerSummary;
};

function amount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

export default function PartyLedgerCards({ summary }: Props) {
  const { t } = useLanguage();
  const cards = [
    { key: "parties", label: t("partyLedger.cards.totalParties"), value: String(summary.totalParties), icon: UsersRound },
    { key: "trips", label: t("partyLedger.cards.totalTrips"), value: String(summary.totalTrips), icon: Truck },
    { key: "freight", label: t("partyLedger.cards.totalFreight"), value: amount(summary.totalFreight), icon: Banknote },
    { key: "received", label: t("partyLedger.cards.totalReceived"), value: amount(summary.totalReceived), icon: ReceiptText },
    { key: "remaining", label: t("partyLedger.cards.totalRemaining"), value: amount(summary.totalRemaining), icon: Wallet },
    { key: "paid", label: t("partyLedger.cards.paidParties"), value: String(summary.paidParties), icon: CircleCheck },
    { key: "partial", label: t("partyLedger.cards.partialParties"), value: String(summary.partialParties), icon: CircleDashed },
    { key: "unpaid", label: t("partyLedger.cards.unpaidParties"), value: String(summary.unpaidParties), icon: CircleX },
  ];

  return (
    <section
      aria-label={t("partyLedger.cards.summary")}
      className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4"
    >
      {cards.map(({ key, label, value, icon: Icon }) => (
        <article key={key} className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="font-semibold text-slate-700">{label}</p>
              <p dir="ltr" className="mt-2 text-2xl font-extrabold text-slate-900">{value}</p>
            </div>
            <span className="rounded-xl bg-blue-50 p-3 text-blue-700">
              <Icon className="h-6 w-6" aria-hidden="true" />
            </span>
          </div>
        </article>
      ))}
    </section>
  );
}

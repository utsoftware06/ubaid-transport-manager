"use client";

import { useEffect, useRef, useState } from "react";
import { Printer, X } from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";
import { buildVehicleSettlementDisplay, getParchiVehicleSettlementTotals } from "@/lib/parchi/vehicleSettlement";
import { supabase } from "@/lib/supabase/client";

import type { BiltyRow } from "./types";

type BiltyDetailsModalProps = {
  bilty: BiltyRow;
  onClose: () => void;
  onPrint: () => void;
};

function relation<T>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

function money(value: number | string | null) {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount)
    ? new Intl.NumberFormat("en-PK", { maximumFractionDigits: 2 }).format(amount)
    : "0";
}

function amountOrZero(value: number | string | null | undefined): number {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

export default function BiltyDetailsModal({
  bilty,
  onClose,
  onPrint,
}: BiltyDetailsModalProps) {
  const { t, dir } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const [vehicleSettlementResource, setVehicleSettlementResource] = useState<{
    key: string;
    status: "loading" | "ready" | "error";
    settlement: ReturnType<typeof buildVehicleSettlementDisplay>;
  }>({ key: "", status: "loading", settlement: null });

  useEffect(() => {
    const previousFocus = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocus?.focus();
    };
  }, [onClose]);

  const party = relation(bilty.parties)?.name ?? "-";
  const broker = relation(bilty.brokers)?.broker_name ?? "-";
  const vehicle = relation(bilty.vehicles);
  const fromLocation = relation(bilty.from_location)?.name ?? bilty.from_city ?? "-";
  const toLocation = relation(bilty.to_location)?.name ?? bilty.to_city ?? "-";
  const vehicleNo = vehicle?.vehicle_no ?? bilty.external_vehicle_no ?? "-";
  const vehicleType = vehicle?.vehicle_type ?? bilty.external_vehicle_type ?? "-";
  const ownerName = vehicle?.owner_name ?? bilty.external_owner_name ?? "-";
  const items = [...(bilty.bilty_items ?? [])].sort((a, b) => a.line_no - b.line_no);
  const originalVehicleFreight = amountOrZero(bilty.vehicle_freight);
  const brokerCommission = amountOrZero(bilty.broker_commission);
  const overweightCharges = amountOrZero(bilty.overweight_charges);
  const loloCharges = amountOrZero(bilty.lolo_charges);
  const detainCharges = amountOrZero(bilty.detain_charges);
  const adjustedVehicleFreight =
    originalVehicleFreight - brokerCommission + overweightCharges + loloCharges + detainCharges;
  const vehicleSettlementKey = `${bilty.adda_id}:${bilty.id}`;
  const vehicleSettlementState = vehicleSettlementResource.key === vehicleSettlementKey ? vehicleSettlementResource.status : "loading";
  const vehicleSettlement = vehicleSettlementResource.key === vehicleSettlementKey ? vehicleSettlementResource.settlement : null;

  useEffect(() => {
    let active = true;
    void Promise.all([
      supabase.rpc("get_bilty_financial_summary", { p_bilty_id: bilty.id }),
      getParchiVehicleSettlementTotals(bilty.adda_id, [bilty.id]),
    ]).then(([summaryResult, parchiTotals]) => {
      if (summaryResult.error) throw summaryResult.error;
      const summaryRow = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
      if (!summaryRow) throw new Error("BILTY_FINANCIAL_SUMMARY_UNAVAILABLE");
      const actualCash = summaryRow.total_vehicle_paid == null ? null : Number(summaryRow.total_vehicle_paid);
      const display = buildVehicleSettlementDisplay(
        adjustedVehicleFreight,
        actualCash !== null && Number.isFinite(actualCash) ? actualCash : null,
        parchiTotals.get(bilty.id)?.withheldCommission ?? 0,
      );
      if (!display) throw new Error("BILTY_VEHICLE_SETTLEMENT_INVALID");
      if (!active) return;
      setVehicleSettlementResource({ key: vehicleSettlementKey, status: "ready", settlement: display });
    }).catch((error: unknown) => {
      console.error("Unable to load Bilty vehicle settlement details:", error);
      if (!active) return;
      setVehicleSettlementResource({ key: vehicleSettlementKey, status: "error", settlement: null });
    });
    return () => { active = false; };
  }, [adjustedVehicleFreight, bilty.adda_id, bilty.id, vehicleSettlementKey]);

  const detail = (label: string, value: React.ReactNode, technical = false) => (
    <div className="rounded-2xl border border-slate-200 bg-white p-3.5 shadow-sm">
      <dt className="text-[11px] font-extrabold uppercase tracking-wide text-slate-500">{label}</dt>
      <dd className="mt-1 font-semibold text-slate-900" dir={technical ? "ltr" : undefined}>
        {value}
      </dd>
    </div>
  );

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/65 p-2 backdrop-blur-sm sm:p-4 md:p-6"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="bilty-details-title"
        aria-describedby="bilty-details-description"
        dir={dir}
        className="max-h-[94vh] w-full max-w-6xl overflow-y-auto rounded-3xl border border-slate-200 bg-white shadow-2xl"
      >
        <header className="sticky top-0 z-10 flex flex-wrap items-start justify-between gap-3 border-b border-slate-200 bg-white/95 p-4 backdrop-blur sm:p-5 md:p-6">
          <div>
            <h2 id="bilty-details-title" className="text-2xl font-black text-slate-950">
              {t("bilty.details.title")}
            </h2>
            <p id="bilty-details-description" className="mt-1 text-sm font-medium text-slate-600">
              {t("bilty.details.description")}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={onPrint}
              className="inline-flex min-h-10 items-center gap-2 rounded-xl bg-blue-600 px-4 py-2 font-extrabold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
            >
              <Printer size={18} aria-hidden="true" />
              {t("bilty.actions.print")}
            </button>
            <button
              ref={closeButtonRef}
              type="button"
              onClick={onClose}
              aria-label={t("bilty.actions.closeDetails")}
              className="rounded-xl border border-slate-200 bg-white p-2.5 text-slate-700 transition hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
            >
              <X size={20} aria-hidden="true" />
            </button>
          </div>
        </header>

        <div className="space-y-6 bg-slate-50/70 p-3 sm:p-4 md:p-6">
          <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {detail(t("bilty.form.biltyNo"), bilty.booking_no, true)}
            {detail(t("bilty.form.date"), bilty.booking_date, true)}
            {detail(t("bilty.form.loadingDate"), bilty.loading_date ?? "-", true)}
            {detail(t("bilty.form.departureDate"), bilty.departure_date ?? "-", true)}
            {detail(t("bilty.form.arrivalDate"), bilty.arrival_date ?? "-", true)}
            {detail(
              t("bilty.form.group"),
              `${bilty.movement_group?.outbound_bilty_no ?? bilty.booking_no} — ${t("bilty.movement.group")} ${bilty.bilty_group_id.replaceAll("-", "").slice(0, 6).toUpperCase()}`,
              true
            )}
            {detail(t("bilty.movement.status"), t(`bilty.movement.${bilty.movement_group?.status === "voucher_created" ? "voucherCreated" : bilty.movement_group?.status ?? "open"}`))}
            {detail(
              t("bilty.form.tripType"),
              bilty.trip_type ? t(`bilty.tripTypes.${bilty.trip_type}`) : t("bilty.legacy")
            )}
            {detail(
              t("bilty.form.freightType"),
              bilty.freight_type ? t(`bilty.freightTypes.${bilty.freight_type}`) : t("bilty.legacy")
            )}
            {detail(
              t("bilty.form.biltyType"),
              bilty.bilty_type === "self_vehicle"
                ? t("bilty.biltyTypes.self")
                : bilty.bilty_type === "other_vehicle"
                  ? t("bilty.biltyTypes.other")
                  : t("bilty.legacy")
            )}
            {detail(t("bilty.form.party"), party)}
            {detail(t("bilty.form.broker"), broker)}
            {detail(t("bilty.form.reference"), bilty.reference_no ?? "-", true)}
            {detail(t("bilty.form.fromSearch"), fromLocation)}
            {detail(t("bilty.form.toSearch"), toLocation)}
            {detail(t("bilty.form.vehicle"), vehicleNo, true)}
            {detail(t("bilty.form.vehicleType"), vehicleType)}
            {detail(t("bilty.form.ownerName"), ownerName)}
            {detail(t("bilty.form.senderName"), bilty.sender_name ?? "-")}
            {detail(t("bilty.form.senderPhone"), bilty.sender_phone ?? "-", true)}
            {detail(t("bilty.form.receiverName"), bilty.receiver_name ?? "-")}
            {detail(t("bilty.form.receiverPhone"), bilty.receiver_phone ?? "-", true)}
            {detail(t("bilty.form.freight"), `Rs. ${money(bilty.freight)}`, true)}
            {detail(t("bilty.details.createdAt"), bilty.created_at ?? "-", true)}
          </dl>

          <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
            <h3 className="mb-3 border-b border-slate-100 pb-3 text-lg font-black text-slate-950">{t("bilty.container.title")}</h3>
            <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {detail(t("bilty.container.number"), bilty.container_no ?? "-", true)}
              {detail(t("bilty.container.size"), bilty.container_size ?? "-", true)}
              {detail(t("bilty.container.weight"), bilty.container_weight ?? "-", true)}
              {detail(t("bilty.container.serial"), bilty.container_serial ?? "-", true)}
              {detail(t("bilty.container.port"), bilty.container_port ?? "-")}
              {detail(t("bilty.container.clearingAgent"), bilty.clearing_agent ?? "-")}
              {detail(t("bilty.container.shippingLine"), bilty.shipping_line ?? "-")}
              {detail(t("bilty.container.cargo"), bilty.container_cargo ?? "-")}
            </dl>
          </section>

          <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
            <h3 className="mb-3 border-b border-slate-100 pb-3 text-lg font-black text-slate-950">{t("bilty.financial.title")}</h3>
            <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {detail(t("bilty.financial.originalVehicleFreight"), `Rs. ${money(originalVehicleFreight)}`, true)}
              {detail(t("bilty.financial.brokerCommission"), `-Rs. ${money(brokerCommission)}`, true)}
              {detail(t("bilty.financial.overweightCharges"), `+Rs. ${money(overweightCharges)}`, true)}
              {detail(t("bilty.financial.loloCharges"), `+Rs. ${money(loloCharges)}`, true)}
              {detail(t("bilty.financial.detainCharges"), `+Rs. ${money(detainCharges)}`, true)}
              {detail(t("bilty.financial.adjustedVehicleFreight"), `Rs. ${money(adjustedVehicleFreight)}`, true)}
              {detail(t("bilty.financial.advanceVehicle"), `Rs. ${money(bilty.advance_vehicle)}`, true)}
              {detail(
                t("bilty.financial.actualVehicleCashPaid"),
                vehicleSettlementState === "ready" && vehicleSettlement ? `Rs. ${money(vehicleSettlement.actualCashPaid)}`
                  : t(vehicleSettlementState === "loading" ? "bilty.states.loading" : "bilty.states.vehicleSettlementUnavailable"),
                true
              )}
              {detail(
                t("bilty.financial.parchiWithheldCommission"),
                vehicleSettlementState === "ready" && vehicleSettlement ? `Rs. ${money(vehicleSettlement.parchiWithheldCommission)}`
                  : t(vehicleSettlementState === "loading" ? "bilty.states.loading" : "bilty.states.vehicleSettlementUnavailable"),
                true
              )}
              {detail(
                t("bilty.financial.vehicleEntitlementSettled"),
                vehicleSettlementState === "ready" && vehicleSettlement ? `Rs. ${money(vehicleSettlement.entitlementSettled)}`
                  : t(vehicleSettlementState === "loading" ? "bilty.states.loading" : "bilty.states.vehicleSettlementUnavailable"),
                true
              )}
              {detail(
                t("bilty.financial.vehicleOutstanding"),
                vehicleSettlementState === "ready" && vehicleSettlement
                  ? <>{`Rs. ${money(vehicleSettlement.outstanding)}`} <span className="ms-2">{t(`vehicleLedger.filters.status.${vehicleSettlement.status.toLowerCase()}`)}</span></>
                  : t(vehicleSettlementState === "loading" ? "bilty.states.loading" : "bilty.states.vehicleSettlementUnavailable"),
                true
              )}
              {detail(t("bilty.financial.advanceBilty"), `Rs. ${money(bilty.advance_bilty)}`, true)}
              {detail(t("bilty.financial.advanceCommission"), `Rs. ${money(bilty.advance_commission)}`, true)}
              {detail(t("bilty.financial.partyCommission"), `Rs. ${money(bilty.party_commission)}`, true)}
              {detail(t("bilty.financial.advanceBrokerage"), `Rs. ${money(bilty.advance_brokerage)}`, true)}
            </dl>
          </section>

          <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
            <h3 className="mb-3 border-b border-slate-100 pb-3 text-lg font-black text-slate-950">{t("bilty.items.title")}</h3>
            <div className="overflow-x-auto rounded-2xl border border-slate-200">
              <table className="min-w-full border-collapse bg-white text-sm">
                <thead className="bg-slate-900 text-white">
                  <tr>
                    <th className="whitespace-nowrap px-3 py-3 text-start">{t("bilty.print.serial")}</th>
                    <th className="whitespace-nowrap px-3 py-3 text-start">{t("bilty.items.goods")}</th>
                    <th className="whitespace-nowrap px-3 py-3 text-start">{t("common.quantity")}</th>
                    <th className="whitespace-nowrap px-3 py-3 text-start">{t("common.weight")}</th>
                    <th className="whitespace-nowrap px-3 py-3 text-start">{t("common.unit")}</th>
                    <th className="whitespace-nowrap px-3 py-3 text-start">{t("common.remarks")}</th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((item, index) => (
                    <tr key={item.id} className="border-b border-slate-100 last:border-0 even:bg-slate-50/70">
                      <td className="px-3 py-3" dir="ltr">{index + 1}</td>
                      <td className="px-3 py-3 font-semibold">{item.goods_name}</td>
                      <td className="px-3 py-3" dir="ltr">{item.quantity}</td>
                      <td className="px-3 py-3" dir="ltr">{item.weight ?? "-"}</td>
                      <td className="px-3 py-3">{item.unit}</td>
                      <td className="px-3 py-3">{item.remarks ?? "-"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </section>
    </div>
  );
}

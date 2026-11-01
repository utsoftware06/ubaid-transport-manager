"use client";

import { Printer, X } from "lucide-react";
import { useEffect, useRef } from "react";

import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { bilingual, modulePrintLabel, printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";

import { movementGroupReference, shortMovementGroupId } from "./movementGroups";
import type { BiltyRow, BiltyTripType } from "./types";

type ChakkarDetailsModalProps = {
  bilties: BiltyRow[];
  onClose: () => void;
};

type Translate = (key: string) => string;

const tripOrder: Record<BiltyTripType, number> = {
  outbound: 0,
  local: 1,
  return: 2,
};

function relation<T>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

function display(value: number | string | null | undefined) {
  if (value === null || value === undefined || String(value).trim() === "") return "-";
  return String(value);
}

function money(value: number | string | null | undefined) {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount)
    ? `Rs. ${new Intl.NumberFormat("en-PK", { maximumFractionDigits: 2 }).format(amount)}`
    : "Rs. 0";
}

function tripRank(tripType: BiltyTripType | null) {
  return tripType ? tripOrder[tripType] : 1;
}

export function sortChakkarBilties(bilties: BiltyRow[]): BiltyRow[] {
  return [...bilties].sort((left, right) =>
    tripRank(left.trip_type) - tripRank(right.trip_type) ||
    left.booking_date.localeCompare(right.booking_date) ||
    (left.loading_date ?? "").localeCompare(right.loading_date ?? "") ||
    (left.created_at ?? "").localeCompare(right.created_at ?? "") ||
    left.booking_no.localeCompare(right.booking_no) ||
    left.id.localeCompare(right.id)
  );
}

function tripLabel(bilty: BiltyRow, t: Translate) {
  return bilty.trip_type ? t(`bilty.tripTypes.${bilty.trip_type}`) : t("bilty.legacy");
}

function statusLabel(status: string | undefined, t: Translate) {
  if (status === "voucher_created") return t("bilty.movement.voucherCreated");
  if (status === "completed") return t("bilty.movement.completed");
  return t("bilty.movement.open");
}

function biltyVehicle(bilty: BiltyRow) {
  return relation(bilty.vehicles)?.vehicle_no ?? bilty.external_vehicle_no ?? "-";
}

function biltyOwner(bilty: BiltyRow) {
  return relation(bilty.vehicles)?.owner_name ?? bilty.external_owner_name ?? "-";
}

function biltyLocation(
  relationValue: BiltyRow["from_location"] | BiltyRow["to_location"],
  legacyValue: string | null
) {
  return relation(relationValue)?.name ?? legacyValue ?? "-";
}

export default function ChakkarDetailsModal({
  bilties,
  onClose,
}: ChakkarDetailsModalProps) {
  const { t, dir, language } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const orderedBilties = sortChakkarBilties(bilties);
  const outbound = orderedBilties.find((bilty) => bilty.trip_type === "outbound");
  const returnBilty = orderedBilties.find((bilty) => bilty.trip_type === "return");
  const contextBilty = outbound ?? orderedBilties[0];
  const group = contextBilty?.movement_group ?? null;
  const groupId = contextBilty?.bilty_group_id ?? "";
  const groupReference = group
    ? movementGroupReference(group, t("bilty.movement.group"))
    : `${t("bilty.movement.group")} ${shortMovementGroupId(groupId)}`;
  const groupAddaId = singleResolvedAddaId(orderedBilties.map((bilty) => bilty.adda_id));
  const modulePrint = useModuleTransportPrint("bilty_chakkar", groupAddaId, language === "ur" ? "ur" : "en");

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

  const printChakkarLegacy = () => {
    const popup = window.open("", "_blank", "width=1100,height=850");
    if (!popup) {
      window.alert(t("bilty.messages.popupBlocked"));
      return;
    }

    const printField = (label: string, value: unknown, technical = false) => `
      <div class="field">
        <span>${escapeHtml(label)}</span>
        <strong class="${technical ? "technical" : ""}">${escapeHtml(display(value as string | number | null | undefined))}</strong>
      </div>`;

    const membersHtml = orderedBilties.map((bilty, index) => {
      const party = relation(bilty.parties)?.name ?? "-";
      const broker = relation(bilty.brokers)?.broker_name ?? "-";
      const fromLocation = biltyLocation(bilty.from_location, bilty.from_city);
      const toLocation = biltyLocation(bilty.to_location, bilty.to_city);
      const sender = [bilty.sender_name, bilty.sender_phone].filter(Boolean).join(" / ") || "-";
      const receiver = [bilty.receiver_name, bilty.receiver_phone].filter(Boolean).join(" / ") || "-";
      const items = [...(bilty.bilty_items ?? [])].sort((left, right) => left.line_no - right.line_no);
      const itemRows = items.length > 0
        ? items.map((item, itemIndex) => `<tr>
            <td class="technical">${itemIndex + 1}</td>
            <td>${escapeHtml(item.goods_name)}</td>
            <td class="technical">${escapeHtml(item.quantity)}</td>
            <td class="technical">${escapeHtml(item.weight ?? "-")}</td>
            <td>${escapeHtml(item.unit)}</td>
            <td>${escapeHtml(item.remarks ?? "-")}</td>
          </tr>`).join("")
        : `<tr><td colspan="6">${escapeHtml(t("bilty.chakkarDetails.noItems"))}</td></tr>`;
      const type = bilty.trip_type ?? "local";

      return `<section class="member member-${escapeHtml(type)}">
        <h2><span>${index + 1}.</span> ${escapeHtml(tripLabel(bilty, t))} — ${escapeHtml(bilty.booking_no)}</h2>
        <div class="fields">
          ${printField(t("bilty.form.tripType"), tripLabel(bilty, t))}
          ${printField(t("bilty.form.biltyNo"), bilty.booking_no, true)}
          ${printField(t("bilty.form.date"), bilty.booking_date, true)}
          ${printField(t("bilty.form.loadingDate"), bilty.loading_date, true)}
          ${printField(t("bilty.form.departureDate"), bilty.departure_date, true)}
          ${printField(t("bilty.form.arrivalDate"), bilty.arrival_date, true)}
          ${printField(t("bilty.form.fromSearch"), fromLocation)}
          ${printField(t("bilty.form.toSearch"), toLocation)}
          ${printField(t("bilty.form.party"), party)}
          ${printField(t("bilty.form.broker"), broker)}
          ${printField(t("bilty.form.vehicle"), biltyVehicle(bilty), true)}
          ${printField(t("bilty.form.ownerName"), biltyOwner(bilty))}
          ${printField(t("bilty.chakkarDetails.vehicleFreightOwner"), money(bilty.vehicle_freight), true)}
          ${printField(t("bilty.financial.advanceVehicle"), money(bilty.advance_vehicle), true)}
          ${printField(t("bilty.form.reference"), bilty.reference_no, true)}
          ${printField(t("bilty.print.sender"), sender)}
          ${printField(t("bilty.print.receiver"), receiver)}
        </div>
        <table>
          <thead><tr><th>${escapeHtml(t("bilty.print.serial"))}</th><th>${escapeHtml(t("bilty.items.goods"))}</th><th>${escapeHtml(t("common.quantity"))}</th><th>${escapeHtml(t("common.weight"))}</th><th>${escapeHtml(t("common.unit"))}</th><th>${escapeHtml(t("common.remarks"))}</th></tr></thead>
          <tbody>${itemRows}</tbody>
        </table>
      </section>`;
    }).join("");

    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head>
      <meta charset="utf-8" />
      <title>${escapeHtml(t("bilty.chakkarDetails.printTitle"))} - ${escapeHtml(groupReference)}</title>
      <style>
        @page{size:A4 landscape;margin:10mm}*{box-sizing:border-box}body{margin:0;color:#0f172a;background:#fff;font-family:Arial,"Noto Nastaliq Urdu",sans-serif;direction:${dir};text-align:start}.sheet{padding:8px}.brand{text-align:center;border-bottom:3px solid #1d4ed8;padding-bottom:10px}.brand h1{margin:0;color:#1d4ed8}.brand p{margin:5px 0 0}.summary,.fields{display:grid;grid-template-columns:repeat(4,1fr);gap:7px;margin-top:12px}.field{border:1px solid #94a3b8;border-radius:5px;padding:7px;min-height:45px}.field span{display:block;color:#475569;font-size:10px;font-weight:700}.field strong{display:block;margin-top:3px;font-size:12px;overflow-wrap:anywhere}.technical{direction:ltr;unicode-bidi:isolate}.member{margin-top:16px;border:2px solid #94a3b8;border-radius:7px;padding:12px;break-inside:auto}.member+.member{break-before:page}.member h2{margin:0;padding:8px 10px;font-size:17px}.member-outbound h2{background:#dbeafe;color:#1e3a8a}.member-local h2{background:#fef3c7;color:#78350f}.member-return h2{background:#d1fae5;color:#064e3b}table{width:100%;border-collapse:collapse;margin-top:12px;font-size:11px}th,td{border:1px solid #64748b;padding:6px;text-align:start;vertical-align:top}th{background:#1d4ed8;color:#fff}
      </style></head><body><main class="sheet">
        <header class="brand"><h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${escapeHtml(t("bilty.chakkarDetails.printTitle"))}</h2><p>${escapeHtml(groupReference)}</p></header>
        <section class="summary">
          ${printField(t("bilty.movement.status"), statusLabel(group?.status, t))}
          ${printField(t("bilty.form.vehicle"), contextBilty ? biltyVehicle(contextBilty) : "-", true)}
          ${printField(t("bilty.form.ownerName"), contextBilty ? biltyOwner(contextBilty) : "-")}
          ${printField(t("bilty.chakkarDetails.totalBilties"), orderedBilties.length, true)}
          ${printField(t("bilty.chakkarDetails.outboundBilty"), outbound?.booking_no, true)}
          ${printField(t("bilty.chakkarDetails.returnBilty"), returnBilty?.booking_no, true)}
        </section>
        ${membersHtml}
      </main><script>window.onload=function(){window.focus();window.print();};</script></body></html>`, orderedBilties[0]?.adda_id ?? null, language === "ur" ? "ur" : "en");
  };

  const printChakkar = () => {
    const presentation: ModulePrintPresentation = {
      documentType: "bilty_chakkar",
      title: printLabel("bilty.chakkarDetails.printTitle"),
      documentNo: printValue(group?.id ?? shortMovementGroupId(groupId)),
      documentDate: printValue(contextBilty?.booking_date),
      fields: [
        { label: printLabel("bilty.movement.status"), value: group?.status ? printLabel(group.status === "voucher_created" ? "bilty.movement.voucherCreated" : group.status === "completed" ? "bilty.movement.completed" : "bilty.movement.open") : null },
        { label: printLabel("bilty.form.vehicle"), value: printValue(contextBilty ? biltyVehicle(contextBilty) : null) },
        { label: printLabel("bilty.form.ownerName"), value: printValue(contextBilty ? biltyOwner(contextBilty) : null) },
        { label: printLabel("bilty.chakkarDetails.totalBilties"), value: String(orderedBilties.length) },
        { label: printLabel("bilty.chakkarDetails.outboundBilty"), value: printValue(outbound?.booking_no) },
        { label: printLabel("bilty.chakkarDetails.returnBilty"), value: printValue(returnBilty?.booking_no) },
      ],
      tables: orderedBilties.flatMap((bilty) => {
        const tripKey = bilty.trip_type ? `bilty.tripTypes.${bilty.trip_type}` : "bilty.legacy";
        const itemColumns = ["bilty.items.goods", "common.quantity", "common.weight", "common.unit", "common.remarks"].map(printLabel);
        const items = [...(bilty.bilty_items ?? [])].sort((left, right) => left.line_no - right.line_no);
        return [
          {
            title: bilingual(`${modulePrintLabel("en", tripKey)} · ${bilty.booking_no}`, `${modulePrintLabel("ur", tripKey)} · ${bilty.booking_no}`),
            columns: ["bilty.form.tripType", "bilty.form.biltyNo", "bilty.form.date", "bilty.form.fromSearch", "bilty.form.toSearch", "bilty.form.party", "bilty.form.broker", "bilty.form.vehicle", "bilty.chakkarDetails.vehicleFreightOwner", "bilty.financial.advanceVehicle"].map(printLabel),
            rows: [[printLabel(tripKey), printValue(bilty.booking_no), printValue(bilty.booking_date), printValue(biltyLocation(bilty.from_location, bilty.from_city)), printValue(biltyLocation(bilty.to_location, bilty.to_city)), printValue(relation(bilty.parties)?.name), printValue(relation(bilty.brokers)?.broker_name), printValue(biltyVehicle(bilty)), printValue(money(bilty.vehicle_freight)), printValue(money(bilty.advance_vehicle))]],
          },
          {
            title: printLabel("bilty.items.title"),
            columns: itemColumns,
            rows: items.map((item) => [printValue(item.goods_name), printValue(item.quantity), printValue(item.weight), printValue(item.unit), printValue(item.remarks)]),
          },
        ];
      }),
    };
    modulePrint.openPresentation(presentation, printChakkarLegacy, groupAddaId);
  };

  const headerDetail = (label: string, value: string | number, technical = false) => (
    <div className="rounded-2xl border border-slate-200 bg-white p-3.5 shadow-sm">
      <dt className="text-[11px] font-extrabold uppercase tracking-wide text-slate-500">{label}</dt>
      <dd className="mt-1 font-bold text-slate-950" dir={technical ? "ltr" : undefined}>{value}</dd>
    </div>
  );

  return (
    <>
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/65 p-2 backdrop-blur-sm sm:p-4 md:p-6"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="chakkar-details-title"
        aria-describedby="chakkar-details-description"
        dir={dir}
        className="max-h-[94vh] w-full max-w-7xl overflow-y-auto rounded-3xl border border-slate-200 bg-slate-50 shadow-2xl"
      >
        <header className="sticky top-0 z-10 flex flex-wrap items-start justify-between gap-3 border-b border-slate-200 bg-white/95 p-4 backdrop-blur sm:p-5 md:p-6">
          <div>
            <h2 id="chakkar-details-title" className="text-2xl font-black text-slate-950">
              {t("bilty.chakkarDetails.title")}
            </h2>
            <p id="chakkar-details-description" className="mt-1 font-semibold text-slate-600">
              {groupReference}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={printChakkar}
              className="inline-flex min-h-10 items-center gap-2 rounded-xl bg-blue-600 px-4 py-2 font-extrabold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
            >
              <Printer size={18} aria-hidden="true" />
              {t("bilty.chakkarDetails.print")}
            </button>
            <button
              ref={closeButtonRef}
              type="button"
              onClick={onClose}
              aria-label={t("bilty.chakkarDetails.close")}
              className="rounded-xl border border-slate-200 bg-white p-2.5 text-slate-700 transition hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
            >
              <X size={20} aria-hidden="true" />
            </button>
          </div>
        </header>

        <div className="space-y-5 p-3 sm:p-4 md:p-6">
          <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {headerDetail(t("bilty.movement.status"), statusLabel(group?.status, t))}
            {headerDetail(t("bilty.form.vehicle"), contextBilty ? biltyVehicle(contextBilty) : "-", true)}
            {headerDetail(t("bilty.form.ownerName"), contextBilty ? biltyOwner(contextBilty) : "-")}
            {headerDetail(t("bilty.chakkarDetails.totalBilties"), orderedBilties.length, true)}
            {headerDetail(t("bilty.chakkarDetails.outboundBilty"), outbound?.booking_no ?? "-", true)}
            {headerDetail(t("bilty.chakkarDetails.returnBilty"), returnBilty?.booking_no ?? "-", true)}
          </dl>

          {orderedBilties.map((bilty, index) => {
            const party = relation(bilty.parties)?.name ?? "-";
            const broker = relation(bilty.brokers)?.broker_name ?? "-";
            const items = [...(bilty.bilty_items ?? [])].sort((left, right) => left.line_no - right.line_no);
            const tripType = bilty.trip_type ?? "local";
            const tone = tripType === "outbound"
              ? "border-blue-300 bg-blue-50 text-blue-950"
              : tripType === "return"
                ? "border-emerald-300 bg-emerald-50 text-emerald-950"
                : "border-amber-300 bg-amber-50 text-amber-950";
            const badgeTone = tripType === "outbound"
              ? "bg-blue-700 text-white"
              : tripType === "return"
                ? "bg-emerald-700 text-white"
                : "bg-amber-500 text-slate-950";

            const memberDetail = (label: string, value: string, technical = false) => (
              <div className="rounded-lg border border-slate-200 bg-white p-3">
                <dt className="text-xs font-bold uppercase tracking-wide text-slate-600">{label}</dt>
                <dd className="mt-1 font-semibold text-slate-950" dir={technical ? "ltr" : undefined}>{value}</dd>
              </div>
            );

            return (
              <article key={bilty.id} className={`overflow-hidden rounded-3xl border ${tone} shadow-sm`}>
                <header className="flex flex-wrap items-center justify-between gap-3 p-4">
                  <div className="flex items-center gap-3">
                    <span className="text-xl font-black" dir="ltr">{index + 1}.</span>
                    <span className={`rounded-full px-3 py-1 text-sm font-black ${badgeTone}`}>
                      {tripLabel(bilty, t)}
                    </span>
                    <h3 className="text-xl font-black" dir="ltr">{bilty.booking_no}</h3>
                  </div>
                </header>

                <div className="space-y-4 bg-white/80 p-3 sm:p-4">
                  <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    {memberDetail(t("bilty.form.tripType"), tripLabel(bilty, t))}
                    {memberDetail(t("bilty.form.biltyNo"), bilty.booking_no, true)}
                    {memberDetail(t("bilty.form.date"), bilty.booking_date, true)}
                    {memberDetail(t("bilty.form.loadingDate"), display(bilty.loading_date), true)}
                    {memberDetail(t("bilty.form.departureDate"), display(bilty.departure_date), true)}
                    {memberDetail(t("bilty.form.arrivalDate"), display(bilty.arrival_date), true)}
                    {memberDetail(t("bilty.form.fromSearch"), biltyLocation(bilty.from_location, bilty.from_city))}
                    {memberDetail(t("bilty.form.toSearch"), biltyLocation(bilty.to_location, bilty.to_city))}
                    {memberDetail(t("bilty.form.party"), party)}
                    {memberDetail(t("bilty.form.broker"), broker)}
                    {memberDetail(t("bilty.form.vehicle"), biltyVehicle(bilty), true)}
                    {memberDetail(t("bilty.form.ownerName"), biltyOwner(bilty))}
                    {memberDetail(t("bilty.chakkarDetails.vehicleFreightOwner"), money(bilty.vehicle_freight), true)}
                    {memberDetail(t("bilty.financial.advanceVehicle"), money(bilty.advance_vehicle), true)}
                    {memberDetail(t("bilty.form.reference"), display(bilty.reference_no), true)}
                    {memberDetail(t("bilty.print.sender"), [bilty.sender_name, bilty.sender_phone].filter(Boolean).join(" / ") || "-")}
                    {memberDetail(t("bilty.print.receiver"), [bilty.receiver_name, bilty.receiver_phone].filter(Boolean).join(" / ") || "-")}
                  </dl>

                  <section>
                    <h4 className="mb-2 text-base font-black text-slate-950">{t("bilty.items.title")}</h4>
                    <div className="overflow-x-auto rounded-2xl border border-slate-200 bg-white">
                      <table className="min-w-full border-collapse text-sm">
                        <thead className="bg-slate-900 text-white">
                          <tr>
                            <th className="whitespace-nowrap px-3 py-2 text-start">{t("bilty.print.serial")}</th>
                            <th className="whitespace-nowrap px-3 py-2 text-start">{t("bilty.items.goods")}</th>
                            <th className="whitespace-nowrap px-3 py-2 text-start">{t("common.quantity")}</th>
                            <th className="whitespace-nowrap px-3 py-2 text-start">{t("common.weight")}</th>
                            <th className="whitespace-nowrap px-3 py-2 text-start">{t("common.unit")}</th>
                            <th className="whitespace-nowrap px-3 py-2 text-start">{t("common.remarks")}</th>
                          </tr>
                        </thead>
                        <tbody>
                          {items.map((item, itemIndex) => (
                            <tr key={item.id} className="border-b border-slate-100 last:border-0 even:bg-slate-50/70">
                              <td className="px-3 py-2" dir="ltr">{itemIndex + 1}</td>
                              <td className="px-3 py-2 font-semibold">{item.goods_name}</td>
                              <td className="px-3 py-2" dir="ltr">{item.quantity}</td>
                              <td className="px-3 py-2" dir="ltr">{item.weight ?? "-"}</td>
                              <td className="px-3 py-2">{item.unit}</td>
                              <td className="px-3 py-2">{item.remarks ?? "-"}</td>
                            </tr>
                          ))}
                          {items.length === 0 && (
                            <tr>
                              <td colSpan={6} className="px-3 py-6 text-center font-semibold text-slate-500">
                                {t("bilty.chakkarDetails.noItems")}
                              </td>
                            </tr>
                          )}
                        </tbody>
                      </table>
                    </div>
                  </section>
                </div>
              </article>
            );
          })}
        </div>
      </section>
    </div>
    {modulePrint.dialog}
    </>
  );
}

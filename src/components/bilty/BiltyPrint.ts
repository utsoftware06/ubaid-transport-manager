import type { AppLanguage } from "@/i18n/translations";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import type { BiltyCopyType, BiltyPrintFinancialSummary } from "@/lib/print/biltyPresentation";

import type { BiltyRow } from "./types";

type Translate = (key: string) => string;
type Direction = "ltr" | "rtl";

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

function hasText(value: unknown): boolean {
  if (value === null || value === undefined) return false;
  const text = String(value).trim();
  return text !== "" && text !== "-";
}

function hasPositiveAmount(value: unknown): boolean {
  if (value === null || value === undefined || value === "") return false;
  const amount = Number(value);
  return Number.isFinite(amount) && amount !== 0;
}

export type BiltyPrintOptions = {
  includeBiltyRsDetails?: boolean;
  includeVehicleFreightDetails?: boolean;
  copyType?: BiltyCopyType;
  financialSummary?: BiltyPrintFinancialSummary | null;
};

export function printBilty(
  bilty: BiltyRow,
  t: Translate,
  language: AppLanguage,
  dir: Direction,
  options: BiltyPrintOptions = {}
): boolean {
  const popup = window.open("", "_blank", "width=980,height=800");
  if (!popup) return false;

  const {
    includeBiltyRsDetails = false,
    includeVehicleFreightDetails = false,
    copyType = "office",
    financialSummary = null,
  } = options;

  const party = relation(bilty.parties)?.name ?? "";
  const broker = relation(bilty.brokers)?.broker_name ?? "";
  const vehicle = relation(bilty.vehicles);
  const fromLocation = relation(bilty.from_location)?.name ?? bilty.from_city ?? "";
  const toLocation = relation(bilty.to_location)?.name ?? bilty.to_city ?? "";
  const vehicleNo = vehicle?.vehicle_no ?? bilty.external_vehicle_no ?? "";
  const vehicleType = vehicle?.vehicle_type ?? bilty.external_vehicle_type ?? "";
  const ownerName = vehicle?.owner_name ?? bilty.external_owner_name ?? "";
  const groupReference = `${bilty.movement_group?.outbound_bilty_no ?? bilty.booking_no} — ${t("bilty.movement.group")} ${bilty.bilty_group_id.replaceAll("-", "").slice(0, 6).toUpperCase()}`;
  const tripType = bilty.trip_type
    ? t(`bilty.tripTypes.${bilty.trip_type}`)
    : t("bilty.legacy");
  const freightType = bilty.freight_type
    ? t(`bilty.freightTypes.${bilty.freight_type}`)
    : t("bilty.legacy");
  const biltyType = bilty.bilty_type === "self_vehicle"
    ? t("bilty.biltyTypes.self")
    : bilty.bilty_type === "other_vehicle"
      ? t("bilty.biltyTypes.other")
      : t("bilty.legacy");

  const labels = {
    title: t("bilty.print.title"),
    biltyNo: t("bilty.form.biltyNo"),
    date: t("bilty.form.date"),
    loadingDate: t("bilty.form.loadingDate"),
    departureDate: t("bilty.form.departureDate"),
    arrivalDate: t("bilty.form.arrivalDate"),
    group: t("bilty.form.group"),
    tripType: t("bilty.form.tripType"),
    freightType: t("bilty.form.freightType"),
    biltyType: t("bilty.form.biltyType"),
    party: t("bilty.form.party"),
    broker: t("bilty.form.broker"),
    reference: t("bilty.form.reference"),
    from: t("bilty.form.fromSearch"),
    to: t("bilty.form.toSearch"),
    vehicle: t("bilty.form.vehicle"),
    vehicleType: t("bilty.form.vehicleType"),
    owner: t("bilty.form.ownerName"),
    sender: t("bilty.print.sender"),
    receiver: t("bilty.print.receiver"),
    items: t("bilty.items.title"),
    serial: t("bilty.print.serial"),
    goods: t("bilty.items.goods"),
    quantity: t("common.quantity"),
    weight: t("common.weight"),
    unit: t("common.unit"),
    remarks: t("common.remarks"),
    freight: t("bilty.form.freight"),
    container: t("bilty.container.title"),
    financial: t("bilty.financial.title"),
    originalVehicleFreight: t("bilty.financial.originalVehicleFreight"),
    adjustedVehicleFreight: t("bilty.financial.adjustedVehicleFreight"),
    brokerCommission: t("bilty.financial.brokerCommission"),
    overweightCharges: t("bilty.financial.overweightCharges"),
    loloCharges: t("bilty.financial.loloCharges"),
    detainCharges: t("bilty.financial.detainCharges"),
    actualVehicleCashPaid: t("bilty.financial.actualVehicleCashPaid"),
    parchiWithheldCommission: t("bilty.financial.parchiWithheldCommission"),
    vehicleEntitlementSettled: t("bilty.financial.vehicleEntitlementSettled"),
    vehicleOutstanding: t("bilty.financial.vehicleOutstanding"),
    senderSignature: t("bilty.print.senderSignature"),
    receiverSignature: t("bilty.print.receiverSignature"),
    authorizedSignature: t("bilty.print.authorizedSignature"),
    footer: t("bilty.print.footer"),
  };

  const itemRows = [...(bilty.bilty_items ?? [])]
    .sort((a, b) => a.line_no - b.line_no)
    .map((item, index) => `
      <tr>
        <td class="technical">${index + 1}</td>
        <td>${escapeHtml(item.goods_name)}</td>
        <td class="technical">${escapeHtml(item.quantity)}</td>
        <td class="technical">${escapeHtml(item.weight ?? "")}</td>
        <td>${escapeHtml(item.unit)}</td>
        <td>${escapeHtml(item.remarks ?? "")}</td>
      </tr>
    `)
    .join("");

  const containerDetails: Array<Array<number | string | null>> = [
    [t("bilty.container.number"), bilty.container_no],
    [t("bilty.container.size"), bilty.container_size],
    [t("bilty.container.weight"), bilty.container_weight],
    [t("bilty.container.serial"), bilty.container_serial],
    [t("bilty.container.port"), bilty.container_port],
    [t("bilty.container.clearingAgent"), bilty.clearing_agent],
    [t("bilty.container.shippingLine"), bilty.shipping_line],
    [t("bilty.container.cargo"), bilty.container_cargo],
  ].filter(([, value]) => hasText(value) && (typeof value !== "number" || value !== 0));

  const totalBiltyRs = amountOrZero(bilty.freight);
  const vehicleFreight = amountOrZero(bilty.vehicle_freight);
  const brokerCommission = amountOrZero(bilty.broker_commission);
  const overweightCharges = amountOrZero(bilty.overweight_charges);
  const loloCharges = amountOrZero(bilty.lolo_charges);
  const detainCharges = amountOrZero(bilty.detain_charges);
  const adjustedVehicleFreight = vehicleFreight - brokerCommission + overweightCharges + loloCharges + detainCharges;
  const addaCommission = totalBiltyRs - vehicleFreight;

  const summaryPartyFinancialRows: Array<[string, number | string | null | undefined]> = financialSummary ? [
    ["Total Bilty Freight", financialSummary.total_bilty_rs],
    ["Advance Received", financialSummary.advance_received],
    ["Later Receipts", financialSummary.later_received],
    ["Total Received", financialSummary.total_received],
    ["Balance Receivable", financialSummary.balance_receivable],
  ] : [];
  const biltyRsFinancialDetails: Array<Array<number | string | null>> = financialSummary
    ? summaryPartyFinancialRows.flatMap(([label, value]) => value === null || value === undefined ? [] : [[label, value]])
    : [
        ["Total Bilty Rs", bilty.freight],
        ["Bilty Advance Received", bilty.advance_bilty],
      ].filter(([, value]) => hasPositiveAmount(value));

  const hasVehicleFreightDetails = [
    vehicleFreight,
    brokerCommission,
    overweightCharges,
    loloCharges,
    detainCharges,
    amountOrZero(bilty.advance_vehicle),
    amountOrZero(financialSummary?.total_vehicle_paid),
    amountOrZero(financialSummary?.parchi_withheld_commission),
  ].some((value) => value !== 0);
  const vehicleFinancialDetails: Array<Array<number | string | null>> = hasVehicleFreightDetails
    ? [
        [labels.originalVehicleFreight, `Rs. ${money(vehicleFreight)}`],
        [labels.brokerCommission, `-Rs. ${money(brokerCommission)}`],
        [labels.overweightCharges, `+Rs. ${money(overweightCharges)}`],
        [labels.loloCharges, `+Rs. ${money(loloCharges)}`],
        [labels.detainCharges, `+Rs. ${money(detainCharges)}`],
        [labels.adjustedVehicleFreight, `Rs. ${money(adjustedVehicleFreight)}`],
        ...(hasPositiveAmount(bilty.advance_vehicle)
          ? [["Advance Vehicle", `Rs. ${money(bilty.advance_vehicle)}`] as Array<number | string | null>]
          : []),
      ]
    : [];
  if (financialSummary) {
    const actualCashPaid = financialSummary.actual_vehicle_cash_paid ?? financialSummary.total_vehicle_paid;
    const withheldCommission = financialSummary.parchi_withheld_commission ?? 0;
    vehicleFinancialDetails.push(
      [t("bilty.financial.laterVehiclePaid"), financialSummary.later_vehicle_paid == null ? null : `Rs. ${money(financialSummary.later_vehicle_paid)}`],
      [labels.actualVehicleCashPaid, actualCashPaid == null ? null : `Rs. ${money(actualCashPaid)}`],
      [labels.parchiWithheldCommission, `Rs. ${money(withheldCommission)}`],
      [labels.vehicleEntitlementSettled, financialSummary.vehicle_entitlement_settled == null
        ? actualCashPaid == null ? null : `Rs. ${money(amountOrZero(actualCashPaid) + amountOrZero(withheldCommission))}`
        : `Rs. ${money(financialSummary.vehicle_entitlement_settled)}`],
      [labels.vehicleOutstanding, financialSummary.vehicle_balance == null ? null : `Rs. ${money(financialSummary.vehicle_balance)}`],
    );
  }

  const combinedFinancialDetails: Array<Array<number | string | null>> =
    includeBiltyRsDetails && includeVehicleFreightDetails && addaCommission !== 0
      ? [["Adda Commission", addaCommission]]
      : [];
  const visibleBiltyFinancialDetails = copyType === "party"
    || (copyType === "office" && includeBiltyRsDetails)
    ? biltyRsFinancialDetails
    : [];
  const visibleVehicleFinancialDetails = copyType === "office" && includeVehicleFreightDetails
    ? vehicleFinancialDetails.filter(([, value]) => value !== null && value !== undefined)
    : [];
  const visibleCombinedFinancialDetails = copyType === "office"
    && includeBiltyRsDetails
    && includeVehicleFreightDetails
    ? combinedFinancialDetails
    : [];

  const primaryDetails: Array<Array<number | string | null>> = [
    [labels.biltyNo, bilty.booking_no],
    [labels.date, bilty.booking_date],
    [labels.loadingDate, bilty.loading_date],
    [labels.departureDate, bilty.departure_date],
    [labels.arrivalDate, bilty.arrival_date],
    [labels.group, groupReference],
    [labels.tripType, tripType],
    [labels.freightType, freightType],
    [labels.biltyType, biltyType],
    [labels.party, party],
    [labels.broker, broker],
    [labels.reference, bilty.reference_no],
    [labels.from, fromLocation],
    [labels.to, toLocation],
    [labels.vehicle, vehicleNo],
    [labels.vehicleType, vehicleType],
    [labels.owner, ownerName],
  ].filter(([, value]) => hasText(value));

  const senderValue = [bilty.sender_name, bilty.sender_phone].filter(hasText).join(" · ");
  const receiverValue = [bilty.receiver_name, bilty.receiver_phone].filter(hasText).join(" · ");

  const printBoxes = (rows: Array<Array<number | string | null>>, moneyValues = false) => rows
    .map(([label, value]) => `<div class="box"><strong>${escapeHtml(label)}</strong><span class="technical">${moneyValues ? `Rs. ${escapeHtml(money(value))}` : escapeHtml(value ?? "")}</span></div>`)
    .join("");

  void writeAddaBrandedPrintDocument(popup, `<!doctype html>
<html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}">
<head>
  <meta charset="utf-8" />
  <title>${escapeHtml(labels.title)} - ${escapeHtml(bilty.booking_no)}</title>
  <style>
    @page { size: A4; margin: 12mm; }
    * { box-sizing: border-box; }
    body { margin: 0; color: #0f172a; background: #fff; font-family: Arial, "Noto Nastaliq Urdu", sans-serif; direction: ${dir}; text-align: start; }
    .sheet { border: 2px solid #1d4ed8; padding: 20px; }
    .brand { text-align: center; border-bottom: 3px solid #1d4ed8; padding-bottom: 12px; }
    .brand h1 { margin: 0; color: #1d4ed8; font-size: 27px; }
    .brand h2 { margin: 7px 0 0; font-size: 21px; }
    .meta { display: grid; grid-template-columns: repeat(3, 1fr); gap: 9px; margin-top: 16px; }
    .box { min-height: 49px; border: 1px solid #94a3b8; border-radius: 5px; padding: 8px; }
    .box strong { display: block; color: #334155; font-size: 11px; margin-bottom: 4px; }
    .wide { grid-column: span 2; }
    .technical { direction: ltr; unicode-bidi: isolate; text-align: start; }
    table { width: 100%; border-collapse: collapse; margin-top: 18px; }
    th, td { border: 1px solid #64748b; padding: 8px; text-align: start; vertical-align: top; }
    th { background: #1d4ed8; color: #fff; }
    .total { display: flex; justify-content: flex-end; margin-top: 14px; font-size: 18px; font-weight: 800; }
    .section-title { margin: 18px 0 8px; padding: 6px 9px; background: #dbeafe; border-inline-start: 4px solid #1d4ed8; font-size: 16px; }
    .signatures { display: grid; grid-template-columns: repeat(3, 1fr); gap: 35px; margin-top: 65px; }
    .signature { border-top: 1px solid #334155; padding-top: 7px; text-align: center; }
    .footer { margin-top: 28px; border-top: 1px solid #cbd5e1; padding-top: 8px; text-align: center; color: #475569; font-size: 11px; }
    @media print { .sheet { border-color: #111827; } }
  </style>
</head>
<body>
  <main class="sheet">
    <header class="brand"><h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${escapeHtml(labels.title)}</h2></header>
    <section class="meta">
      ${printBoxes(primaryDetails)}
      ${hasText(senderValue) ? `<div class="box wide"><strong>${escapeHtml(labels.sender)}</strong>${escapeHtml(senderValue)}</div>` : ""}
      ${hasText(receiverValue) ? `<div class="box"><strong>${escapeHtml(labels.receiver)}</strong>${escapeHtml(receiverValue)}</div>` : ""}
    </section>
    ${containerDetails.length ? `<h3 class="section-title">${escapeHtml(labels.container)}</h3><section class="meta">${printBoxes(containerDetails)}</section>` : ""}
    <table aria-label="${escapeHtml(labels.items)}">
      <thead><tr><th>${escapeHtml(labels.serial)}</th><th>${escapeHtml(labels.goods)}</th><th>${escapeHtml(labels.quantity)}</th><th>${escapeHtml(labels.weight)}</th><th>${escapeHtml(labels.unit)}</th><th>${escapeHtml(labels.remarks)}</th></tr></thead>
      <tbody>${itemRows}</tbody>
    </table>
    ${visibleBiltyFinancialDetails.length ? `
      <h3 class="section-title">${copyType === "party" ? "Party Freight & Receipts" : "Party / Bilty Freight & Receipts"}</h3>
      <section class="meta">${printBoxes(visibleBiltyFinancialDetails, true)}</section>
      ${financialSummary?.payment_status ? `<section class="meta"><div class="box"><strong>Payment Status</strong>${escapeHtml(financialSummary.payment_status)}</div></section>` : ""}
    ` : ""}
    ${visibleVehicleFinancialDetails.length ? `
      <h3 class="section-title">Vehicle Freight Details</h3>
      <section class="meta">${printBoxes(visibleVehicleFinancialDetails)}</section>
    ` : ""}
    ${visibleCombinedFinancialDetails.length ? `
      <section class="meta">${printBoxes(visibleCombinedFinancialDetails, true)}</section>
    ` : ""}
    <section class="signatures"><div class="signature">${escapeHtml(labels.senderSignature)}</div><div class="signature">${escapeHtml(labels.receiverSignature)}</div><div class="signature">${escapeHtml(labels.authorizedSignature)}</div></section>
    <footer class="footer">${escapeHtml(labels.footer)}</footer>
  </main>
  <script>window.onload=function(){window.focus();window.print();};</script>
</body>
</html>`, bilty.adda_id, language === "ur" ? "ur" : "en");
  return true;
}

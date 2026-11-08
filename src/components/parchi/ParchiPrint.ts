import { escapeHtml } from "@/lib/print/escapeHtml";
import { getSafeLogoUrl } from "@/lib/print/foundation";
import { withPrintImageReadiness } from "@/lib/print/printAssets";

export type ParchiPrintEvent = {
  event_id: string | null;
  event_kind: "document_created" | "created" | "funding" | "settlement" | "recovery" | "reversal" | "amendment" | "cancellation" | "recourse" | null;
  event_date: string | null;
  event_amount: number | string | null;
  payment_method: string | null;
  reference_no: string | null;
  reason: string | null;
  reverses_event_id: string | null;
  commission_withheld?: number | string | null;
  actual_cash_amount?: number | string | null;
  funding_route?: "direct_to_vehicle" | "through_adda" | null;
  vehicle_settlement_reference?: string | null;
  event_payer_name?: string | null;
};

export type ParchiPrintData = {
  parchi_no: string;
  direction: "received" | "issued";
  issued_mode?: "standard" | "freight_financing";
  counterparty_name: string | null;
  primary_payer_name?: string | null;
  vehicle_no?: string | null;
  responsible_person_name?: string | null;
  responsible_phone?: string | null;
  document_date: string;
  document_amount: number | string;
  funding_due_date: string | null;
  settlement_due_date: string | null;
  net_funded: number | string;
  funding_status: string;
  net_settled: number | string;
  funded_outstanding: number | string;
  commission_withheld: number | string | null;
  actual_cash_amount: number | string | null;
  settlement_status: string;
  external_reference_no: string | null;
  remarks: string | null;
  references: Array<{ label: string; value: string }>;
  events: ParchiPrintEvent[];
};

export type ParchiPrintBrand = {
  addaName: string | null;
  logoUrl: string | null;
  showLogo: boolean;
  address: string | null;
  phone: string | null;
};

type PrintOptions = {
  parchi: ParchiPrintData;
  brand: ParchiPrintBrand;
  t: (key: string) => string;
  direction: "ltr" | "rtl";
  language: string;
};

function amount(value: number | string | null) {
  const numeric = Number(value ?? 0);
  return `₨ ${Number.isFinite(numeric) ? numeric.toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "0.00"}`;
}

export function openParchiPrint({ parchi, brand, t, direction, language }: PrintOptions): boolean {
  const popup = window.open("", "_blank", "width=820,height=1050");
  if (!popup) {
    window.alert(t("parchi.print.popupBlocked"));
    return false;
  }

  const value = (input: unknown) => escapeHtml(input);
  const label = (key: string) => value(t(key));
  const logo = brand.showLogo ? getSafeLogoUrl(brand.logoUrl) : null;
  const isFinance = parchi.issued_mode === "freight_financing";
  const title = isFinance ? t("parchi.issuedFinance") : parchi.direction === "received" ? t("parchi.received") : t("parchi.issued");
  const outstandingLabel = parchi.direction === "received"
    ? t("parchi.print.brokerPayable")
    : isFinance ? t("parchi.print.issuedFinanceReceivable") : t("parchi.print.otherAddaReceivable");
  const moneyEvents = parchi.events.filter((event) =>
    event.event_kind === "funding" || event.event_kind === "settlement" || event.event_kind === "recovery" || event.event_kind === "reversal" || (isFinance && event.event_kind === "recourse")
  );
  const reversedIds = new Set(moneyEvents
    .filter((event) => event.event_kind === "reversal" && event.reverses_event_id)
    .map((event) => event.reverses_event_id as string));
  const originalEvents = new Map(moneyEvents
    .filter((event) => event.event_id && (event.event_kind === "funding" || event.event_kind === "settlement" || event.event_kind === "recovery"))
    .map((event) => [event.event_id as string, event]));

  const eventRows = moneyEvents.map((event) => {
    const original = event.reverses_event_id ? originalEvents.get(event.reverses_event_id) : undefined;
    const eventLabel = event.event_kind === "funding"
      ? parchi.direction === "received" ? t("parchi.print.fundingReceived") : t("parchi.print.fundingDisbursed")
      : event.event_kind === "settlement" || event.event_kind === "recovery"
        ? parchi.direction === "received" ? t("parchi.print.repayment") : t("parchi.print.recovery")
        : event.event_kind === "recourse" ? t("parchi.events.recourse")
        : original?.event_kind === "funding"
          ? t("parchi.print.fundingReversal")
          : t("parchi.print.settlementReversal");
    const reversed = event.event_kind !== "reversal" && event.event_id && reversedIds.has(event.event_id);
    const valueSource = event.event_kind === "reversal" ? original : event;
    const eventCommission = valueSource?.commission_withheld == null
      ? null
      : Number(valueSource.commission_withheld) * (event.event_kind === "reversal" ? -1 : 1);
    const eventCash = valueSource?.actual_cash_amount == null
      ? null
      : Number(valueSource.actual_cash_amount) * (event.event_kind === "reversal" ? -1 : 1);
    const routeSource = event.event_kind === "reversal" ? original : event;
    const fundingRelated = event.event_kind === "funding" || original?.event_kind === "funding";
    const route = routeSource?.funding_route === "direct_to_vehicle" ? t("parchi.print.fundingRouteDirect")
      : routeSource?.funding_route === "through_adda" ? t("parchi.print.fundingRouteThroughAdda") : t("parchi.print.notRecorded");
    return `<tr>
      <td class="technical">${value(event.event_date || "—")}</td>
      <td>${value(eventLabel)}</td>
      <td class="technical amount">${value(amount(event.event_amount))}</td>
      ${parchi.direction === "received" ? `<td class="technical amount">${!fundingRelated ? "—" : eventCommission === null ? label("parchi.print.notRecorded") : value(amount(eventCommission))}</td><td class="technical amount">${!fundingRelated ? "—" : eventCash === null ? label("parchi.print.notRecorded") : value(amount(eventCash))}</td><td>${!fundingRelated ? "—" : value(route)}</td><td>${value(routeSource?.vehicle_settlement_reference || "—")}</td>` : ""}
      ${isFinance ? `<td class="technical amount">${event.event_kind === "funding" || (event.event_kind === "reversal" && original?.event_kind === "funding") ? eventCommission === null ? label("parchi.print.notRecorded") : value(amount(eventCommission)) : "—"}</td><td class="technical amount">${event.event_kind === "funding" || event.event_kind === "recovery" || event.event_kind === "reversal" ? eventCash === null ? label("parchi.print.notRecorded") : value(amount(eventCash)) : "—"}</td><td>${value(event.event_payer_name || "—")}</td>` : ""}
      <td>${value(event.payment_method || "—")}</td>
      <td>${event.reference_no ? value(event.reference_no) : "—"}</td>
      <td>${reversed ? label("parchi.print.reversed") : "—"}</td>
    </tr>`;
  }).join("");

  const referenceRows = parchi.references.map((reference) =>
    `<div class="field"><span>${value(reference.label)}</span><strong>${value(reference.value)}</strong></div>`
  ).join("");
  const contact = [brand.address, brand.phone].filter((item): item is string => Boolean(item?.trim())).map(value).join(" · ");
  const organization = brand.addaName?.trim() || (language === "ur" ? "اڈے کا نام دستیاب نہیں" : "Adda name unavailable");
  const amountRows = [
    [t("parchi.documentAmount"), amount(parchi.document_amount)],
    ...(parchi.direction === "received" || isFinance ? [
      [t(isFinance ? "parchi.upfrontCommission" : "parchi.print.commissionWithheld"), parchi.commission_withheld === null ? t("parchi.print.notRecorded") : amount(parchi.commission_withheld)],
      [t(isFinance ? "parchi.actualCashDisbursed" : "parchi.print.actualCash"), parchi.actual_cash_amount === null ? t("parchi.print.notRecorded") : amount(parchi.actual_cash_amount)],
    ] : []),
    [t("parchi.print.netFunded"), amount(parchi.net_funded)],
    [parchi.direction === "received" ? t("parchi.print.netRepayment") : t("parchi.print.netRecovery"), amount(parchi.net_settled)],
    [outstandingLabel, amount(parchi.funded_outstanding)],
  ].map(([name, total]) => `<div class="field money-field"><span>${value(name)}</span><strong class="technical">${value(total)}</strong></div>`).join("");
  const counterpartyLabel = isFinance ? t("parchi.primaryPayer") : parchi.direction === "received" ? t("parchi.broker") : t("parchi.otherAdda");

  popup.document.open();
  popup.document.write(withPrintImageReadiness(`<!doctype html>
    <html lang="${value(language)}" dir="${value(direction)}">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>${value(title)} — ${value(parchi.parchi_no)}</title>
        <style>
          @page { size: portrait; margin: 8mm; }
          * { box-sizing: border-box; }
          html, body { margin: 0; padding: 0; background: #fff; color: #111; }
          body { font-family: "Noto Nastaliq Urdu", "Jameel Noori Nastaleeq", "Nirmala UI", "Noto Naskh Arabic", Arial, "Segoe UI", Tahoma, sans-serif; font-size: 10pt; line-height: 1.35; direction: ${value(direction)}; }
          .sheet { width: 100%; max-width: 140mm; margin: 0 auto; padding: 4mm; border: 1px solid #222; }
          .brand { display: grid; grid-template-columns: 20mm minmax(0, 1fr); align-items: center; gap: 3mm; border-bottom: 1px solid #222; padding-bottom: 2.5mm; text-align: center; }
          .logo-slot { display: inline-flex; width: 20mm; height: 16mm; align-items: center; justify-content: center; }
          .logo { display: block; max-width: 100%; max-height: 100%; width: auto; height: auto; object-fit: contain; filter: grayscale(1); }
          .brand h1 { margin: 0; font-size: 15pt; line-height: 1.2; }
          .adda-name { margin-top: 1mm; font-size: 9pt; font-weight: 700; }
          .contact { margin-top: 1mm; font-size: 8pt; }
          .title { margin: 2.5mm 0; padding: 1.5mm; border: 1px solid #222; text-align: center; font-size: 13pt; font-weight: 800; }
          .fields { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5mm; }
          .field { min-width: 0; border: 1px solid #777; padding: 1.5mm 2mm; break-inside: avoid; page-break-inside: avoid; }
          .field span { display: block; font-size: 7.5pt; font-weight: 700; }
          .field strong { display: block; margin-top: .5mm; font-size: 9.5pt; overflow-wrap: anywhere; }
          .field small { display: block; margin-top: .7mm; font-size: 7pt; line-height: 1.25; }
          .wide { grid-column: 1 / -1; }
          h2 { margin: 2.5mm 0 1.5mm; font-size: 10pt; border-bottom: 1px solid #222; padding-bottom: 1mm; }
          .money-field strong { font-size: 10pt; }
          .technical { direction: ltr; unicode-bidi: isolate; text-align: left; }
          .amount { text-align: end; white-space: nowrap; }
          .statuses { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5mm; margin-top: 1.5mm; }
          .status { border: 1px solid #333; padding: 1.5mm 2mm; }
          .status span { display: block; font-size: 7.5pt; font-weight: 700; }
          .status strong { display: block; margin-top: .5mm; font-size: 9pt; }
          .due { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5mm; margin-top: 1.5mm; }
          .history { break-inside: auto; page-break-inside: auto; }
          table { width: 100%; border-collapse: collapse; table-layout: fixed; font-size: 7.5pt; }
          th, td { border: 1px solid #555; padding: 1.3mm; text-align: start; vertical-align: top; overflow-wrap: anywhere; }
          thead { display: table-header-group; }
          tr { break-inside: avoid; page-break-inside: avoid; }
          th { font-weight: 800; }
          .empty { text-align: center; padding: 3mm; }
          .signatures { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 4mm; margin-top: 12mm; break-inside: avoid; page-break-inside: avoid; }
          .signature { min-height: 13mm; border-top: 1px solid #222; padding-top: 1.5mm; text-align: center; font-size: 8pt; }
          .note { margin: 3mm 0 0; border-top: 1px solid #777; padding-top: 1.5mm; font-size: 7.5pt; text-align: center; }
          @media print { .sheet { border: 1px solid #222; margin-inline: auto; } }
          @media screen { body { padding: 10mm; background: #eee; } .sheet { background: #fff; box-shadow: 0 2px 12px #0002; } }
          @media (max-width: 480px) { .fields, .statuses, .due { grid-template-columns: 1fr 1fr; } }
        </style>
      </head>
      <body>
        <main class="sheet">
          <header class="brand">
            <span class="logo-slot">${logo ? `<img class="logo" src="${value(logo)}" alt="" onerror="this.remove()">` : ""}</span>
            <div><h1>${value(organization)}</h1>${contact ? `<div class="contact">${contact}</div>` : ""}</div>
          </header>
          <div class="title">${value(title)}</div>
          <section class="fields">
            <div class="field"><span>${label("parchi.print.parchiNumber")}</span><strong class="technical">${value(parchi.parchi_no)}</strong></div>
            <div class="field"><span>${label("parchi.documentDate")}</span><strong class="technical">${value(parchi.document_date)}</strong></div>
            <div class="field"><span>${label("parchi.externalReference")}</span><strong>${value(parchi.external_reference_no || "—")}</strong></div>
            <div class="field"><span>${value(counterpartyLabel)}</span><strong>${value(parchi.counterparty_name || "—")}</strong></div>
            ${isFinance ? `<div class="field"><span>${label("parchi.responsiblePerson")}</span><strong>${value(parchi.responsible_person_name || "—")}</strong></div><div class="field"><span>${label("common.vehicle")}</span><strong>${value(parchi.vehicle_no || "—")}</strong></div><div class="field"><span>${label("parchi.responsiblePhone")}</span><strong>${value(parchi.responsible_phone || "—")}</strong></div>` : ""}
          </section>
          <h2>${label("parchi.print.financialSummary")}</h2>
          <section class="fields">${amountRows}</section>
          <section class="statuses">
            <div class="status"><span>${label("parchi.fundingStatus")}</span><strong>${label(`parchi.statuses.${statusKey(parchi.funding_status)}`)}</strong></div>
            <div class="status"><span>${label("parchi.settlementStatus")}</span><strong>${label(`parchi.statuses.${statusKey(parchi.settlement_status)}`)}</strong></div>
          </section>
          <section class="due">
            <div class="field"><span>${label("parchi.fundingDueDate")}</span><strong class="technical">${value(parchi.funding_due_date || "—")}</strong><small>${label("parchi.fundingDueHelp")}</small></div>
            <div class="field"><span>${label("parchi.settlementDueDate")}</span><strong class="technical">${value(parchi.settlement_due_date || "—")}</strong><small>${label("parchi.settlementDueHelp")}</small></div>
          </section>
          ${referenceRows ? `<h2>${label("parchi.print.references")}</h2><section class="fields">${referenceRows}</section>` : ""}
          ${parchi.remarks ? `<h2>${label("parchi.remarks")}</h2><div class="field wide">${value(parchi.remarks)}</div>` : ""}
          <section class="history">
            <h2>${label("parchi.print.moneyHistory")}</h2>
            <table>
              <thead><tr><th>${label("parchi.eventDate")}</th><th>${label("parchi.event")}</th><th>${label("parchi.amount")}</th>${parchi.direction === "received" ? `<th>${label("parchi.print.commissionWithheld")}</th><th>${label("parchi.print.actualCash")}</th><th>${label("parchi.print.fundingRoute")}</th><th>${label("parchi.vehicleSettlement")}</th>` : isFinance ? `<th>${label("parchi.upfrontCommission")}</th><th>${label("parchi.actualCashDisbursed")}</th><th>${label("parchi.recoveryPayer")}</th>` : ""}<th>${label("parchi.paymentMethod")}</th><th>${label("parchi.referenceNo")}</th><th>${label("parchi.print.status")}</th></tr></thead>
              <tbody>${eventRows || `<tr><td class="empty" colspan="${parchi.direction === "received" || isFinance ? 9 : 6}">${label("parchi.noEvents")}</td></tr>`}</tbody>
            </table>
          </section>
          <section class="signatures">
            <div class="signature">${label("parchi.print.preparedBy")}</div>
            <div class="signature">${label("parchi.print.receiverSignature")}</div>
            <div class="signature">${label("parchi.print.stamp")}</div>
          </section>
          <p class="note">${label("parchi.print.note")}</p>
        </main>
        <script>window.onload=function(){window.focus();window.print();};</script>
      </body>
    </html>`));
  popup.document.close();
  return true;
}

function statusKey(status: string) {
  const keys: Record<string, string> = {
    Unfunded: "unfunded",
    "Partially Funded": "partiallyFunded",
    "Fully Funded": "fullyFunded",
    Cancelled: "cancelled",
    "Not Funded": "notFunded",
    Unpaid: "unpaid",
    "Partially Settled": "partiallySettled",
    Settled: "settled",
  };
  return keys[status] ?? status;
}

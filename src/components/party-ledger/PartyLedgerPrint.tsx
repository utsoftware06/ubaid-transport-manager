"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import type { PartyLedgerPeriod, PartyLedgerReport, PartyLedgerSummary } from "./types";
import LedgerStatementPrintButton, { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { partyLedgerPrintPresentation } from "./partyLedgerPrintPresentation";

type Translate = (key: string) => string;

type PrintOptions = {
  reports: PartyLedgerReport[];
  dateRange: string;
  title: string;
  t: Translate;
  dir: "ltr" | "rtl";
  language: string;
};

function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

export function openPartyLedgerPrint({
  reports,
  dateRange,
  title,
  t,
  dir,
  language,
}: PrintOptions): boolean {
  if (reports.length === 0) return false;

  const popup = window.open("", "_blank", "width=1200,height=850");
  if (!popup) {
    window.alert(t("partyLedger.messages.allowPopups"));
    return false;
  }

  const value = (input: unknown) => escapeHtml(input);
  const label = (key: string) => value(t(key));
  const sections = reports
    .map((report) => {
      const rows = report.trips
        .map(
          (trip) => `
            <tr>
              <td class="technical">${value(trip.loadingDate)}</td>
              <td class="technical">${value(trip.loadingNo)}</td>
              <td class="technical">${value(trip.bookingNo)}</td>
              <td>${value(trip.route)}</td>
              <td class="technical">${value(trip.vehicleNo)}</td>
              <td>${value(trip.driverName)}</td>
              <td class="technical">${value(formatAmount(trip.freight))}</td>
              <td class="technical">${value(formatAmount(trip.advance))}</td>
              <td class="technical">${value(formatAmount(trip.receiptPayments))}</td>
              <td class="technical">${value(formatAmount(trip.totalReceived))}</td>
              <td class="technical">${value(formatAmount(trip.remaining))}</td>
              <td>${label(`partyLedger.status.${trip.paymentStatus}`)}</td>
            </tr>`
        )
        .join("");

      return `
        <section class="party-section">
          <div class="party-heading">
            <div>
              <h2>${value(report.partyName)}</h2>
              <p>${label("partyLedger.fields.adda")}: ${value(report.addaName)}</p>
            </div>
            <div>
              <p>${label("partyLedger.print.dateRange")}</p>
              <strong class="technical">${value(dateRange)}</strong>
            </div>
          </div>
          <div class="summary">
            <div class="box"><span>${label("partyLedger.fields.totalBookings")}</span><strong class="technical">${report.totalBookings}</strong></div>
            <div class="box"><span>${label("partyLedger.fields.totalTrips")}</span><strong class="technical">${report.totalTrips}</strong></div>
            <div class="box"><span>${label("partyLedger.fields.totalFreight")}</span><strong class="technical">${value(formatAmount(report.totalFreight))}</strong></div>
            <div class="box"><span>${label("partyLedger.fields.totalAdvance")}</span><strong class="technical">${value(formatAmount(report.totalAdvance))}</strong></div>
            <div class="box"><span>${label("partyLedger.fields.receiptPayments")}</span><strong class="technical">${value(formatAmount(report.totalReceiptPayments))}</strong></div>
            <div class="box"><span>${label("partyLedger.fields.totalReceived")}</span><strong class="technical">${value(formatAmount(report.totalReceived))}</strong></div>
            <div class="box"><span>${label("partyLedger.fields.remaining")}</span><strong class="technical">${value(formatAmount(report.remainingBalance))}</strong></div>
          </div>
          <table>
            <thead>
              <tr>
                <th>${label("common.date")}</th>
                <th>${label("common.loadingNo")}</th>
                <th>${label("common.bookingNo")}</th>
                <th>${label("common.route")}</th>
                <th>${label("common.vehicle")}</th>
                <th>${label("common.driver")}</th>
                <th>${label("common.freight")}</th>
                <th>${label("common.advance")}</th>
                <th>${label("partyLedger.fields.receiptPayments")}</th>
                <th>${label("partyLedger.fields.totalReceived")}</th>
                <th>${label("partyLedger.fields.remaining")}</th>
                <th>${label("partyLedger.fields.status")}</th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
            <tfoot>
              <tr>
                <td colspan="6">${label("common.total")}</td>
                <td class="technical">${value(formatAmount(report.totalFreight))}</td>
                <td class="technical">${value(formatAmount(report.totalAdvance))}</td>
                <td class="technical">${value(formatAmount(report.totalReceiptPayments))}</td>
                <td class="technical">${value(formatAmount(report.totalReceived))}</td>
                <td class="technical">${value(formatAmount(report.remainingBalance))}</td>
                <td>${label(`partyLedger.status.${report.paymentStatus}`)}</td>
              </tr>
            </tfoot>
          </table>
        </section>`;
    })
    .join("");

  const addaIds = Array.from(new Set(reports.map((report) => report.addaId)));
  void writeAddaBrandedPrintDocument(popup, `<!doctype html>
    <html lang="${value(language)}" dir="${value(dir)}">
      <head>
        <title>${value(title)}</title>
        <style>
          @page { size: A4 landscape; margin: 10mm; }
          * { box-sizing: border-box; }
          body { margin: 0; color: #111827; background: white; font-family: Arial, sans-serif; direction: ${value(dir)}; text-align: start; }
          .document-title { text-align: center; margin-bottom: 24px; }
          .document-title h1 { margin: 0; font-size: 24px; }
          .document-title p { margin: 6px 0 0; font-weight: 700; }
          .party-section { break-after: page; page-break-after: always; }
          .party-section:last-child { break-after: auto; page-break-after: auto; }
          .party-heading { display: flex; justify-content: space-between; gap: 20px; border-bottom: 2px solid #2563eb; padding-bottom: 10px; margin-bottom: 12px; }
          .party-heading h2, .party-heading p { margin: 0; }
          .summary { display: grid; grid-template-columns: repeat(7, 1fr); gap: 7px; margin-bottom: 14px; }
          .box { border: 1px solid #cbd5e1; padding: 8px; border-radius: 6px; }
          .box span { display: block; font-size: 10px; font-weight: 700; color: #334155; }
          .box strong { display: block; margin-top: 4px; font-size: 12px; }
          table { width: 100%; border-collapse: collapse; font-size: 9px; }
          th, td { border: 1px solid #cbd5e1; padding: 6px; text-align: start; }
          th { background: #2563eb; color: white; }
          tfoot { font-weight: 800; background: #eff6ff; }
          .technical { direction: ltr; unicode-bidi: isolate; }
        </style>
      </head>
      <body>
        <header class="document-title">
          <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
          <p>${value(title)}</p>
        </header>
        ${sections}
        <script>
          window.onload = function () {
            window.focus();
            window.print();
            window.onafterprint = function () { window.close(); };
          };
        </script>
      </body>
  </html>`, addaIds.length === 1 ? addaIds[0] : null, language === "ur" ? "ur" : "en");
  popup.document.close();
  return true;
}

type Props = {
  reports: PartyLedgerReport[];
  summary?: PartyLedgerSummary;
  dateRange: string;
  period?: { period: PartyLedgerPeriod; fromDate: string; toDate: string };
};

export function PartyLedgerPrintAction({ reports, summary, dateRange, period, title }: Props & { title: string }) {
  const { t, dir, language } = useLanguage();
  const addaId = singleResolvedAddaId(reports.map((report) => report.addaId));
  const unavailableReason = reports.length && !addaId
    ? (language === "ur" ? "ایک ہی تصدیق شدہ اڈے کی رپورٹ منتخب کریں۔" : "Filter to one verified Adda before printing this combined statement.")
    : undefined;
  return <>
    <LedgerStatementPrintButton addaId={addaId} documentType="party_ledger" initialLanguage={language} makePresentation={(printLanguage) => partyLedgerPrintPresentation(reports, summary, dateRange, printLanguage, period)} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={() => openPartyLedgerPrint({ reports, dateRange, title, t, dir, language })} unavailableReason={unavailableReason}>
      <button type="button" disabled={reports.length === 0 || !addaId} title={unavailableReason} className="rounded-lg bg-green-600 px-5 py-3 font-bold text-white hover:bg-green-700 focus-visible:ring-2 focus-visible:ring-green-500 disabled:cursor-not-allowed disabled:bg-green-300">{title}</button>
    </LedgerStatementPrintButton>
    {unavailableReason ? <p className="mt-2 max-w-sm text-xs font-semibold text-amber-800">{unavailableReason}</p> : null}
  </>;
}

export default function PartyLedgerPrint(props: Props & { summary: PartyLedgerSummary }) {
  const { t } = useLanguage();
  return <PartyLedgerPrintAction {...props} title={t("partyLedger.actions.printAll")} />;
}

"use client";

import { useState } from "react";
import {
  type TripRecord,
  type TripSummary,
  formatAmount,
  tripStatusTranslationKey,
} from "./TripManagement";
import { useLanguage } from "@/contexts/LanguageContext";
import PrintAddaLogo from "@/components/print/PrintAddaLogo";
import { usePrintBranding } from "@/lib/print/usePrintAddaName";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { bilingual, printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { waitForPrintImages } from "@/lib/print/printAssets";

type Props = {
  trips: TripRecord[];
  summary: TripSummary;
  selectedTrip: TripRecord | null;
};

type PrintMode = "all" | "single";

function formatDate(value: string | null) {
  if (!value) return "-";
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return "-";
  return date.toLocaleDateString("en-PK");
}

function formatDateTime(value: string | null) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  return date.toLocaleString("en-PK");
}

function displayValue(value: string | null) {
  return value && value.trim() ? value : "-";
}

export default function TripPrint({ trips, summary, selectedTrip }: Props) {
  const { t, dir, language } = useLanguage();
  const [printMode, setPrintMode] = useState<PrintMode>("all");
  const printOwnerIds = (printMode === "single" && selectedTrip ? [selectedTrip] : trips).map((trip) => trip.adda_id);
  const addaId = singleResolvedAddaId(printOwnerIds);
  const branding = usePrintBranding(addaId);
  const addaName = branding?.addaName.trim() || (language === "ur" ? "اڈے کا نام دستیاب نہیں" : "Adda name unavailable");
  const modulePrint = useModuleTransportPrint("reports", addaId, language === "ur" ? "ur" : "en");

  function printAfterRender() {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        void waitForPrintImages(document).then(() => window.print());
      });
    });
  }

  function handlePrintAll() {
    if (!addaId || trips.some((trip) => !trip.adda_id)) return;
    const presentation: ModulePrintPresentation = {
      documentType: "reports",
      title: printLabel("tripManagement.print.reportTitle"),
      subtitle: bilingual(`${trips.length} filtered trips`, `${trips.length} فلٹر شدہ ٹرپس`),
      fields: [],
      tables: [{
        title: printLabel("tripManagement.print.reportTitle"),
        columns: [printLabel("tripManagement.form.tripNumber"), printLabel("common.date"), printLabel("common.vehicle"), printLabel("common.driver"), printLabel("common.customer"), printLabel("common.route"), printLabel("common.freight"), printLabel("tripManagement.table.received"), printLabel("common.balance"), printLabel("common.expense"), printLabel("common.profit"), printLabel("common.status")],
        rows: trips.map((trip) => [printValue(trip.trip_no), printValue(trip.trip_date), printValue(trip.vehicleNo), printValue(trip.driverName), printValue(trip.customer_name), printValue(`${trip.loading_from} → ${trip.delivery_to}`), printValue(formatAmount(trip.freight_amount)), printValue(formatAmount(trip.received_amount)), printValue(formatAmount(trip.payment_balance)), printValue(formatAmount(trip.total_expense)), printValue(formatAmount(trip.net_profit)), printLabel(tripStatusTranslationKey(trip.trip_status))]),
      }],
      totals: [
        { label: printLabel("tripManagement.cards.totalFreight"), value: printValue(formatAmount(summary.totalFreight)) },
        { label: printLabel("tripManagement.cards.totalReceived"), value: printValue(formatAmount(summary.totalReceived)) },
        { label: printLabel("tripManagement.cards.totalBalance"), value: printValue(formatAmount(summary.totalBalance)) },
        { label: printLabel("tripManagement.cards.totalExpenses"), value: printValue(formatAmount(summary.totalExpenses)) },
        { label: printLabel("tripManagement.cards.netProfit"), value: printValue(formatAmount(summary.totalProfit)) },
      ],
    };
    modulePrint.openPresentation(presentation, () => { setPrintMode("all"); printAfterRender(); }, addaId);
  }

  function handlePrintSelected() {
    if (!selectedTrip) return;
    if (!selectedTrip.adda_id) return;
    const presentation: ModulePrintPresentation = {
      documentType: "reports",
      title: printLabel("tripManagement.print.recordTitle"),
      documentNo: printValue(selectedTrip.trip_no),
      documentDate: printValue(selectedTrip.trip_date),
      fields: [
        { label: printLabel("common.vehicle"), value: printValue(selectedTrip.vehicleNo) },
        { label: printLabel("common.driver"), value: printValue(selectedTrip.driverName) },
        { label: printLabel("common.customer"), value: printValue(selectedTrip.customer_name) },
        { label: printLabel("common.route"), value: printValue(`${selectedTrip.loading_from} → ${selectedTrip.delivery_to}`) },
        { label: printLabel("common.status"), value: printLabel(tripStatusTranslationKey(selectedTrip.trip_status)) },
      ],
      totals: [
        { label: printLabel("common.freight"), value: printValue(formatAmount(selectedTrip.freight_amount)) },
        { label: printLabel("tripManagement.table.received"), value: printValue(formatAmount(selectedTrip.received_amount)) },
        { label: printLabel("common.balance"), value: printValue(formatAmount(selectedTrip.payment_balance)) },
        { label: printLabel("common.expense"), value: printValue(formatAmount(selectedTrip.total_expense)) },
        { label: printLabel("common.profit"), value: printValue(formatAmount(selectedTrip.net_profit)) },
      ],
    };
    modulePrint.openPresentation(presentation, () => { setPrintMode("single"); printAfterRender(); }, selectedTrip.adda_id);
  }

  return (
    <>
      <section dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">
              {t("tripManagement.print.title")}
            </h2>
            <p className="mt-2 text-sm font-medium text-gray-900">
              {t("tripManagement.print.description")}
            </p>
            <p className="mt-4 text-sm font-bold text-gray-900">
              {t("tripManagement.print.filteredTrips")}:{" "}
              <span dir="ltr">{trips.length}</span> |{" "}
              {t("tripManagement.cards.totalFreight")}:{" "}
              <span dir="ltr">{formatAmount(summary.totalFreight)}</span> |{" "}
              {t("tripManagement.print.selected")}:{" "}
              <span dir="ltr">
                {selectedTrip
                  ? selectedTrip.trip_no
                  : t("tripManagement.print.none")}
              </span>
            </p>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row lg:flex-col">
           <button
  type="button"
  onClick={handlePrintAll}
  disabled={trips.length === 0 || !addaId}
  className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-300"
>
  {t("tripManagement.print.printAll")}
</button>
            <button
              type="button"
              onClick={handlePrintSelected}
              disabled={!selectedTrip || !selectedTrip.adda_id}
              className="rounded-lg bg-gray-900 px-6 py-3 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:bg-gray-500"
            >
              {t("tripManagement.print.printSelected")}
            </button>
          </div>
        </div>
      </section>

      {modulePrint.dialog}

      <section className="trip-print-area" dir={dir} lang={language}>
        {printMode === "all" && (
          <div className="print-document">
            <div className="print-header">
              <div>
                <PrintAddaLogo branding={branding} />
                <h1>{t("tripManagement.print.reportTitle")}</h1>
                <p>{addaName}</p>
              </div>
              <div className="print-meta">
                <p>{t("tripManagement.print.generated")}: <span className="technical">{formatDateTime(new Date().toISOString())}</span></p>
                <p>{t("tripManagement.cards.totalTrips")}: <span className="technical">{summary.totalTrips}</span></p>
              </div>
            </div>

            <div className="print-summary">
              <div><span>{t("tripManagement.cards.totalFreight")}</span><strong className="technical">{formatAmount(summary.totalFreight)}</strong></div>
              <div><span>{t("tripManagement.cards.totalReceived")}</span><strong className="technical">{formatAmount(summary.totalReceived)}</strong></div>
              <div><span>{t("tripManagement.cards.totalBalance")}</span><strong className="technical">{formatAmount(summary.totalBalance)}</strong></div>
              <div><span>{t("tripManagement.cards.totalExpenses")}</span><strong className="technical">{formatAmount(summary.totalExpenses)}</strong></div>
              <div><span>{t("tripManagement.cards.netProfit")}</span><strong className="technical">{formatAmount(summary.totalProfit)}</strong></div>
            </div>

            <table className="print-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>{t("tripManagement.form.tripNumber")}</th>
                  <th>{t("common.date")}</th>
                  <th>{t("common.vehicle")}</th>
                  <th>{t("common.driver")}</th>
                  <th>{t("common.customer")}</th>
                  <th>{t("common.route")}</th>
                  <th>{t("common.freight")}</th>
                  <th>{t("tripManagement.table.received")}</th>
                  <th>{t("common.balance")}</th>
                  <th>{t("common.expense")}</th>
                  <th>{t("common.profit")}</th>
                  <th>{t("common.status")}</th>
                </tr>
              </thead>
              <tbody>
                {trips.map((trip, index) => (
                  <tr key={trip.id}>
                    <td>{index + 1}</td>
                    <td className="technical">{trip.trip_no}</td>
                    <td className="technical">{formatDate(trip.trip_date)}</td>
                    <td className="technical">{trip.vehicleNo}</td>
                    <td>{trip.driverName}</td>
                    <td>{displayValue(trip.customer_name)}</td>
                    <td>{trip.loading_from} {dir === "rtl" ? "←" : "→"} {trip.delivery_to}</td>
                    <td className="technical">{formatAmount(trip.freight_amount)}</td>
                    <td className="technical">{formatAmount(trip.received_amount)}</td>
                    <td className="technical">{formatAmount(trip.payment_balance)}</td>
                    <td className="technical">{formatAmount(trip.total_expense)}</td>
                    <td className="technical">{formatAmount(trip.net_profit)}</td>
                    <td>{t(tripStatusTranslationKey(trip.trip_status))}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {printMode === "single" && selectedTrip && (
          <div className="print-document print-single">
            <div className="print-header">
              <div>
                <PrintAddaLogo branding={branding} />
                <h1>{t("tripManagement.print.recordTitle")}</h1>
                <p>{addaName}</p>
              </div>
              <div className="print-meta">
                <p>{t("tripManagement.print.printed")}: <span className="technical">{formatDateTime(new Date().toISOString())}</span></p>
                <p>{t("tripManagement.form.tripNumber")}: <span className="technical">{selectedTrip.trip_no}</span></p>
              </div>
            </div>

            <div className="print-detail-grid">
              {[
                [t("tripManagement.form.tripNumber"), selectedTrip.trip_no],
                [t("tripManagement.form.tripDate"), formatDate(selectedTrip.trip_date)],
                [t("common.vehicle"), selectedTrip.vehicleNo],
                [t("common.owner"), selectedTrip.ownerName],
                [t("common.driver"), selectedTrip.driverName],
                [t("tripManagement.details.bookingCustomer"), selectedTrip.bookingCustomerName],
                [t("tripManagement.details.customerName"), displayValue(selectedTrip.customer_name)],
                [t("tripManagement.details.customerPhone"), displayValue(selectedTrip.customer_phone)],
                [t("tripManagement.form.loadingFrom"), selectedTrip.loading_from],
                [t("tripManagement.form.deliveryTo"), selectedTrip.delivery_to],
                [t("tripManagement.details.goodsDescription"), displayValue(selectedTrip.goods_description)],
                [t("tripManagement.form.freightAmount"), formatAmount(selectedTrip.freight_amount)],
                [t("tripManagement.form.customerAdvance"), formatAmount(selectedTrip.customer_advance)],
                [t("tripManagement.form.driverAdvance"), formatAmount(selectedTrip.driver_advance)],
                [t("tripManagement.form.totalExpense"), formatAmount(selectedTrip.total_expense)],
                [t("tripManagement.form.receivedAmount"), formatAmount(selectedTrip.received_amount)],
                [t("tripManagement.form.paymentBalance"), formatAmount(selectedTrip.payment_balance)],
                [t("tripManagement.cards.netProfit"), formatAmount(selectedTrip.net_profit)],
                [t("common.status"), t(tripStatusTranslationKey(selectedTrip.trip_status))],
                [t("tripManagement.form.startDate"), formatDate(selectedTrip.start_date)],
                [t("tripManagement.form.completionDate"), formatDate(selectedTrip.completion_date)],
                [t("common.remarks"), displayValue(selectedTrip.remarks)],
              ].map(([label, value]) => (
                <div key={label}>
                  <span>{label}</span>
                  <strong dir="auto">{value}</strong>
                </div>
              ))}
            </div>
          </div>
        )}
      </section>

      <style jsx global>{`
        .trip-print-area {
          display: none;
          direction: ${dir};
        }

        @media print {
          @page {
            size: A4 landscape;
            margin: 10mm;
          }

          body * {
            visibility: hidden !important;
          }

          .trip-print-area,
          .trip-print-area * {
            visibility: visible !important;
          }

          .trip-print-area {
            display: block !important;
            position: absolute !important;
            inset: 0 auto auto 0 !important;
            width: 100% !important;
            background: #ffffff !important;
            color: #000000 !important;
            font-family: Arial, sans-serif !important;
            direction: ${dir} !important;
          }

          .print-header {
            display: flex !important;
            justify-content: space-between !important;
            border-bottom: 3px solid #000000 !important;
            padding-bottom: 12px !important;
            margin-bottom: 14px !important;
          }

          .print-header h1 {
            margin: 0 !important;
            font-size: 24px !important;
            font-weight: 800 !important;
            color: #000000 !important;
          }

          .print-header p,
          .print-meta p {
            margin: 4px 0 0 !important;
            font-size: 12px !important;
            font-weight: 700 !important;
            color: #000000 !important;
          }

          .print-meta {
            text-align: end !important;
          }

          .print-summary {
            display: grid !important;
            grid-template-columns: repeat(5, 1fr) !important;
            gap: 8px !important;
            margin-bottom: 14px !important;
          }

          .print-summary div,
          .print-detail-grid div {
            border: 1px solid #000000 !important;
            padding: 8px !important;
            break-inside: avoid !important;
          }

          .print-summary span,
          .print-detail-grid span {
            display: block !important;
            margin-bottom: 4px !important;
            font-size: 10px !important;
            font-weight: 800 !important;
            text-transform: uppercase !important;
            color: #000000 !important;
          }

          .print-summary strong,
          .print-detail-grid strong {
            display: block !important;
            font-size: 13px !important;
            font-weight: 800 !important;
            color: #000000 !important;
          }

          .print-table {
            width: 100% !important;
            border-collapse: collapse !important;
            font-size: 9px !important;
          }

          .print-table thead {
            display: table-header-group !important;
          }

          .print-table tr {
            break-inside: avoid !important;
          }

          .print-table th,
          .print-table td {
            border: 1px solid #000000 !important;
            padding: 5px !important;
            text-align: start !important;
            color: #000000 !important;
          }

          .print-table th {
            background: #e5e7eb !important;
            font-weight: 800 !important;
          }

          .print-single {
            max-width: 900px !important;
            margin: 0 auto !important;
          }

          .print-detail-grid {
            display: grid !important;
            grid-template-columns: repeat(2, 1fr) !important;
            gap: 10px !important;
          }

          .technical {
            direction: ltr !important;
            unicode-bidi: isolate !important;
          }
        }
      `}</style>
    </>
  );
}

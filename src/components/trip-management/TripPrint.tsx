"use client";

import { useState } from "react";
import { type TripRecord, type TripSummary, formatAmount } from "./TripManagement";

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
  const [printMode, setPrintMode] = useState<PrintMode>("all");

  function printAfterRender() {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        window.print();
      });
    });
  }

  function handlePrintAll() {
    setPrintMode("all");
    printAfterRender();
  }

  function handlePrintSelected() {
    if (!selectedTrip) return;
    setPrintMode("single");
    printAfterRender();
  }

  return (
    <>
      <section className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">Trip Printing</h2>
            <p className="mt-2 text-sm font-medium text-gray-900">
              Print filtered trip reports or the currently selected trip record.
            </p>
            <p className="mt-4 text-sm font-bold text-gray-900">
              Filtered Trips: {trips.length} | Total Freight:{" "}
              {formatAmount(summary.totalFreight)} | Selected:{" "}
              {selectedTrip ? selectedTrip.trip_no : "None"}
            </p>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row lg:flex-col">
           <button
  type="button"
  onClick={handlePrintAll}
  disabled={trips.length === 0}
  className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-300"
>
  Print All Filtered Trips
</button>
            <button
              type="button"
              onClick={handlePrintSelected}
              disabled={!selectedTrip}
              className="rounded-lg bg-gray-900 px-6 py-3 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:bg-gray-500"
            >
              Print Selected Trip
            </button>
          </div>
        </div>
      </section>

      <section className="trip-print-area">
        {printMode === "all" && (
          <div className="print-document">
            <div className="print-header">
              <div>
                <h1>Trip / Chakkar Report</h1>
                <p>UT Software</p>
              </div>
              <div className="print-meta">
                <p>Generated: {formatDateTime(new Date().toISOString())}</p>
                <p>Total Trips: {summary.totalTrips}</p>
              </div>
            </div>

            <div className="print-summary">
              <div><span>Total Freight</span><strong>{formatAmount(summary.totalFreight)}</strong></div>
              <div><span>Total Received</span><strong>{formatAmount(summary.totalReceived)}</strong></div>
              <div><span>Total Balance</span><strong>{formatAmount(summary.totalBalance)}</strong></div>
              <div><span>Total Expenses</span><strong>{formatAmount(summary.totalExpenses)}</strong></div>
              <div><span>Net Profit</span><strong>{formatAmount(summary.totalProfit)}</strong></div>
            </div>

            <table className="print-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Trip No</th>
                  <th>Date</th>
                  <th>Vehicle</th>
                  <th>Driver</th>
                  <th>Customer</th>
                  <th>Route</th>
                  <th>Freight</th>
                  <th>Received</th>
                  <th>Balance</th>
                  <th>Expense</th>
                  <th>Profit</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {trips.map((trip, index) => (
                  <tr key={trip.id}>
                    <td>{index + 1}</td>
                    <td>{trip.trip_no}</td>
                    <td>{formatDate(trip.trip_date)}</td>
                    <td>{trip.vehicleNo}</td>
                    <td>{trip.driverName}</td>
                    <td>{displayValue(trip.customer_name)}</td>
                    <td>{trip.loading_from} → {trip.delivery_to}</td>
                    <td>{formatAmount(trip.freight_amount)}</td>
                    <td>{formatAmount(trip.received_amount)}</td>
                    <td>{formatAmount(trip.payment_balance)}</td>
                    <td>{formatAmount(trip.total_expense)}</td>
                    <td>{formatAmount(trip.net_profit)}</td>
                    <td>{trip.trip_status}</td>
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
                <h1>Trip / Chakkar Record</h1>
                <p>UT Software</p>
              </div>
              <div className="print-meta">
                <p>Printed: {formatDateTime(new Date().toISOString())}</p>
                <p>Trip No: {selectedTrip.trip_no}</p>
              </div>
            </div>

            <div className="print-detail-grid">
              {[
                ["Trip No", selectedTrip.trip_no],
                ["Trip Date", formatDate(selectedTrip.trip_date)],
                ["Vehicle", selectedTrip.vehicleNo],
                ["Owner", selectedTrip.ownerName],
                ["Driver", selectedTrip.driverName],
                ["Booking Customer", selectedTrip.bookingCustomerName],
                ["Customer Name", displayValue(selectedTrip.customer_name)],
                ["Customer Phone", displayValue(selectedTrip.customer_phone)],
                ["Loading From", selectedTrip.loading_from],
                ["Delivery To", selectedTrip.delivery_to],
                ["Goods Description", displayValue(selectedTrip.goods_description)],
                ["Freight Amount", formatAmount(selectedTrip.freight_amount)],
                ["Customer Advance", formatAmount(selectedTrip.customer_advance)],
                ["Driver Advance", formatAmount(selectedTrip.driver_advance)],
                ["Total Expense", formatAmount(selectedTrip.total_expense)],
                ["Received Amount", formatAmount(selectedTrip.received_amount)],
                ["Payment Balance", formatAmount(selectedTrip.payment_balance)],
                ["Net Profit", formatAmount(selectedTrip.net_profit)],
                ["Status", selectedTrip.trip_status],
                ["Start Date", formatDate(selectedTrip.start_date)],
                ["Completion Date", formatDate(selectedTrip.completion_date)],
                ["Remarks", displayValue(selectedTrip.remarks)],
              ].map(([label, value]) => (
                <div key={label}>
                  <span>{label}</span>
                  <strong>{value}</strong>
                </div>
              ))}
            </div>
          </div>
        )}
      </section>

      <style jsx global>{`
        .trip-print-area {
          display: none;
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
            text-align: right !important;
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
            text-align: left !important;
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
        }
      `}</style>
    </>
  );
}
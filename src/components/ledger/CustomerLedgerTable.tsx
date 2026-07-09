"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  type CustomerLedgerRow,
  formatAmount,
} from "./CustomerLedger";
type Props = {
  rows: CustomerLedgerRow[];
  search: string;
  setSearch: Dispatch<SetStateAction<string>>;
  isLoading: boolean;
  errorMessage: string;
};

function getStatusClass(status: CustomerLedgerRow["paymentStatus"]) {
  if (status === "Paid") {
    return "bg-green-100 text-green-700 border-green-200";
  }

  if (status === "Partial") {
    return "bg-yellow-100 text-yellow-700 border-yellow-200";
  }

  return "bg-red-100 text-red-700 border-red-200";
}

export default function CustomerLedgerTable({
  rows,
  search,
  setSearch,
  isLoading,
  errorMessage,
}: Props) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Customer Payment Ledger
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Booking-wise freight recovery and pending balance.
          </p>
        </div>

        <input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search customer ledger..."
          className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100 lg:max-w-sm"
        />
      </div>

      {isLoading && (
        <div className="mt-6 rounded-lg border border-blue-100 bg-blue-50 p-4 text-sm font-bold text-blue-700">
          Loading customer ledger...
        </div>
      )}

      {!isLoading && errorMessage && (
        <div className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      {!isLoading && !errorMessage && rows.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-200 bg-gray-50 p-6 text-center text-sm font-bold text-gray-900">
          No customer ledger records found.
        </div>
      )}

      {!isLoading && !errorMessage && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto">
          <table className="w-full min-w-[1200px] border-collapse text-left">
            <thead>
              <tr className="bg-blue-600 text-white">
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Date
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Booking No
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Sender
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Receiver
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                  Route
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Freight
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Advance
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Receipts
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Total Received
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                  Remaining
                </th>
                <th className="whitespace-nowrap px-4 py-3 text-center text-sm font-bold">
                  Status
                </th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-200">
              {rows.map((row) => (
                <tr
                  key={row.bookingId}
                  className="bg-white text-gray-900 hover:bg-gray-50"
                >
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.date}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-bold">
                    {row.bookingNo}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.sender}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.receiver}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-sm font-semibold">
                    {row.route}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatAmount(row.freight)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatAmount(row.advanceAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold">
                    {formatAmount(row.receiptAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold text-green-700">
                    {formatAmount(row.totalReceived)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right text-sm font-bold text-red-700">
                    {formatAmount(row.remainingAmount)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-center">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        row.paymentStatus
                      )}`}
                    >
                      {row.paymentStatus}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>

            <tfoot>
              <tr className="border-t-2 border-gray-300 bg-gray-50 text-gray-900">
                <td
                  colSpan={5}
                  className="px-4 py-4 text-sm font-extrabold"
                >
                  Total
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(
                    rows.reduce((total, row) => total + row.freight, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(
                    rows.reduce((total, row) => total + row.advanceAmount, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold">
                  {formatAmount(
                    rows.reduce((total, row) => total + row.receiptAmount, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold text-green-700">
                  {formatAmount(
                    rows.reduce((total, row) => total + row.totalReceived, 0)
                  )}
                </td>
                <td className="px-4 py-4 text-right text-sm font-extrabold text-red-700">
                  {formatAmount(
                    rows.reduce((total, row) => total + row.remainingAmount, 0)
                  )}
                </td>
                <td className="px-4 py-4" />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}
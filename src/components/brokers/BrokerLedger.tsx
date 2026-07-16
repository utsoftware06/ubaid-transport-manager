"use client";

import {
  type BrokerRow,
  type BrokerTransactionRow,
  formatAmount,
  getTransactionEffect,
} from "./Brokers";

type Props = {
  broker: BrokerRow;
  onClose: () => void;
  onEditTransaction: (transaction: BrokerTransactionRow) => void;
  onDeleteTransaction: (transaction: BrokerTransactionRow) => void;
  isDeleting: boolean;
};

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getStatusClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") return "border-green-200 bg-green-100 text-green-700";
  return "border-blue-200 bg-blue-100 text-blue-700";
}

function isDebit(transaction: BrokerTransactionRow) {
  return getTransactionEffect(transaction.transactionType, transaction.amount) > 0;
}

export default function BrokerLedger({
  broker,
  onClose,
  onEditTransaction,
  onDeleteTransaction,
  isDeleting,
}: Props) {
  function handlePrintEntry(transaction: BrokerTransactionRow) {
    const printWindow = window.open("", "_blank", "width=900,height=700");

    if (!printWindow) {
      alert("Please allow popups to print broker entry.");
      return;
    }

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Broker Entry - ${escapeHtml(broker.brokerName)}</title>
          <style>
            body { margin: 0; padding: 32px; color: #111827; font-family: Arial, sans-serif; }
            .slip { max-width: 850px; margin: 0 auto; border: 1px solid #d1d5db; border-radius: 10px; padding: 28px; }
            .header { display: flex; justify-content: space-between; border-bottom: 2px solid #111827; padding-bottom: 18px; margin-bottom: 22px; }
            h1 { margin: 0; font-size: 28px; }
            h2 { margin: 6px 0 0; font-size: 18px; }
            .details { display: grid; grid-template-columns: repeat(2, 1fr); gap: 14px 24px; font-size: 15px; }
            .details div { border-bottom: 1px solid #e5e7eb; padding-bottom: 8px; }
          </style>
        </head>
        <body>
          <div class="slip">
            <div class="header">
              <div>
                <h1>UT Software</h1>
                <h2>Broker Transaction</h2>
              </div>
              <div>
                <strong>Date:</strong> ${escapeHtml(transaction.transactionDate)}
              </div>
            </div>
            <div class="details">
              <div><strong>Broker:</strong> ${escapeHtml(broker.brokerName)}</div>
              <div><strong>Type:</strong> ${escapeHtml(transaction.transactionType)}</div>
              <div><strong>Amount:</strong> ${escapeHtml(formatAmount(transaction.amount))}</div>
              <div><strong>Payment:</strong> ${escapeHtml(transaction.paymentMethod)}</div>
              <div><strong>Reference:</strong> ${escapeHtml(transaction.referenceNo)}</div>
              <div><strong>Loading:</strong> ${escapeHtml(transaction.loadingNo)}</div>
              <div><strong>Vehicle:</strong> ${escapeHtml(transaction.vehicleNo)}</div>
              <div><strong>Driver:</strong> ${escapeHtml(transaction.driverName)}</div>
              <div><strong>Description:</strong> ${escapeHtml(transaction.description)}</div>
              <div><strong>Remarks:</strong> ${escapeHtml(transaction.remarks)}</div>
              <div><strong>Running Balance:</strong> ${escapeHtml(formatAmount(transaction.runningBalance))}</div>
            </div>
          </div>
          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  function handlePrintLedger() {
    const printWindow = window.open("", "_blank", "width=1200,height=800");

    if (!printWindow) {
      alert("Please allow popups to print broker ledger.");
      return;
    }

    const rowsHtml =
      broker.transactions.length > 0
        ? broker.transactions
            .map((transaction) => {
              const debit = isDebit(transaction) ? transaction.amount : 0;
              const credit = !isDebit(transaction) ? transaction.amount : 0;

              return `
                <tr>
                  <td>${escapeHtml(transaction.transactionDate)}</td>
                  <td>${escapeHtml(transaction.transactionType)}</td>
                  <td>${escapeHtml(transaction.description)}</td>
                  <td>${escapeHtml(transaction.loadingNo)}</td>
                  <td>${escapeHtml(transaction.vehicleNo)}</td>
                  <td>${escapeHtml(transaction.driverName)}</td>
                  <td>${escapeHtml(transaction.paymentMethod)}</td>
                  <td>${escapeHtml(transaction.referenceNo)}</td>
                  <td>${debit ? escapeHtml(formatAmount(debit)) : "-"}</td>
                  <td>${credit ? escapeHtml(formatAmount(credit)) : "-"}</td>
                  <td>${escapeHtml(formatAmount(transaction.runningBalance))}</td>
                </tr>
              `;
            })
            .join("")
        : `<tr><td colspan="11" class="empty">No transactions found.</td></tr>`;

    printWindow.document.write(`
      <!doctype html>
      <html>
        <head>
          <title>Broker Ledger - ${escapeHtml(broker.brokerName)}</title>
          <style>
            * { box-sizing: border-box; }
            @page { size: A4 landscape; margin: 10mm; }
            body { margin: 0; color: #111827; font-family: Arial, sans-serif; }
            .header { display: flex; justify-content: space-between; border-bottom: 2px solid #111827; padding-bottom: 14px; margin-bottom: 16px; }
            h1 { margin: 0; font-size: 28px; }
            h2 { margin: 4px 0 0; font-size: 18px; }
            .meta { text-align: right; font-size: 13px; line-height: 1.7; }
            .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 16px; }
            .box { border: 1px solid #d1d5db; border-radius: 8px; padding: 10px; }
            .box-title { font-size: 11px; font-weight: 700; }
            .box-value { margin-top: 4px; font-size: 15px; font-weight: 800; }
            table { width: 100%; border-collapse: collapse; font-size: 10px; }
            th { background: #2563eb; color: #fff; text-align: left; padding: 7px; border: 1px solid #2563eb; }
            td { padding: 7px; border: 1px solid #d1d5db; }
            .empty { text-align: center; font-weight: 700; padding: 16px; }
          </style>
        </head>
        <body>
          <div class="header">
            <div>
              <h1>UT Software</h1>
              <h2>Broker Ledger</h2>
            </div>
            <div class="meta">
              <div><strong>Broker:</strong> ${escapeHtml(broker.brokerName)}</div>
              <div><strong>Phone:</strong> ${escapeHtml(broker.phone)}</div>
              <div><strong>Printed:</strong> ${escapeHtml(new Date().toLocaleString("en-PK"))}</div>
            </div>
          </div>

          <div class="summary">
            <div class="box"><div class="box-title">Opening Balance</div><div class="box-value">${escapeHtml(formatAmount(broker.openingBalance))}</div></div>
            <div class="box"><div class="box-title">Total Payable</div><div class="box-value">${escapeHtml(formatAmount(broker.totalPayable))}</div></div>
            <div class="box"><div class="box-title">Total Paid</div><div class="box-value">${escapeHtml(formatAmount(broker.paymentToBroker + broker.advanceToBroker))}</div></div>
            <div class="box"><div class="box-title">Total Received</div><div class="box-value">${escapeHtml(formatAmount(broker.paymentFromBroker))}</div></div>
            <div class="box"><div class="box-title">Advance</div><div class="box-value">${escapeHtml(formatAmount(broker.advanceAmount))}</div></div>
            <div class="box"><div class="box-title">Current Balance</div><div class="box-value">${escapeHtml(formatAmount(broker.currentBalance))}</div></div>
            <div class="box"><div class="box-title">Status</div><div class="box-value">${escapeHtml(broker.balanceStatus)}</div></div>
          </div>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>Description</th>
                <th>Loading</th>
                <th>Vehicle</th>
                <th>Driver</th>
                <th>Payment</th>
                <th>Reference</th>
                <th>Debit</th>
                <th>Credit</th>
                <th>Running Balance</th>
              </tr>
            </thead>
            <tbody>${rowsHtml}</tbody>
          </table>

          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };
          </script>
        </body>
      </html>
    `);

    printWindow.document.close();
  }

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Broker Ledger: {broker.brokerName}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Contact: {broker.contactPerson} | Phone: {broker.phone}
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={handlePrintLedger}
            className="rounded-lg bg-gray-900 px-5 py-3 text-sm font-bold text-white hover:bg-gray-800"
          >
            Print Full Ledger
          </button>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 hover:bg-gray-300"
          >
            Close
          </button>
        </div>
      </div>

      <div className="mb-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Opening</p>
          <p className="mt-2 text-lg font-extrabold text-gray-900">
            {formatAmount(broker.openingBalance)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Payable</p>
          <p className="mt-2 text-lg font-extrabold text-red-700">
            {formatAmount(broker.payableAmount)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Advance</p>
          <p className="mt-2 text-lg font-extrabold text-green-700">
            {formatAmount(broker.advanceAmount)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Current Balance</p>
          <p
            className={`mt-2 text-lg font-extrabold ${
              broker.currentBalance > 0
                ? "text-red-700"
                : broker.currentBalance < 0
                  ? "text-green-700"
                  : "text-blue-700"
            }`}
          >
            {formatAmount(broker.currentBalance)}
          </p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Status</p>
          <span
            className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
              broker.balanceStatus
            )}`}
          >
            {broker.balanceStatus}
          </span>
        </div>
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-200">
        <table className="w-full min-w-[1450px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-left font-bold">Date</th>
              <th className="p-3 text-left font-bold">Transaction Type</th>
              <th className="p-3 text-left font-bold">Description</th>
              <th className="p-3 text-left font-bold">Loading</th>
              <th className="p-3 text-left font-bold">Vehicle</th>
              <th className="p-3 text-left font-bold">Driver</th>
              <th className="p-3 text-left font-bold">Payment Method</th>
              <th className="p-3 text-left font-bold">Reference No</th>
              <th className="p-3 text-right font-bold">Debit</th>
              <th className="p-3 text-right font-bold">Credit</th>
              <th className="p-3 text-right font-bold">Running Balance</th>
              <th className="p-3 text-left font-bold">Status</th>
              <th className="p-3 text-left font-bold">Actions</th>
            </tr>
          </thead>

          <tbody>
            {broker.transactions.length === 0 && (
              <tr>
                <td
                  colSpan={13}
                  className="p-8 text-center text-sm font-bold text-gray-900"
                >
                  No broker transactions found.
                </td>
              </tr>
            )}

            {broker.transactions.map((transaction) => {
              const debit = isDebit(transaction) ? transaction.amount : 0;
              const credit = !isDebit(transaction) ? transaction.amount : 0;
              const status =
                transaction.runningBalance > 0
                  ? "Payable"
                  : transaction.runningBalance < 0
                    ? "Advance"
                    : "Settled";

              return (
                <tr
                  key={transaction.id}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 font-semibold">
                    {transaction.transactionDate}
                  </td>
                  <td className="p-3 font-bold">
                    {transaction.transactionType}
                  </td>
                  <td className="max-w-[260px] p-3 font-semibold">
                    {transaction.description}
                  </td>
                  <td className="p-3 font-semibold">{transaction.loadingNo}</td>
                  <td className="p-3 font-semibold">{transaction.vehicleNo}</td>
                  <td className="p-3 font-semibold">{transaction.driverName}</td>
                  <td className="p-3 font-semibold">
                    {transaction.paymentMethod}
                  </td>
                  <td className="p-3 font-semibold">
                    {transaction.referenceNo}
                  </td>
                  <td className="p-3 text-right font-bold text-red-700">
                    {debit ? formatAmount(debit) : "-"}
                  </td>
                  <td className="p-3 text-right font-bold text-green-700">
                    {credit ? formatAmount(credit) : "-"}
                  </td>
                  <td
                    className={`p-3 text-right font-extrabold ${
                      transaction.runningBalance > 0
                        ? "text-red-700"
                        : transaction.runningBalance < 0
                          ? "text-green-700"
                          : "text-blue-700"
                    }`}
                  >
                    {formatAmount(transaction.runningBalance)}
                  </td>
                  <td className="p-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-bold ${getStatusClass(
                        status
                      )}`}
                    >
                      {status}
                    </span>
                  </td>
                  <td className="min-w-[230px] p-3">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => onEditTransaction(transaction)}
                        className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white hover:bg-blue-700"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        onClick={() => onDeleteTransaction(transaction)}
                        disabled={isDeleting}
                        className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed"
                      >
                        Delete
                      </button>
                      <button
                        type="button"
                        onClick={() => handlePrintEntry(transaction)}
                        className="rounded-lg bg-gray-900 px-3 py-2 font-semibold text-white hover:bg-gray-800"
                      >
                        Print Entry
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
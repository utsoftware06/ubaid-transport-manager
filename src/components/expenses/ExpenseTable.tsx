"use client";
type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  vehicles?: {
    vehicle_no: string;
  } | null;
  drivers?: {
    name: string;
  } | null;
};
type ExpenseItemRecord = {
  id: number;
  expense_id: number;
  expense_type: string;
  amount: number;
  payment_method: string;
  remarks: string | null;
  receipt_url?: string | null;
  receipt_name?: string | null;
};
type ExpenseVoucherRecord = {
  id: number;
  expense_no: string;
  expense_date: string;
  loading_id: number | string;
  description: string | null;
  created_at?: string;
  loadings?: LoadingRecord | null;
  expense_items?: ExpenseItemRecord[];
};
type ExpenseTableProps = {
  expenseVouchers: ExpenseVoucherRecord[];
  search: string;
  setSearch: (value: string) => void;
  viewingExpense: ExpenseVoucherRecord | null;
  onCloseView: () => void;
  onView: (voucher: ExpenseVoucherRecord) => void;
  onEdit: (voucher: ExpenseVoucherRecord) => void;
  onDelete: (voucher: ExpenseVoucherRecord) => void;
  onPrint: (voucher: ExpenseVoucherRecord) => void;
  isDeleting?: boolean;
};
function getVoucherTotal(voucher: ExpenseVoucherRecord) {
  return (voucher.expense_items ?? []).reduce(
    (total, item) => total + Number(item.amount || 0),
    0
  );
}
function getFileExtension(fileName: string) {
  return fileName.split(".").pop()?.toLowerCase() ?? "";
}
function isImageReceipt(fileName: string) {
  return ["jpg", "jpeg", "png", "webp"].includes(getFileExtension(fileName));
}
function isPdfReceipt(fileName: string) {
  return getFileExtension(fileName) === "pdf";
}
function getReceiptFileName(item: ExpenseItemRecord) {
  return item.receipt_name || item.receipt_url || "Receipt";
}
function openReceipt(url: string) {
  window.open(url, "_blank", "noopener,noreferrer");
}
function handlePrintVoucher(voucher: ExpenseVoucherRecord) {
  const printWindow = window.open("", "_blank", "width=950,height=720");

  if (!printWindow) {
    alert("Please allow popups to print the expense voucher.");
    return;
  }

  const items = voucher.expense_items ?? [];
  const grandTotal = getVoucherTotal(voucher);

  const itemRows =
    items.length > 0
      ? items
          .map((item, index) => {
            const receiptName = getReceiptFileName(item);
            let receiptCell = "-";

            if (item.receipt_url && receiptName) {
              if (isImageReceipt(receiptName)) {
                receiptCell = `
                  <a href="${item.receipt_url}" target="_blank">
                    <img
                      src="${item.receipt_url}"
                      alt="${receiptName}"
                      class="receipt-thumb"
                    />
                  </a>
                  <div class="receipt-name">${receiptName}</div>
                `;
              } else {
                receiptCell = `
                  <a href="${item.receipt_url}" target="_blank">
                    ${receiptName}
                  </a>
                `;
              }
            }

            return `
              <tr>
                <td>${index + 1}</td>
                <td>${item.expense_type ?? ""}</td>
                <td>${Number(item.amount || 0).toLocaleString()}</td>
                <td>${item.payment_method ?? ""}</td>
                <td>${receiptCell}</td>
                <td>${item.remarks ?? ""}</td>
              </tr>
            `;
          })
          .join("")
      : `<tr><td colspan="6" class="empty">No expense items found</td></tr>`;

  printWindow.document.write(`
    <!doctype html>
    <html>
      <head>
        <title>Expense Voucher - ${voucher.expense_no}</title>
        <style>
          * { box-sizing: border-box; }
          body {
            margin: 0;
            padding: 32px;
            color: #111827;
            font-family: Arial, sans-serif;
            background: #ffffff;
          }
          .voucher {
            max-width: 950px;
            margin: 0 auto;
            border: 1px solid #d1d5db;
            border-radius: 10px;
            padding: 28px;
          }
          .header {
            display: flex;
            justify-content: space-between;
            gap: 20px;
            border-bottom: 2px solid #111827;
            padding-bottom: 18px;
            margin-bottom: 22px;
          }
          h1 {
            margin: 0;
            font-size: 28px;
            color: #111827;
          }
          .subtitle {
            margin-top: 6px;
            font-size: 14px;
            color: #111827;
          }
          .meta {
            text-align: right;
            font-size: 14px;
            line-height: 1.7;
            color: #111827;
          }
          .details {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 12px 24px;
            margin-bottom: 24px;
            font-size: 15px;
          }
          .details div {
            border-bottom: 1px solid #e5e7eb;
            padding-bottom: 8px;
          }
          table {
            width: 100%;
            border-collapse: collapse;
            font-size: 14px;
          }
          th {
            background: #2563eb;
            color: #ffffff;
            text-align: left;
            padding: 10px;
            border: 1px solid #2563eb;
          }
          td {
            padding: 10px;
            border: 1px solid #d1d5db;
            color: #111827;
            vertical-align: top;
          }
          a {
            color: #2563eb;
            font-weight: 700;
            text-decoration: none;
          }
          tfoot td {
            font-weight: 700;
            background: #f9fafb;
          }
          .empty {
            text-align: center;
            font-weight: 700;
          }
          .description {
            margin: 20px 0;
            min-height: 70px;
            border: 1px solid #d1d5db;
            border-radius: 10px;
            padding: 14px;
            font-size: 15px;
            color: #111827;
          }
          .receipt-thumb {
            width: 64px;
            height: 64px;
            object-fit: cover;
            border: 1px solid #d1d5db;
            border-radius: 8px;
            display: block;
          }
          .receipt-name {
            margin-top: 4px;
            max-width: 140px;
            word-break: break-word;
            font-size: 11px;
            font-weight: 700;
          }
          .signatures {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 24px;
            margin-top: 52px;
            font-size: 14px;
            color: #111827;
          }
          .signature {
            border-top: 1px solid #111827;
            padding-top: 8px;
            text-align: center;
          }
          @media print {
            body { padding: 0; }
            .voucher {
              border: none;
              border-radius: 0;
            }
          }
        </style>
      </head>
      <body>
        <div class="voucher">
          <div class="header">
            <div>
              <h1>Company Header</h1>
              <div class="subtitle">Professional Expense Voucher</div>
            </div>
            <div class="meta">
              <div><strong>Voucher No:</strong> ${voucher.expense_no}</div>
              <div><strong>Date:</strong> ${voucher.expense_date}</div>
            </div>
          </div>

          <div class="details">
            <div><strong>Loading Number:</strong> ${
              voucher.loadings?.loading_no ?? "-"
            }</div>
            <div><strong>Vehicle:</strong> ${
              voucher.loadings?.vehicles?.vehicle_no ?? "-"
            }</div>
            <div><strong>Driver:</strong> ${
              voucher.loadings?.drivers?.name ?? "-"
            }</div>
            <div><strong>Route:</strong> ${voucher.loadings?.route ?? "-"}</div>
            <div><strong>Loading Date:</strong> ${
              voucher.loadings?.loading_date ?? "-"
            }</div>
            <div><strong>Total Items:</strong> ${items.length}</div>
          </div>

          <strong>Description</strong>
          <div class="description">${voucher.description || "-"}</div>

          <table>
            <thead>
              <tr>
                <th>#</th>
                <th>Expense Type</th>
                <th>Amount</th>
                <th>Payment Method</th>
                <th>Receipt</th>
                <th>Remarks</th>
              </tr>
            </thead>
            <tbody>${itemRows}</tbody>
            <tfoot>
              <tr>
                <td colspan="2">Grand Total</td>
                <td>${grandTotal.toLocaleString()}</td>
                <td colspan="3"></td>
              </tr>
            </tfoot>
          </table>

          <div class="signatures">
            <div class="signature">Prepared By</div>
            <div class="signature">Approved By</div>
            <div class="signature">Received By</div>
          </div>
        </div>

        <script>
          window.onload = function () {
            window.print();
          };
        </script>
      </body>
    </html>
  `);

  printWindow.document.close();
}
export default function ExpenseTable({
  expenseVouchers,
  search,
  setSearch,
  viewingExpense,
  onCloseView,
  onView,
  onEdit,
  onDelete,
  isDeleting = false,
}: ExpenseTableProps) {
  const viewingItems = viewingExpense?.expense_items ?? [];
  const viewingGrandTotal = viewingExpense ? getVoucherTotal(viewingExpense) : 0;
  return (
    <>
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
          <div>
            <h2 className="text-2xl font-bold text-gray-900">
              Expense Vouchers
            </h2>
            <p className="mt-1 text-base font-medium text-gray-900">
              Complete voucher records with loading details, totals, and
              actions.
            </p>
          </div>
      <input
        type="text"
        placeholder="Search Voucher, Loading, Vehicle, Driver or Route..."
        value={search}
        onChange={(event) => setSearch(event.target.value)}
        className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 lg:max-w-md"
      />
    </div>

    <div className="overflow-x-auto rounded-xl border border-gray-200">
      <table className="w-full min-w-[1180px] border-collapse bg-white text-sm text-gray-900">
        <thead className="bg-blue-600 text-white">
          <tr>
            <th className="p-3 text-left font-bold">
              Expense Voucher No
            </th>
            <th className="p-3 text-left font-bold">Expense Date</th>
            <th className="p-3 text-left font-bold">Loading Number</th>
            <th className="p-3 text-left font-bold">Vehicle</th>
            <th className="p-3 text-left font-bold">Driver</th>
            <th className="p-3 text-left font-bold">Route</th>
            <th className="p-3 text-right font-bold">Total Amount</th>
            <th className="p-3 text-right font-bold">Total Items</th>
            <th className="p-3 text-left font-bold">Actions</th>
          </tr>
        </thead>

        <tbody className="bg-white text-gray-900">
          {expenseVouchers.length === 0 && (
            <tr>
              <td
                colSpan={9}
                className="p-8 text-center text-base font-semibold text-gray-900"
              >
                No expense voucher records found.
              </td>
            </tr>
          )}

          {expenseVouchers.map((voucher) => (
            <tr
              key={voucher.id}
              className="border-b border-gray-200 hover:bg-gray-50"
            >
              <td className="p-3 font-bold text-gray-900">
                {voucher.expense_no}
              </td>
              <td className="p-3 font-semibold text-gray-900">
                {voucher.expense_date}
              </td>
              <td className="p-3 font-semibold text-gray-900">
                {voucher.loadings?.loading_no ?? "-"}
              </td>
              <td className="p-3 font-semibold text-gray-900">
                {voucher.loadings?.vehicles?.vehicle_no ?? "-"}
              </td>
              <td className="p-3 font-semibold text-gray-900">
                {voucher.loadings?.drivers?.name ?? "-"}
              </td>
              <td className="p-3 font-semibold text-gray-900">
                {voucher.loadings?.route ?? "-"}
              </td>
              <td className="p-3 text-right font-bold text-gray-900">
                {getVoucherTotal(voucher).toLocaleString()}
              </td>
              <td className="p-3 text-right font-bold text-gray-900">
                {voucher.expense_items?.length ?? 0}
              </td>
              <td className="min-w-[230px] p-3">
                <div className="flex flex-wrap gap-2">
                  <button
                    type="button"
                    onClick={() => onView(voucher)}
                    className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                  >
                    View
                  </button>

                  <button
                    type="button"
                    onClick={() => onEdit(voucher)}
                    className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                  >
                    Edit
                  </button>

                  <button
                    type="button"
                    onClick={() => onDelete(voucher)}
                    disabled={isDeleting}
                    className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-400"
                  >
                    Delete
                  </button>

                  <button
                    type="button"
                    onClick={() => handlePrintVoucher(voucher)}
                    className="rounded-lg bg-green-600 px-3 py-2 font-semibold text-white transition hover:bg-green-700"
                  >
                    Print
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  </div>

  {viewingExpense && (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <div className="my-8 w-full max-w-6xl rounded-xl bg-white p-6 shadow-xl md:p-8">
        <div className="mb-6 flex flex-col justify-between gap-4 md:flex-row md:items-start">
          <div>
            <h2 className="text-3xl font-bold text-gray-900">
              Expense Voucher Details
            </h2>
            <p className="mt-1 text-base font-semibold text-gray-900">
              Voucher No: {viewingExpense.expense_no}
            </p>
          </div>

          <button
            type="button"
            onClick={onCloseView}
            className="rounded-lg border border-gray-300 bg-white px-5 py-3 font-semibold text-gray-900 transition hover:bg-gray-50"
          >
            Close
          </button>
        </div>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Voucher No</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingExpense.expense_no}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Expense Date</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingExpense.expense_date}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Loading No</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingExpense.loadings?.loading_no ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              Loading Date
            </p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingExpense.loadings?.loading_date ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Vehicle</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingExpense.loadings?.vehicles?.vehicle_no ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Driver</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingExpense.loadings?.drivers?.name ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Route</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingExpense.loadings?.route ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Grand Total</p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {viewingGrandTotal.toLocaleString()}
            </p>
          </div>
        </div>

        <div className="mt-6 rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Description</p>
          <p className="mt-1 text-base font-semibold text-gray-900">
            {viewingExpense.description || "-"}
          </p>
        </div>

        <div className="mt-8 overflow-x-auto rounded-xl border border-gray-200">
          <table className="w-full min-w-[980px] border-collapse bg-white text-sm text-gray-900">
            <thead className="bg-blue-600 text-white">
              <tr>
                <th className="p-3 text-left font-bold">#</th>
                <th className="p-3 text-left font-bold">Expense Type</th>
                <th className="p-3 text-right font-bold">Amount</th>
                <th className="p-3 text-left font-bold">
                  Payment Method
                </th>
                <th className="p-3 text-left font-bold">Receipt</th>
                <th className="p-3 text-left font-bold">Remarks</th>
              </tr>
            </thead>

            <tbody className="bg-white text-gray-900">
              {viewingItems.length === 0 && (
                <tr>
                  <td
                    colSpan={6}
                    className="p-6 text-center text-base font-semibold text-gray-900"
                  >
                    No expense items found.
                  </td>
                </tr>
              )}

              {viewingItems.map((item, index) => {
                const receiptName = getReceiptFileName(item);

                return (
                  <tr
                    key={item.id}
                    className="border-b border-gray-200 hover:bg-gray-50"
                  >
                    <td className="p-3 font-semibold text-gray-900">
                      {index + 1}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {item.expense_type}
                    </td>
                    <td className="p-3 text-right font-bold text-gray-900">
                      {Number(item.amount || 0).toLocaleString()}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {item.payment_method}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {item.receipt_url ? (
                        isImageReceipt(receiptName) ? (
                          <button
                            type="button"
                            onClick={() =>
                              openReceipt(item.receipt_url as string)
                            }
                            className="block rounded-lg border border-gray-200 bg-white p-1 transition hover:bg-gray-50"
                          >
                            {console.log("Receipt URL:", item.receipt_url)}
                            
                            <img
                              src={item.receipt_url}
                              alt={receiptName}
                              className="h-16 w-16 rounded-md object-cover"
                            />
                          </button>
                        ) : isPdfReceipt(receiptName) ? (
                          <button
                            type="button"
                            onClick={() =>
                              openReceipt(item.receipt_url as string)
                            }
                            className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                          >
                            PDF
                          </button>
                        ) : (
                          <button
                            type="button"
                            onClick={() =>
                              openReceipt(item.receipt_url as string)
                            }
                            className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                          >
                            Open
                          </button>
                        )
                      ) : (
                        "-"
                      )}
                    </td>
                    <td className="p-3 font-semibold text-gray-900">
                      {item.remarks || "-"}
                    </td>
                  </tr>
                );
              })}
            </tbody>

            <tfoot className="bg-gray-50 text-gray-900">
              <tr>
                <td className="p-3 font-bold" colSpan={2}>
                  Grand Total
                </td>
                <td className="p-3 text-right font-bold">
                  {viewingGrandTotal.toLocaleString()}
                </td>
                <td className="p-3" colSpan={3}></td>
              </tr>
            </tfoot>
          </table>
        </div>

        <div className="mt-6 flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={() => handlePrintVoucher(viewingExpense)}
            className="rounded-lg bg-green-600 px-6 py-3 font-semibold text-white transition hover:bg-green-700"
          >
            Print
          </button>

          <button
            type="button"
            onClick={() => onEdit(viewingExpense)}
            className="rounded-lg bg-blue-600 px-6 py-3 font-semibold text-white transition hover:bg-blue-700"
          >
            Edit
          </button>

          <button
            type="button"
            onClick={onCloseView}
            className="rounded-lg border border-gray-300 bg-white px-6 py-3 font-semibold text-gray-900 transition hover:bg-gray-50"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  )}
</>
  );
}
"use client";

type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  vehicle_id: string | null;
  driver_id: string | null;
  vehicles?: {
    vehicle_no: string | null;
  } | null;
  drivers?: {
    name: string | null;
  } | null;
};

type ExpenseItemRecord = {
  id: number;
  expense_id: number;
  expense_type: string;
  amount: number | string;
  payment_method: string;
  remarks: string | null;
  receipt_url: string | null;
  receipt_name: string | null;
};

type DieselEntryRecord = {
  id: number;
  expense_id: number;
  expense_item_id: number;
  entry_date: string;
  petrol_pump_id: string;
  vehicle_id: string;
  driver_id: string | null;
  loading_id: number | null;
  slip_no: string | null;
  liters: number | string;
  rate: number | string;
  total_amount: number | string;
  paid_amount: number | string;
  remaining_amount: number | string;
  payment_status: string;
  remarks: string | null;
  petrol_pumps?: {
    pump_name: string | null;
  } | null;
};

type ExpenseVoucher = {
  id: number;
  expense_no: string;
  expense_date: string;
  loading_id: number;
  description: string | null;
  created_at?: string | null;
  loadings?: LoadingRecord | null;
  expense_items?: ExpenseItemRecord[];
  diesel_entries?: DieselEntryRecord[];
};

type Props = {
  expenseVouchers: ExpenseVoucher[];
  search: string;
  setSearch: (value: string) => void;
  viewingExpense: ExpenseVoucher | null;
  onCloseView: () => void;
  onView: (expense: ExpenseVoucher) => void;
  onEdit: (expense: ExpenseVoucher) => void;
  onDelete: (expense: ExpenseVoucher) => void;
  onPrint: (expense: ExpenseVoucher) => void;
  onPreviewReceipt: (receiptUrl: string) => void;
  isDeleting: boolean;
};

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function formatAmount(value: number | string | null | undefined) {
  return `Rs. ${toNumber(value).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function getStatusClass(status: string) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

function getVoucherTotal(expense: ExpenseVoucher) {
  return (expense.expense_items ?? []).reduce(
    (total, item) => total + toNumber(item.amount),
    0
  );
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
  onPrint,
  onPreviewReceipt,
  isDeleting,
}: Props) {
  const dieselByItemId = new Map<number, DieselEntryRecord>();

  (viewingExpense?.diesel_entries ?? []).forEach((diesel) => {
    dieselByItemId.set(diesel.expense_item_id, diesel);
  });

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-4 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            Expense Vouchers
          </h2>
          <p className="mt-1 text-base font-medium text-gray-900">
            Complete voucher list with receipts, diesel details, edit, delete
            and print actions.
          </p>
        </div>

        <input
          type="text"
          placeholder="Search Expense, Loading, Vehicle, Driver, Type, Amount or Description..."
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 lg:max-w-md"
        />
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-200">
        <table className="w-full min-w-[1200px] border-collapse bg-white text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-left font-bold">Voucher No</th>
              <th className="p-3 text-left font-bold">Date</th>
              <th className="p-3 text-left font-bold">Loading</th>
              <th className="p-3 text-left font-bold">Vehicle</th>
              <th className="p-3 text-left font-bold">Driver</th>
              <th className="p-3 text-left font-bold">Route</th>
              <th className="p-3 text-right font-bold">Items</th>
              <th className="p-3 text-right font-bold">Total Amount</th>
              <th className="p-3 text-left font-bold">Description</th>
              <th className="p-3 text-left font-bold">Actions</th>
            </tr>
          </thead>

          <tbody>
            {expenseVouchers.length === 0 && (
              <tr>
                <td
                  colSpan={10}
                  className="p-8 text-center text-base font-bold text-gray-900"
                >
                  No expense vouchers found.
                </td>
              </tr>
            )}

            {expenseVouchers.map((expense) => (
              <tr
                key={expense.id}
                className="border-b border-gray-200 text-gray-900 hover:bg-gray-50"
              >
                <td className="p-3 font-bold">{expense.expense_no}</td>
                <td className="p-3 font-semibold">{expense.expense_date}</td>
                <td className="p-3 font-semibold">
                  {expense.loadings?.loading_no ?? "-"}
                </td>
                <td className="p-3 font-semibold">
                  {expense.loadings?.vehicles?.vehicle_no ?? "-"}
                </td>
                <td className="p-3 font-semibold">
                  {expense.loadings?.drivers?.name ?? "-"}
                </td>
                <td className="p-3 font-semibold">
                  {expense.loadings?.route ?? "-"}
                </td>
                <td className="p-3 text-right font-bold">
                  {expense.expense_items?.length ?? 0}
                </td>
                <td className="p-3 text-right font-extrabold">
                  {formatAmount(getVoucherTotal(expense))}
                </td>
                <td className="max-w-[260px] p-3 font-semibold">
                  <span className="line-clamp-2">
                    {expense.description || "-"}
                  </span>
                </td>
                <td className="min-w-[260px] p-3">
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => onView(expense)}
                      className="rounded-lg border border-gray-300 bg-white px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50"
                    >
                      View
                    </button>

                    <button
                      type="button"
                      onClick={() => onEdit(expense)}
                      className="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white transition hover:bg-blue-700"
                    >
                      Edit
                    </button>

                    <button
                      type="button"
                      onClick={() => onDelete(expense)}
                      disabled={isDeleting}
                      className="rounded-lg bg-red-600 px-3 py-2 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed"
                    >
                      Delete
                    </button>

                    <button
                      type="button"
                      onClick={() => onPrint(expense)}
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

      {viewingExpense && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="max-h-[90vh] w-full max-w-6xl overflow-y-auto rounded-xl bg-white p-6 shadow-xl">
            <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-start">
              <div>
                <h3 className="text-2xl font-bold text-gray-900">
                  Expense Voucher Details
                </h3>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  Voucher No: {viewingExpense.expense_no}
                </p>
              </div>

              <button
                type="button"
                onClick={onCloseView}
                className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
              >
                Close
              </button>
            </div>

            <div className="mb-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
              <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p className="text-sm font-bold text-gray-900">Date</p>
                <p className="mt-1 text-lg font-bold text-gray-900">
                  {viewingExpense.expense_date}
                </p>
              </div>

              <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p className="text-sm font-bold text-gray-900">Loading</p>
                <p className="mt-1 text-lg font-bold text-gray-900">
                  {viewingExpense.loadings?.loading_no ?? "-"}
                </p>
              </div>

              <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p className="text-sm font-bold text-gray-900">Vehicle</p>
                <p className="mt-1 text-lg font-bold text-gray-900">
                  {viewingExpense.loadings?.vehicles?.vehicle_no ?? "-"}
                </p>
              </div>

              <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p className="text-sm font-bold text-gray-900">Total</p>
                <p className="mt-1 text-lg font-bold text-gray-900">
                  {formatAmount(getVoucherTotal(viewingExpense))}
                </p>
              </div>
            </div>

            <div className="overflow-x-auto rounded-xl border border-gray-200">
              <table className="w-full min-w-[1100px] border-collapse text-sm text-gray-900">
                <thead className="bg-blue-600 text-white">
                  <tr>
                    <th className="p-3 text-left font-bold">#</th>
                    <th className="p-3 text-left font-bold">Expense Type</th>
                    <th className="p-3 text-right font-bold">Amount</th>
                    <th className="p-3 text-left font-bold">Payment</th>
                    <th className="p-3 text-left font-bold">Remarks</th>
                    <th className="p-3 text-left font-bold">Receipt</th>
                  </tr>
                </thead>

                <tbody>
                  {(viewingExpense.expense_items ?? []).map((item, index) => {
                    const diesel = dieselByItemId.get(item.id);

                    return (
                      <tr key={item.id} className="border-b border-gray-200">
                        <td className="p-3 font-semibold">{index + 1}</td>
                        <td className="p-3 font-bold">{item.expense_type}</td>
                        <td className="p-3 text-right font-bold">
                          {formatAmount(item.amount)}
                        </td>
                        <td className="p-3 font-semibold">
                          {item.payment_method}
                        </td>
                        <td className="p-3 font-semibold">
                          <div>{item.remarks || "-"}</div>

                          {diesel && (
                            <div className="mt-3 rounded-lg border border-blue-100 bg-blue-50 p-3">
                              <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
                                <div>
                                  <span className="font-bold">
                                    Petrol Pump:
                                  </span>{" "}
                                  {diesel.petrol_pumps?.pump_name ?? "-"}
                                </div>
                                <div>
                                  <span className="font-bold">Litres:</span>{" "}
                                  {diesel.liters}
                                </div>
                                <div>
                                  <span className="font-bold">Rate:</span>{" "}
                                  {formatAmount(diesel.rate)}
                                </div>
                                <div>
                                  <span className="font-bold">Total:</span>{" "}
                                  {formatAmount(diesel.total_amount)}
                                </div>
                                <div>
                                  <span className="font-bold">Paid:</span>{" "}
                                  {formatAmount(diesel.paid_amount)}
                                </div>
                                <div>
                                  <span className="font-bold">Remaining:</span>{" "}
                                  {formatAmount(diesel.remaining_amount)}
                                </div>
                                <div>
                                  <span className="font-bold">Status:</span>{" "}
                                  <span
                                    className={`inline-flex rounded-full border px-2 py-1 text-xs font-bold ${getStatusClass(
                                      diesel.payment_status
                                    )}`}
                                  >
                                    {diesel.payment_status}
                                  </span>
                                </div>
                                <div>
                                  <span className="font-bold">Slip No:</span>{" "}
                                  {diesel.slip_no ?? "-"}
                                </div>
                              </div>
                            </div>
                          )}
                        </td>
                        <td className="p-3 font-semibold">
                          {item.receipt_url ? (
                            <button
                              type="button"
                              onClick={() =>
                                onPreviewReceipt(item.receipt_url ?? "")
                              }
                              className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-bold text-gray-900 hover:bg-gray-50"
                            >
                              Preview Receipt
                            </button>
                          ) : (
                            "-"
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div className="mt-6 flex justify-end">
              <button
                type="button"
                onClick={() => onPrint(viewingExpense)}
                className="rounded-lg bg-green-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-green-700"
              >
                Print Voucher
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
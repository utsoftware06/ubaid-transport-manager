"use client";

type ReceiptStatus = "idle" | "uploading" | "replacing" | "deleting";

type ExpenseItemRow = {
  rowId: number;
  dbId?: number;
  expenseType: string;
  amount: string;
  paymentMethod: string;
  remarks: string;
  receiptUrl: string | null;
  receiptName: string | null;
  receiptFile: File | null;
  receiptStatus: ReceiptStatus;
  receiptError: string;
  petrolPumpId: string;
  liters: string;
  rate: string;
  paidAmount: string;
  slipNo: string;
};

type PetrolPumpOption = {
  id: string;
  pumpName: string;
  openingBalance: number;
};

type Props = {
  expenseItems: ExpenseItemRow[];
  grandTotal: number;
  petrolPumps: PetrolPumpOption[];
  onAddExpenseItem: () => void;
  onDeleteExpenseItem: (rowId: number) => void;
  onExpenseItemChange: (
    rowId: number,
    field: keyof ExpenseItemRow,
    value: string
  ) => void;
  onReceiptSelected: (rowId: number, file: File) => void;
  onReceiptDelete: (rowId: number) => void;
  onPreviewReceipt: (receiptUrl: string) => void;
  onSave: () => void;
  isSaving: boolean;
};

const expenseTypes = [
  "Fuel",
  "Toll Tax",
  "Food",
  "Labour",
  "Maintenance",
  "Police",
  "Parking",
  "Other",
];

const paymentMethods = [
  "Cash",
  "Bank Transfer",
  "JazzCash",
  "EasyPaisa",
  "Cheque",
];

function toNumber(value: string) {
  const numericValue = Number(value || 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function getDieselStatus(paidAmount: number, totalAmount: number) {
  if (paidAmount <= 0) return "Unpaid";
  if (paidAmount >= totalAmount) return "Paid";
  return "Partial";
}

function getStatusClass(status: string) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

export default function ExpenseItems({
  expenseItems,
  grandTotal,
  petrolPumps,
  onAddExpenseItem,
  onDeleteExpenseItem,
  onExpenseItemChange,
  onReceiptSelected,
  onReceiptDelete,
  onPreviewReceipt,
  onSave,
  isSaving,
}: Props) {
  return (
    <div className="mt-10 rounded-xl border border-gray-200 bg-white p-5">
      <div className="mb-5 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Expense Items</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Add expense rows, attach receipts, and enter diesel details for Fuel.
          </p>
        </div>

        <button
          type="button"
          onClick={onAddExpenseItem}
          className="rounded-lg bg-green-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-green-700"
        >
          Add Expense Item
        </button>
      </div>

      <div className="space-y-5">
        {expenseItems.map((item) => {
          const totalAmount = toNumber(item.liters) * toNumber(item.rate);
          const paidAmount = toNumber(item.paidAmount);
          const remainingAmount = Math.max(totalAmount - paidAmount, 0);
          const paymentStatus = getDieselStatus(paidAmount, totalAmount);

          return (
            <div
              key={item.rowId}
              className="rounded-xl border border-gray-200 bg-gray-50 p-4"
            >
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    Expense Type
                  </label>
                  <select
                    value={item.expenseType}
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "expenseType",
                        event.target.value
                      )
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  >
                    <option value="">Select Type</option>
                    {expenseTypes.map((type) => (
                      <option key={type} value={type}>
                        {type}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    Amount
                  </label>
                  <input
                    type="number"
                    value={item.amount}
                    readOnly={item.expenseType === "Fuel"}
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "amount",
                        event.target.value
                      )
                    }
                    placeholder="0"
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  />
                </div>

                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    Payment Method
                  </label>
                  <select
                    value={item.paymentMethod}
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "paymentMethod",
                        event.target.value
                      )
                    }
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  >
                    {paymentMethods.map((method) => (
                      <option key={method} value={method}>
                        {method}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    Receipt
                  </label>
                  <input
                    type="file"
                    accept=".jpg,.jpeg,.png,.webp,.pdf"
                    onChange={(event) => {
                      const file = event.target.files?.[0];
                      if (file) onReceiptSelected(item.rowId, file);
                    }}
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-900 file:mr-3 file:rounded-md file:border-0 file:bg-blue-600 file:px-3 file:py-2 file:text-sm file:font-bold file:text-white"
                  />

                  {(item.receiptName || item.receiptFile) && (
                    <div className="mt-2 flex flex-wrap items-center gap-2">
                      <span className="text-xs font-bold text-green-700">
                        {item.receiptFile?.name ?? item.receiptName}
                      </span>

                      {item.receiptUrl && (
                        <button
                          type="button"
                          onClick={() => onPreviewReceipt(item.receiptUrl ?? "")}
                          className="rounded border border-gray-300 bg-white px-2 py-1 text-xs font-bold text-gray-900"
                        >
                          Preview
                        </button>
                      )}

                      {(item.receiptUrl || item.receiptFile) && (
                        <button
                          type="button"
                          onClick={() => onReceiptDelete(item.rowId)}
                          disabled={item.receiptStatus !== "idle"}
                          className="rounded bg-red-600 px-2 py-1 text-xs font-bold text-white disabled:cursor-not-allowed"
                        >
                          {item.receiptStatus === "deleting"
                            ? "Deleting..."
                            : "Delete"}
                        </button>
                      )}
                    </div>
                  )}

                  {item.receiptStatus !== "idle" && (
                    <p className="mt-2 text-xs font-bold text-blue-700">
                      {item.receiptStatus === "uploading"
                        ? "Uploading..."
                        : item.receiptStatus === "replacing"
                          ? "Replacing..."
                          : "Deleting..."}
                    </p>
                  )}

                  {item.receiptError && (
                    <p className="mt-2 text-xs font-bold text-red-700">
                      {item.receiptError}
                    </p>
                  )}
                </div>

                <div className="md:col-span-2">
                  <label className="mb-2 block text-sm font-bold text-gray-900">
                    Remarks
                  </label>
                  <input
                    type="text"
                    value={item.remarks}
                    onChange={(event) =>
                      onExpenseItemChange(
                        item.rowId,
                        "remarks",
                        event.target.value
                      )
                    }
                    placeholder="Remarks"
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                  />
                </div>

                <div className="flex items-end">
                  <button
                    type="button"
                    onClick={() => onDeleteExpenseItem(item.rowId)}
                    className="w-full rounded-lg bg-red-600 px-4 py-3 text-sm font-bold text-white transition hover:bg-red-700"
                  >
                    Delete Row
                  </button>
                </div>
              </div>

              {item.expenseType === "Fuel" && (
                <div className="mt-5 rounded-xl border border-blue-100 bg-blue-50 p-4">
                  <h3 className="mb-4 text-lg font-bold text-gray-900">
                    Diesel Details
                  </h3>

                  <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        Petrol Pump
                      </label>
                      <select
                        value={item.petrolPumpId}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "petrolPumpId",
                            event.target.value
                          )
                        }
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      >
                        <option value="">Select Petrol Pump</option>
                        {petrolPumps.map((pump) => (
                          <option key={pump.id} value={pump.id}>
                            {pump.pumpName}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        Litres
                      </label>
                      <input
                        type="number"
                        min="0"
                        value={item.liters}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "liters",
                            event.target.value
                          )
                        }
                        placeholder="0"
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      />
                    </div>

                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        Rate
                      </label>
                      <input
                        type="number"
                        min="0"
                        value={item.rate}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "rate",
                            event.target.value
                          )
                        }
                        placeholder="0"
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      />
                    </div>

                    <div className="rounded-lg border border-gray-200 bg-white p-4">
                      <p className="text-sm font-bold text-gray-900">Total</p>
                      <p className="mt-2 text-xl font-extrabold text-gray-900">
                        {formatAmount(totalAmount)}
                      </p>
                    </div>

                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        Paid Amount
                      </label>
                      <input
                        type="number"
                        min="0"
                        value={item.paidAmount}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "paidAmount",
                            event.target.value
                          )
                        }
                        placeholder="0"
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      />
                    </div>

                    <div className="rounded-lg border border-gray-200 bg-white p-4">
                      <p className="text-sm font-bold text-gray-900">
                        Remaining
                      </p>
                      <p className="mt-2 text-xl font-extrabold text-red-700">
                        {formatAmount(remainingAmount)}
                      </p>
                    </div>

                    <div className="rounded-lg border border-gray-200 bg-white p-4">
                      <p className="text-sm font-bold text-gray-900">Status</p>
                      <span
                        className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                          paymentStatus
                        )}`}
                      >
                        {paymentStatus}
                      </span>
                    </div>

                    <div>
                      <label className="mb-2 block text-sm font-bold text-gray-900">
                        Slip No
                      </label>
                      <input
                        type="text"
                        value={item.slipNo}
                        onChange={(event) =>
                          onExpenseItemChange(
                            item.rowId,
                            "slipNo",
                            event.target.value
                          )
                        }
                        placeholder="Slip No"
                        className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                      />
                    </div>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      <div className="mt-6 flex flex-col justify-between gap-4 rounded-xl border border-gray-200 bg-gray-50 p-4 md:flex-row md:items-center">
        <div>
          <p className="text-sm font-bold text-gray-900">Grand Total</p>
          <p className="mt-1 text-2xl font-extrabold text-gray-900">
            {formatAmount(grandTotal)}
          </p>
        </div>

        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving ? "Saving..." : "Save Expense Voucher"}
        </button>
      </div>
    </div>
  );
}
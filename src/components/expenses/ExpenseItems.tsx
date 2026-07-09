type ReceiptState = "idle" | "uploading" | "replacing" | "deleting";

export type ExpenseItemRow = {
  rowId: number;
  dbId?: number;
  expenseType: string;
  amount: string;
  paymentMethod: string;
  remarks: string;
  receiptUrl: string | null;
  receiptName: string | null;
  receiptFile: File | null;
  receiptStatus: ReceiptState;
  receiptError: string;
};

type ExpenseItemsProps = {
  expenseItems: ExpenseItemRow[];
  grandTotal: number;
  onAddExpenseItem: () => void;
  onDeleteExpenseItem: (rowId: number) => void | Promise<void>;
  onExpenseItemChange: (
    rowId: number,
    field: keyof Pick<
      ExpenseItemRow,
      "expenseType" | "amount" | "paymentMethod" | "remarks"
    >,
    value: string
  ) => void;
  onReceiptSelected: (rowId: number, file: File) => void | Promise<void>;
  onReceiptDelete: (rowId: number) => void | Promise<void>;
  onPreviewReceipt: (url: string, name: string) => void;
  onSave: () => void;
  isSaving?: boolean;
};

const expenseTypeOptions = [
  "Fuel",
  "Toll Tax",
  "Food",
  "Labour",
  "Maintenance",
  "Police",
  "Parking",
  "Other",
];

const paymentMethodOptions = [
  "Cash",
  "Bank Transfer",
  "JazzCash",
  "EasyPaisa",
  "Cheque",
];

function getReceiptButtonText(item: ExpenseItemRow) {
  if (item.receiptStatus === "uploading") return "Uploading...";
  if (item.receiptStatus === "replacing") return "Replacing...";
  if (item.receiptStatus === "deleting") return "Deleting...";
  if (item.receiptUrl) return "Replace";
  return "Choose File";
}

export default function ExpenseItems({
  expenseItems,
  grandTotal,
  onAddExpenseItem,
  onDeleteExpenseItem,
  onExpenseItemChange,
  onReceiptSelected,
  onReceiptDelete,
  onPreviewReceipt,
  onSave,
  isSaving = false,
}: ExpenseItemsProps) {
  return (
    <div className="mt-10 rounded-xl border border-gray-200 bg-gray-50 p-6">
      <div className="mb-6 flex flex-col justify-between gap-3 lg:flex-row lg:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Expense Items</h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Add multiple expense rows with one receipt per row.
          </p>
        </div>

        <div className="rounded-lg border border-gray-200 bg-white px-5 py-3 text-base font-bold text-gray-900">
          Grand Total: RS. {grandTotal.toLocaleString()}
        </div>
      </div>

      <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
        <table className="w-full min-w-[1180px] border-collapse text-sm text-gray-900">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th className="p-3 text-left font-bold">Expense Type</th>
              <th className="p-3 text-right font-bold">Amount</th>
              <th className="p-3 text-left font-bold">Payment Method</th>
              <th className="p-3 text-left font-bold">Receipt</th>
              <th className="p-3 text-left font-bold">Remarks</th>
              <th className="w-[140px] p-3 text-left font-bold">Action</th>
            </tr>
          </thead>

          <tbody className="bg-white text-gray-900">
            {expenseItems.map((item) => {
              const isProcessing = item.receiptStatus !== "idle";

              return (
                <tr
                  key={item.rowId}
                  className="border-b border-gray-200 hover:bg-gray-50"
                >
                  <td className="p-3 align-top">
                    <select
                      value={item.expenseType}
                      onChange={(event) =>
                        onExpenseItemChange(
                          item.rowId,
                          "expenseType",
                          event.target.value
                        )
                      }
                      className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
                    >
                      <option value="">Select Expense Type</option>
                      {expenseTypeOptions.map((option) => (
                        <option key={option} value={option}>
                          {option}
                        </option>
                      ))}
                    </select>
                  </td>

                  <td className="p-3 align-top">
                    <input
                     type="number"
                     min="0"
                     step="0.01"
                     placeholder="Amount"
                      value={item.amount}
                      onChange={(event) =>
                        onExpenseItemChange(
                          item.rowId,
                          "amount",
                          event.target.value
                        )
                      }
                      className="w-full rounded-lg border border-gray-300 bg-white p-3 text-right font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
                    />
                  </td>

                  <td className="p-3 align-top">
                    <select
                      value={item.paymentMethod}
                      onChange={(event) =>
                        onExpenseItemChange(
                          item.rowId,
                          "paymentMethod",
                          event.target.value
                        )
                      }
                      className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
                    >
                      <option value="">Select Payment Method</option>
                      {paymentMethodOptions.map((option) => (
                        <option key={option} value={option}>
                          {option}
                        </option>
                      ))}
                    </select>
                  </td>

                  <td className="min-w-[260px] p-3 align-top">
                    <div className="space-y-2">
                      <div className="flex flex-wrap items-center gap-2">
                        <label className="inline-flex cursor-pointer rounded-lg bg-blue-600 px-4 py-3 font-semibold text-white transition hover:bg-blue-700">
                          {getReceiptButtonText(item)}
                          <input
                            type="file"
                            accept=".jpg,.jpeg,.png,.webp,.pdf"
                            disabled={isProcessing}
                            onChange={(event) => {
                              const file = event.target.files?.[0];
                              event.target.value = "";

                              if (file) {
                                onReceiptSelected(item.rowId, file);
                              }
                            }}
                            className="hidden"
                          />
                        </label>

                        {item.receiptUrl && item.receiptName && (
                          <>
                            <button
                              type="button"
                              onClick={() =>
                                onPreviewReceipt(
                                  item.receiptUrl as string,
                                  item.receiptName as string
                                )
                              }
                              disabled={isProcessing}
                              className="rounded-lg border border-gray-300 bg-white px-4 py-3 font-semibold text-gray-900 transition hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100"
                            >
                              Preview
                            </button>

                            <button
                              type="button"
                              onClick={() => onReceiptDelete(item.rowId)}
                              disabled={isProcessing}
                              className="rounded-lg bg-red-600 px-4 py-3 font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-400"
                            >
                              Delete
                            </button>
                          </>
                        )}
                      </div>

                      {item.receiptUrl && item.receiptName && (
                        <div className="rounded-lg border border-green-200 bg-green-50 px-3 py-2">
                          <p className="text-sm font-bold text-green-700">
                            Uploaded
                          </p>
                          <p className="break-all text-sm font-semibold text-gray-900">
                            {item.receiptName}
                          </p>
                        </div>
                      )}

                      {!item.receiptUrl && item.receiptFile && (
                        <div className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2">
                          <p className="text-sm font-bold text-blue-700">
                            Selected for upload
                          </p>
                          <p className="break-all text-sm font-semibold text-gray-900">
                            {item.receiptFile.name}
                          </p>
                        </div>
                      )}

                      {item.receiptError && (
                        <p className="text-sm font-bold text-red-600">
                          {item.receiptError}
                        </p>
                      )}
                    </div>
                  </td>

                  <td className="p-3 align-top">
                    <input
                      type="text"
                      placeholder="Remarks"
                      value={item.remarks}
                      onChange={(event) =>
                        onExpenseItemChange(
                          item.rowId,
                          "remarks",
                          event.target.value
                        )
                      }
                      className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
                    />
                  </td>

                  <td className="w-[140px] p-3 align-top">
                    <button
                      type="button"
                      onClick={() => onDeleteExpenseItem(item.rowId)}
                      disabled={expenseItems.length === 1 || isProcessing}
                      className="w-full whitespace-nowrap rounded-lg bg-red-600 px-4 py-3 text-center font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-400"
                    >
                      Delete Row
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>

          <tfoot className="bg-gray-50 text-gray-900">
            <tr>
              <td className="p-3 font-bold">Grand Total</td>
              <td className="p-3 text-right font-bold">
              RS.  {grandTotal.toLocaleString()}
              </td>
              <td className="p-3" colSpan={4}></td>
            </tr>
          </tfoot>
        </table>
      </div>

      <div className="mt-6 flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          onClick={onAddExpenseItem}
          className="rounded-lg bg-green-600 px-6 py-3 font-semibold text-white transition hover:bg-green-700"
        >
          Add Expense Item
        </button>

        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
        >
          {isSaving ? "Saving..." : "Save Expense Voucher"}
        </button>
      </div>
    </div>
  );
}
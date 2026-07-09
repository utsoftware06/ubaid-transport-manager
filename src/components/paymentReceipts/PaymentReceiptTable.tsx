type PaymentReceipt = {
  id: string;
  receipt_no: string;
  receipt_date: string;
  amount: number;
  payment_method: string;
  remarks: string | null;
  loadings?: {
    loading_no: string;
  } | null;
};

type Props = {
  receipts: PaymentReceipt[];
};

export default function PaymentReceiptTable({ receipts }: Props) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md">
      <h2 className="mb-6 text-2xl font-bold text-gray-900">
        Receipt History
      </h2>

      <div className="overflow-x-auto">
        <table className="min-w-full border-collapse text-sm text-gray-900">
          <thead>
            <tr className="bg-gray-100">
              <th className="border px-4 py-3 text-left">Receipt No</th>
              <th className="border px-4 py-3 text-left">Date</th>
              <th className="border px-4 py-3 text-left">Loading</th>
              <th className="border px-4 py-3 text-left">Amount</th>
              <th className="border px-4 py-3 text-left">Method</th>
              <th className="border px-4 py-3 text-left">Remarks</th>
            </tr>
          </thead>

          <tbody>
            {receipts.length === 0 ? (
              <tr>
                <td
                  colSpan={6}
                  className="border px-4 py-8 text-center font-semibold text-gray-900"
                >
                  No receipts found.
                </td>
              </tr>
            ) : (
              receipts.map((receipt) => (
                <tr key={receipt.id} className="hover:bg-gray-50">
                  <td className="border px-4 py-3 font-semibold text-gray-900">
                    {receipt.receipt_no}
                  </td>
                  <td className="border px-4 py-3 font-semibold text-gray-900">
                    {receipt.receipt_date}
                  </td>
                  <td className="border px-4 py-3 font-semibold text-gray-900">
                    {receipt.loadings?.loading_no ?? "-"}
                  </td>
                  <td className="border px-4 py-3 font-bold text-gray-900">
                    Rs. {Number(receipt.amount || 0).toLocaleString("en-PK")}
                  </td>
                  <td className="border px-4 py-3 font-semibold text-gray-900">
                    {receipt.payment_method}
                  </td>
                  <td className="border px-4 py-3 font-semibold text-gray-900">
                    {receipt.remarks ?? "-"}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
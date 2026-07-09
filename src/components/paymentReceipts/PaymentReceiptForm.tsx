type BookingRelation = {
  booking_no: string | null;
  sender_name: string | null;
  freight: number | string | null;
};

type LoadingOption = {
  id: string;
  loading_no: string | null;
  remaining_amount: number | string | null;
  bookings: BookingRelation | BookingRelation[] | null;
};

type Props = {
  loadingId: string;
  setLoadingId: (value: string) => void;
  receiptNo: string;
  setReceiptNo: (value: string) => void;
  receiptDate: string;
  setReceiptDate: (value: string) => void;
  amount: string;
  setAmount: (value: string) => void;
  paymentMethod: string;
  setPaymentMethod: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  loadings: LoadingOption[];
  onSave: () => void;
  isSaving: boolean;
};

function getSingleRelation<T>(relation: T | T[] | null | undefined): T | null {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation ?? null;
}

function formatAmount(value: number | string | null | undefined) {
  return Number(value ?? 0).toLocaleString("en-PK");
}

export default function PaymentReceiptForm({
  loadingId,
  setLoadingId,
  receiptNo,
  setReceiptNo,
  receiptDate,
  setReceiptDate,
  amount,
  setAmount,
  paymentMethod,
  setPaymentMethod,
  remarks,
  setRemarks,
  loadings,
  onSave,
  isSaving,
}: Props) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md">
      <h2 className="mb-6 text-2xl font-bold text-gray-900">
        Create Payment Receipt
      </h2>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        <input
          placeholder="Receipt No"
          value={receiptNo}
          onChange={(e) => setReceiptNo(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        />

        <input
          type="date"
          value={receiptDate}
          onChange={(e) => setReceiptDate(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        />

        <select
          value={loadingId}
          onChange={(e) => setLoadingId(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 md:col-span-2"
        >
          <option value="">Select Loading</option>

          {loadings.map((loading) => {
            const booking = getSingleRelation(loading.bookings);

            return (
              <option key={loading.id} value={loading.id}>
                {loading.loading_no ?? "-"} | {booking?.sender_name ?? "-"} |
                Freight Rs. {formatAmount(booking?.freight)} | Remaining Rs.{" "}
                {formatAmount(loading.remaining_amount)}
              </option>
            );
          })}
        </select>

        <input
          type="number"
          placeholder="Received Amount"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        />

        <select
          value={paymentMethod}
          onChange={(e) => setPaymentMethod(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900"
        >
          <option>Cash</option>
          <option>Bank</option>
          <option>Cheque</option>
          <option>Online Transfer</option>
          <option>Account</option>
        </select>

        <textarea
          placeholder="Remarks"
          value={remarks}
          onChange={(e) => setRemarks(e.target.value)}
          disabled={isSaving}
          className="rounded-lg border border-gray-300 bg-white p-3 font-semibold text-gray-900 md:col-span-2"
        />
      </div>

      <button
        onClick={onSave}
        disabled={isSaving}
        className="mt-6 rounded-lg bg-blue-600 px-6 py-3 font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
      >
        {isSaving ? "Saving..." : "Save Receipt"}
      </button>
    </div>
  );
}
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

type ExpenseFormProps = {
  expenseNo: string;
  setExpenseNo: (value: string) => void;
  expenseDate: string;
  setExpenseDate: (value: string) => void;
  loadingId: string;
  setLoadingId: (value: string) => void;
  description: string;
  setDescription: (value: string) => void;
  loadings: LoadingRecord[];
  selectedLoading: LoadingRecord | null;
};

export default function ExpenseForm({
  expenseNo,
  setExpenseNo,
  expenseDate,
  setExpenseDate,
  loadingId,
  setLoadingId,
  description,
  setDescription,
  loadings,
  selectedLoading,
}: ExpenseFormProps) {
  return (
    <div>
      <div className="mb-8">
        <h2 className="text-3xl font-bold text-gray-900">
          Create New Expense Voucher
        </h2>

        <p className="mt-1 text-base font-medium text-gray-900">
          Select a loading, create an expense voucher and add multiple expense
          items.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        <input
          type="text"
          placeholder="Expense Voucher No"
          value={expenseNo}
          onChange={(event) => setExpenseNo(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        />

        <input
          type="date"
          value={expenseDate}
          onChange={(event) => setExpenseDate(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
        />

        <select
          value={loadingId}
          onChange={(event) => setLoadingId(event.target.value)}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 md:col-span-2"
        >
          <option value="">Select Loading</option>

          {loadings.map((loading) => (
            <option key={loading.id} value={loading.id}>
              {loading.loading_no} -{" "}
              {loading.vehicles?.vehicle_no ?? "No Vehicle"} - {loading.route}
            </option>
          ))}
        </select>

        <textarea
          placeholder="Description"
          value={description}
          onChange={(event) => setDescription(event.target.value)}
          rows={3}
          className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 md:col-span-2"
        />
      </div>

      {selectedLoading && (
        <div className="mt-8 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              Loading Number
            </p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.loading_no}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              Vehicle Number
            </p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.vehicles?.vehicle_no ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              Driver Name
            </p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.drivers?.name ?? "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              Route
            </p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.route || "-"}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              Loading Date
            </p>
            <p className="mt-1 text-lg font-bold text-gray-900">
              {selectedLoading.loading_date || "-"}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
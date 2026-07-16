"use client";

import {
  type PetrolPumpOption,
  type PetrolPumpPaymentMethod,
  formatAmount,
} from "./PetrolPumpPayments";

type Props = {
  paymentDate: string;
  setPaymentDate: (value: string) => void;
  petrolPumpId: string;
  setPetrolPumpId: (value: string) => void;
  amount: string;
  setAmount: (value: string) => void;
  paymentMethod: PetrolPumpPaymentMethod;
  setPaymentMethod: (value: PetrolPumpPaymentMethod) => void;
  referenceNo: string;
  setReferenceNo: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  pumps: PetrolPumpOption[];
  selectedPump: PetrolPumpOption | null;
  editingOriginalAmount: number;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

const paymentMethods: PetrolPumpPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
];

function getStatus(balance: number) {
  if (balance > 0) return "Payable";
  if (balance < 0) return "Advance";
  return "Settled";
}

function getStatusClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") return "border-green-200 bg-green-100 text-green-700";
  return "border-blue-200 bg-blue-100 text-blue-700";
}

export default function PetrolPumpPaymentForm({
  paymentDate,
  setPaymentDate,
  petrolPumpId,
  setPetrolPumpId,
  amount,
  setAmount,
  paymentMethod,
  setPaymentMethod,
  referenceNo,
  setReferenceNo,
  remarks,
  setRemarks,
  pumps,
  selectedPump,
  editingOriginalAmount,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const paymentAmount = Number(amount || 0);
  const balanceAfterPayment = selectedPump
    ? selectedPump.currentBalance +
      (isEditing ? editingOriginalAmount : 0) -
      paymentAmount
    : 0;
  const statusAfterPayment = getStatus(balanceAfterPayment);
  const payableAfterPayment =
    balanceAfterPayment > 0 ? balanceAfterPayment : 0;
  const advanceAfterPayment =
    balanceAfterPayment < 0 ? Math.abs(balanceAfterPayment) : 0;

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit Pump Payment" : "Add Pump Payment"}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Record payments made to petrol pumps. Overpayment will be treated as
            advance.
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            Cancel Edit
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Date
          </label>
          <input
            type="date"
            value={paymentDate}
            onChange={(event) => setPaymentDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Petrol Pump
          </label>
          <select
            value={petrolPumpId}
            onChange={(event) => setPetrolPumpId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Petrol Pump</option>
            {pumps.map((pump) => (
              <option key={pump.id} value={pump.id}>
                {pump.pumpName} - {pump.ownerName}
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
            min="0"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            placeholder="0"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Method
          </label>
          <select
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as PetrolPumpPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
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
            Reference No
          </label>
          <input
            type="text"
            value={referenceNo}
            onChange={(event) => setReferenceNo(event.target.value)}
            placeholder="Cheque / transfer / slip no"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Remarks
          </label>
          <input
            type="text"
            value={remarks}
            onChange={(event) => setRemarks(event.target.value)}
            placeholder="Remarks"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      {selectedPump && (
        <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Opening Balance</p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {formatAmount(selectedPump.openingBalance)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Total Diesel</p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {formatAmount(selectedPump.totalDiesel)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              Diesel Paid Allocation
            </p>
            <p className="mt-2 text-lg font-extrabold text-blue-700">
              {formatAmount(selectedPump.dieselPaid)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Manual Payments</p>
            <p className="mt-2 text-lg font-extrabold text-green-700">
              {formatAmount(selectedPump.manualPayments)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Current Balance</p>
            <p
              className={`mt-2 text-lg font-extrabold ${
                selectedPump.currentBalance > 0
                  ? "text-red-700"
                  : selectedPump.currentBalance < 0
                    ? "text-green-700"
                    : "text-blue-700"
              }`}
            >
              {formatAmount(selectedPump.currentBalance)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Status</p>
            <span
              className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                selectedPump.balanceStatus
              )}`}
            >
              {selectedPump.balanceStatus}
            </span>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Payable Amount</p>
            <p className="mt-2 text-lg font-extrabold text-red-700">
              {formatAmount(selectedPump.payableAmount)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Advance Amount</p>
            <p className="mt-2 text-lg font-extrabold text-green-700">
              {formatAmount(selectedPump.advanceAmount)}
            </p>
          </div>

          <div className="rounded-lg border border-blue-200 bg-blue-50 p-4 md:col-span-2 xl:col-span-4">
            <p className="text-sm font-bold text-gray-900">
              Balance After This Payment
            </p>
            <div className="mt-2 flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
              <p
                className={`text-2xl font-extrabold ${
                  balanceAfterPayment > 0
                    ? "text-red-700"
                    : balanceAfterPayment < 0
                      ? "text-green-700"
                      : "text-blue-700"
                }`}
              >
                {formatAmount(balanceAfterPayment)}
              </p>

              <div className="flex flex-wrap gap-2">
                <span
                  className={`inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                    statusAfterPayment
                  )}`}
                >
                  {statusAfterPayment}
                </span>
                <span className="inline-flex rounded-full border border-red-200 bg-white px-3 py-1 text-sm font-bold text-red-700">
                  Payable: {formatAmount(payableAfterPayment)}
                </span>
                <span className="inline-flex rounded-full border border-green-200 bg-white px-3 py-1 text-sm font-bold text-green-700">
                  Advance: {formatAmount(advanceAfterPayment)}
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="mt-6 flex justify-end">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? "Saving..."
            : isEditing
              ? "Update Payment"
              : "Save Payment"}
        </button>
      </div>
    </div>
  );
}
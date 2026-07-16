"use client";

import {
  type BrokerPaymentMethod,
  type BrokerRow,
  type BrokerTransactionType,
  type DriverOption,
  type LoadingOption,
  type VehicleOption,
  formatAmount,
  getBrokerStatus,
  getTransactionEffect,
} from "./Brokers";

type Props = {
  selectedBrokerId: string;
  setSelectedBrokerId: (value: string) => void;
  transactionDate: string;
  setTransactionDate: (value: string) => void;
  transactionType: BrokerTransactionType;
  setTransactionType: (value: BrokerTransactionType) => void;
  amount: string;
  setAmount: (value: string) => void;
  paymentMethod: BrokerPaymentMethod;
  setPaymentMethod: (value: BrokerPaymentMethod) => void;
  referenceNo: string;
  setReferenceNo: (value: string) => void;
  description: string;
  setDescription: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  loadingId: string;
  setLoadingId: (value: string) => void;
  vehicleId: string;
  setVehicleId: (value: string) => void;
  driverId: string;
  setDriverId: (value: string) => void;
  brokers: BrokerRow[];
  selectedBroker: BrokerRow | null;
  loadings: LoadingOption[];
  vehicles: VehicleOption[];
  drivers: DriverOption[];
  editingOriginalTransactionType: BrokerTransactionType;
  editingOriginalAmount: number;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

const transactionTypes: BrokerTransactionType[] = [
  "Broker Payable",
  "Payment To Broker",
  "Payment From Broker",
  "Advance To Broker",
  "Adjustment",
];

const paymentMethods: BrokerPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

function getStatusClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-100 text-red-700";
  if (status === "Advance") return "border-green-200 bg-green-100 text-green-700";
  return "border-blue-200 bg-blue-100 text-blue-700";
}

export default function BrokerTransactionForm({
  selectedBrokerId,
  setSelectedBrokerId,
  transactionDate,
  setTransactionDate,
  transactionType,
  setTransactionType,
  amount,
  setAmount,
  paymentMethod,
  setPaymentMethod,
  referenceNo,
  setReferenceNo,
  description,
  setDescription,
  remarks,
  setRemarks,
  loadingId,
  setLoadingId,
  vehicleId,
  setVehicleId,
  driverId,
  setDriverId,
  brokers,
  selectedBroker,
  loadings,
  vehicles,
  drivers,
  editingOriginalTransactionType,
  editingOriginalAmount,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const transactionAmount = Number(amount || 0);
  const reversedBalance =
    selectedBroker && isEditing
      ? selectedBroker.currentBalance -
        getTransactionEffect(editingOriginalTransactionType, editingOriginalAmount)
      : selectedBroker?.currentBalance ?? 0;
  const balanceAfterTransaction =
    reversedBalance + getTransactionEffect(transactionType, transactionAmount);
  const statusAfterTransaction = getBrokerStatus(balanceAfterTransaction);
  const payableAfter =
    balanceAfterTransaction > 0 ? balanceAfterTransaction : 0;
  const advanceAfter =
    balanceAfterTransaction < 0 ? Math.abs(balanceAfterTransaction) : 0;

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit Broker Transaction" : "Add Broker Transaction"}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Record broker payable, payments, advances and adjustments.
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

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Broker
          </label>
          <select
            value={selectedBrokerId}
            onChange={(event) => setSelectedBrokerId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Broker</option>
            {brokers.map((broker) => (
              <option key={broker.id} value={broker.id}>
                {broker.brokerName}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Transaction Date
          </label>
          <input
            type="date"
            value={transactionDate}
            onChange={(event) => setTransactionDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Transaction Type
          </label>
          <select
            value={transactionType}
            onChange={(event) =>
              setTransactionType(event.target.value as BrokerTransactionType)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {transactionTypes.map((type) => (
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
              setPaymentMethod(event.target.value as BrokerPaymentMethod)
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
            Loading Optional
          </label>
          <select
            value={loadingId}
            onChange={(event) => setLoadingId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Loading</option>
            {loadings.map((loading) => (
              <option key={loading.id} value={loading.id}>
                {loading.loadingNo} - {loading.route}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Vehicle Optional
          </label>
          <select
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Vehicle</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Driver Optional
          </label>
          <select
            value={driverId}
            onChange={(event) => setDriverId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Driver</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
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
            placeholder="Reference No"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="md:col-span-2 xl:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Description
          </label>
          <input
            type="text"
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            placeholder="Description"
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

      {selectedBroker && (
        <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Current Balance</p>
            <p
              className={`mt-2 text-lg font-extrabold ${
                selectedBroker.currentBalance > 0
                  ? "text-red-700"
                  : selectedBroker.currentBalance < 0
                    ? "text-green-700"
                    : "text-blue-700"
              }`}
            >
              {formatAmount(selectedBroker.currentBalance)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Payable</p>
            <p className="mt-2 text-lg font-extrabold text-red-700">
              {formatAmount(selectedBroker.payableAmount)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Advance</p>
            <p className="mt-2 text-lg font-extrabold text-green-700">
              {formatAmount(selectedBroker.advanceAmount)}
            </p>
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-gray-900">Status</p>
            <span
              className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                selectedBroker.balanceStatus
              )}`}
            >
              {selectedBroker.balanceStatus}
            </span>
          </div>

          <div className="rounded-lg border border-blue-200 bg-blue-50 p-4 md:col-span-2 xl:col-span-4">
            <p className="text-sm font-bold text-gray-900">
              Balance After This Transaction
            </p>
            <div className="mt-2 flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
              <p
                className={`text-2xl font-extrabold ${
                  balanceAfterTransaction > 0
                    ? "text-red-700"
                    : balanceAfterTransaction < 0
                      ? "text-green-700"
                      : "text-blue-700"
                }`}
              >
                {formatAmount(balanceAfterTransaction)}
              </p>

              <div className="flex flex-wrap gap-2">
                <span
                  className={`inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
                    statusAfterTransaction
                  )}`}
                >
                  {statusAfterTransaction}
                </span>
                <span className="rounded-full border border-red-200 bg-white px-3 py-1 text-sm font-bold text-red-700">
                  Payable: {formatAmount(payableAfter)}
                </span>
                <span className="rounded-full border border-green-200 bg-white px-3 py-1 text-sm font-bold text-green-700">
                  Advance: {formatAmount(advanceAfter)}
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
              ? "Update Transaction"
              : "Save Transaction"}
        </button>
      </div>
    </div>
  );
}
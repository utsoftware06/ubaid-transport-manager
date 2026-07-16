"use client";

import { useEffect } from "react";
import {
  type CashbookEntryType,
  type CashbookPersonType,
  type CashbookPaymentMethod,
  type VehicleOption,
  type DriverOption,
  type LoadingOption,
} from "./Cashbook";

type Props = {
  entryDate: string;
  setEntryDate: (value: string) => void;
  entryType: CashbookEntryType;
  setEntryType: (value: CashbookEntryType) => void;
  personType: CashbookPersonType;
  setPersonType: (value: CashbookPersonType) => void;
  personName: string;
  setPersonName: (value: string) => void;
  vehicleId: string;
  setVehicleId: (value: string) => void;
  driverId: string;
  setDriverId: (value: string) => void;
  loadingId: string;
  setLoadingId: (value: string) => void;
  paymentMethod: CashbookPaymentMethod;
  setPaymentMethod: (value: CashbookPaymentMethod) => void;
  amount: string;
  setAmount: (value: string) => void;
  description: string;
  setDescription: (value: string) => void;
  vehicles: VehicleOption[];
  drivers: DriverOption[];
  loadings: LoadingOption[];
  onSave: () => void;
  isSaving: boolean;
};

const entryTypes: CashbookEntryType[] = ["Cash In", "Cash Out"];

const personTypes: CashbookPersonType[] = [
  "Customer",
  "Driver",
  "Vehicle Owner",
  "Broker",
  "Adda",
  "Petrol Pump",
  "Workshop",
  "Other",
];

const paymentMethods: CashbookPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

export default function CashbookForm({
  entryDate,
  setEntryDate,
  entryType,
  setEntryType,
  personType,
  setPersonType,
  personName,
  setPersonName,
  vehicleId,
  setVehicleId,
  driverId,
  setDriverId,
  loadingId,
  setLoadingId,
  paymentMethod,
  setPaymentMethod,
  amount,
  setAmount,
  description,
  setDescription,
  vehicles,
  drivers,
  loadings,
  onSave,
  isSaving,
}: Props) {
  const selectedLoading =
    loadings.find((loading) => loading.id === loadingId) ?? null;

  useEffect(() => {
    if (!selectedLoading) return;

    if (!personName.trim() && selectedLoading.senderName) {
      setPersonName(selectedLoading.senderName);
    }

    if (!vehicleId && selectedLoading.vehicleId) {
      setVehicleId(selectedLoading.vehicleId);
    }

    if (!driverId && selectedLoading.driverId) {
      setDriverId(selectedLoading.driverId);
    }
  }, [
    driverId,
    personName,
    selectedLoading,
    setDriverId,
    setPersonName,
    setVehicleId,
    vehicleId,
  ]);

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          Manual Cashbook Entry
        </h2>
        <p className="mt-1 text-sm font-medium text-gray-900">
          Record daily cash received, cash paid, advances and office payments.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Entry Date
          </label>
          <input
            type="date"
            value={entryDate}
            onChange={(event) => setEntryDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Entry Type
          </label>
          <select
            value={entryType}
            onChange={(event) =>
              setEntryType(event.target.value as CashbookEntryType)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {entryTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Person Type
          </label>
          <select
            value={personType}
            onChange={(event) =>
              setPersonType(event.target.value as CashbookPersonType)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {personTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Person Name
          </label>
          <input
            type="text"
            value={personName}
            onChange={(event) => setPersonName(event.target.value)}
            placeholder="Enter person name"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Vehicle Optional
          </label>
          <select
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Vehicle</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo}
                {vehicle.ownerName && vehicle.ownerName !== "-"
                  ? ` - ${vehicle.ownerName}`
                  : ""}
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
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
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
            Loading Optional
          </label>
          <select
            value={loadingId}
            onChange={(event) => setLoadingId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Loading</option>
            {loadings.map((loading) => (
              <option key={loading.id} value={loading.id}>
                {loading.loadingNo} - {loading.vehicleNo} - {loading.route}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Method
          </label>
          <select
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as CashbookPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
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
            Amount
          </label>
          <input
            type="number"
            min="0"
            step="0.01"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            placeholder="Enter amount"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="md:col-span-2 xl:col-span-3">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Description
          </label>
          <input
            type="text"
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            placeholder="Enter transaction description"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      {selectedLoading && (
        <div className="mt-6 rounded-lg border border-blue-100 bg-blue-50 p-4">
          <p className="text-sm font-bold text-gray-900">
            Selected Loading: {selectedLoading.loadingNo}
          </p>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Vehicle: {selectedLoading.vehicleNo} | Driver:{" "}
            {selectedLoading.driverName} | Route: {selectedLoading.route}
          </p>
        </div>
      )}

      <div className="mt-6 flex justify-end">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving ? "Saving..." : "Save Cashbook Entry"}
        </button>
      </div>
    </div>
  );
}
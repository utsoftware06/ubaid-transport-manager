"use client";

import {
  type VehicleOption,
  type WorkshopPaymentStatus,
  formatAmount,
} from "./Workshop";

type Props = {
  workDate: string;
  setWorkDate: (value: string) => void;
  vehicleId: string;
  setVehicleId: (value: string) => void;
  workshopName: string;
  setWorkshopName: (value: string) => void;
  mechanicName: string;
  setMechanicName: (value: string) => void;
  workType: string;
  setWorkType: (value: string) => void;
  billNo: string;
  setBillNo: (value: string) => void;
  partsCost: string;
  setPartsCost: (value: string) => void;
  labourCost: string;
  setLabourCost: (value: string) => void;
  paidAmount: string;
  setPaidAmount: (value: string) => void;
  nextServiceDate: string;
  setNextServiceDate: (value: string) => void;
  odometer: string;
  setOdometer: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  vehicles: VehicleOption[];
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

function getPaymentStatus(
  paidAmount: number,
  totalCost: number
): WorkshopPaymentStatus {
  if (paidAmount <= 0) return "Unpaid";
  if (paidAmount >= totalCost) return "Paid";
  return "Partial";
}

function getStatusClass(status: WorkshopPaymentStatus) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

export default function WorkshopForm({
  workDate,
  setWorkDate,
  vehicleId,
  setVehicleId,
  workshopName,
  setWorkshopName,
  mechanicName,
  setMechanicName,
  workType,
  setWorkType,
  billNo,
  setBillNo,
  partsCost,
  setPartsCost,
  labourCost,
  setLabourCost,
  paidAmount,
  setPaidAmount,
  nextServiceDate,
  setNextServiceDate,
  odometer,
  setOdometer,
  remarks,
  setRemarks,
  vehicles,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const parts = Number(partsCost || 0);
  const labour = Number(labourCost || 0);
  const paid = Number(paidAmount || 0);
  const totalCost = parts + labour;
  const remainingAmount = Math.max(totalCost - paid, 0);
  const paymentStatus = getPaymentStatus(paid, totalCost);

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {isEditing ? "Edit Workshop Entry" : "Add Workshop Entry"}
        </h2>
        <p className="mt-1 text-sm font-medium text-gray-900">
          Enter repair, service, parts and payment details.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Work Date
          </label>
          <input
            type="date"
            value={workDate}
            onChange={(event) => setWorkDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Vehicle
          </label>
          <select
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Vehicle</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo} - {vehicle.ownerName}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Workshop Name
          </label>
          <input
            type="text"
            value={workshopName}
            onChange={(event) => setWorkshopName(event.target.value)}
            placeholder="Workshop name"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Mechanic Name
          </label>
          <input
            type="text"
            value={mechanicName}
            onChange={(event) => setMechanicName(event.target.value)}
            placeholder="Mechanic name"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Work Type
          </label>
          <input
            type="text"
            value={workType}
            onChange={(event) => setWorkType(event.target.value)}
            placeholder="Oil, tyre, repair..."
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Bill No
          </label>
          <input
            type="text"
            value={billNo}
            onChange={(event) => setBillNo(event.target.value)}
            placeholder="Bill no"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Parts Cost
          </label>
          <input
            type="number"
            min="0"
            value={partsCost}
            onChange={(event) => setPartsCost(event.target.value)}
            placeholder="0"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Labour Cost
          </label>
          <input
            type="number"
            min="0"
            value={labourCost}
            onChange={(event) => setLabourCost(event.target.value)}
            placeholder="0"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Total Cost</p>
          <p className="mt-2 text-xl font-extrabold text-gray-900">
            {formatAmount(totalCost)}
          </p>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Paid Amount
          </label>
          <input
            type="number"
            min="0"
            value={paidAmount}
            onChange={(event) => setPaidAmount(event.target.value)}
            placeholder="0"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Remaining Amount</p>
          <p className="mt-2 text-xl font-extrabold text-red-700">
            {formatAmount(remainingAmount)}
          </p>
        </div>

        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <p className="text-sm font-bold text-gray-900">Payment Status</p>
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
            Next Service Date
          </label>
          <input
            type="date"
            value={nextServiceDate}
            onChange={(event) => setNextServiceDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Odometer
          </label>
          <input
            type="number"
            min="0"
            value={odometer}
            onChange={(event) => setOdometer(event.target.value)}
            placeholder="Odometer reading"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="md:col-span-2 xl:col-span-3">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Remarks
          </label>
          <input
            type="text"
            value={remarks}
            onChange={(event) => setRemarks(event.target.value)}
            placeholder="Remarks"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      <div className="mt-6 flex flex-col justify-end gap-3 sm:flex-row">
        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg bg-gray-200 px-6 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            Cancel Edit
          </button>
        )}

        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? "Saving..."
            : isEditing
              ? "Update Workshop Entry"
              : "Save Workshop Entry"}
        </button>
      </div>
    </div>
  );
}
"use client";

import {
  type DriverOption,
  type EmployeeStatus,
  type EmployeeType,
} from "./Employees";

type Props = {
  employeeName: string;
  setEmployeeName: (value: string) => void;
  employeeType: EmployeeType;
  setEmployeeType: (value: EmployeeType) => void;
  phone: string;
  setPhone: (value: string) => void;
  cnic: string;
  setCnic: (value: string) => void;
  address: string;
  setAddress: (value: string) => void;
  joiningDate: string;
  setJoiningDate: (value: string) => void;
  monthlySalary: string;
  setMonthlySalary: (value: string) => void;
  driverId: string;
  setDriverId: (value: string) => void;
  status: EmployeeStatus;
  setStatus: (value: EmployeeStatus) => void;
  drivers: DriverOption[];
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

const employeeTypes: EmployeeType[] = [
  "Driver",
  "Munshi",
  "Accountant",
  "Loader",
  "Office Staff",
  "Helper",
  "Cleaner",
  "Security Guard",
  "Mechanic",
  "Other",
];

const statuses: EmployeeStatus[] = ["Active", "Inactive"];

export default function EmployeeForm({
  employeeName,
  setEmployeeName,
  employeeType,
  setEmployeeType,
  phone,
  setPhone,
  cnic,
  setCnic,
  address,
  setAddress,
  joiningDate,
  setJoiningDate,
  monthlySalary,
  setMonthlySalary,
  driverId,
  setDriverId,
  status,
  setStatus,
  drivers,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit Employee" : "Add Employee"}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            Maintain driver and office staff profile details.
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
            Employee Name
          </label>
          <input
            type="text"
            value={employeeName}
            onChange={(event) => setEmployeeName(event.target.value)}
            placeholder="Employee name"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Employee Type
          </label>
          <select
            value={employeeType}
            onChange={(event) =>
              setEmployeeType(event.target.value as EmployeeType)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {employeeTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>

        {employeeType === "Driver" && (
          <div>
            <label className="mb-2 block text-sm font-bold text-gray-900">
              Driver
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
        )}

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Phone
          </label>
          <input
            type="text"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            placeholder="Phone"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            CNIC
          </label>
          <input
            type="text"
            value={cnic}
            onChange={(event) => setCnic(event.target.value)}
            placeholder="CNIC"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Address
          </label>
          <input
            type="text"
            value={address}
            onChange={(event) => setAddress(event.target.value)}
            placeholder="Address"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Joining Date
          </label>
          <input
            type="date"
            value={joiningDate}
            onChange={(event) => setJoiningDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Monthly Salary
          </label>
          <input
            type="number"
            min="0"
            value={monthlySalary}
            onChange={(event) => setMonthlySalary(event.target.value)}
            placeholder="0"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Status
          </label>
          <select
            value={status}
            onChange={(event) => setStatus(event.target.value as EmployeeStatus)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {statuses.map((statusOption) => (
              <option key={statusOption} value={statusOption}>
                {statusOption}
              </option>
            ))}
          </select>
        </div>
      </div>

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
              ? "Update Employee"
              : "Save Employee"}
        </button>
      </div>
    </div>
  );
}
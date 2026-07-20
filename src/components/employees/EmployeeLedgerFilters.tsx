"use client";

import {
  type Dispatch,
  type SetStateAction,
} from "react";
import {
  type EmployeeLedgerEmployeeOption,
  type EmployeeLedgerFilterValues,
} from "./EmployeeLedger";

type Props = {
  filters: EmployeeLedgerFilterValues;
  setFilters: Dispatch<SetStateAction<EmployeeLedgerFilterValues>>;
  employees: EmployeeLedgerEmployeeOption[];
  transactionTypes: string[];
  onReset: () => void;
};

export default function EmployeeLedgerFilters({
  filters,
  setFilters,
  employees,
  transactionTypes,
  onReset,
}: Props) {
  function updateFilter<K extends keyof EmployeeLedgerFilterValues>(
    key: K,
    value: EmployeeLedgerFilterValues[K]
  ) {
    setFilters((current) => ({
      ...current,
      [key]: value,
    }));
  }

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <h2 className="text-2xl font-bold text-gray-900">Ledger Filters</h2>

      <div className="mt-6 grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Employee
          </label>
          <select
            value={filters.employeeId}
            onChange={(event) => updateFilter("employeeId", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Employees</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.employeeName} - {employee.employeeType}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            From Date
          </label>
          <input
            type="date"
            value={filters.fromDate}
            onChange={(event) => updateFilter("fromDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            To Date
          </label>
          <input
            type="date"
            value={filters.toDate}
            onChange={(event) => updateFilter("toDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Transaction Type
          </label>
          <select
            value={filters.transactionType}
            onChange={(event) =>
              updateFilter("transactionType", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">All Types</option>
            {transactionTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>

        <div className="md:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Search
          </label>
          <input
            type="text"
            value={filters.search}
            onChange={(event) => updateFilter("search", event.target.value)}
            placeholder="Search employee, type, description, reference, remarks or method..."
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      <div className="mt-6">
        <button
          type="button"
          onClick={onReset}
          className="rounded-lg bg-gray-800 px-6 py-3 font-bold text-white hover:bg-gray-900"
        >
          Reset
        </button>
      </div>
    </div>
  );
}
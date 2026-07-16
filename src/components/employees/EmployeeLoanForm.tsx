"use client";

import {
  type EmployeeLoanPaymentMethod,
  type EmployeeOption,
  formatAmount,
} from "./EmployeeLoans";

type Props = {
  employeeId: string;
  setEmployeeId: (value: string) => void;
  loanDate: string;
  setLoanDate: (value: string) => void;
  loanAmount: string;
  setLoanAmount: (value: string) => void;
  monthlyInstallment: string;
  setMonthlyInstallment: (value: string) => void;
  paymentMethod: EmployeeLoanPaymentMethod;
  setPaymentMethod: (value: EmployeeLoanPaymentMethod) => void;
  referenceNo: string;
  setReferenceNo: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  employees: EmployeeOption[];
  selectedEmployee: EmployeeOption | null;
  existingRecoveredAmount: number;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

const paymentMethods: EmployeeLoanPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

export default function EmployeeLoanForm({
  employeeId,
  setEmployeeId,
  loanDate,
  setLoanDate,
  loanAmount,
  setLoanAmount,
  monthlyInstallment,
  setMonthlyInstallment,
  paymentMethod,
  setPaymentMethod,
  referenceNo,
  setReferenceNo,
  remarks,
  setRemarks,
  employees,
  selectedEmployee,
  existingRecoveredAmount,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const loan = Number(loanAmount || 0);
  const recovered = isEditing ? existingRecoveredAmount : 0;
  const remaining = Math.max(loan - recovered, 0);
  const status = remaining <= 0 && loan > 0 ? "Completed" : "Active";

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit Employee Loan" : "New Employee Loan"}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Create employee loan records and automatically post paid amount to
            Cashbook.
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-5 py-2.5 text-sm font-bold text-gray-900 transition hover:bg-gray-100"
          >
            Cancel Edit
          </button>
        )}
      </div>

      {selectedEmployee && (
        <div className="mb-6 grid grid-cols-1 gap-4 md:grid-cols-2">
          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">Employee Name</p>
            <p className="mt-1 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeName}
            </p>
          </div>

          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">Employee Type</p>
            <p className="mt-1 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeType || "-"}
            </p>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Employee
          </label>
          <select
            value={employeeId}
            onChange={(event) => setEmployeeId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Employee</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.employeeName} - {employee.employeeType}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Loan Date
          </label>
          <input
            type="date"
            value={loanDate}
            onChange={(event) => setLoanDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Loan Amount
          </label>
          <input
            type="number"
            min="0"
            value={loanAmount}
            onChange={(event) => setLoanAmount(event.target.value)}
            placeholder="Loan Amount"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Monthly Installment
          </label>
          <input
            type="number"
            min="0"
            value={monthlyInstallment}
            onChange={(event) => setMonthlyInstallment(event.target.value)}
            placeholder="Monthly Installment"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Method
          </label>
          <select
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as EmployeeLoanPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
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
            placeholder="Reference No"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="md:col-span-2 xl:col-span-3">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Remarks
          </label>
          <textarea
            value={remarks}
            onChange={(event) => setRemarks(event.target.value)}
            placeholder="Remarks"
            rows={3}
            className="w-full resize-none rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">Loan Amount</p>
          <p className="mt-2 text-xl font-extrabold text-gray-900">
            {formatAmount(loan)}
          </p>
        </div>

        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">Already Recovered</p>
          <p className="mt-2 text-xl font-extrabold text-green-700">
            {formatAmount(recovered)}
          </p>
        </div>

        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">Remaining Amount</p>
          <p
            className={`mt-2 text-xl font-extrabold ${
              remaining > 0 ? "text-red-700" : "text-green-700"
            }`}
          >
            {formatAmount(remaining)}
          </p>
        </div>

        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">Status</p>
          <span
            className={`mt-2 inline-flex rounded-full px-3 py-1 text-sm font-extrabold ${
              status === "Completed"
                ? "bg-green-100 text-green-700"
                : "bg-orange-100 text-orange-700"
            }`}
          >
            {status}
          </span>
        </div>
      </div>

      <div className="mt-8 flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? "Saving..."
            : isEditing
              ? "Update Loan"
              : "Save Loan"}
        </button>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-8 py-3 font-bold text-gray-900 transition hover:bg-gray-100"
          >
            Cancel Edit
          </button>
        )}
      </div>
    </div>
  );
}
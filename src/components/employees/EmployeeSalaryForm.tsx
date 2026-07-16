"use client";

import {
  type EmployeeSalaryOption,
  type SalaryPaymentMethod,
  formatAmount,
} from "./EmployeeSalary";

type Props = {
  employeeId: string;
  setEmployeeId: (value: string) => void;
  salaryMonth: string;
  setSalaryMonth: (value: string) => void;
  basicSalary: string;
  setBasicSalary: (value: string) => void;
  bonus: string;
  setBonus: (value: string) => void;
  deduction: string;
  setDeduction: (value: string) => void;
  loanRecovery: string;
  setLoanRecovery: (value: string) => void;
  advanceRecovery: string;
  setAdvanceRecovery: (value: string) => void;
  paidAmount: string;
  setPaidAmount: (value: string) => void;
  paymentMethod: SalaryPaymentMethod;
  setPaymentMethod: (value: SalaryPaymentMethod) => void;
  referenceNo: string;
  setReferenceNo: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  employees: EmployeeSalaryOption[];
  selectedEmployee: EmployeeSalaryOption | null;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

const paymentMethods: SalaryPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

function toNumber(value: string) {
  const numericValue = Number(value || 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

export default function EmployeeSalaryForm({
  employeeId,
  setEmployeeId,
  salaryMonth,
  setSalaryMonth,
  basicSalary,
  setBasicSalary,
  bonus,
  setBonus,
  deduction,
  setDeduction,
  loanRecovery,
  setLoanRecovery,
  advanceRecovery,
  setAdvanceRecovery,
  paidAmount,
  setPaidAmount,
  paymentMethod,
  setPaymentMethod,
  referenceNo,
  setReferenceNo,
  remarks,
  setRemarks,
  employees,
  selectedEmployee,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const basic = toNumber(basicSalary);
  const bonusValue = toNumber(bonus);
  const deductionValue = toNumber(deduction);
  const loanRecoveryValue = toNumber(loanRecovery);
  const advanceRecoveryValue = toNumber(advanceRecovery);
  const paidValue = toNumber(paidAmount);
  const netSalary =
    basic + bonusValue - deductionValue - loanRecoveryValue - advanceRecoveryValue;
  const remainingAmount = Math.max(netSalary - paidValue, 0);
  const paymentStatus =
    paidValue <= 0 ? "Unpaid" : paidValue >= netSalary ? "Paid" : "Partial";

  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? "Edit Salary Record" : "Generate Salary"}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            Select an employee, calculate salary and record salary payment.
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-5 py-2.5 text-sm font-bold text-gray-900 hover:bg-gray-100"
          >
            Cancel Edit
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Employee
          </label>
          <select
            value={employeeId}
            onChange={(event) => setEmployeeId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">Select Employee</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.employeeName} - {employee.employeeType} -{" "}
                {formatAmount(employee.monthlySalary)} - Loan{" "}
                {formatAmount(employee.activeLoanRemaining)} / Installment{" "}
                {formatAmount(employee.monthlyInstallment)}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Salary Month
          </label>
          <input
            type="date"
            value={salaryMonth}
            onChange={(event) => setSalaryMonth(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Basic Salary
          </label>
          <input
            type="number"
            min="0"
            value={basicSalary}
            onChange={(event) => setBasicSalary(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Bonus
          </label>
          <input
            type="number"
            min="0"
            value={bonus}
            onChange={(event) => setBonus(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Deduction
          </label>
          <input
            type="number"
            min="0"
            value={deduction}
            onChange={(event) => setDeduction(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Loan Recovery
          </label>
          <input
            type="number"
            min="0"
            value={loanRecovery}
            onChange={(event) => setLoanRecovery(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Advance Recovery
          </label>
          <input
            type="number"
            min="0"
            value={advanceRecovery}
            onChange={(event) => setAdvanceRecovery(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
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
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Payment Method
          </label>
          <select
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as SalaryPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {paymentMethods.map((method) => (
              <option key={method}>{method}</option>
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
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div className="md:col-span-2">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            Remarks
          </label>
          <input
            type="text"
            value={remarks}
            onChange={(event) => setRemarks(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>

      {selectedEmployee && (
        <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">Employee</p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeName}
            </p>
          </div>
          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">Type</p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeType}
            </p>
          </div>
          <div className="rounded-xl border border-red-100 bg-red-50 p-4">
            <p className="text-sm font-bold text-gray-900">Active Loan</p>
            <p className="mt-2 text-lg font-extrabold text-red-700">
              {formatAmount(selectedEmployee.activeLoanRemaining)}
            </p>
          </div>
          <div className="rounded-xl border border-orange-100 bg-orange-50 p-4">
            <p className="text-sm font-bold text-gray-900">Installment</p>
            <p className="mt-2 text-lg font-extrabold text-orange-700">
              {formatAmount(selectedEmployee.monthlyInstallment)}
            </p>
          </div>
        </div>
      )}

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-3">
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">Net Salary</p>
          <p className="mt-2 text-xl font-extrabold text-blue-700">
            {formatAmount(Math.max(netSalary, 0))}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">Remaining Amount</p>
          <p className="mt-2 text-xl font-extrabold text-red-700">
            {formatAmount(remainingAmount)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">Payment Status</p>
          <span
            className={`mt-2 inline-flex rounded-full px-3 py-1 text-sm font-extrabold ${
              paymentStatus === "Paid"
                ? "bg-green-100 text-green-700"
                : paymentStatus === "Partial"
                  ? "bg-orange-100 text-orange-700"
                  : "bg-red-100 text-red-700"
            }`}
          >
            {paymentStatus}
          </span>
        </div>
      </div>

      <div className="mt-8 flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving ? "Saving..." : isEditing ? "Update Salary" : "Save Salary"}
        </button>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-8 py-3 font-bold text-gray-900 hover:bg-gray-100"
          >
            Cancel Edit
          </button>
        )}
      </div>
    </div>
  );
}
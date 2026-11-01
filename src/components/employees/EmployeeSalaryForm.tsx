"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
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
  const { t, dir } = useLanguage();
  const paymentMethodLabel = (method: SalaryPaymentMethod) => {
    const keys: Record<SalaryPaymentMethod, string> = {
      Cash: "cash",
      Bank: "bank",
      Cheque: "cheque",
      "Online Transfer": "onlineTransfer",
      Account: "account",
    };
    return t(`employeeSalary.paymentMethods.${keys[method]}`);
  };
  const statusLabel = (value: string) =>
    t(`common.paymentStatus.${value.toLowerCase()}`);
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
    <form dir={dir} onSubmit={(event) => { event.preventDefault(); void onSave(); }} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing
              ? t("employeeSalary.actions.edit")
              : t("employeeSalary.actions.generate")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("employeeSalary.formDescription")}
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-5 py-2.5 text-sm font-bold text-gray-900 hover:bg-gray-100"
          >
            {t("common.cancelEdit")}
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label htmlFor="salary-employee" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.employee")}
          </label>
          <select
            id="salary-employee"
            value={employeeId}
            onChange={(event) => setEmployeeId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("employeeSalary.placeholders.selectEmployee")}</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.employeeName} - {employee.employeeType} -{" "}
                {formatAmount(employee.monthlySalary)} - {t("employeeSalary.fields.activeLoan")}{" "}
                {formatAmount(employee.activeLoanRemaining)} / {t("employeeSalary.fields.installment")}{" "}
                {formatAmount(employee.monthlyInstallment)}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="salary-month" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.salaryMonth")}
          </label>
          <VoiceTypingField fieldLabel="salary month" mode="date"><input
            id="salary-month"
            type="date"
            value={salaryMonth}
            onChange={(event) => setSalaryMonth(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="salary-basic" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.basicSalary")}
          </label>
          <VoiceTypingField fieldLabel="salary basic" mode="amount"><input
            id="salary-basic"
            type="number"
            min="0"
            value={basicSalary}
            onChange={(event) => setBasicSalary(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="salary-bonus" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.bonus")}
          </label>
          <VoiceTypingField fieldLabel="salary bonus" mode="amount"><input
            id="salary-bonus"
            type="number"
            min="0"
            value={bonus}
            onChange={(event) => setBonus(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="salary-deduction" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.deduction")}
          </label>
          <VoiceTypingField fieldLabel="salary deduction" mode="amount"><input
            id="salary-deduction"
            type="number"
            min="0"
            value={deduction}
            onChange={(event) => setDeduction(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="salary-loan-recovery" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.loanRecovery")}
          </label>
          <VoiceTypingField fieldLabel="salary loan recovery" mode="amount"><input
            id="salary-loan-recovery"
            type="number"
            min="0"
            value={loanRecovery}
            onChange={(event) => setLoanRecovery(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="salary-advance-recovery" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.advanceRecovery")}
          </label>
          <VoiceTypingField fieldLabel="salary advance recovery" mode="amount"><input
            id="salary-advance-recovery"
            type="number"
            min="0"
            value={advanceRecovery}
            onChange={(event) => setAdvanceRecovery(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="salary-paid" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.paidAmount")}
          </label>
          <VoiceTypingField fieldLabel="salary paid" mode="amount"><input
            id="salary-paid"
            type="number"
            min="0"
            value={paidAmount}
            onChange={(event) => setPaidAmount(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="salary-payment-method" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.paymentMethod")}
          </label>
          <select
            id="salary-payment-method"
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as SalaryPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {paymentMethods.map((method) => (
              <option key={method}>{paymentMethodLabel(method)}</option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="salary-reference" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.referenceNo")}
          </label>
          <VoiceTypingField fieldLabel="salary reference" mode="identifier"><input
            id="salary-reference"
            type="text"
            value={referenceNo}
            onChange={(event) => setReferenceNo(event.target.value)}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div className="md:col-span-2">
          <label htmlFor="salary-remarks" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.remarks")}
          </label>
          <VoiceTypingField fieldLabel={t("common.remarks")} value={remarks} onValueChange={setRemarks} contextKey={`${employeeId}:${salaryMonth}:${isEditing ? "edit" : "new"}`}>
            <input
              id="salary-remarks"
              type="text"
              value={remarks}
              onChange={(event) => setRemarks(event.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>
      </div>

      {selectedEmployee && (
        <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              {t("employeeSalary.fields.employee")}
            </p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeName}
            </p>
          </div>
          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              {t("employeeSalary.fields.type")}
            </p>
            <p className="mt-2 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeType}
            </p>
          </div>
          <div className="rounded-xl border border-red-100 bg-red-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              {t("employeeSalary.fields.activeLoan")}
            </p>
            <p dir="ltr" className="mt-2 text-lg font-extrabold text-red-700">
              {formatAmount(selectedEmployee.activeLoanRemaining)}
            </p>
          </div>
          <div className="rounded-xl border border-orange-100 bg-orange-50 p-4">
            <p className="text-sm font-bold text-gray-900">
              {t("employeeSalary.fields.installment")}
            </p>
            <p dir="ltr" className="mt-2 text-lg font-extrabold text-orange-700">
              {formatAmount(selectedEmployee.monthlyInstallment)}
            </p>
          </div>
        </div>
      )}

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-3">
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.netSalary")}
          </p>
          <p dir="ltr" className="mt-2 text-xl font-extrabold text-blue-700">
            {formatAmount(Math.max(netSalary, 0))}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.remainingAmount")}
          </p>
          <p dir="ltr" className="mt-2 text-xl font-extrabold text-red-700">
            {formatAmount(remainingAmount)}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">
            {t("employeeSalary.fields.paymentStatus")}
          </p>
          <span
            className={`mt-2 inline-flex rounded-full px-3 py-1 text-sm font-extrabold ${
              paymentStatus === "Paid"
                ? "bg-green-100 text-green-700"
                : paymentStatus === "Partial"
                  ? "bg-orange-100 text-orange-700"
                  : "bg-red-100 text-red-700"
            }`}
          >
            {statusLabel(paymentStatus)}
          </span>
        </div>
      </div>

      <div className="mt-8 flex flex-col gap-3 sm:flex-row">
        <button
          type="submit"
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 font-bold text-white hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? t("common.states.saving")
            : isEditing
              ? t("employeeSalary.actions.update")
              : t("employeeSalary.actions.save")}
        </button>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-8 py-3 font-bold text-gray-900 hover:bg-gray-100"
          >
            {t("common.cancelEdit")}
          </button>
        )}
      </div>
    </form>
  );
}

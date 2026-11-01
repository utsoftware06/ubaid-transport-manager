"use client";

import {
  type EmployeeLoanPaymentMethod,
  type EmployeeOption,
  formatAmount,
} from "./EmployeeLoans";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  recordId: number | null;
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
  recordId,
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
  const { t, dir } = useLanguage();
  const loan = Number(loanAmount || 0);
  const recovered = isEditing ? existingRecoveredAmount : 0;
  const remaining = Math.max(loan - recovered, 0);
  const status = remaining <= 0 && loan > 0 ? "Completed" : "Active";

  return (
    <form dir={dir} onSubmit={(event) => { event.preventDefault(); void onSave(); }} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing
              ? t("employeeLoans.actions.editLoan")
              : t("employeeLoans.actions.newLoan")}
          </h2>
          <p className="mt-1 text-sm font-medium text-gray-900">
            {t("employeeLoans.formDescription")}
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-5 py-2.5 text-sm font-bold text-gray-900 transition hover:bg-gray-100"
          >
            {t("employeeLoans.actions.cancelEdit")}
          </button>
        )}
      </div>

      {selectedEmployee && (
        <div className="mb-6 grid grid-cols-1 gap-4 md:grid-cols-2">
          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">{t("employeeLoans.fields.employeeName")}</p>
            <p className="mt-1 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeName}
            </p>
          </div>

          <div className="rounded-xl border border-blue-100 bg-blue-50 p-4">
            <p className="text-sm font-bold text-gray-900">{t("employeeLoans.fields.employeeType")}</p>
            <p className="mt-1 text-lg font-extrabold text-gray-900">
              {selectedEmployee.employeeType || "-"}
            </p>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label htmlFor="loan-employee" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLoans.fields.employee")}
          </label>
          <select
            id="loan-employee"
            value={employeeId}
            onChange={(event) => setEmployeeId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("employeeLoans.placeholders.selectEmployee")}</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.employeeName} - {employee.employeeType}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="loan-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLoans.fields.loanDate")}
          </label>
          <VoiceTypingField fieldLabel="loan date" mode="date"><input
            id="loan-date"
            type="date"
            dir="ltr"
            value={loanDate}
            onChange={(event) => setLoanDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="loan-amount" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLoans.fields.loanAmount")}
          </label>
          <VoiceTypingField fieldLabel={t("employeeLoans.placeholders.loanAmount")} mode="amount"><input
            id="loan-amount"
            type="number"
            min="0"
            value={loanAmount}
            onChange={(event) => setLoanAmount(event.target.value)}
            placeholder={t("employeeLoans.placeholders.loanAmount")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="loan-installment" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLoans.fields.monthlyInstallment")}
          </label>
          <VoiceTypingField fieldLabel={t("employeeLoans.placeholders.monthlyInstallment")} mode="amount"><input
            id="loan-installment"
            type="number"
            min="0"
            value={monthlyInstallment}
            onChange={(event) => setMonthlyInstallment(event.target.value)}
            placeholder={t("employeeLoans.placeholders.monthlyInstallment")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="loan-payment-method" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLoans.fields.paymentMethod")}
          </label>
          <select
            id="loan-payment-method"
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as EmployeeLoanPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {paymentMethods.map((method) => (
              <option key={method} value={method}>
                {t(`employeeLoans.paymentMethods.${method === "Online Transfer" ? "onlineTransfer" : method.toLowerCase()}`)}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="loan-reference" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLoans.fields.referenceNo")}
          </label>
          <VoiceTypingField fieldLabel={t("employeeLoans.placeholders.referenceNo")} mode="identifier"><input
            id="loan-reference"
            type="text"
            value={referenceNo}
            onChange={(event) => setReferenceNo(event.target.value)}
            placeholder={t("employeeLoans.placeholders.referenceNo")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div className="md:col-span-2 xl:col-span-3">
          <label htmlFor="loan-remarks" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLoans.fields.remarks")}
          </label>
          <VoiceTypingField fieldLabel={t("employeeLoans.fields.remarks")} value={remarks} onValueChange={setRemarks} contextKey={`${employeeId}:${recordId ?? "new"}`}>
            <textarea
              id="loan-remarks"
              value={remarks}
              onChange={(event) => setRemarks(event.target.value)}
              placeholder={t("employeeLoans.placeholders.remarks")}
              rows={3}
              className="w-full resize-none rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none transition placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("employeeLoans.fields.loanAmount")}</p>
          <p dir="ltr" className="mt-2 text-xl font-extrabold text-gray-900">
            {formatAmount(loan)}
          </p>
        </div>

        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("employeeLoans.fields.alreadyRecovered")}</p>
          <p dir="ltr" className="mt-2 text-xl font-extrabold text-green-700">
            {formatAmount(recovered)}
          </p>
        </div>

        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("employeeLoans.fields.remainingAmount")}</p>
          <p
            dir="ltr"
            className={`mt-2 text-xl font-extrabold ${
              remaining > 0 ? "text-red-700" : "text-green-700"
            }`}
          >
            {formatAmount(remaining)}
          </p>
        </div>

        <div className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("employeeLoans.fields.status")}</p>
          <span
            className={`mt-2 inline-flex rounded-full px-3 py-1 text-sm font-extrabold ${
              status === "Completed"
                ? "bg-green-100 text-green-700"
                : "bg-orange-100 text-orange-700"
            }`}
          >
            {t(`employeeLoans.statuses.${status.toLowerCase()}`)}
          </span>
        </div>
      </div>

      <div className="mt-8 flex flex-col gap-3 sm:flex-row">
        <button
          type="submit"
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? t("common.saving")
            : isEditing
              ? t("employeeLoans.actions.updateLoan")
              : t("employeeLoans.actions.saveLoan")}
        </button>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg border border-gray-300 bg-white px-8 py-3 font-bold text-gray-900 transition hover:bg-gray-100"
          >
            {t("employeeLoans.actions.cancelEdit")}
          </button>
        )}
      </div>
    </form>
  );
}

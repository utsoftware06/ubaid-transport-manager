"use client";

import {
  type Dispatch,
  type SetStateAction,
} from "react";
import {
  type EmployeeLedgerEmployeeOption,
  type EmployeeLedgerFilterValues,
} from "./EmployeeLedger";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

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
  const { t, dir } = useLanguage();
  const transactionTypeLabel = (type: string) => {
    const keyByType: Record<string, string> = {
      "Salary Generated": "salaryGenerated",
      "Salary Paid": "salaryPaid",
      "Employee Loan": "employeeLoan",
      "Loan Recovery": "loanRecovery",
      "Advance Salary": "advanceSalary",
      "Advance Recovery": "advanceRecovery",
      "Adjustment Debit": "adjustmentDebit",
      "Adjustment Credit": "adjustmentCredit",
    };
    const key = keyByType[type];
    return key ? t(`employeeLedger.transactionTypes.${key}`) : type;
  };
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
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <h2 className="text-2xl font-bold text-gray-900">{t("employeeLedger.filters.title")}</h2>

      <div className="mt-6 grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label htmlFor="ledger-employee-filter" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLedger.fields.employee")}
          </label>
          <select
            id="ledger-employee-filter"
            value={filters.employeeId}
            onChange={(event) => updateFilter("employeeId", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("employeeLedger.filters.allEmployees")}</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.employeeName} - {employee.employeeType}
              </option>
            ))}
          </select>
        </div>


        <div>
          <label htmlFor="ledger-from-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLedger.filters.fromDate")}
          </label>
          <VoiceTypingField fieldLabel="ledger from date" mode="date"><input
            id="ledger-from-date"
            type="date"
            dir="ltr"
            value={filters.fromDate}
            onChange={(event) => updateFilter("fromDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="ledger-to-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLedger.filters.toDate")}
          </label>
          <VoiceTypingField fieldLabel="ledger to date" mode="date"><input
            id="ledger-to-date"
            type="date"
            dir="ltr"
            value={filters.toDate}
            onChange={(event) => updateFilter("toDate", event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="ledger-transaction-type" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employeeLedger.fields.transactionType")}
          </label>
          <select
            id="ledger-transaction-type"
            value={filters.transactionType}
            onChange={(event) =>
              updateFilter("transactionType", event.target.value)
            }
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("employeeLedger.filters.allTypes")}</option>
            {transactionTypes.map((type) => (
              <option key={type} value={type}>
                {transactionTypeLabel(type)}
              </option>
            ))}
          </select>
        </div>


        <div className="md:col-span-2">
          <label htmlFor="ledger-search" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.actions.search")}
          </label>
          <VoiceTypingField fieldLabel={t("employeeLedger.filters.searchPlaceholder")} mode="text"><input
            id="ledger-search"
            type="text"
            value={filters.search}
            onChange={(event) => updateFilter("search", event.target.value)}
            placeholder={t("employeeLedger.filters.searchPlaceholder")}
            className="w-full rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 outline-none placeholder:text-gray-600 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>

      </div>

      <div className="mt-6">
        <button
          type="button"
          onClick={onReset}
          className="rounded-lg bg-gray-800 px-6 py-3 font-bold text-white hover:bg-gray-900"
        >
          {t("common.reset")}
        </button>
      </div>
    </div>
  );
}

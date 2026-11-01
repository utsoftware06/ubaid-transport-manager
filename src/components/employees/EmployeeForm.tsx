"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import {
  type DriverOption,
  type EmployeeStatus,
  type EmployeeType,
} from "./Employees";

type AddaOption = { id: string; name: string };

type Props = {
  contextKey?: string;
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
  addaId: string;
  setAddaId: (value: string) => void;
  addas: AddaOption[];
  isSuperAdmin: boolean;
  isSaveContextLoading: boolean;
  isSaveDisabled: boolean;
  drivers: DriverOption[];
  onSave: () => void | Promise<void>;
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
  contextKey = "employee-form",
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
  addaId,
  setAddaId,
  addas,
  isSuperAdmin,
  isSaveContextLoading,
  isSaveDisabled,
  drivers,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const { t, dir } = useLanguage();
  const employeeTypeLabel = (type: EmployeeType) => {
    const keys: Record<EmployeeType, string> = {
      Driver: "driver",
      Munshi: "munshi",
      Accountant: "accountant",
      Loader: "loader",
      "Office Staff": "officeStaff",
      Helper: "helper",
      Cleaner: "cleaner",
      "Security Guard": "securityGuard",
      Mechanic: "mechanic",
      Other: "other",
    };
    return t(`employees.types.${keys[type]}`);
  };
  const statusLabel = (value: EmployeeStatus) =>
    t(`employees.statuses.${value.toLowerCase()}`);

  return (
    <form
      dir={dir}
      onSubmit={(event) => {
        event.preventDefault();
        void onSave();
      }}
      className="rounded-xl bg-white p-6 shadow-md md:p-8"
    >
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing
              ? t("employees.actions.edit")
              : t("employees.actions.add")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("employees.formDescription")}
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            aria-label={t("common.cancelEdit")}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            {t("common.cancelEdit")}
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label htmlFor="employee-name" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employees.fields.name")}
          </label>
          <VoiceTypingField fieldLabel={t("employees.fields.name")} value={employeeName} onValueChange={setEmployeeName} contextKey={contextKey}>
          <input
            type="text"
            id="employee-name"
            name="employeeName"
            value={employeeName}
            onChange={(event) => setEmployeeName(event.target.value)}
            placeholder={t("employees.placeholders.name")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label htmlFor="employee-type" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employees.fields.type")}
          </label>
          <select
            id="employee-type"
            name="employeeType"
            value={employeeType}
            onChange={(event) =>
              setEmployeeType(event.target.value as EmployeeType)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {employeeTypes.map((type) => (
              <option key={type} value={type}>
                {employeeTypeLabel(type)}
              </option>
            ))}
          </select>
        </div>

        {isSuperAdmin && (
          <div>
            <label htmlFor="employee-adda" className="mb-2 block text-sm font-bold text-gray-900">
              Adda
            </label>
            <select
              required
              id="employee-adda"
              name="addaId"
              value={addaId}
              onChange={(event) => setAddaId(event.target.value)}
              disabled={isSaveContextLoading}
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:bg-gray-100"
            >
              <option value="">{t("drivers.selectAdda")}</option>
              {addas.map((adda) => (
                <option key={adda.id} value={adda.id}>
                  {adda.name}
                </option>
              ))}
            </select>
          </div>
        )}

        {employeeType === "Driver" && (
          <div>
            <label htmlFor="employee-driver" className="mb-2 block text-sm font-bold text-gray-900">
              {t("common.driver")}
            </label>
            <select
              id="employee-driver"
              name="driverId"
              value={driverId}
              onChange={(event) => setDriverId(event.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            >
              <option value="">{t("employees.placeholders.selectDriver")}</option>
              {drivers.map((driver) => (
                <option key={driver.id} value={driver.id}>
                  {driver.name}
                </option>
              ))}
            </select>
          </div>
        )}


        <div>
          <label htmlFor="employee-phone" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employees.fields.phone")}
          </label>
          <VoiceTypingField fieldLabel={t("employees.placeholders.phone")} mode="phone"><input
            type="text"
            id="employee-phone"
            name="phone"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            placeholder={t("employees.placeholders.phone")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="employee-cnic" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employees.fields.cnic")}
          </label>
          <VoiceTypingField fieldLabel={t("employees.placeholders.cnic")} mode="cnic"><input
            type="text"
            id="employee-cnic"
            name="cnic"
            value={cnic}
            onChange={(event) => setCnic(event.target.value)}
            placeholder={t("employees.placeholders.cnic")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="employee-address" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employees.fields.address")}
          </label>
          <VoiceTypingField fieldLabel={t("employees.fields.address")} value={address} onValueChange={setAddress} contextKey={contextKey}>
            <input
              type="text"
              id="employee-address"
              name="address"
              value={address}
              onChange={(event) => setAddress(event.target.value)}
              placeholder={t("employees.placeholders.address")}
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>


        <div>
          <label htmlFor="employee-joining-date" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employees.fields.joiningDate")}
          </label>
          <VoiceTypingField fieldLabel="joining Date" mode="date"><input
            type="date"
            id="employee-joining-date"
            name="joiningDate"
            value={joiningDate}
            onChange={(event) => setJoiningDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label htmlFor="employee-monthly-salary" className="mb-2 block text-sm font-bold text-gray-900">
            {t("employees.fields.monthlySalary")}
          </label>
          <VoiceTypingField fieldLabel={t("employees.fields.monthlySalary")} mode="amount"><input
            type="number"
            id="employee-monthly-salary"
            name="monthlySalary"
            min="0"
            value={monthlySalary}
            onChange={(event) => setMonthlySalary(event.target.value)}
            placeholder="0"
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="employee-status" className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.status")}
          </label>
          <select
            id="employee-status"
            name="status"
            value={status}
            onChange={(event) => setStatus(event.target.value as EmployeeStatus)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {statuses.map((statusOption) => (
              <option key={statusOption} value={statusOption}>
                {statusLabel(statusOption)}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="mt-6 flex justify-end">
        <button
          type="submit"
          disabled={isSaving || isSaveContextLoading || isSaveDisabled}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? t("common.states.saving")
            : isEditing
              ? t("employees.actions.update")
              : t("employees.actions.save")}
        </button>
      </div>
    </form>
  );
}

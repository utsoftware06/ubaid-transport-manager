"use client";

import { useEffect, useEffectEvent, useRef } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import {
  type EmployeeRow,
  type EmployeeStatus,
  type EmployeeType,
  formatAmount,
} from "./Employees";

type Props = {
  employee: EmployeeRow | null;
  onClose: () => void;
};

const employeeTypeKeys: Record<EmployeeType, string> = {
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

function formatDate(value: string) {
  if (!value) return "-";
  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime()) ? "-" : date.toLocaleDateString("en-PK");
}

function formatDateTime(value: string) {
  if (!value) return "-";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "-" : date.toLocaleString("en-PK");
}

export default function EmployeeDetails({ employee, onClose }: Props) {
  const { t, dir } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const closeModal = useEffectEvent(onClose);

  useEffect(() => {
    if (!employee) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") closeModal();
    }

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);
    closeButtonRef.current?.focus();

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [employee]);

  if (!employee) return null;

  const statusKey = employee.status.toLowerCase() as Lowercase<EmployeeStatus>;
  const details = [
    { label: t("employees.fields.name"), value: employee.employeeName },
    {
      label: t("employees.fields.type"),
      value: t(`employees.types.${employeeTypeKeys[employee.employeeType]}`),
    },
    {
      label: t("employees.fields.phone"),
      value: employee.phone,
      technical: true,
    },
    {
      label: t("employees.fields.cnic"),
      value: employee.cnic,
      technical: true,
    },
    { label: t("employees.fields.address"), value: employee.address },
    {
      label: t("employees.fields.joiningDate"),
      value: formatDate(employee.joiningDate),
      technical: true,
    },
    {
      label: t("employees.fields.monthlySalary"),
      value: formatAmount(employee.monthlySalary),
      technical: true,
    },
    {
      label: t("common.status"),
      value: t(`employees.statuses.${statusKey}`),
    },
    ...(employee.driverId
      ? [{ label: t("common.driver"), value: employee.driverName }]
      : []),
    {
      label: t("employees.fields.createdAt"),
      value: formatDateTime(employee.createdAt),
      technical: true,
    },
    {
      label: t("employees.cards.totalLoan"),
      value: formatAmount(employee.totalLoan),
      technical: true,
    },
    {
      label: t("employees.cards.recoveredLoan"),
      value: formatAmount(employee.recoveredLoan),
      technical: true,
    },
    {
      label: t("employees.cards.remainingLoan"),
      value: formatAmount(employee.remainingLoan),
      technical: true,
    },
    {
      label: t("employees.fields.salaryGenerated"),
      value: formatAmount(employee.totalSalaryGenerated),
      technical: true,
    },
    {
      label: t("employees.fields.salaryPaid"),
      value: formatAmount(employee.totalSalaryPaid),
      technical: true,
    },
    {
      label: t("employees.cards.remainingSalary"),
      value: formatAmount(employee.remainingSalary),
      technical: true,
    },
  ];

  return (
    <div
      dir={dir}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="employee-details-title"
        aria-describedby="employee-details-description"
        className="max-h-[90vh] w-full max-w-5xl overflow-y-auto rounded-xl bg-white p-6 shadow-2xl md:p-8"
      >
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h2
              id="employee-details-title"
              className="text-2xl font-bold text-gray-900"
            >
              {t("employees.details.title")}
            </h2>
            <p
              id="employee-details-description"
              className="mt-1 text-sm font-semibold text-gray-900"
            >
              {t("employees.details.description")} {employee.employeeName}
            </p>
          </div>

          <button
            ref={closeButtonRef}
            type="button"
            onClick={onClose}
            aria-label={t("common.actions.close")}
            className="rounded-lg bg-gray-900 px-4 py-2 text-sm font-bold text-white hover:bg-black"
          >
            {t("common.actions.close")}
          </button>
        </div>

        <dl className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {details.map((detail) => (
            <div
              key={detail.label}
              className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm"
            >
              <dt className="text-xs font-extrabold uppercase text-gray-900">
                {detail.label}
              </dt>
              <dd
                dir={detail.technical ? "ltr" : undefined}
                className="mt-2 break-words text-base font-bold text-gray-900"
              >
                {detail.value}
              </dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}

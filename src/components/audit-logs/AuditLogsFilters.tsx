"use client";

import { useEffect, useMemo, useState } from "react";
import type {
  AuditActionType,
  AuditLog,
  AuditLogFilterValues,
} from "@/types/auditLogs";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type AuditLogsFiltersProps = {
  logs: AuditLog[];
  appliedFilters: AuditLogFilterValues;
  onApply: (filters: AuditLogFilterValues) => void;
  onReset: () => void;
  onRefresh: () => void;
  isLoading: boolean;
};

const actionOptions: Array<"" | AuditActionType> = [
  "",
  "CREATE",
  "UPDATE",
  "DELETE",
];

const knownModuleNames: Record<string, string> = {
  vehicle_documents: "Vehicle Documents",
  loadings: "Loadings",
  bookings: "Bookings",
  drivers: "Drivers",
  vehicles: "Vehicles",
  expenses: "Expenses",
  trips: "Trips",
  addas: "Addas",
};

function formatModuleName(value: string) {
  if (knownModuleNames[value]) {
    return knownModuleNames[value];
  }

  return value
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function createEmptyFilters(): AuditLogFilterValues {
  return {
    search: "",
    actionType: "",
    tableName: "",
    userEmail: "",
    fromDate: "",
    toDate: "",
  };
}

export default function AuditLogsFilters({
  logs,
  appliedFilters,
  onApply,
  onReset,
  onRefresh,
  isLoading,
}: AuditLogsFiltersProps) {
  const { t, dir } = useLanguage();
  const [filters, setFilters] =
    useState<AuditLogFilterValues>(appliedFilters);
  const [validationMessage, setValidationMessage] = useState("");

  useEffect(() => {
    const syncTimer = window.setTimeout(() => {
      setFilters(appliedFilters);
      setValidationMessage("");
    }, 0);

    return () => window.clearTimeout(syncTimer);
  }, [appliedFilters]);

  const moduleOptions = useMemo(() => {
    return Array.from(new Set(logs.map((log) => log.table_name)))
      .filter(Boolean)
      .sort((first, second) =>
        formatModuleName(first).localeCompare(formatModuleName(second))
      );
  }, [logs]);

  function updateFilter<K extends keyof AuditLogFilterValues>(
    key: K,
    value: AuditLogFilterValues[K]
  ) {
    setFilters((current) => ({
      ...current,
      [key]: value,
    }));
    setValidationMessage("");
  }

  function validateFilters() {
    if (filters.fromDate && filters.toDate && filters.fromDate > filters.toDate) {
      setValidationMessage(t("auditLogs.validation.invalidDateRange"));
      return false;
    }

    return true;
  }

  function handleApply() {
    if (!validateFilters()) return;

    onApply(filters);
  }

  function handleReset() {
    setFilters(createEmptyFilters());
    setValidationMessage("");
    onReset();
  }

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    handleApply();
  }

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <div className="flex flex-col gap-2">
        <h2 className="text-xl font-extrabold text-gray-900">
          {t("auditLogs.filters.title")}
        </h2>
        <p className="text-sm font-semibold text-gray-900">
          {t("auditLogs.filters.description")}
        </p>
      </div>

      {validationMessage && (
        <div className="mt-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {validationMessage}
        </div>
      )}

      <form onSubmit={handleSubmit} className="mt-6">
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">

          <VoiceTypingField fieldLabel={t("auditLogs.filters.searchPlaceholder")} mode="text"><label className="block xl:col-span-2">
            <span className="text-sm font-extrabold text-gray-900">
              {t("common.actions.search")}
            </span>
            <input
              type="text"
              value={filters.search}
              onChange={(event) => updateFilter("search", event.target.value)}
              placeholder={t("auditLogs.filters.searchPlaceholder")}
              disabled={isLoading}
              className="mt-2 w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            />
          </label></VoiceTypingField>


          <label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("auditLogs.fields.action")}
            </span>
            <select
              value={filters.actionType}
              onChange={(event) =>
                updateFilter(
                  "actionType",
                  event.target.value as "" | AuditActionType
                )
              }
              disabled={isLoading}
              className="mt-2 w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            >
              {actionOptions.map((option) => (
                <option key={option || "all"} value={option}>
                  {option ? t(`auditLogs.actions.${option.toLowerCase()}`) : t("auditLogs.filters.allActions")}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("auditLogs.fields.module")}
            </span>
            <select
              value={filters.tableName}
              onChange={(event) =>
                updateFilter("tableName", event.target.value)
              }
              disabled={isLoading}
              className="mt-2 w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            >
              <option value="">{t("auditLogs.filters.allModules")}</option>
              {moduleOptions.map((moduleName) => (
                <option key={moduleName} value={moduleName}>
                  {knownModuleNames[moduleName]
                    ? t(`auditLogs.modules.${moduleName}`)
                    : formatModuleName(moduleName)}
                </option>
              ))}
            </select>
          </label>


          <VoiceTypingField fieldLabel={t("auditLogs.filters.userEmailPlaceholder")} mode="email"><label className="block xl:col-span-2">
            <span className="text-sm font-extrabold text-gray-900">
              {t("auditLogs.fields.userEmail")}
            </span>
            <input
              type="text"
              value={filters.userEmail}
              onChange={(event) =>
                updateFilter("userEmail", event.target.value)
              }
              placeholder={t("auditLogs.filters.userEmailPlaceholder")}
              disabled={isLoading}
              className="mt-2 w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            />
          </label></VoiceTypingField>



          <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("common.fromDate")}
            </span>
            <input
              type="date"
              value={filters.fromDate}
              max={filters.toDate || undefined}
              onChange={(event) =>
                updateFilter("fromDate", event.target.value)
              }
              disabled={isLoading}
              className="mt-2 w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            />
          </label></VoiceTypingField>



          <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("common.toDate")}
            </span>
            <input
              type="date"
              value={filters.toDate}
              min={filters.fromDate || undefined}
              onChange={(event) => updateFilter("toDate", event.target.value)}
              disabled={isLoading}
              className="mt-2 w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 disabled:cursor-not-allowed"
            />
          </label></VoiceTypingField>


          <div className="flex flex-col gap-3 md:col-span-2 xl:col-span-4 xl:flex-row xl:items-end">
            <button
              type="submit"
              disabled={isLoading}
              className="w-full rounded-lg bg-blue-600 px-5 py-3 text-sm font-extrabold text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed"
            >
              {t("auditLogs.filters.apply")}
            </button>

            <button
              type="button"
              onClick={handleReset}
              disabled={isLoading}
              className="w-full rounded-lg bg-gray-200 px-5 py-3 text-sm font-extrabold text-gray-900 shadow-sm hover:bg-gray-300 disabled:cursor-not-allowed"
            >
              {t("common.actions.reset")}
            </button>

            <button
              type="button"
              onClick={onRefresh}
              disabled={isLoading}
              className="w-full rounded-lg border border-blue-600 bg-white px-5 py-3 text-sm font-extrabold text-blue-700 shadow-sm hover:bg-blue-50 disabled:cursor-not-allowed"
            >
              {t("common.actions.refresh")}
            </button>
          </div>
        </div>
      </form>
    </section>
  );
}

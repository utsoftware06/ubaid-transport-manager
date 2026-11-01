"use client";

import type { AuditLog, JsonValue } from "@/types/auditLogs";
import { useLanguage } from "@/contexts/LanguageContext";
import { userRoleLabel } from "@/config/navigation";

type AuditLogsTableProps = {
  logs: AuditLog[];
  loading: boolean;
  currentPage: number;
  totalPages: number;
  totalRecords: number;
  onPageChange: (page: number) => void;
  onViewDetails: (log: AuditLog) => void;
  onPrint: () => void;
  onExportCsv: () => void;
};

function formatModuleName(value: string) {
  const knownModules: Record<string, string> = {
    vehicle_documents: "Vehicle Documents",
    trips: "Trips",
    drivers: "Drivers",
    vehicles: "Vehicles",
    bookings: "Bookings",
    expenses: "Expenses",
    loadings: "Loadings",
    addas: "Addas",
  };

  if (knownModules[value]) {
    return knownModules[value];
  }

  return value
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function isJsonObject(value: JsonValue | null): value is Record<string, JsonValue> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function formatFieldName(value: string) {
  return value
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function getChangedFieldsLabel(value: JsonValue | null) {
  if (!isJsonObject(value)) {
    return "-";
  }

  const fields = Object.keys(value).map(formatFieldName);

  if (fields.length === 0) {
    return "-";
  }

  const visibleFields = fields.slice(0, 3);
  const remainingCount = fields.length - visibleFields.length;

  return remainingCount > 0
    ? `${visibleFields.join(", ")} +${remainingCount} more`
    : visibleFields.join(", ");
}

function getShortRecordId(value: string | null) {
  if (!value) {
    return "-";
  }

  if (value.length <= 14) {
    return value;
  }

  return `${value.slice(0, 8)}...${value.slice(-4)}`;
}

function getActionBadgeClass(action: AuditLog["action_type"]) {
  if (action === "CREATE") {
    return "border-green-200 bg-green-50 text-green-700";
  }

  if (action === "UPDATE") {
    return "border-indigo-200 bg-indigo-50 text-indigo-700";
  }

  return "border-red-200 bg-red-50 text-red-700";
}

export default function AuditLogsTable({
  logs,
  loading,
  currentPage,
  totalPages,
  totalRecords,
  onPageChange,
  onViewDetails,
  onPrint,
  onExportCsv,
}: AuditLogsTableProps) {
  const { t, dir, language } = useLanguage();
  const safeTotalPages = Math.max(totalPages, 1);
  const safeCurrentPage = Math.min(Math.max(currentPage, 1), safeTotalPages);

  function goToPage(page: number) {
    const nextPage = Math.min(Math.max(page, 1), safeTotalPages);

    if (nextPage !== safeCurrentPage) {
      onPageChange(nextPage);
    }
  }

  return (
    <section dir={dir} className="rounded-xl bg-white p-6 shadow-md">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h2 className="text-xl font-extrabold text-gray-900">
            {t("auditLogs.table.title")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("auditLogs.table.totalRecords")}: {totalRecords}
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={onPrint}
            disabled={loading || totalRecords === 0}
            className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-extrabold text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed"
          >
            {t("common.actions.print")}
          </button>

          <button
            type="button"
            onClick={onExportCsv}
            disabled={loading || totalRecords === 0}
            className="rounded-lg bg-green-600 px-5 py-3 text-sm font-extrabold text-white shadow-sm hover:bg-green-700 disabled:cursor-not-allowed"
          >
            {t("common.actions.exportCsv")}
          </button>
        </div>
      </div>

      <div className="mt-6 overflow-x-auto rounded-xl border border-gray-200">
        <table className="min-w-[1100px] w-full border-collapse text-left text-sm">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th scope="col" className="px-4 py-3 font-extrabold">
                {t("auditLogs.fields.dateTime")}
              </th>
              <th scope="col" className="px-4 py-3 font-extrabold">
                {t("auditLogs.fields.action")}
              </th>
              <th scope="col" className="px-4 py-3 font-extrabold">
                {t("auditLogs.fields.module")}
              </th>
              <th scope="col" className="px-4 py-3 font-extrabold">
                Record ID
              </th>
              <th scope="col" className="px-4 py-3 font-extrabold">
                {t("auditLogs.fields.user")}
              </th>
              <th scope="col" className="px-4 py-3 font-extrabold">
                Role
              </th>
              <th scope="col" className="px-4 py-3 font-extrabold">
                Changed Fields
              </th>
              <th scope="col" className="px-4 py-3 font-extrabold">
                {t("auditLogs.fields.details")}
              </th>
            </tr>
          </thead>

          <tbody>
            {loading &&
              Array.from({ length: 5 }).map((_, index) => (
                <tr key={`loading-${index}`} className="border-b border-gray-200">
                  <td className="px-4 py-4">
                    <div className="h-4 w-36 animate-pulse rounded bg-gray-200" />
                  </td>
                  <td className="px-4 py-4">
                    <div className="h-6 w-20 animate-pulse rounded-full bg-gray-200" />
                  </td>
                  <td className="px-4 py-4">
                    <div className="h-4 w-32 animate-pulse rounded bg-gray-200" />
                  </td>
                  <td className="px-4 py-4">
                    <div className="h-4 w-28 animate-pulse rounded bg-gray-200" />
                  </td>
                  <td className="px-4 py-4">
                    <div className="h-4 w-40 animate-pulse rounded bg-gray-200" />
                  </td>
                  <td className="px-4 py-4">
                    <div className="h-4 w-20 animate-pulse rounded bg-gray-200" />
                  </td>
                  <td className="px-4 py-4">
                    <div className="h-4 w-44 animate-pulse rounded bg-gray-200" />
                  </td>
                  <td className="px-4 py-4">
                    <div className="h-8 w-24 animate-pulse rounded bg-gray-200" />
                  </td>
                </tr>
              ))}

            {!loading && logs.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center">
                  <h3 className="text-lg font-extrabold text-gray-900">
                    {t("auditLogs.table.empty")}
                  </h3>
                  <p className="mt-2 text-sm font-semibold text-gray-900">
                    Try changing filters or refreshing the audit log list.
                  </p>
                </td>
              </tr>
            )}

            {!loading &&
              logs.map((log) => (
                <tr
                  key={log.id}
                  className="border-b border-gray-200 hover:bg-blue-50"
                >
                  <td className="whitespace-nowrap px-4 py-3 font-semibold text-gray-900">
                    {new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", { dateStyle: "medium", timeStyle: "short" }).format(new Date(log.created_at))}
                  </td>

                  <td className="px-4 py-3">
                    <span
                      className={`inline-flex rounded-full border px-3 py-1 text-xs font-extrabold ${getActionBadgeClass(
                        log.action_type
                      )}`}
                    >
                      {t(`auditLogs.actions.${log.action_type.toLowerCase()}`)}
                    </span>
                  </td>

                  <td className="whitespace-nowrap px-4 py-3 font-bold text-gray-900">
                    {["vehicle_documents", "trips", "drivers", "vehicles", "bookings", "expenses", "loadings", "addas"].includes(log.table_name)
                      ? t(`auditLogs.modules.${log.table_name}`)
                      : formatModuleName(log.table_name)}
                  </td>

                  <td
                    className="whitespace-nowrap px-4 py-3 font-semibold text-gray-900"
                    title={log.record_id ?? "-"}
                  >
                    {getShortRecordId(log.record_id)}
                  </td>

                  <td className="whitespace-nowrap px-4 py-3 font-semibold text-gray-900">
                    {log.user_email ?? "System"}
                  </td>

                  <td className="whitespace-nowrap px-4 py-3 font-semibold text-gray-900">
                    {userRoleLabel(log.user_role, t)}
                  </td>

                  <td className="max-w-[280px] px-4 py-3 font-semibold text-gray-900">
                    {getChangedFieldsLabel(log.changed_fields)}
                  </td>

                  <td className="px-4 py-3">
                    <button
                      type="button"
                      onClick={() => onViewDetails(log)}
                      className="whitespace-nowrap rounded-lg bg-blue-600 px-4 py-2 text-xs font-extrabold text-white shadow-sm hover:bg-blue-700"
                    >
                      {t("auditLogs.actions.viewDetails")}
                    </button>
                  </td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>

      <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <p className="text-sm font-bold text-gray-900">
          {t("common.pagination.page")} {safeCurrentPage} {t("common.pagination.of")} {safeTotalPages}
        </p>

        <div className="flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={() => goToPage(safeCurrentPage - 1)}
            disabled={loading || safeCurrentPage <= 1}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-extrabold text-gray-900 shadow-sm hover:bg-gray-300 disabled:cursor-not-allowed"
          >
            {t("common.pagination.previous")}
          </button>

          <button
            type="button"
            onClick={() => goToPage(safeCurrentPage + 1)}
            disabled={loading || safeCurrentPage >= safeTotalPages}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-extrabold text-gray-900 shadow-sm hover:bg-gray-300 disabled:cursor-not-allowed"
          >
            {t("common.pagination.next")}
          </button>
        </div>
      </div>
    </section>
  );
}

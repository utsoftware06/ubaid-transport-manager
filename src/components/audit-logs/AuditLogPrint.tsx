"use client";

import { useEffect, useMemo } from "react";
import type {
  AuditLog,
  AuditLogFilterValues,
  JsonValue,
} from "@/types/auditLogs";
import { useLanguage } from "@/contexts/LanguageContext";
import { userRoleLabel } from "@/config/navigation";
import PrintAddaLogo from "@/components/print/PrintAddaLogo";
import { usePrintBranding } from "@/lib/print/usePrintAddaName";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { bilingual, modulePrintLabel, printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import { waitForPrintImages } from "@/lib/print/printAssets";

type AuditLogPrintProps = {
  logs: AuditLog[];
  filters: AuditLogFilterValues;
  onClose: () => void;
};

function formatDateTime(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return new Intl.DateTimeFormat("en-PK", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function formatDateOnly(value: string) {
  if (!value) {
    return "-";
  }

  const date = new Date(`${value}T00:00:00`);

  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return new Intl.DateTimeFormat("en-PK", {
    dateStyle: "medium",
  }).format(date);
}

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

function formatFieldName(value: string) {
  return value
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function isJsonObject(value: JsonValue | null): value is Record<string, JsonValue> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function getChangedFieldNames(value: JsonValue | null) {
  if (!isJsonObject(value)) {
    return "-";
  }

  const fields = Object.keys(value).map(formatFieldName);

  return fields.length > 0 ? fields.join(", ") : "-";
}

function getActiveFilters(filters: AuditLogFilterValues, t: (key: string) => string) {
  const activeFilters: Array<{ label: string; value: string }> = [];

  if (filters.search.trim()) {
    activeFilters.push({ label: t("common.actions.search"), value: filters.search.trim() });
  }

  if (filters.actionType) {
    activeFilters.push({ label: t("auditLogs.fields.action"), value: t(`auditLogs.actions.${filters.actionType.toLowerCase()}`) });
  }

  if (filters.tableName) {
    activeFilters.push({
      label: t("auditLogs.fields.module"),
      value: ["vehicle_documents", "trips", "drivers", "vehicles", "bookings", "expenses", "loadings", "addas"].includes(filters.tableName)
        ? t(`auditLogs.modules.${filters.tableName}`)
        : formatModuleName(filters.tableName),
    });
  }

  if (filters.userEmail.trim()) {
    activeFilters.push({
      label: t("auditLogs.fields.userEmail"),
      value: filters.userEmail.trim(),
    });
  }

  if (filters.fromDate) {
    activeFilters.push({
      label: t("common.fromDate"),
      value: formatDateOnly(filters.fromDate),
    });
  }

  if (filters.toDate) {
    activeFilters.push({
      label: t("common.toDate"),
      value: formatDateOnly(filters.toDate),
    });
  }

  return activeFilters;
}

export default function AuditLogPrint({
  logs,
  filters,
  onClose,
}: AuditLogPrintProps) {
  const { t, dir, language } = useLanguage();
  const ownerAddaId = singleResolvedAddaId(logs.map((log) => log.adda_id));
  const branding = usePrintBranding(ownerAddaId);
  const addaName = branding?.addaName.trim() || (language === "ur" ? "اڈے کا نام دستیاب نہیں" : "Adda name unavailable");
  const modulePrint = useModuleTransportPrint("audit_log", ownerAddaId, language === "ur" ? "ur" : "en");
  const generatedAt = useMemo(() => new Date().toISOString(), []);
  const activeFilters = useMemo(() => getActiveFilters(filters, t), [filters, t]);

  const summary = useMemo(() => {
    return logs.reduce(
      (totals, log) => {
        totals.totalLogs += 1;

        if (log.action_type === "CREATE") totals.createLogs += 1;
        if (log.action_type === "UPDATE") totals.updateLogs += 1;
        if (log.action_type === "DELETE") totals.deleteLogs += 1;

        return totals;
      },
      {
        totalLogs: 0,
        createLogs: 0,
        updateLogs: 0,
        deleteLogs: 0,
      }
    );
  }, [logs]);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose();
      }
    }

    const previousOverflow = document.body.style.overflow;

    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose]);

  function handlePrintLegacy() {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        void waitForPrintImages(document).then(() => window.print());
      });
    });
  }

  function handlePrint() {
    if (!ownerAddaId || logs.some((log) => !log.adda_id)) return;
    const presentation: ModulePrintPresentation = {
      documentType: "audit_log",
      title: printLabel("auditLogs.print.reportTitle"),
      fields: [
        { label: printLabel("auditLogs.print.activeFilters"), value: printValue(activeFilters.length ? activeFilters.map((filter) => `${filter.label}: ${filter.value}`).join(" · ") : modulePrintLabel(language === "ur" ? "ur" : "en", "auditLogs.print.allRecords")) },
        { label: printLabel("auditLogs.table.totalRecords"), value: printValue(summary.totalLogs) },
      ],
      totals: [
        { label: printLabel("auditLogs.actions.create"), value: printValue(summary.createLogs) },
        { label: printLabel("auditLogs.actions.update"), value: printValue(summary.updateLogs) },
        { label: printLabel("auditLogs.actions.delete"), value: printValue(summary.deleteLogs) },
      ],
      tables: [{
        columns: [printLabel("common.date"), printLabel("auditLogs.fields.action"), printLabel("auditLogs.fields.module"), bilingual("Record ID", "ریکارڈ آئی ڈی"), printLabel("auditLogs.fields.userEmail"), printLabel("auditLogs.fields.userRole"), bilingual("Changed Fields", "تبدیل شدہ فیلڈز")],
        rows: logs.map((log) => [
          printValue(formatDateTime(log.created_at)),
          bilingual(modulePrintLabel("en", `auditLogs.actions.${log.action_type.toLowerCase()}`), modulePrintLabel("ur", `auditLogs.actions.${log.action_type.toLowerCase()}`)),
          bilingual(["vehicle_documents", "trips", "drivers", "vehicles", "bookings", "expenses", "loadings", "addas"].includes(log.table_name) ? modulePrintLabel("en", `auditLogs.modules.${log.table_name}`) : formatModuleName(log.table_name), ["vehicle_documents", "trips", "drivers", "vehicles", "bookings", "expenses", "loadings", "addas"].includes(log.table_name) ? modulePrintLabel("ur", `auditLogs.modules.${log.table_name}`) : formatModuleName(log.table_name)),
          printValue(log.record_id), printValue(log.user_email ?? "System"),
          bilingual(userRoleLabel(log.user_role, (key) => modulePrintLabel("en", key)), userRoleLabel(log.user_role, (key) => modulePrintLabel("ur", key))),
          printValue(getChangedFieldNames(log.changed_fields)),
        ]),
      }],
    };
    modulePrint.openPresentation(presentation, handlePrintLegacy, ownerAddaId);
  }

  return (
    <div
      dir={dir}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 print:static print:block print:bg-white print:p-0"
      role="presentation"
      onClick={onClose}
    >
      <div
        className="flex max-h-[92vh] w-full max-w-7xl flex-col overflow-hidden rounded-xl bg-white shadow-2xl print:max-h-none print:max-w-none print:overflow-visible print:rounded-none print:shadow-none"
        role="dialog"
        aria-modal="true"
        aria-labelledby="audit-log-print-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="border-b border-gray-200 bg-white p-5 print:hidden">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2
                id="audit-log-print-title"
                className="text-2xl font-extrabold text-gray-900"
              >
                {t("auditLogs.print.previewTitle")}
              </h2>
              <p className="mt-1 text-sm font-semibold text-gray-900">
                {t("auditLogs.print.previewDescription")}
              </p>
            </div>

            <div className="flex flex-col gap-3 sm:flex-row">
              <button
                type="button"
                onClick={handlePrint}
                disabled={!ownerAddaId || logs.some((log) => !log.adda_id)}
                className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-extrabold text-white shadow-sm hover:bg-blue-700"
              >
                {t("common.actions.print")}
              </button>
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-extrabold text-gray-900 shadow-sm hover:bg-gray-300"
              >
                {t("common.actions.close")}
              </button>
            </div>
          </div>
        </div>

        <div className="flex-1 overflow-auto bg-gray-50 p-5 print:overflow-visible print:bg-white print:p-0">
          <div
            id="audit-log-print-area"
            className="mx-auto max-w-7xl rounded-xl bg-white p-6 shadow-md print:m-0 print:max-w-none print:rounded-none print:p-0 print:shadow-none"
          >
            <header className="border-b-2 border-gray-900 pb-5 text-center">
              <div className="flex items-center justify-center gap-2">
                <PrintAddaLogo branding={branding} />
                <h1 className="text-3xl font-extrabold text-gray-900">{addaName}</h1>
              </div>
              <h2 className="mt-2 text-xl font-extrabold text-gray-900">
                {t("auditLogs.print.reportTitle")}
              </h2>
              <p className="mt-2 text-sm font-bold text-gray-900">
                {t("common.print.generated")}: {new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", { dateStyle: "medium", timeStyle: "short" }).format(new Date(generatedAt))}
              </p>
              <p className="mt-1 text-sm font-bold text-gray-900">
                {t("auditLogs.table.totalRecords")}: {logs.length}
              </p>
            </header>

            <section className="mt-6">
              <h3 className="text-lg font-extrabold text-gray-900">
                {t("auditLogs.print.activeFilters")}
              </h3>

              {activeFilters.length === 0 ? (
                <div className="mt-3 rounded-lg border border-gray-200 bg-gray-50 p-4 text-sm font-bold text-gray-900">
                  {t("auditLogs.print.allRecords")}
                </div>
              ) : (
                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  {activeFilters.map((filter) => (
                    <div
                      key={filter.label}
                      className="rounded-lg border border-gray-200 bg-gray-50 p-4"
                    >
                      <p className="text-xs font-extrabold uppercase tracking-wide text-gray-900">
                        {filter.label}
                      </p>
                      <p className="mt-1 break-words text-sm font-bold text-gray-900">
                        {filter.value}
                      </p>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <section className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div className="rounded-lg border border-blue-200 bg-blue-50 p-4">
                <p className="text-xs font-extrabold uppercase text-gray-900">
                  {t("auditLogs.summary.totalLogs")}
                </p>
                <p className="mt-2 text-2xl font-extrabold text-gray-900">
                  {summary.totalLogs}
                </p>
              </div>
              <div className="rounded-lg border border-green-200 bg-green-50 p-4">
                <p className="text-xs font-extrabold uppercase text-gray-900">
                  {t("auditLogs.summary.created")}
                </p>
                <p className="mt-2 text-2xl font-extrabold text-green-700">
                  {summary.createLogs}
                </p>
              </div>
              <div className="rounded-lg border border-indigo-200 bg-indigo-50 p-4">
                <p className="text-xs font-extrabold uppercase text-gray-900">
                  {t("auditLogs.summary.updated")}
                </p>
                <p className="mt-2 text-2xl font-extrabold text-indigo-700">
                  {summary.updateLogs}
                </p>
              </div>
              <div className="rounded-lg border border-red-200 bg-red-50 p-4">
                <p className="text-xs font-extrabold uppercase text-gray-900">
                  {t("auditLogs.summary.deleted")}
                </p>
                <p className="mt-2 text-2xl font-extrabold text-red-700">
                  {summary.deleteLogs}
                </p>
              </div>
            </section>

            <section className="mt-6">
              <div className="overflow-x-auto rounded-xl border border-gray-200 print:overflow-visible print:rounded-none">
                <table className="min-w-[1000px] w-full border-collapse text-left text-sm print:min-w-0 print:text-[10px]">
                  <thead className="bg-blue-600 text-white">
                    <tr>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        #
                      </th>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        {t("auditLogs.fields.dateTime")}
                      </th>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        {t("auditLogs.fields.action")}
                      </th>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        {t("auditLogs.fields.module")}
                      </th>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        Record ID
                      </th>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        {t("auditLogs.fields.userEmail")}
                      </th>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        {t("auditLogs.fields.userRole")}
                      </th>
                      <th className="px-3 py-3 font-extrabold" scope="col">
                        Changed Fields
                      </th>
                    </tr>
                  </thead>

                  <tbody>
                    {logs.length === 0 ? (
                      <tr>
                        <td
                          colSpan={8}
                          className="px-3 py-10 text-center font-bold text-gray-900"
                        >
                          {t("auditLogs.print.empty")}
                        </td>
                      </tr>
                    ) : (
                      logs.map((log, index) => (
                        <tr
                          key={log.id}
                          className="border-b border-gray-200 align-top"
                        >
                          <td className="px-3 py-3 font-semibold text-gray-900">
                            {index + 1}
                          </td>
                          <td className="px-3 py-3 font-semibold text-gray-900">
                            {formatDateTime(log.created_at)}
                          </td>
                          <td className="px-3 py-3 font-semibold text-gray-900">
                            {t(`auditLogs.actions.${log.action_type.toLowerCase()}`)}
                          </td>
                          <td className="px-3 py-3 font-semibold text-gray-900">
                            {["vehicle_documents", "trips", "drivers", "vehicles", "bookings", "expenses", "loadings", "addas"].includes(log.table_name)
                              ? t(`auditLogs.modules.${log.table_name}`)
                              : formatModuleName(log.table_name)}
                          </td>
                          <td className="break-all px-3 py-3 font-semibold text-gray-900">
                            {log.record_id ?? "-"}
                          </td>
                          <td className="break-all px-3 py-3 font-semibold text-gray-900">
                            {log.user_email ?? "System"}
                          </td>
                          <td className="px-3 py-3 font-semibold text-gray-900">
                            {userRoleLabel(log.user_role, t)}
                          </td>
                          <td className="px-3 py-3 font-semibold text-gray-900">
                            {getChangedFieldNames(log.changed_fields)}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </section>

            <footer className="mt-6 border-t border-gray-900 pt-4 text-center text-xs font-bold text-gray-900">
              <p>{addaName} {t("auditLogs.print.reportTitle")}</p>
              <p>{t("common.print.generated")}: {new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", { dateStyle: "medium", timeStyle: "short" }).format(new Date(generatedAt))}</p>
            </footer>
          </div>
        </div>
      </div>

      {modulePrint.dialog}
      <style jsx global>{`
        @media print {
          @page {
            size: A4 landscape;
            margin: 10mm;
          }

          html,
          body {
            background: #ffffff !important;
            margin: 0 !important;
            padding: 0 !important;
          }

          body * {
            visibility: hidden !important;
          }

          #audit-log-print-area,
          #audit-log-print-area * {
            visibility: visible !important;
          }

          #audit-log-print-area {
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
            width: 100% !important;
            background: #ffffff !important;
            color: #111827 !important;
          }

          #audit-log-print-area table {
            width: 100% !important;
            border-collapse: collapse !important;
          }

          #audit-log-print-area th,
          #audit-log-print-area td {
            border: 1px solid #111827 !important;
            padding: 5px !important;
            color: #111827 !important;
            vertical-align: top !important;
          }

          #audit-log-print-area th {
            background: #2563eb !important;
            color: #ffffff !important;
            font-weight: 800 !important;
          }

          #audit-log-print-area thead {
            display: table-header-group !important;
          }

          #audit-log-print-area tr {
            break-inside: avoid !important;
            page-break-inside: avoid !important;
          }

          #audit-log-print-area header,
          #audit-log-print-area section,
          #audit-log-print-area footer {
            break-inside: avoid;
          }
        }
      `}</style>
    </div>
  );
}

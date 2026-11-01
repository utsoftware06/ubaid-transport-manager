"use client";

import { useEffect, useMemo, useState } from "react";
import type { AuditLog, JsonValue } from "@/types/auditLogs";
import { useLanguage } from "@/contexts/LanguageContext";
import { userRoleLabel } from "@/config/navigation";

type AuditLogDetailsModalProps = {
  log: AuditLog;
  onClose: () => void;
};

type CopyTarget = "changed" | "old" | "new";

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

function hasJsonData(value: JsonValue | null) {
  if (value === null) return false;

  if (Array.isArray(value)) {
    return value.length > 0;
  }

  if (typeof value === "object") {
    return Object.keys(value).length > 0;
  }

  if (typeof value === "string") {
    return value.trim().length > 0;
  }

  return true;
}

function stringifyJson(value: JsonValue | null) {
  if (!hasJsonData(value)) {
    return "No data available.";
  }

  return JSON.stringify(value, null, 2);
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

function SummaryItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-gray-300 bg-white p-4 shadow-sm">
      <p className="text-xs font-extrabold uppercase tracking-wide text-gray-900">
        {label}
      </p>
      <p className="mt-2 break-words text-sm font-bold text-gray-900">
        {value || "-"}
      </p>
    </div>
  );
}

function JsonSection({
  title,
  value,
  copyLabel,
  copied,
  onCopy,
  showFieldChips = false,
}: {
  title: string;
  value: JsonValue | null;
  copyLabel: string;
  copied: boolean;
  onCopy: () => void;
  showFieldChips?: boolean;
}) {
  const fieldNames = isJsonObject(value) ? Object.keys(value) : [];

  return (
    <section className="rounded-xl border border-gray-200 bg-white shadow-sm">
      <div className="flex flex-col gap-3 border-b border-gray-200 p-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h3 className="text-lg font-extrabold text-gray-900">{title}</h3>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {hasJsonData(value)
              ? "Structured audit data captured by the system."
              : "No data available."}
          </p>
        </div>

        <div className="flex items-center gap-3">
          {copied && (
            <span className="text-sm font-extrabold text-green-700">
              Copied!
            </span>
          )}
          <button
            type="button"
            onClick={onCopy}
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-extrabold text-white shadow-sm hover:bg-blue-700"
          >
            {copyLabel}
          </button>
        </div>
      </div>

      {showFieldChips && fieldNames.length > 0 && (
        <div className="flex flex-wrap gap-2 border-b border-gray-200 bg-blue-50 p-4">
          {fieldNames.map((field) => (
            <span
              key={field}
              className="rounded-full border border-blue-200 bg-white px-3 py-1 text-xs font-extrabold text-blue-700"
            >
              {formatFieldName(field)}
            </span>
          ))}
        </div>
      )}

      <pre className="max-h-80 overflow-auto whitespace-pre-wrap break-words bg-gray-50 p-4 font-mono text-xs font-semibold text-gray-900">
        {stringifyJson(value)}
      </pre>
    </section>
  );
}

export default function AuditLogDetailsModal({
  log,
  onClose,
}: AuditLogDetailsModalProps) {
  const { t, dir, language } = useLanguage();
  const [copiedTarget, setCopiedTarget] = useState<CopyTarget | null>(null);

  const modalTitleId = "audit-log-details-title";

  const summaryItems = useMemo(
    () => [
      {
        label: t("auditLogs.fields.dateTime"),
        value: new Intl.DateTimeFormat(language === "ur" ? "ur-PK" : "en-PK", { dateStyle: "medium", timeStyle: "short" }).format(new Date(log.created_at)),
      },
      {
        label: t("auditLogs.fields.action"),
        value: t(`auditLogs.actions.${log.action_type.toLowerCase()}`),
      },
      {
        label: t("auditLogs.fields.module"),
        value: ["vehicle_documents", "trips", "drivers", "vehicles", "bookings", "expenses", "loadings", "addas"].includes(log.table_name)
          ? t(`auditLogs.modules.${log.table_name}`)
          : formatModuleName(log.table_name),
      },
      {
        label: t("auditLogs.fields.recordId"),
        value: log.record_id ?? "-",
      },
      {
        label: t("auditLogs.fields.userEmail"),
        value: log.user_email ?? "System",
      },
      {
        label: t("auditLogs.fields.userRole"),
        value: userRoleLabel(log.user_role, t),
      },
      {
        label: t("auditLogs.fields.userId"),
        value: log.user_id ?? "-",
      },
      {
        label: t("auditLogs.fields.addaId"),
        value: log.adda_id ?? "-",
      },
    ],
    [language, log, t]
  );

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

  useEffect(() => {
    if (!copiedTarget) return;

    const timeoutId = window.setTimeout(() => {
      setCopiedTarget(null);
    }, 2000);

    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [copiedTarget]);

  async function handleCopy(target: CopyTarget, value: JsonValue | null) {
    try {
      await navigator.clipboard.writeText(stringifyJson(value));
      setCopiedTarget(target);
    } catch {
      setCopiedTarget(null);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="presentation"
      dir={dir}
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={modalTitleId}
        className="flex max-h-[92vh] w-full max-w-6xl flex-col overflow-hidden rounded-xl bg-white shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="border-b border-gray-200 bg-white p-5">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <div className="flex flex-wrap items-center gap-3">
                <h2
                  id={modalTitleId}
                  className="text-2xl font-extrabold text-gray-900"
                >
                  {t("auditLogs.details.title")}
                </h2>
                <span
                  className={`inline-flex rounded-full border px-3 py-1 text-xs font-extrabold ${getActionBadgeClass(
                    log.action_type
                  )}`}
                >
                  {t(`auditLogs.actions.${log.action_type.toLowerCase()}`)}
                </span>
              </div>
              <p className="mt-2 text-sm font-semibold text-gray-900">
                {t("auditLogs.details.description")} {["vehicle_documents", "trips", "drivers", "vehicles", "bookings", "expenses", "loadings", "addas"].includes(log.table_name) ? t(`auditLogs.modules.${log.table_name}`) : formatModuleName(log.table_name)}.
              </p>
            </div>

            <button
              type="button"
              onClick={onClose}
              className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-extrabold text-gray-900 shadow-sm hover:bg-gray-300"
            >
              {t("common.actions.close")}
            </button>
          </div>
        </header>

        <div className="flex-1 space-y-6 overflow-y-auto p-5">
          <section className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
            {summaryItems.map((item) => (
              <SummaryItem
                key={item.label}
                label={item.label}
                value={item.value}
              />
            ))}
          </section>

          <JsonSection
            title={t("auditLogs.details.changedFields")}
            value={log.changed_fields}
            copyLabel={t("auditLogs.details.copyChangedFields")}
            copied={copiedTarget === "changed"}
            onCopy={() => handleCopy("changed", log.changed_fields)}
            showFieldChips
          />

          <JsonSection
            title={t("auditLogs.details.oldData")}
            value={log.old_data}
            copyLabel={t("auditLogs.details.copyOldData")}
            copied={copiedTarget === "old"}
            onCopy={() => handleCopy("old", log.old_data)}
          />

          <JsonSection
            title={t("auditLogs.details.newData")}
            value={log.new_data}
            copyLabel={t("auditLogs.details.copyNewData")}
            copied={copiedTarget === "new"}
            onCopy={() => handleCopy("new", log.new_data)}
          />
        </div>

        <footer className="border-t border-gray-200 bg-white p-5">
          <div className="flex justify-end">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-extrabold text-white shadow-sm hover:bg-blue-700"
            >
              {t("common.actions.close")}
            </button>
          </div>
        </footer>
      </div>
    </div>
  );
}

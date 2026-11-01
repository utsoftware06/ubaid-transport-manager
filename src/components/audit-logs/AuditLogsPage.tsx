"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import AuditLogDetailsModal from "@/components/audit-logs/AuditLogDetailsModal";
import AuditLogPrint from "@/components/audit-logs/AuditLogPrint";
import AuditLogsCards from "@/components/audit-logs/AuditLogsCards";
import AuditLogsFilters from "@/components/audit-logs/AuditLogsFilters";
import AuditLogsTable from "@/components/audit-logs/AuditLogsTable";
import { supabase } from "@/lib/supabase/client";
import type {
  AuditActionType,
  AuditLog,
  AuditLogFilterValues,
  AuditLogSummary,
  JsonValue,
} from "@/types/auditLogs";
import { useLanguage } from "@/contexts/LanguageContext";
import { userRoleLabel } from "@/config/navigation";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

const PAGE_SIZE = 20;

const emptyFilters: AuditLogFilterValues = {
  search: "",
  actionType: "",
  tableName: "",
  userEmail: "",
  fromDate: "",
  toDate: "",
};

type AuditLogDatabaseRow = {
  id: string;
  adda_id: string | null;
  user_id: string | null;
  action_type: string;
  table_name: string;
  record_id: string | null;
  old_data: JsonValue | null;
  new_data: JsonValue | null;
  changed_fields: JsonValue | null;
  user_email: string | null;
  user_role: string | null;
  created_at: string;
};

function isAuditActionType(value: string): value is AuditActionType {
  return value === "CREATE" || value === "UPDATE" || value === "DELETE";
}

function normalizeAuditLog(row: AuditLogDatabaseRow): AuditLog | null {
  if (!isAuditActionType(row.action_type)) {
    return null;
  }

  return {
    id: row.id,
    adda_id: row.adda_id,
    user_id: row.user_id,
    action_type: row.action_type,
    table_name: row.table_name,
    record_id: row.record_id,
    old_data: row.old_data,
    new_data: row.new_data,
    changed_fields: row.changed_fields,
    user_email: row.user_email,
    user_role: row.user_role,
    created_at: row.created_at,
  };
}

function isJsonObject(value: JsonValue | null): value is Record<string, JsonValue> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function getChangedFieldNames(value: JsonValue | null): string {
  if (!isJsonObject(value)) return "-";

  const fields = Object.keys(value);
  return fields.length > 0 ? fields.join(", ") : "-";
}

function formatDate(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return new Intl.DateTimeFormat("en-PK", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function escapeCsvValue(value: string) {
  return `"${value.replace(/"/g, '""').replace(/\r?\n|\r/g, " ")}"`;
}

function isWithinDateRange(value: string, fromDate: string, toDate: string) {
  const createdAt = new Date(value);

  if (Number.isNaN(createdAt.getTime())) {
    return false;
  }

  if (fromDate) {
    const startDate = new Date(`${fromDate}T00:00:00`);
    if (createdAt < startDate) return false;
  }

  if (toDate) {
    const endDate = new Date(`${toDate}T23:59:59.999`);
    if (createdAt > endDate) return false;
  }

  return true;
}

export default function AuditLogsPage() {
  const { t, dir } = useLanguage();
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [appliedFilters, setAppliedFilters] =
    useState<AuditLogFilterValues>(emptyFilters);
  const [selectedLog, setSelectedLog] = useState<AuditLog | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const [isPrintOpen, setIsPrintOpen] = useState(false);

  const isMountedRef = useRef(true);

  const loadAuditLogs = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage("");

    try {
      const { data, error } = await supabase
        .from("audit_logs")
        .select(
          `
          id,
          adda_id,
          user_id,
          action_type,
          table_name,
          record_id,
          old_data,
          new_data,
          changed_fields,
          user_email,
          user_role,
          created_at
        `
        )
        .order("created_at", { ascending: false });

      if (error) throw error;

      if (!isMountedRef.current) return;

      const rows = (data ?? []) as AuditLogDatabaseRow[];
      setAuditLogs(
  rows
    .map(normalizeAuditLog)
    .filter((log): log is AuditLog => log !== null)
);
    } catch (error) {
      if (!isMountedRef.current) return;

      console.error("Unable to load audit logs:", error);
      setErrorMessage(t("auditLogs.messages.loadFailed"));
    } finally {
      if (isMountedRef.current) {
        setIsLoading(false);
      }
    }
  }, [t]);

  useEffect(() => {
    isMountedRef.current = true;
    const loadTimer = window.setTimeout(() => {
      void loadAuditLogs();
    }, 0);

    return () => {
      window.clearTimeout(loadTimer);
      isMountedRef.current = false;
    };
  }, [loadAuditLogs]);

  const filteredLogs = useMemo(() => {
    const searchText = appliedFilters.search.trim().toLowerCase();
    const userEmailText = appliedFilters.userEmail.trim().toLowerCase();

    return auditLogs.filter((log) => {
      if (
        appliedFilters.actionType &&
        log.action_type !== appliedFilters.actionType
      ) {
        return false;
      }

      if (
        appliedFilters.tableName &&
        log.table_name !== appliedFilters.tableName
      ) {
        return false;
      }

      if (
        userEmailText &&
        !(log.user_email ?? "").toLowerCase().includes(userEmailText)
      ) {
        return false;
      }

      if (
        !isWithinDateRange(
          log.created_at,
          appliedFilters.fromDate,
          appliedFilters.toDate
        )
      ) {
        return false;
      }

      if (!searchText) {
        return true;
      }

      const searchableText = [
        log.table_name,
        log.record_id ?? "",
        log.user_email ?? "",
        log.user_role ?? "",
      ]
        .join(" ")
        .toLowerCase();

      return searchableText.includes(searchText);
    });
  }, [appliedFilters, auditLogs]);

  const summary = useMemo<AuditLogSummary>(() => {
    return filteredLogs.reduce(
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
  }, [filteredLogs]);

  const totalPages = useMemo(() => {
    return Math.max(Math.ceil(filteredLogs.length / PAGE_SIZE), 1);
  }, [filteredLogs.length]);

  const paginatedLogs = useMemo(() => {
    const safePage = Math.min(Math.max(currentPage, 1), totalPages);
    const startIndex = (safePage - 1) * PAGE_SIZE;

    return filteredLogs.slice(startIndex, startIndex + PAGE_SIZE);
  }, [currentPage, filteredLogs, totalPages]);

  useEffect(() => {
    const resetTimer = window.setTimeout(() => {
      setCurrentPage(1);
    }, 0);

    return () => window.clearTimeout(resetTimer);
  }, [appliedFilters]);

  useEffect(() => {
    const clampTimer = window.setTimeout(() => {
      setCurrentPage((page) => Math.min(Math.max(page, 1), totalPages));
    }, 0);

    return () => window.clearTimeout(clampTimer);
  }, [totalPages]);

  const handleApplyFilters = useCallback((filters: AuditLogFilterValues) => {
    setAppliedFilters(filters);
    setCurrentPage(1);
  }, []);

  const handleResetFilters = useCallback(() => {
    setAppliedFilters(emptyFilters);
    setCurrentPage(1);
  }, []);

  const handleRefresh = useCallback(() => {
    void loadAuditLogs();
  }, [loadAuditLogs]);

  const handleViewDetails = useCallback((log: AuditLog) => {
    setSelectedLog(log);
  }, []);

  const handleCloseDetails = useCallback(() => {
    setSelectedLog(null);
  }, []);

  const handlePrint = useCallback(() => {
    setIsPrintOpen(true);
  }, []);

  const handleClosePrint = useCallback(() => {
    setIsPrintOpen(false);
  }, []);

  const handleExportCsv = useCallback(() => {
    const headers = [
      t("common.date"),
      t("auditLogs.fields.action"),
      t("auditLogs.fields.module"),
      t("auditLogs.fields.recordId"),
      t("auditLogs.fields.userEmail"),
      t("auditLogs.fields.userRole"),
      t("auditLogs.details.changedFields"),
    ];

    const rows = filteredLogs.map((log) => [
      formatDate(log.created_at),
      log.action_type,
      log.table_name,
      log.record_id ?? "-",
      log.user_email ?? "-",
      userRoleLabel(log.user_role, t),
      getChangedFieldNames(log.changed_fields),
    ]);

    const csvContent = [headers, ...rows]
      .map((row) => row.map(escapeCsvValue).join(","))
      .join("\n");

    const blob = new Blob([csvContent], {
      type: "text/csv;charset=utf-8",
    });

    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    const today = new Date().toISOString().slice(0, 10);

    anchor.href = url;
    anchor.download = `audit-logs-${today}.csv`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();

    URL.revokeObjectURL(url);
  }, [filteredLogs, t]);

  return (
    <div dir={dir} className="ut-module-page mx-auto max-w-7xl space-y-6 p-0">
      <div className="rounded-xl bg-white p-6 shadow-md">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <ModulePageHeading icon="audit" accent="purple" title={t("auditLogs.title")} description={t("auditLogs.description")} />

          <button
            type="button"
            onClick={handleRefresh}
            disabled={isLoading}
            className="rounded-lg bg-blue-600 px-5 py-3 text-sm font-extrabold text-white shadow-sm hover:bg-blue-700 disabled:cursor-not-allowed"
          >
            {isLoading ? t("common.states.refreshing") : t("common.actions.refresh")}
          </button>
        </div>

        {errorMessage && (
          <div className="mt-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
            {errorMessage}
          </div>
        )}
      </div>

      <AuditLogsCards summary={summary} loading={isLoading} />

      <AuditLogsFilters
        logs={auditLogs}
        appliedFilters={appliedFilters}
        onApply={handleApplyFilters}
        onReset={handleResetFilters}
        onRefresh={handleRefresh}
        isLoading={isLoading}
      />

      <AuditLogsTable
        logs={paginatedLogs}
        loading={isLoading}
        currentPage={currentPage}
        totalPages={totalPages}
        totalRecords={filteredLogs.length}
        onPageChange={setCurrentPage}
        onViewDetails={handleViewDetails}
        onPrint={handlePrint}
        onExportCsv={handleExportCsv}
      />

      {selectedLog && (
        <AuditLogDetailsModal log={selectedLog} onClose={handleCloseDetails} />
      )}

      {isPrintOpen && (
        <AuditLogPrint
          logs={filteredLogs}
          filters={appliedFilters}
          onClose={handleClosePrint}
        />
      )}
    </div>
  );
}

export type AuditActionType = "CREATE" | "UPDATE" | "DELETE";

export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

export interface AuditLog {
  id: string;
  adda_id: string | null;
  user_id: string | null;
  action_type: AuditActionType;
  table_name: string;
  record_id: string | null;
  old_data: JsonValue | null;
  new_data: JsonValue | null;
  changed_fields: JsonValue | null;
  user_email: string | null;
  user_role: string | null;
  created_at: string;
}

export interface AuditLogFilterValues {
  search: string;
  actionType: "" | AuditActionType;
  tableName: string;
  userEmail: string;
  fromDate: string;
  toDate: string;
}

export interface AuditLogSummary {
  totalLogs: number;
  createLogs: number;
  updateLogs: number;
  deleteLogs: number;
}

export interface AuditLogPagination {
  currentPage: number;
  totalPages: number;
  pageSize: number;
  totalRecords: number;
}

export interface AuditLogPrintSummary {
  generatedAt: string;
  totalLogs: number;
  createLogs: number;
  updateLogs: number;
  deleteLogs: number;
}
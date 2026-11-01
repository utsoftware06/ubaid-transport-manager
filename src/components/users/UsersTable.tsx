"use client";

import { USER_ROLES, userRoleLabel } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import type { ManagedUser } from "@/components/users/types";

type UsersTableProps = {
  users: ManagedUser[];
  isLoading: boolean;
  currentPage: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  isMutating: boolean;
  mutatingUserId: string | null;
  onEdit: (user: ManagedUser) => void;
  onResetPassword: (user: ManagedUser) => void;
  onToggleStatus: (user: ManagedUser) => void;
  onDelete: (user: ManagedUser) => void;
};

function formatTechnicalDate(value: string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(date);
}

function visiblePageNumbers(currentPage: number, totalPages: number) {
  const first = Math.max(1, Math.min(currentPage - 1, totalPages - 2));
  const last = Math.min(totalPages, Math.max(currentPage + 1, 3));
  return Array.from({ length: last - first + 1 }, (_, index) => first + index);
}

export default function UsersTable({
  users,
  isLoading,
  currentPage,
  totalPages,
  onPageChange,
  isMutating,
  mutatingUserId,
  onEdit,
  onResetPassword,
  onToggleStatus,
  onDelete,
}: UsersTableProps) {
  const { t } = useLanguage();
  const pages = visiblePageNumbers(currentPage, totalPages);

  return (
    <section
      aria-labelledby="managed-users-table-title"
      className="rounded-2xl border border-slate-200 bg-white shadow-sm"
    >
      <div className="border-b border-slate-200 p-5">
        <h2
          id="managed-users-table-title"
          className="text-xl font-extrabold text-slate-900"
        >
          {t("userManagement.table.title")}
        </h2>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[1050px]">
          <thead className="bg-blue-600 text-white">
            <tr>
              <th scope="col" className="p-4 text-start font-extrabold">
                {t("userManagement.table.fullName")}
              </th>
              <th scope="col" className="p-4 text-start font-extrabold">
                {t("userManagement.table.email")}
              </th>
              <th scope="col" className="p-4 text-start font-extrabold">
                {t("userManagement.table.role")}
              </th>
              <th scope="col" className="p-4 text-start font-extrabold">
                {t("userManagement.table.adda")}
              </th>
              <th scope="col" className="p-4 text-start font-extrabold">
                {t("userManagement.table.status")}
              </th>
              <th scope="col" className="p-4 text-start font-extrabold">
                {t("userManagement.table.createdDate")}
              </th>
              <th scope="col" className="p-4 text-start font-extrabold">
                {t("userManagement.table.actions")}
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200 bg-white">
            {isLoading ? (
              <tr>
                <td colSpan={7} className="p-10 text-center font-bold text-slate-700">
                  {t("userManagement.states.loading")}
                </td>
              </tr>
            ) : users.length === 0 ? (
              <tr>
                <td colSpan={7} className="p-10 text-center font-bold text-slate-700">
                  {t("userManagement.states.empty")}
                </td>
              </tr>
            ) : (
              users.map((user) => {
                const displayName =
                  user.fullName || t("userManagement.values.notAvailable");
                const roleLabel = userRoleLabel(user.role, t);
                const isProtected = user.role === USER_ROLES.superAdmin;
                const isCurrentMutation =
                  isMutating && mutatingUserId === user.id;
                const actionsDisabled = isMutating || isProtected;

                return (
                  <tr key={user.id} className="hover:bg-blue-50/50">
                    <td className="p-4 font-bold text-slate-900">{displayName}</td>
                    <td dir="ltr" className="p-4 text-start font-medium text-slate-800">
                      {user.email || t("userManagement.values.notAvailable")}
                    </td>
                    <td className="p-4 font-semibold text-slate-800">
                      {roleLabel}
                    </td>
                    <td className="p-4 text-slate-800">
                      {user.addaName || t("userManagement.values.notAssigned")}
                    </td>
                    <td className="p-4">
                      <span
                        className={`inline-flex rounded-full border px-3 py-1 text-sm font-extrabold ${
                          user.isActive
                            ? "border-emerald-300 bg-emerald-50 text-emerald-800"
                            : "border-slate-300 bg-slate-100 text-slate-700"
                        }`}
                      >
                        {t(
                          user.isActive
                            ? "userManagement.status.active"
                            : "userManagement.status.inactive"
                        )}
                      </span>
                    </td>
                    <td dir="ltr" className="p-4 text-start font-medium text-slate-800">
                      {formatTechnicalDate(user.createdAt)}
                    </td>
                    <td className="p-4">
                      <div className="flex min-w-[420px] flex-wrap gap-2">
                        <button
                          type="button"
                          disabled={actionsDisabled}
                          onClick={() => onEdit(user)}
                          aria-label={`${t("userManagement.actions.edit")} ${displayName}`}
                          title={
                            isProtected
                              ? t("userManagement.actions.protectedSuperAdmin")
                              : undefined
                          }
                          className="rounded-lg border border-blue-300 bg-blue-50 px-3 py-2 font-bold text-blue-800 hover:bg-blue-100 disabled:cursor-not-allowed disabled:border-slate-300 disabled:bg-slate-100 disabled:text-slate-600"
                        >
                          {t("userManagement.actions.edit")}
                        </button>
                        <button
                          type="button"
                          disabled={isMutating}
                          onClick={() => onResetPassword(user)}
                          aria-label={`${t("userManagement.actions.resetPassword")} ${displayName}`}
                          className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 font-bold text-amber-900 hover:bg-amber-100 disabled:cursor-wait disabled:bg-slate-100 disabled:text-slate-600"
                        >
                          {t("userManagement.actions.resetPassword")}
                        </button>
                        <button
                          type="button"
                          disabled={actionsDisabled}
                          onClick={() => onToggleStatus(user)}
                          aria-label={`${t(
                            user.isActive
                              ? "userManagement.actions.deactivate"
                              : "userManagement.actions.activate"
                          )} ${displayName}`}
                          title={
                            isProtected
                              ? t("userManagement.actions.protectedSuperAdmin")
                              : undefined
                          }
                          className="rounded-lg border border-slate-300 bg-white px-3 py-2 font-bold text-slate-800 hover:bg-slate-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-600"
                        >
                          {isCurrentMutation
                            ? t("userManagement.actions.updating")
                            : t(
                                user.isActive
                                  ? "userManagement.actions.deactivate"
                                  : "userManagement.actions.activate"
                              )}
                        </button>
                        <button
                          type="button"
                          disabled={actionsDisabled}
                          onClick={() => onDelete(user)}
                          aria-label={`${t("userManagement.actions.delete")} ${displayName}`}
                          title={
                            isProtected
                              ? t("userManagement.actions.protectedSuperAdmin")
                              : undefined
                          }
                          className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 font-bold text-red-800 hover:bg-red-100 disabled:cursor-not-allowed disabled:border-slate-300 disabled:bg-slate-100 disabled:text-slate-600"
                        >
                          {t("userManagement.actions.delete")}
                        </button>
                      </div>
                      {isProtected && (
                        <p className="mt-2 text-sm font-semibold text-slate-700">
                          {t("userManagement.actions.protectedSuperAdmin")}
                        </p>
                      )}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      <nav
        aria-label={t("userManagement.pagination.label")}
        className="flex flex-wrap items-center justify-between gap-3 border-t border-slate-200 p-4"
      >
        <p dir="ltr" className="font-bold text-slate-700">
          {t("common.pagination.page")} {currentPage}{" "}
          {t("common.pagination.of")} {totalPages}
        </p>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            disabled={currentPage === 1}
            onClick={() => onPageChange(currentPage - 1)}
            className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold text-slate-900 hover:bg-slate-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-600"
          >
            {t("common.pagination.previous")}
          </button>

          {pages.map((page) => (
            <button
              key={page}
              type="button"
              aria-label={`${t("userManagement.pagination.goToPage")} ${page}`}
              aria-current={page === currentPage ? "page" : undefined}
              onClick={() => onPageChange(page)}
              className={`min-w-10 rounded-lg border px-3 py-2 font-extrabold ${
                page === currentPage
                  ? "border-blue-600 bg-blue-600 text-white"
                  : "border-slate-300 bg-white text-slate-900 hover:bg-slate-50"
              }`}
            >
              {page}
            </button>
          ))}

          <button
            type="button"
            disabled={currentPage === totalPages}
            onClick={() => onPageChange(currentPage + 1)}
            className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold text-slate-900 hover:bg-slate-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-600"
          >
            {t("common.pagination.next")}
          </button>
        </div>
      </nav>
    </section>
  );
}

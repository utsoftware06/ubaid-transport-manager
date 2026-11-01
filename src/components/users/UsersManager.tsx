"use client";

import { useCallback, useMemo, useRef, useState, useEffect } from "react";
import { Plus, RotateCcw } from "lucide-react";
import { useRouter } from "next/navigation";

import CreateUserForm from "@/components/users/CreateUserForm";
import DeleteUserModal from "@/components/users/DeleteUserModal";
import EditUserModal from "@/components/users/EditUserModal";
import ResetPasswordModal from "@/components/users/ResetPasswordModal";
import UserManagementCards from "@/components/users/UserManagementCards";
import UsersTable from "@/components/users/UsersTable";
import type {
  AddaOption,
  CreateUserValues,
  ManagedUser,
  RoleFilter,
  StatusFilter,
  UpdateUserValues,
  UsersListResponse,
} from "@/components/users/types";
import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { supabase } from "@/lib/supabase/client";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

const PAGE_SIZE = 10;

function apiErrorCode(payload: unknown): string | null {
  if (
    typeof payload === "object" &&
    payload !== null &&
    "error" in payload &&
    typeof payload.error === "object" &&
    payload.error !== null &&
    "code" in payload.error &&
    typeof payload.error.code === "string"
  ) {
    return payload.error.code;
  }

  return null;
}

function isUsersListResponse(payload: unknown): payload is UsersListResponse {
  return (
    typeof payload === "object" &&
    payload !== null &&
    "success" in payload &&
    payload.success === true &&
    "users" in payload &&
    Array.isArray(payload.users)
  );
}

export default function UsersManager() {
  const router = useRouter();
  const { t, dir } = useLanguage();
  const [users, setUsers] = useState<ManagedUser[]>([]);
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [search, setSearch] = useState("");
  const [roleFilter, setRoleFilter] = useState<RoleFilter>("all");
  const [addaFilter, setAddaFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [selectedEditUser, setSelectedEditUser] = useState<ManagedUser | null>(
    null
  );
  const [selectedPasswordUser, setSelectedPasswordUser] =
    useState<ManagedUser | null>(null);
  const [selectedDeleteUser, setSelectedDeleteUser] =
    useState<ManagedUser | null>(null);
  const [isMutating, setIsMutating] = useState(false);
  const [mutatingUserId, setMutatingUserId] = useState<string | null>(null);
  const [loadError, setLoadError] = useState("");
  const [formError, setFormError] = useState("");
  const [actionError, setActionError] = useState("");
  const [successMessage, setSuccessMessage] = useState("");
  const createInFlightRef = useRef(false);
  const mutationInFlightRef = useRef(false);

  const errorMessageForCode = useCallback(
    (code: string | null, fallbackKey: string) => {
      const keys: Record<string, string> = {
        AUTHENTICATION_REQUIRED: "userManagement.errors.sessionExpired",
        INVALID_SESSION: "userManagement.errors.sessionExpired",
        FORBIDDEN: "userManagement.errors.forbidden",
        USER_LIST_FAILED: "userManagement.errors.loadFailed",
        EMAIL_ALREADY_EXISTS: "userManagement.errors.emailExists",
        INVALID_ADDA: "userManagement.errors.invalidAdda",
        ADDA_REQUIRED: "userManagement.validation.addaRequired",
        INVALID_ROLE: "userManagement.validation.roleRequired",
        INVALID_ACTIVE_STATUS: "userManagement.errors.createFailed",
        PASSWORD_TOO_SHORT: "userManagement.validation.passwordLength",
        FULL_NAME_REQUIRED: "userManagement.validation.fullNameRequired",
        EMAIL_REQUIRED: "userManagement.validation.emailRequired",
        INVALID_EMAIL: "userManagement.validation.emailInvalid",
        PASSWORD_REQUIRED: "userManagement.validation.passwordLength",
        INVALID_MANAGED_ROLE: "userManagement.validation.roleRequired",
        INVALID_USER_ID: "userManagement.errors.userNotFound",
        USER_NOT_FOUND: "userManagement.errors.userNotFound",
        TARGET_USER_LOAD_FAILED: "userManagement.errors.userNotFound",
        USER_UPDATE_FAILED: "userManagement.errors.updateFailed",
        SELF_DEACTIVATION_FORBIDDEN:
          "userManagement.errors.selfDeactivation",
        SELF_DELETE_FORBIDDEN: "userManagement.errors.selfDelete",
        PROTECTED_SUPER_ADMIN: "userManagement.errors.protectedSuperAdmin",
        UNSUPPORTED_TARGET_ROLE: "userManagement.errors.unsupportedTargetRole",
        PASSWORD_RESET_FAILED: "userManagement.errors.passwordResetFailed",
        USER_DELETE_FAILED: "userManagement.errors.deleteFailed",
        USER_HAS_LINKED_RECORDS: "userManagement.errors.linkedRecords",
      };

      return t(code && keys[code] ? keys[code] : fallbackKey);
    },
    [t]
  );

  const loadData = useCallback(async () => {
    setIsLoading(true);
    setLoadError("");

    try {
      const {
        data: { session },
        error: sessionError,
      } = await supabase.auth.getSession();

      if (sessionError || !session?.access_token) {
        if (sessionError) {
          console.error("Unable to read the user-management session:", sessionError);
        }
        setLoadError(t("userManagement.errors.sessionExpired"));
        router.replace("/login");
        return;
      }

      const [usersResponse, addasResult] = await Promise.all([
        fetch("/api/admin/users", {
          method: "GET",
          headers: {
            Authorization: `Bearer ${session.access_token}`,
          },
          cache: "no-store",
        }),
        supabase.from("addas").select("id, name").order("name"),
      ]);

      const usersPayload: unknown = await usersResponse.json();

      if (!usersResponse.ok || !isUsersListResponse(usersPayload)) {
        const code = apiErrorCode(usersPayload);
        setLoadError(
          errorMessageForCode(code, "userManagement.errors.loadFailed")
        );

        if (usersResponse.status === 401) {
          router.replace("/login");
        } else if (usersResponse.status === 403) {
          router.replace("/dashboard");
        }
        return;
      }

      if (addasResult.error) {
        console.error("Unable to load Addas for user management:", addasResult.error);
        setLoadError(t("userManagement.errors.loadFailed"));
        return;
      }

      setUsers(usersPayload.users);
      setAddas((addasResult.data ?? []) as AddaOption[]);
    } catch (error) {
      console.error("Unable to load user management data:", error);
      setLoadError(t("userManagement.errors.loadFailed"));
    } finally {
      setIsLoading(false);
    }
  }, [errorMessageForCode, router, t]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void loadData();
    }, 0);

    return () => window.clearTimeout(timer);
  }, [loadData]);

  const filteredUsers = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    return users.filter((user) => {
      const matchesSearch =
        !keyword ||
        [user.fullName, user.email]
          .filter((value): value is string => Boolean(value))
          .some((value) => value.toLowerCase().includes(keyword));
      const matchesRole =
        roleFilter === "all" || user.role === roleFilter;
      const matchesAdda =
        addaFilter === "all" || user.addaId === addaFilter;
      const matchesStatus =
        statusFilter === "all" ||
        (statusFilter === "active" ? user.isActive : !user.isActive);

      return matchesSearch && matchesRole && matchesAdda && matchesStatus;
    });
  }, [addaFilter, roleFilter, search, statusFilter, users]);

  const totalPages = Math.max(1, Math.ceil(filteredUsers.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visibleUsers = filteredUsers.slice(
    (currentPage - 1) * PAGE_SIZE,
    currentPage * PAGE_SIZE
  );

  const closeCreateForm = useCallback(() => {
    if (!createInFlightRef.current) {
      setIsCreateOpen(false);
      setFormError("");
    }
  }, []);

  const closeEditModal = useCallback(() => {
    if (!mutationInFlightRef.current) {
      setSelectedEditUser(null);
      setActionError("");
    }
  }, []);

  const closePasswordModal = useCallback(() => {
    if (!mutationInFlightRef.current) {
      setSelectedPasswordUser(null);
      setActionError("");
    }
  }, []);

  const closeDeleteModal = useCallback(() => {
    if (!mutationInFlightRef.current) {
      setSelectedDeleteUser(null);
      setActionError("");
    }
  }, []);

  const getAccessToken = useCallback(async () => {
    const {
      data: { session },
      error,
    } = await supabase.auth.getSession();

    if (error) {
      console.error("Unable to read the user-management session:", error);
    }

    if (!session?.access_token) {
      router.replace("/login");
      return null;
    }

    return session.access_token;
  }, [router]);

  async function handleCreateUser(values: CreateUserValues) {
    if (createInFlightRef.current) return;

    createInFlightRef.current = true;
    setIsCreating(true);
    setFormError("");
    setSuccessMessage("");

    try {
      const {
        data: { session },
        error: sessionError,
      } = await supabase.auth.getSession();

      if (sessionError || !session?.access_token) {
        if (sessionError) {
          console.error("Unable to read the user-creation session:", sessionError);
        }
        setFormError(t("userManagement.errors.sessionExpired"));
        return;
      }

      const response = await fetch("/api/admin/users", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fullName: values.fullName,
          email: values.email,
          password: values.password,
          role: values.role,
          addaId: values.addaId,
          isActive: values.isActive,
        }),
      });
      const payload: unknown = await response.json();

      if (!response.ok) {
        setFormError(
          errorMessageForCode(
            apiErrorCode(payload),
            "userManagement.errors.createFailed"
          )
        );
        return;
      }

      setIsCreateOpen(false);
      setSuccessMessage(t("userManagement.messages.created"));
      setPage(1);
      await loadData();
    } catch (error) {
      console.error("Unable to create managed user:", error);
      setFormError(t("userManagement.errors.createFailed"));
    } finally {
      createInFlightRef.current = false;
      setIsCreating(false);
    }
  }

  async function handleEditUser(values: UpdateUserValues) {
    if (!selectedEditUser || mutationInFlightRef.current) return;

    mutationInFlightRef.current = true;
    setIsMutating(true);
    setMutatingUserId(selectedEditUser.id);
    setActionError("");
    setSuccessMessage("");

    try {
      const accessToken = await getAccessToken();
      if (!accessToken) {
        setActionError(t("userManagement.errors.sessionExpired"));
        return;
      }

      const response = await fetch(
        `/api/admin/users/${encodeURIComponent(selectedEditUser.id)}`,
        {
          method: "PATCH",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(values),
        }
      );
      const payload: unknown = await response.json();

      if (!response.ok) {
        setActionError(
          errorMessageForCode(
            apiErrorCode(payload),
            "userManagement.errors.updateFailed"
          )
        );
        return;
      }

      const statusChanged = selectedEditUser.isActive !== values.isActive;
      setSelectedEditUser(null);
      setSuccessMessage(
        t(
          statusChanged
            ? values.isActive
              ? "userManagement.messages.activated"
              : "userManagement.messages.deactivated"
            : "userManagement.messages.updated"
        )
      );
      await loadData();
    } catch (error) {
      console.error("Unable to update managed user:", error);
      setActionError(t("userManagement.errors.updateFailed"));
    } finally {
      mutationInFlightRef.current = false;
      setIsMutating(false);
      setMutatingUserId(null);
    }
  }

  async function handleToggleStatus(user: ManagedUser) {
    if (
      mutationInFlightRef.current ||
      user.role === USER_ROLES.superAdmin ||
      !window.confirm(
        t(
          user.isActive
            ? "userManagement.statusChange.confirmDeactivate"
            : "userManagement.statusChange.confirmActivate"
        )
      )
    ) {
      return;
    }

    if (!user.fullName || !user.addaId) {
      setSuccessMessage("");
      setLoadError(t("userManagement.errors.invalidManagedProfile"));
      return;
    }

    mutationInFlightRef.current = true;
    setIsMutating(true);
    setMutatingUserId(user.id);
    setActionError("");
    setSuccessMessage("");

    try {
      const accessToken = await getAccessToken();
      if (!accessToken) {
        setLoadError(t("userManagement.errors.sessionExpired"));
        return;
      }

      const response = await fetch(
        `/api/admin/users/${encodeURIComponent(user.id)}`,
        {
          method: "PATCH",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            fullName: user.fullName,
            role: user.role,
            addaId: user.addaId,
            isActive: !user.isActive,
          }),
        }
      );
      const payload: unknown = await response.json();

      if (!response.ok) {
        setLoadError(
          errorMessageForCode(
            apiErrorCode(payload),
            "userManagement.errors.updateFailed"
          )
        );
        return;
      }

      setSuccessMessage(
        t(
          user.isActive
            ? "userManagement.messages.deactivated"
            : "userManagement.messages.activated"
        )
      );
      await loadData();
    } catch (error) {
      console.error("Unable to change managed-user status:", error);
      setLoadError(t("userManagement.errors.updateFailed"));
    } finally {
      mutationInFlightRef.current = false;
      setIsMutating(false);
      setMutatingUserId(null);
    }
  }

  async function handleResetPassword(password: string) {
    if (!selectedPasswordUser || mutationInFlightRef.current) return;

    mutationInFlightRef.current = true;
    setIsMutating(true);
    setMutatingUserId(selectedPasswordUser.id);
    setActionError("");
    setSuccessMessage("");

    try {
      const accessToken = await getAccessToken();
      if (!accessToken) {
        setActionError(t("userManagement.errors.sessionExpired"));
        return;
      }

      const response = await fetch(
        `/api/admin/users/${encodeURIComponent(
          selectedPasswordUser.id
        )}/reset-password`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ password }),
        }
      );
      const payload: unknown = await response.json();

      if (!response.ok) {
        setActionError(
          errorMessageForCode(
            apiErrorCode(payload),
            "userManagement.errors.passwordResetFailed"
          )
        );
        return;
      }

      setSelectedPasswordUser(null);
      setSuccessMessage(t("userManagement.messages.passwordReset"));
      await loadData();
    } catch (error) {
      console.error("Unable to reset managed-user password:", error);
      setActionError(t("userManagement.errors.passwordResetFailed"));
    } finally {
      mutationInFlightRef.current = false;
      setIsMutating(false);
      setMutatingUserId(null);
    }
  }

  async function handleDeleteUser() {
    if (!selectedDeleteUser || mutationInFlightRef.current) return;

    mutationInFlightRef.current = true;
    setIsMutating(true);
    setMutatingUserId(selectedDeleteUser.id);
    setActionError("");
    setSuccessMessage("");

    try {
      const accessToken = await getAccessToken();
      if (!accessToken) {
        setActionError(t("userManagement.errors.sessionExpired"));
        return;
      }

      const response = await fetch(
        `/api/admin/users/${encodeURIComponent(selectedDeleteUser.id)}`,
        {
          method: "DELETE",
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        }
      );
      const payload: unknown = await response.json();

      if (!response.ok) {
        setActionError(
          errorMessageForCode(
            apiErrorCode(payload),
            "userManagement.errors.deleteFailed"
          )
        );
        return;
      }

      setSelectedDeleteUser(null);
      setSuccessMessage(t("userManagement.messages.deleted"));
      await loadData();
    } catch (error) {
      console.error("Unable to delete managed user:", error);
      setActionError(t("userManagement.errors.deleteFailed"));
    } finally {
      mutationInFlightRef.current = false;
      setIsMutating(false);
      setMutatingUserId(null);
    }
  }

  function resetFilters() {
    setSearch("");
    setRoleFilter("all");
    setAddaFilter("all");
    setStatusFilter("all");
    setPage(1);
  }

  return (
    <main dir={dir} className="ut-module-page mx-auto max-w-[1600px] space-y-6 text-slate-900">
      <header className="flex flex-col justify-between gap-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:flex-row sm:items-center sm:p-5">
        <ModulePageHeading icon="users" accent="blue" title={t("userManagement.title")} description={t("userManagement.description")} />
        <button
          type="button"
          onClick={() => {
            setSuccessMessage("");
            setFormError("");
            setIsCreateOpen(true);
          }}
          className="inline-flex min-h-12 items-center justify-center gap-2 rounded-xl bg-blue-600 px-5 py-3 font-extrabold text-white shadow-sm hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
        >
          <Plus className="h-5 w-5" aria-hidden="true" />
          {t("userManagement.actions.addUser")}
        </button>
      </header>

      {successMessage && (
        <div
          role="status"
          className="rounded-xl border border-emerald-300 bg-emerald-50 p-4 font-bold text-emerald-800"
        >
          {successMessage}
        </div>
      )}

      {loadError && (
        <div
          role="alert"
          className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-300 bg-red-50 p-4 font-bold text-red-800"
        >
          <span>{loadError}</span>
          <button
            type="button"
            onClick={() => void loadData()}
            className="rounded-lg border border-red-300 bg-white px-4 py-2 text-red-800 hover:bg-red-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
          >
            {t("userManagement.actions.retry")}
          </button>
        </div>
      )}

      <UserManagementCards users={filteredUsers} />

      <section
        aria-labelledby="user-filters-title"
        className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"
      >
        <div className="mb-4 flex items-center justify-between gap-3">
          <h2 id="user-filters-title" className="text-xl font-extrabold text-slate-900">
            {t("userManagement.filters.title")}
          </h2>
          <button
            type="button"
            onClick={resetFilters}
            className="inline-flex items-center gap-2 rounded-lg border border-slate-300 bg-white px-4 py-2 font-bold text-slate-900 hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
          >
            <RotateCcw className="h-4 w-4" aria-hidden="true" />
            {t("userManagement.filters.reset")}
          </button>
        </div>

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">

          <VoiceTypingField fieldLabel={t("userManagement.filters.searchPlaceholder")} mode="text"><label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.filters.search")}
            </span>
            <input
              type="search"
              value={search}
              onChange={(event) => {
                setSearch(event.target.value);
                setPage(1);
              }}
              placeholder={t("userManagement.filters.searchPlaceholder")}
              className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 placeholder:text-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
            />
          </label></VoiceTypingField>


          <label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.filters.role")}
            </span>
            <select
              value={roleFilter}
              onChange={(event) => {
                setRoleFilter(event.target.value as RoleFilter);
                setPage(1);
              }}
              className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
            >
              <option value="all">{t("userManagement.filters.allRoles")}</option>
              <option value={USER_ROLES.superAdmin}>{t("roles.superAdmin")}</option>
              <option value={USER_ROLES.addaAdmin}>{t("roles.addaAdmin")}</option>
              <option value={USER_ROLES.operator}>{t("roles.operator")}</option>
            </select>
          </label>

          <label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.filters.adda")}
            </span>
            <select
              value={addaFilter}
              onChange={(event) => {
                setAddaFilter(event.target.value);
                setPage(1);
              }}
              className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
            >
              <option value="all">{t("userManagement.filters.allAddas")}</option>
              {addas.map((adda) => (
                <option key={adda.id} value={adda.id}>
                  {adda.name}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.filters.status")}
            </span>
            <select
              value={statusFilter}
              onChange={(event) => {
                setStatusFilter(event.target.value as StatusFilter);
                setPage(1);
              }}
              className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
            >
              <option value="all">{t("userManagement.filters.allStatuses")}</option>
              <option value="active">{t("userManagement.status.active")}</option>
              <option value="inactive">{t("userManagement.status.inactive")}</option>
            </select>
          </label>
        </div>
      </section>

      <UsersTable
        users={visibleUsers}
        isLoading={isLoading}
        currentPage={currentPage}
        totalPages={totalPages}
        onPageChange={setPage}
        isMutating={isMutating}
        mutatingUserId={mutatingUserId}
        onEdit={(user) => {
          setActionError("");
          setSelectedEditUser(user);
        }}
        onResetPassword={(user) => {
          setActionError("");
          setSelectedPasswordUser(user);
        }}
        onToggleStatus={(user) => void handleToggleStatus(user)}
        onDelete={(user) => {
          setActionError("");
          setSelectedDeleteUser(user);
        }}
      />

      {isCreateOpen && (
        <CreateUserForm
          addas={addas}
          isSubmitting={isCreating}
          serverError={formError}
          onClose={closeCreateForm}
          onSubmit={handleCreateUser}
        />
      )}

      {selectedEditUser && (
        <EditUserModal
          key={selectedEditUser.id}
          user={selectedEditUser}
          addas={addas}
          isSubmitting={isMutating}
          serverError={actionError}
          onClose={closeEditModal}
          onSubmit={handleEditUser}
        />
      )}

      {selectedPasswordUser && (
        <ResetPasswordModal
          key={selectedPasswordUser.id}
          user={selectedPasswordUser}
          isSubmitting={isMutating}
          serverError={actionError}
          onClose={closePasswordModal}
          onSubmit={handleResetPassword}
        />
      )}

      {selectedDeleteUser && (
        <DeleteUserModal
          key={selectedDeleteUser.id}
          user={selectedDeleteUser}
          isSubmitting={isMutating}
          serverError={actionError}
          onClose={closeDeleteModal}
          onConfirm={handleDeleteUser}
        />
      )}
    </main>
  );
}

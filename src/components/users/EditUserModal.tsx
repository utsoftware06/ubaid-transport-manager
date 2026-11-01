"use client";

import { FormEvent, useRef, useState } from "react";

import UserModalShell from "@/components/users/UserModalShell";
import type {
  AddaOption,
  CreatableUserRole,
  ManagedUser,
  UpdateUserValues,
} from "@/components/users/types";
import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type EditUserModalProps = {
  user: ManagedUser;
  addas: AddaOption[];
  isSubmitting: boolean;
  serverError: string;
  onClose: () => void;
  onSubmit: (values: UpdateUserValues) => Promise<void>;
};

export default function EditUserModal({
  user,
  addas,
  isSubmitting,
  serverError,
  onClose,
  onSubmit,
}: EditUserModalProps) {
  const { t } = useLanguage();
  const [fullName, setFullName] = useState(user.fullName ?? "");
  const [role, setRole] = useState<CreatableUserRole>(
    user.role === USER_ROLES.operator
      ? USER_ROLES.operator
      : USER_ROLES.addaAdmin
  );
  const [addaId, setAddaId] = useState(user.addaId ?? "");
  const [isActive, setIsActive] = useState(user.isActive);
  const [validationError, setValidationError] = useState("");
  const submissionInFlightRef = useRef(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submissionInFlightRef.current || isSubmitting) return;

    if (!fullName.trim()) {
      setValidationError(t("userManagement.validation.fullNameRequired"));
      return;
    }

    if (
      role !== USER_ROLES.addaAdmin &&
      role !== USER_ROLES.operator
    ) {
      setValidationError(t("userManagement.validation.roleRequired"));
      return;
    }

    if (!addaId || !addas.some((adda) => adda.id === addaId)) {
      setValidationError(t("userManagement.validation.addaRequired"));
      return;
    }

    submissionInFlightRef.current = true;
    setValidationError("");

    try {
      await onSubmit({
        fullName: fullName.trim(),
        role,
        addaId,
        isActive,
      });
    } finally {
      submissionInFlightRef.current = false;
    }
  }

  return (
    <UserModalShell
      titleId="edit-user-dialog-title"
      descriptionId="edit-user-dialog-description"
      title={t("userManagement.edit.title")}
      description={t("userManagement.edit.description")}
      closeLabel={t("userManagement.edit.close")}
      isBusy={isSubmitting}
      onClose={onClose}
    >
      {(validationError || serverError) && (
        <div
          role="alert"
          className="mt-5 rounded-xl border border-red-300 bg-red-50 p-4 font-bold text-red-800"
        >
          {validationError || serverError}
        </div>
      )}

      <form onSubmit={(event) => void handleSubmit(event)} className="mt-6">
        <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
          <label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.form.fullName")}
            </span>
            <VoiceTypingField fieldLabel={t("userManagement.form.fullName")} value={fullName} onValueChange={(value) => { setFullName(value); setValidationError(""); }} contextKey={user.id}>
              <input
                name="editFullName"
                type="text"
                required
                value={fullName}
                onChange={(event) => {
                  setFullName(event.target.value);
                  setValidationError("");
                }}
                disabled={isSubmitting}
                className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 placeholder:text-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
              />
            </VoiceTypingField>
          </label>

          <label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.form.role")}
            </span>
            <select
              name="editRole"
              value={role}
              onChange={(event) => {
                setRole(event.target.value as CreatableUserRole);
                setValidationError("");
              }}
              disabled={isSubmitting}
              className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
            >
              <option value={USER_ROLES.addaAdmin}>{t("roles.addaAdmin")}</option>
              <option value={USER_ROLES.operator}>{t("roles.operator")}</option>
            </select>
          </label>

          <label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.form.adda")}
            </span>
            <select
              name="editAddaId"
              required
              value={addaId}
              onChange={(event) => {
                setAddaId(event.target.value);
                setValidationError("");
              }}
              disabled={isSubmitting}
              className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
            >
              <option value="">{t("userManagement.form.selectAdda")}</option>
              {addas.map((adda) => (
                <option key={adda.id} value={adda.id}>
                  {adda.name}
                </option>
              ))}
            </select>
          </label>

          <label className="flex items-center gap-3 rounded-xl border border-slate-300 bg-slate-50 p-4 md:self-end">
            <input
              name="editIsActive"
              type="checkbox"
              checked={isActive}
              onChange={(event) => setIsActive(event.target.checked)}
              disabled={isSubmitting}
              className="h-5 w-5 rounded border-slate-400 text-blue-600 focus:ring-blue-500"
            />
            <span className="font-extrabold text-slate-900">
              {t("userManagement.form.activeStatus")}
            </span>
          </label>
        </div>

        <div className="mt-7 flex flex-wrap justify-end gap-3">
          <button
            type="button"
            disabled={isSubmitting}
            onClick={onClose}
            className="rounded-xl border border-slate-300 bg-white px-5 py-3 font-extrabold text-slate-900 hover:bg-slate-50 disabled:cursor-wait disabled:bg-slate-100"
          >
            {t("common.actions.cancel")}
          </button>
          <button
            type="submit"
            disabled={isSubmitting}
            className="rounded-xl bg-blue-600 px-6 py-3 font-extrabold text-white hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2 disabled:cursor-wait disabled:bg-blue-400"
          >
            {t(
              isSubmitting
                ? "userManagement.edit.saving"
                : "userManagement.edit.save"
            )}
          </button>
        </div>
      </form>
    </UserModalShell>
  );
}

"use client";

import { useRef } from "react";

import UserModalShell from "@/components/users/UserModalShell";
import type { ManagedUser } from "@/components/users/types";
import { useLanguage } from "@/contexts/LanguageContext";

type DeleteUserModalProps = {
  user: ManagedUser;
  isSubmitting: boolean;
  serverError: string;
  onClose: () => void;
  onConfirm: () => Promise<void>;
};

export default function DeleteUserModal({
  user,
  isSubmitting,
  serverError,
  onClose,
  onConfirm,
}: DeleteUserModalProps) {
  const { t } = useLanguage();
  const submissionInFlightRef = useRef(false);

  async function handleConfirm() {
    if (submissionInFlightRef.current || isSubmitting) return;
    submissionInFlightRef.current = true;

    try {
      await onConfirm();
    } finally {
      submissionInFlightRef.current = false;
    }
  }

  return (
    <UserModalShell
      titleId="delete-user-dialog-title"
      descriptionId="delete-user-dialog-description"
      title={t("userManagement.delete.title")}
      description={t("userManagement.delete.description")}
      closeLabel={t("userManagement.delete.close")}
      isBusy={isSubmitting}
      onClose={onClose}
    >
      {serverError && (
        <div
          role="alert"
          className="mt-5 rounded-xl border border-red-300 bg-red-50 p-4 font-bold text-red-800"
        >
          {serverError}
        </div>
      )}

      <div className="mt-6 rounded-xl border border-red-200 bg-red-50 p-5">
        <p className="font-extrabold text-red-900">
          {user.fullName || t("userManagement.values.notAvailable")}
        </p>
        <p dir="ltr" className="mt-1 text-start font-medium text-red-800">
          {user.email || t("userManagement.values.notAvailable")}
        </p>
        <p className="mt-4 font-bold text-red-900">
          {t("userManagement.delete.warning")}
        </p>
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
          type="button"
          disabled={isSubmitting}
          onClick={() => void handleConfirm()}
          className="rounded-xl bg-red-600 px-6 py-3 font-extrabold text-white hover:bg-red-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500 focus-visible:ring-offset-2 disabled:cursor-wait disabled:bg-red-400"
        >
          {t(
            isSubmitting
              ? "userManagement.delete.deleting"
              : "userManagement.delete.confirm"
          )}
        </button>
      </div>
    </UserModalShell>
  );
}

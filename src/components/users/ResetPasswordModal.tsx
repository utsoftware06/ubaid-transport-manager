"use client";

import { FormEvent, useRef, useState } from "react";
import { Eye, EyeOff } from "lucide-react";

import UserModalShell from "@/components/users/UserModalShell";
import type { ManagedUser } from "@/components/users/types";
import { useLanguage } from "@/contexts/LanguageContext";

type ResetPasswordModalProps = {
  user: ManagedUser;
  isSubmitting: boolean;
  serverError: string;
  onClose: () => void;
  onSubmit: (password: string) => Promise<void>;
};

export default function ResetPasswordModal({
  user,
  isSubmitting,
  serverError,
  onClose,
  onSubmit,
}: ResetPasswordModalProps) {
  const { t } = useLanguage();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [validationError, setValidationError] = useState("");
  const submissionInFlightRef = useRef(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submissionInFlightRef.current || isSubmitting) return;

    if (password.length < 8) {
      setValidationError(t("userManagement.validation.passwordLength"));
      return;
    }

    if (password !== confirmPassword) {
      setValidationError(t("userManagement.validation.passwordMismatch"));
      return;
    }

    submissionInFlightRef.current = true;
    setValidationError("");

    try {
      await onSubmit(password);
    } finally {
      submissionInFlightRef.current = false;
    }
  }

  return (
    <UserModalShell
      titleId="reset-password-dialog-title"
      descriptionId="reset-password-dialog-description"
      title={t("userManagement.resetPassword.title")}
      description={`${t("userManagement.resetPassword.description")} ${
        user.fullName || user.email || t("userManagement.values.notAvailable")
      }`}
      closeLabel={t("userManagement.resetPassword.close")}
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
              {t("userManagement.resetPassword.newPassword")}
            </span>
            <div className="relative">
              <input
                name="newPassword"
                type={showPassword ? "text" : "password"}
                autoComplete="new-password"
                dir="ltr"
                minLength={8}
                required
                value={password}
                onChange={(event) => {
                  setPassword(event.target.value);
                  setValidationError("");
                }}
                disabled={isSubmitting}
                className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 pe-12 text-start text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
              />
              <button
                type="button"
                onClick={() => setShowPassword((current) => !current)}
                disabled={isSubmitting}
                aria-label={t(
                  showPassword
                    ? "userManagement.resetPassword.hidePassword"
                    : "userManagement.resetPassword.showPassword"
                )}
                className="absolute end-2 top-1/2 -translate-y-1/2 rounded-lg p-2 text-slate-700 hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
              >
                {showPassword ? (
                  <EyeOff className="h-5 w-5" aria-hidden="true" />
                ) : (
                  <Eye className="h-5 w-5" aria-hidden="true" />
                )}
              </button>
            </div>
          </label>

          <label className="block">
            <span className="mb-2 block font-bold text-slate-800">
              {t("userManagement.resetPassword.confirmPassword")}
            </span>
            <input
              name="confirmNewPassword"
              type={showPassword ? "text" : "password"}
              autoComplete="new-password"
              dir="ltr"
              minLength={8}
              required
              value={confirmPassword}
              onChange={(event) => {
                setConfirmPassword(event.target.value);
                setValidationError("");
              }}
              disabled={isSubmitting}
              className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-start text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
            />
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
                ? "userManagement.resetPassword.saving"
                : "userManagement.resetPassword.save"
            )}
          </button>
        </div>
      </form>
    </UserModalShell>
  );
}

"use client";

import { FormEvent, useEffect, useRef, useState } from "react";
import { X } from "lucide-react";

import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import type {
  AddaOption,
  CreateUserValues,
  CreatableUserRole,
} from "@/components/users/types";

type CreateUserFormProps = {
  addas: AddaOption[];
  isSubmitting: boolean;
  serverError: string;
  onClose: () => void;
  onSubmit: (values: CreateUserValues) => Promise<void>;
};

const INITIAL_VALUES: CreateUserValues = {
  fullName: "",
  email: "",
  password: "",
  confirmPassword: "",
  role: USER_ROLES.addaAdmin,
  addaId: "",
  isActive: true,
};

export default function CreateUserForm({
  addas,
  isSubmitting,
  serverError,
  onClose,
  onSubmit,
}: CreateUserFormProps) {
  const { t, dir } = useLanguage();
  const [values, setValues] = useState<CreateUserValues>(INITIAL_VALUES);
  const [validationError, setValidationError] = useState("");
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);
  const submissionInFlightRef = useRef(false);

  useEffect(() => {
    previousFocusRef.current =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !submissionInFlightRef.current) {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocusRef.current?.focus();
    };
  }, [onClose]);

  function updateValue<Key extends keyof CreateUserValues>(
    key: Key,
    value: CreateUserValues[Key]
  ) {
    setValues((current) => ({ ...current, [key]: value }));
    setValidationError("");
  }

  function validate(): string | null {
    const fullName = values.fullName.trim();
    const email = values.email.trim();

    if (!fullName) return "userManagement.validation.fullNameRequired";
    if (!email) return "userManagement.validation.emailRequired";
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return "userManagement.validation.emailInvalid";
    }
    if (values.password.length < 8) {
      return "userManagement.validation.passwordLength";
    }
    if (values.password !== values.confirmPassword) {
      return "userManagement.validation.passwordMismatch";
    }
    if (
      values.role !== USER_ROLES.addaAdmin &&
      values.role !== USER_ROLES.operator
    ) {
      return "userManagement.validation.roleRequired";
    }
    if (!values.addaId || !addas.some((adda) => adda.id === values.addaId)) {
      return "userManagement.validation.addaRequired";
    }

    return null;
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submissionInFlightRef.current || isSubmitting) return;

    const errorKey = validate();
    if (errorKey) {
      setValidationError(t(errorKey));
      return;
    }

    submissionInFlightRef.current = true;

    try {
      await onSubmit({
        ...values,
        fullName: values.fullName.trim(),
        email: values.email.trim().toLowerCase(),
      });
    } finally {
      submissionInFlightRef.current = false;
    }
  }

  return (
    <div
      className="fixed inset-0 z-[70] flex items-center justify-center p-4"
      dir={dir}
    >
      <button
        type="button"
        aria-label={t("userManagement.form.close")}
        className="absolute inset-0 h-full w-full bg-slate-950/45"
        onClick={() => {
          if (!isSubmitting) onClose();
        }}
      />

      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-user-dialog-title"
        aria-describedby="create-user-dialog-description"
        className="relative z-10 max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 text-slate-900 shadow-2xl sm:p-7"
      >
        <header className="flex items-start justify-between gap-4">
          <div>
            <h2
              id="create-user-dialog-title"
              className="text-2xl font-extrabold text-slate-900"
            >
              {t("userManagement.form.title")}
            </h2>
            <p
              id="create-user-dialog-description"
              className="mt-2 font-medium text-slate-700"
            >
              {t("userManagement.form.description")}
            </p>
          </div>
          <button
            ref={closeButtonRef}
            type="button"
            disabled={isSubmitting}
            onClick={onClose}
            aria-label={t("userManagement.form.close")}
            className="shrink-0 rounded-lg border border-slate-300 bg-white p-2 text-slate-800 hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:bg-slate-100"
          >
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </header>

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
              <VoiceTypingField fieldLabel={t("userManagement.form.fullName")} value={values.fullName} onValueChange={(value) => updateValue("fullName", value)} contextKey="create-user">
                <input
                  name="fullName"
                  type="text"
                  autoComplete="name"
                  required
                  value={values.fullName}
                  onChange={(event) => updateValue("fullName", event.target.value)}
                  placeholder={t("userManagement.form.fullNamePlaceholder")}
                  disabled={isSubmitting}
                  className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 placeholder:text-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
                />
              </VoiceTypingField>
            </label>


            <VoiceTypingField fieldLabel={t("userManagement.form.emailPlaceholder")} mode="email"><label className="block">
              <span className="mb-2 block font-bold text-slate-800">
                {t("userManagement.form.email")}
              </span>
              <input
                name="email"
                type="email"
                autoComplete="email"
                dir="ltr"
                required
                value={values.email}
                onChange={(event) => updateValue("email", event.target.value)}
                placeholder={t("userManagement.form.emailPlaceholder")}
                disabled={isSubmitting}
                className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-start text-slate-900 placeholder:text-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
              />
            </label></VoiceTypingField>


            <label className="block">
              <span className="mb-2 block font-bold text-slate-800">
                {t("userManagement.form.temporaryPassword")}
              </span>
              <input
                name="password"
                type="password"
                autoComplete="new-password"
                dir="ltr"
                required
                minLength={8}
                value={values.password}
                onChange={(event) => updateValue("password", event.target.value)}
                placeholder={t("userManagement.form.passwordPlaceholder")}
                disabled={isSubmitting}
                className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-start text-slate-900 placeholder:text-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
              />
            </label>

            <label className="block">
              <span className="mb-2 block font-bold text-slate-800">
                {t("userManagement.form.confirmPassword")}
              </span>
              <input
                name="confirmPassword"
                type="password"
                autoComplete="new-password"
                dir="ltr"
                required
                minLength={8}
                value={values.confirmPassword}
                onChange={(event) =>
                  updateValue("confirmPassword", event.target.value)
                }
                placeholder={t("userManagement.form.confirmPasswordPlaceholder")}
                disabled={isSubmitting}
                className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-start text-slate-900 placeholder:text-slate-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
              />
            </label>

            <label className="block">
              <span className="mb-2 block font-bold text-slate-800">
                {t("userManagement.form.role")}
              </span>
              <select
                name="role"
                required
                value={values.role}
                onChange={(event) =>
                  updateValue("role", event.target.value as CreatableUserRole)
                }
                disabled={isSubmitting}
                className="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:bg-slate-100"
              >
                <option value={USER_ROLES.addaAdmin}>
                  {t("roles.addaAdmin")}
                </option>
                <option value={USER_ROLES.operator}>
                  {t("roles.operator")}
                </option>
              </select>
            </label>

            <label className="block">
              <span className="mb-2 block font-bold text-slate-800">
                {t("userManagement.form.adda")}
              </span>
              <select
                name="addaId"
                required
                value={values.addaId}
                onChange={(event) => updateValue("addaId", event.target.value)}
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
          </div>

          <label className="mt-5 flex items-center gap-3 rounded-xl border border-slate-300 bg-slate-50 p-4">
            <input
              name="isActive"
              type="checkbox"
              checked={values.isActive}
              onChange={(event) => updateValue("isActive", event.target.checked)}
              disabled={isSubmitting}
              className="h-5 w-5 rounded border-slate-400 text-blue-600 focus:ring-blue-500"
            />
            <span>
              <span className="block font-extrabold text-slate-900">
                {t("userManagement.form.activeStatus")}
              </span>
              <span className="block text-sm font-medium text-slate-700">
                {t("userManagement.form.activeStatusHelp")}
              </span>
            </span>
          </label>

          <div className="mt-7 flex flex-wrap justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="rounded-xl border border-slate-300 bg-white px-5 py-3 font-extrabold text-slate-900 hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:bg-slate-100"
            >
              {t("common.actions.cancel")}
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="rounded-xl bg-blue-600 px-6 py-3 font-extrabold text-white hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:bg-blue-400"
            >
              {t(
                isSubmitting
                  ? "userManagement.form.creating"
                  : "userManagement.form.create"
              )}
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}

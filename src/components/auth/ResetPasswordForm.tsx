"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Eye, EyeOff } from "lucide-react";
import { useRef, useState, type FormEvent } from "react";

import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";

type Props = {
  recoveryVerified: boolean;
};

export default function ResetPasswordForm({ recoveryVerified }: Props) {
  const router = useRouter();
  const { t, dir } = useLanguage();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [showPasswords, setShowPasswords] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [passwordUpdated, setPasswordUpdated] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const submissionInFlightRef = useRef(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!recoveryVerified || submissionInFlightRef.current) return;

    setErrorMessage("");
    if (password.length < 8) {
      setErrorMessage(t("auth.resetPassword.passwordTooShort"));
      return;
    }
    if (password !== confirmation) {
      setErrorMessage(t("auth.resetPassword.passwordMismatch"));
      return;
    }

    submissionInFlightRef.current = true;
    setIsSubmitting(true);

    try {
      const { error } = await supabase.auth.updateUser({ password });
      if (error) {
        setErrorMessage(t("auth.resetPassword.updateFailed"));
        return;
      }

      setPasswordUpdated(true);
      let serverCleanupSucceeded = false;
      try {
        const response = await fetch("/auth/recovery-complete", {
          method: "POST",
          credentials: "same-origin",
          cache: "no-store",
        });
        serverCleanupSucceeded = response.ok;
      } catch {
        // The browser sign-out below still clears this browser's auth session.
      }

      const { error: localSignOutError } = await supabase.auth.signOut({
        scope: "local",
      });
      if (!serverCleanupSucceeded && localSignOutError) {
        setErrorMessage(t("auth.resetPassword.cleanupFailed"));
        return;
      }
      router.replace("/login?passwordUpdated=1");
      router.refresh();
    } catch {
      setErrorMessage(t("auth.resetPassword.updateFailed"));
    } finally {
      submissionInFlightRef.current = false;
      setIsSubmitting(false);
    }
  }

  const invalidLink = !recoveryVerified;

  return (
    <main
      dir={dir}
      className="flex min-h-screen items-center justify-center bg-gray-100 p-5 text-gray-900 sm:p-8"
    >
      <section className="w-full max-w-xl rounded-2xl border border-gray-200 bg-white p-6 shadow-lg sm:p-10">
        <div dir="ltr" className="mb-7 text-center">
          <p className="text-2xl font-extrabold italic tracking-tight text-blue-950">
            UT Software
          </p>
          <p className="text-sm italic text-slate-600">Ubaid Transport Manager</p>
        </div>

        <h1 className="mb-3 text-center text-3xl font-bold text-gray-900 sm:text-4xl">
          {t("auth.resetPassword.title")}
        </h1>
        <p className="mb-7 text-center text-gray-600">
          {t("auth.resetPassword.description")}
        </p>

        {invalidLink ? (
          <div
            role="alert"
            className="rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950"
          >
            <p>{t("auth.resetPassword.invalidLink")}</p>
            <Link
              href="/forgot-password"
              className="mt-3 inline-block font-bold text-blue-800 underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600"
            >
              {t("auth.resetPassword.requestNewLink")}
            </Link>
          </div>
        ) : passwordUpdated && errorMessage ? (
          <div
            role="alert"
            className="rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950"
          >
            <p>{errorMessage}</p>
            <Link
              href="/login"
              className="mt-3 inline-block font-bold text-blue-800 underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600"
            >
              {t("auth.backToLogin")}
            </Link>
          </div>
        ) : (
          <form onSubmit={(event) => void handleSubmit(event)} className="space-y-5">
            {errorMessage ? (
              <div
                role="alert"
                className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-800"
              >
                {errorMessage}
              </div>
            ) : null}

            <div>
              <label
                htmlFor="recovery-password"
                className="mb-2 block font-semibold text-gray-900"
              >
                {t("auth.resetPassword.password")}
              </label>
              <div className="relative">
                <input
                  id="recovery-password"
                  type={showPasswords ? "text" : "password"}
                  autoComplete="new-password"
                  dir="ltr"
                  minLength={8}
                  required
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  disabled={isSubmitting}
                  className="w-full rounded-xl border border-gray-300 bg-white p-4 pe-14 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-600 disabled:cursor-not-allowed disabled:bg-gray-100"
                />
                <button
                  type="button"
                  onClick={() => setShowPasswords((current) => !current)}
                  disabled={isSubmitting}
                  aria-label={
                    t(
                      showPasswords
                        ? "userManagement.resetPassword.hidePassword"
                        : "userManagement.resetPassword.showPassword"
                    )
                  }
                  aria-pressed={showPasswords}
                  className="absolute end-2 top-1/2 -translate-y-1/2 rounded-lg p-2 text-slate-700 hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 disabled:opacity-50"
                >
                  {showPasswords ? (
                    <EyeOff className="h-5 w-5" aria-hidden="true" />
                  ) : (
                    <Eye className="h-5 w-5" aria-hidden="true" />
                  )}
                </button>
              </div>
            </div>

            <label htmlFor="recovery-password-confirm" className="block">
              <span className="mb-2 block font-semibold text-gray-900">
                {t("auth.resetPassword.confirmPassword")}
              </span>
              <input
                id="recovery-password-confirm"
                type={showPasswords ? "text" : "password"}
                autoComplete="new-password"
                dir="ltr"
                minLength={8}
                required
                value={confirmation}
                onChange={(event) => setConfirmation(event.target.value)}
                disabled={isSubmitting}
                className="w-full rounded-xl border border-gray-300 bg-white p-4 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-600 disabled:cursor-not-allowed disabled:bg-gray-100"
              />
            </label>

            <button
              type="submit"
              disabled={isSubmitting}
              aria-busy={isSubmitting}
              className="w-full rounded-xl bg-blue-900 p-4 text-lg font-bold text-white transition hover:bg-blue-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2 disabled:cursor-wait disabled:opacity-60"
            >
              {isSubmitting
                ? t("auth.resetPassword.submitting")
                : t("auth.resetPassword.submit")}
            </button>
          </form>
        )}

        <p className="mt-7 text-center">
          <Link
            href="/login"
            className="font-semibold text-blue-800 underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600"
          >
            {t("auth.backToLogin")}
          </Link>
        </p>
      </section>
    </main>
  );
}

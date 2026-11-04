"use client";

import Link from "next/link";
import { FormEvent, useRef, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

export default function ForgotPasswordPage() {
  const { t, dir } = useLanguage();
  const [email, setEmail] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [isSent, setIsSent] = useState(false);
  const submissionInFlightRef = useRef(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submissionInFlightRef.current) return;

    submissionInFlightRef.current = true;
    setErrorMessage("");
    setIsSent(false);
    setIsSubmitting(true);

    try {
      const redirectTo = `${window.location.origin}/auth/callback`;
      const { error } = await supabase.auth.resetPasswordForEmail(
        email.trim(),
        { redirectTo }
      );

      if (error) {
        console.error("Password reset request failed:", error);
        setErrorMessage(t("auth.messages.resetFailed"));
        return;
      }

      setIsSent(true);
    } catch (error) {
      console.error("Password reset request failed:", error);
      setErrorMessage(
        t("auth.messages.resetFailed")
      );
    } finally {
      submissionInFlightRef.current = false;
      setIsSubmitting(false);
    }
  }

  return (
    <main dir={dir} className="flex min-h-screen items-center justify-center bg-gray-100 p-8 text-gray-900">
      <div className="w-full max-w-xl rounded-2xl border border-gray-200 bg-white p-10 shadow-lg">
        <h1 className="mb-4 text-center text-4xl font-bold text-gray-900">
          {t("auth.forgot.title")}
        </h1>
        <p className="mb-8 text-center text-base text-gray-600">
          {t("auth.forgot.description")}
        </p>

        {isSent ? (
          <div
            role="status"
            className="mb-6 rounded-xl border border-green-200 bg-green-50 p-4 text-green-800"
          >
            {t("auth.messages.resetSent")}
          </div>
        ) : null}

        {errorMessage ? (
          <div
            role="alert"
            className="mb-6 rounded-xl border border-red-200 bg-red-50 p-4 text-red-800"
          >
            {errorMessage}
          </div>
        ) : null}

        <form onSubmit={handleSubmit} className="space-y-6">

          <div>
            <label
              htmlFor="email"
              className="mb-2 block text-base font-semibold text-gray-900"
            >
              {t("auth.email")}
            </label>
            <VoiceTypingField fieldLabel={t("auth.email")} mode="email"><input
              id="email"
              type="email"
              autoComplete="email"
              placeholder={t("auth.email")}
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
              disabled={isSubmitting}
              className="w-full rounded-xl border border-gray-300 bg-white p-5 text-xl text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:cursor-not-allowed disabled:bg-gray-100"
            /></VoiceTypingField>
          </div>


          <button
            type="submit"
            disabled={isSubmitting}
            className="w-full rounded-xl bg-blue-600 p-5 text-2xl font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
          >
            {isSubmitting
              ? t("auth.forgot.sending")
              : t("auth.forgot.submit")}
          </button>
        </form>

        <p className="mt-8 text-center">
          <Link
            href="/login"
            className="font-semibold text-blue-700 hover:text-blue-800 hover:underline"
          >
            {t("auth.backToLogin")}
          </Link>
        </p>
      </div>
    </main>
  );
}

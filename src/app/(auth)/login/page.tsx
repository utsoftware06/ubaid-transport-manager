"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

export default function LoginPage() {
  const router = useRouter();
  const { t, dir } = useLanguage();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const submissionInFlightRef = useRef(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submissionInFlightRef.current) return;

    submissionInFlightRef.current = true;
    setErrorMessage("");
    setIsSubmitting(true);

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (error) {
        console.error("Login failed:", error);
        setErrorMessage(t("auth.messages.loginFailed"));
        return;
      }

      router.replace("/dashboard");
      router.refresh();
    } catch (error) {
      console.error("Login request failed:", error);
      setErrorMessage(t("auth.messages.loginFailed"));
    } finally {
      submissionInFlightRef.current = false;
      setIsSubmitting(false);
    }
  }

  return (
    <main dir={dir} className="min-h-screen flex items-center justify-center bg-gray-100 p-8 text-gray-900">
      <div className="bg-white p-10 rounded-2xl shadow-lg border border-gray-200 w-full max-w-xl">
        <h1 className="text-5xl font-bold text-center text-gray-900 mb-10">
          {t("auth.login.title")}
        </h1>

        {errorMessage && (
          <div
            role="alert"
            className="mb-6 rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-700"
          >
            {errorMessage}
          </div>
        )}


        <form onSubmit={handleSubmit} className="space-y-6">
          <VoiceTypingField fieldLabel={t("auth.email")} mode="email"><input
            type="email"
            autoComplete="email"
            dir="ltr"
            aria-label={t("auth.email")}
            placeholder={t("auth.email")}
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
            disabled={isSubmitting}
            className="w-full border border-gray-300 p-5 rounded-xl bg-white text-xl text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          /></VoiceTypingField>

          <input
            type="password"
            autoComplete="current-password"
            dir="ltr"
            aria-label={t("auth.password")}
            placeholder={t("auth.password")}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
            disabled={isSubmitting}
            className="w-full border border-gray-300 p-5 rounded-xl bg-white text-xl text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          <button
            type="submit"
            disabled={isSubmitting}
            className="w-full bg-blue-600 hover:bg-blue-700 text-white text-2xl font-semibold p-5 rounded-xl transition"
          >
            {isSubmitting
              ? t("auth.login.submitting")
              : t("auth.login.submit")}
          </button>
        </form>


        <div className="mt-6 flex flex-col items-center gap-3 text-center">
          <Link
            href="/forgot-password"
            className="font-semibold text-blue-700 hover:text-blue-800 hover:underline"
          >
            {t("auth.login.forgotPassword")}
          </Link>
          <Link
            href="/register"
            className="font-semibold text-blue-700 hover:text-blue-800 hover:underline"
          >
            {t("auth.login.createAccount")}
          </Link>
        </div>
      </div>
    </main>
  );
}


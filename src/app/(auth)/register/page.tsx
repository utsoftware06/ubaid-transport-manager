"use client";

import Link from "next/link";
import { useLanguage } from "@/contexts/LanguageContext";

export default function RegisterPage() {
  const { t, dir } = useLanguage();

  return (
    <main
      dir={dir}
      className="flex min-h-screen items-center justify-center bg-slate-100 p-8 text-slate-900"
    >
      <section
        aria-labelledby="registration-managed-title"
        className="w-full max-w-xl rounded-2xl border border-slate-200 bg-white p-10 text-center shadow-lg"
      >
        <h1
          id="registration-managed-title"
          className="text-4xl font-bold text-slate-900"
        >
          {t("auth.register.adminManagedTitle")}
        </h1>

        <p className="mt-6 text-lg font-semibold leading-8 text-slate-700">
          {t("auth.register.adminManagedDescription")}
        </p>

        <Link
          href="/login"
          className="mt-8 inline-flex min-h-12 items-center justify-center rounded-xl bg-blue-600 px-6 py-3 text-lg font-bold text-white transition hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
        >
          {t("auth.backToLogin")}
        </Link>
      </section>
    </main>
  );
}

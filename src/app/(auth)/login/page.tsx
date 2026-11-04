"use client";

import { useRouter } from "next/navigation";
import {
  useRef,
  useState,
  useSyncExternalStore,
  type FormEvent,
} from "react";

import UTLoginDesign from "@/components/auth/UTLoginDesign";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";

function subscribeToNavigation(onChange: () => void) {
  window.addEventListener("popstate", onChange);
  return () => window.removeEventListener("popstate", onChange);
}

function getPasswordUpdatedSnapshot() {
  return new URLSearchParams(window.location.search).get("passwordUpdated") === "1";
}

function getPasswordUpdatedServerSnapshot() {
  return false;
}

export default function LoginPage() {
  const router = useRouter();
  const { t } = useLanguage();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const passwordUpdated = useSyncExternalStore(
    subscribeToNavigation,
    getPasswordUpdatedSnapshot,
    getPasswordUpdatedServerSnapshot
  );
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
    <UTLoginDesign
      email={email}
      password={password}
      onEmailChange={setEmail}
      onPasswordChange={setPassword}
      onSubmit={handleSubmit}
      isLoading={isSubmitting}
      error={errorMessage || null}
      successNotice={passwordUpdated ? t("auth.messages.passwordUpdated") : null}
    />
  );
}

"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { X } from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";

type UserModalShellProps = {
  titleId: string;
  descriptionId: string;
  title: string;
  description: string;
  closeLabel: string;
  isBusy: boolean;
  onClose: () => void;
  children: ReactNode;
};

export default function UserModalShell({
  titleId,
  descriptionId,
  title,
  description,
  closeLabel,
  isBusy,
  onClose,
  children,
}: UserModalShellProps) {
  const { dir } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);
  const isBusyRef = useRef(isBusy);

  useEffect(() => {
    isBusyRef.current = isBusy;
  }, [isBusy]);

  useEffect(() => {
    previousFocusRef.current =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isBusyRef.current) {
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

  return (
    <div
      dir={dir}
      className="fixed inset-0 z-[70] flex items-center justify-center p-4"
    >
      <button
        type="button"
        aria-label={closeLabel}
        disabled={isBusy}
        onClick={onClose}
        className="absolute inset-0 h-full w-full bg-slate-950/45 disabled:cursor-wait"
      />

      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={descriptionId}
        className="relative z-10 max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 text-slate-900 shadow-2xl sm:p-7"
      >
        <header className="flex items-start justify-between gap-4">
          <div>
            <h2 id={titleId} className="text-2xl font-extrabold text-slate-900">
              {title}
            </h2>
            <p id={descriptionId} className="mt-2 font-medium text-slate-700">
              {description}
            </p>
          </div>

          <button
            ref={closeButtonRef}
            type="button"
            disabled={isBusy}
            onClick={onClose}
            aria-label={closeLabel}
            className="shrink-0 rounded-lg border border-slate-300 bg-white p-2 text-slate-800 hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-wait disabled:bg-slate-100"
          >
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </header>

        {children}
      </section>
    </div>
  );
}

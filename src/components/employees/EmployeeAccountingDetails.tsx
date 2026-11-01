"use client";

import { useEffect, useEffectEvent, useRef } from "react";
import { useLanguage } from "@/contexts/LanguageContext";

export type AccountingDetail = {
  label: string;
  value: string;
  technical?: boolean;
};

type Props = {
  title: string;
  description: string;
  details: AccountingDetail[];
  onClose: () => void;
};

export default function EmployeeAccountingDetails({
  title,
  description,
  details,
  onClose,
}: Props) {
  const { t, dir } = useLanguage();
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const closeFromEffect = useEffectEvent(onClose);

  useEffect(() => {
    const previouslyFocused = document.activeElement;
    const previousOverflow = document.body.style.overflow;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") closeFromEffect();
    }

    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);
    closeButtonRef.current?.focus();

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", handleKeyDown);
      if (previouslyFocused instanceof HTMLElement) previouslyFocused.focus();
    };
  }, []);

  return (
    <div
      dir={dir}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="employee-accounting-details-title"
        aria-describedby="employee-accounting-details-description"
        className="max-h-[90vh] w-full max-w-4xl overflow-y-auto rounded-xl bg-white p-6 shadow-2xl md:p-8"
      >
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h2 id="employee-accounting-details-title" className="text-2xl font-bold text-gray-900">
              {title}
            </h2>
            <p id="employee-accounting-details-description" className="mt-1 text-sm font-semibold text-gray-900">
              {description}
            </p>
          </div>
          <button ref={closeButtonRef} type="button" onClick={onClose} className="rounded-lg bg-gray-900 px-4 py-2 text-sm font-bold text-white hover:bg-black">
            {t("common.actions.close")}
          </button>
        </div>

        <dl className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {details.map((detail, index) => (
            <div key={`${detail.label}-${index}`} className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
              <dt className="text-xs font-extrabold uppercase text-gray-900">{detail.label}</dt>
              <dd dir={detail.technical ? "ltr" : undefined} className="mt-2 break-words font-bold text-gray-900">
                {detail.value || "-"}
              </dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}

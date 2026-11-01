"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { X } from "lucide-react";

import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import type {
  PartyAddaOption,
  PartyFormValues,
  PartyRecord,
} from "@/types/parties";

type PartyFormModalProps = {
  party: PartyRecord | null;
  addas: PartyAddaOption[];
  fixedAddaId: string | null;
  isSaving: boolean;
  onClose: () => void;
  onSubmit: (values: PartyFormValues) => Promise<void>;
};

export default function PartyFormModal({
  party,
  addas,
  fixedAddaId,
  isSaving,
  onClose,
  onSubmit,
}: PartyFormModalProps) {
  const { t, dir } = useLanguage();
  const [name, setName] = useState(party?.name ?? "");
  const [phone, setPhone] = useState(party?.phone ?? "");
  const [city, setCity] = useState(party?.city ?? "");
  const [address, setAddress] = useState(party?.address ?? "");
  const [addaId, setAddaId] = useState(party?.adda_id ?? fixedAddaId ?? "");
  const [isActive, setIsActive] = useState(party?.is_active ?? true);
  const [validationMessage, setValidationMessage] = useState("");
  const nameInputRef = useRef<HTMLInputElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);
  const isSavingRef = useRef(isSaving);
  const submittingRef = useRef(false);

  useEffect(() => {
    isSavingRef.current = isSaving;
  }, [isSaving]);

  useEffect(() => {
    previousFocusRef.current =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    nameInputRef.current?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !isSavingRef.current) onClose();
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocusRef.current?.focus();
    };
  }, [onClose]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submittingRef.current) return;

    if (!name.trim()) {
      setValidationMessage(t("parties.validation.nameRequired"));
      nameInputRef.current?.focus();
      return;
    }
    if (!addaId) {
      setValidationMessage(t("parties.validation.addaRequired"));
      return;
    }

    submittingRef.current = true;
    setValidationMessage("");
    try {
      await onSubmit({
        name: name.trim(),
        phone: phone.trim(),
        city: city.trim(),
        address: address.trim(),
        addaId,
        isActive,
      });
    } finally {
      submittingRef.current = false;
    }
  }

  const inputClassName =
    "w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-900 placeholder:text-slate-500 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100";

  return (
    <div dir={dir} className="fixed inset-0 z-[70] flex items-center justify-center p-4">
      <button
        type="button"
        aria-label={t("common.actions.close")}
        disabled={isSaving}
        onClick={onClose}
        className="absolute inset-0 h-full w-full bg-slate-950/45 disabled:cursor-wait"
      />
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="party-form-title"
        aria-describedby="party-form-description"
        className="relative z-10 max-h-[92vh] w-full max-w-2xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 text-slate-900 shadow-2xl sm:p-7"
      >
        <header className="flex items-start justify-between gap-4">
          <div>
            <h2 id="party-form-title" className="text-2xl font-extrabold">
              {t(party ? "parties.form.editTitle" : "parties.form.addTitle")}
            </h2>
            <p id="party-form-description" className="mt-2 font-medium text-slate-700">
              {t("parties.form.description")}
            </p>
          </div>
          <button
            type="button"
            disabled={isSaving}
            onClick={onClose}
            aria-label={t("common.actions.close")}
            className="rounded-lg border border-slate-300 bg-white p-2 text-slate-800 hover:bg-slate-50 focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-wait"
          >
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </header>

        <form onSubmit={handleSubmit} className="mt-6 space-y-5">
          {validationMessage && (
            <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 font-semibold text-red-700">
              {validationMessage}
            </p>
          )}
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
            <div>
              <label htmlFor="party-name" className="mb-2 block font-bold">
                {t("parties.fields.name")} *
              </label>
              <VoiceTypingField fieldLabel={t("parties.fields.name")} value={name} onValueChange={setName} contextKey={party?.id ?? "new"}>
              <input
                ref={nameInputRef}
                id="party-name"
                name="partyName"
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder={t("parties.placeholders.name")}
                className={inputClassName}
                maxLength={160}
              />
              </VoiceTypingField>
            </div>
            <div>
              <label htmlFor="party-phone" className="mb-2 block font-bold">
                {t("parties.fields.phone")}
              </label>
              <VoiceTypingField fieldLabel={t("parties.fields.phone")} mode="phone" contextKey={party?.id ?? "new"}>
              <input
                id="party-phone"
                name="partyPhone"
                type="tel"
                dir="ltr"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                placeholder={t("parties.placeholders.phone")}
                className={inputClassName}
                maxLength={40}
              />
              </VoiceTypingField>
            </div>

            <div>
              <label htmlFor="party-city" className="mb-2 block font-bold">
                {t("parties.fields.city")}
              </label>
              <VoiceTypingField fieldLabel={t("parties.fields.city")} mode="text" contextKey={party?.id ?? "new"}><input
                id="party-city"
                name="partyCity"
                value={city}
                onChange={(event) => setCity(event.target.value)}
                placeholder={t("parties.placeholders.city")}
                className={inputClassName}
                maxLength={120}
              /></VoiceTypingField>
            </div>

            {!fixedAddaId && (
              <div>
                <label htmlFor="party-adda" className="mb-2 block font-bold">
                  {t("parties.fields.adda")} *
                </label>
                <select
                  id="party-adda"
                  name="partyAdda"
                  value={addaId}
                  onChange={(event) => setAddaId(event.target.value)}
                  className={inputClassName}
                >
                  <option value="">{t("parties.placeholders.selectAdda")}</option>
                  {addas.map((adda) => (
                    <option key={adda.id} value={adda.id}>{adda.name}</option>
                  ))}
                </select>
              </div>
            )}
          </div>
          <div>
            <label htmlFor="party-address" className="mb-2 block font-bold">
              {t("parties.fields.address")}
            </label>
            <VoiceTypingField fieldLabel={t("parties.fields.address")} value={address} onValueChange={setAddress} contextKey={party?.id ?? "new"}>
            <textarea
              id="party-address"
              name="partyAddress"
              rows={3}
              value={address}
              onChange={(event) => setAddress(event.target.value)}
              placeholder={t("parties.placeholders.address")}
              className={inputClassName}
              maxLength={500}
            />
            </VoiceTypingField>
          </div>
          <label className="flex items-center gap-3 font-bold">
            <input
              type="checkbox"
              checked={isActive}
              onChange={(event) => setIsActive(event.target.checked)}
              className="h-5 w-5 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
            />
            {t("parties.fields.active")}
          </label>
          <footer className="flex flex-wrap justify-end gap-3 border-t border-slate-200 pt-5">
            <button
              type="button"
              disabled={isSaving}
              onClick={onClose}
              className="rounded-lg border border-slate-300 bg-white px-5 py-3 font-bold text-slate-900 hover:bg-slate-50 disabled:cursor-wait"
            >
              {t("common.actions.cancel")}
            </button>
            <button
              type="submit"
              disabled={isSaving}
              className="rounded-lg bg-blue-600 px-6 py-3 font-bold text-white hover:bg-blue-700 disabled:cursor-wait disabled:bg-blue-400"
            >
              {isSaving
                ? t("common.states.saving")
                : t(party ? "common.actions.update" : "common.actions.save")}
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}

"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { X } from "lucide-react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { findOtherAddaDuplicates, mapOtherAddaError, saveOtherAdda, setOtherAddaStatus } from "./api";
import type { OtherAdda, OtherAddaBusinessType, OtherAddaDuplicate, OtherAddaMasterSnapshot } from "./types";

type Props = {
  master: OtherAdda | null;
  initialBusinessType: OtherAddaBusinessType;
  /** Only Super Admin supplies this explicitly selected target. */
  targetAddaId?: string;
  canReactivate: boolean;
  onClose: () => void;
  onSaved: (id: string) => void;
  onUseExisting: (match: OtherAddaDuplicate) => void;
  onBusyChange: (busy: boolean) => void;
  onRefresh: () => Promise<void>;
};
const inputClass = "w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-950 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100";
const nullableFields = ["contact_person", "mobile", "whatsapp", "city", "address", "ntn_cnic", "notes"] as const;
const labels = { adda_name: "Adda Name", contact_person: "Contact Person", mobile: "Mobile", whatsapp: "WhatsApp", city: "City", address: "Address", ntn_cnic: "NTN/CNIC", notes: "Notes" };

export default function OtherAddaFormModal({ master, initialBusinessType, targetAddaId, canReactivate, onClose, onSaved, onUseExisting, onBusyChange, onRefresh }: Props) {
  const { dir } = useLanguage();
  const [values, setValues] = useState(() => ({
    adda_name: master?.adda_name ?? "", contact_person: master?.contact_person ?? "",
    mobile: master?.mobile ?? "", whatsapp: master?.whatsapp ?? "", city: master?.city ?? "",
    address: master?.address ?? "", ntn_cnic: master?.ntn_cnic ?? "", notes: master?.notes ?? "",
    business_type: master?.business_type ?? initialBusinessType,
  }));
  const [matches, setMatches] = useState<OtherAddaDuplicate[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [uncertainCreate, setUncertainCreate] = useState(false);
  const [checkedAfterUncertainty, setCheckedAfterUncertainty] = useState(false);
  const lock = useRef(false);
  const dialogRef = useRef<HTMLElement>(null);
  const nameRef = useRef<HTMLInputElement>(null);
  const closeRef = useRef(onClose);
  useEffect(() => { closeRef.current = onClose; }, [onClose]);

  useEffect(() => {
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    nameRef.current?.focus();
    function keydown(event: KeyboardEvent) {
      if (event.key === "Escape" && !lock.current) closeRef.current();
      if (event.key !== "Tab") return;
      const elements = Array.from(dialogRef.current?.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled)') ?? []);
      const first = elements[0]; const last = elements[elements.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    }
    document.addEventListener("keydown", keydown);
    return () => { document.body.style.overflow = overflow; document.removeEventListener("keydown", keydown); previousFocus?.focus(); };
  }, []);

  function snapshot(): OtherAddaMasterSnapshot {
    const result: OtherAddaMasterSnapshot = {
      adda_name: values.adda_name.trim(), business_type: values.business_type,
      contact_person: null, mobile: null, whatsapp: null, city: null, address: null, ntn_cnic: null, notes: null,
    };
    for (const field of nullableFields) result[field] = values[field].trim() || null;
    return result;
  }
  function change(field: keyof typeof values, value: string) {
    setValues((previous) => ({ ...previous, [field]: value }));
    setMatches(null); setError(""); setCheckedAfterUncertainty(false);
  }
  async function run(action: () => Promise<void>) {
    if (lock.current) return;
    lock.current = true; setBusy(true); onBusyChange(true); setError("");
    try { await action(); }
    catch (failure) { const mapped = mapOtherAddaError(failure); console.error("Other Adda form action failed", mapped); setError(mapped.message); }
    finally { lock.current = false; setBusy(false); onBusyChange(false); }
  }
  async function checkDuplicates() {
    const payload = snapshot();
    const found = await findOtherAddaDuplicates({ adda_name: payload.adda_name, mobile: payload.mobile, city: payload.city,
      ...(targetAddaId ? { target_adda_id: targetAddaId } : {}) });
    setMatches(found); return found;
  }
  async function save() {
    try {
      const id = await saveOtherAdda({ ...snapshot(), id: master?.id ?? null,
        ...(targetAddaId ? { target_adda_id: targetAddaId } : {}) });
      onSaved(id);
    } catch (failure) {
      const mapped = mapOtherAddaError(failure);
      // Known server rejection is definitive. Network/unknown/malformed success may have committed.
      if (!master && (mapped.reason === "unknown" || mapped.reason === "invalid_response")) {
        setUncertainCreate(true); setCheckedAfterUncertainty(false); setMatches(null);
      }
      throw mapped;
    }
  }
  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!values.adda_name.trim()) { setError("Adda Name is required."); nameRef.current?.focus(); return; }
    if (uncertainCreate) return;
    void run(async () => { if (!master && (await checkDuplicates()).length) return; await save(); });
  }
  function continueCreation() {
    if (uncertainCreate && !checkedAfterUncertainty) return;
    if (!window.confirm(uncertainCreate
      ? "The earlier create may have succeeded. Have you checked existing records and intentionally chosen to create again?"
      : "Create another Other Adda despite the possible existing matches?")) return;
    void run(save);
  }
  function reviewUncertain() {
    void run(async () => {
      await onRefresh(); await checkDuplicates(); setCheckedAfterUncertainty(true);
    });
  }

  return <div dir={dir} className="fixed inset-0 z-[70] flex items-center justify-center p-3 sm:p-5">
    <button type="button" disabled={busy} onClick={onClose} aria-label="Close form" className="absolute inset-0 bg-slate-950/45" />
    <section ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby="other-adda-form-title" aria-describedby="other-adda-form-description" className="relative max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-2xl border border-blue-100 bg-white p-5 text-slate-950 shadow-2xl sm:p-7">
      <header className="flex items-start justify-between gap-3">
        <div><h2 id="other-adda-form-title" className="text-2xl font-extrabold">{master ? "Edit Other Adda" : "Add Other Adda"}</h2>
          <p id="other-adda-form-description" className="mt-2 font-medium text-slate-700">One-Time accounts retain their history. Status is managed separately.</p></div>
        <button type="button" disabled={busy} onClick={onClose} aria-label="Close form" className="rounded-lg border p-2 focus-visible:ring-2 focus-visible:ring-blue-500"><X size={20} /></button>
      </header>
      <form onSubmit={submit} className="mt-6 space-y-5">
        {error && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{error}</p>}
        {uncertainCreate && <section role="alert" className="space-y-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950">
          <p className="font-bold">Creation could not be confirmed. It may already have succeeded. Your form data is retained; refresh and check existing records before intentionally retrying.</p>
          <button type="button" disabled={busy} onClick={reviewUncertain} className="rounded-lg border border-amber-400 bg-white px-4 py-2 font-bold">Refresh / Check Existing Records</button>
          {checkedAfterUncertainty && <p>Review the matches below. An empty check cannot guarantee that the earlier request will not finish later.</p>}
        </section>}
        <fieldset disabled={busy} className="grid gap-4 sm:grid-cols-2">
          {(["adda_name", "contact_person", "mobile", "whatsapp", "city", "ntn_cnic"] as const).map((field) => <label key={field} className="block font-bold" htmlFor={`oa-${field}`}>
            {labels[field]}{field === "adda_name" ? " *" : ""}
            <VoiceTypingField fieldLabel={labels[field]} value={values[field]} onValueChange={(value) => change(field, value)} mode={field === "mobile" || field === "whatsapp" ? "phone" : field === "ntn_cnic" ? "identifier" : "text"} contextKey={master?.id ?? targetAddaId ?? "new"}><input ref={field === "adda_name" ? nameRef : undefined} id={`oa-${field}`} name={field} required={field === "adda_name"} type={field === "mobile" || field === "whatsapp" ? "tel" : "text"} dir={field === "mobile" || field === "whatsapp" || field === "ntn_cnic" ? "ltr" : undefined} value={values[field]} onChange={(e) => change(field, e.target.value)} className={`${inputClass} mt-2`} /></VoiceTypingField>
          </label>)}
          <label htmlFor="oa-business-type" className="font-bold">Business Type *<select id="oa-business-type" required value={values.business_type} onChange={(e) => change("business_type", e.target.value)} className={`${inputClass} mt-2`}><option value="regular">Regular</option><option value="one_time">One-Time</option></select></label>
          {(["address", "notes"] as const).map((field) => <label key={field} htmlFor={`oa-${field}`} className="font-bold sm:col-span-2">{labels[field]}<VoiceTypingField fieldLabel={labels[field]} value={values[field]} onValueChange={(value) => change(field, value)} contextKey={master?.id ?? targetAddaId ?? "new"}><textarea id={`oa-${field}`} rows={3} value={values[field]} onChange={(e) => change(field, e.target.value)} className={`${inputClass} mt-2`} /></VoiceTypingField></label>)}
        </fieldset>
        {matches !== null && !master && <section aria-labelledby="oa-duplicate-title" className="space-y-3 rounded-xl border border-blue-200 bg-blue-50 p-4">
          <h3 id="oa-duplicate-title" className="text-lg font-extrabold">{matches.length ? "Possible Existing Other Adda" : "No Possible Matches Found"}</h3>
          {matches.map((match) => <article key={match.id} className="rounded-lg border border-blue-200 bg-white p-4">
            <p className="font-extrabold">{match.adda_name}</p><p className="mt-1 text-sm font-medium"><span dir="ltr">{match.mobile || "No mobile"}</span> · {match.city || "No city"} · {match.status === "active" ? "Active" : "Archived"}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button type="button" disabled={busy} onClick={() => onUseExisting(match)} className="rounded-lg border border-blue-300 px-3 py-2 font-bold text-blue-800">Use Existing</button>
              {match.status === "archived" && canReactivate && <button type="button" disabled={busy} onClick={() => void run(async () => {
                await setOtherAddaStatus({ other_adda_id: match.id, status: "active" });
                setMatches((previous) => previous?.map((item) => item.id === match.id ? { ...item, status: "active" } : item) ?? null);
                await onRefresh();
              })} className="rounded-lg border border-emerald-300 px-3 py-2 font-bold text-emerald-800">Reactivate</button>}
            </div>
          </article>)}
          {(matches.length > 0 || uncertainCreate) && <button type="button" disabled={busy || (uncertainCreate && !checkedAfterUncertainty)} onClick={continueCreation} className="rounded-lg border border-amber-400 bg-white px-4 py-2 font-bold text-amber-900">Continue Anyway{uncertainCreate ? " / Intentionally Retry Create" : ""}</button>}
        </section>}
        <footer className="flex flex-wrap justify-end gap-3 border-t pt-5">
          <button type="button" disabled={busy} onClick={onClose} className="rounded-lg border px-5 py-3 font-bold">Cancel</button>
          <button type="submit" disabled={busy || uncertainCreate} className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white hover:bg-blue-700 disabled:bg-blue-400">{busy ? "Working…" : master ? "Save Changes" : "Check & Create"}</button>
        </footer>
      </form>
    </section>
  </div>;
}

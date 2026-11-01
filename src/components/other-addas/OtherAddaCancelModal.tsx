"use client";

import { useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { mapOtherAddaError, reverseOtherAddaObligation } from "./api";
import type { DatabaseNumeric, OtherAddaTransaction, ReverseOtherAddaObligationInput } from "./types";

type Props = {
  entry: OtherAddaTransaction;
  onClose: () => void;
  onSaved: (transactionId: string) => Promise<void>;
};
type Form = { cancelDate: string; reason: string };
type PendingAttempt = { payload: ReverseOtherAddaObligationInput; unresolved: boolean };

const input = "mt-2 w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-950 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";
const secondary = "rounded-lg border border-blue-200 bg-white px-4 py-2.5 font-bold text-blue-800 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50";

function pakistanDate(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Karachi", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}
function money(value: DatabaseNumeric): string {
  const text = String(value);
  if (!/^\d+(?:\.\d{1,2})?$/.test(text)) return text;
  const [whole, fraction = ""] = text.split(".");
  return `Rs. ${whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${fraction.padEnd(2, "0")}`;
}

export default function OtherAddaCancelModal({ entry, onClose, onSaved }: Props) {
  const { dir } = useLanguage();
  const [form, setForm] = useState<Form>(() => ({ cancelDate: pakistanDate(), reason: "" }));
  const [attempt, setAttempt] = useState<PendingAttempt | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const submitting = useRef(false);
  const locked = attempt?.unresolved === true;
  const isLena = entry.side === "receivable";

  function buildPayload(): ReverseOtherAddaObligationInput {
    if (!form.cancelDate) throw new Error("Cancel Date is required.");
    if (form.cancelDate < entry.transaction_date) throw new Error("Cancel Date cannot be earlier than the original Entry Date.");
    const reason = form.reason.trim();
    if (!reason) throw new Error("Reason is required.");
    return {
      transaction_id: entry.id,
      transaction_date: form.cancelDate,
      reason,
      request_id: globalThis.crypto.randomUUID(),
    };
  }

  async function submit() {
    if (submitting.current) return;
    submitting.current = true; setBusy(true); setError("");
    let current = attempt;
    try {
      if (!current) {
        current = { payload: buildPayload(), unresolved: false };
        setAttempt(current);
      }
      const transactionId = await reverseOtherAddaObligation(current.payload);
      setAttempt(null);
      await onSaved(transactionId);
    } catch (failure) {
      const mapped = mapOtherAddaError(failure);
      if (!current) {
        setAttempt(null);
        setError(mapped.message);
      } else if (mapped.reason === "idempotency_payload_mismatch") {
        setAttempt({ ...current, unresolved: true });
        setError("This request ID was already used with different cancel details. Refresh the account and verify the existing Entry Cancel before trying again.");
      } else if (mapped.reason === "unknown" || mapped.reason === "invalid_response") {
        setAttempt({ ...current, unresolved: true });
        setError("The cancellation result is uncertain. The details are locked. Use Retry Same Cancel; it safely keeps the same request ID.");
      } else {
        setAttempt(null);
        setError(mapped.message);
      }
    } finally { submitting.current = false; setBusy(false); }
  }

  return <div dir={dir} className="fixed inset-0 z-[70] flex items-center justify-center p-3 sm:p-5">
    <button type="button" aria-label="Close cancel form" disabled={busy || locked} onClick={onClose} className="absolute inset-0 bg-slate-950/55 disabled:cursor-not-allowed" />
    <section role="dialog" aria-modal="true" aria-labelledby="other-adda-cancel-title" aria-describedby="other-adda-cancel-description" className="relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-2xl border border-amber-100 bg-white p-5 text-slate-950 shadow-2xl sm:p-7">
      <div className="flex items-start justify-between gap-4"><div><h2 id="other-adda-cancel-title" className="text-2xl font-extrabold">Cancel Entry</h2><p id="other-adda-cancel-description" className="mt-2 font-medium text-slate-700">This will not delete the original entry. A separate Entry Cancel record will be added.</p></div><button type="button" disabled={busy || locked} onClick={onClose} aria-label="Close" className={secondary}>×</button></div>
      <div className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4"><dl className="grid gap-3 sm:grid-cols-2"><div><dt className="font-bold text-amber-900">Side</dt><dd className="mt-1 font-extrabold">{isLena ? "LENA HAI" : "DENA HAI"}</dd></div><div><dt className="font-bold text-amber-900">Amount</dt><dd dir="ltr" className="mt-1 font-extrabold">{money(entry.amount)}</dd></div><div><dt className="font-bold text-amber-900">Entry Date</dt><dd dir="ltr" className="mt-1">{entry.transaction_date}</dd></div><div><dt className="font-bold text-amber-900">Due Date</dt><dd dir="ltr" className="mt-1">{entry.due_date || "—"}</dd></div><div><dt className="font-bold text-amber-900">Reference</dt><dd className="mt-1 break-words">{entry.reference_no || "—"}</dd></div><div className="sm:col-span-2"><dt className="font-bold text-amber-900">Description</dt><dd className="mt-1 whitespace-pre-wrap break-words">{entry.description}</dd></div></dl><p className="mt-4 font-bold text-amber-950">Cancellation reduces effective {isLena ? "LENA" : "DENA"} by the original amount.</p></div>
      {error && <p role="alert" className="mt-4 rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{error}</p>}
      {locked && <p role="status" className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 font-semibold text-amber-950">Do not change or recreate this cancellation. Retrying uses request ID <span dir="ltr" className="break-all">{attempt.payload.request_id}</span>.</p>}
      <form onSubmit={(event) => { event.preventDefault(); void submit(); }} className="mt-5 space-y-4">

        <VoiceTypingField fieldLabel="Cancel Date *" mode="date"><label className="block font-bold">Cancel Date *<input type="date" required min={entry.transaction_date} value={form.cancelDate} disabled={busy || locked} onChange={(event) => setForm({ ...form, cancelDate: event.target.value })} className={input} /></label></VoiceTypingField>

        <label className="block font-bold">Reason *<VoiceTypingField fieldLabel="Reason" value={form.reason} onValueChange={(reason) => setForm((current) => ({ ...current, reason }))} contextKey={entry.id}><textarea required rows={4} value={form.reason} disabled={busy || locked} onChange={(event) => setForm({ ...form, reason: event.target.value })} placeholder="Why is this entry being cancelled?" className={input} /></VoiceTypingField></label>
        <div className="flex flex-wrap justify-end gap-3 pt-2"><button type="button" disabled={busy || locked} onClick={onClose} className={secondary}>Keep Entry</button><button type="submit" disabled={busy} className="rounded-lg bg-amber-600 px-5 py-2.5 font-bold text-white hover:bg-amber-700 disabled:cursor-not-allowed disabled:opacity-60">{busy ? "Saving…" : locked ? "Retry Same Cancel" : "Confirm Entry Cancel"}</button></div>
      </form>
    </section>
  </div>;
}

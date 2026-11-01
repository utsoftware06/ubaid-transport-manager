"use client";

import { useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { mapOtherAddaError, normalizeOtherAddaAmount, postOtherAddaObligation } from "./api";
import type { OtherAddaSide, PostOtherAddaObligationInput } from "./types";

type Props = {
  otherAddaId: string;
  otherAddaName: string;
  side: OtherAddaSide;
  onClose: () => void;
  onSaved: (transactionId: string) => Promise<void>;
};
type Form = { transactionDate: string; dueDate: string; amount: string; referenceNo: string; description: string };
type PendingAttempt = { payload: PostOtherAddaObligationInput; unresolved: boolean };

const input = "mt-2 w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-950 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";
const secondary = "rounded-lg border border-blue-200 bg-white px-4 py-2.5 font-bold text-blue-800 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50";

function localDate(): string {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

export default function OtherAddaEventModal({ otherAddaId, otherAddaName, side, onClose, onSaved }: Props) {
  const { dir } = useLanguage();
  const [form, setForm] = useState<Form>(() => ({ transactionDate: localDate(), dueDate: "", amount: "", referenceNo: "", description: "" }));
  const [attempt, setAttempt] = useState<PendingAttempt | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const submitting = useRef(false);
  const isLena = side === "receivable";
  const locked = attempt?.unresolved === true;

  function buildPayload(): PostOtherAddaObligationInput {
    if (!form.transactionDate) throw new Error("Date is required.");
    if (form.dueDate && form.dueDate < form.transactionDate) throw new Error("Due Date cannot be earlier than Entry Date.");
    const amount = normalizeOtherAddaAmount(form.amount);
    if (!form.description.trim()) throw new Error("Description is required.");
    return {
      other_adda_id: otherAddaId,
      transaction_date: form.transactionDate,
      side,
      amount,
      description: form.description.trim(),
      reference_no: form.referenceNo.trim() || null,
      dueDate: form.dueDate || null,
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
      const transactionId = await postOtherAddaObligation(current.payload);
      setAttempt(null);
      await onSaved(transactionId);
    } catch (failure) {
      const mapped = mapOtherAddaError(failure);
      if (!current) {
        // Local validation failed before any request was issued.
        setAttempt(null);
        setError(mapped.message);
      } else if (mapped.reason === "idempotency_payload_mismatch") {
        if (current) setAttempt({ ...current, unresolved: true });
        setError("This request ID was already used with different entry details. Refresh the account and verify the original entry before trying again.");
      } else if (mapped.reason === "unknown" || mapped.reason === "invalid_response") {
        if (current) setAttempt({ ...current, unresolved: true });
        setError("The posting result is uncertain. The entry details are locked. Use Retry Same Entry; it safely keeps the same request ID.");
      } else {
        setAttempt(null);
        setError(mapped.message);
      }
    } finally { submitting.current = false; setBusy(false); }
  }

  return <div dir={dir} className="fixed inset-0 z-[70] flex items-center justify-center p-3 sm:p-5">
    <button type="button" aria-label="Close entry form" disabled={busy || locked} onClick={onClose} className="absolute inset-0 bg-slate-950/55 disabled:cursor-not-allowed" />
    <section role="dialog" aria-modal="true" aria-labelledby="other-adda-event-title" aria-describedby="other-adda-event-description" className="relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-2xl border border-blue-100 bg-white p-5 text-slate-950 shadow-2xl sm:p-7">
      <div className="flex items-start justify-between gap-4"><div><h2 id="other-adda-event-title" className="text-2xl font-extrabold">{isLena ? "Add LENA Entry" : "Add DENA Entry"}</h2><p id="other-adda-event-description" className="mt-2 font-medium text-slate-700">{otherAddaName} · {isLena ? "Other Adda se hamare Adda ko paisay LENA hain." : "Hamare Adda ne Other Adda ko paisay DENA hain."}</p></div><button type="button" disabled={busy || locked} onClick={onClose} aria-label="Close" className={secondary}>×</button></div>
      <div className={`mt-5 rounded-xl border p-4 font-bold ${isLena ? "border-emerald-200 bg-emerald-50 text-emerald-900" : "border-amber-200 bg-amber-50 text-amber-950"}`}>Entry side: {isLena ? "LENA HAI (Receivable)" : "DENA HAI (Payable)"}</div>
      {error && <p role="alert" className="mt-4 rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{error}</p>}
      {locked && <p role="status" className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 font-semibold text-amber-950">Do not change or recreate this entry. Retrying uses request ID <span dir="ltr" className="break-all">{attempt.payload.request_id}</span>.</p>}
      <form onSubmit={(event) => { event.preventDefault(); void submit(); }} className="mt-5 space-y-4">

        <VoiceTypingField fieldLabel="Entry Date *" mode="date"><label className="block font-bold">Entry Date *<input type="date" required value={form.transactionDate} disabled={busy || locked} onChange={(e) => setForm({ ...form, transactionDate: e.target.value })} className={input} /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel="Due Date (Optional)" mode="date"><label className="block font-bold">Due Date (Optional)<input type="date" min={form.transactionDate || undefined} value={form.dueDate} disabled={busy || locked} onChange={(e) => setForm({ ...form, dueDate: e.target.value })} className={input} /><span className="mt-1 block text-sm font-medium text-slate-600">A due date is a reminder only. It does not create a payment or settlement.</span></label></VoiceTypingField>


        <VoiceTypingField fieldLabel="Amount *" mode="amount"><label className="block font-bold">Amount *<input type="text" inputMode="decimal" required placeholder="0.00" value={form.amount} disabled={busy || locked} onChange={(e) => setForm({ ...form, amount: e.target.value })} className={input} /><span className="mt-1 block text-sm font-medium text-slate-600">Positive amount, maximum two decimal places. No rounding is applied.</span></label></VoiceTypingField>


        <VoiceTypingField fieldLabel="Reference No" mode="identifier"><label className="block font-bold">Reference No<input type="text" value={form.referenceNo} disabled={busy || locked} onChange={(e) => setForm({ ...form, referenceNo: e.target.value })} className={input} /></label></VoiceTypingField>

        <label className="block font-bold">Description *<VoiceTypingField fieldLabel="Description" value={form.description} onValueChange={(description) => setForm((current) => ({ ...current, description }))} contextKey={`${otherAddaId}:${side}`}><textarea required rows={4} placeholder="Freight adjustment, Loading amount, or Manual account entry" value={form.description} disabled={busy || locked} onChange={(e) => setForm({ ...form, description: e.target.value })} className={input} /></VoiceTypingField></label>
        <div className="flex flex-wrap justify-end gap-3 pt-2"><button type="button" disabled={busy || locked} onClick={onClose} className={secondary}>Cancel</button><button type="submit" disabled={busy} className={`rounded-lg px-5 py-2.5 font-bold text-white disabled:cursor-not-allowed disabled:opacity-60 ${isLena ? "bg-emerald-600 hover:bg-emerald-700" : "bg-amber-600 hover:bg-amber-700"}`}>{busy ? "Saving…" : locked ? "Retry Same Entry" : isLena ? "Save LENA Entry" : "Save DENA Entry"}</button></div>
      </form>
    </section>
  </div>;
}

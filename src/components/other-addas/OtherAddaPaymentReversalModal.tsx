"use client";

import { useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { mapOtherAddaError, reverseOtherAddaPayment } from "./api";
import type { OtherAddaPayment, ReverseOtherAddaPaymentInput } from "./types";

type Props = {
  payment: OtherAddaPayment;
  onClose: () => void;
  onSaved: (reversalId: string) => Promise<void>;
};
type PendingAttempt = { payload: ReverseOtherAddaPaymentInput; unresolved: boolean };

const input = "mt-2 w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-950 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";
const secondary = "rounded-lg border border-blue-200 bg-white px-4 py-2.5 font-bold text-blue-800 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50";

function pakistanDate(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Karachi", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

export default function OtherAddaPaymentReversalModal({ payment, onClose, onSaved }: Props) {
  const { dir } = useLanguage();
  const [reversalDate, setReversalDate] = useState(pakistanDate);
  const [reason, setReason] = useState("");
  const [attempt, setAttempt] = useState<PendingAttempt | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const submitting = useRef(false);
  const locked = attempt?.unresolved === true;

  function buildPayload(): ReverseOtherAddaPaymentInput {
    const trimmedReason = reason.trim();
    if (!reversalDate || reversalDate < payment.payment_date) throw new Error("Reversal date cannot be earlier than the payment date.");
    if (!trimmedReason) throw new Error("A reversal reason is required.");
    return {
      payment_id: payment.id,
      reversal_date: reversalDate,
      reason: trimmedReason,
      request_id: globalThis.crypto.randomUUID(),
    };
  }

  async function submit() {
    if (submitting.current) return;
    submitting.current = true;
    setBusy(true);
    setError("");
    let current = attempt;
    try {
      if (!current) {
        current = { payload: buildPayload(), unresolved: false };
        setAttempt(current);
      }
      const reversalId = await reverseOtherAddaPayment(current.payload);
      setAttempt(null);
      await onSaved(reversalId);
    } catch (failure) {
      const mapped = mapOtherAddaError(failure);
      if (!current) {
        setAttempt(null);
        setError(mapped.message);
      } else if (mapped.reason === "idempotency_payload_mismatch") {
        setAttempt({ ...current, unresolved: true });
        setError("This request ID is linked to different reversal details. Refresh payment history and verify the existing reversal.");
      } else if (mapped.reason === "unknown" || mapped.reason === "invalid_response") {
        setAttempt({ ...current, unresolved: true });
        setError("The reversal result is uncertain. Details are locked; retrying uses the same request ID.");
      } else {
        setAttempt(null);
        setError(mapped.message);
      }
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  }

  return <div dir={dir} className="fixed inset-0 z-[70] flex items-center justify-center p-3 sm:p-5">
    <button type="button" aria-label="Close payment reversal form" disabled={busy || locked} onClick={onClose} className="absolute inset-0 bg-slate-950/55 disabled:cursor-not-allowed" />
    <section role="dialog" aria-modal="true" aria-labelledby="other-adda-payment-reversal-title" className="relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-2xl border border-amber-200 bg-white p-5 text-slate-950 shadow-2xl sm:p-7">
      <div className="flex items-start justify-between gap-4"><div><h2 id="other-adda-payment-reversal-title" className="text-2xl font-extrabold">Reverse Posted Payment?</h2><p className="mt-2 font-medium text-slate-700">This appends an opposite Cashbook movement and restores the original FIFO allocations. The original payment remains in history.</p></div><button type="button" disabled={busy || locked} onClick={onClose} aria-label="Close" className={secondary}>×</button></div>
      <div className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 font-semibold text-amber-950"><p>{payment.side === "receivable" ? "Received LENA" : "Paid DENA"} · {payment.payment_date} · {payment.payment_method}</p><p dir="ltr" className="mt-1 text-xl font-extrabold">{payment.amount}</p></div>
      {error && <p role="alert" className="mt-4 rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{error}</p>}
      {locked && <p role="status" className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 font-semibold text-amber-950">Do not change or recreate this reversal. Retry keeps request ID <span dir="ltr" className="break-all">{attempt.payload.request_id}</span>.</p>}
      <form onSubmit={(event) => { event.preventDefault(); void submit(); }} className="mt-5 space-y-4">

        <VoiceTypingField fieldLabel="Reversal Date *" mode="date"><label className="block font-bold">Reversal Date *<input type="date" min={payment.payment_date} required value={reversalDate} disabled={busy || locked} onChange={(event) => setReversalDate(event.target.value)} className={input} /></label></VoiceTypingField>

        <label className="block font-bold">Reason *<VoiceTypingField fieldLabel="Reason" value={reason} onValueChange={setReason} contextKey={payment.id}><textarea required rows={4} value={reason} disabled={busy || locked} onChange={(event) => setReason(event.target.value)} className={input} /></VoiceTypingField></label>
        <div className="flex flex-wrap justify-end gap-3 pt-2"><button type="button" disabled={busy || locked} onClick={onClose} className={secondary}>Keep Payment</button><button type="submit" disabled={busy} className="rounded-lg bg-amber-700 px-5 py-2.5 font-bold text-white disabled:cursor-not-allowed disabled:opacity-60">{busy ? "Reversing…" : locked ? "Retry Same Reversal" : "Confirm Reversal"}</button></div>
      </form>
    </section>
  </div>;
}

"use client";

import { useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { mapOtherAddaError, normalizeOtherAddaAmount, postOtherAddaPayment } from "./api";
import type { DatabaseNumeric, OtherAddaSide, PostOtherAddaPaymentInput } from "./types";

type Props = {
  otherAddaId: string;
  otherAddaName: string;
  side: OtherAddaSide;
  outstanding: DatabaseNumeric;
  onClose: () => void;
  onSaved: (paymentId: string) => Promise<void>;
};
type PendingAttempt = { payload: PostOtherAddaPaymentInput; unresolved: boolean };

const input = "mt-2 w-full rounded-lg border border-slate-300 bg-white px-4 py-3 font-medium text-slate-950 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";
const secondary = "rounded-lg border border-blue-200 bg-white px-4 py-2.5 font-bold text-blue-800 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50";
const paymentMethods = ["Cash", "Bank", "Cheque", "Online Transfer", "Account"] as const;

function pakistanDate(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Karachi", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}
function toCents(value: DatabaseNumeric): bigint {
  const raw = String(value);
  if (!/^\d+(?:\.\d{1,2})?$/.test(raw)) throw new Error("Outstanding balance is invalid. Refresh account balances.");
  const [whole, fraction = ""] = raw.split(".");
  return BigInt(whole) * BigInt(100) + BigInt(fraction.padEnd(2, "0"));
}
function formatCents(value: bigint): string {
  const whole = String(value / BigInt(100)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `Rs. ${whole}.${String(value % BigInt(100)).padStart(2, "0")}`;
}

export default function OtherAddaPaymentForm({ otherAddaId, otherAddaName, side, outstanding, onClose, onSaved }: Props) {
  const { dir } = useLanguage();
  const [paymentDate, setPaymentDate] = useState(pakistanDate);
  const [amount, setAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<(typeof paymentMethods)[number]>("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");
  const [attempt, setAttempt] = useState<PendingAttempt | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const submitting = useRef(false);
  const locked = attempt?.unresolved === true;
  const isReceivable = side === "receivable";

  function buildPayload(): PostOtherAddaPaymentInput {
    if (!paymentDate) throw new Error("Payment date is required.");
    const normalizedAmount = normalizeOtherAddaAmount(amount);
    if (toCents(normalizedAmount) > toCents(outstanding)) {
      throw new Error("Payment amount cannot exceed the current outstanding amount.");
    }
    return {
      other_adda_id: otherAddaId,
      payment_date: paymentDate,
      side,
      amount: normalizedAmount,
      payment_method: paymentMethod,
      reference_no: referenceNo.trim() || null,
      remarks: remarks.trim() || null,
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
      const paymentId = await postOtherAddaPayment(current.payload);
      setAttempt(null);
      await onSaved(paymentId);
    } catch (failure) {
      const mapped = mapOtherAddaError(failure);
      if (!current) {
        setAttempt(null);
        setError(mapped.message);
      } else if (mapped.reason === "idempotency_payload_mismatch") {
        setAttempt({ ...current, unresolved: true });
        setError("This request ID is linked to different payment details. Refresh the account and verify payment history before retrying.");
      } else if (mapped.reason === "unknown" || mapped.reason === "invalid_response") {
        setAttempt({ ...current, unresolved: true });
        setError("The payment result is uncertain. Details are locked; retrying uses the same request ID.");
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
    <button type="button" aria-label="Close payment form" disabled={busy || locked} onClick={onClose} className="absolute inset-0 bg-slate-950/55 disabled:cursor-not-allowed" />
    <section role="dialog" aria-modal="true" aria-labelledby="other-adda-payment-title" className="relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-2xl border border-blue-100 bg-white p-5 text-slate-950 shadow-2xl sm:p-7">
      <div className="flex items-start justify-between gap-4"><div><h2 id="other-adda-payment-title" className="text-2xl font-extrabold">{isReceivable ? "Receive LENA Payment" : "Pay DENA"}</h2><p className="mt-2 font-medium text-slate-700">{otherAddaName}</p></div><button type="button" disabled={busy || locked} onClick={onClose} aria-label="Close" className={secondary}>×</button></div>
      <div className={`mt-5 rounded-xl border p-4 ${isReceivable ? "border-emerald-200 bg-emerald-50 text-emerald-950" : "border-amber-200 bg-amber-50 text-amber-950"}`}>
        <p className="font-bold">Current {isReceivable ? "LENA" : "DENA"} outstanding</p>
        <p dir="ltr" className="mt-1 text-2xl font-extrabold">{formatCents(toCents(outstanding))}</p>
        <p className="mt-1 text-sm font-medium">The server checks the authoritative outstanding amount again when posting.</p>
      </div>
      {error && <p role="alert" className="mt-4 rounded-xl border border-red-200 bg-red-50 p-4 font-semibold text-red-800">{error}</p>}
      {locked && <p role="status" className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 font-semibold text-amber-950">Do not change or recreate this payment. Retry keeps request ID <span dir="ltr" className="break-all">{attempt.payload.request_id}</span>.</p>}
      <form onSubmit={(event) => { event.preventDefault(); void submit(); }} className="mt-5 space-y-4">

        <VoiceTypingField fieldLabel="Payment Date *" mode="date"><label className="block font-bold">Payment Date *<input type="date" required value={paymentDate} disabled={busy || locked} onChange={(event) => setPaymentDate(event.target.value)} className={input} /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel="Amount *" mode="amount"><label className="block font-bold">Amount *<input type="text" inputMode="decimal" required placeholder="0.00" value={amount} disabled={busy || locked} onChange={(event) => setAmount(event.target.value)} className={input} /></label></VoiceTypingField>

        <label className="block font-bold">Payment Method *<select required value={paymentMethod} disabled={busy || locked} onChange={(event) => setPaymentMethod(event.target.value as (typeof paymentMethods)[number])} className={input}>{paymentMethods.map((method) => <option key={method} value={method}>{method}</option>)}</select></label>
        <VoiceTypingField fieldLabel="Reference No" mode="identifier"><label className="block font-bold">Reference No<input type="text" value={referenceNo} disabled={busy || locked} onChange={(event) => setReferenceNo(event.target.value)} className={input} /></label></VoiceTypingField>

        <label className="block font-bold">Remarks<VoiceTypingField fieldLabel="Remarks" value={remarks} onValueChange={setRemarks} contextKey={`${otherAddaId}:${side}`}><textarea rows={3} value={remarks} disabled={busy || locked} onChange={(event) => setRemarks(event.target.value)} className={input} /></VoiceTypingField></label>
        <div className="flex flex-wrap justify-end gap-3 pt-2"><button type="button" disabled={busy || locked} onClick={onClose} className={secondary}>Cancel</button><button type="submit" disabled={busy} className={`rounded-lg px-5 py-2.5 font-bold text-white disabled:cursor-not-allowed disabled:opacity-60 ${isReceivable ? "bg-emerald-600 hover:bg-emerald-700" : "bg-amber-600 hover:bg-amber-700"}`}>{busy ? "Posting…" : locked ? "Retry Same Payment" : "Post Payment"}</button></div>
      </form>
    </section>
  </div>;
}

"use client";

import { useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

export type ManualVoucherAdjustment = {
  id: string;
  manual_settlement_id: string;
  voucher_id: number;
  manual_voucher_id: string;
  adjustment_no: string;
  adjustment_date: string;
  freight_adjustment: number | string;
  expense_adjustment: number | string;
  net_adjustment: number | string;
  reason: string;
  status: "draft" | "finalized";
  reverses_adjustment_id: string | null;
  finalized_at: string | null;
};

type Props = {
  open: boolean;
  voucher: {
    id: number;
    expenseNo: string;
    vehicleNo: string;
    voucherDate: string;
    settlement: {
      id: string;
      total_freight: number | string;
      total_expense_amount: number | string;
      net_vehicle_amount: number | string;
    } | null;
    adjustments: ManualVoucherAdjustment[];
  } | null;
  onClose: () => void;
  onChanged: () => Promise<void>;
};

function amount(value: number | string | null | undefined) {
  const n = Number(value ?? 0);
  return `Rs. ${(Number.isFinite(n) ? n : 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
}

function numericValue(value: string) {
  if (!value.trim()) return 0;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

function newAdjustmentNo(voucherId: number) {
  const token = globalThis.crypto?.randomUUID?.().replaceAll("-", "").slice(0, 8)
    ?? Math.random().toString(36).slice(2, 10).toUpperCase();
  return `MVA-${voucherId}-${Date.now()}-${token}`;
}

export default function ManualVoucherAdjustmentModal({ open, voucher, onClose, onChanged }: Props) {
  const initialDraft = voucher?.adjustments.find((row) => row.status === "draft") ?? null;
  const [editingDraftId, setEditingDraftId] = useState<string | null>(initialDraft?.id ?? null);
  const [adjustmentDate, setAdjustmentDate] = useState(initialDraft?.adjustment_date ?? new Date().toISOString().slice(0, 10));
  const [freightAdjustment, setFreightAdjustment] = useState(initialDraft ? String(initialDraft.freight_adjustment) : "0");
  const [expenseAdjustment, setExpenseAdjustment] = useState(initialDraft ? String(initialDraft.expense_adjustment) : "0");
  const [reason, setReason] = useState(initialDraft?.reason ?? "");
  const [adjustmentRows, setAdjustmentRows] = useState(voucher?.adjustments ?? []);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState("");

  const drafts = useMemo(() => adjustmentRows.filter((row) => row.status === "draft"), [adjustmentRows]);
  const finalized = useMemo(() => adjustmentRows.filter((row) => row.status === "finalized"), [adjustmentRows]);
  const finalizedNet = finalized.reduce((sum, row) => sum + Number(row.net_adjustment || 0), 0);
  const draftNet = numericValue(freightAdjustment) - numericValue(expenseAdjustment);
  const originalNet = Number(voucher?.settlement?.net_vehicle_amount ?? 0);

  if (!open || !voucher) return null;

  async function refreshAdjustments() {
    if (!voucher) return;
    const result = await supabase
      .from("manual_voucher_adjustments")
      .select("*")
      .eq("voucher_id", voucher.id)
      .order("created_at", { ascending: true });
    if (result.error) throw new Error(result.error.message);
    setAdjustmentRows((result.data ?? []) as ManualVoucherAdjustment[]);
    await onChanged();
  }

  async function saveDraft(): Promise<string> {
    if (!voucher) throw new Error("Manual Voucher is unavailable.");
    const freight = numericValue(freightAdjustment);
    const expense = numericValue(expenseAdjustment);
    if (!adjustmentDate || !reason.trim() || !Number.isFinite(freight) || !Number.isFinite(expense)) {
      throw new Error("Enter a date, valid adjustment amounts, and a reason.");
    }
    const net = freight - expense;
    if (Math.round(net * 100) === 0) throw new Error("Net adjustment must be greater or less than zero.");

    const existingDraft = voucher.adjustments.find((row) => row.id === editingDraftId && row.status === "draft");
    const result = await supabase.rpc("save_manual_voucher_adjustment", {
      p_adjustment_id: existingDraft?.id ?? null,
      p_voucher_id: voucher.id,
      p_adjustment_no: existingDraft?.adjustment_no ?? newAdjustmentNo(voucher.id),
      p_adjustment_date: adjustmentDate,
      p_freight_adjustment: freight,
      p_expense_adjustment: expense,
      p_reason: reason.trim(),
    });
    if (result.error) throw new Error(result.error.message);
    const savedId = typeof result.data === "string" ? result.data : String(result.data ?? "");
    if (!savedId) throw new Error("The adjustment RPC did not return an adjustment ID.");
    setEditingDraftId(savedId);
    await refreshAdjustments();
    return savedId;
  }

  async function handleSave(finalize: boolean) {
    if (isSaving) return;
    setIsSaving(true);
    setError("");
    try {
      const id = await saveDraft();
      if (finalize) {
        const result = await supabase.rpc("finalize_manual_voucher_adjustment", { p_adjustment_id: id });
        if (result.error) throw new Error(result.error.message);
        setEditingDraftId(null);
        setFreightAdjustment("0");
        setExpenseAdjustment("0");
        setReason("");
        await refreshAdjustments();
      }
    } catch (saveError) {
      const message = saveError instanceof Error ? saveError.message : String(saveError);
      setError(message);
    } finally {
      setIsSaving(false);
    }
  }

  async function handleReverse(adjustment: ManualVoucherAdjustment) {
    if (!voucher) return;
    const alreadyReversed = adjustmentRows.some((row) => row.reverses_adjustment_id === adjustment.id);
    if (adjustment.reverses_adjustment_id || alreadyReversed) return;
    const reversalReason = window.prompt("Reason for reversing this finalized adjustment:");
    if (!reversalReason?.trim()) return;
    if (!window.confirm(`Create an equal and opposite Owner/Gari adjustment for ${adjustment.adjustment_no}?`)) return;
    setIsSaving(true);
    setError("");
    try {
      const result = await supabase.rpc("reverse_manual_voucher_adjustment", {
        p_adjustment_id: adjustment.id,
        p_reversal_date: new Date().toISOString().slice(0, 10),
        p_reason: reversalReason.trim(),
      });
      if (result.error) throw new Error(result.error.message);
      await refreshAdjustments();
    } catch (reverseError) {
      setError(reverseError instanceof Error ? reverseError.message : String(reverseError));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4" onMouseDown={(event) => { if (event.target === event.currentTarget && !isSaving) onClose(); }}>
      <section role="dialog" aria-modal="true" aria-labelledby="manual-adjustment-title" className="max-h-[92vh] w-full max-w-4xl overflow-y-auto rounded-2xl bg-white p-5 shadow-2xl sm:p-7">
        <header className="mb-5 flex items-start justify-between gap-4">
          <div>
            <h2 id="manual-adjustment-title" className="text-2xl font-black text-slate-950">Manual Voucher Adjustment</h2>
            <p className="mt-1 font-semibold text-slate-600">Voucher {voucher.expenseNo} · {voucher.vehicleNo || "—"} · {voucher.voucherDate}</p>
          </div>
          <button type="button" onClick={onClose} disabled={isSaving} className="rounded-lg bg-slate-100 px-4 py-2 font-bold text-slate-800 disabled:opacity-50">Close</button>
        </header>

        <div className="mb-6 grid gap-3 sm:grid-cols-3">
          <Metric label="Original Freight" value={amount(voucher.settlement?.total_freight)} />
          <Metric label="Original Expenses" value={amount(voucher.settlement?.total_expense_amount)} />
          <Metric label="Original Chakkar Net" value={amount(voucher.settlement?.net_vehicle_amount)} />
        </div>

        <section className="mb-6 rounded-xl border border-purple-200 bg-purple-50 p-4">
          <h3 className="font-black text-purple-950">Append-only adjustment</h3>
          <p className="mt-1 text-sm font-medium text-purple-900">Net adjustment = freight adjustment − expense adjustment. Finalizing adds one separate Owner/Gari transaction; it does not rewrite the original settlement or create Cashbook income.</p>
          <div className="mt-4 grid gap-3 md:grid-cols-2">

            <VoiceTypingField fieldLabel="Adjustment Date" mode="date"><label className="text-sm font-bold text-slate-800">Adjustment Date<input type="date" value={adjustmentDate} onChange={(event) => setAdjustmentDate(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2" /></label></VoiceTypingField>

            <label className="text-sm font-bold text-slate-800">Reason / Notes<VoiceTypingField fieldLabel="Reason / Notes" value={reason} onValueChange={setReason} contextKey={`${voucher.id}:${editingDraftId ?? "new"}`}><input value={reason} onChange={(event) => setReason(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2" maxLength={1000} /></VoiceTypingField></label>

            <VoiceTypingField fieldLabel="Freight Adjustment (+ / −)" mode="amount"><label className="text-sm font-bold text-slate-800">Freight Adjustment (+ / −)<input type="number" step="0.01" value={freightAdjustment} onChange={(event) => setFreightAdjustment(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-end" /></label></VoiceTypingField>


            <VoiceTypingField fieldLabel="Expense Adjustment (+ / −)" mode="amount"><label className="text-sm font-bold text-slate-800">Expense Adjustment (+ / −)<input type="number" step="0.01" value={expenseAdjustment} onChange={(event) => setExpenseAdjustment(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-end" /></label></VoiceTypingField>

          </div>
          <div className="mt-4 grid gap-3 sm:grid-cols-3">
            <Metric label="Net Adjustment" value={Number.isFinite(draftNet) ? amount(draftNet) : "Invalid amount"} />
            <Metric label="Prior Finalized Adjustments" value={amount(finalizedNet)} />
            <Metric label="Adjusted Chakkar Net Preview" value={Number.isFinite(draftNet) ? amount(originalNet + finalizedNet + draftNet) : "—"} />
          </div>
          {error && <p role="alert" className="mt-3 rounded-lg bg-red-100 p-3 font-semibold text-red-800">{error}</p>}
          <div className="mt-4 flex flex-wrap gap-2">
            <button type="button" onClick={() => void handleSave(false)} disabled={isSaving} className="rounded-lg border border-purple-300 bg-white px-4 py-2 font-bold text-purple-900 disabled:opacity-50">{isSaving ? "Saving…" : "Save Draft"}</button>
            <button type="button" onClick={() => void handleSave(true)} disabled={isSaving} className="rounded-lg bg-purple-700 px-4 py-2 font-bold text-white hover:bg-purple-800 disabled:opacity-50">{isSaving ? "Processing…" : "Save & Finalize"}</button>
            {drafts.length > 0 && <span className="self-center text-sm font-semibold text-amber-800">Draft adjustment is editable until finalized.</span>}
          </div>
        </section>

        <section className="overflow-x-auto rounded-xl border border-slate-200">
          <h3 className="border-b border-slate-200 bg-slate-50 p-3 font-black text-slate-900">Adjustment history</h3>
          <table className="w-full min-w-[760px] text-sm">
            <thead className="bg-slate-800 text-white"><tr><th className="p-3 text-start">Adjustment</th><th className="p-3 text-start">Date</th><th className="p-3 text-end">Freight</th><th className="p-3 text-end">Expense</th><th className="p-3 text-end">Net</th><th className="p-3 text-start">Status / Reason</th><th className="p-3 text-start">Action</th></tr></thead>
          <tbody>{adjustmentRows.map((row) => {
              const reversed = adjustmentRows.some((candidate) => candidate.reverses_adjustment_id === row.id);
              return <tr key={row.id} className="border-t border-slate-200">
                <td className="p-3 font-bold">{row.adjustment_no}</td><td className="p-3">{row.adjustment_date}</td>
                <td className="p-3 text-end">{amount(row.freight_adjustment)}</td><td className="p-3 text-end">{amount(row.expense_adjustment)}</td><td className="p-3 text-end font-black">{amount(row.net_adjustment)}</td>
                <td className="p-3"><span className="font-bold">{row.status}</span>{row.reverses_adjustment_id && <span className="ms-1 text-xs">(reversal)</span>}<div className="text-xs text-slate-600">{row.reason}</div></td>
                <td className="p-3">{row.status === "draft" ? <button type="button" onClick={() => { setEditingDraftId(row.id); setAdjustmentDate(row.adjustment_date); setFreightAdjustment(String(row.freight_adjustment)); setExpenseAdjustment(String(row.expense_adjustment)); setReason(row.reason); }} className="rounded-md bg-amber-100 px-3 py-1 font-bold text-amber-900">Edit Draft</button> : !row.reverses_adjustment_id && !reversed ? <button type="button" disabled={isSaving} onClick={() => void handleReverse(row)} className="rounded-md bg-slate-100 px-3 py-1 font-bold text-slate-800 disabled:opacity-50">Reverse</button> : <span className="text-xs text-slate-500">—</span>}</td>
              </tr>;
            })}
              {adjustmentRows.length === 0 && <tr><td colSpan={7} className="p-6 text-center font-semibold text-slate-500">No adjustments recorded.</td></tr>}
            </tbody>
          </table>
        </section>
      </section>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-lg border border-slate-200 bg-white p-3"><span className="block text-xs font-bold text-slate-600">{label}</span><strong className="mt-1 block [direction:ltr] text-end text-slate-950">{value}</strong></div>;
}

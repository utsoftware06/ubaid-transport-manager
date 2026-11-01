"use client";

import { useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import { X } from "lucide-react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import type {
  AddaAccountCategory,
  AddaAccountEmployee,
  AddaAccountEntry,
  AddaFinanceSettlement,
} from "./types";

const control = "h-10 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm text-slate-900 shadow-sm outline-none transition focus:border-blue-500 focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";
const label = "block space-y-1.5 text-sm font-semibold text-slate-700";
const secondaryButton = "inline-flex h-10 items-center justify-center rounded-lg border border-slate-300 bg-white px-4 text-sm font-bold text-slate-700 transition hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:opacity-60";
const primaryButton = "inline-flex h-10 items-center justify-center rounded-lg bg-blue-600 px-4 text-sm font-bold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-60";
const methods = ["Cash", "Bank", "Cheque", "Online Transfer", "Account"];

function localDate() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function money(value: number) {
  return `Rs. ${value.toLocaleString("en-PK", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

function DialogShell({ title, children, onClose, wide = false }: {
  title: string; children: ReactNode; onClose: () => void; wide?: boolean;
}) {
  const { t } = useLanguage();
  return <div className="fixed inset-0 z-[80] flex items-center justify-center bg-slate-950/45 p-3 sm:p-6" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <section role="dialog" aria-modal="true" aria-label={title} className={`flex max-h-[92vh] w-full flex-col overflow-hidden rounded-2xl border border-blue-100 bg-white shadow-2xl ${wide ? "max-w-4xl" : "max-w-2xl"}`}>
      <header className="flex shrink-0 items-center justify-between gap-3 border-b border-slate-100 px-5 py-4 sm:px-6">
        <h2 className="text-lg font-extrabold text-slate-900 sm:text-xl">{title}</h2>
        <button type="button" onClick={onClose} aria-label={t("common.actions.close")} className="rounded-lg p-2 text-slate-500 hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"><X size={19} /></button>
      </header>
      <div className="min-h-0 overflow-y-auto p-5 sm:p-6">{children}</div>
    </section>
  </div>;
}

export type SourceFormValue = {
  date: string;
  categoryId: string;
  amount: number;
  paidAmount: number;
  receivedAmount: number;
  paymentMethod: string | null;
  employeeId: string | null;
  referenceNo: string | null;
  description: string | null;
  remarks: string | null;
  requestId: string;
};

export type MetadataFormValue = {
  referenceNo: string | null;
  description: string | null;
  remarks: string | null;
  requestId: string;
};

export function AddaFinanceSourceDialog({
  kind, categories, employees, onClose, onSubmit,
}: {
  kind: "expense" | "income";
  categories: AddaAccountCategory[];
  employees: AddaAccountEmployee[];
  onClose: () => void;
  onSubmit: (value: SourceFormValue) => Promise<boolean>;
}) {
  const { t, dir } = useLanguage();
  const isExpense = kind === "expense";
  const [date, setDate] = useState(localDate);
  const [categoryId, setCategoryId] = useState("");
  const [amount, setAmount] = useState("");
  const [paidAmount, setPaidAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("");
  const [employeeId, setEmployeeId] = useState("");
  const [referenceNo, setReferenceNo] = useState("");
  const [description, setDescription] = useState("");
  const [remarks, setRemarks] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const requestRef = useRef("");
  const submittedSignature = useRef("");
  const amountNumber = Number(amount);
  const paidNumber = Number(paidAmount || 0);
  const statusText = useMemo(() => {
    if (!amountNumber || !paidNumber) return t("addaAccount.form.unpaid");
    return paidNumber >= amountNumber ? t("addaAccount.form.paid") : t("addaAccount.form.partial");
  }, [amountNumber, paidNumber, t]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    if (!date || !Number.isFinite(amountNumber) || amountNumber <= 0 || !Number.isFinite(paidNumber)
      || paidNumber < 0 || paidNumber > amountNumber || (isExpense && !categoryId)
      || (paidNumber > 0 && !paymentMethod)) {
      setError(!Number.isFinite(amountNumber) || amountNumber <= 0
        ? t("addaAccount.messages.amountInvalid")
        : paidNumber > amountNumber ? t("addaAccount.messages.amountExceeds")
          : paidNumber > 0 && !paymentMethod ? t("addaAccount.messages.methodRequired")
            : t("addaAccount.messages.required"));
      return;
    }
    const signature = JSON.stringify([kind, date, categoryId, amountNumber, paidNumber, paymentMethod, employeeId, referenceNo, description, remarks]);
    if (!requestRef.current || submittedSignature.current !== signature) requestRef.current = crypto.randomUUID();
    submittedSignature.current = signature;
    setSaving(true);
    try {
      const succeeded = await onSubmit({
        date,
        categoryId,
        amount: amountNumber,
        paidAmount: isExpense ? paidNumber : 0,
        receivedAmount: isExpense ? 0 : paidNumber,
        paymentMethod: paidNumber > 0 ? paymentMethod : null,
        employeeId: isExpense && employeeId ? employeeId : null,
        referenceNo: referenceNo.trim() || null,
        description: description.trim() || null,
        remarks: remarks.trim() || null,
        requestId: requestRef.current,
      });
      if (succeeded) onClose();
    } catch {
      setError(t("addaAccount.messages.requestFailed"));
    } finally {
      setSaving(false);
    }
  }

  const recognizedAmountLabel = t("addaAccount.form.amount");
  return <DialogShell title={t(isExpense ? "addaAccount.form.expenseTitle" : "addaAccount.form.incomeTitle")} onClose={saving ? () => undefined : onClose}>
    <form dir={dir} onSubmit={(event) => void submit(event)} className="space-y-4">
      {!isExpense && <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm font-medium text-amber-900">{t("addaAccount.form.incomeNotice")}</p>}
      <div className="grid gap-4 sm:grid-cols-2">

        <VoiceTypingField fieldLabel={t("addaAccount.form.date")} mode="date"><label className={label}>{t("addaAccount.form.date")}<input className={control} type="date" required value={date} onChange={(event) => setDate(event.target.value)} /></label></VoiceTypingField>

        {isExpense && <label className={label}>{t("addaAccount.form.category")}<select className={control} value={categoryId} onChange={(event) => setCategoryId(event.target.value)} required><option value="">{t("addaAccount.filters.allCategories")}</option>{categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>}

        <VoiceTypingField fieldLabel={recognizedAmountLabel} mode="amount"><label className={label}>{recognizedAmountLabel}<input className={control} type="number" min="0.01" step="0.01" required value={amount} onChange={(event) => setAmount(event.target.value)} /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t(isExpense ? "addaAccount.form.paidAmount" : "addaAccount.form.receivedAmount")} mode="amount"><label className={label}>{t(isExpense ? "addaAccount.form.paidAmount" : "addaAccount.form.receivedAmount")}<input className={control} type="number" min="0" step="0.01" max={amountNumber || undefined} value={paidAmount} onChange={(event) => setPaidAmount(event.target.value)} /></label></VoiceTypingField>

        {paidNumber > 0 && <label className={label}>{t("addaAccount.form.paymentMethod")}<select className={control} required value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)}><option value="">{t("addaAccount.form.selectMethod")}</option>{methods.map((method) => <option value={method} key={method}>{method}</option>)}</select></label>}
        {isExpense && <label className={label}>{t("addaAccount.form.employee")}<select className={control} value={employeeId} onChange={(event) => setEmployeeId(event.target.value)}><option value="">{t("addaAccount.form.noEmployee")}</option>{employees.map((employee) => <option key={employee.id} value={employee.id}>{employee.employee_name}</option>)}</select></label>}

        <VoiceTypingField fieldLabel={t("addaAccount.form.reference")} mode="identifier"><label className={label}>{t("addaAccount.form.reference")}<input className={control} maxLength={120} value={referenceNo} onChange={(event) => setReferenceNo(event.target.value)} /></label></VoiceTypingField>

      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className={label}>{t("addaAccount.form.description")}<VoiceTypingField fieldLabel={t("addaAccount.form.description")} value={description} onValueChange={setDescription} contextKey={kind}><textarea className="min-h-20 w-full rounded-lg border border-slate-300 p-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" maxLength={500} value={description} onChange={(event) => setDescription(event.target.value)} /></VoiceTypingField></label>
        <label className={label}>{t("addaAccount.form.remarks")}<VoiceTypingField fieldLabel={t("addaAccount.form.remarks")} value={remarks} onValueChange={setRemarks} contextKey={kind}><textarea className="min-h-20 w-full rounded-lg border border-slate-300 p-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" maxLength={1000} value={remarks} onChange={(event) => setRemarks(event.target.value)} /></VoiceTypingField></label>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-100 bg-blue-50/70 p-3 text-sm">
        <p className="font-medium text-slate-700">{t("addaAccount.form.amountHint")}</p>
        <span className={`rounded-full px-3 py-1 font-bold ${statusText === t("addaAccount.form.paid") ? "bg-emerald-100 text-emerald-800" : statusText === t("addaAccount.form.partial") ? "bg-amber-100 text-amber-800" : "bg-slate-100 text-slate-700"}`}>{statusText}</span>
      </div>
      {amountNumber > 0 && <p className="text-sm font-semibold text-slate-600">{isExpense ? t("addaAccount.summary.pendingExpense") : t("addaAccount.summary.pendingIncome")}: {money(Math.max(0, amountNumber - paidNumber))}</p>}
      {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm font-semibold text-red-800">{error}</p>}
      <footer className="flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-4">
        <button type="button" disabled={saving} onClick={onClose} className={secondaryButton}>{t("addaAccount.form.cancel")}</button>
        <button type="submit" disabled={saving} className={primaryButton}>{saving ? t("addaAccount.form.saving") : t(isExpense ? "addaAccount.form.saveExpense" : "addaAccount.form.saveIncome")}</button>
      </footer>
    </form>
  </DialogShell>;
}

export function AddaAccountEntryMetadataDialog({ entry, onClose, onSubmit }: {
  entry: AddaAccountEntry;
  onClose: () => void;
  onSubmit: (value: MetadataFormValue) => Promise<boolean>;
}) {
  const { t, dir } = useLanguage();
  const [referenceNo, setReferenceNo] = useState(entry.reference_no ?? "");
  const [description, setDescription] = useState(entry.description ?? "");
  const [remarks, setRemarks] = useState(entry.remarks ?? "");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const requestRef = useRef("");
  const signatureRef = useRef("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    const reference = referenceNo.trim() || null;
    const detail = description.trim() || null;
    const note = remarks.trim() || null;
    const signature = JSON.stringify([entry.id, reference, detail, note]);
    if (!requestRef.current || signatureRef.current !== signature) requestRef.current = crypto.randomUUID();
    signatureRef.current = signature;
    setSaving(true);
    try {
      if (await onSubmit({ referenceNo: reference, description: detail, remarks: note, requestId: requestRef.current })) onClose();
    } catch {
      setError(t("addaAccount.messages.requestFailed"));
    } finally {
      setSaving(false);
    }
  }

  return <DialogShell title={t("addaAccount.metadata.title")} onClose={saving ? () => undefined : onClose}>
    <form dir={dir} onSubmit={(event) => void submit(event)} className="space-y-4">
      <p className="rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm font-medium text-blue-900">{t("addaAccount.metadata.notice")}</p>
      <div className="grid gap-4 sm:grid-cols-2">

        <VoiceTypingField fieldLabel={t("addaAccount.metadata.referenceNo")} mode="identifier"><label className={label}>{t("addaAccount.metadata.referenceNo")}<input className={control} maxLength={120} value={referenceNo} onChange={(event) => setReferenceNo(event.target.value)} /></label></VoiceTypingField>

        <label className={label}>{t("addaAccount.metadata.description")}<VoiceTypingField fieldLabel={t("addaAccount.metadata.description")} value={description} onValueChange={setDescription} contextKey={entry.id}><input className={control} maxLength={500} value={description} onChange={(event) => setDescription(event.target.value)} /></VoiceTypingField></label>
        <label className={`${label} sm:col-span-2`}>{t("addaAccount.metadata.remarks")}<VoiceTypingField fieldLabel={t("addaAccount.metadata.remarks")} value={remarks} onValueChange={setRemarks} contextKey={entry.id}><textarea className="min-h-24 w-full rounded-lg border border-slate-300 p-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" maxLength={1000} value={remarks} onChange={(event) => setRemarks(event.target.value)} /></VoiceTypingField></label>
      </div>
      {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm font-semibold text-red-800">{error}</p>}
      <footer className="flex justify-end gap-2 border-t border-slate-100 pt-4">
        <button type="button" disabled={saving} onClick={onClose} className={secondaryButton}>{t("addaAccount.form.cancel")}</button>
        <button type="submit" disabled={saving} className={primaryButton}>{saving ? t("addaAccount.form.saving") : t("addaAccount.metadata.save")}</button>
      </footer>
    </form>
  </DialogShell>;
}

export function AddaFinanceSettlementDialog({ entry, onClose, onSubmit }: {
  entry: AddaAccountEntry;
  onClose: () => void;
  onSubmit: (input: { date: string; amount: number; method: string; referenceNo: string | null; remarks: string | null; requestId: string }) => Promise<boolean>;
}) {
  const { t, dir } = useLanguage();
  const [date, setDate] = useState(localDate);
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState("");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const requestRef = useRef("");
  const signatureRef = useRef("");
  const amountNumber = Number(amount);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError("");
    if (!date || !Number.isFinite(amountNumber) || amountNumber <= 0 || amountNumber > entry.pending_amount || !method) {
      setError(amountNumber > entry.pending_amount ? t("addaAccount.messages.amountExceeds") : t("addaAccount.messages.required"));
      return;
    }
    const signature = JSON.stringify([entry.id, date, amountNumber, method, referenceNo, remarks]);
    if (!requestRef.current || signatureRef.current !== signature) requestRef.current = crypto.randomUUID();
    signatureRef.current = signature; setSaving(true);
    try {
      if (await onSubmit({ date, amount: amountNumber, method, referenceNo: referenceNo.trim() || null, remarks: remarks.trim() || null, requestId: requestRef.current })) onClose();
    } catch { setError(t("addaAccount.messages.requestFailed")); }
    finally { setSaving(false); }
  }
  return <DialogShell title={t("addaAccount.settlement.settlementTitle")} onClose={saving ? () => undefined : onClose}>
    <form dir={dir} onSubmit={(event) => void submit(event)} className="space-y-4">
      <div className="rounded-xl border border-blue-100 bg-blue-50 p-4 text-sm">
        <p className="font-bold text-slate-800">{t("addaAccount.settlement.original")}: {money(entry.amount)}</p>
        <p className="mt-1 text-slate-600">{t("addaAccount.settlement.pending")}: {money(entry.pending_amount)}</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">

        <VoiceTypingField fieldLabel={t("addaAccount.settlement.settlementDate")} mode="date"><label className={label}>{t("addaAccount.settlement.settlementDate")}<input className={control} type="date" required value={date} onChange={(event) => setDate(event.target.value)} /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("addaAccount.settlement.settlementAmount")} mode="amount"><label className={label}>{t("addaAccount.settlement.settlementAmount")}<input className={control} type="number" min="0.01" max={entry.pending_amount} step="0.01" required value={amount} onChange={(event) => setAmount(event.target.value)} /></label></VoiceTypingField>

        <label className={label}>{t("addaAccount.form.paymentMethod")}<select className={control} required value={method} onChange={(event) => setMethod(event.target.value)}><option value="">{t("addaAccount.form.selectMethod")}</option>{methods.map((item) => <option key={item} value={item}>{item}</option>)}</select></label>

        <VoiceTypingField fieldLabel={t("addaAccount.settlement.referenceNo")} mode="identifier"><label className={label}>{t("addaAccount.settlement.referenceNo")}<input className={control} maxLength={120} value={referenceNo} onChange={(event) => setReferenceNo(event.target.value)} /></label></VoiceTypingField>

      <label className={`${label} sm:col-span-2`}>{t("addaAccount.settlement.remarks")}<VoiceTypingField fieldLabel={t("addaAccount.settlement.remarks")} value={remarks} onValueChange={setRemarks} contextKey={entry.id}><textarea className="min-h-20 w-full rounded-lg border border-slate-300 p-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" maxLength={1000} value={remarks} onChange={(event) => setRemarks(event.target.value)} /></VoiceTypingField></label>
      </div>
      {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm font-semibold text-red-800">{error}</p>}
      <footer className="flex justify-end gap-2 border-t border-slate-100 pt-4"><button type="button" disabled={saving} onClick={onClose} className={secondaryButton}>{t("addaAccount.form.cancel")}</button><button type="submit" disabled={saving} className={primaryButton}>{saving ? t("addaAccount.form.saving") : t("addaAccount.settlement.save")}</button></footer>
    </form>
  </DialogShell>;
}

export function AddaFinanceHistoryDialog({ entry, settlements, loading, canManage, onClose, onSettle, onReverseSettlement, onReverseEntry }: {
  entry: AddaAccountEntry;
  settlements: AddaFinanceSettlement[];
  loading: boolean;
  canManage: boolean;
  onClose: () => void;
  onSettle: () => void;
  onReverseSettlement: (settlement: AddaFinanceSettlement) => void;
  onReverseEntry: () => void;
}) {
  const { t, dir } = useLanguage();
  const reversedSettlementIds = new Set(settlements.flatMap((item) => item.reverses_settlement_id ? [item.reverses_settlement_id] : []));
  const isBiltyMargin = entry.source_type === "bilty_margin";
  const sourceManaged = isBiltyMargin || entry.source_type === "bilty_loss" || entry.source_type === "employee_salary_generated" || entry.source_type === "issued_parchi_financing_commission";
  const canReverseEntry = !entry.is_reversal && !entry.is_reversed
    && entry.net_settled_amount === 0
    && ["manual_adda_expense", "manual_other_income"].includes(entry.source_type);
  const statusKey = entry.is_reversed ? "reversed" : entry.is_reversal ? "reversal" : isBiltyMargin
    ? entry.realization_status === "realized" ? "realized" : entry.realization_status === "partial" ? "partial" : "marginPending"
    : entry.entry_status === "settled" ? "paid" : entry.entry_status === "partial" ? "partial" : "unpaid";
  return <DialogShell title={t("addaAccount.settlement.title")} onClose={onClose} wide>
    <div dir={dir} className="space-y-5">
      {isBiltyMargin ? <div className="grid gap-3 rounded-xl border border-blue-100 bg-blue-50/60 p-4 sm:grid-cols-2 xl:grid-cols-4">
        <p><span className="block text-xs font-semibold text-slate-500">{t("addaAccount.print.earnedAmount")}</span><strong>{money(entry.earned_amount ?? entry.amount)}</strong></p>
        <p><span className="block text-xs font-semibold text-slate-500">{t("addaAccount.print.receivedBasisAmount")}</span><strong>{money(entry.received_basis_amount ?? 0)}</strong></p>
        <p><span className="block text-xs font-semibold text-emerald-700">{t("addaAccount.print.realizedAmount")}</span><strong>{money(entry.realized_amount ?? 0)}</strong></p>
        <p><span className="block text-xs font-semibold text-amber-700">{t("addaAccount.print.marginPendingAmount")}</span><strong>{money(entry.margin_pending_amount ?? entry.amount)}</strong></p>
      </div> : <div className="grid gap-3 rounded-xl border border-slate-200 bg-slate-50 p-4 sm:grid-cols-3">
        <p><span className="block text-xs font-semibold text-slate-500">{t("addaAccount.settlement.original")}</span><strong>{money(entry.amount)}</strong></p>
        <p><span className="block text-xs font-semibold text-slate-500">{t("addaAccount.ledger.settled")}</span><strong>{money(entry.net_settled_amount)}</strong></p>
        <p><span className="block text-xs font-semibold text-slate-500">{t("addaAccount.settlement.pending")}</span><strong>{money(entry.pending_amount)}</strong></p>
      </div>}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div><h3 className="font-extrabold text-slate-900">{entry.category_name ?? t(`addaAccount.ledger.${entry.entry_kind}`)}</h3><p className="mt-1 text-sm text-slate-600">{entry.description || "—"} {entry.reference_no ? `· ${entry.reference_no}` : ""}</p></div>
        <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-bold text-slate-700">{t(`addaAccount.status.${statusKey}`)}</span>
      </div>
      {sourceManaged ? <p role="note" className="rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm text-blue-900">{t(isBiltyMargin ? "addaAccount.print.marginReceiptNote" : "addaAccount.print.sourceManagedNote")}</p> : <section className="overflow-hidden rounded-xl border border-slate-200">
        <div className="overflow-x-auto"><table className="w-full min-w-[850px] text-sm">
          <thead className="bg-slate-100 text-start text-xs uppercase text-slate-600"><tr>{["date", "event", "amount", "method", "direction", "reference"].map((key) => <th key={key} className="px-3 py-2.5 text-start">{t(`addaAccount.settlement.${key}`)}</th>)}<th className="px-3 py-2.5 text-start">{t("addaAccount.ledger.action")}</th></tr></thead>
          <tbody>
            {loading && <tr><td colSpan={7} role="status" className="p-8 text-center text-slate-600">{t("common.loading")}</td></tr>}
            {!loading && settlements.length === 0 && <tr><td colSpan={7} className="p-8 text-center text-slate-500">{t("addaAccount.settlement.noRows")}</td></tr>}
            {!loading && settlements.map((item) => <tr key={item.id} className="border-t border-slate-100">
              <td className="whitespace-nowrap px-3 py-3">{item.payment_date}</td>
              <td className="px-3 py-3"><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${item.event_type === "settlement" ? "bg-emerald-50 text-emerald-800" : "bg-amber-50 text-amber-800"}`}>{t(`addaAccount.settlement.${item.event_type}`)}</span>{item.reversal_reason && <p className="mt-1 text-xs text-slate-500">{item.reversal_reason}</p>}</td>
              <td className="whitespace-nowrap px-3 py-3 font-bold">{money(item.amount)}</td>
              <td className="px-3 py-3">{item.payment_method ?? "—"}</td>
              <td className={`whitespace-nowrap px-3 py-3 font-bold ${item.cashbook_entry_type === "Cash In" ? "text-emerald-700" : "text-rose-700"}`}>{item.cashbook_entry_type ? t(item.cashbook_entry_type === "Cash In" ? "addaAccount.settlement.cashIn" : "addaAccount.settlement.cashOut") : "—"}</td>
              <td className="px-3 py-3">{item.reference_no ?? item.cashbook_reference_id ?? "—"}</td>
              <td className="px-3 py-3">{canManage && item.event_type === "settlement" && !reversedSettlementIds.has(item.id) && <button type="button" onClick={() => onReverseSettlement(item)} className="rounded-lg border border-rose-200 px-2.5 py-1.5 text-xs font-bold text-rose-700 hover:bg-rose-50">{t("addaAccount.settlement.reverse")}</button>}</td>
            </tr>)}
          </tbody>
        </table></div>
      </section>}
      {!sourceManaged && <p className="break-all text-xs text-slate-500">{t("addaAccount.settlement.cashbookRef")}: adda_finance_settlement / {settlements.map((item) => item.cashbook_reference_id).filter(Boolean).join(", ") || "—"}</p>}
      {canManage && <footer className="flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-4">
        {canManage && !sourceManaged && !entry.is_reversal && !entry.is_reversed && entry.pending_amount > 0 && <button type="button" onClick={onSettle} className={primaryButton}>{t("addaAccount.ledger.settle")}</button>}
        {canManage && canReverseEntry && <button type="button" onClick={onReverseEntry} className="inline-flex h-10 items-center rounded-lg border border-rose-200 px-4 text-sm font-bold text-rose-700 hover:bg-rose-50">{t("addaAccount.ledger.reverse")}</button>}
      </footer>}
    </div>
  </DialogShell>;
}

export function AddaFinanceActiveSettlementsDialog({ entry, onClose, onOpenHistory }: {
  entry: AddaAccountEntry;
  onClose: () => void;
  onOpenHistory: () => void;
}) {
  const { t, dir } = useLanguage();
  return <DialogShell title={t("addaAccount.settlement.activeEntryTitle")} onClose={onClose}>
    <div dir={dir} className="space-y-4">
      <p role="status" className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm font-semibold text-amber-900">
        {t("addaAccount.settlement.activeEntrySettlements")}
      </p>
      <p className="text-sm text-slate-700">
        {t("addaAccount.ledger.settled")}: <strong>{money(entry.net_settled_amount)}</strong>
      </p>
      <footer className="flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-4">
        <button type="button" onClick={onClose} className={secondaryButton}>{t("common.actions.cancel")}</button>
        <button type="button" onClick={onOpenHistory} className={primaryButton}>{t("addaAccount.settlement.openHistory")}</button>
      </footer>
    </div>
  </DialogShell>;
}

export function AddaFinanceReversalDialog({ target, submitError, onClose, onSubmit }: {
  target:
    | { kind: "entry"; addaId: string; accountEntryId: string; entry: AddaAccountEntry }
    | { kind: "settlement"; addaId: string; accountEntryId: string; settlementId: string; entry: AddaAccountEntry; settlement: AddaFinanceSettlement };
  submitError?: string;
  onClose: () => void;
  onSubmit: (input: { date: string; reason: string; requestId: string }) => Promise<boolean>;
}) {
  const { t, dir } = useLanguage();
  const [date, setDate] = useState(localDate);
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const requestRef = useRef("");
  const signatureRef = useRef("");
  const isEntry = target.kind === "entry";
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError("");
    if (!date || !reason.trim()) { setError(t("addaAccount.messages.required")); return; }
    const signature = JSON.stringify([
      target.kind,
      target.addaId,
      target.accountEntryId,
      isEntry ? null : target.settlementId,
      date,
      reason.trim(),
    ]);
    if (!requestRef.current || signatureRef.current !== signature) requestRef.current = crypto.randomUUID();
    signatureRef.current = signature; setSaving(true);
    try {
      if (await onSubmit({ date, reason: reason.trim(), requestId: requestRef.current })) onClose();
    } catch { setError(t("addaAccount.messages.requestFailed")); }
    finally { setSaving(false); }
  }
  return <DialogShell title={t(isEntry ? "addaAccount.settlement.reverseEntry" : "addaAccount.settlement.reverseSettlementTitle")} onClose={saving ? () => undefined : onClose}>
    <form dir={dir} onSubmit={(event) => void submit(event)} className="space-y-4">
      <p className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm font-medium text-amber-900">{t(isEntry ? "addaAccount.settlement.confirmEntry" : "addaAccount.settlement.confirmSettlement")}</p>

      <VoiceTypingField fieldLabel={t("addaAccount.settlement.reversalDate")} mode="date"><label className={label}>{t("addaAccount.settlement.reversalDate")}<input className={control} type="date" required value={date} onChange={(event) => setDate(event.target.value)} /></label></VoiceTypingField>

      <label className={label}>{t("addaAccount.settlement.reversalReason")}<VoiceTypingField fieldLabel={t("addaAccount.settlement.reversalReason")} value={reason} onValueChange={setReason} contextKey={`${target.kind}:${target.addaId}:${target.accountEntryId}`}><textarea className="min-h-24 w-full rounded-lg border border-slate-300 p-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100" maxLength={1000} required value={reason} onChange={(event) => setReason(event.target.value)} /></VoiceTypingField></label>
      {(error || submitError) && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm font-semibold text-red-800">{error || submitError}</p>}
      <footer className="flex justify-end gap-2 border-t border-slate-100 pt-4"><button type="button" disabled={saving} onClick={onClose} className={secondaryButton}>{t("common.actions.cancel")}</button><button type="submit" disabled={saving} className="inline-flex h-10 items-center rounded-lg bg-rose-600 px-4 text-sm font-bold text-white hover:bg-rose-700 disabled:opacity-60">{saving ? t("addaAccount.form.saving") : t(isEntry ? "addaAccount.ledger.reverse" : "addaAccount.settlement.reverse")}</button></footer>
    </form>
  </DialogShell>;
}

"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { supabase } from "@/lib/supabase/client";
import { formatAmount, type WorkshopEntryRow, type WorkshopOption } from "./Workshop";
import { getWorkTypeLabel } from "./workshopWorkTypes";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  workshops: WorkshopOption[];
  entries: WorkshopEntryRow[];
  onAccountingChanged: () => Promise<void>;
};

type PaymentRow = {
  id: number;
  workshopId: string;
  paymentDate: string;
  amount: number;
  advanceUsed: number;
  paymentNow: number;
  openingApplied: number;
  advanceCreated: number;
  availableAdvanceBefore: number;
  currentPayableBefore: number;
  remainingPayable: number;
  remainingAdvance: number;
  settlementStatus: string;
  paymentMethod: string;
  referenceNo: string;
  remarks: string;
  createdAt: string;
};

type PaymentDatabaseRow = {
  id: number;
  workshop_id: string;
  payment_date: string;
  amount: number | string | null;
  advance_used: number | string | null;
  payment_now: number | string | null;
  opening_applied: number | string | null;
  advance_created: number | string | null;
  available_advance_before: number | string | null;
  current_payable_before: number | string | null;
  remaining_payable: number | string | null;
  remaining_advance: number | string | null;
  settlement_status: string | null;
  payment_method: string | null;
  reference_no: string | null;
  remarks: string | null;
  created_at: string | null;
};

const paymentMethods = ["Cash", "Bank", "Cheque", "Online Transfer"] as const;

function numberValue(value: number | string | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function statusClass(status: string) {
  if (status === "Payable") return "border-red-200 bg-red-50 text-red-700";
  if (status === "Advance") return "border-green-200 bg-green-50 text-green-700";
  return "border-blue-200 bg-blue-50 text-blue-700";
}

export default function WorkshopAccount({ workshops, entries, onAccountingChanged }: Props) {
  const { t, dir, language } = useLanguage();
  const [selectedWorkshopId, setSelectedWorkshopId] = useState("");
  const [payments, setPayments] = useState<PaymentRow[]>([]);
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().slice(0, 10));
  const [advanceUsed, setAdvanceUsed] = useState("0");
  const [paymentNow, setPaymentNow] = useState("0");
  const [paymentMethod, setPaymentMethod] = useState<(typeof paymentMethods)[number]>("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const saveLock = useRef(false);
  const deleteLock = useRef(false);

  const loadPayments = useCallback(async () => {
    if (workshops.length === 0) {
      setPayments([]);
      return;
    }
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from("workshop_payments")
        .select("id,workshop_id,payment_date,amount,advance_used,payment_now,opening_applied,advance_created,available_advance_before,current_payable_before,remaining_payable,remaining_advance,settlement_status,payment_method,reference_no,remarks,created_at")
        .in("workshop_id", workshops.map((workshop) => workshop.id))
        .order("payment_date", { ascending: false })
        .order("created_at", { ascending: false });
      if (error) {
        console.error("Failed to load Workshop payments:", error);
        alert(t("workshop.account.messages.loadFailed"));
        return;
      }
      setPayments(((data ?? []) as PaymentDatabaseRow[]).map((row) => ({
        id: row.id,
        workshopId: row.workshop_id,
        paymentDate: row.payment_date,
        amount: numberValue(row.amount),
        advanceUsed: numberValue(row.advance_used),
        paymentNow: numberValue(row.payment_now),
        openingApplied: numberValue(row.opening_applied),
        advanceCreated: numberValue(row.advance_created),
        availableAdvanceBefore: numberValue(row.available_advance_before),
        currentPayableBefore: numberValue(row.current_payable_before),
        remainingPayable: numberValue(row.remaining_payable),
        remainingAdvance: numberValue(row.remaining_advance),
        settlementStatus: row.settlement_status || "Paid",
        paymentMethod: row.payment_method || "Cash",
        referenceNo: row.reference_no || "",
        remarks: row.remarks || "",
        createdAt: row.created_at || "",
      })));
    } finally {
      setIsLoading(false);
    }
  }, [t, workshops]);

  useEffect(() => {
    const timeoutId = window.setTimeout(() => { void loadPayments(); }, 0);
    return () => window.clearTimeout(timeoutId);
  }, [loadPayments]);

  const selectedWorkshop = workshops.find((workshop) => workshop.id === selectedWorkshopId) ?? null;
  const modulePrint = useModuleTransportPrint("workshop", selectedWorkshop?.addaId, language);
  const selectedEntries = useMemo(() => entries.filter((entry) => entry.workshopId === selectedWorkshopId), [entries, selectedWorkshopId]);
  const selectedPayments = useMemo(() => payments.filter((payment) => payment.workshopId === selectedWorkshopId), [payments, selectedWorkshopId]);
  const latestPayment = selectedPayments[0] ?? null;
  const editingPayment = editingId === null ? null : selectedPayments.find((payment) => payment.id === editingId) ?? null;
  const totalBills = selectedEntries.reduce((total, entry) => total + entry.totalCost, 0);
  const totalPaidAllocation = selectedEntries.reduce((total, entry) => total + entry.paidAmount, 0);
  const manualPayments = selectedPayments.reduce((total, payment) => total + payment.paymentNow, 0);
  const openingBalance = selectedWorkshop?.openingBalance ?? 0;
  const currentPayable = latestPayment ? latestPayment.remainingPayable : Math.max(openingBalance, 0) + selectedEntries.reduce((total, entry) => total + entry.remainingAmount, 0);
  const availableAdvance = latestPayment ? latestPayment.remainingAdvance : Math.max(-openingBalance, 0);
  const accountStatus = currentPayable > 0 ? "Payable" : availableAdvance > 0 ? "Advance" : "Paid";
  const previewPayableBefore = editingPayment?.currentPayableBefore ?? currentPayable;
  const previewAdvanceBefore = editingPayment?.availableAdvanceBefore ?? availableAdvance;
  const advanceNumber = numberValue(advanceUsed);
  const paymentNumber = numberValue(paymentNow);
  const totalSettlement = advanceNumber + paymentNumber;
  const remainingPayable = Math.max(previewPayableBefore - totalSettlement, 0);
  const remainingExistingAdvance = Math.max(previewAdvanceBefore - advanceNumber, 0);
  const newAdvance = Math.max(totalSettlement - previewPayableBefore, 0);
  const remainingAdvance = remainingExistingAdvance + newAdvance;
  const previewStatus = remainingPayable > 0 ? "Payable" : remainingAdvance > 0 ? "Advance" : "Paid";

  function resetPayment() {
    setEditingId(null);
    setPaymentDate(new Date().toISOString().slice(0, 10));
    setAdvanceUsed("0");
    setPaymentNow("0");
    setPaymentMethod("Cash");
    setReferenceNo("");
    setRemarks("");
  }

  function chooseWorkshop(value: string) {
    setSelectedWorkshopId(value);
    resetPayment();
    if (!value) return;
    const workshop = workshops.find((item) => item.id === value);
    const workshopEntries = entries.filter((entry) => entry.workshopId === value);
    const workshopPayments = payments.filter((payment) => payment.workshopId === value);
    const newest = workshopPayments[0];
    const payable = newest ? newest.remainingPayable : Math.max(workshop?.openingBalance ?? 0, 0) + workshopEntries.reduce((sum, entry) => sum + entry.remainingAmount, 0);
    const advance = newest ? newest.remainingAdvance : Math.max(-(workshop?.openingBalance ?? 0), 0);
    setAdvanceUsed(String(Math.min(advance, payable)));
  }

  function editPayment(row: PaymentRow) {
    setSelectedWorkshopId(row.workshopId);
    setEditingId(row.id);
    setPaymentDate(row.paymentDate);
    setAdvanceUsed(String(row.advanceUsed));
    setPaymentNow(String(row.paymentNow));
    setPaymentMethod(paymentMethods.includes(row.paymentMethod as (typeof paymentMethods)[number]) ? row.paymentMethod as (typeof paymentMethods)[number] : "Cash");
    setReferenceNo(row.referenceNo);
    setRemarks(row.remarks);
  }

  async function savePayment() {
    if (saveLock.current) return;
    if (!selectedWorkshopId) return alert(t("workshop.account.validation.workshopRequired"));
    if (!paymentDate) return alert(t("workshop.account.validation.dateRequired"));
    if (advanceNumber < 0 || paymentNumber < 0) return alert(t("workshop.account.validation.nonNegative"));
    if (totalSettlement <= 0) return alert(t("workshop.account.validation.settlementRequired"));
    if (advanceNumber > previewAdvanceBefore) return alert(t("workshop.account.validation.advanceExceedsAvailable"));
    if (advanceNumber > previewPayableBefore) return alert(t("workshop.account.validation.advanceExceedsPayable"));
    saveLock.current = true;
    setIsSaving(true);
    try {
      const { error } = await supabase.rpc("save_workshop_payment", {
        p_payment_id: editingId,
        p_workshop_id: selectedWorkshopId,
        p_payment_date: paymentDate,
        p_advance_used: advanceNumber,
        p_payment_now: paymentNumber,
        p_payment_method: paymentMethod,
        p_reference_no: referenceNo.trim() || null,
        p_remarks: remarks.trim() || null,
      });
      if (error) {
        console.error("Failed to save Workshop payment:", error);
        alert(t("workshop.account.messages.saveFailed"));
        return;
      }
      alert(t(editingId ? "workshop.account.messages.updated" : "workshop.account.messages.saved"));
      resetPayment();
      await Promise.all([loadPayments(), onAccountingChanged()]);
    } finally {
      saveLock.current = false;
      setIsSaving(false);
    }
  }

  async function deletePayment(row: PaymentRow) {
    if (deleteLock.current || !window.confirm(t("workshop.account.messages.deleteConfirm"))) return;
    deleteLock.current = true;
    setDeletingId(row.id);
    try {
      const { error } = await supabase.rpc("delete_workshop_payment", { p_payment_id: row.id });
      if (error) {
        console.error("Failed to delete Workshop payment:", error);
        alert(t("workshop.account.messages.deleteFailed"));
        return;
      }
      alert(t("workshop.account.messages.deleted"));
      if (editingId === row.id) resetPayment();
      await Promise.all([loadPayments(), onAccountingChanged()]);
    } finally {
      deleteLock.current = false;
      setDeletingId(null);
    }
  }

  function openPrintLegacy(title: string, body: string, ownerAddaId: string | null) {
    const printWindow = window.open("", "_blank", "width=1100,height=800");
    if (!printWindow) return alert(t("workshop.messages.allowPopups"));
    void writeAddaBrandedPrintDocument(printWindow, "<!doctype html><html lang='" + escapeHtml(language) + "' dir='" + escapeHtml(dir) + "'><head><title>" + escapeHtml(title) + "</title><style>@page{size:A4;margin:12mm}*{box-sizing:border-box}body{font-family:Arial;color:#111827}h1,h2{margin:0 0 12px}.head{border-bottom:2px solid #111827;margin-bottom:18px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px 20px}.box{border:1px solid #cbd5e1;padding:12px;margin-top:16px}table{width:100%;border-collapse:collapse;margin-top:12px;font-size:12px}th,td{border:1px solid #cbd5e1;padding:6px;text-align:start}th{background:#2563eb;color:white}.signatures{display:grid;grid-template-columns:repeat(3,1fr);gap:35px;margin-top:55px}.signature{border-top:1px solid #111827;text-align:center;padding-top:7px}</style></head><body>" + body + "<script>window.onload=function(){window.focus();window.print();}</script></body></html>", ownerAddaId, language === "ur" ? "ur" : "en");
  }

  function openPrint(title: string, body: string, ownerAddaId: string | null) {
    modulePrint.open(title, body, () => openPrintLegacy(title, body, ownerAddaId));
  }

  function printReceipt(row: PaymentRow) {
    const workshop = workshops.find((item) => item.id === row.workshopId);
    const value = (label: string, text: string) => "<div><strong>" + escapeHtml(label) + ":</strong> <span dir='ltr'>" + escapeHtml(text || "-") + "</span></div>";
    openPrint(t("workshop.account.print.receiptTitle"), "<div class='head'><h1>" + PRINT_ADDA_NAME_TOKEN + "</h1><h2>" + escapeHtml(t("workshop.account.print.receiptTitle")) + "</h2></div><div class='grid'>" + value(t("workshop.master.fields.name"), workshop?.workshopName || "-") + value(t("workshop.master.fields.owner"), workshop?.ownerName || "-") + value(t("workshop.master.fields.phone"), workshop?.phone || "-") + value(t("workshop.account.form.paymentDate"), row.paymentDate) + value(t("workshop.account.form.paymentMethod"), row.paymentMethod) + value(t("workshop.account.form.referenceNo"), row.referenceNo) + value(t("workshop.account.form.advanceUsed"), formatAmount(row.advanceUsed)) + value(t("workshop.account.form.paymentNow"), formatAmount(row.paymentNow)) + value(t("workshop.account.form.totalSettlement"), formatAmount(row.amount)) + value(t("workshop.account.form.currentPayableBefore"), formatAmount(row.currentPayableBefore)) + value(t("workshop.account.form.availableAdvanceBefore"), formatAmount(row.availableAdvanceBefore)) + value(t("workshop.account.form.remainingPayable"), formatAmount(row.remainingPayable)) + value(t("workshop.account.form.remainingAdvance"), formatAmount(row.remainingAdvance)) + value(t("workshop.account.cards.status"), t("workshop.account.statuses." + row.settlementStatus.toLowerCase())) + value(t("workshop.account.form.remarks"), row.remarks) + "</div><div class='signatures'><div class='signature'>" + escapeHtml(t("workshop.account.print.preparedBy")) + "</div><div class='signature'>" + escapeHtml(t("workshop.account.print.approvedBy")) + "</div><div class='signature'>" + escapeHtml(t("workshop.account.print.receivedBy")) + "</div></div>", workshop?.addaId ?? null);
  }

  function printLedger() {
    if (!selectedWorkshop) return alert(t("workshop.account.validation.workshopRequired"));
    const inRange = (date: string) => (!fromDate || date >= fromDate) && (!toDate || date <= toDate);
    const bills = selectedEntries.filter((entry) => inRange(entry.workDate));
    const ledgerPayments = selectedPayments.filter((payment) => inRange(payment.paymentDate));
    const billRows = bills.map((entry) => "<tr><td dir='ltr'>" + escapeHtml(entry.workDate) + "</td><td>" + escapeHtml(entry.vehicleNo) + "</td><td>" + escapeHtml(entry.billNo || "-") + "</td><td>" + escapeHtml(entry.workItems.length ? entry.workItems.map((item)=>getWorkTypeLabel(item.workType,t)).join(", ") : entry.workType) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(entry.totalCost)) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(entry.paidAmount)) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(entry.remainingAmount)) + "</td><td>" + escapeHtml(t(entry.voucherId ? "expenses.workshopLink.attached" : "expenses.workshopLink.notAttached")) + (entry.voucherId ? "<br><span dir='ltr'>" + escapeHtml(entry.voucherNo || entry.voucherId) + " · " + escapeHtml(entry.voucherDate || "-") + "</span>" : "") + "</td></tr>").join("");
    const paymentRows = ledgerPayments.map((row) => "<tr><td dir='ltr'>" + escapeHtml(row.paymentDate) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(row.advanceUsed)) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(row.paymentNow)) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(row.amount)) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(row.remainingPayable)) + "</td><td dir='ltr'>" + escapeHtml(formatAmount(row.remainingAdvance)) + "</td><td>" + escapeHtml(t("workshop.account.statuses." + row.settlementStatus.toLowerCase())) + "</td></tr>").join("");
    openPrint(t("workshop.account.print.ledgerTitle"), "<div class='head'><h1>" + PRINT_ADDA_NAME_TOKEN + "</h1><h2>" + escapeHtml(t("workshop.account.print.ledgerTitle")) + "</h2><p>" + escapeHtml(selectedWorkshop.workshopName) + " — " + escapeHtml(fromDate || t("workshop.filters.allDates")) + " " + escapeHtml(t("workshop.print.to")) + " " + escapeHtml(toDate || t("workshop.filters.allDates")) + "</p></div><h2>" + escapeHtml(t("workshop.account.bills.title")) + "</h2><table><thead><tr><th>" + escapeHtml(t("workshop.table.date")) + "</th><th>" + escapeHtml(t("workshop.table.vehicle")) + "</th><th>" + escapeHtml(t("workshop.table.billNo")) + "</th><th>" + escapeHtml(t("workshop.table.workType")) + "</th><th>" + escapeHtml(t("workshop.table.totalCost")) + "</th><th>" + escapeHtml(t("workshop.table.paid")) + "</th><th>" + escapeHtml(t("workshop.table.remaining")) + "</th><th>" + escapeHtml(t("expenses.workshopLink.voucherStatus")) + "</th></tr></thead><tbody>" + billRows + "</tbody></table><h2 style='margin-top:22px'>" + escapeHtml(t("workshop.account.payments.title")) + "</h2><table><thead><tr><th>" + escapeHtml(t("workshop.account.form.paymentDate")) + "</th><th>" + escapeHtml(t("workshop.account.form.advanceUsed")) + "</th><th>" + escapeHtml(t("workshop.account.form.paymentNow")) + "</th><th>" + escapeHtml(t("workshop.account.form.totalSettlement")) + "</th><th>" + escapeHtml(t("workshop.account.form.remainingPayable")) + "</th><th>" + escapeHtml(t("workshop.account.form.remainingAdvance")) + "</th><th>" + escapeHtml(t("workshop.account.cards.status")) + "</th></tr></thead><tbody>" + paymentRows + "</tbody></table><div class='box'><h2>" + escapeHtml(t("workshop.account.print.finalSummary")) + "</h2><div class='grid'><div>" + escapeHtml(t("workshop.account.cards.openingBalance")) + ": <b dir='ltr'>" + escapeHtml(formatAmount(openingBalance)) + "</b></div><div>" + escapeHtml(t("workshop.account.cards.totalBills")) + ": <b dir='ltr'>" + escapeHtml(formatAmount(totalBills)) + "</b></div><div>" + escapeHtml(t("workshop.account.cards.currentPayable")) + ": <b dir='ltr'>" + escapeHtml(formatAmount(currentPayable)) + "</b></div><div>" + escapeHtml(t("workshop.account.cards.availableAdvance")) + ": <b dir='ltr'>" + escapeHtml(formatAmount(availableAdvance)) + "</b></div></div></div>", selectedWorkshop.addaId);
  }

  const summaryCards = [
    ["openingBalance", openingBalance], ["totalBills", totalBills], ["totalPaidAllocation", totalPaidAllocation],
    ["manualPayments", manualPayments], ["currentPayable", currentPayable], ["availableAdvance", availableAdvance],
  ] as const;

  return <section dir={dir} className="space-y-6">
    <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm"><h2 className="text-2xl font-black text-gray-900">{t("workshop.account.title")}</h2><p className="mt-1 font-semibold text-gray-700">{t("workshop.account.description")}</p><label className="mt-5 block max-w-xl text-sm font-bold text-gray-900"><span className="mb-2 block">{t("workshop.account.selectWorkshop")}</span><select value={selectedWorkshopId} onChange={(event) => chooseWorkshop(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-gray-900"><option value="">{t("workshop.placeholders.selectWorkshop")}</option>{workshops.map((workshop) => <option key={workshop.id} value={workshop.id}>{workshop.workshopName}</option>)}</select></label></div>

    {selectedWorkshop && <>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">{summaryCards.map(([key, value]) => <div key={key} className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"><div className="font-bold text-gray-700">{t("workshop.account.cards." + key)}</div><div dir="ltr" className="mt-2 text-2xl font-black text-gray-900">{formatAmount(value)}</div></div>)}<div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"><div className="font-bold text-gray-700">{t("workshop.account.cards.status")}</div><div className={"mt-2 inline-flex rounded-full border px-3 py-1 font-black " + statusClass(accountStatus)}>{t("workshop.account.statuses." + accountStatus.toLowerCase())}</div></div></div>

      <div className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm"><h3 className="text-xl font-black text-gray-900">{t(editingId ? "workshop.account.form.editTitle" : "workshop.account.form.title")}</h3><div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">

        <VoiceTypingField fieldLabel={t("workshop.account.form.paymentDate")} mode="date"><label className="font-bold text-gray-900"><span className="mb-2 block">{t("workshop.account.form.paymentDate")}</span><input type="date" value={paymentDate} onChange={(event) => setPaymentDate(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("workshop.account.form.advanceUsed")} mode="amount"><label className="font-bold text-gray-900"><span className="mb-2 block">{t("workshop.account.form.advanceUsed")}</span><input type="number" min="0" dir="ltr" value={advanceUsed} onChange={(event) => setAdvanceUsed(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /><small className="text-gray-700">{t("workshop.account.form.availableAdvanceBefore")}: {formatAmount(previewAdvanceBefore)}</small></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("workshop.account.form.paymentNow")} mode="cnic"><label className="font-bold text-gray-900"><span className="mb-2 block">{t("workshop.account.form.paymentNow")}</span><input type="number" min="0" dir="ltr" value={paymentNow} onChange={(event) => setPaymentNow(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /><small className="text-gray-700">{t("workshop.account.form.currentPayableBefore")}: {formatAmount(previewPayableBefore)}</small></label></VoiceTypingField>

        <label className="font-bold text-gray-900"><span className="mb-2 block">{t("workshop.account.form.paymentMethod")}</span><select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value as (typeof paymentMethods)[number])} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3">{paymentMethods.map((method) => <option key={method} value={method}>{t("workshop.account.methods." + (method === "Online Transfer" ? "onlineTransfer" : method.toLowerCase()))}</option>)}</select></label>

        <VoiceTypingField fieldLabel={t("workshop.account.form.referenceNo")} mode="identifier"><label className="font-bold text-gray-900"><span className="mb-2 block">{t("workshop.account.form.referenceNo")}</span><input dir="ltr" value={referenceNo} onChange={(event) => setReferenceNo(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("workshop.account.form.remarks")} mode="text"><label className="font-bold text-gray-900 md:col-span-2 xl:col-span-3"><span className="mb-2 block">{t("workshop.account.form.remarks")}</span><input value={remarks} onChange={(event) => setRemarks(event.target.value)} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></label></VoiceTypingField>

      </div><div className="mt-5 grid grid-cols-2 gap-3 rounded-xl border border-blue-200 bg-blue-50 p-4 md:grid-cols-4"><div><b>{t("workshop.account.form.totalSettlement")}</b><div dir="ltr">{formatAmount(totalSettlement)}</div></div><div><b>{t("workshop.account.form.remainingPayable")}</b><div dir="ltr">{formatAmount(remainingPayable)}</div></div><div><b>{t("workshop.account.form.remainingAdvance")}</b><div dir="ltr">{formatAmount(remainingAdvance)}</div></div><div><b>{t("workshop.account.cards.status")}</b><div className="font-black">{t("workshop.account.statuses." + previewStatus.toLowerCase())}</div></div></div><div className="mt-4 flex flex-wrap gap-2"><button type="button" disabled={isSaving} onClick={() => void savePayment()} className="rounded-lg bg-blue-600 px-6 py-3 font-bold text-white disabled:cursor-not-allowed">{isSaving ? t("common.states.saving") : t(editingId ? "workshop.account.actions.update" : "workshop.account.actions.save")}</button>{editingId && <button type="button" onClick={resetPayment} className="rounded-lg border border-gray-300 bg-white px-6 py-3 font-bold text-gray-900">{t("workshop.account.actions.cancel")}</button>}</div></div>

      <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"><div className="flex flex-wrap items-end justify-between gap-3"><div><h3 className="text-xl font-black">{t("workshop.account.bills.title")}</h3><div className="mt-3 flex flex-wrap gap-3">
      <VoiceTypingField fieldLabel={t("workshop.filters.fromDate")} mode="date"><label className="font-bold">{t("workshop.filters.fromDate")}<input type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)} className="ms-2 rounded border border-gray-300 p-2" /></label></VoiceTypingField>

      <VoiceTypingField fieldLabel={t("workshop.filters.toDate")} mode="date"><label className="font-bold">{t("workshop.filters.toDate")}<input type="date" value={toDate} onChange={(event) => setToDate(event.target.value)} className="ms-2 rounded border border-gray-300 p-2" /></label></VoiceTypingField>
      </div></div><button type="button" onClick={printLedger} className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white">{t("workshop.account.actions.printLedger")}</button></div><div className="mt-4 overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-blue-600 text-white"><tr>{["date","vehicle","billNo","workType","partsCost","labourCost","totalCost","paid","remaining","status"].map((key) => <th key={key} className="p-3 text-start">{t("workshop.table." + key)}</th>)}<th className="p-3 text-start">{t("expenses.workshopLink.voucherStatus")}</th></tr></thead><tbody>{selectedEntries.length === 0 ? <tr><td colSpan={11} className="p-6 text-center font-semibold text-gray-700">{t("workshop.account.bills.empty")}</td></tr> : selectedEntries.map((entry) => <tr key={entry.id} className="border-b"><td dir="ltr" className="p-3">{entry.workDate}</td><td className="p-3">{entry.vehicleNo}</td><td className="p-3">{entry.billNo || "-"}</td><td className="p-3">{entry.workType}</td><td dir="ltr" className="p-3">{formatAmount(entry.partsCost)}</td><td dir="ltr" className="p-3">{formatAmount(entry.labourCost)}</td><td dir="ltr" className="p-3">{formatAmount(entry.totalCost)}</td><td dir="ltr" className="p-3">{formatAmount(entry.paidAmount)}</td><td dir="ltr" className="p-3">{formatAmount(entry.remainingAmount)}</td><td className="p-3">{t("workshop.statuses." + entry.paymentStatus.toLowerCase())}</td><td className="p-3"><span className={entry.voucherId ? "font-black text-blue-800" : "font-bold text-gray-700"}>{t(entry.voucherId ? "expenses.workshopLink.attached" : "expenses.workshopLink.notAttached")}</span>{entry.voucherId && <span dir="ltr" className="mt-1 block text-xs font-semibold text-gray-800">{entry.voucherNo || entry.voucherId} · {entry.voucherDate || "-"}</span>}</td></tr>)}</tbody></table></div></div>

      <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"><h3 className="text-xl font-black">{t("workshop.account.payments.title")}</h3>{isLoading ? <p className="py-6 font-semibold">{t("workshop.account.loading")}</p> : <div className="mt-4 overflow-x-auto"><table className="min-w-[1500px] text-sm"><thead className="bg-blue-600 text-white"><tr>{["paymentDate","advanceUsed","paymentNow","totalSettlement","payableBefore","advanceBefore","remainingPayable","remainingAdvance","status","paymentMethod","referenceNo","remarks","actions"].map((key) => <th key={key} className="p-3 text-start">{t("workshop.account.table." + key)}</th>)}</tr></thead><tbody>{selectedPayments.length === 0 ? <tr><td colSpan={13} className="p-6 text-center font-semibold text-gray-700">{t("workshop.account.payments.empty")}</td></tr> : selectedPayments.map((row) => <tr key={row.id} className="border-b"><td dir="ltr" className="p-3">{row.paymentDate}</td><td dir="ltr" className="p-3">{formatAmount(row.advanceUsed)}</td><td dir="ltr" className="p-3">{formatAmount(row.paymentNow)}</td><td dir="ltr" className="p-3">{formatAmount(row.amount)}</td><td dir="ltr" className="p-3">{formatAmount(row.currentPayableBefore)}</td><td dir="ltr" className="p-3">{formatAmount(row.availableAdvanceBefore)}</td><td dir="ltr" className="p-3">{formatAmount(row.remainingPayable)}</td><td dir="ltr" className="p-3">{formatAmount(row.remainingAdvance)}</td><td className="p-3">{t("workshop.account.statuses." + row.settlementStatus.toLowerCase())}</td><td className="p-3">{t("workshop.account.methods." + (row.paymentMethod === "Online Transfer" ? "onlineTransfer" : row.paymentMethod.toLowerCase()))}</td><td className="p-3">{row.referenceNo || "-"}</td><td className="p-3">{row.remarks || "-"}</td><td className="p-3"><div className="flex gap-2"><button type="button" aria-label={t("workshop.account.actions.edit") + " " + row.paymentDate} onClick={() => editPayment(row)} className="rounded bg-blue-600 px-3 py-2 font-bold text-white">{t("workshop.account.actions.edit")}</button><button type="button" aria-label={t("workshop.account.actions.printReceipt") + " " + row.paymentDate} onClick={() => printReceipt(row)} className="rounded bg-slate-700 px-3 py-2 font-bold text-white">{t("workshop.account.actions.printReceipt")}</button><button type="button" aria-label={t("workshop.account.actions.delete") + " " + row.paymentDate} disabled={deletingId === row.id} onClick={() => void deletePayment(row)} className="rounded bg-red-600 px-3 py-2 font-bold text-white disabled:cursor-not-allowed">{t("workshop.account.actions.delete")}</button></div></td></tr>)}</tbody></table></div>}</div>
    </>}
    {modulePrint.dialog}
  </section>;
}

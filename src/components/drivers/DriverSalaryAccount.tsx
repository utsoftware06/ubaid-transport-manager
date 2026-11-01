"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { supabase } from "@/lib/supabase/client";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { printLabel, printValue, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Translate = (key: string) => string;
type Driver = { id: string; adda_id: string; name: string; opening_balance?: number | string | null };
type Vehicle = { id: string; vehicle_no: string };
type Assignment = { id: string; driver_id: string; vehicle_id: string; start_date: string; end_date: string | null };

type Earning = {
  id: string; driver_id: string; vehicle_id: string; driver_vehicle_assignment_id: string;
  salary_date: string; salary_month: string; period_start: string | null; period_end: string | null; earning_type: string;
  basic_salary: number | string; trip_pay: number | string; bonus_allowance: number | string;
  other_earnings: number | string; deduction_fine: number | string; gross_expense: number | string;
  advance_adjusted: number | string; net_payable: number | string; paid_amount: number | string;
  remaining_amount: number | string; payment_status: string; remarks: string | null; created_at: string;
};
type Payment = {
  id: number; driver_id: string; payment_date: string; amount: number | string; advance_used: number | string;
  payment_now: number | string; remaining_payable: number | string; remaining_advance: number | string;
  available_advance_before: number | string; current_payable_before: number | string; settlement_status: string;
  payment_method: string | null; reference_no: string | null; remarks: string | null; created_at: string;
};
type Allocation = { id: string; payment_id: number; driver_earning_id: string; amount: number | string };
type VoucherLink = { driver_earning_id: string; voucher_id: number };
type Voucher = { id: number; expense_no: string | null; expense_date: string | null };
type LedgerRow = { key: string; date: string; type: "earning" | "payment"; earning: number; payment: number; adjustment: number; vehicle: string; description: string; effect: number; status: string; running: number };

const fieldClass = "w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 font-semibold text-slate-900 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100 disabled:bg-slate-100";
const Card = ({ children }: { children: React.ReactNode }) => <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">{children}</section>;
const today = () => new Date().toISOString().slice(0, 10);
const monthNow = () => today().slice(0, 7);
const numberValue = (value: number | string | null | undefined) => { const parsed = Number(value ?? 0); return Number.isFinite(parsed) ? parsed : 0; };
const money = (value: number) => `Rs. ${value.toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
const statusLabel = (status: string, t: Translate) => t(`drivers.account.statuses.${status}`);

function rpcMessage(error: { code?: string | null; message?: string | null }, t: Translate) {
  const message = (error.message ?? "").toLowerCase();
  if (message.includes("exactly one driver assignment")) return t("drivers.account.errors.assignmentMissing");
  if (message.includes("deduction cannot exceed")) return t("drivers.account.errors.deductionTooHigh");
  if (message.includes("another adda") || message.includes("unauthorized")) return t("drivers.account.errors.permission");
  if (message.includes("not found") || error.code === "P0002") return t("drivers.account.errors.notFound");
  if (message.includes("settlement") || message.includes("finite positive")) return t("drivers.account.errors.invalidPayment");
  return t("drivers.account.errors.saveFailed");
}

export default function DriverSalaryAccount({ drivers, vehicles, assignments, t, dir, language }: {
  drivers: Driver[]; vehicles: Vehicle[]; assignments: Assignment[]; t: Translate; dir: string; language: string;
}) {
  const [driverId, setDriverId] = useState("");
  const [earnings, setEarnings] = useState<Earning[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [allocations, setAllocations] = useState<Allocation[]>([]);
  const [links, setLinks] = useState<VoucherLink[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const modulePrint = useModuleTransportPrint("driver_ledger", drivers.find((driver) => driver.id === driverId)?.adda_id ?? null, language === "ur" ? "ur" : "en");
  const [salaryDate, setSalaryDate] = useState(today());
  const [salaryMonth, setSalaryMonth] = useState(monthNow());
  const [periodStart, setPeriodStart] = useState("");
  const [periodEnd, setPeriodEnd] = useState("");
  const [earningType, setEarningType] = useState("monthly_salary");
  const [basicSalary, setBasicSalary] = useState("");
  const [tripPay, setTripPay] = useState("");
  const [bonus, setBonus] = useState("");
  const [otherEarnings, setOtherEarnings] = useState("");
  const [deduction, setDeduction] = useState("");
  const [earningAdvance, setEarningAdvance] = useState("");
  const [earningRemarks, setEarningRemarks] = useState("");
  const [paymentId, setPaymentId] = useState<number | null>(null);
  const [paymentDate, setPaymentDate] = useState(today());
  const [advanceUsed, setAdvanceUsed] = useState("");
  const [paymentNow, setPaymentNow] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [paymentRemarks, setPaymentRemarks] = useState("");

  const load = useCallback(async () => {
    setLoading(true); setError("");
    const [earningResult, paymentResult, allocationResult, linkResult] = await Promise.all([
      supabase.from("driver_earnings").select("id,driver_id,vehicle_id,driver_vehicle_assignment_id,salary_date,salary_month,period_start,period_end,earning_type,basic_salary,trip_pay,bonus_allowance,other_earnings,deduction_fine,gross_expense,advance_adjusted,net_payable,paid_amount,remaining_amount,payment_status,remarks,created_at").order("salary_date", { ascending: false }),
      supabase.from("driver_payments").select("id,driver_id,payment_date,amount,advance_used,payment_now,available_advance_before,current_payable_before,remaining_payable,remaining_advance,settlement_status,payment_method,reference_no,remarks,created_at").order("payment_date", { ascending: false }).order("id", { ascending: false }),
      supabase.from("driver_payment_allocations").select("id,payment_id,driver_earning_id,amount"),
      supabase.from("voucher_driver_earnings").select("driver_earning_id,voucher_id"),
    ]);
    const queryError = earningResult.error ?? paymentResult.error ?? allocationResult.error ?? linkResult.error;
    if (queryError) {
      console.error("Driver account load failed", { code: queryError.code, message: queryError.message, details: queryError.details, hint: queryError.hint });
      setError(t("drivers.account.errors.loadFailed")); setLoading(false); return;
    }
    const linkRows = (linkResult.data ?? []) as VoucherLink[];
    const voucherIds = [...new Set(linkRows.map((row) => row.voucher_id))];
    const voucherResult = voucherIds.length
      ? await supabase.from("expenses").select("id,expense_no,expense_date").in("id", voucherIds)
      : { data: [] as Voucher[], error: null };
    if (voucherResult.error) {
      console.error("Driver Voucher metadata load failed", voucherResult.error);
      setError(t("drivers.account.errors.loadFailed")); setLoading(false); return;
    }
    setEarnings((earningResult.data ?? []) as Earning[]);
    setPayments((paymentResult.data ?? []) as Payment[]);
    setAllocations((allocationResult.data ?? []) as Allocation[]);
    setLinks(linkRows); setVouchers((voucherResult.data ?? []) as Voucher[]); setLoading(false);
  }, [t]);

  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer); }, [load]);
  useEffect(() => { const timer = window.setTimeout(() => { if (!driverId && drivers[0]?.id) setDriverId(drivers[0].id); }, 0); return () => window.clearTimeout(timer); }, [driverId, drivers]);

  const selectedDriver = drivers.find((driver) => driver.id === driverId) ?? null;
  const vehicleMap = useMemo(() => new Map(vehicles.map((vehicle) => [vehicle.id, vehicle.vehicle_no])), [vehicles]);
  const currentAssignment = assignments.find((assignment) => assignment.driver_id === driverId && assignment.end_date === null) ?? null;
  const datedAssignments = assignments.filter((assignment) => assignment.driver_id === driverId && assignment.start_date <= salaryDate && (!assignment.end_date || assignment.end_date >= salaryDate));
  const resolvedAssignment = datedAssignments.length === 1 ? datedAssignments[0] : null;
  const driverEarnings = earnings.filter((earning) => earning.driver_id === driverId);
  const driverPayments = payments.filter((payment) => payment.driver_id === driverId);
  const filteredEarnings = driverEarnings.filter((earning) => (!fromDate || earning.salary_date >= fromDate) && (!toDate || earning.salary_date <= toDate));
  const filteredPayments = driverPayments.filter((payment) => (!fromDate || payment.payment_date >= fromDate) && (!toDate || payment.payment_date <= toDate));
  const linkMap = useMemo(() => new Map(links.map((link) => [link.driver_earning_id, link.voucher_id])), [links]);
  const voucherMap = useMemo(() => new Map(vouchers.map((voucher) => [voucher.id, voucher])), [vouchers]);
  const basic = numberValue(basicSalary), trip = numberValue(tripPay), bonusAmount = numberValue(bonus), other = numberValue(otherEarnings), fine = numberValue(deduction), adjusted = numberValue(earningAdvance);
  const earnedBefore = basic + trip + bonusAmount + other;
  const gross = Math.max(earnedBefore - fine, 0);
  const net = gross - adjusted;

  const lastPayment = [...driverPayments].sort((a, b) => a.payment_date.localeCompare(b.payment_date) || a.created_at.localeCompare(b.created_at) || a.id - b.id).at(-1);
  const opening = numberValue(selectedDriver?.opening_balance);
  const payable = lastPayment ? numberValue(lastPayment.remaining_payable) : Math.max(opening, 0) + driverEarnings.reduce((sum, earning) => sum + numberValue(earning.remaining_amount), 0);
  const recoverable = lastPayment ? numberValue(lastPayment.remaining_advance) : Math.max(-opening, 0) + driverEarnings.reduce((sum, earning) => sum + Math.max(-numberValue(earning.net_payable), 0), 0);
  const totalGross = driverEarnings.reduce((sum, earning) => sum + numberValue(earning.gross_expense), 0);
  const totalSettled = driverEarnings.reduce((sum, earning) => sum + numberValue(earning.advance_adjusted) + numberValue(earning.paid_amount), 0);

  const ledgerEvents: Omit<LedgerRow, "running">[] = [
      ...driverEarnings.map((earning) => ({ key: `e-${earning.id}`, date: earning.salary_date, type: "earning" as const, earning: numberValue(earning.gross_expense), payment: 0, adjustment: numberValue(earning.advance_adjusted), vehicle: vehicleMap.get(earning.vehicle_id) ?? "-", description: `${t(`drivers.account.earningTypes.${earning.earning_type}`)}${earning.remarks ? ` - ${earning.remarks}` : ""}`, effect: numberValue(earning.net_payable), status: earning.payment_status })),
      ...driverPayments.map((payment) => ({ key: `p-${payment.id}`, date: payment.payment_date, type: "payment" as const, earning: 0, payment: numberValue(payment.payment_now), adjustment: numberValue(payment.advance_used), vehicle: "-", description: `${payment.payment_method ?? "-"}${payment.reference_no ? ` - ${payment.reference_no}` : ""}${payment.remarks ? ` - ${payment.remarks}` : ""}`, effect: -numberValue(payment.payment_now), status: payment.settlement_status })),
    ].sort((a, b) => a.date.localeCompare(b.date) || a.key.localeCompare(b.key));
  const allLedger = ledgerEvents.reduce<{ running: number; rows: LedgerRow[] }>((result, event) => {
    const running = result.running + event.effect;
    return { running, rows: [...result.rows, { ...event, running }] };
  }, { running: opening, rows: [] });
  const ledger = allLedger.rows.filter((event) => (!fromDate || event.date >= fromDate) && (!toDate || event.date <= toDate));
  const statementOpening = opening + ledgerEvents.filter((event) => fromDate && event.date < fromDate).reduce((sum, event) => sum + event.effect, 0);
  const statementClosing = ledger.at(-1)?.running ?? statementOpening;

  async function saveEarning() {
    if (!driverId || !salaryDate || !salaryMonth || !earningType || !resolvedAssignment) { alert(t("drivers.account.errors.assignmentMissing")); return; }
    const values = [basic, trip, bonusAmount, other, fine, adjusted];
    if (values.some((value) => !Number.isFinite(value) || value < 0) || fine > earnedBefore) { alert(t("drivers.account.errors.invalidAmounts")); return; }
    setBusy(true);
    const result = await supabase.rpc("save_driver_earning", {
      p_earning_id: null, p_driver_id: driverId, p_salary_date: salaryDate, p_salary_month: `${salaryMonth}-01`,
      p_period_start: periodStart || null, p_period_end: periodEnd || null, p_earning_type: earningType,
      p_basic_salary: basic, p_trip_pay: trip, p_bonus_allowance: bonusAmount, p_other_earnings: other,
      p_deduction_fine: fine, p_advance_adjusted: adjusted, p_remarks: earningRemarks.trim() || null,
    });
    if (result.error) {
      console.error("save_driver_earning failed", { code: result.error.code, message: result.error.message, details: result.error.details, hint: result.error.hint });
      alert(rpcMessage(result.error, t));
    } else {
      alert(t("drivers.account.messages.earningSaved"));
      setBasicSalary(""); setTripPay(""); setBonus(""); setOtherEarnings(""); setDeduction(""); setEarningAdvance(""); setEarningRemarks(""); await load();
    }
    setBusy(false);
  }

  function resetPayment() { setPaymentId(null); setPaymentDate(today()); setAdvanceUsed(""); setPaymentNow(""); setPaymentMethod("Cash"); setReferenceNo(""); setPaymentRemarks(""); }
  async function savePayment() {
    const advance = numberValue(advanceUsed), cash = numberValue(paymentNow);
    if (!driverId || !paymentDate || advance < 0 || cash < 0 || advance + cash <= 0 || !Number.isFinite(advance + cash)) { alert(t("drivers.account.errors.invalidPayment")); return; }
    const editablePayment = paymentId ? driverPayments.find((payment) => payment.id === paymentId) : null;
    const availableForPayment = editablePayment ? numberValue(editablePayment.available_advance_before) : recoverable;
    if (advance > availableForPayment) { alert(t("drivers.account.errors.advanceExceeded")); return; }
    setBusy(true);
    const result = await supabase.rpc("save_driver_payment", { p_payment_id: paymentId, p_driver_id: driverId, p_payment_date: paymentDate, p_advance_used: advance, p_payment_now: cash, p_payment_method: paymentMethod, p_reference_no: referenceNo.trim() || null, p_remarks: paymentRemarks.trim() || null });
    if (result.error) {
      console.error("save_driver_payment failed", { code: result.error.code, message: result.error.message, details: result.error.details, hint: result.error.hint });
      alert(rpcMessage(result.error, t));
    } else { alert(t("drivers.account.messages.paymentSaved")); resetPayment(); await load(); }
    setBusy(false);
  }

  function editPayment(payment: Payment) { setPaymentId(payment.id); setPaymentDate(payment.payment_date); setAdvanceUsed(String(payment.advance_used)); setPaymentNow(String(payment.payment_now)); setPaymentMethod(payment.payment_method ?? "Cash"); setReferenceNo(payment.reference_no ?? ""); setPaymentRemarks(payment.remarks ?? ""); }
  async function deletePayment(payment: Payment) {
    if (!window.confirm(t("drivers.account.messages.deletePaymentConfirm"))) return;
    setBusy(true); const result = await supabase.rpc("delete_driver_payment", { p_payment_id: payment.id });
    if (result.error) { console.error("delete_driver_payment failed", result.error); alert(rpcMessage(result.error, t)); }
    else { if (paymentId === payment.id) resetPayment(); await load(); }
    setBusy(false);
  }

  function printStatementLegacy() {
    if (!selectedDriver) return;
    const popup = window.open("", "_blank", "width=1150,height=850");
    if (!popup) { alert(t("reports.messages.allowPopups")); return; }
    const rows = ledger.map((row) => `<tr><td>${escapeHtml(row.date)}</td><td>${escapeHtml(t(`drivers.account.types.${row.type}`))}</td><td>${escapeHtml(row.vehicle)}</td><td>${escapeHtml(row.description)}</td><td>${escapeHtml(money(row.earning))}</td><td>${escapeHtml(money(row.payment))}</td><td>${escapeHtml(money(row.adjustment))}</td><td>${escapeHtml(money(row.running))}</td><td>${escapeHtml(statusLabel(row.status,t))}</td></tr>`).join("");
    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head><meta charset="utf-8"><title>${escapeHtml(t("drivers.account.printTitle"))}</title><style>@page{size:A4 landscape;margin:10mm}body{font-family:Arial;color:#0f172a}h1{border-bottom:3px solid #2563eb;padding-bottom:8px}.meta{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:12px 0}.box{border:1px solid #94a3b8;padding:8px}table{width:100%;border-collapse:collapse;font-size:11px}th,td{border:1px solid #94a3b8;padding:6px;text-align:start}th{background:#2563eb;color:white}.summary{margin-top:12px;font-weight:bold}</style></head><body><h1>${PRINT_ADDA_NAME_TOKEN}</h1><p>${escapeHtml(selectedDriver.name)}</p><div class="meta"><div class="box"><b>${escapeHtml(t("drivers.account.driver"))}:</b> ${escapeHtml(selectedDriver.name)}</div><div class="box"><b>${escapeHtml(t("drivers.account.dateRange"))}:</b> ${escapeHtml(fromDate || "-")} — ${escapeHtml(toDate || "-")}</div><div class="box"><b>${escapeHtml(t("drivers.account.openingBalance"))}:</b> ${escapeHtml(money(statementOpening))}</div></div><table><thead><tr>${["date","type","vehicle","description","earning","paymentNow","advanceUsed","runningBalance","status"].map((key) => `<th>${escapeHtml(t(`drivers.account.${key}`))}</th>`).join("")}</tr></thead><tbody>${rows}</tbody></table><div class="summary">${escapeHtml(t("drivers.account.closingBalance"))}: ${escapeHtml(money(statementClosing))} — ${escapeHtml(t(statementClosing > 0 ? "drivers.account.payable" : statementClosing < 0 ? "drivers.account.recoverable" : "drivers.account.settled"))}</div><script>window.onload=()=>{window.print();window.close()}</script></body></html>`, selectedDriver.adda_id, language === "ur" ? "ur" : "en");
  }

  function printStatement() {
    if (!selectedDriver) return;
    const presentation: ModulePrintPresentation = {
      documentType: "driver_ledger",
      title: printLabel("drivers.account.printTitle"),
      documentDate: printValue(fromDate || toDate ? `${fromDate || "—"} — ${toDate || "—"}` : null),
      fields: [
        { label: printLabel("drivers.account.driver"), value: printValue(selectedDriver.name) },
        { label: printLabel("drivers.account.dateRange"), value: printValue(fromDate || toDate ? `${fromDate || "—"} — ${toDate || "—"}` : null) },
      ],
      totals: [
        { label: printLabel("drivers.account.openingBalance"), value: printValue(money(statementOpening)) },
        { label: printLabel("drivers.account.closingBalance"), value: printValue(money(statementClosing)) },
      ],
      tables: [{
        columns: ["drivers.account.date", "drivers.account.type", "drivers.account.vehicle", "drivers.account.description", "drivers.account.earning", "drivers.account.paymentNow", "drivers.account.advanceUsed", "drivers.account.runningBalance", "drivers.account.status"].map(printLabel),
        rows: ledger.map((row) => [printValue(row.date), printLabel(`drivers.account.types.${row.type}`), printValue(row.vehicle), printValue(row.description), printValue(money(row.earning)), printValue(money(row.payment)), printValue(money(row.adjustment)), printValue(money(row.running)), printLabel(`drivers.account.statuses.${row.status}`)]),
      }],
    };
    modulePrint.openPresentation(presentation, printStatementLegacy, selectedDriver.adda_id);
  }

  function printPaymentReceipt(payment: Payment) {
    if (!selectedDriver) return;
    const presentation: ModulePrintPresentation = {
      documentType: "driver_ledger",
      title: printLabel("drivers.account.paymentReceiptTitle"),
      documentNo: printValue(payment.reference_no ?? payment.id),
      documentDate: printValue(payment.payment_date),
      fields: [
        { label: printLabel("drivers.account.driver"), value: printValue(selectedDriver.name) },
        { label: printLabel("drivers.account.paymentMethod"), value: payment.payment_method ? printLabel(`drivers.account.paymentMethods.${payment.payment_method}`) : null },
        { label: printLabel("drivers.account.referenceNo"), value: printValue(payment.reference_no) },
        { label: printLabel("drivers.account.paymentNow"), value: printValue(money(numberValue(payment.payment_now))) },
        { label: printLabel("drivers.account.advanceUsed"), value: printValue(money(numberValue(payment.advance_used))) },
        { label: printLabel("drivers.account.remainingPayable"), value: printValue(money(numberValue(payment.remaining_payable))) },
        { label: printLabel("drivers.account.remainingAdvance"), value: printValue(money(numberValue(payment.remaining_advance))) },
        { label: printLabel("drivers.account.status"), value: printLabel(`drivers.account.statuses.${payment.settlement_status}`) },
      ],
      remarks: printValue(payment.remarks),
    };
    const legacyReceipt = () => {
      const popup = window.open("", "_blank", "width=760,height=700");
      if (!popup) { alert(t("reports.messages.allowPopups")); return; }
      void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head><meta charset="utf-8"><title>${escapeHtml(t("drivers.account.paymentReceiptTitle"))}</title><style>@page{size:A5 portrait;margin:12mm}body{font-family:Arial,sans-serif;color:#111827}.receipt{border:1px solid #94a3b8;padding:18px}.row{padding:8px;border-bottom:1px solid #cbd5e1}.sign{margin-top:46px;border-top:1px solid #111827;padding-top:6px;text-align:center}</style></head><body><h1>${PRINT_ADDA_NAME_TOKEN}</h1><div class="receipt"><h2>${escapeHtml(t("drivers.account.paymentReceiptTitle"))}</h2>${[[t("drivers.account.driver"),selectedDriver.name],[t("drivers.account.paymentDate"),payment.payment_date],[t("drivers.account.paymentNow"),money(numberValue(payment.payment_now))],[t("drivers.account.advanceUsed"),money(numberValue(payment.advance_used))],[t("drivers.account.paymentMethod"),payment.payment_method??"—"],[t("drivers.account.referenceNo"),payment.reference_no??"—"],[t("drivers.account.remarks"),payment.remarks??"—"]].map(([label,value])=>`<div class="row"><b>${escapeHtml(label)}:</b> ${escapeHtml(value)}</div>`).join("")}<div class="sign">${escapeHtml(t("drivers.account.driver"))} / Receiver signature</div></div><script>window.onload=()=>{window.focus();window.print()}</script></body></html>`, selectedDriver.adda_id, language === "ur" ? "ur" : "en");
    };
    modulePrint.openPresentation(presentation, legacyReceipt, selectedDriver.adda_id);
  }

  if (loading) return <Card><p className="text-center font-bold">{t("common.loading")}</p></Card>;
  if (error) return <div className="rounded-xl border border-red-200 bg-red-50 p-5 font-bold text-red-700">{error}</div>;

  return <div className="space-y-5">
    <Card><div className="grid gap-4 lg:grid-cols-[1fr_2fr]"><label className="font-bold">{t("drivers.account.selectDriver")}<select className={`${fieldClass} mt-1`} value={driverId} onChange={(event) => { setDriverId(event.target.value); resetPayment(); }}><option value="">{t("drivers.assignment.selectDriver")}</option>{drivers.map((driver) => <option key={driver.id} value={driver.id}>{driver.name}</option>)}</select></label><div className="grid gap-3 sm:grid-cols-3"><Info label={t("drivers.account.driver")} value={selectedDriver?.name ?? "-"}/><Info label={t("drivers.assignment.currentVehicle")} value={vehicleMap.get(currentAssignment?.vehicle_id ?? "") ?? t("drivers.assignment.unassigned")}/><Info label={t("drivers.account.accountStatus")} value={t(payable > 0 ? "drivers.account.payable" : recoverable > 0 ? "drivers.account.recoverable" : "drivers.account.settled")}/></div></div></Card>
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5"><Summary label={t("drivers.account.totalEarnings")} value={totalGross}/><Summary label={t("drivers.account.totalSettled")} value={totalSettled}/><Summary label={t("drivers.account.currentPayable")} value={payable} tone="red"/><Summary label={t("drivers.account.driverRecoverable")} value={recoverable} tone="green"/><Summary label={t("drivers.account.availableAdvance")} value={recoverable} tone="green"/></div>
    <div className="grid gap-5 xl:grid-cols-2"><Card><h2 className="text-xl font-black">{t("drivers.account.addEarning")}</h2><div className="mt-4 grid gap-3 sm:grid-cols-2">
    <Label text={t("drivers.account.salaryDate")}><VoiceTypingField fieldLabel={t("drivers.account.salaryDate")} mode="date"><input className={fieldClass} type="date" value={salaryDate} onChange={(event) => setSalaryDate(event.target.value)}/></VoiceTypingField></Label>

    <Label text={t("drivers.account.salaryMonth")}><VoiceTypingField fieldLabel={t("drivers.account.salaryMonth")} mode="date"><input className={fieldClass} type="month" value={salaryMonth} onChange={(event) => setSalaryMonth(event.target.value)}/></VoiceTypingField></Label>

    <Label text={t("drivers.account.periodStart")}><VoiceTypingField fieldLabel={t("drivers.account.periodStart")} mode="date"><input className={fieldClass} type="date" value={periodStart} onChange={(event) => setPeriodStart(event.target.value)}/></VoiceTypingField></Label>

    <Label text={t("drivers.account.periodEnd")}><VoiceTypingField fieldLabel={t("drivers.account.periodEnd")} mode="date"><input className={fieldClass} type="date" value={periodEnd} onChange={(event) => setPeriodEnd(event.target.value)}/></VoiceTypingField></Label>
    <Label text={t("drivers.account.earningType")}><select className={fieldClass} value={earningType} onChange={(event) => setEarningType(event.target.value)}>{["monthly_salary","trip_pay","bonus_allowance","other"].map((type) => <option key={type} value={type}>{t(`drivers.account.earningTypes.${type}`)}</option>)}</select></Label><Info label={t("drivers.account.resolvedVehicle")} value={resolvedAssignment ? vehicleMap.get(resolvedAssignment.vehicle_id) ?? "-" : t("drivers.account.noAssignment")}/>{([[t("drivers.account.basicSalary"),basicSalary,setBasicSalary],[t("drivers.account.tripPay"),tripPay,setTripPay],[t("drivers.account.bonusAllowance"),bonus,setBonus],[t("drivers.account.otherEarnings"),otherEarnings,setOtherEarnings],[t("drivers.account.deductionFine"),deduction,setDeduction],[t("drivers.account.advanceAdjusted"),earningAdvance,setEarningAdvance]] as [string,string,(value:string)=>void][]).map(([label,value,setter]) =>
    <Label key={label} text={label}><VoiceTypingField fieldLabel={label} mode="number"><input className={fieldClass} type="number" min="0" step="0.01" value={value} onChange={(event) => setter(event.target.value)}/></VoiceTypingField></Label>
    )}</div><Label text={t("drivers.account.remarks")}><VoiceTypingField fieldLabel={t("drivers.account.remarks")} value={earningRemarks} onValueChange={setEarningRemarks} contextKey={`${driverId}:earning`}><textarea className={`${fieldClass} mt-3`} value={earningRemarks} onChange={(event) => setEarningRemarks(event.target.value)}/></VoiceTypingField></Label><div className="mt-4 grid grid-cols-3 gap-2 rounded-xl bg-blue-50 p-3 text-sm font-bold"><span>{t("drivers.account.earnedBefore")}: {money(earnedBefore)}</span><span>{t("drivers.account.grossExpense")}: {money(gross)}</span><span>{t("drivers.account.netPayable")}: {money(net)}</span></div><button disabled={busy || !driverId} onClick={() => void saveEarning()} className="mt-4 rounded-lg bg-blue-600 px-5 py-2.5 font-black text-white disabled:opacity-50">{t("drivers.account.saveEarning")}</button></Card>
    <Card><h2 className="text-xl font-black">{t(paymentId ? "drivers.account.editPayment" : "drivers.account.addPayment")}</h2><div className="mt-4 grid gap-3 sm:grid-cols-2">
    <Label text={t("drivers.account.paymentDate")}><VoiceTypingField fieldLabel={t("drivers.account.paymentDate")} mode="date"><input className={fieldClass} type="date" value={paymentDate} onChange={(event) => setPaymentDate(event.target.value)}/></VoiceTypingField></Label>

    <Label text={t("drivers.account.advanceUsed")}><VoiceTypingField fieldLabel={t("drivers.account.advanceUsed")} mode="amount"><input className={fieldClass} type="number" min="0" step="0.01" value={advanceUsed} onChange={(event) => setAdvanceUsed(event.target.value)}/></VoiceTypingField></Label>

    <Label text={t("drivers.account.paymentNow")}><VoiceTypingField fieldLabel={t("drivers.account.paymentNow")} mode="amount"><input className={fieldClass} type="number" min="0" step="0.01" value={paymentNow} onChange={(event) => setPaymentNow(event.target.value)}/></VoiceTypingField></Label>
    <Label text={t("drivers.account.paymentMethod")}><select className={fieldClass} value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)}>{["Cash","Bank Transfer","Cheque","Online"].map((method) => <option key={method} value={method}>{t(`drivers.account.paymentMethods.${method}`)}</option>)}</select></Label>
    <Label text={t("drivers.account.referenceNo")}><VoiceTypingField fieldLabel={t("drivers.account.referenceNo")} mode="identifier"><input className={fieldClass} value={referenceNo} onChange={(event) => setReferenceNo(event.target.value)}/></VoiceTypingField></Label>
    <Label text={t("drivers.account.remarks")}><VoiceTypingField fieldLabel={t("drivers.account.remarks")} value={paymentRemarks} onValueChange={setPaymentRemarks} contextKey={`${driverId}:payment:${paymentId ?? "new"}`}><textarea className={fieldClass} value={paymentRemarks} onChange={(event) => setPaymentRemarks(event.target.value)}/></VoiceTypingField></Label></div><div className="mt-4 rounded-xl border border-blue-200 bg-blue-50 p-3 font-semibold">{t("drivers.account.cashbookNotice")}</div><div className="mt-4 flex gap-2"><button disabled={busy || !driverId} onClick={() => void savePayment()} className="rounded-lg bg-blue-600 px-5 py-2.5 font-black text-white disabled:opacity-50">{t(paymentId ? "drivers.account.updatePayment" : "drivers.account.savePayment")}</button>{paymentId && <button onClick={resetPayment} className="rounded-lg border px-5 font-bold">{t("common.actions.cancel")}</button>}</div></Card></div>
    <Card><div className="flex flex-wrap items-end justify-between gap-3"><div><h2 className="text-xl font-black">{t("drivers.account.ledgerTitle")}</h2><p className="font-semibold text-slate-600">{t("drivers.account.ledgerDescription")}</p></div>

    <div className="flex flex-wrap gap-2"><VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input className={fieldClass} type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)}/></VoiceTypingField><VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input className={fieldClass} type="date" value={toDate} onChange={(event) => setToDate(event.target.value)}/></VoiceTypingField><button onClick={() => { setFromDate(""); setToDate(""); }} className="rounded-lg border px-4 font-bold">{t("common.actions.reset")}</button><button onClick={printStatement} className="rounded-lg bg-blue-600 px-4 font-
    bold text-white">{t("common.actions.print")}</button></div>
    </div><Table headers={["date","type","earning","paymentNow","advanceUsed","vehicle","description","runningBalance","status"].map((key) => t(`drivers.account.${key}`))} rows={ledger.map((row) => [row.date,t(`drivers.account.types.${row.type}`),money(row.earning),money(row.payment),money(row.adjustment),row.vehicle,row.description,money(row.running),statusLabel(row.status,t)])}/></Card>
    <Card><h2 className="text-xl font-black">{t("drivers.account.earningHistory")}</h2><Table headers={["salaryDate","salaryMonth","vehicle","grossExpense","totalSettled","remaining","status","voucherStatus"].map((key) => t(`drivers.account.${key}`))} rows={filteredEarnings.map((earning) => { const voucherId = linkMap.get(earning.id), voucher = voucherId ? voucherMap.get(voucherId) : null; return [earning.salary_date,earning.salary_month.slice(0,7),vehicleMap.get(earning.vehicle_id) ?? "-",money(numberValue(earning.gross_expense)),money(numberValue(earning.advance_adjusted)+numberValue(earning.paid_amount)),money(numberValue(earning.remaining_amount)),statusLabel(earning.payment_status,t),voucher ? `${t("drivers.account.attached")} — ${voucher.expense_no ?? voucher.id} (${voucher.expense_date ?? "-"})` : t("drivers.account.notAttached")]; })}/></Card>
    <Card><h2 className="text-xl font-black">{t("drivers.account.paymentHistory")}</h2><Table headers={["paymentDate","paymentNow","advanceUsed","paymentMethod","referenceNo","remarks","status","actions"].map((key) => t(`drivers.account.${key}`))} rows={filteredPayments.map((payment) => [payment.payment_date,money(numberValue(payment.payment_now)),money(numberValue(payment.advance_used)),t(`drivers.account.paymentMethods.${payment.payment_method ?? "Cash"}`),payment.reference_no ?? "-",payment.remarks ?? "-",statusLabel(payment.settlement_status,t),<div key={payment.id} className="flex gap-3"><button onClick={() => printPaymentReceipt(payment)} className="font-bold text-slate-700">{t("common.actions.print")}</button><button onClick={() => editPayment(payment)} className="font-bold text-blue-700">{t("common.actions.edit")}</button><button disabled={busy} onClick={() => void deletePayment(payment)} className="font-bold text-red-700">{t("common.actions.delete")}</button></div>])}/><p className="mt-3 text-xs font-semibold text-slate-500">{t("drivers.account.allocationsInfo")}: {allocations.filter((allocation) => driverEarnings.some((earning) => earning.id === allocation.driver_earning_id)).length}</p></Card>
  </div>;
}

function Label({ text, children }: { text: string; children: React.ReactNode }) { return <label className="font-bold"><span className="mb-1 block">{text}</span>{children}</label>; }
function Info({ label, value }: { label: string; value: string }) { return <div className="rounded-xl border border-blue-100 bg-blue-50 p-3"><p className="text-xs font-bold text-slate-600">{label}</p><p className="mt-1 font-black">{value}</p></div>; }
function Summary({ label, value, tone = "blue" }: { label: string; value: number; tone?: "blue" | "red" | "green" }) { const colors = tone === "red" ? "text-red-700" : tone === "green" ? "text-green-700" : "text-blue-700"; return <Card><p className="font-bold text-slate-600">{label}</p><p className={`mt-2 text-2xl font-black ${colors}`}>{money(value)}</p></Card>; }
function Table({ headers, rows }: { headers: string[]; rows: React.ReactNode[][] }) { return <div className="mt-4 overflow-x-auto"><table className="w-full min-w-[950px] text-sm"><thead className="bg-blue-600 text-white"><tr>{headers.map((header) => <th key={header} className="p-3 text-start">{header}</th>)}</tr></thead><tbody>{rows.map((row, rowIndex) => <tr key={rowIndex} className="border-b border-slate-200">{row.map((cell, cellIndex) => <td key={cellIndex} className="p-3">{cell}</td>)}</tr>)}</tbody></table></div>; }

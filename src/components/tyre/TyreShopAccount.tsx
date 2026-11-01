"use client";

import { useCallback, useEffect, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { supabase } from "@/lib/supabase/client";
import { money, type TyreShop } from "./types";

type Bill = { id:string; bill_date:string; bill_no:string|null; amount:number; paid_amount:number; remaining_amount:number; payment_status:string; tyre_vehicle_entries:{ work_type:string; vehicles:{vehicle_no:string|null}|null }|null };
type Payment = { id:number; payment_date:string; advance_used:number; payment_now:number; amount:number; remaining_payable:number; remaining_advance:number; settlement_status:string; payment_method:string|null; reference_no:string|null; remarks:string|null };
const input = "w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 font-semibold";
const number = (value:unknown) => Number.isFinite(Number(value)) ? Number(value) : 0;

export default function TyreShopAccount({ shops, onChanged }:{ shops:TyreShop[]; onChanged:()=>Promise<void> }) {
  const { t, dir, language } = useLanguage();
  const [shopId, setShopId] = useState("");
  const [bills, setBills] = useState<Bill[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [editId, setEditId] = useState<number|null>(null);
  const [form, setForm] = useState({ date:new Date().toISOString().slice(0,10), advance:"0", now:"0", method:"Cash", reference:"", remarks:"" });
  const shop = shops.find((item) => item.id === shopId);
  const modulePrint = useModuleTransportPrint("tyre", shop?.addaId, language);

  const load = useCallback(async () => {
    if (!shopId) { setBills([]); setPayments([]); return; }
    const [billResult, paymentResult] = await Promise.all([
      supabase.from("tyre_shop_bills").select("id,bill_date,bill_no,amount,paid_amount,remaining_amount,payment_status,tyre_vehicle_entries(work_type,vehicles(vehicle_no))").eq("tyre_shop_id",shopId).order("bill_date"),
      supabase.from("tyre_shop_payments").select("id,payment_date,advance_used,payment_now,amount,remaining_payable,remaining_advance,settlement_status,payment_method,reference_no,remarks").eq("tyre_shop_id",shopId).order("payment_date",{ascending:false}).order("id",{ascending:false}),
    ]);
    if (billResult.error || paymentResult.error) { console.error("Tyre Shop account load failed", billResult.error ?? paymentResult.error); return; }
    setBills((billResult.data ?? []) as unknown as Bill[]);
    setPayments((paymentResult.data ?? []) as Payment[]);
  }, [shopId]);
  useEffect(() => { const timer=window.setTimeout(()=>void load(),0); return()=>window.clearTimeout(timer); }, [load]);

  const latest = payments[0];
  const totalBills = bills.reduce((sum,bill)=>sum+number(bill.amount),0);
  const totalSettled = bills.reduce((sum,bill)=>sum+number(bill.paid_amount),0);
  const payable = latest?.remaining_payable ?? Math.max(number(shop?.openingBalance),0)+bills.reduce((sum,bill)=>sum+number(bill.remaining_amount),0);
  const advance = latest?.remaining_advance ?? Math.max(-number(shop?.openingBalance),0);

  async function save() {
    const { error } = await supabase.rpc("save_tyre_shop_payment", { p_payment_id:editId, p_tyre_shop_id:shopId, p_payment_date:form.date, p_advance_used:number(form.advance), p_payment_now:number(form.now), p_payment_method:form.method, p_reference_no:form.reference||null, p_remarks:form.remarks||null });
    if (error) { console.error("Tyre Shop payment save failed",error); alert(t("tyre.account.saveFailed")); return; }
    setEditId(null); setForm({...form,advance:"0",now:"0",reference:"",remarks:""}); await load(); await onChanged();
  }
  async function remove(id:number) {
    if (!confirm(t("tyre.account.confirmDelete"))) return;
    const { error } = await supabase.rpc("delete_tyre_shop_payment",{p_payment_id:id});
    if (error) { console.error("Tyre Shop payment delete failed",error); return; }
    await load(); await onChanged();
  }
  function legacyPrintLedger() {
    if (!shop) return;
    const popup=window.open("","_blank","width=1100,height=800"); if(!popup)return;
    const billRows=bills.map(bill=>`<tr><td>${escapeHtml(bill.bill_date)}</td><td>${escapeHtml(bill.tyre_vehicle_entries?.vehicles?.vehicle_no??"-")}</td><td>${escapeHtml(bill.bill_no??"-")}</td><td>${escapeHtml(money(bill.amount))}</td><td>${escapeHtml(money(bill.paid_amount))}</td><td>${escapeHtml(money(bill.remaining_amount))}</td></tr>`).join("");
    const paymentRows=payments.map(payment=>`<tr><td>${escapeHtml(payment.payment_date)}</td><td>${escapeHtml(money(payment.advance_used))}</td><td>${escapeHtml(money(payment.payment_now))}</td><td>${escapeHtml(money(payment.remaining_payable))}</td><td>${escapeHtml(money(payment.remaining_advance))}</td><td>${escapeHtml(payment.reference_no??"-")}</td></tr>`).join("");
    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head><style>@page{size:A4;margin:12mm}body{font-family:Arial;color:#0f172a}table{width:100%;border-collapse:collapse;margin:16px 0}th,td{border:1px solid #94a3b8;padding:7px}th{background:#2563eb;color:white}</style></head><body><h1>${PRINT_ADDA_NAME_TOKEN} — ${escapeHtml(t("tyre.account.ledger"))}</h1><h2>${escapeHtml(shop.shopName)}</h2><p>${escapeHtml(t("tyre.account.currentPayable"))}: ${escapeHtml(money(payable))} · ${escapeHtml(t("tyre.account.availableAdvance"))}: ${escapeHtml(money(advance))}</p><h3>${escapeHtml(t("tyre.account.bills"))}</h3><table>${billRows}</table><h3>${escapeHtml(t("tyre.account.payments"))}</h3><table>${paymentRows}</table><script>window.onload=()=>{window.focus();window.print()}</script></body></html>`, shop.addaId, language === "ur" ? "ur" : "en");
  }

  function printLedger() {
    if (!shop) return;
    const body = `<div class="grid"><div><strong>${escapeHtml(t("tyre.account.openingBalance"))}:</strong> ${escapeHtml(money(shop.openingBalance))}</div><div><strong>${escapeHtml(t("tyre.account.totalBills"))}:</strong> ${escapeHtml(money(totalBills))}</div><div><strong>${escapeHtml(t("tyre.account.totalSettled"))}:</strong> ${escapeHtml(money(totalSettled))}</div><div><strong>${escapeHtml(t("tyre.account.currentPayable"))}:</strong> ${escapeHtml(money(payable))}</div><div><strong>${escapeHtml(t("tyre.account.availableAdvance"))}:</strong> ${escapeHtml(money(advance))}</div></div><h2>${escapeHtml(shop.shopName)}</h2><h3>${escapeHtml(t("tyre.account.bills"))}</h3><table><thead><tr>${["common.date","common.vehicle","tyre.fields.billNo","common.total","common.paid","common.remaining"].map(key=>`<th>${escapeHtml(t(key))}</th>`).join("")}</tr></thead><tbody>${bills.map(bill=>`<tr><td>${escapeHtml(bill.bill_date)}</td><td>${escapeHtml(bill.tyre_vehicle_entries?.vehicles?.vehicle_no??"-")}</td><td>${escapeHtml(bill.bill_no??"-")}</td><td>${escapeHtml(money(bill.amount))}</td><td>${escapeHtml(money(bill.paid_amount))}</td><td>${escapeHtml(money(bill.remaining_amount))}</td></tr>`).join("")}</tbody></table><h3>${escapeHtml(t("tyre.account.payments"))}</h3><table><thead><tr>${["common.date","tyre.account.advanceUsed","tyre.account.paymentNow","tyre.account.currentPayable","tyre.account.availableAdvance","tyre.account.referenceNo"].map(key=>`<th>${escapeHtml(t(key))}</th>`).join("")}</tr></thead><tbody>${payments.map(payment=>`<tr><td>${escapeHtml(payment.payment_date)}</td><td>${escapeHtml(money(payment.advance_used))}</td><td>${escapeHtml(money(payment.payment_now))}</td><td>${escapeHtml(money(payment.remaining_payable))}</td><td>${escapeHtml(money(payment.remaining_advance))}</td><td>${escapeHtml(payment.reference_no??"-")}</td></tr>`).join("")}</tbody></table>`;
    modulePrint.open(t("tyre.account.ledger"), body, legacyPrintLedger);
  }

  const cards=[["openingBalance",number(shop?.openingBalance)],["totalBills",totalBills],["totalSettled",totalSettled],["currentPayable",payable],["availableAdvance",advance]] as const;
  return <div dir={dir} className="space-y-4">
    <section className="rounded-xl border bg-white p-5"><label className="font-bold">{t("tyre.account.shop")}<select className={`${input} mt-1`} value={shopId} onChange={(event)=>setShopId(event.target.value)}><option value="">{t("tyre.select")}</option>{shops.filter(item=>item.shopType==="external_supplier"&&item.isActive).map(item=><option key={item.id} value={item.id}>{item.shopName}</option>)}</select></label>{shop&&<button className="mt-3 rounded-lg border border-blue-600 px-4 py-2 font-bold text-blue-700" onClick={printLedger}>{t("tyre.account.printLedger")}</button>}</section>
    {shop&&<><section className="grid gap-3 md:grid-cols-5">{cards.map(([key,value])=><div key={key} className="rounded-xl border bg-white p-4"><p className="font-bold text-slate-600">{t(`tyre.account.${key}`)}</p><p className="text-xl font-black text-blue-700">{money(value)}</p></div>)}</section>
    <section className="rounded-xl border bg-white p-5"><h2 className="text-xl font-black">{t("tyre.account.addPayment")}</h2>



    <div className="mt-3 grid gap-3 md:grid-cols-4"><VoiceTypingField fieldLabel={t("tyre.account.paymentDate")} mode="date"><input type="date" className={input} value={form.date} onChange={event=>setForm({...form,date:event.target.value})}/></VoiceTypingField><VoiceTypingField fieldLabel={t("tyre.account.advanceUsed")} mode="amount"><input type="number" min="0" className={input} placeholder={t("tyre.account.advanceUsed")} value={form.advance} onChange={event=>setForm({...form,advance:event.target.value})}/></VoiceTypingField><VoiceTypingField fieldLabel={t("tyre.account.paymentNow")} mode="amount"><input type="number" min="0" className={input} placeholder={t("tyre.account.paymentNow")} value={form.now} onChange={event=>setForm({...form,now:event.target.value})}/></VoiceTypingField><select className={input} value={form.method} onChange={event=>setForm({...form,method:event.target.value})}><option>Cash</option><option>Bank</option></select><VoiceTypingField fieldLabel={t("tyre.account.referenceNo")} mode="identifier"><input className={input} placeholder={t("tyre.account.referenceNo")} value={form.reference} onChange={event=>setForm({...form,reference:event.target.value})}/></VoiceTypingField><VoiceTypingField fieldLabel={t("common.remarks")} value={form.remarks} onValueChange={remarks=>setForm(current=>({...current,remarks}))} contextKey={`${shopId}:${editId ?? "new"}`}><input className={`${input} md:col-span-2`} placeholder={t("common.remarks")} value={form.remarks} onChange={event=>setForm({...form,remarks:event.target.value})}/></VoiceTypingField></div>
    <p className="mt-3 rounded-lg bg-blue-50 p-3 font-bold">{t("tyre.account.totalSettlement")}: {money(number(form.advance)+number(form.now))}</p><button disabled={!form.date||number(form.advance)+number(form.now)<=0||number(form.advance)>advance||number(form.advance)>payable} onClick={()=>void save()} className="mt-3 rounded-lg bg-blue-600 px-5 py-2.5 font-bold text-white disabled:opacity-40">{t("common.actions.save")}</button></section>
    <section className="overflow-x-auto rounded-xl border bg-white p-5"><h2 className="text-xl font-black">{t("tyre.account.bills")}</h2><table className="mt-3 w-full text-sm"><tbody>{bills.map(bill=><tr className="border-b" key={bill.id}><td className="p-2">{bill.bill_date}</td><td>{bill.tyre_vehicle_entries?.vehicles?.vehicle_no??"-"}</td><td>{bill.bill_no??"-"}</td><td>{bill.tyre_vehicle_entries?.work_type?t(`tyre.work.${bill.tyre_vehicle_entries.work_type}`):"-"}</td><td>{money(bill.amount)}</td><td>{money(bill.paid_amount)}</td><td>{money(bill.remaining_amount)}</td><td>{t(`tyre.account.status.${bill.payment_status}`)}</td></tr>)}</tbody></table></section>
    <section className="overflow-x-auto rounded-xl border bg-white p-5"><h2 className="text-xl font-black">{t("tyre.account.payments")}</h2><table className="mt-3 w-full text-sm"><tbody>{payments.map(payment=><tr className="border-b" key={payment.id}><td className="p-2">{payment.payment_date}</td><td>{money(payment.advance_used)}</td><td>{money(payment.payment_now)}</td><td>{money(payment.remaining_payable)}</td><td>{money(payment.remaining_advance)}</td><td>{payment.payment_method??"-"}</td><td>{payment.reference_no??"-"}</td><td>{t(`tyre.account.status.${payment.settlement_status}`)}</td><td><button className="me-3 font-bold text-blue-700" onClick={()=>{setEditId(payment.id);setForm({date:payment.payment_date,advance:String(payment.advance_used),now:String(payment.payment_now),method:payment.payment_method??"Cash",reference:payment.reference_no??"",remarks:payment.remarks??""})}}>{t("common.actions.edit")}</button><button className="font-bold text-red-700" onClick={()=>void remove(payment.id)}>{t("common.actions.delete")}</button></td></tr>)}</tbody></table></section></>}
    {modulePrint.dialog}
  </div>;
}

"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import { useModuleTransportPrint } from "@/components/print/ModuleTransportPrintButton";
import { supabase } from "@/lib/supabase/client";
import OilSupplierAccount from "./OilSupplierAccount";
import { readManualVoucherSourceEditContext, returnToManualVoucherAfterSourceEdit, type ManualVoucherSourceEditContext } from "@/lib/manualVoucherSourceEdit";
import { money, productLabel, type OilExternalSale, type OilMovementType, type OilProduct, type OilPurchase, type OilShop, type OilStockMovement, type OilSupplierBill, type OilVehicleEntry, type PartyOption, type PurchaseLine, type VehicleOption } from "./types";

type Tab = "dashboard" | "shops" | "account" | "products" | "store" | "vehicle" | "sales" | "stock" | "history";
const today = () => new Date().toISOString().slice(0, 10);
const line = (): PurchaseLine => ({ key: crypto.randomUUID(), oilProductId: "", liters: "", ratePerLiter: "", batchReference: "" });
const input = "w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-slate-950 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100";
const label = "space-y-1 text-sm font-bold text-slate-900";

function relationOne<T>(value: T | T[] | null | undefined): T | null { return Array.isArray(value) ? value[0] ?? null : value ?? null; }
function num(value: unknown) { const parsed = Number(value ?? 0); return Number.isFinite(parsed) ? parsed : 0; }

export default function OilManager() {
  const { t, dir, language } = useLanguage();
  const [tab, setTab] = useState<Tab>("dashboard");
  const [addaId, setAddaId] = useState("");
  const [shops, setShops] = useState<OilShop[]>([]);
  const [products, setProducts] = useState<OilProduct[]>([]);
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [parties, setParties] = useState<PartyOption[]>([]);
  const [purchases, setPurchases] = useState<OilPurchase[]>([]);
  const [supplierBills, setSupplierBills] = useState<OilSupplierBill[]>([]);
  const [movements, setMovements] = useState<OilStockMovement[]>([]);
  const [vehicleEntries, setVehicleEntries] = useState<OilVehicleEntry[]>([]);
  const [sales, setSales] = useState<OilExternalSale[]>([]);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [manualSourceEditContext, setManualSourceEditContext] = useState<ManualVoucherSourceEditContext | null>(null);
  const lock = useRef(false);
  const modulePrint = useModuleTransportPrint("oil", addaId || null, language);

  useEffect(() => {
    const context = readManualVoucherSourceEditContext("oil");
    if (context) {
      const timer = window.setTimeout(() => {
        setManualSourceEditContext(context);
        setTab("vehicle");
      }, 0);
      return () => window.clearTimeout(timer);
    }
  }, []);

  const load = useCallback(async () => {
    setLoading(true); setError("");
    const auth = await supabase.auth.getUser();
    if (!auth.data.user) { setError(t("oil.messages.auth")); setLoading(false); return; }
    const profile = await supabase.from("profiles").select("adda_id,is_active").eq("id", auth.data.user.id).maybeSingle();
    if (profile.error || !profile.data?.is_active || !profile.data.adda_id) { setError(t("oil.messages.auth")); setLoading(false); return; }
    setAddaId(profile.data.adda_id);
    const [shopResult, productResult, vehicleResult, partyResult, purchaseResult, movementResult, entryResult, saleResult, supplierBillResult] = await Promise.all([
      supabase.from("oil_shops").select("id,adda_id,shop_name,shop_type,owner_name,phone,address,opening_balance,is_active").order("shop_name"),
      supabase.from("oil_products").select("id,adda_id,oil_type,brand,grade,is_active").order("oil_type"),
      supabase.from("vehicles").select("id,vehicle_no,owner_name").order("vehicle_no"),
      supabase.from("parties").select("id,name").eq("is_active", true).order("name"),
      supabase.from("oil_purchases").select("id,purchase_date,oil_shop_id,bill_no,total_amount,paid_amount,remaining_amount,payment_status,remarks,oil_shops(shop_name),oil_purchase_items(oil_product_id,liters,rate_per_liter,batch_reference)").order("purchase_date", { ascending: false }),
      supabase.from("oil_stock_movements").select("id,movement_date,oil_product_id,movement_type,liters_in,liters_out,unit_cost,reference_type,reference_id,remarks").order("movement_date", { ascending: true }).order("created_at", { ascending: true }),
      supabase.from("oil_vehicle_entries").select("id,entry_date,vehicle_id,source_type,oil_shop_id,oil_product_id,liters,rate_per_liter,total_amount,bill_no,odometer,next_oil_change_date,remarks").order("entry_date", { ascending: false }),
      supabase.from("oil_external_sales").select("id,sale_date,oil_product_id,vehicle_no,party_id,owner_name,phone,liters,sale_rate_per_liter,total_amount,received_amount,remaining_amount,sale_status,payment_method,remarks").order("sale_date", { ascending: false }),
      supabase.from("oil_supplier_bills").select("id,oil_shop_id,source_type,oil_purchase_id,oil_vehicle_entry_id,bill_date,bill_no,amount,paid_amount,remaining_amount,payment_status"),
    ]);
    const failed = [
      { query: "oil_shops", result: shopResult },
      { query: "oil_products", result: productResult },
      { query: "vehicles", result: vehicleResult },
      { query: "parties", result: partyResult },
      { query: "oil_purchases", result: purchaseResult },
      { query: "oil_stock_movements", result: movementResult },
      { query: "oil_vehicle_entries", result: entryResult },
      { query: "oil_external_sales", result: saleResult },
      { query: "oil_supplier_bills", result: supplierBillResult },
    ].find((entry) => entry.result.error);
    if (failed?.result.error) {
      const loadError = failed.result.error;
      console.error("Oil module load failed", {
        query: failed.query,
        code: loadError.code,
        message: loadError.message,
        details: loadError.details,
        hint: loadError.hint,
      });
      const missingOilSchema =
        (loadError.code === "PGRST205" || loadError.code === "42P01") &&
        /oil_(shops|products|purchases|purchase_items|stock_movements|vehicle_entries|external_sales)/i.test(
          `${loadError.message ?? ""} ${loadError.details ?? ""}`
        );
      setError(t(missingOilSchema ? "oil.messages.schemaMissing" : "oil.messages.loadFailed"));
      setLoading(false);
      return;
    }
    setShops((shopResult.data ?? []).map((x) => ({ id:String(x.id), addaId:String(x.adda_id), shopName:x.shop_name, shopType:x.shop_type as OilShop["shopType"], ownerName:x.owner_name??"", phone:x.phone??"", address:x.address??"", openingBalance:num(x.opening_balance), isActive:Boolean(x.is_active) })));
    setProducts((productResult.data ?? []).map((x) => ({ id:String(x.id), addaId:String(x.adda_id), oilType:x.oil_type, brand:x.brand??"", grade:x.grade??"", isActive:Boolean(x.is_active) })));
    setVehicles((vehicleResult.data ?? []).map((x) => ({ id:String(x.id), vehicleNo:x.vehicle_no??"-", ownerName:x.owner_name??"" })));
    setParties((partyResult.data ?? []).map((x) => ({ id:String(x.id), partyName:x.name??"-" })));
    setPurchases((purchaseResult.data ?? []).map((x) => { const shop=relationOne(x.oil_shops as {shop_name:string}|{shop_name:string}[]|null);const bill=(supplierBillResult.data??[]).find(b=>String(b.oil_purchase_id)===String(x.id)); return { id:String(x.id),purchaseDate:x.purchase_date,oilShopId:String(x.oil_shop_id),shopName:shop?.shop_name??"-",billNo:x.bill_no??"",totalAmount:num(x.total_amount),paidAmount:num(bill?.paid_amount??x.paid_amount),remainingAmount:num(bill?.remaining_amount??x.remaining_amount),paymentStatus:bill?.payment_status??x.payment_status,remarks:x.remarks??"",items:(x.oil_purchase_items??[]).map((i) => ({key:crypto.randomUUID(),oilProductId:String(i.oil_product_id),liters:String(i.liters),ratePerLiter:String(i.rate_per_liter),batchReference:i.batch_reference??""})) }; }));
    setMovements((movementResult.data ?? []).map((x) => ({ id:String(x.id),movementDate:x.movement_date,oilProductId:String(x.oil_product_id),movementType:x.movement_type as OilMovementType,litersIn:num(x.liters_in),litersOut:num(x.liters_out),unitCost:num(x.unit_cost),referenceType:x.reference_type,referenceId:String(x.reference_id),remarks:x.remarks??"" })));
    const oilEntryIds = (entryResult.data ?? []).map((entry) => String(entry.id));
    const linkResult = oilEntryIds.length === 0
      ? { data: [] as Array<{ oil_vehicle_entry_id: string; voucher_id: number }>, error: null }
      : await supabase.from("voucher_oil_entries").select("oil_vehicle_entry_id,voucher_id").in("oil_vehicle_entry_id", oilEntryIds);
    if (linkResult.error) {
      console.error("Oil Voucher attachment status load failed", linkResult.error);
      setError(t("oil.messages.loadFailed")); setLoading(false); return;
    }
    const voucherIds = Array.from(new Set((linkResult.data ?? []).map((link) => Number(link.voucher_id))));
    const voucherResult = voucherIds.length === 0
      ? { data: [] as Array<{ id: number; expense_no: string | null; expense_date: string | null }>, error: null }
      : await supabase.from("expenses").select("id,expense_no,expense_date").in("id", voucherIds);
    if (voucherResult.error) {
      console.error("Oil-linked Voucher metadata load failed", voucherResult.error);
      setError(t("oil.messages.loadFailed")); setLoading(false); return;
    }
    const links = new Map((linkResult.data ?? []).map((link) => [String(link.oil_vehicle_entry_id), Number(link.voucher_id)]));
    const vouchers = new Map((voucherResult.data ?? []).map((voucher) => [Number(voucher.id), voucher]));
    setVehicleEntries((entryResult.data ?? []).map((x) => { const voucherId=links.get(String(x.id))??null;const voucher=voucherId===null?undefined:vouchers.get(voucherId);return { id:String(x.id),entryDate:x.entry_date,vehicleId:String(x.vehicle_id),sourceType:x.source_type,oilShopId:x.oil_shop_id?String(x.oil_shop_id):"",oilProductId:String(x.oil_product_id),liters:num(x.liters),ratePerLiter:num(x.rate_per_liter),totalAmount:num(x.total_amount),billNo:x.bill_no??"",odometer:x.odometer==null?null:num(x.odometer),nextOilChangeDate:x.next_oil_change_date??"",remarks:x.remarks??"",attachedVoucherId:voucherId,attachedVoucherNo:voucher?.expense_no??"",attachedVoucherDate:voucher?.expense_date??""}; }));
    setSales((saleResult.data ?? []).map((x) => ({ id:String(x.id),saleDate:x.sale_date,oilProductId:String(x.oil_product_id),vehicleNo:x.vehicle_no,partyId:x.party_id?String(x.party_id):"",ownerName:x.owner_name??"",phone:x.phone??"",liters:num(x.liters),saleRatePerLiter:num(x.sale_rate_per_liter),totalAmount:num(x.total_amount),receivedAmount:num(x.received_amount),remainingAmount:num(x.remaining_amount),saleStatus:x.sale_status,paymentMethod:x.payment_method??"",remarks:x.remarks??"" })));
    setSupplierBills((supplierBillResult.data ?? []).map(x=>({id:String(x.id),oilShopId:String(x.oil_shop_id),sourceType:x.source_type as OilSupplierBill["sourceType"],sourceId:String(x.oil_purchase_id??x.oil_vehicle_entry_id),billDate:x.bill_date,billNo:x.bill_no??"",amount:num(x.amount),paidAmount:num(x.paid_amount),remainingAmount:num(x.remaining_amount),paymentStatus:x.payment_status})));
    setLoading(false);
  }, [t]);
  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  const stock = useMemo(() => new Map(products.map((p) => [p.id, movements.filter((m) => m.oilProductId===p.id).reduce((sum,m)=>sum+m.litersIn-m.litersOut,0)])), [products,movements]);
  const totalStock = [...stock.values()].reduce((sum,value)=>sum+value,0);
  const vehicleExpense = vehicleEntries.reduce((sum,row)=>sum+row.totalAmount,0);
  const externalSales = sales.reduce((sum,row)=>sum+row.totalAmount,0);
  const run = async (action: () => PromiseLike<{ error: { message?: string; code?: string; details?: string; hint?: string } | null }>, successKey: string) => {
    if (lock.current) return false; lock.current=true; setBusy(true); setError("");
    try { const result=await action(); if(result.error){console.error("Oil operation failed",result.error);setError(t("oil.messages.saveFailed"));return false;} await load(); alert(t(successKey)); return true; }
    finally { lock.current=false;setBusy(false); }
  };
  const printLegacy = (title: string, body: string) => { const w=window.open("","_blank","width=1100,height=800"); if(!w){alert(t("oil.messages.popup"));return;} void writeAddaBrandedPrintDocument(w, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head><title>${escapeHtml(title)}</title><style>@page{size:A4;margin:12mm}body{font-family:Arial;color:#0f172a}h1{border-bottom:3px solid #2563eb;padding-bottom:8px}.meta{color:#334155}table{width:100%;border-collapse:collapse;margin-top:16px}th,td{border:1px solid #94a3b8;padding:7px;text-align:start}th{background:#2563eb;color:white}.total{font-weight:800;font-size:18px;text-align:end;margin-top:18px}</style></head><body><h1>${PRINT_ADDA_NAME_TOKEN} — ${escapeHtml(title)}</h1>${body}<script>window.onload=()=>{window.focus();window.print()}</script></body></html>`, addaId, language === "ur" ? "ur" : "en"); };
  const print = (title: string, body: string) => modulePrint.open(title, body, () => printLegacy(title, body));

  const externalShops = shops.filter((shop) => shop.shopType === "external_supplier");
  const ownStore = shops.find((shop) => shop.shopType === "adda_owned") ?? null;
  const tabs: Tab[]=["dashboard","shops","account","products","store","vehicle","sales","stock","history"];
  if (loading) return <div className="rounded-xl border bg-white p-8 font-bold text-slate-900">{t("oil.loading")}</div>;
  return <main dir={dir} className="ut-module-page space-y-5">
    <header className="rounded-2xl border border-blue-100 bg-white p-4 shadow-sm sm:p-5"><ModulePageHeading icon="oil" accent="green" title={t("oil.title")} description={t("oil.description")} /></header>
    <nav className="flex gap-2 overflow-x-auto rounded-xl border bg-white p-3" aria-label={t("oil.title")}>{tabs.map((name)=>{const needsStore=name==="sales"||name==="stock";const disabled=needsStore&&!ownStore?.isActive;return <button key={name} type="button" disabled={disabled} title={disabled?t("oil.store.disabledNotice"):undefined} onClick={()=>setTab(name)} className={`whitespace-nowrap rounded-lg px-4 py-2.5 font-bold disabled:cursor-not-allowed disabled:border-slate-300 disabled:bg-white disabled:text-amber-700 ${tab===name?"bg-blue-600 text-white":"border border-slate-300 bg-white text-slate-900"}`}>{t(`oil.tabs.${name}`)}</button>})}</nav>
    {error&&<div role="alert" className="rounded-lg border border-red-300 bg-white p-4 font-bold text-red-700">{error}</div>}
    {tab==="dashboard"&&<Dashboard cards={[ ["shops",externalShops.length],["products",products.length],["stock",totalStock],["vehicleExpense",vehicleExpense],["externalSales",externalSales],["supplierBills",supplierBills.length] ]} t={t}/>}
    {tab==="shops"&&<Shops shops={externalShops} purchases={purchases} vehicleEntries={vehicleEntries} addaId={addaId} busy={busy} t={t} run={run} print={print}/>}
    {tab==="account"&&<OilSupplierAccount shops={externalShops} onChanged={load} onPrint={(title,body,fallback)=>modulePrint.open(title,body,fallback)}/>}
    {tab==="products"&&<Products products={products} addaId={addaId} busy={busy} t={t} run={run}/>}
    {tab==="store"&&<><OwnStore store={ownStore} suppliers={externalShops} products={products} purchases={purchases} stock={stock} addaId={addaId} busy={busy} t={t} run={run} print={print}/><SupplierLiabilitySummary bills={supplierBills.filter(b=>b.sourceType==="oil_purchase")} t={t}/></>}
    {tab==="vehicle"&&<><VehicleOil vehicles={vehicles} shops={externalShops} products={products} stock={stock} entries={vehicleEntries} ownStoreEnabled={Boolean(ownStore?.isActive)} busy={busy} t={t} run={run} print={print} manualSourceEditContext={manualSourceEditContext}/><SupplierLiabilitySummary bills={supplierBills.filter(b=>b.sourceType==="oil_vehicle_entry")} t={t}/></>}
    {tab==="sales"&&<Sales products={products} parties={parties} stock={stock} sales={sales} busy={busy} t={t} run={run} print={print}/>}
    {tab==="stock"&&<StockLedger products={products} movements={movements} t={t} print={print}/>}
    {tab==="history"&&<VehicleHistory vehicles={vehicles} products={products} entries={vehicleEntries} t={t} print={print}/>}
    {modulePrint.dialog}
  </main>;
}

type T = (key:string)=>string;
type OilResult = { error: { message?: string; code?: string; details?: string; hint?: string } | null };
type Run = (action:()=>PromiseLike<OilResult>,successKey:string)=>Promise<boolean>;
type Print = (title:string,body:string)=>void;
const oilPrintDetails = (t:T, fields:Array<[string,unknown]>) => `<div class="details">${fields.filter(([,value])=>value!==null&&value!==undefined&&value!=="").map(([label,value])=>`<div><strong>${escapeHtml(label)}:</strong> ${escapeHtml(String(value))}</div>`).join("")}</div>`;
function SupplierLiabilitySummary({bills,t}:{bills:OilSupplierBill[];t:T}){return <Card><h2 className="text-xl font-black">{t("oil.account.bills")}</h2><Rows headers={[t("oil.fields.date"),t("oil.fields.billNo"),t("oil.fields.amount"),t("oil.fields.paidAmount"),t("oil.fields.remaining"),t("oil.fields.status")]} rows={bills.map(b=>[b.billDate,b.billNo||"-",money(b.amount),money(b.paidAmount),money(b.remainingAmount),t(`oil.options.${b.paymentStatus}`)])}/></Card>}
const Field=({name,children}:{name:string;children:React.ReactNode})=><label className={label}><span className="block">{name}</span>{children}</label>;
const Card=({children}:{children:React.ReactNode})=><section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">{children}</section>;
const Button=({children,...props}:React.ButtonHTMLAttributes<HTMLButtonElement>)=><button {...props} className={`rounded-lg bg-blue-600 px-5 py-2.5 font-bold text-white disabled:cursor-not-allowed disabled:bg-blue-400 ${props.className??""}`}>{children}</button>;

function Dashboard({cards,t}:{cards:Array<[string,number]>;t:T}) { return <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">{cards.map(([key,value])=><Card key={key}><p className="font-bold text-slate-600">{t(`oil.dashboard.${key}`)}</p><p dir="ltr" className="mt-2 text-3xl font-black text-blue-700">{key.includes("Expense")||key.includes("Sales")?money(value):value.toLocaleString("en-PK")}</p></Card>)}</div>; }

function Shops({shops,purchases,vehicleEntries,addaId,busy,t,run,print}:{shops:OilShop[];purchases:OilPurchase[];vehicleEntries:OilVehicleEntry[];addaId:string;busy:boolean;t:T;run:Run;print:Print}) {
  const empty={shopName:"",ownerName:"",phone:"",address:"",openingBalance:"0"}; const [form,setForm]=useState(empty); const [id,setId]=useState(""); const [search,setSearch]=useState("");
  const list=shops.filter(x=>[x.shopName,x.ownerName,x.phone].join(" ").toLowerCase().includes(search.toLowerCase()));
  const save=()=>run(()=>id?supabase.from("oil_shops").update({shop_name:form.shopName.trim(),owner_name:form.ownerName||null,phone:form.phone||null,address:form.address||null,opening_balance:num(form.openingBalance)}).eq("id",id).eq("shop_type","external_supplier"):supabase.from("oil_shops").insert({adda_id:addaId,shop_name:form.shopName.trim(),shop_type:"external_supplier",owner_name:form.ownerName||null,phone:form.phone||null,address:form.address||null,opening_balance:num(form.openingBalance)}),"oil.messages.saved").then(ok=>{if(ok){setForm(empty);setId("");}});
  return <div className="space-y-4"><Card><h2 className="text-xl font-black">{t("oil.shops.title")}</h2><p className="mt-1 font-semibold text-slate-700">{t("oil.shops.description")}</p><div className="mt-4 grid gap-3 md:grid-cols-3">
  <Field name={t("oil.fields.shopName")}><VoiceTypingField fieldLabel={t("oil.fields.shopName")} mode="text"><input className={input} value={form.shopName} onChange={e=>setForm({...form,shopName:e.target.value})}/></VoiceTypingField></Field>

  <Field name={t("oil.fields.ownerName")}><VoiceTypingField fieldLabel={t("oil.fields.ownerName")} mode="text"><input className={input} value={form.ownerName} onChange={e=>setForm({...form,ownerName:e.target.value})}/></VoiceTypingField></Field>

  <Field name={t("oil.fields.phone")}><VoiceTypingField fieldLabel={t("oil.fields.phone")} mode="phone"><input dir="ltr" className={input} value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></VoiceTypingField></Field>

  <Field name={t("oil.fields.address")}><VoiceTypingField fieldLabel={t("oil.fields.address")} mode="text"><input className={input} value={form.address} onChange={e=>setForm({...form,address:e.target.value})}/></VoiceTypingField></Field>

  <Field name={t("oil.fields.openingBalance")}><VoiceTypingField fieldLabel={t("oil.fields.openingBalance")} mode="amount"><input type="number" dir="ltr" className={input} value={form.openingBalance} onChange={e=>setForm({...form,openingBalance:e.target.value})}/></VoiceTypingField></Field>
  </div><div className="mt-4 flex gap-2"><Button disabled={busy||!form.shopName.trim()||!addaId} onClick={()=>void save()}>{t(id?"common.actions.update":"common.actions.save")}</Button>{id&&<button className="rounded-lg border px-5 font-bold" onClick={()=>{setId("");setForm(empty)}}>{t("common.actions.cancel")}</button>}</div></Card><Card>
  <div className="flex gap-3"><VoiceTypingField fieldLabel={t("oil.search")} mode="text"><input className={input} placeholder={t("oil.search")} value={search} onChange={e=>setSearch(e.target.value)}/></VoiceTypingField><Button onClick={()=>print(t("oil.shops.title"),`<table><tr><th>${escapeHtml(t("oil.fields.shopName"))}</th><th>${escapeHtml(t("oil.fields.ownerName"))}</th><th>${escapeHtml(t("oil.fields.openingBalance"))}</th></tr>${list.map(x=>`<tr><td>${escapeHtml(x.shopName)}</td><td>${escapeHtml(x.ownerName)}</td><td>${escapeHtml(money(x.openingBalance))}</td></tr>`).join("")}</table>`)}>{t("common.actions.print")}</Button></div>
  <Rows headers={[t("oil.fields.shopName"),t("oil.fields.ownerName"),t("oil.fields.openingBalance"),t("oil.fields.totalBills"),t("oil.fields.paidAmount"),t("oil.fields.remaining"),t("common.actions.title")]} rows={list.map(x=>{const stockBills=purchases.filter(p=>p.oilShopId===x.id);const directVehicleBills=vehicleEntries.filter(entry=>entry.sourceType==="external_shop"&&entry.oilShopId===x.id);const billTotal=stockBills.reduce((sum,p)=>sum+p.totalAmount,0)+directVehicleBills.reduce((sum,entry)=>sum+entry.totalAmount,0);const paid=stockBills.reduce((sum,p)=>sum+p.paidAmount,0);return [x.shopName,x.ownerName||"-",money(x.openingBalance),money(billTotal),money(paid),money(x.openingBalance+billTotal-paid),<div key={x.id} className="flex gap-2"><button className="font-bold text-blue-700" onClick={()=>{setId(x.id);setForm({shopName:x.shopName,ownerName:x.ownerName,phone:x.phone,address:x.address,openingBalance:String(x.openingBalance)})}}>{t("common.actions.edit")}</button><button className="font-bold text-red-700" onClick={()=>window.confirm(t("oil.messages.confirmDelete"))&&void run(()=>supabase.from("oil_shops").delete().eq("id",x.id).eq("shop_type","external_supplier"),"oil.messages.deleted")}>{t("common.actions.delete")}</button></div>]})}/></Card><Card><h3 className="text-lg font-black">{t("oil.shops.accountNoticeTitle")}</h3><p className="mt-1 font-semibold text-slate-700">{t("oil.shops.accountNotice")}</p></Card></div>;
}

function Products({products,addaId,busy,t,run}:{products:OilProduct[];addaId:string;busy:boolean;t:T;run:Run}) { const empty={oilType:"",brand:"",grade:""};const[form,setForm]=useState(empty);const[id,setId]=useState("");const save=()=>run(()=>id?supabase.from("oil_products").update({oil_type:form.oilType.trim(),brand:form.brand.trim(),grade:form.grade.trim()}).eq("id",id):supabase.from("oil_products").insert({adda_id:addaId,oil_type:form.oilType.trim(),brand:form.brand.trim(),grade:form.grade.trim()}),"oil.messages.saved").then(ok=>{if(ok){setForm(empty);setId("")}});return <div className="space-y-4"><Card><h2 className="text-xl font-black">{t("oil.products.title")}</h2><div className="mt-4 grid gap-3 md:grid-cols-3">
<Field name={t("oil.fields.oilType")}><VoiceTypingField fieldLabel={t("oil.fields.oilType")} mode="text"><input className={input} value={form.oilType} onChange={e=>setForm({...form,oilType:e.target.value})}/></VoiceTypingField></Field>

<Field name={t("oil.fields.brand")}><VoiceTypingField fieldLabel={t("oil.fields.brand")} mode="text"><input className={input} value={form.brand} onChange={e=>setForm({...form,brand:e.target.value})}/></VoiceTypingField></Field>

<Field name={t("oil.fields.grade")}><VoiceTypingField fieldLabel={t("oil.fields.grade")} mode="text"><input className={input} value={form.grade} onChange={e=>setForm({...form,grade:e.target.value})}/></VoiceTypingField></Field>
</div><Button className="mt-4" disabled={busy||!form.oilType.trim()} onClick={()=>void save()}>{t(id?"common.actions.update":"common.actions.save")}</Button></Card><Card><Rows headers={[t("oil.fields.oilType"),t("oil.fields.brand"),t("oil.fields.grade"),t("oil.fields.status"),t("common.actions.title")]} rows={products.map(x=>[x.oilType,x.brand||"-",x.grade||"-",x.isActive?t("oil.options.active"):t("oil.options.inactive"),<div key={x.id} className="flex gap-2"><button className="font-bold text-blue-700" onClick={()=>{setId(x.id);setForm({oilType:x.oilType,brand:x.brand,grade:x.grade})}}>{t("common.actions.edit")}</button><button className="font-bold text-amber-700" onClick={()=>void run(()=>supabase.from("oil_products").update({is_active:!x.isActive}).eq("id",x.id),"oil.messages.saved")}>{x.isActive?t("oil.actions.deactivate"):t("oil.actions.activate")}</button></div>])}/></Card></div> }

function OwnStore({store,suppliers,products,purchases,stock,addaId,busy,t,run,print}:{store:OilShop|null;suppliers:OilShop[];products:OilProduct[];purchases:OilPurchase[];stock:Map<string,number>;addaId:string;busy:boolean;t:T;run:Run;print:Print}) {
  const [name,setName]=useState(store?.shopName??"");
  useEffect(()=>{const timer=window.setTimeout(()=>setName(store?.shopName??""),0);return()=>window.clearTimeout(timer)},[store]);
  const saveStore=()=>run(()=>store?supabase.from("oil_shops").update({shop_name:name.trim(),is_active:true}).eq("id",store.id).eq("shop_type","adda_owned"):supabase.from("oil_shops").insert({adda_id:addaId,shop_name:name.trim(),shop_type:"adda_owned",opening_balance:0,is_active:true}),"oil.messages.saved");
  const stockRows=products.map(product=>[productLabel(product),`${num(stock.get(product.id)).toLocaleString("en-PK")} L`]);
  return <div className="space-y-4"><Card><h2 className="text-xl font-black">{t("oil.store.title")}</h2><p className="mt-1 font-semibold text-slate-700">{t("oil.store.description")}</p>
  <div className="mt-4 flex flex-col gap-3 sm:flex-row"><VoiceTypingField fieldLabel={t("oil.store.name")} mode="text"><input className={input} value={name} onChange={e=>setName(e.target.value)} placeholder={t("oil.store.name")}/></VoiceTypingField><Button disabled={busy||!name.trim()||!addaId} onClick={()=>void saveStore()}>{store?t("common.actions.update"):t("oil.store.enable")}</Button>{store&&<button className="rounded-lg border border-slate-300 bg-white px-5 font-bold text-slate-900" onClick={()=>void run(()=>supabase.from("oil_shops").update({is_active:!store.isActive}).eq("id",store.id).eq("shop_type","adda_owned"),"oil.messages.saved")}>{store.isActive?t("oil.store.disable"):t("oil.store.enable")}</button>}</div>
  </Card>{!store?.isActive?<Card><p className="font-bold text-amber-700">{t("oil.store.disabledNotice")}</p></Card>:<><Card><div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><div><p className="font-bold text-slate-600">{t("oil.dashboard.stock")}</p><p dir="ltr" className="text-2xl font-black text-blue-700">{[...stock.values()].reduce((sum,value)=>sum+value,0).toLocaleString("en-PK")} L</p></div><div><p className="font-bold text-slate-600">{t("oil.store.productsInStock")}</p><p className="text-2xl font-black text-blue-700">{[...stock.values()].filter(value=>value>0).length}</p></div><div><p className="font-bold text-slate-600">{t("oil.store.purchaseCount")}</p><p className="text-2xl font-black text-blue-700">{purchases.length}</p></div><div><p className="font-bold text-slate-600">{t("oil.store.inventoryNote")}</p><p className="font-semibold text-slate-700">{t("oil.store.ledgerDerived")}</p></div></div><Rows headers={[t("oil.fields.oilProduct"),t("oil.fields.availableStock")]} rows={stockRows}/></Card><Purchases shops={suppliers} products={products} purchases={purchases} busy={busy} t={t} run={run} print={print}/></>}</div>;
}

function Purchases({shops,products,purchases,busy,t,run,print}:{shops:OilShop[];products:OilProduct[];purchases:OilPurchase[];busy:boolean;t:T;run:Run;print:Print}) { const empty={shopId:"",date:today(),billNo:"",remarks:""};const[form,setForm]=useState(empty);const[lines,setLines]=useState<PurchaseLine[]>([line()]);const total=lines.reduce((s,x)=>s+num(x.liters)*num(x.ratePerLiter),0);const save=()=>run(()=>supabase.rpc("save_oil_purchase_with_items",{p_purchase_id:null,p_oil_shop_id:form.shopId,p_purchase_date:form.date,p_bill_no:form.billNo||null,p_paid_amount:0,p_remarks:form.remarks||null,p_items:lines.map(x=>({oil_product_id:x.oilProductId,liters:num(x.liters),rate_per_liter:num(x.ratePerLiter),batch_reference:x.batchReference||null}))}),"oil.messages.saved").then(ok=>{if(ok){setForm(empty);setLines([line()])}});return <div className="space-y-4"><Card><h2 className="text-xl font-black">{t("oil.purchases.title")}</h2><div className="mt-4 grid gap-3 md:grid-cols-3"><Field name={t("oil.fields.oilShop")}><select className={input} value={form.shopId} onChange={e=>setForm({...form,shopId:e.target.value})}><option value="">{t("oil.select")}</option>{shops.filter(x=>x.isActive).map(x=><option key={x.id} value={x.id}>{x.shopName}</option>)}</select></Field>
<Field name={t("oil.fields.purchaseDate")}><VoiceTypingField fieldLabel={t("oil.fields.purchaseDate")} mode="date"><input type="date" className={input} value={form.date} onChange={e=>setForm({...form,date:e.target.value})}/></VoiceTypingField></Field>

<Field name={t("oil.fields.billNo")}><VoiceTypingField fieldLabel={t("oil.fields.billNo")} mode="identifier"><input className={input} value={form.billNo} onChange={e=>setForm({...form,billNo:e.target.value})}/></VoiceTypingField></Field>
</div><div className="mt-4 space-y-2">{lines.map((x,index)=>

<div key={x.key} className="grid gap-2 rounded-lg border p-3 md:grid-cols-5"><select aria-label={t("oil.fields.oilProduct")} className={input} value={x.oilProductId} onChange={e=>setLines(lines.map(y=>y.key===x.key?{...y,oilProductId:e.target.value}:y))}><option value="">{t("oil.fields.oilProduct")}</option>{products.filter(p=>p.isActive).map(p=><option key={p.id} value={p.id}>{productLabel(p)}</option>)}</select><VoiceTypingField fieldLabel={t("oil.fields.liters")} mode="number"><input aria-label={t("oil.fields.liters")} type="number" min="0" className={input} placeholder={t("oil.fields.liters")} value={x.liters} onChange={e=>setLines(lines.map(y=>y.key===x.key?{...y,liters:e.target.value}:y))}/></VoiceTypingField><VoiceTypingField fieldLabel={t("oil.fields.rate")} mode="amount"><input aria-label={t("oil.fields.rate")} type="number" min="0" className={input} placeholder={t("oil.fields.rate")} value={x.ratePerLiter} onChange={e=>setLines(lines.map(y=>y.key===x.key?{...y,ratePerLiter:e.target.value}:y))}/></VoiceTypingField><div dir="ltr" className="rounded-lg border bg-blue-50 p-3 font-black">{money(num(x.liters)*num(x.ratePerLiter))}</div><button aria-label={t("common.actions.delete")} className="font-bold text-red-700" disabled={lines.length===1} onClick={()=>setLines(lines.filter(y=>y.key!==x.key))}>×</button>{index===lines.length-1&&
<VoiceTypingField fieldLabel={t("oil.fields.batch")} mode="text"><input className={`${input} md:col-span-4`} placeholder={t("oil.fields.batch")} value={x.batchReference} onChange={e=>setLines(lines.map(y=>y.key===x.key?{...y,batchReference:e.target.value}:y))}/></VoiceTypingField>
}</div>)}</div><button className="mt-3 rounded-lg border border-blue-600 px-4 py-2 font-bold text-blue-700" onClick={()=>setLines([...lines,line()])}>+ {t("oil.actions.addLine")}</button><p dir="ltr" className="mt-4 text-xl font-black text-blue-700">{t("oil.fields.grandTotal")}: {money(total)}</p><Field name={t("oil.fields.remarks")}><VoiceTypingField fieldLabel={t("oil.fields.remarks")} value={form.remarks} onValueChange={remarks=>setForm(current=>({...current,remarks}))} contextKey={form.shopId}><textarea className={input} value={form.remarks} onChange={e=>setForm({...form,remarks:e.target.value})}/></VoiceTypingField></Field><Button className="mt-4" disabled={busy||!form.shopId||!form.date||total<=0||lines.some(x=>!x.oilProductId||num(x.liters)<=0||num(x.ratePerLiter)<0)} onClick={()=>void save()}>{t("common.actions.save")}</Button></Card><Card><Rows headers={[t("oil.fields.purchaseDate"),t("oil.fields.oilShop"),t("oil.fields.billNo"),t("oil.fields.grandTotal"),t("oil.fields.status"),t("common.actions.title")]} rows={purchases.map(x=>[x.purchaseDate,x.shopName,x.billNo||"-",money(x.totalAmount),t(`oil.options.${x.paymentStatus}`),<button key={x.id} className="font-bold text-blue-700" onClick={()=>print(t("oil.print.purchase"),`${oilPrintDetails(t,[[t("oil.fields.purchaseDate"),x.purchaseDate],[t("oil.fields.oilShop"),x.shopName],[t("oil.fields.billNo"),x.billNo],[t("oil.fields.remarks"),x.remarks]])}<table><tr><th>${escapeHtml(t("oil.fields.oilProduct"))}</th><th>${escapeHtml(t("oil.fields.liters"))}</th><th>${escapeHtml(t("oil.fields.rate"))}</th><th>${escapeHtml(t("oil.fields.amount"))}</th></tr>${x.items.map(i=>`<tr><td>${escapeHtml(productLabel(products.find(p=>p.id===i.oilProductId)))}</td><td>${escapeHtml(i.liters)}</td><td>${escapeHtml(i.ratePerLiter)}</td><td>${escapeHtml(money(num(i.liters)*num(i.ratePerLiter)))}</td></tr>`).join("")}</table><p class="total">${escapeHtml(money(x.totalAmount))}</p>`)}>{t("common.actions.print")}</button>])}/></Card></div> }

function VehicleOil({vehicles,shops,products,stock,entries,ownStoreEnabled,busy,t,run,print,manualSourceEditContext}:{vehicles:VehicleOption[];shops:OilShop[];products:OilProduct[];stock:Map<string,number>;entries:OilVehicleEntry[];ownStoreEnabled:boolean;busy:boolean;t:T;run:Run;print:Print;manualSourceEditContext:ManualVoucherSourceEditContext|null}) {
  type Form = {date:string;vehicleId:string;sourceType:OilVehicleEntry["sourceType"];shopId:string;productId:string;liters:string;rate:string;billNo:string;odometer:string;nextDate:string;remarks:string};
  const empty:Form = {date:today(),vehicleId:"",sourceType:"external_shop",shopId:"",productId:"",liters:"",rate:"",billNo:"",odometer:"",nextDate:"",remarks:""};
  const [f,setF] = useState<Form>(empty);
  const [editingId,setEditingId] = useState<string|null>(null);
  const manualSourceRouteHandledRef = useRef(false);
  const total = num(f.liters)*num(f.rate);

  useEffect(() => {
    if (!manualSourceEditContext || manualSourceRouteHandledRef.current) return;
    manualSourceRouteHandledRef.current = true;
    const timer = window.setTimeout(() => {
      const entry = entries.find((candidate) => candidate.id === manualSourceEditContext.sourceEntryId);
      if (!entry || entry.attachedVoucherId !== manualSourceEditContext.voucherId) {
        alert(t("oil.messages.manualSourceUnavailable"));
        return;
      }
      setEditingId(entry.id);
      setF({
        date:entry.entryDate,
        vehicleId:entry.vehicleId,
        sourceType:entry.sourceType,
        shopId:entry.oilShopId,
        productId:entry.oilProductId,
        liters:String(entry.liters),
        rate:String(entry.ratePerLiter),
        billNo:entry.billNo,
        odometer:entry.odometer===null?"":String(entry.odometer),
        nextDate:entry.nextOilChangeDate,
        remarks:entry.remarks,
      });
    }, 0);
    return () => window.clearTimeout(timer);
  },[entries,manualSourceEditContext,t]);

  const cancel = () => {
    if (manualSourceEditContext && editingId === manualSourceEditContext.sourceEntryId) {
      returnToManualVoucherAfterSourceEdit(manualSourceEditContext);
      return;
    }
    setEditingId(null);
    setF(empty);
  };

  const save = async () => {
    const isManualSourceEdit = Boolean(
      manualSourceEditContext && editingId === manualSourceEditContext.sourceEntryId
    );
    const payload = {
      p_entry_id:editingId,
      p_entry_date:f.date,
      p_vehicle_id:f.vehicleId,
      p_source_type:f.sourceType,
      p_oil_shop_id:f.sourceType==="external_shop"?f.shopId:null,
      p_oil_product_id:f.productId,
      p_liters:num(f.liters),
      p_rate_per_liter:num(f.rate),
      p_bill_no:f.billNo||null,
      p_odometer:f.odometer?num(f.odometer):null,
      p_next_oil_change_date:f.nextDate||null,
      p_remarks:f.remarks||null,
    };
    const saved = isManualSourceEdit
      ? await run(() => supabase.rpc("save_manual_voucher_oil_source_entry", {
          p_voucher_id:manualSourceEditContext!.voucherId,
          ...payload,
        }),"oil.messages.updated")
      : await run(() => supabase.rpc("save_oil_vehicle_entry",payload),editingId?"oil.messages.updated":"oil.messages.saved");
    if (!saved) return;
    if (isManualSourceEdit && manualSourceEditContext) {
      returnToManualVoucherAfterSourceEdit(manualSourceEditContext);
      return;
    }
    setEditingId(null);
    setF(empty);
  };

  return <div className="space-y-4">
    <Card>
      <h2 className="text-xl font-black">{t("oil.vehicle.title")}</h2>
      <p className="mt-1 font-semibold text-slate-700">{t("oil.vehicle.description")}</p>
      {editingId&&<p className="mt-3 rounded-lg border border-amber-300 bg-amber-50 p-3 font-bold text-amber-900">{t("oil.vehicle.editingNotice")}</p>}
      <div className="mt-4 grid gap-3 md:grid-cols-4">

        <Field name={t("oil.fields.date")}><VoiceTypingField fieldLabel={t("oil.fields.date")} mode="date"><input type="date" className={input} value={f.date} onChange={e=>setF({...f,date:e.target.value})}/></VoiceTypingField></Field>

        <Field name={t("oil.fields.vehicle")}><select className={input} value={f.vehicleId} onChange={e=>setF({...f,vehicleId:e.target.value})}><option value="">{t("oil.select")}</option>{vehicles.map(x=><option key={x.id} value={x.id}>{x.vehicleNo}</option>)}</select></Field>
        <Field name={t("oil.fields.source")}><select className={input} value={f.sourceType} onChange={e=>setF({...f,sourceType:e.target.value as OilVehicleEntry["sourceType"],shopId:""})}><option value="external_shop">{t("oil.options.externalShop")}</option>{ownStoreEnabled&&<option value="adda_stock">{t("oil.options.addaStock")}</option>}</select></Field>
        {f.sourceType==="external_shop"&&<Field name={t("oil.fields.oilShop")}><select className={input} value={f.shopId} onChange={e=>setF({...f,shopId:e.target.value})}><option value="">{t("oil.select")}</option>{shops.filter(x=>x.isActive).map(x=><option key={x.id} value={x.id}>{x.shopName}</option>)}</select></Field>}
        <Field name={t("oil.fields.oilProduct")}><select className={input} value={f.productId} onChange={e=>setF({...f,productId:e.target.value})}><option value="">{t("oil.select")}</option>{products.filter(x=>x.isActive).map(x=><option key={x.id} value={x.id}>{productLabel(x)}</option>)}</select></Field>
        {f.sourceType==="adda_stock"&&<div className="rounded-lg border border-blue-300 bg-white p-3 font-bold text-blue-800">{t("oil.fields.availableStock")}: <span dir="ltr">{num(stock.get(f.productId)).toLocaleString("en-PK")} L</span></div>}

        <Field name={t("oil.fields.liters")}><VoiceTypingField fieldLabel={t("oil.fields.liters")} mode="number"><input type="number" min="0" className={input} value={f.liters} onChange={e=>setF({...f,liters:e.target.value})}/></VoiceTypingField></Field>


        <Field name={t("oil.fields.rate")}><VoiceTypingField fieldLabel={t("oil.fields.rate")} mode="amount"><input type="number" min="0" className={input} value={f.rate} onChange={e=>setF({...f,rate:e.target.value})}/></VoiceTypingField></Field>

        <Field name={t("oil.fields.amount")}><div dir="ltr" className={`${input} font-black`}>{money(total)}</div></Field>

        <Field name={t("oil.fields.billNo")}><VoiceTypingField fieldLabel={t("oil.fields.billNo")} mode="identifier"><input className={input} value={f.billNo} onChange={e=>setF({...f,billNo:e.target.value})}/></VoiceTypingField></Field>


        <Field name={t("oil.fields.odometer")}><VoiceTypingField fieldLabel={t("oil.fields.odometer")} mode="number"><input type="number" min="0" className={input} value={f.odometer} onChange={e=>setF({...f,odometer:e.target.value})}/></VoiceTypingField></Field>


        <Field name={t("oil.fields.nextChange")}><VoiceTypingField fieldLabel={t("oil.fields.nextChange")} mode="date"><input type="date" className={input} value={f.nextDate} onChange={e=>setF({...f,nextDate:e.target.value})}/></VoiceTypingField></Field>

      </div>
      {!ownStoreEnabled&&<p className="mt-3 font-semibold text-amber-700">{t("oil.vehicle.storeUnavailable")}</p>}
      <Field name={t("oil.fields.remarks")}><VoiceTypingField fieldLabel={t("oil.fields.remarks")} value={f.remarks} onValueChange={remarks=>setF(current=>({...current,remarks}))} contextKey={f.vehicleId}><textarea className={input} value={f.remarks} onChange={e=>setF({...f,remarks:e.target.value})}/></VoiceTypingField></Field>
      <div className="mt-4 flex flex-wrap gap-3">
        <Button disabled={busy||!f.vehicleId||!f.productId||total<=0||(f.sourceType==="external_shop"&&!f.shopId)||(f.sourceType==="adda_stock"&&!ownStoreEnabled)} onClick={()=>void save()}>{editingId?t("common.actions.update"):t("common.actions.save")}</Button>
        {editingId&&<Button className="bg-slate-600 hover:bg-slate-700" disabled={busy} onClick={cancel}>{t("common.actions.cancel")}</Button>}
      </div>
    </Card>
    <Card><Rows headers={[t("oil.fields.date"),t("oil.fields.vehicle"),t("oil.fields.oilProduct"),t("oil.fields.liters"),t("oil.fields.amount"),t("expenses.oilLink.voucherStatus"),t("common.actions.title")]} rows={entries.map(x=>[
      x.entryDate,
      vehicles.find(v=>v.id===x.vehicleId)?.vehicleNo??"-",
      productLabel(products.find(p=>p.id===x.oilProductId)),
      `${x.liters} L`,money(x.totalAmount),
      x.attachedVoucherId===null?t("expenses.oilLink.notAttached"):`${t("expenses.oilLink.attached")} · ${x.attachedVoucherNo||x.attachedVoucherId} · ${x.attachedVoucherDate||"-"}`,
      <div key={x.id} className="flex gap-3">
        {x.attachedVoucherId===null&&<button type="button" className="font-bold text-blue-700" onClick={()=>{setEditingId(x.id);setF({date:x.entryDate,vehicleId:x.vehicleId,sourceType:x.sourceType,shopId:x.oilShopId,productId:x.oilProductId,liters:String(x.liters),rate:String(x.ratePerLiter),billNo:x.billNo,odometer:x.odometer===null?"":String(x.odometer),nextDate:x.nextOilChangeDate,remarks:x.remarks});}}>{t("common.edit")}</button>}
        <button type="button" className="font-bold text-blue-700" onClick={()=>print(t("oil.print.vehicleEntry"),`${oilPrintDetails(t,[[t("common.date"),x.entryDate],[t("common.vehicle"),vehicles.find(v=>v.id===x.vehicleId)?.vehicleNo],[t("oil.fields.billNo"),x.billNo],[t("oil.fields.oilShop"),shops.find(shop=>shop.id===x.oilShopId)?.shopName],[t("oil.fields.source"),t(`oil.options.${x.sourceType==="adda_stock"?"addaStock":"externalShop"}`)],[t("oil.fields.odometer"),x.odometer],[t("oil.fields.nextChange"),x.nextOilChangeDate],[t("expenses.oilLink.voucherStatus"),x.attachedVoucherId===null?t("expenses.oilLink.notAttached"):`${t("expenses.oilLink.attached")} · ${t("expenses.oilLink.voucherNo")}: ${x.attachedVoucherNo||x.attachedVoucherId} · ${t("expenses.oilLink.voucherDate")}: ${x.attachedVoucherDate||"-"}`],[t("oil.fields.remarks"),x.remarks]])}<table><tr><th>${escapeHtml(t("oil.fields.oilProduct"))}</th><th>${escapeHtml(t("oil.fields.liters"))}</th><th>${escapeHtml(t("oil.fields.rate"))}</th><th>${escapeHtml(t("oil.fields.amount"))}</th></tr><tr><td>${escapeHtml(productLabel(products.find(p=>p.id===x.oilProductId)))}</td><td>${x.liters}</td><td>${escapeHtml(money(x.ratePerLiter))}</td><td>${escapeHtml(money(x.totalAmount))}</td></tr></table>`)}>{t("common.actions.print")}</button>
      </div>
    ])}/></Card>
  </div>;
}
function Sales({products,parties,stock,sales,busy,t,run,print}:{products:OilProduct[];parties:PartyOption[];stock:Map<string,number>;sales:OilExternalSale[];busy:boolean;t:T;run:Run;print:Print}) { const empty={date:today(),productId:"",vehicleNo:"",partyId:"",ownerName:"",phone:"",liters:"",rate:"",received:"0",method:"cash",remarks:""};const[f,setF]=useState(empty);const total=num(f.liters)*num(f.rate);const save=()=>run(()=>supabase.rpc("save_oil_external_sale",{p_sale_id:null,p_sale_date:f.date,p_oil_product_id:f.productId,p_vehicle_no:f.vehicleNo,p_party_id:f.partyId||null,p_owner_name:f.ownerName||null,p_phone:f.phone||null,p_liters:num(f.liters),p_sale_rate_per_liter:num(f.rate),p_received_amount:num(f.received),p_payment_method:f.method,p_remarks:f.remarks||null}),"oil.messages.saved").then(ok=>ok&&setF(empty));return <div className="space-y-4"><Card><h2 className="text-xl font-black">{t("oil.sales.title")}</h2><div className="mt-4 grid gap-3 md:grid-cols-4">
<Field name={t("oil.fields.date")}><VoiceTypingField fieldLabel={t("oil.fields.date")} mode="date"><input type="date" className={input} value={f.date} onChange={e=>setF({...f,date:e.target.value})}/></VoiceTypingField></Field>

<Field name={t("oil.fields.vehicleNo")}><VoiceTypingField fieldLabel={t("oil.fields.vehicleNo")} mode="identifier"><input className={input} value={f.vehicleNo} onChange={e=>setF({...f,vehicleNo:e.target.value})}/></VoiceTypingField></Field>
<Field name={t("oil.fields.party")}><select className={input} value={f.partyId} onChange={e=>setF({...f,partyId:e.target.value})}><option value="">{t("oil.options.noParty")}</option>{parties.map(x=><option key={x.id} value={x.id}>{x.partyName}</option>)}</select></Field>
<Field name={t("oil.fields.ownerName")}><VoiceTypingField fieldLabel={t("oil.fields.ownerName")} mode="text"><input className={input} value={f.ownerName} onChange={e=>setF({...f,ownerName:e.target.value})}/></VoiceTypingField></Field>

<Field name={t("oil.fields.phone")}><VoiceTypingField fieldLabel={t("oil.fields.phone")} mode="phone"><input className={input} value={f.phone} onChange={e=>setF({...f,phone:e.target.value})}/></VoiceTypingField></Field>
<Field name={t("oil.fields.oilProduct")}><select className={input} value={f.productId} onChange={e=>setF({...f,productId:e.target.value})}><option value="">{t("oil.select")}</option>{products.filter(x=>x.isActive).map(x=><option key={x.id} value={x.id}>{productLabel(x)}</option>)}</select></Field><div className="rounded-lg border border-blue-300 bg-white p-3 font-bold text-blue-800">{t("oil.fields.availableStock")}: <span dir="ltr">{num(stock.get(f.productId)).toLocaleString("en-PK")} L</span></div>
<Field name={t("oil.fields.liters")}><VoiceTypingField fieldLabel={t("oil.fields.liters")} mode="number"><input type="number" min="0" className={input} value={f.liters} onChange={e=>setF({...f,liters:e.target.value})}/></VoiceTypingField></Field>

<Field name={t("oil.fields.rate")}><VoiceTypingField fieldLabel={t("oil.fields.rate")} mode="amount"><input type="number" min="0" className={input} value={f.rate} onChange={e=>setF({...f,rate:e.target.value})}/></VoiceTypingField></Field>
<Field name={t("oil.fields.amount")}><div className={`${input} font-black`}>{money(total)}</div></Field>
<Field name={t("oil.fields.received")}><VoiceTypingField fieldLabel={t("oil.fields.received")} mode="number"><input type="number" min="0" className={input} value={f.received} onChange={e=>setF({...f,received:e.target.value})}/></VoiceTypingField></Field>
<Field name={t("oil.fields.remaining")}><div className={`${input} font-black`}>{money(Math.max(total-num(f.received),0))}</div></Field><Field name={t("oil.fields.paymentMethod")}><select className={input} value={f.method} onChange={e=>setF({...f,method:e.target.value})}><option value="cash">{t("oil.options.cash")}</option><option value="credit">{t("oil.options.credit")}</option></select></Field></div><Field name={t("oil.fields.remarks")}><VoiceTypingField fieldLabel={t("oil.fields.remarks")} value={f.remarks} onValueChange={remarks=>setF(current=>({...current,remarks}))} contextKey={f.vehicleNo}><textarea className={input} value={f.remarks} onChange={e=>setF({...f,remarks:e.target.value})}/></VoiceTypingField></Field><Button className="mt-4" disabled={busy||!f.productId||!f.vehicleNo.trim()||total<=0||num(f.received)>total} onClick={()=>void save()}>{t("common.actions.save")}</Button></Card><Card><Rows headers={[t("oil.fields.date"),t("oil.fields.vehicleNo"),t("oil.fields.oilProduct"),t("oil.fields.amount"),t("oil.fields.remaining"),t("common.actions.title")]} rows={sales.map(x=>[x.saleDate,x.vehicleNo,productLabel(products.find(p=>p.id===x.oilProductId)),money(x.totalAmount),money(x.remainingAmount),<button key={x.id} className="font-bold text-blue-700" onClick={()=>print(t("oil.print.externalSale"),`${oilPrintDetails(t,[[t("common.date"),x.saleDate],[t("oil.fields.vehicleNo"),x.vehicleNo],[t("oil.fields.party"),parties.find(p=>p.id===x.partyId)?.partyName],[t("oil.fields.ownerName"),x.ownerName],[t("oil.fields.phone"),x.phone],[t("oil.fields.paymentMethod"),t(`oil.options.${x.paymentMethod}`)],[t("oil.fields.remarks"),x.remarks]])}<table><tr><th>${escapeHtml(t("oil.fields.oilProduct"))}</th><th>${escapeHtml(t("oil.fields.liters"))}</th><th>${escapeHtml(t("oil.fields.amount"))}</th><th>${escapeHtml(t("oil.fields.received"))}</th><th>${escapeHtml(t("oil.fields.remaining"))}</th></tr><tr><td>${escapeHtml(productLabel(products.find(p=>p.id===x.oilProductId)))}</td><td>${x.liters}</td><td>${escapeHtml(money(x.totalAmount))}</td><td>${escapeHtml(money(x.receivedAmount))}</td><td>${escapeHtml(money(x.remainingAmount))}</td></tr></table>`)}>{t("common.actions.print")}</button>])}/></Card></div> }

function StockLedger({products,movements,t,print}:{products:OilProduct[];movements:OilStockMovement[];t:T;print:Print}) { const[productId,setProductId]=useState("");const[type,setType]=useState("");const[from,setFrom]=useState("");const[to,setTo]=useState("");const rows=movements.filter(x=>(!productId||x.oilProductId===productId)&&(!type||x.movementType===type)&&(!from||x.movementDate>=from)&&(!to||x.movementDate<=to));const display=rows.reduce<{balances:Record<string,number>;items:Array<OilStockMovement & {running:number}>}>((state,x)=>{const running=(state.balances[x.oilProductId]??0)+x.litersIn-x.litersOut;return {balances:{...state.balances,[x.oilProductId]:running},items:[...state.items,{...x,running}]};},{balances:{},items:[]}).items;const body=`${oilPrintDetails(t,[[t("common.fromDate"),from],[t("common.toDate"),to],[t("oil.fields.oilProduct"),productId?productLabel(products.find(product=>product.id===productId)):""],[t("oil.fields.movementType"),type?t(`oil.movement.${type}`):""]])}<table><tr><th>${escapeHtml(t("oil.fields.date"))}</th><th>${escapeHtml(t("oil.fields.oilProduct"))}</th><th>${escapeHtml(t("oil.fields.stockIn"))}</th><th>${escapeHtml(t("oil.fields.stockOut"))}</th><th>${escapeHtml(t("oil.fields.running"))}</th></tr>${display.map(x=>`<tr><td>${x.movementDate}</td><td>${escapeHtml(productLabel(products.find(p=>p.id===x.oilProductId)))}</td><td>${x.litersIn}</td><td>${x.litersOut}</td><td>${x.running}</td></tr>`).join("")}</table>`;return <Card><div className="flex flex-wrap items-center justify-between gap-3"><h2 className="text-xl font-black">{t("oil.stock.title")}</h2><Button onClick={()=>print(t("oil.print.stockLedger"),body)}>{t("common.actions.print")}</Button></div>

<div className="my-4 grid gap-3 md:grid-cols-4"><select className={input} value={productId} onChange={e=>setProductId(e.target.value)}><option value="">{t("oil.options.allProducts")}</option>{products.map(x=><option key={x.id} value={x.id}>{productLabel(x)}</option>)}</select><select className={input} value={type} onChange={e=>setType(e.target.value)}><option value="">{t("oil.options.allMovements")}</option>{["purchase","own_vehicle_issue","external_vehicle_sale","opening_stock","adjustment_in","adjustment_out"].map(x=><option key={x} value={x}>{t(`oil.movement.${x}`)}</option>)}</select><VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input aria-label={t("common.fromDate")} type="date" className={input} value={from} onChange={e=>setFrom(e.target.value)}/></VoiceTypingField><VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input aria-label={t("common.toDate")} type="date" className={input} value={to} onChange={e=>setTo(e.target.value)}/></VoiceTypingField></div>
<Rows headers={[t("oil.fields.date"),t("oil.fields.oilProduct"),t("oil.fields.movementType"),t("oil.fields.stockIn"),t("oil.fields.stockOut"),t("oil.fields.running"),t("oil.fields.reference")]} rows={display.map(x=>[x.movementDate,productLabel(products.find(p=>p.id===x.oilProductId)),t(`oil.movement.${x.movementType}`),x.litersIn,x.litersOut,x.running,x.referenceType])}/></Card> }

function VehicleHistory({vehicles,products,entries,t,print}:{vehicles:VehicleOption[];products:OilProduct[];entries:OilVehicleEntry[];t:T;print:Print}) { const[vehicle,setVehicle]=useState("");const[product,setProduct]=useState("");const[from,setFrom]=useState("");const[to,setTo]=useState("");const rows=entries.filter(x=>(!vehicle||x.vehicleId===vehicle)&&(!product||x.oilProductId===product)&&(!from||x.entryDate>=from)&&(!to||x.entryDate<=to));const body=`${oilPrintDetails(t,[[t("oil.fields.vehicle"),vehicle?vehicles.find(item=>item.id===vehicle)?.vehicleNo:""],[t("oil.fields.oilProduct"),product?productLabel(products.find(item=>item.id===product)):""],[t("common.fromDate"),from],[t("common.toDate"),to]])}<table><tr><th>${escapeHtml(t("oil.fields.date"))}</th><th>${escapeHtml(t("oil.fields.vehicle"))}</th><th>${escapeHtml(t("oil.fields.oilProduct"))}</th><th>${escapeHtml(t("oil.fields.liters"))}</th><th>${escapeHtml(t("oil.fields.amount"))}</th><th>${escapeHtml(t("expenses.oilLink.voucherStatus"))}</th></tr>${rows.map(x=>`<tr><td>${x.entryDate}</td><td>${escapeHtml(vehicles.find(v=>v.id===x.vehicleId)?.vehicleNo??"-")}</td><td>${escapeHtml(productLabel(products.find(p=>p.id===x.oilProductId)))}</td><td>${x.liters}</td><td>${escapeHtml(money(x.totalAmount))}</td><td>${escapeHtml(x.attachedVoucherId===null?t("expenses.oilLink.notAttached"):`${t("expenses.oilLink.attached")} · ${x.attachedVoucherNo||x.attachedVoucherId} · ${x.attachedVoucherDate||"-"}`)}</td></tr>`).join("")}</table>`;return <Card><div className="flex justify-between gap-3"><h2 className="text-xl font-black">{t("oil.history.title")}</h2><Button onClick={()=>print(t("oil.print.vehicleHistory"),body)}>{t("common.actions.print")}</Button></div>

<div className="my-4 grid gap-3 md:grid-cols-4"><select className={input} value={vehicle} onChange={e=>setVehicle(e.target.value)}><option value="">{t("oil.options.allVehicles")}</option>{vehicles.map(x=><option key={x.id} value={x.id}>{x.vehicleNo}</option>)}</select><select className={input} value={product} onChange={e=>setProduct(e.target.value)}><option value="">{t("oil.options.allProducts")}</option>{products.map(x=><option key={x.id} value={x.id}>{productLabel(x)}</option>)}</select><VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><input aria-label={t("common.fromDate")} type="date" className={input} value={from} onChange={e=>setFrom(e.target.value)}/></VoiceTypingField><VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><input aria-label={t("common.toDate")} type="date" className={input} value={to} onChange={e=>setTo(e.target.value)}/></VoiceTypingField></div>
<Rows headers={[t("oil.fields.date"),t("oil.fields.vehicle"),t("oil.fields.oilProduct"),t("oil.fields.liters"),t("oil.fields.rate"),t("oil.fields.amount"),t("oil.fields.source"),t("oil.fields.odometer"),t("oil.fields.nextChange"),t("expenses.oilLink.voucherStatus")]} rows={rows.map(x=>[x.entryDate,vehicles.find(v=>v.id===x.vehicleId)?.vehicleNo??"-",productLabel(products.find(p=>p.id===x.oilProductId)),x.liters,money(x.ratePerLiter),money(x.totalAmount),t(`oil.options.${x.sourceType==="adda_stock"?"addaStock":"externalShop"}`),x.odometer??"-",x.nextOilChangeDate||"-",x.attachedVoucherId===null?t("expenses.oilLink.notAttached"):`${t("expenses.oilLink.attached")} · ${x.attachedVoucherNo||x.attachedVoucherId} · ${x.attachedVoucherDate||"-"}`])}/></Card> }

function Rows({headers,rows}:{headers:string[];rows:React.ReactNode[][]}) { return <div className="mt-4 overflow-x-auto"><table className="min-w-full text-sm"><thead className="bg-blue-600 text-white"><tr>{headers.map(x=><th key={x} className="whitespace-nowrap p-3 text-start">{x}</th>)}</tr></thead><tbody>{rows.map((row,i)=><tr key={i} className="border-b border-slate-200">{row.map((cell,j)=><td key={j} className="whitespace-nowrap p-3 font-medium text-slate-900">{cell}</td>)}</tr>)}</tbody></table>{rows.length===0&&<p className="p-6 text-center font-bold text-slate-700">—</p>}</div> }

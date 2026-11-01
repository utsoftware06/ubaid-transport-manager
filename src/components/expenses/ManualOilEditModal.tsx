"use client";

import { useEffect, useMemo, useState } from "react";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { supabase } from "@/lib/supabase/client";
import type { VoucherOilOption, VoucherOilProductOption, VoucherOilShopOption } from "./VoucherOilSelector";

type Props = {
  voucherId: number;
  entry: VoucherOilOption;
  addaId: string;
  vehicleId: string;
  onClose: () => void;
  onSaved: () => Promise<void>;
  products: VoucherOilProductOption[];
  shops: VoucherOilShopOption[];
};

type Relation<T> = T | T[] | null;
type OilSourceRow = {
  id: string;
  adda_id: string;
  entry_date: string | null;
  vehicle_id: string;
  source_type: "external_shop" | "adda_stock";
  oil_shop_id: string | null;
  oil_product_id: string;
  liters: number | string;
  rate_per_liter: number | string;
  total_amount: number | string;
  bill_no: string | null;
  odometer: number | string | null;
  next_oil_change_date: string | null;
  remarks: string | null;
  oil_products: Relation<{ id: string; adda_id: string; oil_type: string | null; brand: string | null; grade: string | null }>;
  oil_shops: Relation<{ id: string; adda_id: string; shop_name: string | null }>;
};

type FormState = {
  date: string;
  sourceType: "external_shop" | "adda_stock";
  shopId: string;
  productId: string;
  liters: string;
  rate: string;
  billNo: string;
  odometer: string;
  nextDate: string;
  remarks: string;
};

function relationOne<T>(value: Relation<T>): T | null {
  return Array.isArray(value) ? value[0] ?? null : value;
}

function amount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
}

const inputClass = "w-full rounded-lg border border-slate-300 bg-white px-3 py-3 font-semibold text-slate-900";

export default function ManualOilEditModal({
  voucherId,
  entry,
  addaId,
  vehicleId,
  onClose,
  onSaved,
  products,
  shops,
}: Props) {
  const { t, dir } = useLanguage();
  const [form, setForm] = useState<FormState | null>(null);
  const [sourceProduct, setSourceProduct] = useState<VoucherOilProductOption | null>(null);
  const [sourceShop, setSourceShop] = useState<VoucherOilShopOption | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let active = true;
    const load = async () => {
      setLoading(true);
      setErrorMessage("");
      const { data, error } = await supabase
        .from("oil_vehicle_entries")
        .select("id, adda_id, entry_date, vehicle_id, source_type, oil_shop_id, oil_product_id, liters, rate_per_liter, total_amount, bill_no, odometer, next_oil_change_date, remarks, oil_products(id, adda_id, oil_type, brand, grade), oil_shops(id, adda_id, shop_name)")
        .eq("id", entry.id)
        .maybeSingle();
      if (!active) return;
      if (error || !data) {
        setErrorMessage(error?.message ?? t("oil.messages.loadFailed"));
        setLoading(false);
        return;
      }
      const source = data as unknown as OilSourceRow;
      if (source.adda_id !== addaId || source.vehicle_id !== vehicleId) {
        setErrorMessage("The Oil source no longer matches this Manual Voucher's Adda and vehicle.");
        setLoading(false);
        return;
      }
      const product = relationOne(source.oil_products);
      const shop = relationOne(source.oil_shops);
      setSourceProduct(product ? {
        id: product.id,
        addaId: product.adda_id,
        oilType: product.oil_type ?? "-",
        brand: product.brand ?? "",
        grade: product.grade ?? "",
      } : null);
      setSourceShop(shop ? { id: shop.id, addaId: shop.adda_id, shopName: shop.shop_name ?? "-" } : null);
      setForm({
        date: source.entry_date ?? "",
        sourceType: source.source_type,
        shopId: source.oil_shop_id ?? "",
        productId: source.oil_product_id,
        liters: String(source.liters),
        rate: String(source.rate_per_liter),
        billNo: source.bill_no ?? "",
        odometer: source.odometer == null ? "" : String(source.odometer),
        nextDate: source.next_oil_change_date ?? "",
        remarks: source.remarks ?? "",
      });
      setLoading(false);
    };
    void load();
    return () => { active = false; };
  }, [addaId, entry.id, t, vehicleId]);

  const visibleProducts = useMemo(() => {
    const rows = products.filter((product) => !product.addaId || product.addaId === addaId);
    if (sourceProduct && !rows.some((product) => product.id === sourceProduct.id)) rows.push(sourceProduct);
    return rows;
  }, [addaId, products, sourceProduct]);
  const visibleShops = useMemo(() => {
    const rows = shops.filter((shop) => !shop.addaId || shop.addaId === addaId);
    if (sourceShop && !rows.some((shop) => shop.id === sourceShop.id)) rows.push(sourceShop);
    return rows;
  }, [addaId, shops, sourceShop]);
  const liters = Number(form?.liters || 0);
  const rate = Number(form?.rate || 0);
  const total = liters * rate;

  function change<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((current) => current ? { ...current, [key]: value } : current);
  }

  async function save() {
    if (!form || saving) return;
    setErrorMessage("");
    if (!form.date || !form.productId || !Number.isFinite(liters) || liters <= 0 || !Number.isFinite(rate) || rate < 0 || total <= 0) {
      setErrorMessage("Enter a date, product, positive quantity, and valid rate.");
      return;
    }
    if (form.sourceType === "external_shop" && !form.shopId) {
      setErrorMessage("Select the Oil Shop for this external purchase.");
      return;
    }
    setSaving(true);
    let closeAfterSave = false;
    try {
      const { data, error } = await supabase.rpc("save_manual_voucher_oil_source_entry", {
        p_voucher_id: voucherId,
        p_entry_id: entry.id,
        p_entry_date: form.date,
        p_vehicle_id: vehicleId,
        p_source_type: form.sourceType,
        p_oil_shop_id: form.sourceType === "external_shop" ? form.shopId || null : null,
        p_oil_product_id: form.productId,
        p_liters: liters,
        p_rate_per_liter: rate,
        p_bill_no: form.billNo.trim() || null,
        p_odometer: form.odometer ? Number(form.odometer) : null,
        p_next_oil_change_date: form.nextDate || null,
        p_remarks: form.remarks.trim() || null,
      });
      if (error) throw new Error(error.message);
      if (String(data) !== entry.id) throw new Error("Oil edit returned a different source ID.");
      await onSaved();
      closeAfterSave = true;
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : t("oil.messages.updateFailed"));
    } finally {
      setSaving(false);
    }
    if (closeAfterSave) onClose();
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-start justify-center overflow-y-auto bg-slate-950/60 p-3 pt-6 sm:p-6" role="presentation">
      <section role="dialog" aria-modal="true" aria-label={t("oil.vehicle.editingNotice")} dir={dir} className="w-full max-w-4xl rounded-2xl bg-white p-4 shadow-2xl sm:p-6">
        <header className="mb-5 flex items-center justify-between gap-3">
          <div>
            <h2 className="text-xl font-black text-slate-950">{t("oil.vehicle.title")} — {t("common.edit")}</h2>
            <p className="mt-1 font-semibold text-slate-700">{entry.vehicleNo} · {entry.productName}</p>
          </div>
          <button type="button" onClick={onClose} disabled={saving} className="rounded-lg border border-slate-300 px-3 py-2 font-bold text-slate-800 disabled:opacity-50">{t("common.actions.cancel")}</button>
        </header>
        {errorMessage && <p role="alert" className="mb-4 rounded-lg border border-red-300 bg-red-50 p-3 text-sm font-bold text-red-800">{errorMessage}</p>}
        {loading ? (
          <div className="rounded-xl bg-slate-50 p-8 text-center font-bold text-slate-700">{t("common.states.loading")}</div>
        ) : form ? (
          <div className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">

              <VoiceTypingField fieldLabel={t("oil.fields.date")} mode="date"><label className="font-bold text-slate-800">{t("oil.fields.date")}<input type="date" className={`${inputClass} mt-1`} value={form.date} onChange={(event) => change("date", event.target.value)} /></label></VoiceTypingField>

              <label className="font-bold text-slate-800">{t("oil.fields.vehicle")}<input className={`${inputClass} mt-1 bg-slate-100`} value={entry.vehicleNo} readOnly /></label>
              <label className="font-bold text-slate-800">{t("oil.fields.source")}<select className={`${inputClass} mt-1`} value={form.sourceType} onChange={(event) => change("sourceType", event.target.value as FormState["sourceType"])}><option value="external_shop">{t("oil.options.externalShop")}</option><option value="adda_stock">{t("oil.options.addaStock")}</option></select></label>
              {form.sourceType === "external_shop" && <label className="font-bold text-slate-800">{t("oil.fields.oilShop")}<select className={`${inputClass} mt-1`} value={form.shopId} onChange={(event) => change("shopId", event.target.value)}><option value="">{t("oil.select")}</option>{visibleShops.map((shop) => <option key={shop.id} value={shop.id}>{shop.shopName}</option>)}</select></label>}
              <label className="font-bold text-slate-800">{t("oil.fields.oilProduct")}<select className={`${inputClass} mt-1`} value={form.productId} onChange={(event) => change("productId", event.target.value)}><option value="">{t("oil.select")}</option>{visibleProducts.map((product) => <option key={product.id} value={product.id}>{[product.oilType, product.brand, product.grade].filter(Boolean).join(" · ")}</option>)}</select></label>

              <VoiceTypingField fieldLabel={t("oil.fields.liters")} mode="number"><label className="font-bold text-slate-800">{t("oil.fields.liters")}<input type="number" min="0" step="any" className={`${inputClass} mt-1`} value={form.liters} onChange={(event) => change("liters", event.target.value)} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("oil.fields.rate")} mode="amount"><label className="font-bold text-slate-800">{t("oil.fields.rate")}<input type="number" min="0" step="any" className={`${inputClass} mt-1`} value={form.rate} onChange={(event) => change("rate", event.target.value)} /></label></VoiceTypingField>

              <div className="rounded-lg border border-blue-200 bg-blue-50 p-3"><p className="font-bold text-slate-700">{t("oil.fields.amount")}</p><p dir="ltr" className="mt-1 text-lg font-black text-blue-900">{amount(total)}</p></div>

              <VoiceTypingField fieldLabel={t("oil.fields.billNo")} mode="identifier"><label className="font-bold text-slate-800">{t("oil.fields.billNo")}<input className={`${inputClass} mt-1`} value={form.billNo} onChange={(event) => change("billNo", event.target.value)} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("oil.fields.odometer")} mode="number"><label className="font-bold text-slate-800">{t("oil.fields.odometer")}<input type="number" min="0" className={`${inputClass} mt-1`} value={form.odometer} onChange={(event) => change("odometer", event.target.value)} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("oil.fields.nextChange")} mode="date"><label className="font-bold text-slate-800">{t("oil.fields.nextChange")}<input type="date" className={`${inputClass} mt-1`} value={form.nextDate} onChange={(event) => change("nextDate", event.target.value)} /></label></VoiceTypingField>

            </div>
            <label className="block font-bold text-slate-800">{t("oil.fields.remarks")}<VoiceTypingField fieldLabel={t("oil.fields.remarks")} value={form.remarks} onValueChange={(value) => change("remarks", value)} contextKey={`${addaId}:${voucherId}:${entry.id}`}><textarea className={`${inputClass} mt-1`} value={form.remarks} onChange={(event) => change("remarks", event.target.value)} /></VoiceTypingField></label>
            <div className="flex justify-end gap-3">
              <button type="button" onClick={onClose} disabled={saving} className="rounded-lg border border-slate-300 px-5 py-3 font-bold text-slate-800 disabled:opacity-50">{t("common.actions.cancel")}</button>
              <button type="button" onClick={() => void save()} disabled={saving} className="rounded-lg bg-blue-700 px-6 py-3 font-black text-white disabled:opacity-50">{saving ? t("common.states.saving") : t("common.actions.save")}</button>
            </div>
          </div>
        ) : null}
      </section>
    </div>
  );
}

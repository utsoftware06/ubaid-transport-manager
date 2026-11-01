"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { useReactToPrint } from "react-to-print";
import { supabase } from "@/lib/supabase/client";
import { loadAddaPrintSettings, saveAddaPrintSetting } from "@/lib/print/persistence";
import { resolvePrintBranding } from "@/lib/print/resolvePrintBranding";
import { createDefaultPrintSettings, validatePrintSettingsValues } from "@/lib/print/settings";
import { getPrintDirection, getPrintPageRule, getSafeLogoUrl, updatePrintPreviewOverrides } from "@/lib/print/foundation";
import type { PrintBranding, PrintDocumentSettingsValues, PrintDocumentType, PrintLanguage, PrintPreviewOverrides, PrintTemplateId } from "@/lib/print/types";
import { isUserRole, type UserRole } from "@/config/navigation";
import { translations } from "@/i18n/translations";
import { templatePageDefaults } from "./ModuleTransportPrintDocument";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

export type LedgerDocumentType = Extract<PrintDocumentType, "party_ledger" | "broker_ledger" | "adda_account" | "vehicle_ledger" | "owner_ledger" | "owner_gari_account" | "driver_ledger">;
export function isLedgerDocumentType(value: PrintDocumentType): value is LedgerDocumentType {
  return ["party_ledger", "broker_ledger", "adda_account", "vehicle_ledger", "owner_ledger", "owner_gari_account", "driver_ledger"].includes(value);
}
export type LedgerPrintField = { label: string; value: string; direction?: "ltr" | "rtl" };
export type LedgerPrintTable = { title?: string; columns: string[]; rows: string[][]; emptyMessage?: string };
export type LedgerPrintPresentation = {
  documentType: LedgerDocumentType;
  title: string;
  subtitle?: string;
  reference?: string;
  fields: LedgerPrintField[];
  summary: LedgerPrintField[];
  tables: LedgerPrintTable[];
  synthetic?: boolean;
};
export type LedgerPresentationFactory = (language: PrintLanguage) => LedgerPrintPresentation;

type ButtonProps = {
  addaId: string | null | undefined;
  documentType: LedgerDocumentType;
  makePresentation: LedgerPresentationFactory;
  initialLanguage?: PrintLanguage;
  fallbackLabel: string;
  onLegacyPrint: () => void;
  children: ReactNode;
  unavailableReason?: string;
  autoOpenKey?: string | number | null;
  onDialogClose?: () => void;
  showLegacyFallback?: boolean;
};

const strings = {
  en: { title: "Statement print preview", loading: "Loading this Adda’s saved print settings…", close: "Close", template: "Layout", paper: "Paper", orientation: "Orientation", language: "Language", margins: "Margins (mm)", logo: "Logo", address: "Address", phone: "Phone", signatures: "Signatures", stamp: "Stamp", reset: "Reset preview", print: "Print / Save as PDF", save: "Save defaults", saving: "Saving…", saved: "Defaults saved.", fallback: "Use legacy print", readError: "Saved defaults could not be loaded. Saving is disabled.", unauthorized: "This statement’s Adda is not authorized for this account.", noOwner: "A single verified Adda is required for this statement print.", failed: "Print settings could not be saved: ", temporary: "Preview changes are temporary until Save defaults is selected.", synthetic: "Synthetic sample — not a real account", a4: "A4", a5: "A5", portrait: "Portrait", landscape: "Landscape", prepared: "Prepared by", account: "Account holder", empty: "No recorded rows", unavailable: "New statement printing is unavailable for a mixed or unresolved Adda report." },
  ur: { title: "اسٹیٹمنٹ پرنٹ پیش نظارہ", loading: "اس اڈے کی محفوظ پرنٹ ترتیبات لوڈ ہو رہی ہیں…", close: "بند کریں", template: "لے آؤٹ", paper: "کاغذ", orientation: "رخ", language: "زبان", margins: "حاشیے (ملی میٹر)", logo: "لوگو", address: "پتہ", phone: "فون", signatures: "دستخط", stamp: "مہر", reset: "پیش نظارہ بحال کریں", print: "پرنٹ / پی ڈی ایف محفوظ کریں", save: "ڈیفالٹ محفوظ کریں", saving: "محفوظ ہو رہا ہے…", saved: "ڈیفالٹ محفوظ ہو گئے۔", fallback: "پرانا پرنٹ استعمال کریں", readError: "محفوظ پرنٹ ترتیبات لوڈ نہیں ہو سکیں۔ محفوظ کرنا بند ہے۔", unauthorized: "اس اکاؤنٹ کو اس اسٹیٹمنٹ کے اڈے کی اجازت نہیں۔", noOwner: "اسٹیٹمنٹ پرنٹ کے لیے ایک تصدیق شدہ اڈا ضروری ہے۔", failed: "پرنٹ ترتیبات محفوظ نہ ہو سکیں: ", temporary: "پیش نظارہ کی تبدیلیاں صرف ڈیفالٹ محفوظ کرنے پر مستقل ہوں گی۔", synthetic: "مصنوعی نمونہ — حقیقی اکاؤنٹ نہیں", a4: "A4", a5: "A5", portrait: "پورٹریٹ", landscape: "لینڈ اسکیپ", prepared: "تیار کنندہ", account: "اکاؤنٹ ہولڈر", empty: "کوئی درج شدہ ریکارڈ نہیں", unavailable: "متعدد یا غیر تصدیق شدہ اڈوں والی رپورٹ کا نیا پرنٹ دستیاب نہیں۔" },
} as const;

export function translateLedgerPrint(language: PrintLanguage, key: string): string {
  let value: unknown = translations[language];
  for (const part of key.split(".").filter(Boolean)) {
    if (!value || typeof value !== "object" || !(part in value)) return key;
    value = (value as Record<string, unknown>)[part];
  }
  return typeof value === "string" ? value : key;
}

export function singleResolvedAddaId(ids: Array<string | null | undefined>): string | null {
  if (ids.length === 0 || ids.some((id) => !id)) return null;
  const unique = Array.from(new Set(ids as string[]));
  return unique.length === 1 ? unique[0] : null;
}

export function createSyntheticLedgerPresentation(documentType: LedgerDocumentType, language: PrintLanguage): LedgerPrintPresentation {
  const ur = language === "ur";
  const label = (en: string, urdu: string) => ur ? urdu : en;
  const title = ({
    party_ledger: label("Party Ledger", "پارٹی لیجر"),
    broker_ledger: label("Broker Ledger", "بروکر لیجر"),
    adda_account: label("Adda Account", "اڈہ اکاؤنٹ"),
    vehicle_ledger: label("Vehicle Ledger", "گاڑی لیجر"),
    owner_ledger: label("Vehicle Owner Account", "گاڑی مالک اکاؤنٹ"),
    owner_gari_account: label("Owner / Gari Account", "مالک / گاڑی اکاؤنٹ"),
    driver_ledger: label("Driver Ledger", "ڈرائیور لیجر"),
  })[documentType];
  return {
    documentType, title,
    subtitle: label("Filtered statement · 1–27 October 2026", "فلٹر شدہ اسٹیٹمنٹ · ۱ تا ۲۷ اکتوبر ۲۰۲۶"),
    reference: label("SAMPLE-001", "نمونہ-001"),
    synthetic: true,
    fields: [
      { label: label("Account", "اکاؤنٹ"), value: label("Synthetic account", "مصنوعی اکاؤنٹ") },
      { label: label("Period", "مدت"), value: label("1–27 October 2026", "۱ تا ۲۷ اکتوبر ۲۰۲۶") },
      { label: label("Entries", "اندراجات"), value: "2", direction: "ltr" },
    ],
    summary: [
      { label: label("Opening balance", "ابتدائی بیلنس"), value: "Rs. 12,000" },
      { label: label("Debit", "ڈیبٹ"), value: "Rs. 24,500" },
      { label: label("Credit", "کریڈٹ"), value: "Rs. 8,000" },
      { label: label("Closing balance", "اختتامی بیلنس"), value: "Rs. 28,500" },
    ],
    tables: [{
      title: label("Statement activity", "اسٹیٹمنٹ سرگرمی"),
      columns: [label("Date", "تاریخ"), label("Reference", "حوالہ"), label("Description", "تفصیل"), label("Debit", "ڈیبٹ"), label("Credit", "کریڈٹ"), label("Running balance", "چلتا بیلنس")],
      rows: [["2026-10-27", "SAMPLE-001", label("Synthetic row", "مصنوعی اندراج"), "Rs. 16,500", "—", "Rs. 28,500"], ["2026-10-25", "SAMPLE-000", label("Synthetic opening entry", "مصنوعی ابتدائی اندراج"), "—", "Rs. 8,000", "Rs. 12,000"]],
      emptyMessage: label("No recorded rows", "کوئی درج شدہ ریکارڈ نہیں"),
    }],
  };
}

export default function LedgerStatementPrintButton(props: ButtonProps) {
  const [open, setOpen] = useState(() => props.autoOpenKey !== undefined && props.autoOpenKey !== null);
  const blocked = !props.addaId || Boolean(props.unavailableReason);
  const initial = props.initialLanguage ?? "en";
  return <>
    <span className="inline-flex" title={blocked ? props.unavailableReason ?? strings[initial].noOwner : undefined}>
      <span onClick={() => { if (!blocked) setOpen(true); }} aria-disabled={blocked} className={blocked ? "pointer-events-none opacity-50" : ""}>{props.children}</span>
    </span>
    {blocked && props.unavailableReason ? <span className="sr-only">{props.unavailableReason}</span> : null}
    {open && props.addaId ? <LedgerStatementPrintDialog key={`${props.addaId}:${props.documentType}`} {...props} addaId={props.addaId} onClose={() => { setOpen(false); props.onDialogClose?.(); }} /> : null}
  </>;
}

type LoadedSettings = { key: string; branding: PrintBranding; defaults: PrintDocumentSettingsValues; canSave: boolean; readError: string | null };
function LedgerStatementPrintDialog({ addaId, documentType, makePresentation, initialLanguage = "en", fallbackLabel, onLegacyPrint, onClose, showLegacyFallback = true }: Omit<ButtonProps, "children" | "unavailableReason"> & { addaId: string; onClose: () => void }) {
  const [loaded, setLoaded] = useState<LoadedSettings | null>(null);
  const [overrides, setOverrides] = useState<PrintPreviewOverrides | null>(null);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);
  const [logoFailed, setLogoFailed] = useState(false);
  const printRef = useRef<HTMLDivElement | null>(null);
  const key = `${addaId}:${documentType}`;
  const presentation = makePresentation(overrides?.language ?? initialLanguage);
  const activeLoaded = loaded?.key === key ? loaded : null;
  const activeOverrides = activeLoaded ? overrides : null;
  const invalid = activeOverrides ? validatePrintSettingsValues(activeOverrides) : ["settings_missing"];
  const copy = strings[activeOverrides?.language ?? initialLanguage];

  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        const auth = await supabase.auth.getUser();
        if (!auth.data.user) throw new Error("No active user.");
        const { data: profile, error: profileError } = await supabase.from("profiles").select("role,adda_id,is_active").eq("id", auth.data.user.id).maybeSingle();
        if (profileError || !profile || profile.is_active !== true || !isUserRole(profile.role)) throw new Error("Active profile unavailable.");
        const role = profile.role as UserRole;
        const authorized = role === "super_admin" || profile.adda_id === addaId;
        if (!authorized) throw new Error("Unauthorized owner Adda context.");
        const canSave = role === "super_admin" || (role === "adda_admin" && profile.adda_id === addaId);
        const [brandResult, settingsResult] = await Promise.allSettled([resolvePrintBranding(addaId), loadAddaPrintSettings(addaId)]);
        if (!active) return;
        const branding = brandResult.status === "fulfilled" ? brandResult.value.branding : {
          addaId, addaName: "", tagline: null, logoUrl: null, address: null, city: null, phone: null,
          alternatePhone: null, existingPaperSize: null, showLogoByDefault: true, footerText: null,
        } satisfies PrintBranding;
        const settingRows = settingsResult.status === "fulfilled" ? settingsResult.value : [];
        const saved = settingRows.find((row) => row.addaId === addaId && row.documentType === documentType);
        const defaults = saved ? { ...saved } : createDefaultPrintSettings(branding);
        const readError = settingsResult.status === "rejected" ? (settingsResult.reason instanceof Error ? settingsResult.reason.message : "Settings could not be loaded.") : null;
        setLoaded({ key, branding, defaults, canSave: canSave && !readError, readError });
        setOverrides({ ...defaults, language: initialLanguage, showFooter: Boolean(branding.footerText) });
      } catch (caught) {
        if (active) setError(caught instanceof Error && caught.message.includes("Unauthorized") ? strings.en.unauthorized : strings.en.noOwner);
      }
    })();
    return () => { active = false; };
  }, [addaId, documentType, initialLanguage, key]);

  const setValue = <K extends keyof PrintPreviewOverrides>(field: K, value: PrintPreviewOverrides[K]) => {
    if (!activeOverrides) return;
    setMessage(""); setOverrides(updatePrintPreviewOverrides(activeOverrides, field, value));
  };
  const selectTemplate = (templateId: PrintTemplateId) => {
    if (!activeOverrides) return;
    setOverrides({ ...activeOverrides, templateId, ...templatePageDefaults(templateId) });
  };
  const reset = () => {
    if (!activeLoaded) return;
    setOverrides({ ...activeLoaded.defaults, language: initialLanguage, showFooter: Boolean(activeLoaded.branding.footerText) });
    setMessage("");
  };
  const beforePrint = async () => {
    const images = Array.from(printRef.current?.querySelectorAll("img") ?? []);
    await Promise.all(images.map((image) => image.complete ? Promise.resolve() : new Promise<void>((resolve) => {
      image.addEventListener("load", () => resolve(), { once: true });
      image.addEventListener("error", () => resolve(), { once: true });
      window.setTimeout(resolve, 1500);
    })));
    if (document.fonts?.ready) await Promise.race([document.fonts.ready.then(() => undefined), new Promise<void>((resolve) => window.setTimeout(resolve, 1000))]);
  };
  const printDocument = useReactToPrint({ contentRef: printRef, documentTitle: `${documentType}-${presentation.reference || "statement"}`, pageStyle: activeOverrides ? `${getPrintPageRule(activeOverrides.paperSize, activeOverrides.orientation, activeOverrides)} @media print { body * { visibility: hidden !important; } #ledger-statement-print, #ledger-statement-print * { visibility: visible !important; } #ledger-statement-print { position: absolute !important; inset: 0 auto auto 0 !important; width: 100% !important; max-width: none !important; } }` : undefined, onBeforePrint: beforePrint });

  async function saveDefaults() {
    if (!activeLoaded || !activeOverrides || !activeLoaded.canSave || invalid.length || saving) return;
    setSaving(true); setError(""); setMessage("");
    try {
      const values: PrintDocumentSettingsValues = { ...activeOverrides };
      await saveAddaPrintSetting(addaId, documentType, values);
      setLoaded((current) => current?.key === key ? { ...current, defaults: values } : current);
      setMessage(strings[activeOverrides.language].saved);
    } catch (caught) { setError(strings[activeOverrides.language].failed + (caught instanceof Error ? caught.message : "Unknown error.")); }
    finally { setSaving(false); }
  }

  const dir = getPrintDirection(activeOverrides?.language ?? initialLanguage);
  const templateNames: Array<[PrintTemplateId, string, string]> = [
    ["traditional_pad", "Traditional Transport Pad", "روایتی ٹرانسپورٹ پیڈ"],
    ["modern_professional", "Modern Professional", "جدید پروفیشنل"],
    ["compact_pad", "Compact Pad", "کمپیکٹ پیڈ"],
    ["detailed_a4", "Detailed A4", "تفصیلی A4"],
  ];
  return <div className="fixed inset-0 z-[110] overflow-y-auto bg-slate-950/70 p-2 sm:p-5 print-module-modal" dir={dir}>
    <div className="mx-auto max-w-7xl rounded-xl bg-slate-100 p-3 shadow-2xl sm:p-5">
      <header className="mb-3 flex items-start justify-between gap-3 rounded-lg bg-white p-4 print-module-controls"><div><h2 className="text-xl font-black">{copy.title} · {presentation.title}</h2><p className="mt-1 text-sm font-bold">{presentation.reference ?? ""}</p></div><button className="rounded border px-4 py-2 font-bold" onClick={onClose}>{copy.close}</button></header>
      {error ? <p role="alert" className="rounded border border-red-300 bg-red-50 p-4 font-bold text-red-900 print-module-controls">{error}</p> : null}
      {!error && !activeOverrides ? <p role="status" className="p-6 text-center font-bold print-module-controls">{copy.loading}</p> : null}
      {activeLoaded && activeOverrides ? <>
        <section className="mb-4 grid gap-3 rounded-lg bg-white p-4 md:grid-cols-4 print-module-controls">
          <label className="grid gap-1 text-sm font-bold">{copy.template}<select className="rounded border p-2" value={activeOverrides.templateId} onChange={(event) => selectTemplate(event.target.value as PrintTemplateId)}>{templateNames.map(([id, en, ur]) => <option key={id} value={id}>{activeOverrides.language === "ur" ? ur : en}</option>)}</select></label>
          <label className="grid gap-1 text-sm font-bold">{copy.paper}<select className="rounded border p-2" value={activeOverrides.paperSize} onChange={(event) => setValue("paperSize", event.target.value as PrintPreviewOverrides["paperSize"])}><option value="A4">{copy.a4}</option><option value="A5">{copy.a5}</option></select></label>
          <label className="grid gap-1 text-sm font-bold">{copy.orientation}<select className="rounded border p-2" value={activeOverrides.orientation} onChange={(event) => setValue("orientation", event.target.value as PrintPreviewOverrides["orientation"])}><option value="portrait">{copy.portrait}</option><option value="landscape">{copy.landscape}</option></select></label>
          <label className="grid gap-1 text-sm font-bold">{copy.language}<select className="rounded border p-2" value={activeOverrides.language} onChange={(event) => setValue("language", event.target.value as PrintLanguage)}><option value="en">English</option><option value="ur">اردو</option></select></label>
          <fieldset className="md:col-span-4"><legend className="text-sm font-bold">{copy.margins}</legend><div className="grid grid-cols-2 gap-2 sm:grid-cols-4">{(["marginTopMm", "marginRightMm", "marginBottomMm", "marginLeftMm"] as const).map((field) =>
           <VoiceTypingField key={field} fieldLabel={`${copy.margins} ${field}`} mode="number"><input aria-label={`${copy.margins} ${field}`} className="rounded border p-2" type="number" min="0" max="30" step="0.1" value={activeOverrides[field]} onChange={(event) => setValue(field, Number(event.target.value))} /></VoiceTypingField>
          )}</div></fieldset>
          <div className="flex flex-wrap gap-4 md:col-span-4">{([["showLogo", copy.logo], ["showAddress", copy.address], ["showPhone", copy.phone], ["showSignatures", copy.signatures], ["showStamp", copy.stamp]] as const).map(([field, label]) => <label key={field} className="flex items-center gap-2 text-sm font-bold"><input type="checkbox" checked={activeOverrides[field]} onChange={(event) => setValue(field, event.target.checked)} />{label}</label>)}</div>
          <div className="flex flex-wrap gap-2 md:col-span-4"><button className="rounded border px-4 py-2 font-bold" onClick={reset}>{copy.reset}</button><button className="rounded bg-slate-900 px-4 py-2 font-bold text-white" disabled={invalid.length > 0} onClick={() => void printDocument()}>{copy.print}</button><button className="rounded border border-blue-700 px-4 py-2 font-bold text-blue-800 disabled:opacity-40" disabled={!activeLoaded.canSave || saving || invalid.length > 0} onClick={() => void saveDefaults()}>{saving ? copy.saving : copy.save}</button>{showLegacyFallback ? <button className="rounded border px-4 py-2 font-bold" onClick={onLegacyPrint}>{fallbackLabel}</button> : null}</div>
          {activeLoaded.readError ? <p className="text-sm font-bold text-amber-800 md:col-span-4">{copy.readError}</p> : null}
          {activeLoaded.canSave ? <p className="text-xs font-semibold text-slate-600 md:col-span-4">{copy.temporary}</p> : null}
          {message ? <p role="status" className="font-bold text-green-800 md:col-span-4">{message}</p> : null}{error ? <p role="alert" className="font-bold text-red-800 md:col-span-4">{error}</p> : null}
        </section>
        <div className="overflow-auto rounded-lg bg-slate-200 p-3 sm:p-6 print-module-preview" ref={printRef}><LedgerStatementPrintDocument presentation={presentation} branding={activeLoaded.branding} overrides={activeOverrides} logoFailed={logoFailed} onLogoError={() => setLogoFailed(true)} /></div>
      </> : null}
    </div>
  </div>;
}

export function LedgerStatementPrintDocument({ presentation, branding, overrides, logoFailed = false, onLogoError }: { presentation: LedgerPrintPresentation; branding: PrintBranding; overrides: PrintPreviewOverrides; logoFailed?: boolean; onLogoError?: () => void }) {
  const lang = overrides.language;
  const copy = strings[lang];
  const logoUrl = overrides.showLogo && !logoFailed ? getSafeLogoUrl(branding.logoUrl) : null;
  const sheetClass = `ledger-statement ledger-${overrides.templateId} ledger-paper-${overrides.paperSize.toLowerCase()}-${overrides.orientation}`;
  const signatureBlock = overrides.showSignatures ? <footer className="ledger-signatures"><span>{copy.prepared}</span><span>{copy.account}</span>{overrides.showStamp ? <span>{copy.stamp}</span> : null}</footer> : null;
  const fields = presentation.fields.filter((field) => field.value !== "");
  const tables = presentation.tables;
  const summary = presentation.summary;
  const header = <header className="ledger-brand"><div className="ledger-mark">{logoUrl ? <img src={logoUrl} alt="" onError={onLogoError} /> : <img src="/images/print/transport-truck.svg" alt="" />}</div><div className="ledger-brand-copy"><h1>{branding.addaName.trim() || (lang === "ur" ? "اڈے کا نام دستیاب نہیں" : "Adda name unavailable")}</h1>{overrides.showAddress && (branding.address || branding.city) ? <p>{[branding.address, branding.city].filter(Boolean).join(", ")}</p> : null}{overrides.showPhone && (branding.phone || branding.alternatePhone) ? <p dir="ltr">{[branding.phone, branding.alternatePhone].filter(Boolean).join(" · ")}</p> : null}</div><div className="ledger-title-badge"><small>{presentation.subtitle ?? (lang === "ur" ? "اکاؤنٹ اسٹیٹمنٹ" : "ACCOUNT STATEMENT")}</small><strong>{presentation.title}</strong>{presentation.reference ? <span dir="ltr">{presentation.reference}</span> : null}</div></header>;
  const fieldGrid = <section className="ledger-fields">{fields.map((field, index) => <div className="ledger-field" key={`${field.label}-${index}`}><b>{field.label}</b><span dir={field.direction ?? "auto"}>{field.value}</span></div>)}</section>;
  const tableMarkup = tables.map((table, tableIndex) => <section className="ledger-table-section" key={`${table.title ?? "table"}-${tableIndex}`}>{table.title ? <h2>{table.title}</h2> : null}<table><thead><tr>{table.columns.map((column, index) => <th key={`${column}-${index}`}>{column}</th>)}</tr></thead><tbody>{table.rows.length ? table.rows.map((row, rowIndex) => <tr key={rowIndex}>{table.columns.map((_, columnIndex) => <td key={columnIndex} dir="auto">{row[columnIndex] ?? ""}</td>)}</tr>) : <tr><td colSpan={table.columns.length}>{table.emptyMessage ?? copy.empty}</td></tr>}</tbody></table></section>);
  const summaryMarkup = <section className="ledger-summary" aria-label={lang === "ur" ? "مالی خلاصہ" : "Account summary"}>{summary.map((field, index) => <div className="ledger-summary-item" key={`${field.label}-${index}`}><span>{field.label}</span><strong dir={field.direction ?? "ltr"}>{field.value}</strong></div>)}</section>;
  const style = <style>{`
    @page{size:${overrides.paperSize} ${overrides.orientation};margin:${overrides.marginTopMm}mm ${overrides.marginRightMm}mm ${overrides.marginBottomMm}mm ${overrides.marginLeftMm}mm}
    .ledger-statement{--ink:#18202a;--line:#4b5563;--blue:#1e4f78;box-sizing:border-box;width:100%;min-height:100%;padding:0;background:#fff;color:var(--ink);font:11px/1.45 Arial,"Noto Nastaliq Urdu",sans-serif;text-align:start;direction:${getPrintDirection(lang)}}
    .ledger-statement *{box-sizing:border-box}.ledger-brand{display:grid;grid-template-columns:54px minmax(0,1fr) auto;align-items:center;gap:10px;border-bottom:2px solid var(--ink);padding:6px 0 10px;margin-bottom:12px}.ledger-mark{display:flex;align-items:center;justify-content:center;width:50px;height:44px}.ledger-mark img{max-width:48px;max-height:42px;object-fit:contain}.ledger-brand-copy h1{font-size:20px;line-height:1.15;margin:0}.ledger-brand-copy p{font-size:9px;margin:2px 0 0}.ledger-title-badge{min-width:145px;border:2px solid var(--ink);padding:5px 8px;text-align:center}.ledger-title-badge small,.ledger-title-badge span{display:block;font-size:8px;font-weight:700}.ledger-title-badge strong{display:block;font-size:13px}.ledger-title-badge span{margin-top:2px}.ledger-fields{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));border:1px solid var(--line);margin:10px 0}.ledger-field{display:grid;grid-template-columns:minmax(92px,auto) minmax(0,1fr);gap:7px;padding:5px 7px;border-bottom:1px solid #9ca3af;overflow-wrap:anywhere}.ledger-field:nth-child(odd){border-inline-end:1px solid #9ca3af}.ledger-field b{font-size:9px}.ledger-field span{unicode-bidi:plaintext}.ledger-summary{display:flex;flex-wrap:wrap;gap:6px;margin:10px 0}.ledger-summary-item{flex:1 1 125px;border:1px solid var(--line);padding:6px 8px;min-width:100px}.ledger-summary-item span,.ledger-summary-item strong{display:block}.ledger-summary-item span{font-size:8px;font-weight:700}.ledger-summary-item strong{font-size:11px;margin-top:2px;unicode-bidi:isolate}.ledger-table-section{margin:12px 0}.ledger-table-section h2{font-size:12px;margin:10px 0 5px}.ledger-table-section table{width:100%;border-collapse:collapse;table-layout:auto;font-size:9px}.ledger-table-section thead{display:table-header-group}.ledger-table-section tr{break-inside:avoid;page-break-inside:avoid}.ledger-table-section th,.ledger-table-section td{border:1px solid var(--line);padding:4px 5px;text-align:start;vertical-align:top;overflow-wrap:anywhere}.ledger-table-section th{background:#f1f3f5;font-size:8px}.ledger-signatures{display:grid;grid-template-columns:1fr 1fr ${overrides.showStamp ? "72px" : "0"};gap:22px;margin-top:30px;break-inside:avoid;page-break-inside:avoid}.ledger-signatures span{min-height:28px;border-top:1px solid var(--ink);padding-top:4px;text-align:center;font-size:9px}.ledger-footer{margin-top:12px;border-top:1px solid #888;padding-top:5px;font-size:8px}
    .ledger-traditional_pad .ledger-brand{border-bottom:3px double var(--ink)}.ledger-traditional_pad .ledger-fields{border-width:2px}.ledger-traditional_pad .ledger-summary-item{border-width:2px}.ledger-traditional_pad .ledger-table-section th,.ledger-traditional_pad .ledger-table-section td{border:1.5px solid var(--ink)}.ledger-traditional_pad .ledger-title-badge{border-width:3px;transform:rotate(-1deg)}
    .ledger-modern_professional{--blue:#194e75}.ledger-modern_professional .ledger-brand{border-bottom:5px solid var(--blue);padding-bottom:13px}.ledger-modern_professional .ledger-title-badge{border:0;border-inline-start:4px solid var(--blue);background:#edf4f8}.ledger-modern_professional .ledger-fields{border:0;gap:7px}.ledger-modern_professional .ledger-field{border:1px solid #b8c7d2;border-radius:3px}.ledger-modern_professional .ledger-summary-item{border-color:#7692a7;border-top:3px solid var(--blue);background:#f7fafc}.ledger-modern_professional .ledger-table-section th{background:#dfeaf1;border-color:#53718a}
    .ledger-compact_pad{font-size:9px;line-height:1.3}.ledger-compact_pad .ledger-brand{grid-template-columns:40px minmax(0,1fr) auto;gap:6px;padding:3px 0 6px;margin-bottom:7px}.ledger-compact_pad .ledger-mark{width:38px;height:32px}.ledger-compact_pad .ledger-mark img{max-width:36px;max-height:30px}.ledger-compact_pad .ledger-brand-copy h1{font-size:14px}.ledger-compact_pad .ledger-title-badge{min-width:105px;padding:3px 5px}.ledger-compact_pad .ledger-title-badge strong{font-size:10px}.ledger-compact_pad .ledger-field{grid-template-columns:minmax(75px,auto) minmax(0,1fr);padding:3px 4px;gap:4px}.ledger-compact_pad .ledger-summary{gap:3px;margin:6px 0}.ledger-compact_pad .ledger-summary-item{flex-basis:92px;min-width:78px;padding:3px 5px}.ledger-compact_pad .ledger-table-section table{font-size:7.5px}.ledger-compact_pad .ledger-table-section th,.ledger-compact_pad .ledger-table-section td{padding:2px 3px}.ledger-compact_pad .ledger-signatures{margin-top:20px}
    .ledger-detailed_a4 .ledger-brand{grid-template-columns:64px minmax(0,1fr) auto;padding:12px 0 16px;border-bottom:2px solid #20313f}.ledger-detailed_a4 .ledger-mark{width:60px;height:54px}.ledger-detailed_a4 .ledger-mark img{max-width:56px;max-height:50px}.ledger-detailed_a4 .ledger-brand-copy h1{font-size:25px}.ledger-detailed_a4 .ledger-title-badge{min-width:180px;padding:9px}.ledger-detailed_a4 .ledger-title-badge strong{font-size:16px}.ledger-detailed_a4 .ledger-field{padding:8px 10px}.ledger-detailed_a4 .ledger-summary-item{flex-basis:150px;padding:9px 11px}.ledger-detailed_a4 .ledger-table-section table{font-size:10px}.ledger-detailed_a4 .ledger-table-section th,.ledger-detailed_a4 .ledger-table-section td{padding:6px 7px}
    .ledger-paper-a5-portrait{font-size:9px}.ledger-paper-a5-landscape .ledger-summary-item{flex-basis:110px}
    @media print{.ledger-statement{min-height:auto}.ledger-table-section{break-inside:auto}.ledger-table-section h2{break-after:avoid}.ledger-signatures{break-inside:avoid}.ledger-brand{break-inside:avoid}.ledger-summary{break-inside:avoid}}
  `}</style>;
  const masthead = <>{style}{header}{presentation.synthetic ? <p className="ledger-footer">{copy.synthetic}</p> : null}{presentation.subtitle ? <p className="ledger-intro">{presentation.subtitle}</p> : null}{fieldGrid}{summaryMarkup}{tableMarkup}{signatureBlock}{overrides.showFooter && branding.footerText ? <p className="ledger-footer">{branding.footerText}</p> : null}</>;

  if (overrides.templateId === "traditional_pad") return <article id="ledger-statement-print" className={`${sheetClass} ledger-traditional_pad`} lang={lang} dir={getPrintDirection(lang)}>{masthead}</article>;
  if (overrides.templateId === "modern_professional") return <article id="ledger-statement-print" className={`${sheetClass} ledger-modern_professional`} lang={lang} dir={getPrintDirection(lang)}><div className="ledger-modern-top">{header}</div>{presentation.synthetic ? <p className="ledger-footer">{copy.synthetic}</p> : null}<section className="ledger-modern-account"><h2>{presentation.title}</h2>{presentation.subtitle ? <p>{presentation.subtitle}</p> : null}{fieldGrid}</section>{summaryMarkup}{tableMarkup}{signatureBlock}{overrides.showFooter && branding.footerText ? <p className="ledger-footer">{branding.footerText}</p> : null}{style}</article>;
  if (overrides.templateId === "compact_pad") return <article id="ledger-statement-print" className={`${sheetClass} ledger-compact_pad`} lang={lang} dir={getPrintDirection(lang)}><div className="ledger-compact-header">{header}</div>{presentation.synthetic ? <p className="ledger-footer">{copy.synthetic}</p> : null}{fieldGrid}{summaryMarkup}{tableMarkup}{signatureBlock}{overrides.showFooter && branding.footerText ? <p className="ledger-footer">{branding.footerText}</p> : null}{style}</article>;
  return <article id="ledger-statement-print" className={`${sheetClass} ledger-detailed_a4`} lang={lang} dir={getPrintDirection(lang)}><div className="ledger-detailed-heading">{header}<div className="ledger-document-context"><b>{presentation.title}</b>{presentation.reference ? <span dir="ltr">{presentation.reference}</span> : null}</div></div>{presentation.synthetic ? <p className="ledger-footer">{copy.synthetic}</p> : null}<div className="ledger-detailed-panels">{fieldGrid}</div>{summaryMarkup}{tableMarkup}{signatureBlock}{overrides.showFooter && branding.footerText ? <p className="ledger-footer">{branding.footerText}</p> : null}{style}</article>;
}

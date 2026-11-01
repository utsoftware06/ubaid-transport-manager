"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useReactToPrint } from "react-to-print";
import { supabase } from "@/lib/supabase/client";
import { loadAddaPrintSettings, saveAddaPrintSetting } from "@/lib/print/persistence";
import { resolvePrintBranding } from "@/lib/print/resolvePrintBranding";
import { createDefaultPrintSettings, validatePrintSettingsValues } from "@/lib/print/settings";
import { getPrintDirection, getPrintPageRule, updatePrintPreviewOverrides } from "@/lib/print/foundation";
import type { PrintBranding, PrintDocumentSettingsValues, PrintPreviewOverrides, PrintTemplateId } from "@/lib/print/types";
import { cellText, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import { adaptModulePrintMarkup } from "@/lib/print/modulePresentationAdapters";
import ModuleTransportPrintDocument, { templatePageDefaults } from "./ModuleTransportPrintDocument";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  addaId: string | null | undefined;
  presentation: ModulePrintPresentation;
  fallbackLabel: string;
  onLegacyPrint: () => void;
  initialLanguage?: "en" | "ur";
  children: ReactNode;
};
type Role = "super_admin" | "adda_admin" | "operator";
type Loaded = { key: string; branding: PrintBranding; defaults: PrintDocumentSettingsValues; canSave: boolean; readError: string | null };

const strings = {
  en: { title: "Print preview", loading: "Loading this record's Adda settings…", close: "Close", template: "Layout", paper: "Paper", orientation: "Orientation", language: "Language", margins: "Margins (mm)", logo: "Logo", address: "Address", phone: "Phone", signatures: "Signatures", stamp: "Stamp", footer: "Footer", reset: "Reset preview", print: "Print / Save as PDF", save: "Save defaults", saving: "Saving…", fallback: "Use legacy print", saved: "Defaults saved.", readError: "Saved defaults could not be loaded. Temporary settings are in use; saving is disabled.", unauthorized: "The record’s owning Adda could not be verified for this account.", noOwner: "This record has no verified Adda context. New-template printing is unavailable.", failed: "Print settings could not be saved: ", temporary: "Preview changes are temporary until Save defaults is selected.", synthetic: "Synthetic sample — not a real record", ready: "Available", a4: "A4", a5: "A5", portrait: "Portrait", landscape: "Landscape" },
  ur: { title: "پرنٹ پیش نظارہ", loading: "اس ریکارڈ کے اڈے کی ترتیبات لوڈ ہو رہی ہیں…", close: "بند کریں", template: "لے آؤٹ", paper: "کاغذ", orientation: "رخ", language: "زبان", margins: "حاشیے (ملی میٹر)", logo: "لوگو", address: "پتہ", phone: "فون", signatures: "دستخط", stamp: "مہر", footer: "فٹر", reset: "پیش نظارہ بحال کریں", print: "پرنٹ / پی ڈی ایف محفوظ کریں", save: "ڈیفالٹ محفوظ کریں", saving: "محفوظ ہو رہا ہے…", fallback: "پرانا پرنٹ استعمال کریں", saved: "ڈیفالٹ محفوظ ہو گئے۔", readError: "محفوظ ڈیفالٹ لوڈ نہ ہو سکے۔ عارضی ترتیبات استعمال ہو رہی ہیں؛ محفوظ کرنا بند ہے۔", unauthorized: "اس ریکارڈ کے مالک اڈے کی اس اکاؤنٹ کے لیے تصدیق نہیں ہو سکی۔", noOwner: "اس ریکارڈ کے لیے تصدیق شدہ اڈا دستیاب نہیں۔ نیا پرنٹ بند ہے۔", failed: "پرنٹ ترتیبات محفوظ نہ ہو سکیں: ", temporary: "پیش نظارہ کی تبدیلیاں صرف ڈیفالٹ محفوظ کرنے کے بعد مستقل ہوں گی۔", synthetic: "نمونہ — حقیقی ریکارڈ نہیں", ready: "دستیاب", a4: "A4", a5: "A5", portrait: "پورٹریٹ", landscape: "لینڈ اسکیپ" },
} as const;

export default function ModuleTransportPrintButton({ addaId, presentation, fallbackLabel, onLegacyPrint, initialLanguage = "en", children }: Props) {
  const [open, setOpen] = useState(false);
  return <>
    <span className="inline-flex" onClick={() => setOpen(true)}>{children}</span>
    {open ? <ModuleTransportPrintDialog addaId={addaId ?? null} presentation={presentation} fallbackLabel={fallbackLabel} onLegacyPrint={onLegacyPrint} initialLanguage={initialLanguage} onClose={() => setOpen(false)} /> : null}
  </>;
}

type Request = { title: string; markup: string; fallback: () => void; ownerAddaId?: string | null; presentation?: ModulePrintPresentation };
export function useModuleTransportPrint(documentType: ModulePrintPresentation["documentType"], addaId: string | null | undefined, language: "en" | "ur") {
  const [request, setRequest] = useState<Request | null>(null);
  const open = useCallback((title: string, markup: string, fallback: () => void, ownerAddaId?: string | null) => setRequest({ title, markup, fallback, ownerAddaId }), []);
  const openPresentation = useCallback((presentation: ModulePrintPresentation, fallback: () => void, ownerAddaId?: string | null) => setRequest({ title: presentation.title.en, markup: "", presentation, fallback, ownerAddaId }), []);
  const close = useCallback(() => setRequest(null), []);
  const presentation = useMemo(() => request ? request.presentation ?? adaptModulePrintMarkup(documentType, request.title, request.markup) : null, [documentType, request]);
  const documentAddaId = request?.ownerAddaId !== undefined ? request.ownerAddaId : addaId ?? null;
  const dialog = request && presentation ? <ModuleTransportPrintDialog key={`${documentAddaId ?? "missing"}:${documentType}:${request.title}`} addaId={documentAddaId} presentation={presentation} initialLanguage={language} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={request.fallback} onClose={close} /> : null;
  return { open, openPresentation, dialog };
}

function ModuleTransportPrintDialog({ addaId, presentation, initialLanguage, fallbackLabel, onLegacyPrint, onClose }: Omit<Props, "children"> & { onClose: () => void; initialLanguage: "en" | "ur" }) {
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [overrides, setOverrides] = useState<PrintPreviewOverrides | null>(null);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [logoFailed, setLogoFailed] = useState(false);
  const printRef = useRef<HTMLDivElement | null>(null);
  const key = `${addaId ?? "missing"}:${presentation.documentType}`;
  const language = overrides?.language ?? "en";
  const copy = strings[language];
  const invalid = overrides ? validatePrintSettingsValues(overrides) : ["settings_missing"];

  useEffect(() => {
    let active = true;
    if (!addaId) return () => { active = false; };
    void (async () => {
      try {
        const auth = await supabase.auth.getUser();
        if (!auth.data.user) throw new Error("No active user.");
        const { data: profile, error: profileError } = await supabase.from("profiles").select("role,adda_id,is_active").eq("id", auth.data.user.id).maybeSingle();
        if (profileError || !profile || profile.is_active !== true) throw new Error("Active profile unavailable.");
        const role = profile.role as Role;
        const ownsContext = role === "super_admin" || profile.adda_id === addaId;
        if (!ownsContext || !["super_admin", "adda_admin", "operator"].includes(role)) throw new Error("Unauthorized owner Adda context.");
        const canSave = role === "super_admin" || (role === "adda_admin" && profile.adda_id === addaId);
        const [brandingResult, settingsResult] = await Promise.allSettled([resolvePrintBranding(addaId), loadAddaPrintSettings(addaId)]);
        if (!active) return;
        const fallbackBranding: PrintBranding = brandingResult.status === "fulfilled" ? brandingResult.value.branding : {
          addaId, addaName: "", tagline: null, logoUrl: null, address: null, city: null, phone: null,
          alternatePhone: null, existingPaperSize: null, showLogoByDefault: true, footerText: null,
        };
        const settingsRows = settingsResult.status === "fulfilled" ? settingsResult.value : [];
        const existing = settingsRows.find((row) => row.addaId === addaId && row.documentType === presentation.documentType);
        const defaults = existing ? { ...existing } : createDefaultPrintSettings(fallbackBranding);
        const readError = settingsResult.status === "rejected" ? (settingsResult.reason instanceof Error ? settingsResult.reason.message : "Settings read failed.") : null;
        const base: PrintPreviewOverrides = { ...defaults, language: initialLanguage, showFooter: Boolean(fallbackBranding.footerText) };
        setLoaded({ key, branding: fallbackBranding, defaults, canSave: canSave && !readError, readError });
        setOverrides(base);
      } catch (caught) {
        if (active) setError(caught instanceof Error && caught.message.includes("Unauthorized") ? strings.en.unauthorized : strings.en.noOwner);
      }
    })();
    return () => { active = false; };
  }, [addaId, key, presentation.documentType, initialLanguage]);

  const activeLoaded = loaded?.key === key ? loaded : null;
  const activeOverrides = activeLoaded && overrides ? overrides : null;
  const setValue = <K extends keyof PrintPreviewOverrides>(field: K, value: PrintPreviewOverrides[K]) => {
    if (!activeOverrides) return;
    setMessage("");
    setOverrides(updatePrintPreviewOverrides(activeOverrides, field, value));
  };
  const selectTemplate = (id: PrintTemplateId) => {
    if (!activeOverrides) return;
    const page = templatePageDefaults(id);
    setOverrides({ ...activeOverrides, templateId: id, ...page });
  };
  const reset = () => {
    if (!activeLoaded) return;
    setOverrides({ ...activeLoaded.defaults, language: initialLanguage, showFooter: Boolean(activeLoaded.branding.footerText) });
    setMessage("");
  };
  const beforePrint = async () => {
    const images = Array.from(printRef.current?.querySelectorAll("img") ?? []);
    await Promise.all(images.map((img) => img.complete ? Promise.resolve() : new Promise<void>((resolve) => {
      img.addEventListener("load", () => resolve(), { once: true }); img.addEventListener("error", () => resolve(), { once: true });
      window.setTimeout(resolve, 1500);
    })));
    if (document.fonts?.ready) await Promise.race([document.fonts.ready.then(() => undefined), new Promise<void>((resolve) => window.setTimeout(resolve, 1000))]);
  };
  const doPrint = useReactToPrint({ contentRef: printRef, documentTitle: `${presentation.documentType}-${String(presentation.documentNo ?? "record")}`, pageStyle: activeOverrides ? getPrintPageRule(activeOverrides.paperSize, activeOverrides.orientation, activeOverrides) : undefined, onBeforePrint: beforePrint });

  async function saveDefaults() {
    if (!addaId || !activeLoaded?.canSave || !activeOverrides || invalid.length || saving) return;
    setSaving(true); setMessage(""); setError("");
    const values: PrintDocumentSettingsValues = { ...activeOverrides };
    try {
      await saveAddaPrintSetting(addaId, presentation.documentType, values);
      setLoaded((current) => current?.key === key ? { ...current, defaults: values } : current);
      setMessage(strings[activeOverrides.language].saved);
    } catch (caught) { setError(strings[activeOverrides.language].failed + (caught instanceof Error ? caught.message : "Unknown error.")); }
    finally { setSaving(false); }
  }

  const direction = getPrintDirection(language);
  const layoutNames: Array<[PrintTemplateId, string, string]> = [
    ["traditional_pad", "Traditional Transport Pad", "روایتی ٹرانسپورٹ پیڈ"],
    ["modern_professional", "Modern Professional", "جدید پروفیشنل"],
    ["compact_pad", "Compact A5 Pad", "کمپیکٹ A5 پیڈ"],
    ["detailed_a4", "Detailed A4", "تفصیلی A4"],
  ];
  return <div className="fixed inset-0 z-[100] overflow-y-auto bg-slate-950/70 p-2 sm:p-5 print-module-modal" dir={direction}>
    <div className="mx-auto max-w-7xl rounded-xl bg-slate-100 p-3 shadow-2xl sm:p-5">
      <header className="mb-3 flex items-start justify-between gap-3 rounded-lg bg-white p-4 print-module-controls"><div><h2 className="text-xl font-black">{copy.title} · {cellText(presentation.title, language)}</h2><p className="mt-1 text-sm font-bold">{presentation.synthetic ? copy.synthetic : String(presentation.documentNo ?? "")}</p></div><button className="rounded border px-4 py-2 font-bold" onClick={onClose}>{copy.close}</button></header>
      {error ? <p role="alert" className="rounded border border-red-300 bg-red-50 p-4 font-bold text-red-900 print-module-controls">{error}</p> : null}
      {!error && !activeOverrides ? <p role="status" className="p-6 text-center font-bold print-module-controls">{copy.loading}</p> : null}
      {activeLoaded && activeOverrides ? <>
        <section className="mb-4 grid gap-3 rounded-lg bg-white p-4 md:grid-cols-4 print-module-controls">
          <label className="grid gap-1 text-sm font-bold">{copy.template}<select className="rounded border p-2" value={activeOverrides.templateId} onChange={(e) => selectTemplate(e.target.value as PrintTemplateId)}>{layoutNames.map(([id,en,ur])=><option key={id} value={id}>{language === "ur" ? ur : en}</option>)}</select></label>
          <label className="grid gap-1 text-sm font-bold">{copy.paper}<select className="rounded border p-2" value={activeOverrides.paperSize} onChange={(e) => setValue("paperSize", e.target.value as PrintPreviewOverrides["paperSize"])}><option value="A4">{copy.a4}</option><option value="A5">{copy.a5}</option></select></label>
          <label className="grid gap-1 text-sm font-bold">{copy.orientation}<select className="rounded border p-2" value={activeOverrides.orientation} onChange={(e) => setValue("orientation", e.target.value as PrintPreviewOverrides["orientation"])}><option value="portrait">{copy.portrait}</option><option value="landscape">{copy.landscape}</option></select></label>
          <label className="grid gap-1 text-sm font-bold">{copy.language}<select className="rounded border p-2" value={activeOverrides.language} onChange={(e) => setValue("language", e.target.value as PrintPreviewOverrides["language"])}><option value="en">English</option><option value="ur">اردو</option></select></label>
          <fieldset className="md:col-span-4"><legend className="text-sm font-bold">{copy.margins}</legend><div className="grid grid-cols-2 gap-2 sm:grid-cols-4">{(["marginTopMm","marginRightMm","marginBottomMm","marginLeftMm"] as const).map((key) =>
           <VoiceTypingField key={key} fieldLabel={`${copy.margins} ${key}`} mode="number"><input aria-label={`${copy.margins} ${key}`} className="rounded border p-2" type="number" min="0" max="30" step="0.1" value={activeOverrides[key]} onChange={(e) => setValue(key, Number(e.target.value))}/></VoiceTypingField>
          )}</div></fieldset>
          <div className="flex flex-wrap gap-4 md:col-span-4">{([["showLogo",copy.logo],["showAddress",copy.address],["showPhone",copy.phone],["showSignatures",copy.signatures],["showStamp",copy.stamp],["showFooter",copy.footer]] as const).map(([key,label])=><label key={key} className="flex items-center gap-2 text-sm font-bold"><input type="checkbox" checked={activeOverrides[key]} onChange={(e)=>setValue(key,e.target.checked)}/>{label}</label>)}</div>
          <div className="flex flex-wrap gap-2 md:col-span-4"><button className="rounded border px-4 py-2 font-bold" onClick={reset}>{copy.reset}</button><button className="rounded bg-slate-900 px-4 py-2 font-bold text-white" disabled={invalid.length>0} onClick={()=>void doPrint()}>{copy.print}</button><button className="rounded border border-blue-700 px-4 py-2 font-bold text-blue-800 disabled:opacity-40" disabled={!activeLoaded.canSave||saving||invalid.length>0} onClick={()=>void saveDefaults()}>{saving?copy.saving:copy.save}</button><button className="rounded border px-4 py-2 font-bold" onClick={onLegacyPrint}>{fallbackLabel}</button></div>
          {activeLoaded.readError ? <p className="text-sm font-bold text-amber-800 md:col-span-4">{strings[activeOverrides.language].readError}</p> : null}
          {activeLoaded.canSave ? <p className="text-xs font-semibold text-slate-600 md:col-span-4">{strings[activeOverrides.language].temporary}</p> : null}
          {message ? <p role="status" className="font-bold text-green-800 md:col-span-4">{message}</p> : null}{error ? <p role="alert" className="font-bold text-red-800 md:col-span-4">{error}</p> : null}
        </section>
        <div className="overflow-auto rounded-lg bg-slate-200 p-3 sm:p-6 print-module-preview" ref={printRef}><ModuleTransportPrintDocument presentation={presentation} branding={activeLoaded.branding} overrides={activeOverrides} logoFailed={logoFailed} onLogoError={()=>setLogoFailed(true)}/></div>
      </> : null}
    </div>
  </div>;
}

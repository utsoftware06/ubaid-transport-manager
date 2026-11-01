"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useReactToPrint } from "react-to-print";
import { getPrintPageRule, getPrintDirection, updatePrintPreviewOverrides } from "@/lib/print/foundation";
import { createDefaultPrintSettings, validatePrintSettingsValues } from "@/lib/print/settings";
import { loadAddaPrintSettings } from "@/lib/print/persistence";
import { resolvePrintBranding } from "@/lib/print/resolvePrintBranding";
import { createVoucherTemplateDefaults } from "@/lib/print/voucherPresentation";
import type { PrintBranding, PrintPreviewOverrides, PrintTemplateId } from "@/lib/print/types";
import type { VoucherPrintPresentation } from "@/lib/print/voucherPresentation";
import { VoucherTemplateDocument, voucherTemplateLanguageCopy } from "./VoucherTemplateDocument";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  presentation: VoucherPrintPresentation;
  language: "en" | "ur";
  onClose: () => void;
  onLegacyPrint: () => void;
};

type ResourceState = {
  addaId: string;
  branding: PrintBranding;
  settings: Awaited<ReturnType<typeof loadAddaPrintSettings>>;
  settingsError: string | null;
  brandingError: string | null;
};
type Draft = { key: string; values: PrintPreviewOverrides };

const emptyBranding = (addaId: string): PrintBranding => ({
  addaId, addaName: "", tagline: null, logoUrl: null, address: null, city: null,
  phone: null, alternatePhone: null, existingPaperSize: null, showLogoByDefault: true, footerText: null,
});

const templateNames = {
  en: { traditional_pad: "Traditional Transport Pad", modern_professional: "Modern Professional", compact_pad: "Compact Pad", detailed_a4: "Detailed A4" },
  ur: { traditional_pad: "روایتی ٹرانسپورٹ پیڈ", modern_professional: "جدید پروفیشنل", compact_pad: "کمپیکٹ پیڈ", detailed_a4: "تفصیلی A4" },
} as const;

export default function VoucherTemplatePrint({ presentation, language, onClose, onLegacyPrint }: Props) {
  const [resource, setResource] = useState<ResourceState | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [fallbackConfirmed, setFallbackConfirmed] = useState(false);
  const [logoFailed, setLogoFailed] = useState(false);
  const printRef = useRef<HTMLDivElement | null>(null);
  const addaId = presentation.addaId;
  const contextKey = `${addaId}:voucher:${presentation.voucherNo}`;

  useEffect(() => {
    let active = true;
    void Promise.allSettled([resolvePrintBranding(addaId), loadAddaPrintSettings(addaId)]).then(([brandResult, settingsResult]) => {
      if (!active) return;
      const branding = brandResult.status === "fulfilled" ? brandResult.value.branding : emptyBranding(addaId);
      const settings = settingsResult.status === "fulfilled" ? settingsResult.value : [];
      setResource({
        addaId,
        branding,
        settings,
        brandingError: brandResult.status === "rejected" ? (brandResult.reason instanceof Error ? brandResult.reason.message : "Branding could not be loaded.") : brandResult.value.settingsError,
        settingsError: settingsResult.status === "rejected" ? (settingsResult.reason instanceof Error ? settingsResult.reason.message : "Saved Voucher defaults could not be loaded.") : null,
      });
    });
    return () => { active = false; };
  }, [addaId, presentation.voucherNo]);

  const currentResource = resource?.addaId === addaId ? resource : null;
  const branding = currentResource?.branding ?? null;
  const savedSettings = currentResource?.settings.find((row) => row.documentType === "voucher") ?? null;
  const base = useMemo(() => branding
    ? savedSettings ?? createVoucherTemplateDefaults(createDefaultPrintSettings(branding))
    : null, [branding, savedSettings]);
  const overrides = base
    ? draft?.key === contextKey ? draft.values : { ...base, language, showFooter: Boolean(branding?.footerText) }
    : null;
  const labels = voucherTemplateLanguageCopy(overrides?.language ?? language);
  const validationErrors = overrides ? validatePrintSettingsValues(overrides) : ["settings_unavailable"];
  const canPreview = Boolean(currentResource && branding?.addaId === addaId && overrides && validationErrors.length === 0
    && (!currentResource.settingsError || savedSettings || fallbackConfirmed)
    && (!currentResource.brandingError || fallbackConfirmed));

  function update<K extends keyof PrintPreviewOverrides>(key: K, value: PrintPreviewOverrides[K]) {
    if (!overrides) return;
    setFallbackConfirmed(false);
    setDraft({ key: contextKey, values: updatePrintPreviewOverrides(overrides, key, value) });
  }

  function selectTemplate(templateId: PrintTemplateId) {
    if (!overrides) return;
    const next = createVoucherTemplateDefaults({ ...overrides, templateId });
    setFallbackConfirmed(false);
    setDraft({ key: contextKey, values: next });
  }

  function resetPreview() {
    if (!base) return;
    setFallbackConfirmed(false);
    setDraft({ key: contextKey, values: { ...base, language, showFooter: Boolean(branding?.footerText) } });
  }

  async function waitForAssets() {
    const images = Array.from(printRef.current?.querySelectorAll("img") ?? []);
    await Promise.race([
      Promise.all(images.map((image) => image.complete ? Promise.resolve() : new Promise<void>((resolve) => {
        image.addEventListener("load", () => resolve(), { once: true });
        image.addEventListener("error", () => resolve(), { once: true });
      }))),
      new Promise<void>((resolve) => window.setTimeout(resolve, 1600)),
    ]);
    if (document.fonts?.ready) await Promise.race([document.fonts.ready.then(() => undefined), new Promise<void>((resolve) => window.setTimeout(resolve, 1000))]);
  }

  const printDocument = useReactToPrint({
    contentRef: printRef,
    documentTitle: presentation.voucherNo,
    pageStyle: overrides ? getPrintPageRule(overrides.paperSize, overrides.orientation, overrides) : undefined,
    onBeforePrint: waitForAssets,
  });

  const urdu = (overrides?.language ?? language) === "ur";
  const words = urdu ? {
    title: "واؤچر پرنٹ پیش نظارہ", template: "لے آؤٹ", paper: "کاغذ", orientation: "رخ", language: "زبان", margins: "حاشیے",
    logo: "لوگو", address: "پتہ", phone: "فون", signatures: "دستخط", stamp: "مہر", footer: "فٹر", a4: "A4", a5: "A5",
    portrait: "پورٹریٹ", landscape: "لینڈ اسکیپ", print: "پرنٹ / پی ڈی ایف محفوظ کریں", close: "بند کریں", reset: "محفوظ ڈیفالٹ بحال کریں",
    legacy: "موجودہ پرنٹ استعمال کریں", loading: "واؤچر کے اڈہ ڈیفالٹس لوڈ ہو رہے ہیں…", settingsError: "محفوظ ڈیفالٹس لوڈ نہیں ہوئے:",
    noDefault: "محفوظ واؤچر ڈیفالٹ نہیں؛ عارضی ترتیب استعمال ہو رہی ہے۔", fallback: "عارضی ترتیب کے ساتھ جاری رکھیں", owner: "مالک اڈہ",
  } : {
    title: "Voucher print preview", template: "Template", paper: "Paper", orientation: "Orientation", language: "Language", margins: "Margins (mm)",
    logo: "Logo", address: "Address", phone: "Phone", signatures: "Signatures", stamp: "Stamp", footer: "Footer", a4: "A4", a5: "A5",
    portrait: "Portrait", landscape: "Landscape", print: "Print / Save as PDF", close: "Close", reset: "Reset preview",
    legacy: "Use existing print", loading: "Loading this Voucher owner Adda’s defaults…", settingsError: "Saved defaults could not be loaded:",
    noDefault: "No saved Voucher default; temporary settings are in use.", fallback: "Continue with temporary settings", owner: "Voucher owner Adda",
  };

  return <div className="fixed inset-0 z-[80] overflow-y-auto bg-slate-950/65 p-2 backdrop-blur-sm sm:p-4" dir={getPrintDirection(overrides?.language ?? language)}>
    <div className="mx-auto my-2 max-w-7xl rounded-2xl bg-slate-100 p-3 shadow-2xl sm:my-5 sm:p-5">
      <header className="mb-4 flex flex-wrap items-start justify-between gap-3 rounded-xl bg-white p-4 voucher-print-ui">
        <div><h2 className="text-xl font-black text-slate-950">{words.title} · <span dir="ltr">{presentation.voucherNo}</span></h2><p className="mt-1 text-sm font-bold text-slate-600">{words.owner}: {branding?.addaName || addaId}</p></div>
        <button type="button" onClick={onClose} className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-extrabold text-slate-800">{words.close}</button>
      </header>
      <section className="mb-4 grid gap-3 rounded-xl bg-white p-4 sm:grid-cols-2 lg:grid-cols-4 voucher-print-ui">
        <label className="grid gap-1 text-sm font-bold">{words.template}<select value={overrides?.templateId ?? "traditional_pad"} disabled={!overrides} onChange={(event) => selectTemplate(event.target.value as PrintTemplateId)} className="rounded-lg border border-slate-300 p-2.5">{(Object.keys(templateNames[language]) as PrintTemplateId[]).map((id) => <option key={id} value={id}>{templateNames[language][id]}</option>)}</select></label>
        <label className="grid gap-1 text-sm font-bold">{words.paper}<select value={overrides?.paperSize ?? "A4"} disabled={!overrides} onChange={(event) => update("paperSize", event.target.value as PrintPreviewOverrides["paperSize"])} className="rounded-lg border border-slate-300 p-2.5"><option value="A4">{words.a4}</option><option value="A5">{words.a5}</option></select></label>
        <label className="grid gap-1 text-sm font-bold">{words.orientation}<select value={overrides?.orientation ?? "portrait"} disabled={!overrides} onChange={(event) => update("orientation", event.target.value as PrintPreviewOverrides["orientation"])} className="rounded-lg border border-slate-300 p-2.5"><option value="portrait">{words.portrait}</option><option value="landscape">{words.landscape}</option></select></label>
        <label className="grid gap-1 text-sm font-bold">{words.language}<select value={overrides?.language ?? language} disabled={!overrides} onChange={(event) => update("language", event.target.value as PrintPreviewOverrides["language"])} className="rounded-lg border border-slate-300 p-2.5"><option value="en">English</option><option value="ur">اردو</option></select></label>
        {(["marginTopMm", "marginRightMm", "marginBottomMm", "marginLeftMm"] as const).map((field, index) =>
         <VoiceTypingField key={field} fieldLabel={`${words.margins} · ${["Top", "Right", "Bottom", "Left"][index]}`} mode="number"><label className="grid gap-1 text-xs font-bold">{`${words.margins} · ${["Top", "Right", "Bottom", "Left"][index]}`}<input type="number" min="0" max="30" step="0.1" value={overrides?.[field] ?? 10} disabled={!overrides} onChange={(event) => update(field, Number(event.target.value))} className="rounded-lg border border-slate-300 p-2" /></label></VoiceTypingField>
        )}
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 sm:col-span-2 lg:col-span-4">{([["showLogo", words.logo], ["showAddress", words.address], ["showPhone", words.phone], ["showSignatures", words.signatures], ["showStamp", words.stamp], ["showFooter", words.footer]] as const).map(([key, label]) => <label key={key} className="inline-flex items-center gap-2 text-sm font-bold"><input type="checkbox" checked={Boolean(overrides?.[key])} disabled={!overrides || (key === "showFooter" && !branding?.footerText)} onChange={(event) => update(key, event.target.checked)} />{label}</label>)}</div>
      </section>
      <div className="mb-4 flex flex-wrap items-center gap-3 rounded-xl bg-white p-4 voucher-print-ui">
        <button type="button" onClick={resetPreview} disabled={!base} className="rounded-lg border border-slate-300 px-4 py-2.5 font-extrabold">{words.reset}</button>
        <button type="button" onClick={onLegacyPrint} className="rounded-lg border border-amber-400 px-4 py-2.5 font-extrabold text-amber-950">{words.legacy}</button>
        <button type="button" onClick={() => { if (canPreview) printDocument(); }} disabled={!canPreview} className="rounded-lg bg-slate-950 px-4 py-2.5 font-extrabold text-white disabled:opacity-50">{words.print}</button>
        {!currentResource ? <span role="status">{words.loading}</span> : null}
        {currentResource?.settingsError ? <div role="alert" className="w-full text-sm font-bold text-amber-900">{words.settingsError} {currentResource.settingsError}<button type="button" onClick={() => setFallbackConfirmed(true)} className="ms-2 underline">{words.fallback}</button></div> : null}
        {currentResource && !currentResource.settingsError && !savedSettings ? <p className="text-sm font-semibold text-slate-700">{words.noDefault}</p> : null}
        {currentResource?.brandingError ? <div role="alert" className="w-full text-sm font-bold text-amber-900">{currentResource.brandingError}<button type="button" onClick={() => setFallbackConfirmed(true)} className="ms-2 underline">{words.fallback}</button></div> : null}
        {validationErrors.length > 0 ? <p role="alert" className="w-full text-sm font-bold text-red-800">{validationErrors.join(", ")}</p> : null}
      </div>
      {presentation.isSyntheticSample ? <p className="mb-3 text-center text-xs font-black uppercase tracking-wide text-slate-600 voucher-print-ui">{labels.sample}</p> : null}
      {branding && overrides ? <div className="overflow-x-auto rounded-xl bg-slate-200 p-3 sm:p-6"><VoucherTemplateDocument presentation={presentation} branding={branding} overrides={overrides} logoFailed={logoFailed} onLogoError={() => setLogoFailed(true)} printRef={printRef} /></div> : null}
      <style dangerouslySetInnerHTML={{ __html: `@media print{.voucher-print-ui{display:none!important}body{background:#fff!important}.voucher-print-root{display:block!important}}` }} />
    </div>
  </div>;
}

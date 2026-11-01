"use client";

/* eslint-disable @next/next/no-img-element -- Adda logos are tenant-supplied URLs and use guarded URL fallback handling. */

import { useEffect, useMemo, useRef, useState, type Ref } from "react";
import { useReactToPrint } from "react-to-print";
import { getPrintDirection, getPrintPageRule, getSafeLogoUrl, updatePrintPreviewOverrides } from "@/lib/print/foundation";
import { createDefaultPrintSettings, validatePrintSettingsValues } from "@/lib/print/settings";
import { loadAddaPrintSettings } from "@/lib/print/persistence";
import { resolvePrintBranding } from "@/lib/print/resolvePrintBranding";
import { missingPrintAddaName } from "@/lib/print/resolvePrintBranding";
import type { PrintBranding, PrintPreviewOverrides, PrintTemplateId } from "@/lib/print/types";
import { supabase } from "@/lib/supabase/client";
import { applyParchiWithholdingToFinancialSummary, getParchiVehicleSettlementTotals } from "@/lib/parchi/vehicleSettlement";
import type { BiltyRow } from "./types";
import {
  BILTY_OFFICE_FINANCIAL_FIELD_OWNERSHIP,
  createBiltyPrintPresentation,
  filterBiltyOfficeFinancials,
  resolveBiltyPrintDefaults,
  type BiltyCopyType,
  type BiltyPrintFinancialSummary,
  type BiltyPrintPresentation,
} from "@/lib/print/biltyPresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type ResourceState = {
  addaId: string;
  biltyId: string;
  status: "ready";
  branding: PrintBranding | null;
  settingsRows: Awaited<ReturnType<typeof loadAddaPrintSettings>>;
  settingsError: string | null;
  brandingError: string | null;
  summary: BiltyPrintFinancialSummary | null;
  summaryError: string | null;
};

type Props = {
  bilty: BiltyRow;
  language: "en" | "ur";
  onClose: () => void;
  onLegacyPrint: (
    includeBiltyDetails: boolean,
    includeVehicleDetails: boolean,
    copyType: BiltyCopyType,
    summary: BiltyPrintFinancialSummary | null,
  ) => void;
};

type PreviewDraft = { key: string; values: PrintPreviewOverrides };

const emptyBranding = (addaId: string): PrintBranding => ({
  addaId, addaName: "", tagline: null, logoUrl: null, address: null, city: null,
  phone: null, alternatePhone: null, existingPaperSize: null,
  showLogoByDefault: true, footerText: null,
});

const copyLabel = (language: "en" | "ur", copy: BiltyCopyType) => ({
  en: { office: "Office Copy", party: "Party Copy", driver: "Driver Copy" },
  ur: { office: "دفتری نقل", party: "پارٹی نقل", driver: "ڈرائیور نقل" },
}[language][copy]);

export default function BiltyTemplatePrint({ bilty, language, onClose, onLegacyPrint }: Props) {
  const [copyType, setCopyType] = useState<BiltyCopyType>("office");
  const [resources, setResources] = useState<ResourceState | null>(null);
  const [overrides, setOverrides] = useState<PreviewDraft | null>(null);
  const [fallbackConfirmedKey, setFallbackConfirmedKey] = useState<string | null>(null);
  const [includeBiltyDetails, setIncludeBiltyDetails] = useState(false);
  const [includeVehicleDetails, setIncludeVehicleDetails] = useState(false);
  const [logoFailedUrl, setLogoFailedUrl] = useState<string | null>(null);
  const printRef = useRef<HTMLElement | null>(null);
  const isUrdu = language === "ur";
  const direction = getPrintDirection(language);
  const addaId = bilty.adda_id;

  useEffect(() => {
    let active = true;
    const brandingTask = resolvePrintBranding(addaId).then((result) => ({
      branding: result.branding,
      error: result.settingsError,
    }));
    const settingsTask = loadAddaPrintSettings(addaId);
    const summaryTask = Promise.all([
      supabase.rpc("get_bilty_financial_summary", { p_bilty_id: bilty.id }),
      getParchiVehicleSettlementTotals(addaId, [bilty.id]),
    ]).then(([summaryResult, parchiTotals]) => {
      if (summaryResult.error) throw summaryResult.error;
      const row = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
      if (!row) throw new Error("BILTY_FINANCIAL_SUMMARY_UNAVAILABLE");
      return applyParchiWithholdingToFinancialSummary(
        row as BiltyPrintFinancialSummary,
        parchiTotals.get(bilty.id)?.withheldCommission ?? 0,
      );
    });

    void Promise.allSettled([brandingTask, settingsTask, summaryTask]).then(([brand, settings, summary]) => {
      if (!active) return;
      const branding = brand.status === "fulfilled" ? brand.value.branding : emptyBranding(addaId);
      const brandingError = brand.status === "rejected"
        ? (brand.reason instanceof Error ? brand.reason.message : "Branding could not be loaded.")
        : brand.value.error;
      setResources({
        addaId,
        biltyId: bilty.id,
        status: "ready",
        branding,
        settingsRows: settings.status === "fulfilled" ? settings.value : [],
        settingsError: settings.status === "rejected"
          ? (settings.reason instanceof Error ? settings.reason.message : "Saved print defaults could not be loaded.")
          : null,
        brandingError,
        summary: summary.status === "fulfilled" ? summary.value : null,
        summaryError: summary.status === "rejected"
          ? (summary.reason instanceof Error ? summary.reason.message : "Bilty financial summary could not be loaded.")
          : null,
      });
    });
    return () => { active = false; };
  }, [addaId, bilty.id]);

  const currentResources = resources?.addaId === addaId && resources.biltyId === bilty.id && resources.status === "ready" ? resources : null;
  const branding = currentResources?.branding;
  const baseSettings = (() => {
    if (!branding || branding.addaId !== addaId) return null;
    try {
      return resolveBiltyPrintDefaults(addaId, branding, currentResources?.settingsRows ?? []);
    } catch {
      return createDefaultPrintSettings(branding);
    }
  })();
  const previewKey = `${addaId}:bilty:${bilty.id}`;
  const effectiveOverrides = baseSettings
    ? (overrides?.key === previewKey ? overrides.values : { ...baseSettings, language, showFooter: Boolean(branding?.footerText) })
    : null;
  const projection = useMemo<BiltyPrintPresentation | null>(() => {
    if (!currentResources) return null;
    if (copyType !== "driver" && !currentResources.summary) return null;
    try { return createBiltyPrintPresentation(bilty, currentResources.summary, copyType); }
    catch { return null; }
  }, [bilty, copyType, currentResources]);
  const renderPresentation = useMemo(() => projection
    ? filterBiltyOfficeFinancials(projection, includeBiltyDetails, includeVehicleDetails)
    : null, [projection, includeBiltyDetails, includeVehicleDetails]);
  const invalidSettings = effectiveOverrides ? validatePrintSettingsValues(effectiveOverrides) : ["settings_unavailable"];

  function updateOverride<K extends keyof PrintPreviewOverrides>(key: K, value: PrintPreviewOverrides[K]) {
    if (!effectiveOverrides) return;
    setFallbackConfirmedKey(null);
    setOverrides({ key: previewKey, values: updatePrintPreviewOverrides(effectiveOverrides, key, value) });
  }

  function selectTemplate(templateId: PrintTemplateId) {
    if (!effectiveOverrides) return;
    const format = templateId === "modern_professional"
      ? { paperSize: "A4" as const, orientation: "landscape" as const }
      : templateId === "compact_pad"
        ? { paperSize: "A5" as const, orientation: "portrait" as const }
        : templateId === "detailed_a4"
          ? { paperSize: "A4" as const, orientation: "portrait" as const }
          : { paperSize: "A5" as const, orientation: "portrait" as const };
    const withPaper = updatePrintPreviewOverrides(effectiveOverrides, "paperSize", format.paperSize);
    const withOrientation = updatePrintPreviewOverrides(withPaper, "orientation", format.orientation);
    setFallbackConfirmedKey(null);
    setOverrides({ key: previewKey, values: updatePrintPreviewOverrides(withOrientation, "templateId", templateId) });
  }

  function resetPreview() {
    if (!baseSettings) return;
    setOverrides({ key: previewKey, values: { ...baseSettings, language, showFooter: Boolean(branding?.footerText) } });
    setFallbackConfirmedKey(null);
  }

  const savedTemplateExists = Boolean(currentResources?.settingsRows.some((row) => row.addaId === addaId && row.documentType === "bilty"));
  const canUsePreview = Boolean(currentResources && effectiveOverrides && projection && invalidSettings.length === 0
    && (!currentResources.settingsError || savedTemplateExists || fallbackConfirmedKey === previewKey));
  const previewReady = canUsePreview && (copyType === "driver" || !currentResources?.summaryError);
  const logoFailed = Boolean(branding?.logoUrl && logoFailedUrl === branding.logoUrl);

  async function waitForPrintAssets() {
    const images = Array.from(printRef.current?.querySelectorAll("img") ?? []);
    await Promise.race([
      Promise.all(images.map((image) => image.complete ? Promise.resolve() : new Promise<void>((resolve) => {
        image.addEventListener("load", () => resolve(), { once: true });
        image.addEventListener("error", () => resolve(), { once: true });
      }))),
      new Promise<void>((resolve) => window.setTimeout(resolve, 1800)),
    ]);
    if (document.fonts?.ready) {
      await Promise.race([
        document.fonts.ready.then(() => undefined),
        new Promise<void>((resolve) => window.setTimeout(resolve, 1200)),
      ]);
    }
  }

  const printDocument = useReactToPrint({
    contentRef: printRef,
    documentTitle: `${bilty.booking_no} - ${copyLabel(language, copyType)}`,
    pageStyle: effectiveOverrides ? getPrintPageRule(effectiveOverrides.paperSize, effectiveOverrides.orientation, effectiveOverrides) : undefined,
    onBeforePrint: waitForPrintAssets,
  });

  const words = isUrdu ? {
    title: "مال برداری بلٹی", copy: copyLabel("ur", copyType), template: "لے آؤٹ", paper: "کاغذ",
    orientation: "رخ", language: "زبان", margins: "حاشیے", logo: "لوگو", address: "پتہ",
    phone: "فون", signatures: "دستخط", stamp: "مہر", footer: "فٹر", a4: "A4", a5: "A5",
    portrait: "پورٹریٹ", landscape: "لینڈ اسکیپ", print: "پرنٹ / پی ڈی ایف محفوظ کریں",
    close: "بند کریں", reset: "محفوظ ڈیفالٹ بحال کریں", legacy: "پرانا پرنٹ استعمال کریں",
    saved: "اس بلٹی کے مالک اڈے کے محفوظ ڈیفالٹس استعمال ہو رہے ہیں۔",
    fallback: "محفوظ ڈیفالٹ دستیاب نہیں؛ یہ عارضی لے آؤٹ ہے۔", confirm: "عارضی ڈیفالٹس کے ساتھ جاری رکھیں",
    loading: "بلٹی کی برانڈنگ اور محفوظ ڈیفالٹس لوڈ ہو رہے ہیں…", financialUnavailable: "محفوظ بلٹی مالی خلاصہ دستیاب نہیں؛ دفتر/پارٹی کا نیا پرنٹ بند ہے۔",
    noFinancial: "ڈرائیور نقل میں مالی معلومات شامل نہیں ہیں۔", settingsError: "محفوظ ڈیفالٹس لوڈ نہیں ہوئے:",
    includeBiltyDetails: "بلٹی / پارٹی مالی تفصیل شامل کریں (صرف دفتر نقل)", includeVehicleDetails: "گاڑی کے کرائے کی تفصیل شامل کریں (صرف دفتر نقل)", officeOnly: "یہ دونوں اختیارات صرف دفتر نقل پر لاگو ہیں۔",
  } : {
    title: "GOODS TRANSPORT BILTY", copy: copyLabel("en", copyType), template: "Template", paper: "Paper",
    orientation: "Orientation", language: "Language", margins: "Margins (mm)", logo: "Logo", address: "Address",
    phone: "Phone", signatures: "Signatures", stamp: "Stamp", footer: "Footer", a4: "A4", a5: "A5",
    portrait: "Portrait", landscape: "Landscape", print: "Print / Save as PDF", close: "Close",
    reset: "Reset preview", legacy: "Print legacy format", saved: "Saved defaults for the Bilty owner Adda are applied.",
    fallback: "No saved Bilty defaults were found. These are temporary values.", confirm: "Continue with temporary defaults",
    loading: "Loading this Bilty's Adda branding and saved defaults…",
    financialUnavailable: "The saved Bilty financial summary is unavailable. New Office/Party printing is disabled.",
    noFinancial: "This Driver copy contains no financial section.", settingsError: "Saved defaults could not be loaded:",
    includeBiltyDetails: "Include Bilty / party financial details (Office copy only)", includeVehicleDetails: "Include vehicle freight details (Office copy only)", officeOnly: "These two options apply to the Office copy only.",
  };

  const templateOptions: Array<{ id: PrintTemplateId; label: string }> = [
    { id: "traditional_pad", label: isUrdu ? "روایتی ٹرانسپورٹ پیڈ" : "Traditional Pakistani Pad" },
    { id: "modern_professional", label: isUrdu ? "جدید پروفیشنل" : "Modern Professional" },
    { id: "compact_pad", label: isUrdu ? "کمپیکٹ پیڈ" : "Compact Pad" },
    { id: "detailed_a4", label: isUrdu ? "تفصیلی A4" : "Detailed A4" },
  ];

  return (
    <div className="fixed inset-0 z-[70] overflow-y-auto bg-slate-950/65 p-2 backdrop-blur-sm sm:p-4">
      <div className="mx-auto my-2 max-w-7xl rounded-2xl bg-slate-100 p-3 shadow-2xl sm:my-5 sm:p-5" dir={direction}>
        <header className="bilty-print-controls mb-4 flex flex-wrap items-start justify-between gap-3 rounded-xl bg-white p-4">
          <div><h2 className="text-xl font-black text-slate-950">{words.title} · <span dir="ltr">{bilty.booking_no}</span></h2><p className="mt-1 text-sm font-bold text-slate-600">{words.copy}</p></div>
          <button type="button" onClick={onClose} className="rounded-lg border border-slate-300 bg-white px-4 py-2 font-extrabold text-slate-800">{words.close}</button>
        </header>

        <section className="bilty-print-controls mb-4 grid gap-3 rounded-xl bg-white p-4 sm:grid-cols-2 lg:grid-cols-4">
          <label className="grid gap-1 text-sm font-bold">{isUrdu ? "نقل" : "Copy"}<select value={copyType} onChange={(event) => setCopyType(event.target.value as BiltyCopyType)} className="rounded-lg border border-slate-300 p-2.5">
            <option value="office">{copyLabel(language, "office")}</option><option value="party">{copyLabel(language, "party")}</option><option value="driver">{copyLabel(language, "driver")}</option>
          </select></label>
          <label className="grid gap-1 text-sm font-bold">{words.template}<select disabled={!effectiveOverrides} value={effectiveOverrides?.templateId ?? "traditional_pad"} onChange={(event) => selectTemplate(event.target.value as PrintTemplateId)} className="rounded-lg border border-slate-300 p-2.5">
            {templateOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select></label>
          <label className="grid gap-1 text-sm font-bold">{words.paper}<select disabled={!effectiveOverrides} value={effectiveOverrides?.paperSize ?? "A4"} onChange={(event) => updateOverride("paperSize", event.target.value as PrintPreviewOverrides["paperSize"])} className="rounded-lg border border-slate-300 p-2.5"><option value="A4">{words.a4}</option><option value="A5">{words.a5}</option></select></label>
          <label className="grid gap-1 text-sm font-bold">{words.orientation}<select disabled={!effectiveOverrides} value={effectiveOverrides?.orientation ?? "portrait"} onChange={(event) => updateOverride("orientation", event.target.value as PrintPreviewOverrides["orientation"])} className="rounded-lg border border-slate-300 p-2.5"><option value="portrait">{words.portrait}</option><option value="landscape">{words.landscape}</option></select></label>
          <label className="grid gap-1 text-sm font-bold">{words.language}<select disabled={!effectiveOverrides} value={effectiveOverrides?.language ?? language} onChange={(event) => updateOverride("language", event.target.value as PrintPreviewOverrides["language"])} className="rounded-lg border border-slate-300 p-2.5"><option value="en">English</option><option value="ur">اردو</option></select></label>
          {(["marginTopMm", "marginRightMm", "marginBottomMm", "marginLeftMm"] as const).map((field, index) =>
           <VoiceTypingField key={field} fieldLabel={`${words.margins} · ${["Top", "Right", "Bottom", "Left"][index]}`} mode="number"><label className="grid gap-1 text-xs font-bold">{`${words.margins} · ${["Top", "Right", "Bottom", "Left"][index]}`}<input disabled={!effectiveOverrides} type="number" min="0" max="30" step="0.1" value={effectiveOverrides?.[field] ?? 10} onChange={(event) => updateOverride(field, Number(event.target.value))} className="rounded-lg border border-slate-300 p-2" /></label></VoiceTypingField>
          )}
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2 sm:col-span-2 lg:col-span-4">
            {([ ["showLogo", words.logo], ["showAddress", words.address], ["showPhone", words.phone], ["showSignatures", words.signatures], ["showStamp", words.stamp], ["showFooter", words.footer] ] as const).map(([field, label]) => <label key={field} className="inline-flex items-center gap-2 text-sm font-bold"><input type="checkbox" checked={effectiveOverrides?.[field] ?? false} disabled={!effectiveOverrides || (field === "showFooter" && !branding?.footerText)} onChange={(event) => updateOverride(field, event.target.checked)} />{label}</label>)}
          </div>
        </section>

        <section className="bilty-print-controls mb-4 flex flex-wrap items-center gap-3 rounded-xl bg-white p-4">
          <button type="button" onClick={resetPreview} disabled={!baseSettings} className="rounded-lg border border-slate-300 px-4 py-2.5 font-extrabold">{words.reset}</button>
          <button type="button" onClick={() => onLegacyPrint(
            includeBiltyDetails,
            includeVehicleDetails,
            copyType,
            currentResources?.summary?.bilty_id === bilty.id ? currentResources.summary : null,
          )} className="rounded-lg border border-amber-400 px-4 py-2.5 font-extrabold text-amber-950">{words.legacy}</button>
          <label className="inline-flex items-center gap-2 text-sm font-semibold"><input type="checkbox" checked={includeBiltyDetails} disabled={copyType !== "office"} onChange={(event) => setIncludeBiltyDetails(event.target.checked)} />{words.includeBiltyDetails}</label>
          <label className="inline-flex items-center gap-2 text-sm font-semibold"><input type="checkbox" checked={includeVehicleDetails} disabled={copyType !== "office"} onChange={(event) => setIncludeVehicleDetails(event.target.checked)} />{words.includeVehicleDetails}</label>
          <p className="w-full text-xs font-medium text-slate-600">{words.officeOnly}</p>
          <button type="button" onClick={() => { if (previewReady) printDocument(); }} disabled={!previewReady} className="rounded-lg bg-slate-950 px-4 py-2.5 font-extrabold text-white disabled:cursor-not-allowed disabled:opacity-50">{words.print}</button>
          {!currentResources ? <span role="status" className="text-sm font-bold text-slate-700">{words.loading}</span> : null}
          {currentResources?.settingsError ? <div role="alert" className="w-full text-sm font-bold text-amber-900">{words.settingsError} {currentResources.settingsError}<button type="button" onClick={() => setFallbackConfirmedKey(previewKey)} className="ms-2 underline">{words.confirm}</button></div> : null}
          {currentResources && !currentResources.settingsError && !currentResources.settingsRows.some((row) => row.documentType === "bilty") ? <p className="text-sm font-semibold text-slate-700">{words.fallback}</p> : null}
          {currentResources?.brandingError ? <p role="alert" className="w-full text-sm font-bold text-amber-900">Branding fallback: {currentResources.brandingError}</p> : null}
          {currentResources?.summaryError ? <p role="alert" className="w-full text-sm font-bold text-red-800">{words.financialUnavailable} {currentResources.summaryError}</p> : null}
          {currentResources && copyType !== "driver" && !currentResources.summary && !currentResources.summaryError ? <p role="alert" className="w-full text-sm font-bold text-red-800">{words.financialUnavailable}</p> : null}
          {copyType === "driver" ? <p className="text-sm font-semibold text-slate-700">{words.noFinancial}</p> : null}
          {invalidSettings.length > 0 ? <p role="alert" className="w-full text-sm font-bold text-red-800">Invalid print margins or settings: {invalidSettings.join(", ")}</p> : null}
          {currentResources && !currentResources.settingsError && savedTemplateExists ? <p role="status" className="text-sm font-semibold text-green-800">{words.saved}</p> : null}
        </section>

        <div className="overflow-x-auto rounded-xl bg-slate-300 p-2 sm:p-4">
          {renderPresentation && effectiveOverrides && branding ? (
            <BiltyTemplateDocument presentation={renderPresentation} branding={branding} overrides={effectiveOverrides} logoFailed={logoFailed} onLogoError={() => setLogoFailedUrl(branding.logoUrl)} printRef={printRef} />
          ) : <div className="rounded-xl bg-white p-8 text-center font-bold text-slate-700">{!currentResources ? words.loading : copyType !== "driver" ? words.financialUnavailable : words.settingsError}</div>}
        </div>
      </div>
    </div>
  );
}

const labelsEn: Record<string, string> = {
  office: "Office Copy", party: "Party Copy", driver: "Driver Copy", biltyNo: "Bilty No.", date: "Booking Date",
  loading: "Loading Date", departure: "Departure", arrival: "Arrival", group: "Movement Group / Outbound Bilty",
  trip: "Trip Type", freightType: "Freight Type", biltyType: "Vehicle Type", loadingSource: "Loaded Through", freightReceivableFrom: "Collection Source", partyName: "Party", broker: "Broker",
  reference: "Reference No.", from: "From", to: "To", sender: "Sender", receiver: "Receiver", vehicle: "Vehicle No.",
  vehicleType: "Vehicle Type", owner: "Owner", externalOwner: "External Vehicle", items: "Goods Details", serial: "No.",
  goods: "Goods Description", quantity: "Quantity", weight: "Weight", unit: "Unit", remarks: "Remarks", container: "Container / Cargo Details",
  signatures: "Signatures", prepared: "Prepared By", receiverSign: "Receiver Signature", authorized: "Authorized Signature", stamp: "Stamp",
  footer: "Footer",
  amount: "Amount", paymentStatus: "Payment Status", printNote: "Values shown are copied from the saved Bilty and authorized financial summary; no totals are recalculated.",
  totalBiltyFreight: "Total Bilty Freight", advanceReceived: "Advance Received", laterReceived: "Later Receipts", totalReceived: "Total Received",
  balanceReceivable: "Balance Receivable", vehicleFreight: "Vehicle Freight", advanceVehicle: "Vehicle Advance", laterVehiclePaid: "Later Vehicle Payments",
  totalVehiclePaid: "Actual Vehicle Cash Paid", parchiWithheldCommission: "Noncash Parchi Withholding", vehicleEntitlementSettled: "Vehicle Entitlement Settled",
  vehicleBalance: "Vehicle Balance", addaCommission: "Adda Commission", brokerBrokerage: "Broker Brokerage",
  xlWeight: "Overweight", mtReceivable: "MT Receivable", mtPayable: "MT Payable", loloCharges: "LOLO Charges", otherIncome: "Other Income", lessDeduction: "Less / Deduction",
  partyCommission: "Party Commission", advanceCommission: "Advance Commission", advanceBrokerage: "Advance Brokerage", savedBrokerCommission: "Saved Broker Commission",
  savedOverweightCharges: "Saved Overweight Charges", savedDetainCharges: "Saved Detain Charges", savedMtReceivable: "Saved MT Receivable", savedMtPayable: "Saved MT Payable", savedDeductionAdjustment: "Saved Deduction Adjustment",
  freight: "Party Freight", advance: "Advance", receipts: "Later Receipts", received: "Total Received", balance: "Remaining Balance",
};

const labelsUr: Record<string, string> = {
  office: "دفتری نقل", party: "پارٹی نقل", driver: "ڈرائیور نقل", biltyNo: "بلٹی نمبر", date: "بلٹی تاریخ",
  loading: "لوڈنگ تاریخ", departure: "روانگی", arrival: "آمد", group: "موومنٹ گروپ / روانگی بلٹی", trip: "سفر کی قسم",
  freightType: "کرایہ کی قسم", biltyType: "گاڑی کی قسم", loadingSource: "لوڈنگ کا ذریعہ", freightReceivableFrom: "وصولی کا ذریعہ", partyName: "پارٹی", broker: "بروکر", reference: "حوالہ نمبر",
  from: "روانگی مقام", to: "منزل", sender: "بھیجنے والا", receiver: "وصول کنندہ", vehicle: "گاڑی نمبر", vehicleType: "گاڑی کی قسم",
  owner: "مالک", externalOwner: "بیرونی گاڑی", items: "سامان کی تفصیل", serial: "نمبر", goods: "سامان", quantity: "مقدار", weight: "وزن",
  unit: "اکائی", remarks: "تفصیل", container: "کنٹینر / کارگو تفصیل", signatures: "دستخط", prepared: "تیار کنندہ", receiverSign: "وصول کنندہ کے دستخط",
  authorized: "مجاز دستخط", stamp: "مہر", amount: "رقم", paymentStatus: "ادائیگی کی حالت", printNote: "رقوم محفوظ بلٹی اور مالی خلاصے سے لی گئی ہیں؛ یہاں کوئی حساب دوبارہ نہیں کیا گیا۔",
  footer: "فٹر",
  totalBiltyFreight: "کل بلٹی کرایہ", advanceReceived: "پیشگی وصول", laterReceived: "بعد کی وصولیاں", totalReceived: "کل وصول شدہ", balanceReceivable: "باقی وصولی",
  vehicleFreight: "گاڑی کا کرایہ", advanceVehicle: "گاڑی پیشگی", laterVehiclePaid: "بعد کی گاڑی ادائیگیاں", totalVehiclePaid: "اصل نقد گاڑی ادائیگی",
  parchiWithheldCommission: "پارچی کی غیر نقد کٹوتی", vehicleEntitlementSettled: "گاڑی کے حق کی سیٹلمنٹ", vehicleBalance: "گاڑی بقایا",
  addaCommission: "اڈہ کمیشن", brokerBrokerage: "بروکر کمیشن", xlWeight: "اوور ویٹ", mtReceivable: "ایم ٹی وصولی", mtPayable: "ایم ٹی ادائیگی",
  loloCharges: "لو لو چارجز", otherIncome: "دیگر آمدن", lessDeduction: "کٹوتی", freight: "پارٹی کرایہ", advance: "پیشگی", receipts: "بعد کی وصولیاں",
  partyCommission: "پارٹی کمیشن", advanceCommission: "پیشگی کمیشن", advanceBrokerage: "پیشگی بروکریج", savedBrokerCommission: "محفوظ بروکر کمیشن",
  savedOverweightCharges: "محفوظ اوور ویٹ چارجز", savedDetainCharges: "محفوظ ڈیٹین چارجز", savedMtReceivable: "محفوظ ایم ٹی وصولی", savedMtPayable: "محفوظ ایم ٹی ادائیگی", savedDeductionAdjustment: "محفوظ کٹوتی ایڈجسٹمنٹ",
  received: "کل وصول شدہ", balance: "باقی رقم",
};

function templateText(language: "en" | "ur", key: string): string {
  return (language === "ur" ? labelsUr : labelsEn)[key] ?? labelsEn[key] ?? key;
}

function valueText(value: unknown, language: "en" | "ur"): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "number" || (typeof value === "string" && /^-?\d+(?:\.\d+)?$/.test(value))) return `Rs. ${String(value)}`;
  if (typeof value === "string" && ["paid", "partial", "unpaid"].includes(value.toLowerCase())) {
    return language === "ur" ? ({ paid: "ادا شدہ", partial: "جزوی", unpaid: "غیر ادا شدہ" }[value.toLowerCase()] ?? value) : value.toUpperCase();
  }
  return String(value);
}

function displayedFieldValue(value: string | null, language: "en" | "ur" = "en", key?: string): string {
  if (!value?.trim()) return "—";
  const normalized = value.toLowerCase();
  if (key === "trip") {
    const values: Record<string, [string, string]> = {
      outbound: ["Rawangi / Outbound", "روانگی"], local: ["Local", "مقامی"], return: ["Wapsi / Return", "واپسی"],
    };
    return values[normalized]?.[language === "ur" ? 1 : 0] ?? value;
  }
  if (key === "freightType") {
    const values: Record<string, [string, string]> = {
      paid: ["Paid", "ادا شدہ"], advance: ["Advance", "پیشگی"], to_pay: ["To Pay", "قابل ادائیگی"],
    };
    return values[normalized]?.[language === "ur" ? 1 : 0] ?? value;
  }
  if (key === "biltyType") {
    const values: Record<string, [string, string]> = {
      self_vehicle: ["Own Vehicle", "اپنی گاڑی"], other_vehicle: ["Other Vehicle", "بیرونی گاڑی"],
    };
    return values[normalized]?.[language === "ur" ? 1 : 0] ?? value;
  }
  if (key === "loadingSource" || key === "freightReceivableFrom") {
    const values: Record<string, [string, string]> = {
      own_adda: ["Own Adda", "اپنا اڈہ"], other_adda: ["Other Adda", "دوسرا اڈہ"],
      existing_counterparty: ["Existing Counterparty", "موجودہ فریق"],
    };
    return values[normalized]?.[language === "ur" ? 1 : 0] ?? value;
  }
  return value;
}

export function BiltyTemplateDocument({
  presentation, branding, overrides, logoFailed, onLogoError, printRef,
}: {
  presentation: BiltyPrintPresentation;
  branding: PrintBranding;
  overrides: PrintPreviewOverrides;
  logoFailed: boolean;
  onLogoError: () => void;
  printRef?: Ref<HTMLElement>;
}) {
  const language = overrides.language;
  const labels = (key: string) => templateText(language, key);
  const isUrdu = language === "ur";
  const logoUrl = overrides.showLogo ? getSafeLogoUrl(branding.logoUrl) : null;
  const showLogo = Boolean(logoUrl && !logoFailed);
  const copy = labels(presentation.copyType);
  const pageClass = `bilty-template-page bilty-template-${overrides.templateId} bilty-template-${overrides.paperSize.toLowerCase()}-${overrides.orientation}`;
  const details = ([
    ["biltyNo", presentation.biltyNo], ["date", presentation.bookingDate], ["loading", presentation.loadingDate],
    ["departure", presentation.departureDate], ["arrival", presentation.arrivalDate], ["trip", presentation.tripType],
    ["freightType", presentation.freightType], ["biltyType", presentation.biltyType], ["loadingSource", presentation.loadingSource],
    ["freightReceivableFrom", presentation.freightReceivableFrom], ["partyName", presentation.partyName],
    ["broker", presentation.brokerName], ["sender", presentation.senderName], ["receiver", presentation.receiverName],
    ["reference", presentation.referenceNo], ["from", presentation.routeFrom], ["to", presentation.routeTo],
    ["vehicle", presentation.vehicleNo], ["vehicleType", presentation.vehicleType], ["owner", presentation.vehicleOwner],
    ["group", presentation.movementGroupNo],
  ] as Array<[string, string | null]>).filter((row): row is [string, string] => row[1] !== null);
  const detailLabel = (key: string) => labels(key === "owner" && presentation.externalOwner ? "externalOwner" : key);
  const moneyRows = presentation.copyType === "office" ? presentation.officeFinancials : presentation.copyType === "party" ? presentation.partyFinancials : [];
  const officeFinancialLabels: Record<string, string> = {
    totalBiltyFreight: "totalBiltyFreight", advanceReceived: "advanceReceived", laterReceived: "laterReceived",
    totalReceived: "totalReceived", balanceReceivable: "balanceReceivable", paymentStatus: "paymentStatus",
    vehicleFreight: "vehicleFreight", advanceVehicle: "advanceVehicle", laterVehiclePaid: "laterVehiclePaid",
    totalVehiclePaid: "totalVehiclePaid", parchiWithheldCommission: "parchiWithheldCommission", vehicleEntitlementSettled: "vehicleEntitlementSettled",
    vehicleBalance: "vehicleBalance", savedBrokerCommission: "savedBrokerCommission",
    savedOverweightCharges: "savedOverweightCharges", loloCharges: "loloCharges", savedDetainCharges: "savedDetainCharges",
    addaCommission: "addaCommission",
  };
  const partyFinancialLabels: Record<string, string> = {
    freight: "freight", advance: "advance", laterReceipts: "receipts", totalReceived: "received",
    balance: "balance", paymentStatus: "paymentStatus",
  };
  const moneyDetails = moneyRows.flatMap((row) => {
    if (row.value === null || row.value === undefined) return [];
    const labelKey = presentation.copyType === "office" ? officeFinancialLabels[row.key] : partyFinancialLabels[row.key];
    if (!labelKey) return [];
    const section = presentation.copyType === "office"
      ? BILTY_OFFICE_FINANCIAL_FIELD_OWNERSHIP[row.key as keyof typeof BILTY_OFFICE_FINANCIAL_FIELD_OWNERSHIP]
      : "bilty";
    return [{ key: row.key, label: labels(labelKey), value: valueText(row.value, language), section }];
  });
  const selectDetails = (keys: string[]) => details.filter(([key]) => keys.includes(key));
  const identity = <div className="bilty-adda-brand">
    {showLogo ? <img src={logoUrl ?? undefined} alt="" className="bilty-template-logo" onError={onLogoError} /> : null}
    <div className="bilty-adda-brand-copy">
      <h1>{branding.addaName.trim() || missingPrintAddaName(language)}</h1>
      {branding.tagline ? <p>{branding.tagline}</p> : null}
      {overrides.showAddress && [branding.address, branding.city].filter((item) => item?.trim()).map((item, index) => <p key={`address-${index}`}>{item}</p>)}
      {overrides.showPhone && [branding.phone, branding.alternatePhone].filter((item) => item?.trim()).map((item, index) => <p key={`phone-${index}`}>{item}</p>)}
      {overrides.showLogo && branding.logoUrl && logoFailed ? <small>{isUrdu ? "لوگو دستیاب نہیں" : "Logo unavailable"}</small> : null}
    </div>
  </div>;
  const numberBox = <div className="bilty-number-box">
    <small>{labels("biltyNo")}</small><strong dir="ltr">{presentation.biltyNo}</strong>
    {presentation.bookingDate ? <span><b>{labels("date")}:</b> <span dir="ltr">{presentation.bookingDate}</span></span> : null}
    {presentation.referenceNo ? <span><b>{labels("reference")}:</b> <span dir="auto">{presentation.referenceNo}</span></span> : null}
  </div>;
  const title = <div className="bilty-document-heading">
    <h2 lang="ur" dir="rtl">مال برداری بلٹی</h2>
    <span>{isUrdu ? "بلٹی" : "GOODS TRANSPORT BILTY"}</span>
    <b className="bilty-copy-badge">{copy}</b>
  </div>;
  const truck = <img src="/images/print/transport-truck.svg" alt="" className="bilty-truck-illustration" />;
  const goodsTable = <table className="bilty-template-items">
    <thead><tr><th>{labels("serial")}</th><th>{labels("goods")}</th><th>{labels("quantity")}</th><th>{labels("weight")}</th><th>{labels("unit")}</th><th>{labels("remarks")}</th></tr></thead>
    <tbody>{presentation.items.map((item, index) => <tr key={`${item.line_no}-${index}`}><td dir="ltr">{index + 1}</td><td dir="auto">{item.goods_name || "—"}</td><td dir="ltr">{String(item.quantity ?? "—")}</td><td dir="ltr">{item.weight == null ? "—" : String(item.weight)}</td><td dir="auto">{item.unit || "—"}</td><td dir="auto">{item.remarks || "—"}</td></tr>)}</tbody>
  </table>;
  const renderFinancialSection = (sectionName: string, heading: string, rows: typeof moneyDetails) => rows.length ? <section key={sectionName} className={`bilty-template-financial bilty-financial-${sectionName}`}>
    <h3>{heading}</h3>
    <dl>{rows.map(({ key, label, value }) => <div key={key}><dt>{label}</dt><dd dir="ltr">{value}</dd></div>)}</dl>
  </section> : null;
  const financialSection = presentation.copyType === "office" ? <>
    {renderFinancialSection("bilty", isUrdu ? "پارٹی / بلٹی کرایہ اور وصولیاں" : "PARTY / BILTY FREIGHT & RECEIPTS", moneyDetails.filter((row) => row.section === "bilty"))}
    {renderFinancialSection("vehicle", isUrdu ? "گاڑی کا کرایہ اور ادائیگیاں" : "VEHICLE FREIGHT & PAYMENTS", moneyDetails.filter((row) => row.section === "vehicle"))}
    {renderFinancialSection("combined", isUrdu ? "اڈہ کمیشن" : "COMBINED ADDA SUMMARY", moneyDetails.filter((row) => row.section === "both"))}
  </> : presentation.copyType === "party"
    ? renderFinancialSection("party", isUrdu ? "پارٹی کرایہ اور وصولیاں" : "PARTY FREIGHT & RECEIPTS", moneyDetails)
    : null;
  const signatures = overrides.showSignatures || overrides.showStamp ? <section className="bilty-template-signatures">
    {overrides.showSignatures ? <><div><span />{labels("prepared")}</div><div><span />{labels("receiverSign")}</div><div><span />{labels("authorized")}</div></> : null}
    {overrides.showStamp ? <div className="bilty-stamp-space"><span />{labels("stamp")}</div> : null}
  </section> : null;
  const footer = overrides.showFooter && branding.footerText ? <p className="bilty-template-footer">{branding.footerText}</p> : null;
  const note = presentation.copyType === "driver" ? null : <p className="bilty-template-note">{labels("printNote")}</p>;
  const infoFields = (fields: Array<[string, string]>, className: string) => <div className={className}>
    {fields.map(([key, value]) => <div className="bilty-info-field" key={key}><b>{detailLabel(key)}</b><span dir={key === "date" || key === "loading" || key === "departure" || key === "arrival" ? "ltr" : "auto"}>{displayedFieldValue(value, language, key)}</span></div>)}
  </div>;
  const visibleContacts = ([
    ["sender", presentation.senderName], ["receiver", presentation.receiverName],
  ] as Array<[string, string | null]>).filter((entry): entry is [string, string] => Boolean(entry[1]?.trim()));
  const contacts = visibleContacts.length ? <section className="bilty-contact-lines">
    {visibleContacts.map(([key, value]) => <p key={key}><b>{labels(key)}:</b><span dir="auto">{value}</span>{key === "sender" && presentation.senderPhone ? <small dir="ltr">{presentation.senderPhone}</small> : null}{key === "receiver" && presentation.receiverPhone ? <small dir="ltr">{presentation.receiverPhone}</small> : null}</p>)}
  </section> : null;
  const containerDetails = presentation.containerDetails.length ? <section className="bilty-template-container"><h3>{labels("container")}</h3>{presentation.containerDetails.map((field) => <span key={field.label}><b>{field.label}:</b> {field.value}</span>)}</section> : null;
  const traditionalFields = selectDetails(["loading", "departure", "arrival", "trip", "freightType", "biltyType", "loadingSource", "freightReceivableFrom", "partyName", "broker", "reference", "from", "to", "vehicle", "vehicleType", "owner", "group"]);
  const modernJourney = selectDetails(["loading", "departure", "arrival", "trip", "freightType", "loadingSource", "freightReceivableFrom", "group"]);
  const modernParties = selectDetails(["partyName", "broker", "vehicle", "vehicleType", "owner", "biltyType"]);
  const detailedDocument = selectDetails(["loading", "departure", "arrival", "trip", "freightType", "biltyType", "loadingSource", "freightReceivableFrom", "group", "from", "to"]);
  const detailedParties = selectDetails(["partyName", "broker", "vehicle", "vehicleType", "owner"]);

  return <>
    <style>{getPrintPageRule(overrides.paperSize, overrides.orientation, overrides)}</style>
    <article id="bilty-template-print" ref={printRef} className={pageClass} lang={language} dir={getPrintDirection(language)}>
      {presentation.isSyntheticSample ? <div className="bilty-template-sample-mark">SYNTHETIC SAMPLE · NOT A BUSINESS RECORD</div> : null}
      {overrides.templateId === "traditional_pad" ? <>
        <header className="bilty-traditional-head">
          <div className="bilty-traditional-title-row">{truck}<div className="bilty-traditional-title">{title}</div>{numberBox}</div>
          <div className="bilty-traditional-brand-row">{identity}<span className="bilty-traditional-copy">{copy}</span></div>
        </header>
        {infoFields(traditionalFields, "bilty-traditional-fields")}
        {contacts}{containerDetails}
        <section className="bilty-goods-section bilty-traditional-goods"><h3>{labels("items")}</h3>{goodsTable}</section>
        {financialSection}{note}{signatures}{footer}
      </> : null}
      {overrides.templateId === "modern_professional" ? <>
        <header className="bilty-modern-head"><div className="bilty-modern-branding">{identity}{numberBox}</div><div className="bilty-modern-title-row">{title}<div className="bilty-modern-route"><small>{isUrdu ? "سفر کا راستہ" : "TRANSPORT ROUTE"}</small><strong dir="auto">{displayedFieldValue(presentation.routeFrom, language)} <b aria-hidden="true">→</b> {displayedFieldValue(presentation.routeTo, language)}</strong></div></div></header>
        <section className="bilty-modern-panels">
          <div className="bilty-modern-panel"><h3>{isUrdu ? "دستاویز اور سفر" : "DOCUMENT & JOURNEY"}</h3>{infoFields(modernJourney, "bilty-modern-field-grid")}</div>
          <div className="bilty-modern-panel"><h3>{isUrdu ? "فریقین اور گاڑی" : "PARTIES & VEHICLE"}</h3>{infoFields(modernParties, "bilty-modern-field-grid")}</div>
        </section>
        {contacts}{containerDetails}
        <section className="bilty-goods-section bilty-modern-goods"><h3>{labels("items")}</h3>{goodsTable}</section>
        {financialSection}{note}{signatures}{footer}
      </> : null}
      {overrides.templateId === "compact_pad" ? <>
        <header className="bilty-compact-head"><div className="bilty-compact-top">{truck}{identity}{numberBox}</div><div className="bilty-compact-heading">{title}</div></header>
        <div className="bilty-compact-route"><b>{labels("from")}:</b><strong dir="auto">{displayedFieldValue(presentation.routeFrom, language)} <span aria-hidden="true">→</span> {displayedFieldValue(presentation.routeTo, language)}</strong></div>
        {infoFields(selectDetails(["loading", "departure", "arrival", "trip", "freightType", "biltyType", "loadingSource", "freightReceivableFrom", "partyName", "broker", "vehicle", "vehicleType", "owner", "group"]), "bilty-compact-fields")}
        {contacts}{containerDetails}
        <section className="bilty-goods-section bilty-compact-goods"><h3>{labels("items")}</h3>{goodsTable}</section>
        {financialSection}{note}{signatures}{footer}
      </> : null}
      {overrides.templateId === "detailed_a4" ? <>
        <header className="bilty-detailed-head"><div className="bilty-detailed-branding">{identity}{numberBox}</div><div className="bilty-detailed-title">{title}<div className="bilty-detailed-route"><b>{labels("from")} / {labels("to")}</b><strong dir="auto">{displayedFieldValue(presentation.routeFrom, language)} <span aria-hidden="true">→</span> {displayedFieldValue(presentation.routeTo, language)}</strong></div></div></header>
        <section className="bilty-detailed-panels">
          <div className="bilty-detailed-panel"><h3>{isUrdu ? "دستاویز اور سفر" : "DOCUMENT & JOURNEY"}</h3>{infoFields(detailedDocument, "bilty-detailed-field-list")}</div>
          <div className="bilty-detailed-panel"><h3>{isUrdu ? "فریقین اور گاڑی" : "PARTIES & VEHICLE"}</h3>{infoFields(detailedParties, "bilty-detailed-field-list")}</div>
        </section>
        {contacts}{containerDetails}
        <section className="bilty-goods-section bilty-detailed-goods"><h3>{labels("items")}</h3>{goodsTable}</section>
        {financialSection}{note}{signatures}{footer}
      </> : null}
    </article>
  </>;
}

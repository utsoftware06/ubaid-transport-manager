"use client";

import { useEffect, useMemo, useState } from "react";
import { Printer, RefreshCw } from "lucide-react";
import { isUserRole, type UserRole } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import { resolvePrintTenantContext } from "@/lib/print/foundation";
import { PRINT_DOCUMENT_REGISTRY, PRINT_TEMPLATES, getPrintTemplateStatusForDocument } from "@/lib/print/registry";
import { createDefaultPrintSettings, getPrintSettingsContextKey, validatePrintSettingsValues } from "@/lib/print/settings";
import { loadAddaPrintSettings, saveAddaPrintSetting } from "@/lib/print/persistence";
import { resolvePrintBranding, type AddaBrandRow, type PrintBrandingResult } from "@/lib/print/resolvePrintBranding";
import type { PrintBranding, PrintDocumentSettingsRow, PrintDocumentType, PrintPreviewOverrides, PrintTenantProfile } from "@/lib/print/types";
import { supabase } from "@/lib/supabase/client";
import PrintFoundationSample from "./PrintFoundationSample";
import { BiltyTemplateDocument } from "@/components/bilty/BiltyTemplatePrint";
import { createSyntheticBiltyPresentation } from "@/lib/print/biltyPresentation";
import { VoucherTemplateDocument } from "@/components/expenses/VoucherTemplateDocument";
import { createSyntheticVoucherPresentation, createVoucherTemplateDefaults, type VoucherPrintKind } from "@/lib/print/voucherPresentation";
import PrintTemplateControls from "./PrintTemplateControls";
import { printCopy } from "./printCopy";
import ModuleTransportPrintDocument from "./ModuleTransportPrintDocument";
import { createSyntheticModulePresentation } from "@/lib/print/modulePresentation";
import { LedgerStatementPrintDocument, createSyntheticLedgerPresentation, isLedgerDocumentType } from "./LedgerStatementPrint";

type ProfileRow = { role: string | null; adda_id: string | null; is_active: boolean | null };
type PageState = "loading" | "ready" | "error" | "missing_adda" | "no_addas";
type SettingsState =
  | { addaId: string; status: "loading" }
  | { addaId: string; status: "ready"; rows: PrintDocumentSettingsRow[] }
  | { addaId: string; status: "error"; message: string };
type PreviewDraft = { key: string; values: PrintPreviewOverrides };

const emptyBranding = (addaId: string): PrintBranding => ({
  addaId, addaName: "", tagline: null, logoUrl: null, address: null, city: null, phone: null,
  alternatePhone: null, existingPaperSize: null, showLogoByDefault: true, footerText: null,
});

export default function PrintTemplatesPage() {
  const { language: appLanguage, dir } = useLanguage();
  const [profile, setProfile] = useState<PrintTenantProfile | null>(null);
  const [profileState, setProfileState] = useState<PageState>("loading");
  const [addas, setAddas] = useState<AddaBrandRow[]>([]);
  const [selectedAddaId, setSelectedAddaId] = useState<string | null>(null);
  const [brandingResult, setBrandingResult] = useState<PrintBrandingResult | null>(null);
  const [settingsState, setSettingsState] = useState<SettingsState | null>(null);
  const [documentType, setDocumentType] = useState<PrintDocumentType>("bilty");
  const [voucherSampleKind, setVoucherSampleKind] = useState<VoucherPrintKind>("standard");
  const [previewDraft, setPreviewDraft] = useState<PreviewDraft | null>(null);
  const [saving, setSaving] = useState(false);
  const [previewLogoFailedKey, setPreviewLogoFailedKey] = useState<string | null>(null);
  const [saveFeedback, setSaveFeedback] = useState<{ key: string; error?: string; saved?: boolean } | null>(null);

  const copy = (key: string) => printCopy(appLanguage, key);
  const tenantContext = useMemo(() => resolvePrintTenantContext(profile, selectedAddaId), [profile, selectedAddaId]);
  const selectedAdda = useMemo(
    () => tenantContext.status === "ready" ? addas.find((adda) => adda.id === tenantContext.addaId) ?? null : null,
    [addas, tenantContext]
  );

  useEffect(() => {
    let active = true;
    async function loadProfile() {
      setProfileState("loading");
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (!active) return;
      if (authError || !authData.user) { setProfileState("error"); return; }
      const { data, error } = await supabase.from("profiles")
        .select("role, adda_id, is_active").eq("id", authData.user.id).maybeSingle();
      if (!active) return;
      if (error || !data) {
        console.error("Unable to load print-template profile context:", error);
        setProfileState("error");
        return;
      }
      const row = data as ProfileRow;
      if (row.is_active !== true || !isUserRole(row.role)) { setProfileState("error"); return; }
      const nextProfile: PrintTenantProfile = { role: row.role as UserRole, addaId: row.adda_id };
      setProfile(nextProfile);
      if (nextProfile.role !== "super_admin") {
        setSelectedAddaId(nextProfile.addaId);
        setProfileState(nextProfile.addaId ? "ready" : "missing_adda");
        return;
      }
      const { data: addaRows, error: addaError } = await supabase.from("addas")
        .select("id, name, address, city, phone").order("name", { ascending: true });
      if (!active) return;
      if (addaError) {
        console.error("Unable to load Addas for print-template context:", addaError);
        setProfileState("error");
        return;
      }
      const availableAddas = (addaRows ?? []) as AddaBrandRow[];
      setAddas(availableAddas);
      setProfileState(availableAddas.length ? "ready" : "no_addas");
    }
    void loadProfile();
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (tenantContext.status !== "ready") return;
    let active = true;
    void resolvePrintBranding(tenantContext.addaId, selectedAdda)
      .then((result) => { if (active) setBrandingResult(result); })
      .catch((error: unknown) => {
        console.error("Unable to resolve authorized print branding:", error);
        if (active) setBrandingResult({
          branding: emptyBranding(tenantContext.addaId), settingsAvailable: false,
          settingsError: error instanceof Error ? error.message : "Branding could not be loaded.",
        });
      });
    return () => { active = false; };
  }, [tenantContext, selectedAdda]);

  useEffect(() => {
    if (tenantContext.status !== "ready") return;
    const requestedAddaId = tenantContext.addaId;
    let active = true;
    void loadAddaPrintSettings(requestedAddaId)
      .then((rows) => { if (active) setSettingsState({ addaId: requestedAddaId, status: "ready", rows }); })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : "Unknown print-settings read error.";
        console.error("Unable to read Adda print defaults:", error);
        if (active) setSettingsState({ addaId: requestedAddaId, status: "error", message });
      });
    return () => { active = false; };
  }, [tenantContext]);

  const addaId = tenantContext.status === "ready" ? tenantContext.addaId : null;
  const branding = addaId && brandingResult?.branding.addaId === addaId ? brandingResult.branding : null;
  const currentSettingsState = addaId && settingsState?.addaId === addaId ? settingsState : null;
  const savedRows = currentSettingsState?.status === "ready" ? currentSettingsState.rows : [];
  const savedDocumentSettings = savedRows.find((row) => row.documentType === documentType) ?? null;
  const fallbackSettings = useMemo(() => branding
    ? documentType === "voucher"
      ? createVoucherTemplateDefaults(createDefaultPrintSettings(branding))
      : createDefaultPrintSettings(branding)
    : null, [branding, documentType]);
  const settingsBase = savedDocumentSettings ?? fallbackSettings;
  const draftKey = addaId ? getPrintSettingsContextKey(addaId, documentType) : "";
  const baseOverrides: PrintPreviewOverrides | null = settingsBase ? {
    ...settingsBase, language: appLanguage, showFooter: Boolean(branding?.footerText),
  } : null;
  const currentOverrides = baseOverrides
    ? (previewDraft?.key === draftKey ? previewDraft.values : baseOverrides)
    : null;
  const previewLogoKey = `${draftKey}:${currentOverrides?.templateId ?? "none"}`;
  const templateStatus = currentOverrides ? getPrintTemplateStatusForDocument(documentType, currentOverrides.templateId) : "planned";
  const templateAvailable = templateStatus !== "planned";
  const canManageDefaults = tenantContext.status === "ready" && tenantContext.canManageDefaults;
  const settingsReadFailed = currentSettingsState?.status === "error";
  const settingsLoading = currentSettingsState?.status === "loading" || (tenantContext.status === "ready" && !currentSettingsState);
  const validationErrors = currentOverrides ? validatePrintSettingsValues(currentOverrides) : ["settings_unavailable"];

  function handlePreviewChange(next: PrintPreviewOverrides) {
    if (!draftKey) return;
    setSaveFeedback(null);
    setPreviewDraft({ key: draftKey, values: next });
  }

  function resetOverrides() {
    if (!draftKey || !baseOverrides) return;
    setSaveFeedback(null);
    setPreviewDraft({ key: draftKey, values: baseOverrides });
  }

  async function handleSaveDefaults() {
    if (!addaId || !canManageDefaults || !currentOverrides || settingsReadFailed || settingsLoading
      || getPrintTemplateStatusForDocument(documentType, currentOverrides.templateId) === "planned") return;
    const saveKey = draftKey;
    const saveDocumentType = documentType;
    const errors = validatePrintSettingsValues(currentOverrides);
    if (errors.length) { setSaveFeedback({ key: saveKey, error: errors.join(", ") }); return; }
    setSaving(true); setSaveFeedback(null);
    try {
      const row = await saveAddaPrintSetting(addaId, saveDocumentType, currentOverrides);
      if (row.addaId !== addaId || row.documentType !== saveDocumentType) throw new Error("Save returned a different Adda or document.");
      setSettingsState((previous) => {
        if (!previous || previous.addaId !== addaId || previous.status !== "ready") return previous;
        return { ...previous, rows: [...previous.rows.filter((item) => item.documentType !== saveDocumentType), row] };
      });
      setPreviewDraft((current) => current?.key === saveKey ? null : current);
      setSaveFeedback({ key: saveKey, saved: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown print-settings save error.";
      console.error("Unable to save Adda print defaults:", error);
      setSaveFeedback({ key: saveKey, error: message });
    } finally { setSaving(false); }
  }

  async function printSample() {
    if (!templateAvailable) return;
    const previewId = documentType === "bilty" ? "bilty-template-print" : documentType === "voucher" ? "voucher-template-print" : ["oil", "diesel", "petrol_pump", "tyre", "workshop"].includes(documentType) ? "module-transport-print" : isLedgerDocumentType(documentType) ? "ledger-statement-print" : "print-template-foundation-preview";
    const logo = document.getElementById(previewId)?.querySelector("img");
    if (logo && !logo.complete) {
      await Promise.race([
        new Promise<void>((resolve) => {
          logo.addEventListener("load", () => resolve(), { once: true });
          logo.addEventListener("error", () => resolve(), { once: true });
        }),
        new Promise<void>((resolve) => window.setTimeout(resolve, 1200)),
      ]);
    }
    window.print();
  }

  const isSuperAdmin = profile?.role === "super_admin";
  const contextMessage = profile?.role === "super_admin" ? copy("superAdminScope")
    : profile?.role === "adda_admin" ? copy("adminScope") : copy("operatorScope");

  return (
    <div dir={dir} className="ut-module-page min-w-0 p-0">
      <div className="mx-auto max-w-7xl space-y-6">
        <header className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm print-foundation-no-print">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-slate-100 text-slate-900"><Printer aria-hidden="true" /></div>
            <div><h1 className="text-3xl font-black text-slate-950">{copy("title")}</h1><p className="mt-2 font-semibold text-slate-700">{copy("subtitle")}</p></div>
          </div>
        </header>

        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm print-foundation-no-print">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div className="min-w-0 flex-1">
              <label htmlFor="print-template-adda" className="mb-1 block text-sm font-extrabold text-slate-800">{copy("context")}</label>
              {isSuperAdmin ? (
                <select id="print-template-adda" value={selectedAddaId ?? ""} onChange={(event) => {
                  setSelectedAddaId(event.target.value || null); setPreviewDraft(null); setSaveFeedback(null);
                }} className="w-full max-w-xl rounded-lg border border-slate-300 bg-white p-3 font-bold text-slate-950">
                  <option value="">{copy("selectAdda")}</option>
                  {addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}{adda.city ? " · " + adda.city : ""}</option>)}
                </select>
              ) : (
                <p className="max-w-xl rounded-lg border border-slate-200 bg-slate-50 p-3 font-bold text-slate-900">{branding?.addaName || (tenantContext.status === "ready" ? tenantContext.addaId : "—")}</p>
              )}
              <p className="mt-2 text-xs font-semibold text-slate-600">{contextMessage}</p>
            </div>
            <button type="button" onClick={resetOverrides} disabled={!baseOverrides}
              className="inline-flex items-center justify-center gap-2 rounded-lg border border-slate-300 px-4 py-2.5 text-sm font-extrabold text-slate-800 disabled:opacity-50 print-foundation-no-print">
              <RefreshCw size={16} aria-hidden="true" />{copy("reset")}
            </button>
          </div>
        </section>

        {profileState === "loading" || (tenantContext.status === "ready" && !branding) ? (
          <div className="rounded-xl border border-slate-200 bg-white p-6 text-center font-bold text-slate-700 print-foundation-no-print">{copy("loading")}</div>
        ) : profileState === "error" ? (
          <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-5 font-bold text-red-800 print-foundation-no-print">{copy("loadError")}</div>
        ) : profileState === "missing_adda" ? (
          <div role="alert" className="rounded-xl border border-amber-200 bg-amber-50 p-5 font-bold text-amber-900 print-foundation-no-print">{copy("noAdda")}</div>
        ) : profileState === "no_addas" ? (
          <div role="alert" className="rounded-xl border border-amber-200 bg-amber-50 p-5 font-bold text-amber-900 print-foundation-no-print">{copy("noAddas")}</div>
        ) : tenantContext.status === "select_adda" ? (
          <div role="status" className="rounded-xl border border-blue-200 bg-blue-50 p-5 font-bold text-blue-900 print-foundation-no-print">{copy("contextRequired")}</div>
        ) : null}

        {tenantContext.status === "ready" && branding && currentOverrides ? (
          <>
            <div className="grid gap-5 xl:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] print-foundation-no-print">
              <div>
                <label htmlFor="print-document-type" className="mb-1 block text-sm font-extrabold text-slate-800">{copy("documentType")}</label>
                <select id="print-document-type" value={documentType} onChange={(event) => {
                  setDocumentType(event.target.value as PrintDocumentType); setPreviewDraft(null); setSaveFeedback(null);
                }} className="mb-4 w-full rounded-lg border border-slate-300 bg-white p-3 font-bold text-slate-950">
                  {PRINT_DOCUMENT_REGISTRY.map((item) => <option key={item.documentType} value={item.documentType}>{item.label}</option>)}
                </select>
                {documentType === "voucher" ? <label className="mb-4 grid gap-1 text-sm font-extrabold text-slate-800">{appLanguage === "ur" ? "واؤچر کی مثال" : "Voucher sample"}<select value={voucherSampleKind} onChange={(event) => setVoucherSampleKind(event.target.value as VoucherPrintKind)} className="w-full rounded-lg border border-slate-300 bg-white p-3 font-bold text-slate-950"><option value="standard">{copy("voucherStandardSample")}</option><option value="manual">{copy("voucherManualSample")}</option></select></label> : null}
                <PrintTemplateControls
                  documentType={documentType}
                  language={currentOverrides.language} overrides={currentOverrides}
                  footerAvailable={Boolean(branding.footerText)} canManageDefaults={canManageDefaults}
                  saveDisabled={settingsReadFailed || settingsLoading || validationErrors.length > 0 || templateStatus === "planned"}
                  saving={saving} savedMessage={saveFeedback?.key === draftKey && saveFeedback.saved ? copy("saved") : null}
                  errorMessage={saveFeedback?.key === draftKey && saveFeedback.error ? copy("settingsSaveError") + " " + saveFeedback.error : null}
                  validationMessage={validationErrors.length ? copy("invalidPrintSettings") : null}
                  onChange={handlePreviewChange} onReset={resetOverrides}
                  onSave={() => void handleSaveDefaults()} onPrint={() => void printSample()}
                />
              </div>
              <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
                <h2 className="text-lg font-black text-slate-950">{copy("templateAvailability")}</h2>
                <div className="mt-3 grid gap-3 sm:grid-cols-2">
                  {PRINT_TEMPLATES.map((template) => (
                    <article key={template.id} className="rounded-xl border border-slate-200 p-3">
                      <h3 className="font-extrabold text-slate-900">{template.label}</h3>
                      <p className="mt-1 text-xs font-bold text-slate-600">{getPrintTemplateStatusForDocument(documentType, template.id) === "ready" ? copy("biltyReady") : getPrintTemplateStatusForDocument(documentType, template.id) === "foundation_preview_only" ? copy("foundationOnly") : copy("notImplemented")}</p>
                    </article>
                  ))}
                </div>
              </section>
            </div>

            <section className="rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm font-semibold leading-6 text-blue-950 print-foundation-no-print">
              {settingsLoading ? <p role="status">{copy("settingsLoading")}</p> : null}
              {settingsReadFailed ? <p role="alert">{copy("settingsReadError")} {currentSettingsState?.status === "error" ? currentSettingsState.message : ""}</p> : null}
              {currentSettingsState?.status === "ready" && !savedDocumentSettings ? <p>{copy("noDocumentDefault")}</p> : null}
              {brandingResult?.settingsError ? <p className="mt-1">{copy("settingsUnavailable")} {brandingResult.settingsError}</p> : null}
              {!settingsReadFailed && !settingsLoading ? <p className="mt-1">{copy("fallbackSettings")}</p> : null}
              {!templateAvailable ? <p role="status" className="mt-2 font-extrabold">{copy("templateUnavailable")}</p> : null}
            </section>

            <section className="space-y-3 print-foundation-no-print">
              <h2 className="text-xl font-black text-slate-950">{copy("legacyTitle")}</h2>
              <p className="max-w-4xl text-sm font-semibold leading-6 text-slate-700">{copy("legacyBody")}</p>
              <ul className="grid gap-2 rounded-xl border border-slate-200 bg-white p-4 sm:grid-cols-2">
                <li className="flex items-center justify-between gap-3 rounded-lg border border-slate-100 px-3 py-2 text-sm">
                  <strong className="text-slate-900">{copy("bookingSlipLabel")}</strong>
                  <span className="shrink-0 text-xs font-bold text-slate-600">{copy("legacyAvailable")}</span>
                </li>
                {PRINT_DOCUMENT_REGISTRY.map((item) => (
                  <li key={item.documentType} className="rounded-lg border border-slate-100 px-3 py-2 text-sm">
                    <div className="flex items-center justify-between gap-3"><strong className="text-slate-900">{item.label}</strong><span className="shrink-0 text-xs font-bold text-slate-600">{item.newTemplateStatus === "implemented_individual" ? copy("biltyReady") : item.newTemplateStatus === "implemented_flows" ? copy("partialReady") : item.legacyPrintAvailable ? copy("legacyAvailable") : copy("notImplemented")}</span></div>
                    {item.coverageNote ? <p className="mt-1 text-xs font-medium text-slate-600">{appLanguage === "ur" ? item.coverageNote.ur : item.coverageNote.en}</p> : null}
                  </li>
                ))}
              </ul>
            </section>

            <div className="print-foundation-screen-preview rounded-2xl border border-dashed border-slate-300 bg-slate-100 p-4 sm:p-8">
              <div className="print-foundation-no-print mb-3 flex items-center justify-between gap-2 text-xs font-bold uppercase tracking-wide text-slate-500">
                <span>{templateStatus === "ready" ? copy("biltyReady") : templateStatus === "foundation_preview_only" ? copy("foundationOnly") : copy("notImplemented")}</span>
                <span>{currentOverrides.paperSize} · {currentOverrides.orientation}</span>
              </div>
              {templateAvailable
                ? documentType === "bilty" && templateStatus === "ready"
                  ? <BiltyTemplateDocument key={`${tenantContext.addaId}:${documentType}:${currentOverrides.templateId}`} presentation={createSyntheticBiltyPresentation()} branding={branding} overrides={currentOverrides} logoFailed={previewLogoFailedKey === previewLogoKey} onLogoError={() => setPreviewLogoFailedKey(previewLogoKey)} />
                  : documentType === "voucher" && templateStatus === "ready"
                    ? <VoucherTemplateDocument key={`${tenantContext.addaId}:${documentType}:${voucherSampleKind}:${currentOverrides.templateId}`} presentation={createSyntheticVoucherPresentation(tenantContext.addaId, voucherSampleKind)} branding={branding} overrides={currentOverrides} logoFailed={previewLogoFailedKey === previewLogoKey} onLogoError={() => setPreviewLogoFailedKey(previewLogoKey)} />
                    : ["oil", "diesel", "petrol_pump", "tyre", "workshop"].includes(documentType)
                      ? <ModuleTransportPrintDocument key={`${tenantContext.addaId}:${documentType}:${currentOverrides.templateId}`} presentation={createSyntheticModulePresentation(documentType as "oil" | "diesel" | "petrol_pump" | "tyre" | "workshop")} branding={branding} overrides={currentOverrides} logoFailed={previewLogoFailedKey === previewLogoKey} onLogoError={() => setPreviewLogoFailedKey(previewLogoKey)} />
                      : isLedgerDocumentType(documentType)
                        ? <LedgerStatementPrintDocument key={`${tenantContext.addaId}:${documentType}:${currentOverrides.templateId}:${currentOverrides.language}`} presentation={createSyntheticLedgerPresentation(documentType, currentOverrides.language)} branding={branding} overrides={currentOverrides} logoFailed={previewLogoFailedKey === previewLogoKey} onLogoError={() => setPreviewLogoFailedKey(previewLogoKey)} />
                      : <PrintFoundationSample key={tenantContext.addaId + ":" + documentType} branding={branding} overrides={currentOverrides} />
                : <div className="rounded-xl border border-amber-300 bg-amber-50 p-6 font-bold text-amber-950 print-foundation-no-print">{copy("templateUnavailable")}</div>}
            </div>
          </>
        ) : null}
      </div>
    </div>
  );
}

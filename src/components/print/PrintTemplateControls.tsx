"use client";

import { getPrintTemplateStatusForDocument, PRINT_TEMPLATES } from "@/lib/print/registry";
import type { PrintDocumentType } from "@/lib/print/types";
import { updatePrintPreviewOverrides } from "@/lib/print/foundation";
import { createVoucherTemplateDefaults } from "@/lib/print/voucherPresentation";
import type { PrintLanguage, PrintOrientation, PrintPaperSize, PrintPreviewOverrides, PrintTemplateId } from "@/lib/print/types";
import { printCopy } from "./printCopy";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type PrintTemplateControlsProps = {
  documentType: PrintDocumentType;
  language: PrintLanguage;
  overrides: PrintPreviewOverrides;
  footerAvailable: boolean;
  canManageDefaults: boolean;
  saveDisabled: boolean;
  saving: boolean;
  savedMessage: string | null;
  errorMessage: string | null;
  validationMessage: string | null;
  onChange: (value: PrintPreviewOverrides) => void;
  onReset: () => void;
  onSave: () => void;
  onPrint: () => void;
};

export default function PrintTemplateControls({
  documentType, language, overrides, footerAvailable, canManageDefaults, saveDisabled, saving, savedMessage, errorMessage, validationMessage,
  onChange, onReset, onSave, onPrint,
}: PrintTemplateControlsProps) {
  const copy = (key: string) => printCopy(language, key);
  const update = <K extends keyof PrintPreviewOverrides,>(key: K, value: PrintPreviewOverrides[K]) => {
    const next = updatePrintPreviewOverrides(overrides, key, value);
    onChange(documentType === "voucher" && key === "templateId"
      ? createVoucherTemplateDefaults(next, value as PrintTemplateId)
      : next);
  };

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm print-foundation-no-print">
      <h2 className="text-lg font-black text-slate-950">{copy("previewSettings")}</h2>
      <div className="mt-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <label className="grid gap-1 text-sm font-bold text-slate-800">
          {copy("template")}
          <select className="rounded-lg border border-slate-300 bg-white p-2.5" value={overrides.templateId}
            onChange={(event) => update("templateId", event.target.value as PrintTemplateId)}>
            {PRINT_TEMPLATES.map((template) => (
              <option key={template.id} value={template.id} disabled={getPrintTemplateStatusForDocument(documentType, template.id) === "planned"}>
                {template.label}{getPrintTemplateStatusForDocument(documentType, template.id) === "planned" ? " — " + copy("notImplemented") : getPrintTemplateStatusForDocument(documentType, template.id) === "foundation_preview_only" ? " — " + copy("foundationOnly") : " — " + copy("biltyReady")}
              </option>
            ))}
          </select>
        </label>
        <label className="grid gap-1 text-sm font-bold text-slate-800">
          {copy("paper")}
          <select className="rounded-lg border border-slate-300 bg-white p-2.5" value={overrides.paperSize}
            onChange={(event) => update("paperSize", event.target.value as PrintPaperSize)}>
            <option value="A4">{copy("a4")}</option><option value="A5">{copy("a5")}</option>
          </select>
        </label>
        <label className="grid gap-1 text-sm font-bold text-slate-800">
          {copy("orientation")}
          <select className="rounded-lg border border-slate-300 bg-white p-2.5" value={overrides.orientation}
            onChange={(event) => update("orientation", event.target.value as PrintOrientation)}>
          <option value="portrait">{copy("portrait")}</option><option value="landscape">{copy("landscape")}</option>
          </select>
        </label>
        <label className="grid gap-1 text-sm font-bold text-slate-800">
          {copy("language")}
          <select className="rounded-lg border border-slate-300 bg-white p-2.5" value={overrides.language}
            onChange={(event) => update("language", event.target.value as PrintLanguage)}>
            <option value="en">{copy("languageEnglish")}</option><option value="ur">{copy("languageUrdu")}</option>
          </select>
        </label>
      </div>

      <fieldset className="mt-4">
        <legend className="text-sm font-extrabold text-slate-800">{copy("margins")}</legend>
        <div className="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {([
            ["marginTopMm", "marginTop"], ["marginRightMm", "marginRight"],
            ["marginBottomMm", "marginBottom"], ["marginLeftMm", "marginLeft"],
          ] as const).map(([field, label]) => (

             <VoiceTypingField key={field} fieldLabel={copy(label)} mode="number"><label className="grid gap-1 text-xs font-bold text-slate-700">
              {copy(label)}
              <input type="number" min="0" max="30" step="0.1" className="rounded-lg border border-slate-300 p-2"
                value={overrides[field]} onChange={(event) => update(field, Number(event.target.value))} />
            </label></VoiceTypingField>

          ))}
        </div>
      </fieldset>

      <div className="mt-4 flex flex-wrap gap-x-6 gap-y-3 text-sm font-bold text-slate-800">
        {([
          ["showLogo", "showLogo"], ["showAddress", "showAddress"], ["showPhone", "showPhone"],
          ["showSignatures", "showSignatures"], ["showStamp", "showStamp"], ["showFooter", "showFooter"],
        ] as const).map(([field, label]) => (
          <label key={field} className="inline-flex items-center gap-2">
            <input type="checkbox" checked={overrides[field]} disabled={field === "showFooter" && !footerAvailable}
              onChange={(event) => update(field, event.target.checked)} />
            {copy(label)}
          </label>
        ))}
      </div>

      <div className="mt-5 flex flex-wrap gap-3">
        <button type="button" onClick={onReset} className="rounded-lg border border-slate-300 px-4 py-2.5 text-sm font-extrabold text-slate-800 hover:bg-slate-50">{copy("reset")}</button>
        <button type="button" onClick={onPrint} disabled={saveDisabled || getPrintTemplateStatusForDocument(documentType, overrides.templateId) === "planned"}
          className="rounded-lg bg-slate-950 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50">{copy("print")}</button>
        {canManageDefaults ? (
          <button type="button" onClick={onSave} disabled={saveDisabled || saving || getPrintTemplateStatusForDocument(documentType, overrides.templateId) === "planned"}
            className="rounded-lg border border-blue-700 px-4 py-2.5 text-sm font-extrabold text-blue-800 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50">
            {saving ? copy("saving") : copy("saveDefaults")}
          </button>
        ) : null}
      </div>
      {savedMessage ? <p role="status" className="mt-3 text-sm font-bold text-green-800">{savedMessage}</p> : null}
      {errorMessage ? <p role="alert" className="mt-3 text-sm font-bold text-red-800">{errorMessage}</p> : null}
      {validationMessage ? <p role="alert" className="mt-3 text-sm font-bold text-red-800">{validationMessage}</p> : null}
      <p className="mt-3 text-xs font-semibold leading-5 text-slate-600">{canManageDefaults ? copy("explicitSave") : copy("operatorScope")}</p>
    </section>
  );
}

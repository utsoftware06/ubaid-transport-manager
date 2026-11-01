/* eslint-disable @next/next/no-img-element -- Adda logo URLs are sanitized and print may run before next/image settles. */
import { useMemo, useState } from "react";
import { getPrintDirection, getPrintPageRule, getSafeLogoUrl } from "@/lib/print/foundation";
import { missingPrintAddaName } from "@/lib/print/resolvePrintBranding";
import { cellText, type ModulePrintPresentation } from "@/lib/print/modulePresentation";
import type { PrintBranding, PrintPreviewOverrides, PrintTemplateId } from "@/lib/print/types";

type Props = { presentation: ModulePrintPresentation; branding: PrintBranding; overrides: PrintPreviewOverrides; logoFailed?: boolean; onLogoError?: () => void };

const art: Partial<Record<ModulePrintPresentation["documentType"], string>> = {
  oil: "M12 2C9 7 5 11 5 15a7 7 0 0 0 14 0c0-4-4-8-7-13Zm0 16a3 3 0 0 1-3-3",
  diesel: "M5 3h10v18H5z M8 6h4v5H8z M15 7h2l3 3v8a2 2 0 0 1-4 0v-4",
  petrol_pump: "M4 21V4h11v17 M7 7h5v5H7z M15 9h2l3 3v6a2 2 0 0 1-4 0v-3",
  tyre: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 5a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z",
  workshop: "M14 6a5 5 0 0 0-6 6l-5 5 4 4 5-5a5 5 0 0 0 6-6l-3 3-4-4 3-3Z",
};

export function templatePageDefaults(templateId: PrintTemplateId) {
  if (templateId === "modern_professional") return { paperSize: "A4" as const, orientation: "landscape" as const };
  if (templateId === "compact_pad") return { paperSize: "A5" as const, orientation: "portrait" as const };
  return { paperSize: "A4" as const, orientation: "portrait" as const };
}

export default function ModuleTransportPrintDocument({ presentation, branding, overrides, logoFailed = false, onLogoError }: Props) {
  const [imageFailed, setImageFailed] = useState(false);
  const language = overrides.language;
  const direction = getPrintDirection(language);
  const logoUrl = overrides.showLogo ? getSafeLogoUrl(branding.logoUrl) : null;
  const showLogo = Boolean(logoUrl) && !logoFailed && !imageFailed;
  const title = cellText(presentation.title, language);
  const fields = useMemo(() => presentation.fields.filter((field) => field.value != null && field.value !== ""), [presentation.fields]);
  const signatureLabels = language === "ur" ? ["تیار کنندہ", "وصول کنندہ کے دستخط"] : ["Prepared by", "Receiver signature"];
  const stamp = language === "ur" ? "مہر" : "Stamp";
  const amountLabels = language === "ur" ? "خلاصہ" : "Totals";

  return <article id="module-transport-print" className={`module-print-sheet module-print-${presentation.documentType} module-print-${overrides.templateId}`} lang={language} dir={direction}>
    <style>{`
      @page { size: ${overrides.paperSize} ${overrides.orientation}; margin: ${overrides.marginTopMm}mm ${overrides.marginRightMm}mm ${overrides.marginBottomMm}mm ${overrides.marginLeftMm}mm; }
      .module-print-sheet{--ink:#15191f;--line:#4b5563;box-sizing:border-box;width:100%;background:#fff;color:var(--ink);font:12px/1.45 Arial,"Noto Nastaliq Urdu",sans-serif;padding:0;break-after:page}
      .module-print-sheet *{box-sizing:border-box}.module-print-header{display:grid;grid-template-columns:auto 1fr auto;align-items:center;gap:12px;border-bottom:2px solid var(--ink);padding:8px 0 12px;margin-bottom:12px}.module-print-marks{display:flex;align-items:center;gap:4px}.module-print-brand{min-width:0}.module-print-brand h1{font-size:22px;line-height:1.2;margin:0}.module-print-brand p{margin:2px 0 0}.module-print-logo{width:48px;height:48px;object-fit:contain}.module-print-art{width:48px;height:48px;fill:none;stroke:var(--ink);stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}.module-print-no{border:2px solid var(--ink);padding:7px 10px;text-align:center;min-width:118px}.module-print-no small{display:block;font-weight:700}.module-print-no strong{font-size:18px;direction:ltr;unicode-bidi:isolate}.module-print-subtitle{font-weight:700;color:#374151;margin:2px 0}.module-print-fields{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:0 12px;border:1px solid var(--line);margin:10px 0}.module-print-field{display:grid;grid-template-columns:minmax(90px,auto) 1fr;gap:8px;padding:5px 7px;border-bottom:1px solid #9ca3af}.module-print-field:nth-child(odd){border-inline-end:1px solid #9ca3af}.module-print-field b{font-size:10px}.module-print-field span{unicode-bidi:plaintext}.module-print-section-title{font-size:13px;margin:12px 0 5px}.module-print-table{width:100%;border-collapse:collapse;break-inside:auto}.module-print-table thead{display:table-header-group}.module-print-table tr{break-inside:avoid}.module-print-table th,.module-print-table td{border:1px solid var(--line);padding:5px 6px;text-align:start;vertical-align:top}.module-print-table th{font-size:10px;background:#f3f4f6}.module-print-total-wrap{margin-top:10px;display:flex;justify-content:flex-end;gap:8px;flex-wrap:wrap}.module-print-total{border:1px solid var(--line);min-width:135px;padding:7px 9px}.module-print-total b{display:block;font-size:10px}.module-print-total strong{direction:ltr;unicode-bidi:isolate}.module-print-remarks{border:1px solid var(--line);min-height:42px;padding:7px;margin-top:10px;white-space:pre-wrap;overflow-wrap:anywhere}.module-print-signatures{display:grid;grid-template-columns:1fr 1fr ${overrides.showStamp ? "80px" : "0px"};gap:20px;margin-top:38px;break-inside:avoid}.module-print-signature{border-top:1px solid var(--ink);text-align:center;padding-top:5px;min-height:24px}.module-print-traditional_pad .module-print-header{border-bottom:3px solid var(--ink);padding:9px 0 13px}.module-print-traditional_pad .module-print-fields{border:2px solid var(--ink)}.module-print-traditional_pad .module-print-field{border-bottom:1px solid var(--ink)}.module-print-traditional_pad .module-print-no{border-width:3px;min-width:132px}.module-print-modern_professional{font-size:11px}.module-print-modern_professional .module-print-header{border-bottom:3px solid #234b72}.module-print-modern_professional .module-print-fields{grid-template-columns:repeat(3,minmax(0,1fr));border:0;gap:8px}.module-print-modern_professional .module-print-field{border:1px solid #6b7280}.module-print-compact_pad{font-size:10px}.module-print-compact_pad .module-print-header{gap:7px;padding:3px 0 7px;margin-bottom:7px}.module-print-compact_pad .module-print-brand h1{font-size:17px}.module-print-compact_pad .module-print-art,.module-print-compact_pad .module-print-logo{width:37px;height:37px}.module-print-compact_pad .module-print-no{min-width:92px;padding:4px}.module-print-compact_pad .module-print-no strong{font-size:15px}.module-print-compact_pad .module-print-fields{margin:6px 0}.module-print-compact_pad .module-print-field{padding:3px 5px}.module-print-detailed_a4{font-size:12px}.module-print-detailed_a4 .module-print-fields{grid-template-columns:repeat(3,minmax(0,1fr))}.module-print-detailed_a4 .module-print-header{padding-bottom:16px;margin-bottom:16px}.module-print-detailed_a4 .module-print-table th,.module-print-detailed_a4 .module-print-table td{padding:7px}.module-print-modern_professional .module-print-no{border-color:#234b72}.module-print-modern_professional .module-print-table th{background:#e8eef4}
      @media print{.print-module-preview,.print-module-preview *,#module-transport-print,#module-transport-print *{visibility:visible!important}.print-module-preview{overflow:visible!important;height:auto!important;max-height:none!important;padding:0!important;background:#fff!important}#module-transport-print{position:relative!important;inset:auto!important;width:100%!important;max-width:none!important;margin:0!important;overflow:visible!important}.module-print-sheet{break-after:auto}.module-print-table{width:100%}.module-print-table th{print-color-adjust:exact;-webkit-print-color-adjust:exact}.module-print-remarks{break-inside:avoid}}
    `}</style>
    <header className="module-print-header">
      <div className="module-print-marks"><svg className="module-print-art" viewBox="0 0 24 24" aria-hidden="true"><path d={art[presentation.documentType] ?? "M3 17h2l2-5h9l3 5h2v3H3zM8 12l2-5h5l2 5M5 20a1.5 1.5 0 1 0 3 0m8 0a1.5 1.5 0 1 0 3 0"} /></svg>{showLogo ? <img className="module-print-logo" src={logoUrl!} alt="" onError={() => { setImageFailed(true); onLogoError?.(); }} /> : null}</div>
      <div className="module-print-brand">
        <h1>{branding.addaName.trim() || missingPrintAddaName(language)}</h1>
        {overrides.showAddress && [branding.address, branding.city].filter(Boolean).length ? <p>{[branding.address, branding.city].filter(Boolean).join(" · ")}</p> : null}
        {overrides.showPhone && [branding.phone, branding.alternatePhone].filter(Boolean).length ? <p dir="ltr">{[branding.phone, branding.alternatePhone].filter(Boolean).join(" · ")}</p> : null}
        {presentation.subtitle ? <p className="module-print-subtitle">{cellText(presentation.subtitle, language)}</p> : null}
      </div>
      <div className="module-print-no"><small>{title}</small><strong>{cellText(presentation.documentNo, language)}</strong><div>{cellText(presentation.documentDate, language)}</div></div>
    </header>
    {presentation.synthetic ? <p className="module-print-synthetic">{language === "ur" ? "نمونہ پیش نظارہ — حقیقی ریکارڈ نہیں" : "SYNTHETIC PREVIEW — NOT A REAL RECORD"}</p> : null}
    {fields.length ? <section className="module-print-fields">{fields.map((field, index) => <div className="module-print-field" key={`${index}:${field.label.en}`}><b>{cellText(field.label, language)}</b><span>{cellText(field.value, language)}</span></div>)}</section> : null}
    {(presentation.tables ?? []).map((table, tableIndex) => <section key={`${tableIndex}:${table.title?.en ?? "items"}`}>
      {table.title ? <h2 className="module-print-section-title">{cellText(table.title, language)}</h2> : null}
      <table className="module-print-table"><thead><tr>{table.columns.map((column, index) => <th key={index}>{cellText(column, language)}</th>)}</tr></thead><tbody>
        {table.rows.length ? table.rows.map((row, rowIndex) => <tr key={rowIndex}>{table.columns.map((_, columnIndex) => <td key={columnIndex}>{cellText(row[columnIndex], language)}</td>)}</tr>) : <tr><td colSpan={table.columns.length}>{language === "ur" ? "کوئی درج شدہ ریکارڈ نہیں" : "No recorded rows"}</td></tr>}
      </tbody></table>
    </section>)}
    {presentation.totals?.length ? <section><h2 className="module-print-section-title">{amountLabels}</h2><div className="module-print-total-wrap">{presentation.totals.map((total, index) => <div className="module-print-total" key={index}><b>{cellText(total.label, language)}</b><strong>{cellText(total.value, language)}</strong></div>)}</div></section> : null}
    {presentation.remarks != null && presentation.remarks !== "" ? <div className="module-print-remarks"><b>{language === "ur" ? "ریمارکس" : "Remarks"}: </b>{cellText(presentation.remarks, language)}</div> : null}
    {overrides.showSignatures ? <footer className="module-print-signatures"><div className="module-print-signature">{signatureLabels[0]}</div><div className="module-print-signature">{signatureLabels[1]}</div>{overrides.showStamp ? <div className="module-print-signature">{stamp}</div> : null}</footer> : null}
    {overrides.showFooter && branding.footerText ? <p className="module-print-footer">{branding.footerText}</p> : null}
  </article>;
}

export { getPrintPageRule };

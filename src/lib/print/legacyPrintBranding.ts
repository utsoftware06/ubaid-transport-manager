import { escapeHtml } from "@/lib/print/escapeHtml";
import { getSafeLogoUrl } from "@/lib/print/foundation";
import { missingPrintAddaName, resolvePrintBranding } from "@/lib/print/resolvePrintBranding";
import { withPrintImageReadiness } from "@/lib/print/printAssets";

export const PRINT_ADDA_NAME_TOKEN = "__PRINT_ADDA_NAME__";

/** Writes a legacy popup with the explicitly owning Adda's saved name and print logo. */
export async function writeAddaBrandedPrintDocument(
  target: Window,
  html: string,
  addaId: string | null | undefined,
  language: "en" | "ur",
): Promise<void> {
  let name = missingPrintAddaName(language);
  let logoUrl: string | null = null;
  if (addaId) {
    try {
      const result = await resolvePrintBranding(addaId);
      if (result.branding.addaId === addaId) {
        if (result.branding.addaName.trim()) name = result.branding.addaName.trim();
        if (result.branding.showLogoByDefault) logoUrl = getSafeLogoUrl(result.branding.logoUrl);
      }
    } catch {
      // Keep a neutral label if the authorized tenant branding lookup is unavailable.
    }
  }

  const logo = `<span aria-hidden="true" style="display:inline-flex;vertical-align:middle;align-items:center;justify-content:center;width:48px;height:42px;flex:none;margin-inline-end:8px">${logoUrl ? `<img src="${escapeHtml(logoUrl)}" alt="" style="display:block;max-width:46px;max-height:40px;width:auto;height:auto;object-fit:contain" onerror="this.remove()">` : ""}</span>`;
  const brand = `${logo}<span style="vertical-align:middle">${escapeHtml(name)}</span>`;
  target.document.open();
  target.document.write(withPrintImageReadiness(html.replaceAll(PRINT_ADDA_NAME_TOKEN, brand)));
  target.document.close();
}

import { escapeHtml } from "@/lib/print/escapeHtml";
import { missingPrintAddaName, resolvePrintBranding } from "@/lib/print/resolvePrintBranding";

export const PRINT_ADDA_NAME_TOKEN = "__PRINT_ADDA_NAME__";

/** Writes a legacy popup with the explicitly owning Adda's name only. */
export async function writeAddaBrandedPrintDocument(
  target: Window,
  html: string,
  addaId: string | null | undefined,
  language: "en" | "ur",
): Promise<void> {
  let name = missingPrintAddaName(language);
  if (addaId) {
    try {
      const result = await resolvePrintBranding(addaId);
      if (result.branding.addaId === addaId && result.branding.addaName.trim()) {
        name = result.branding.addaName.trim();
      }
    } catch {
      // Keep a neutral label if the authorized tenant branding lookup is unavailable.
    }
  }

  target.document.open();
  target.document.write(html.replaceAll(PRINT_ADDA_NAME_TOKEN, escapeHtml(name)));
  target.document.close();
}

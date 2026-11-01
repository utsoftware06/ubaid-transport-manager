import { supabase } from "@/lib/supabase/client";
import { projectPrintBranding, type AddaBrandRow, type CompanySettingsBrandRow } from "./brandingProjection";
import type { PrintBranding } from "./types";

export type PrintBrandingResult = {
  branding: PrintBranding;
  settingsAvailable: boolean;
  settingsError: string | null;
};

export function missingPrintAddaName(language: "en" | "ur"): string {
  return language === "ur" ? "اڈے کا نام دستیاب نہیں" : "Adda name unavailable";
}

/** Uses the normal authenticated client so existing RLS remains the authority. */
export async function resolvePrintBranding(
  addaId: string,
  addaFallback?: AddaBrandRow | null
): Promise<PrintBrandingResult> {
  const [settingsResult, addaResult] = await Promise.all([
    supabase
      .from("company_settings")
      .select("adda_id, business_tagline, logo_url, address, city, phone, alternate_phone, paper_size, show_logo_on_print, print_footer_text")
      .eq("adda_id", addaId)
      .maybeSingle(),
    addaFallback?.id === addaId
      ? Promise.resolve({ data: addaFallback, error: null })
      : supabase
          .from("addas")
          .select("id, name, address, city, phone")
          .eq("id", addaId)
          .maybeSingle(),
  ]);

  const settingsRow = settingsResult.data as CompanySettingsBrandRow | null;
  const resolvedAdda = addaResult.data as AddaBrandRow | null;
  const settingsError = settingsResult.error?.message ?? null;

  return {
    branding: projectPrintBranding(addaId, settingsRow, resolvedAdda),
    settingsAvailable: !settingsResult.error,
    settingsError,
  };
}

export type { AddaBrandRow };

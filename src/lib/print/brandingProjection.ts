import type { PrintBranding } from "./types";

export type AddaBrandRow = {
  id: string;
  name: string;
  address: string | null;
  city: string | null;
  phone: string | null;
};

export type CompanySettingsBrandRow = {
  adda_id: string;
  business_tagline: string | null;
  logo_url: string | null;
  address: string | null;
  city: string | null;
  phone: string | null;
  alternate_phone: string | null;
  paper_size: string | null;
  show_logo_on_print: boolean | null;
  print_footer_text: string | null;
};

/** Pure owner-scoped projection: company_settings never replaces addas.name. */
export function projectPrintBranding(
  addaId: string,
  settingsRow: CompanySettingsBrandRow | null,
  addaRow: AddaBrandRow | null,
): PrintBranding {
  const settings = settingsRow?.adda_id === addaId ? settingsRow : null;
  const adda = addaRow?.id === addaId ? addaRow : null;
  return {
    addaId,
    addaName: adda?.name?.trim() || "",
    tagline: settings?.business_tagline ?? null,
    logoUrl: settings?.logo_url ?? null,
    address: settings?.address ?? adda?.address ?? null,
    city: settings?.city ?? adda?.city ?? null,
    phone: settings?.phone ?? adda?.phone ?? null,
    alternatePhone: settings?.alternate_phone ?? null,
    existingPaperSize: settings?.paper_size ?? null,
    showLogoByDefault: settings?.show_logo_on_print ?? true,
    footerText: settings?.print_footer_text ?? null,
  };
}

import { supabase } from "@/lib/supabase/client";
import { getSafeLogoUrl } from "@/lib/print/foundation";
import { ADDA_LOGO_BUCKET, parseAddaLogoReference } from "./addaLogoCore";

export * from "./addaLogoCore";

/** Resolves only this Adda's private object to a short-lived display URL. */
export async function resolveAddaLogoDisplayUrl(
  addaId: string,
  reference: string | null | undefined,
): Promise<string | null> {
  if (!reference) return null;
  const privateLogo = parseAddaLogoReference(reference);
  if (!privateLogo) return getSafeLogoUrl(reference);
  if (privateLogo.addaId !== addaId.toLowerCase()) return null;

  try {
    const { data, error } = await supabase.storage
      .from(ADDA_LOGO_BUCKET)
      .createSignedUrl(privateLogo.path, 60 * 60);
    return error ? null : data.signedUrl;
  } catch {
    return null;
  }
}

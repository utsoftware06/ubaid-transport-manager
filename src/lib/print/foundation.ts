import type {
  PrintDirection,
  PrintOrientation,
  PrintPaperSize,
  PrintTenantProfile,
  PrintPreviewOverrides,
} from "./types";

export type PrintTenantResolution =
  | { status: "ready"; addaId: string; canManageDefaults: boolean }
  | { status: "select_adda" }
  | { status: "missing_own_adda" }
  | { status: "invalid_role" };

/** Non-Super-Admin context is always pinned to profiles.adda_id. */
export function resolvePrintTenantContext(
  profile: PrintTenantProfile | null,
  selectedAddaId: string | null
): PrintTenantResolution {
  if (!profile) return { status: "invalid_role" };

  if (profile.role === "super_admin") {
    return selectedAddaId
      ? { status: "ready", addaId: selectedAddaId, canManageDefaults: true }
      : { status: "select_adda" };
  }

  if (profile.role !== "adda_admin" && profile.role !== "operator") {
    return { status: "invalid_role" };
  }

  if (!profile.addaId) return { status: "missing_own_adda" };

  return {
    status: "ready",
    addaId: profile.addaId,
    canManageDefaults: profile.role === "adda_admin",
  };
}

export function normalizePrintPaperSize(value: string | null | undefined): PrintPaperSize {
  return value === "A5" ? "A5" : "A4";
}

export function getPrintPageSize(
  paperSize: PrintPaperSize,
  orientation: PrintOrientation
): string {
  return `${paperSize} ${orientation}`;
}

export function getPrintPageRule(
  paperSize: PrintPaperSize,
  orientation: PrintOrientation,
  margins: Pick<PrintPreviewOverrides, "marginTopMm" | "marginRightMm" | "marginBottomMm" | "marginLeftMm">
): string {
  const safeMargin = (value: number) =>
    Number.isFinite(value) && value >= 0 && value <= 30 && Math.round(value * 10) === value * 10
      ? value
      : 10;
  return `@page { size: ${getPrintPageSize(paperSize, orientation)}; margin: ${safeMargin(margins.marginTopMm)}mm ${safeMargin(margins.marginRightMm)}mm ${safeMargin(margins.marginBottomMm)}mm ${safeMargin(margins.marginLeftMm)}mm; }`;
}

export function getPrintDirection(language: "en" | "ur"): PrintDirection {
  return language === "ur" ? "rtl" : "ltr";
}

/** Returns a new object so preview edits never mutate the saved/default source. */
export function updatePrintPreviewOverrides<K extends keyof PrintPreviewOverrides>(
  current: PrintPreviewOverrides,
  key: K,
  value: PrintPreviewOverrides[K]
): PrintPreviewOverrides {
  return { ...current, [key]: value };
}

/** Reject active content and non-web schemes; relative URLs remain same-origin. */
export function getSafeLogoUrl(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;
  if (trimmed.startsWith("/")) {
    return trimmed.startsWith("//") || trimmed.startsWith("/\\") ? null : trimmed;
  }

  try {
    const parsed = new URL(trimmed);
    return parsed.protocol === "https:"
      ? parsed.toString()
      : null;
  } catch {
    return null;
  }
}

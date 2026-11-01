import {
  isPrintDocumentType,
  isPrintTemplateId,
  type PrintBranding,
  type PrintDocumentSettingsRow,
  type PrintDocumentSettingsValues,
  type PrintDocumentType,
  type PrintLanguage,
  type PrintOrientation,
  type PrintPaperSize,
  type PrintTemplateId,
} from "./types";
import { normalizePrintPaperSize } from "./foundation";

export const DEFAULT_PRINT_MARGIN_MM = 10;
export const MAX_PRINT_MARGIN_MM = 30;

export function createDefaultPrintSettings(
  branding: PrintBranding
): PrintDocumentSettingsValues {
  return {
    templateId: "traditional_pad",
    paperSize: normalizePrintPaperSize(branding.existingPaperSize),
    orientation: "portrait",
    marginTopMm: DEFAULT_PRINT_MARGIN_MM,
    marginRightMm: DEFAULT_PRINT_MARGIN_MM,
    marginBottomMm: DEFAULT_PRINT_MARGIN_MM,
    marginLeftMm: DEFAULT_PRINT_MARGIN_MM,
    showLogo: branding.showLogoByDefault,
    showAddress: true,
    showPhone: true,
    showSignatures: true,
    showStamp: true,
  };
}

export function validatePrintSettingsValues(
  value: PrintDocumentSettingsValues
): string[] {
  const errors: string[] = [];
  if (!isPrintTemplateId(value.templateId)) errors.push("unsupported_template_id");
  if (value.paperSize !== "A4" && value.paperSize !== "A5") errors.push("unsupported_paper_size");
  if (value.orientation !== "portrait" && value.orientation !== "landscape") errors.push("unsupported_orientation");

  for (const [name, margin] of [
    ["top", value.marginTopMm],
    ["right", value.marginRightMm],
    ["bottom", value.marginBottomMm],
    ["left", value.marginLeftMm],
  ] as const) {
    if (!Number.isFinite(margin) || margin < 0 || margin > MAX_PRINT_MARGIN_MM || Math.round(margin * 10) !== margin * 10) {
      errors.push(`invalid_margin_${name}`);
    }
  }

  for (const flag of [value.showLogo, value.showAddress, value.showPhone, value.showSignatures, value.showStamp]) {
    if (typeof flag !== "boolean") errors.push("invalid_branding_visibility");
  }

  return errors;
}

/** Context key for draft state. A preview override is valid only in this scope. */
export function getPrintSettingsContextKey(addaId: string, documentType: PrintDocumentType): string {
  return `${addaId}:${documentType}`;
}

type DatabasePrintSettingsRow = {
  adda_id: string;
  document_type: string;
  template_id: string;
  paper_size: string;
  orientation: string;
  margin_top_mm: number | string;
  margin_right_mm: number | string;
  margin_bottom_mm: number | string;
  margin_left_mm: number | string;
  show_logo: boolean;
  show_address: boolean;
  show_phone: boolean;
  show_signatures: boolean;
  show_stamp: boolean;
  created_at: string;
  updated_at: string;
  created_by: string | null;
  updated_by: string | null;
};

export function parsePrintSettingsRow(value: unknown): PrintDocumentSettingsRow | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Partial<DatabasePrintSettingsRow>;
  if (
    typeof row.adda_id !== "string" ||
    !isPrintDocumentType(row.document_type) ||
    !isPrintTemplateId(row.template_id) ||
    (row.paper_size !== "A4" && row.paper_size !== "A5") ||
    (row.orientation !== "portrait" && row.orientation !== "landscape")
  ) return null;

  const rawMargins = [row.margin_top_mm, row.margin_right_mm, row.margin_bottom_mm, row.margin_left_mm];
  if (rawMargins.some((margin) =>
    (typeof margin !== "number" && typeof margin !== "string")
    || (typeof margin === "string" && !/^-?\d+(?:\.\d)?$/.test(margin.trim()))
  )) return null;
  if ([row.show_logo, row.show_address, row.show_phone, row.show_signatures, row.show_stamp]
    .some((flag) => typeof flag !== "boolean")) return null;

  const values: PrintDocumentSettingsValues = {
    templateId: row.template_id as PrintTemplateId,
    paperSize: row.paper_size as PrintPaperSize,
    orientation: row.orientation as PrintOrientation,
    marginTopMm: Number(row.margin_top_mm),
    marginRightMm: Number(row.margin_right_mm),
    marginBottomMm: Number(row.margin_bottom_mm),
    marginLeftMm: Number(row.margin_left_mm),
    showLogo: row.show_logo as boolean,
    showAddress: row.show_address as boolean,
    showPhone: row.show_phone as boolean,
    showSignatures: row.show_signatures as boolean,
    showStamp: row.show_stamp as boolean,
  };

  if (validatePrintSettingsValues(values).length > 0) return null;
  if (typeof row.created_at !== "string" || typeof row.updated_at !== "string") return null;

  return {
    addaId: row.adda_id,
    documentType: row.document_type as PrintDocumentType,
    ...values,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    createdBy: typeof row.created_by === "string" ? row.created_by : null,
    updatedBy: typeof row.updated_by === "string" ? row.updated_by : null,
  };
}

export function parsePrintLanguage(value: unknown): PrintLanguage {
  return value === "ur" ? "ur" : "en";
}

export type PrintLanguage = "en" | "ur";
export type PrintDirection = "ltr" | "rtl";
export type PrintPaperSize = "A4" | "A5";
export type PrintOrientation = "portrait" | "landscape";

export const PRINT_TEMPLATE_IDS = [
  "traditional_pad",
  "modern_professional",
  "compact_pad",
  "detailed_a4",
] as const;

export type PrintTemplateId = (typeof PRINT_TEMPLATE_IDS)[number];

export const PRINT_DOCUMENT_TYPES = [
  "bilty",
  "bilty_chakkar",
  "loading",
  "packing_slip",
  "voucher",
  "parchi",
  "cashbook",
  "customer_ledger",
  "party_ledger",
  "broker_ledger",
  "driver_ledger",
  "owner_ledger",
  "vehicle_ledger",
  "vehicle_monthly_hisab",
  "owner_gari_account",
  "adda_account",
  "other_adda_receipt",
  "payment_receipt",
  "diesel",
  "petrol_pump",
  "oil",
  "tyre",
  "workshop",
  "vehicle_document",
  "employee",
  "reports",
  "audit_log",
] as const;

export type PrintDocumentType = (typeof PRINT_DOCUMENT_TYPES)[number];

export function isPrintTemplateId(value: unknown): value is PrintTemplateId {
  return typeof value === "string" && PRINT_TEMPLATE_IDS.some((id) => id === value);
}

export function isPrintDocumentType(value: unknown): value is PrintDocumentType {
  return typeof value === "string" && PRINT_DOCUMENT_TYPES.some((type) => type === value);
}

export type PrintDocumentSettingsValues = {
  templateId: PrintTemplateId;
  paperSize: PrintPaperSize;
  orientation: PrintOrientation;
  marginTopMm: number;
  marginRightMm: number;
  marginBottomMm: number;
  marginLeftMm: number;
  showLogo: boolean;
  showAddress: boolean;
  showPhone: boolean;
  showSignatures: boolean;
  showStamp: boolean;
};

export type PrintDocumentSettingsRow = PrintDocumentSettingsValues & {
  addaId: string;
  documentType: PrintDocumentType;
  createdAt: string;
  updatedAt: string;
  createdBy: string | null;
  updatedBy: string | null;
};

export type PrintField = {
  label: string;
  value: string;
  direction?: PrintDirection;
};

export type PrintTable = {
  columns: string[];
  rows: string[][];
};

/** Presentation-only data. Module adapters must pass already-authorized values and totals. */
export type PrintPresentationData<TDocument extends PrintDocumentType = PrintDocumentType> = {
  documentType: TDocument;
  title: string;
  subtitle?: string;
  reference?: string;
  fields: PrintField[];
  tables?: PrintTable[];
  notes?: string[];
};

export type PrintBranding = {
  addaId: string;
  addaName: string;
  tagline: string | null;
  logoUrl: string | null;
  address: string | null;
  city: string | null;
  phone: string | null;
  alternatePhone: string | null;
  existingPaperSize: string | null;
  showLogoByDefault: boolean;
  footerText: string | null;
};

export type PrintPreviewOverrides = PrintDocumentSettingsValues & {
  language: PrintLanguage;
  showFooter: boolean;
};

export type PrintTenantProfile = {
  role: "super_admin" | "adda_admin" | "operator";
  addaId: string | null;
};

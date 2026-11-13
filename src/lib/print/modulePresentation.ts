import type { PrintDocumentType, PrintLanguage } from "./types";

export type BilingualText = { en: string; ur: string };
export type PrintCell = string | number | BilingualText | null | undefined;
export type ModulePrintPresentation = {
  documentType: PrintDocumentType;
  layoutVariant?: "vehicle_owner_summary";
  title: BilingualText;
  documentNo?: PrintCell;
  documentDate?: PrintCell;
  subtitle?: BilingualText;
  fields: Array<{ label: BilingualText; value: PrintCell }>;
  tables?: Array<{ title?: BilingualText; columns: BilingualText[]; rows: PrintCell[][] }>;
  totals?: Array<{ label: BilingualText; value: PrintCell }>;
  remarks?: PrintCell;
  synthetic?: boolean;
};

export const bilingual = (en: string, ur: string): BilingualText => ({ en, ur });
export const printLabel = (key: string): BilingualText => ({
  en: modulePrintLabel("en", key),
  ur: modulePrintLabel("ur", key),
});
export const printValue = (value: unknown): PrintCell => value == null || value === "" ? null : String(value);
export const cellText = (value: PrintCell, language: PrintLanguage): string => {
  if (value == null || value === "") return "—";
  if (typeof value === "object") return value[language];
  return String(value);
};

export function createSyntheticModulePresentation(
  documentType: ModulePrintPresentation["documentType"],
): ModulePrintPresentation {
  const common = {
    documentDate: "2026-10-27",
    documentNo: "SAMPLE-ONLY",
    fields: [
      { label: bilingual("Vehicle", "گاڑی"), value: bilingual("Synthetic vehicle · ABC-000", "نمونہ گاڑی · ABC-000") },
      { label: bilingual("Reference", "حوالہ"), value: bilingual("Synthetic reference only", "صرف نمونہ حوالہ") },
    ],
    tables: [{
      title: bilingual("Recorded items", "درج شدہ اشیاء"),
      columns: [bilingual("Description", "تفصیل"), bilingual("Quantity", "مقدار"), bilingual("Amount", "رقم")],
      rows: [[bilingual("Labelled synthetic preview", "واضح طور پر نشان زد نمونہ پیش نظارہ"), "—", "—"]],
    }],
    totals: [{ label: bilingual("Recorded total", "درج شدہ کل"), value: "—" }],
    remarks: bilingual("No real transaction data is shown.", "کوئی حقیقی لین دین کا ڈیٹا نہیں دکھایا گیا۔"),
    synthetic: true,
  } satisfies Omit<ModulePrintPresentation, "documentType" | "title" | "subtitle">;
  const titles: Partial<Record<PrintDocumentType, BilingualText>> = {
    oil: bilingual("Oil purchase / issue document", "آئل خرید / اجرا دستاویز"),
    diesel: bilingual("Diesel entry document", "ڈیزل اندراج دستاویز"),
    petrol_pump: bilingual("Petrol pump statement", "پٹرول پمپ اسٹیٹمنٹ"),
    tyre: bilingual("Tyre work / account document", "ٹائر کام / اکاؤنٹ دستاویز"),
    workshop: bilingual("Workshop work document", "ورکشاپ کام دستاویز"),
  };
  return { ...common, documentType, title: titles[documentType] ?? bilingual("Document preview", "دستاویز کا پیش نظارہ"), subtitle: bilingual("Synthetic sample — not a real record", "نمونہ — حقیقی ریکارڈ نہیں") };
}

export function modulePrintLabel(language: PrintLanguage, key: string): string {
  const [module, ...path] = key.split(".");
  let cursor: unknown = (requireTranslations())[language];
  for (const part of [module, ...path]) {
    if (!cursor || typeof cursor !== "object" || !(part in cursor)) return key;
    cursor = (cursor as Record<string, unknown>)[part];
  }
  return typeof cursor === "string" ? cursor : key;
}

function requireTranslations() {
  // Static import stays tree-shakeable and gives print overrides the same dictionaries as the app.
  return translationsCache;
}

import { translations as translationsCache } from "@/i18n/translations";

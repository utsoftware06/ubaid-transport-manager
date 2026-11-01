import { bilingual, modulePrintLabel, type ModulePrintPresentation } from "./modulePresentation";
import type { PrintDocumentType } from "./types";
import { translations } from "@/i18n/translations";

type ModuleDocument = PrintDocumentType;

/** Legacy print payload adapters keep module entry points unchanged while feeding the shared renderer. */
export const adaptOilPrintMarkup = (title: string, markup: string) => adaptLegacyMarkup("oil", title, markup);
export const adaptDieselPrintMarkup = (title: string, markup: string) => adaptLegacyMarkup("diesel", title, markup);
export const adaptPetrolPumpPrintMarkup = (title: string, markup: string) => adaptLegacyMarkup("petrol_pump", title, markup);
export const adaptTyrePrintMarkup = (title: string, markup: string) => adaptLegacyMarkup("tyre", title, markup);
export const adaptWorkshopPrintMarkup = (title: string, markup: string) => adaptLegacyMarkup("workshop", title, markup);

export function adaptModulePrintMarkup(documentType: ModuleDocument, title: string, markup: string): ModulePrintPresentation {
  switch (documentType) {
    case "oil": return adaptOilPrintMarkup(title, markup);
    case "diesel": return adaptDieselPrintMarkup(title, markup);
    case "petrol_pump": return adaptPetrolPumpPrintMarkup(title, markup);
    case "tyre": return adaptTyrePrintMarkup(title, markup);
    case "workshop": return adaptWorkshopPrintMarkup(title, markup);
    default: return adaptLegacyMarkup(documentType, title, markup);
  }
}

function translatedSystemText(value: string): { en: string; ur: string } {
  const normalized = value.replace(/\s+/g, " ").trim().toLocaleLowerCase();
  const english = flattenTranslations(translations.en);
  const urdu = flattenTranslations(translations.ur);
  for (const [key, englishValue] of english) {
    if (englishValue.replace(/\s+/g, " ").trim().toLocaleLowerCase() === normalized) {
      return { en: englishValue, ur: urdu.get(key) ?? value };
    }
  }
  for (const [key, urduValue] of urdu) {
    if (urduValue.replace(/\s+/g, " ").trim().toLocaleLowerCase() === normalized) {
      return { en: english.get(key) ?? value, ur: urduValue };
    }
  }
  return { en: value, ur: value };
}

const translationFlatCache = new WeakMap<object, Map<string, string>>();
function flattenTranslations(source: object): Map<string, string> {
  const cached = translationFlatCache.get(source);
  if (cached) return cached;
  const result = new Map<string, string>();
  const visit = (value: unknown, path: string[]) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return;
    for (const [key, child] of Object.entries(value)) {
      if (typeof child === "string") result.set([...path, key].join("."), child);
      else visit(child, [...path, key]);
    }
  };
  visit(source, []);
  translationFlatCache.set(source, result);
  return result;
}

function likelySystemColumn(header: string): boolean {
  return /\b(status|type|method|category|direction|source|event|payment|trip|unit|side)\b/i.test(header);
}

function adaptLegacyMarkup(documentType: ModuleDocument, title: string, markup: string): ModulePrintPresentation {
  const document = new DOMParser().parseFromString(markup, "text/html");
  const clean = (value: string | null | undefined) => value?.replace(/\s+/g, " ").trim() ?? "";
  const normalize = (value: string) => value.toLocaleLowerCase().replace(/[:：\s]+/g, "").trim();
  const fields: ModulePrintPresentation["fields"] = [];
  document.querySelectorAll(".details > div, .grid > div, .meta > div").forEach((node) => {
    const text = clean(node.textContent);
    if (!text || /ut software/i.test(text)) return;
    const strong = node.querySelector("strong, b");
    if (strong) {
      const label = clean(strong.textContent).replace(/[:：]$/, "");
      const value = clean(node.textContent).slice(clean(strong.textContent).length).replace(/^[:：\s]+/, "");
      if (label && value) fields.push({ label: translatedSystemText(label), value });
    } else fields.push({ label: bilingual("Details", "تفصیل"), value: text });
  });

  // The existing supplier statements put the selected master name in an h2, outside their metadata grid.
  const isOilSupplierStatement = documentType === "oil" && ["en", "ur"].some((language) =>
    normalize(title) === normalize(modulePrintLabel(language as "en" | "ur", "oil.account.ledger")),
  );
  const isTyreShopStatement = documentType === "tyre" && ["en", "ur"].some((language) =>
    normalize(title) === normalize(modulePrintLabel(language as "en" | "ur", "tyre.account.ledger")),
  );
  if (isOilSupplierStatement || isTyreShopStatement) {
    const name = Array.from(document.querySelectorAll("h2")).map((node) => clean(node.textContent))
      .find((text) => text && normalize(text) !== normalize(title));
    if (name) {
      const labelKey = isOilSupplierStatement ? "oil.account.supplier" : "tyre.account.shop";
      fields.push({
        label: bilingual(modulePrintLabel("en", labelKey), modulePrintLabel("ur", labelKey)),
        value: name,
      });
    }
  }

  const tables: NonNullable<ModulePrintPresentation["tables"]> = [];
  document.querySelectorAll("table").forEach((table) => {
    const rows = Array.from(table.querySelectorAll("tr"));
    if (!rows.length) return;
    let headers = Array.from(rows[0].querySelectorAll("th")).map((cell) => clean(cell.textContent));
    let dataRows = rows;
    if (headers.length) dataRows = rows.slice(1);
    else if (rows[0].querySelectorAll("td").length && rows.length > 1) {
      headers = Array.from(rows[0].querySelectorAll("td")).map((cell) => clean(cell.textContent));
      dataRows = rows.slice(1);
    }
    if (!headers.length) return;
    const precedingHeading = table.previousElementSibling;
    const sectionTitle = precedingHeading && /^H[1-6]$/.test(precedingHeading.tagName)
      ? clean(precedingHeading.textContent)
      : undefined;
    tables.push({
      title: sectionTitle ? translatedSystemText(sectionTitle) : undefined,
      columns: headers.map((label) => translatedSystemText(label || "—")),
      rows: dataRows.map((row) => Array.from(row.querySelectorAll("td,th")).map((cell, index) => {
        const text = clean(cell.textContent);
        return headers[index] && likelySystemColumn(headers[index]) ? translatedSystemText(text) : text;
      })),
    });
  });
  const totals = Array.from(document.querySelectorAll(".total")).map((node) => {
    const text = clean(node.textContent);
    const labelNode = node.querySelector("strong, b");
    const label = labelNode ? clean(labelNode.textContent).replace(/[:：]$/, "") : "Total";
    const value = labelNode ? text.slice(clean(labelNode.textContent).length).replace(/^[:：\s]+/, "") : text;
    return { label: translatedSystemText(label || "Total"), value };
  }).filter((item) => item.value);
  const remarks = Array.from(document.querySelectorAll("p:not(.total), .remarks")).map((node) => clean(node.textContent)).filter((text) => text && !/ut software/i.test(text)).join("\n") || undefined;
  const documentNumberKeys: Partial<Record<ModuleDocument, string[]>> = {
    oil: ["oil.fields.billNo"], diesel: ["diesel.fields.slipNo", "diesel.fields.expenseNo"],
    petrol_pump: ["petrolPumpPayments.fields.reference"], tyre: ["tyre.fields.billNo"],
    workshop: ["workshop.table.billNo", "workshop.account.form.referenceNo"],
  };
  const dateKeys = ["common.date", "oil.fields.purchaseDate", "oil.fields.date"];
  const knownValue = (keys: string[]) => fields.find((field) => keys.some((key) => {
    return [modulePrintLabel("en", key), modulePrintLabel("ur", key)].some((label) => label !== key && normalize(label) === normalize(field.label.en));
  }))?.value;
  return {
    documentType, title: bilingual(title || "Document", title || "دستاویز"),
    documentNo: knownValue(documentNumberKeys[documentType] ?? []), documentDate: knownValue(dateKeys),
    fields, tables, totals, remarks,
  };
}

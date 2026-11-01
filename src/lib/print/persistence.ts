import { isPrintDocumentType, type PrintDocumentSettingsRow, type PrintDocumentSettingsValues, type PrintDocumentType } from "./types";
import { parsePrintSettingsRow, validatePrintSettingsValues } from "./settings";
import { supabase } from "@/lib/supabase/client";

export class PrintSettingsPersistenceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PrintSettingsPersistenceError";
  }
}

export async function loadAddaPrintSettings(addaId: string): Promise<PrintDocumentSettingsRow[]> {
  const { data, error } = await supabase.rpc("get_adda_document_print_settings", {
    p_adda_id: addaId,
  });
  if (error) throw new PrintSettingsPersistenceError(error.message);
  if (!Array.isArray(data)) throw new PrintSettingsPersistenceError("Print settings RPC returned an unexpected response.");

  const parsed = data.map(parsePrintSettingsRow);
  if (parsed.some((row) => row === null)) {
    throw new PrintSettingsPersistenceError("Print settings contain an unsupported or invalid value.");
  }
  return parsed as PrintDocumentSettingsRow[];
}

export async function saveAddaPrintSetting(
  addaId: string,
  documentType: PrintDocumentType,
  values: PrintDocumentSettingsValues
): Promise<PrintDocumentSettingsRow> {
  if (!isPrintDocumentType(documentType)) {
    throw new PrintSettingsPersistenceError("Unsupported print document type.");
  }
  const invalidValues = validatePrintSettingsValues(values);
  if (invalidValues.length) {
    throw new PrintSettingsPersistenceError(`Invalid print settings: ${invalidValues.join(", ")}`);
  }
  const { data, error } = await supabase.rpc("save_adda_document_print_setting", {
    p_adda_id: addaId,
    p_document_type: documentType,
    p_template_id: values.templateId,
    p_paper_size: values.paperSize,
    p_orientation: values.orientation,
    p_margin_top_mm: values.marginTopMm,
    p_margin_right_mm: values.marginRightMm,
    p_margin_bottom_mm: values.marginBottomMm,
    p_margin_left_mm: values.marginLeftMm,
    p_show_logo: values.showLogo,
    p_show_address: values.showAddress,
    p_show_phone: values.showPhone,
    p_show_signatures: values.showSignatures,
    p_show_stamp: values.showStamp,
  });
  if (error) throw new PrintSettingsPersistenceError(error.message);

  const row = parsePrintSettingsRow(Array.isArray(data) ? data[0] : data);
  if (!row || row.addaId !== addaId || row.documentType !== documentType) {
    throw new PrintSettingsPersistenceError("Print settings save returned an unexpected response.");
  }
  return row;
}

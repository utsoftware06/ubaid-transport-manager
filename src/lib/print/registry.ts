import type { PrintDocumentType, PrintTemplateId } from "./types";

export type PrintTemplateAvailability = "implemented_individual" | "planned";

export type PrintTemplateDefinition = {
  id: PrintTemplateId;
  label: string;
  availability: PrintTemplateAvailability;
  productionReady: boolean;
  note: string;
};

/** Stable IDs stay document-neutral; per-document availability is defined below. */
export const PRINT_TEMPLATES: readonly PrintTemplateDefinition[] = [
  {
    id: "traditional_pad",
    label: "Traditional Pakistani Transport Pad",
    availability: "implemented_individual",
    productionReady: true,
    note: "Implemented for the document and statement flows listed as available in the coverage inventory.",
  },
  {
    id: "modern_professional",
    label: "Modern Professional",
    availability: "implemented_individual",
    productionReady: true,
    note: "Implemented for the document and statement flows listed as available in the coverage inventory.",
  },
  {
    id: "compact_pad",
    label: "Compact Pad",
    availability: "implemented_individual",
    productionReady: true,
    note: "Implemented for the document and statement flows listed as available in the coverage inventory.",
  },
  {
    id: "detailed_a4",
    label: "Detailed A4",
    availability: "implemented_individual",
    productionReady: true,
    note: "Implemented for the document and statement flows listed as available in the coverage inventory.",
  },
] as const;

export type LegacyPrintCoverage = {
  documentType: PrintDocumentType;
  label: string;
  currentEntryPoints: readonly string[];
  legacyPrintAvailable: boolean;
  newTemplateStatus: "not_migrated" | "implemented_individual" | "implemented_flows";
  coverageNote?: { en: string; ur: string };
};

/** Current print entry points and new-template availability; legacy paths remain available as fallbacks. */
export const PRINT_DOCUMENT_REGISTRY: readonly LegacyPrintCoverage[] = [
  { documentType: "bilty", label: "Individual Bilty and copies", currentEntryPoints: ["src/components/bilty/BiltyPrint.ts", "src/components/bilty/BiltyTemplatePrint.tsx", "src/app/(dashboard)/bookings/page.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_individual" },
  { documentType: "bilty_chakkar", label: "Grouped Bilty / Chakkar", currentEntryPoints: ["src/components/bilty/ChakkarDetailsModal.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the grouped Chakkar detail report. Legacy Booking Slip remains a separate supported print using the Bilty document key.", ur: "چار لے آؤٹس گروپ چکر کی تفصیل رپورٹ شامل کرتے ہیں۔ پرانی بکنگ سلپ بلٹی دستاویز کی الگ پرنٹ سہولت ہے۔" } },
  { documentType: "loading", label: "Loading", currentEntryPoints: ["src/components/loadingDetails/LoadingPrint.tsx", "src/app/(dashboard)/loading/page.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover Loading slips from both the Loading list and Loading detail; filtered and supplied totals are preserved.", ur: "چار لے آؤٹس لوڈنگ فہرست اور تفصیل دونوں سے لوڈنگ سلپ شامل کرتے ہیں؛ فلٹر اور فراہم کردہ ٹوٹل برقرار ہیں۔" } },
  { documentType: "packing_slip", label: "Packing Slip", currentEntryPoints: ["src/app/(dashboard)/packing/page.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the saved Packing Slip and item rows; tenant ownership is resolved through its Loading.", ur: "چار لے آؤٹس محفوظ پیکنگ سلپ اور آئٹم قطاریں شامل کرتے ہیں؛ اڈے کی ملکیت لوڈنگ سے طے ہوتی ہے۔" } },
  { documentType: "voucher", label: "Standard and Manual Voucher", currentEntryPoints: ["src/app/(dashboard)/expenses/page.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_individual" },
  { documentType: "parchi", label: "Parchi", currentEntryPoints: ["src/components/parchi/Parchi.tsx", "src/components/parchi/ParchiPrint.ts"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the Parchi arrangement/history and individual posted funding, settlement or reversal receipts. Principal is presented from the existing Parchi source only.", ur: "چار لے آؤٹس پرچی معاہدہ/تاریخ اور درج شدہ فنڈنگ، ادائیگی یا ریورسل رسید شامل کرتے ہیں۔ اصل رقم صرف موجودہ پرچی سورس سے دکھائی جاتی ہے۔" } },
  { documentType: "cashbook", label: "Cashbook", currentEntryPoints: ["src/components/cashbook/CashbookTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts print the authorized filtered Cashbook rows and supplied totals; the report is explicitly limited to the selected period/filter.", ur: "چار لے آؤٹس مجاز فلٹر شدہ کیش بک اندراجات اور فراہم کردہ ٹوٹل پرنٹ کرتے ہیں؛ رپورٹ منتخب مدت/فلٹر تک محدود ہے۔" } },
  { documentType: "customer_ledger", label: "Customer Ledger", currentEntryPoints: ["src/components/ledger/CustomerLedgerTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the existing authorized Customer statement, supplied balances and report rows.", ur: "چار لے آؤٹس موجودہ مجاز کسٹمر اسٹیٹمنٹ، فراہم کردہ بیلنس اور رپورٹ اندراجات شامل کرتے ہیں۔" } },
  { documentType: "party_ledger", label: "Party Ledger", currentEntryPoints: ["src/components/party-ledger/PartyLedgerPrint.tsx", "src/components/party-ledger/PartyTripsModal.tsx", "src/components/party-ledger/PartyLedgerTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the filtered Party statement, per-Party statement and trip detail print actions. Mixed/unresolved Adda reports require one Adda filter.", ur: "چار لے آؤٹس فلٹر شدہ پارٹی اسٹیٹمنٹ، فی پارٹی اسٹیٹمنٹ اور ٹرپ تفصیل پرنٹ کو شامل کرتے ہیں۔ متعدد یا غیر تصدیق شدہ اڈوں کے لیے ایک اڈہ منتخب کریں۔" } },
  { documentType: "broker_ledger", label: "Broker Ledger", currentEntryPoints: ["src/components/brokers/BrokerLedger.tsx", "src/components/brokers/BrokerTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the filtered Broker ledger and individual transaction print. Parchi is not added unless supplied by the existing Broker statement source.", ur: "چار لے آؤٹس فلٹر شدہ بروکر لیجر اور انفرادی لین دین پرنٹ کو شامل کرتے ہیں۔ پارچی صرف موجودہ بروکر اسٹیٹمنٹ کے فراہم کردہ ڈیٹا پر شامل ہے۔" } },
  { documentType: "driver_ledger", label: "Driver activity and ledger", currentEntryPoints: ["src/components/ledger/DriverLedgerView.tsx", "src/components/drivers/DriverSalaryAccount.tsx", "src/components/drivers/DriverManager.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover Driver Activity, Driver Account balances/history, payment receipts and the assignment-history report. Mixed/unresolved Adda reports are blocked.", ur: "چار لے آؤٹس ڈرائیور سرگرمی، اکاؤنٹ بیلنس/تاریخ، ادائیگی رسید اور تعیناتی تاریخ رپورٹ شامل کرتے ہیں۔ متعدد یا غیر تصدیق شدہ اڈوں کی رپورٹ بند ہے۔" } },
  { documentType: "owner_ledger", label: "Owner Ledger", currentEntryPoints: ["src/components/ownerLedger/OwnerPrint.tsx", "src/components/ownerLedger/OwnerTripsModal.tsx", "src/components/ownerLedger/printOwnerLedger.ts"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover filtered Owner reports and Owner trip-detail prints, including the existing Chakkar leg adjustments.", ur: "چار لے آؤٹس فلٹر شدہ مالک رپورٹس اور ٹرپ تفصیل پرنٹ کو شامل کرتے ہیں، بشمول موجودہ چکر لیگ ایڈجسٹمنٹس۔" } },
  { documentType: "vehicle_ledger", label: "Vehicle Ledger", currentEntryPoints: ["src/components/vehicleLedger/VehicleTripsModal.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the existing per-vehicle trip statement with recorded freight legs, payments, expenses and supplied report totals.", ur: "چار لے آؤٹس فی گاڑی موجودہ ٹرپ اسٹیٹمنٹ میں درج کرایہ لیگ، ادائیگی، اخراجات اور رپورٹ کے فراہم کردہ ٹوٹل شامل کرتے ہیں۔" } },
  { documentType: "vehicle_monthly_hisab", label: "Vehicle Monthly Hisab", currentEntryPoints: ["src/components/vehicle-monthly-hisab/VehicleMonthlyHisab.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the existing period report and selected Chakkar slip using approved supplied totals. Owner withdrawals and monthly Adda commission cuts are not added.", ur: "چار لے آؤٹس موجودہ مدت رپورٹ اور منتخب چکر سلپ کو منظور شدہ ٹوٹل کے ساتھ شامل کرتے ہیں۔ مالک کی نکاسی یا ماہانہ اڈہ کمیشن منہا نہیں کیا جاتا۔" } },
  { documentType: "owner_gari_account", label: "Owner / Gari Account", currentEntryPoints: ["src/components/owner-gari-account/OwnerGariAccount.tsx", "src/components/owner-gari-account/OwnerGariAccountPrint.ts", "src/components/owner-gari-account/OwnerGariWithdrawalReceiptPrint.ts"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the existing Owner/Gari period statement and authorized withdrawal receipts from their existing read sources. Legacy print remains available as fallback.", ur: "چار لے آؤٹس موجودہ مالک/گاڑی مدت کی اسٹیٹمنٹ اور موجودہ مجاز ریڈ سورس سے ودہولڈنگ رسیدوں کو شامل کرتے ہیں۔ پرانا پرنٹ متبادل کے طور پر دستیاب ہے۔" } },
  { documentType: "adda_account", label: "Adda Account", currentEntryPoints: ["src/components/adda-account/AddaAccount.tsx", "src/components/adda-account/AddaAccountPrint.ts"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the existing individual Adda Finance entry voucher and its recorded settlement/reversal history; no new statement query is introduced.", ur: "چار لے آؤٹس موجودہ انفرادی اڈہ فنانس اندراج اور اس کی درج شدہ ادائیگی/واپسی تاریخ کو شامل کرتے ہیں؛ کوئی نئی اسٹیٹمنٹ کوئری شامل نہیں۔" } },
  { documentType: "other_adda_receipt", label: "Other Adda statements and payment receipts", currentEntryPoints: ["src/components/other-addas/OtherAddaAccount.tsx", "src/components/other-addas/OtherAddaPaymentReceipt.ts"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the authorized Other Adda account statement and individual payment receipt. Obligations and Cashbook payments stay in separate source sections.", ur: "چار لے آؤٹس مجاز دوسرے اڈے کا اکاؤنٹ اسٹیٹمنٹ اور ادائیگی رسید شامل کرتے ہیں۔ واجبات اور کیش بک ادائیگیاں الگ سورس حصوں میں رہتی ہیں۔" } },
  { documentType: "payment_receipt", label: "Payment Receipts", currentEntryPoints: ["src/components/paymentReceipts/PaymentReceiptTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover individual receipt slips and filtered receipt reports from authorized rows.", ur: "چار لے آؤٹس مجاز اندراجات سے انفرادی رسیدیں اور فلٹر شدہ رسید رپورٹ شامل کرتے ہیں۔" } },
  { documentType: "diesel", label: "Diesel reports", currentEntryPoints: ["src/components/diesel/DieselTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "New layouts: individual Diesel entry and filtered Diesel report. Legacy print remains available as fallback.", ur: "نئے لے آؤٹس: انفرادی ڈیزل اندراج اور فلٹر شدہ ڈیزل رپورٹ۔ پرانا پرنٹ متبادل کے طور پر دستیاب ہے۔" } },
  { documentType: "petrol_pump", label: "Petrol pump and payments", currentEntryPoints: ["src/components/petrolPumps/PetrolPumpTable.tsx", "src/components/petrolPumpPayments/PetrolPumpPaymentTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "New layouts: pump Diesel ledger, individual payment receipt and payment report. Legacy print remains available as fallback.", ur: "نئے لے آؤٹس: پمپ ڈیزل لیجر، انفرادی ادائیگی رسید اور ادائیگی رپورٹ۔ پرانا پرنٹ متبادل کے طور پر دستیاب ہے۔" } },
  { documentType: "oil", label: "Oil statements and reports", currentEntryPoints: ["src/components/oil/OilManager.tsx", "src/components/oil/OilSupplierAccount.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "New layouts: purchase bill, vehicle oil issue, external sale, stock movement ledger, vehicle history and supplier statement. No shop-list print action exists in the current UI. Legacy print remains available as fallback.", ur: "نئے لے آؤٹس: خریداری بل، گاڑی کو آئل اجرا، بیرونی فروخت، اسٹاک نقل و حرکت لیجر، گاڑی کی ہسٹری اور سپلائر اسٹیٹمنٹ۔ موجودہ انٹرفیس میں دکانوں کی فہرست پرنٹ کرنے کا اختیار نہیں۔ پرانا پرنٹ متبادل کے طور پر دستیاب ہے۔" } },
  { documentType: "tyre", label: "Tyre statements and reports", currentEntryPoints: ["src/components/tyre/TyreManager.tsx", "src/components/tyre/TyreShopAccount.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "New layouts: tyre event/fitment history and Tyre Shop statement. No separate entry slip was present in the existing UI. Legacy print remains available as fallback.", ur: "نئے لے آؤٹس: ٹائر ایونٹ/فٹنگ ہسٹری اور ٹائر شاپ اسٹیٹمنٹ۔ موجودہ انٹرفیس میں علیحدہ اندراج سلپ موجود نہیں تھی۔ پرانا پرنٹ متبادل کے طور پر دستیاب ہے۔" } },
  { documentType: "workshop", label: "Workshop records, master list and accounts", currentEntryPoints: ["src/components/workshop/WorkshopTable.tsx", "src/components/workshop/WorkshopAccount.tsx", "src/components/workshop/WorkshopMaster.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover individual work entries, reports, payment receipts, account ledger and the filtered Workshop master list. Existing print remains a fallback.", ur: "چار لے آؤٹس انفرادی کام، رپورٹ، ادائیگی رسید، اکاؤنٹ لیجر اور فلٹر شدہ ورکشاپ فہرست شامل کرتے ہیں۔ موجودہ پرنٹ متبادل ہے۔" } },
  { documentType: "vehicle_document", label: "Vehicle Documents", currentEntryPoints: ["src/components/vehicle-documents/VehicleDocumentPrint.tsx", "src/components/vehicle-documents/VehicleDocumentTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the filtered Vehicle Document register and individual selected document; a single verified Adda is required for branding.", ur: "چار لے آؤٹس فلٹر شدہ گاڑی دستاویز رجسٹر اور منتخب دستاویز شامل کرتے ہیں؛ برانڈنگ کے لیے ایک تصدیق شدہ اڈہ ضروری ہے۔" } },
  { documentType: "employee", label: "Employee and payroll documents", currentEntryPoints: ["src/components/employees/EmployeeTable.tsx", "src/components/employees/EmployeeSalarySlip.tsx", "src/components/employees/EmployeeSalaryTable.tsx", "src/components/employees/EmployeeLedgerTable.tsx", "src/components/employees/EmployeeLoanTable.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover employee register, salary slips/reports, employee ledger entries/statements and loan receipts/reports. Existing authorized rows and totals are presented unchanged.", ur: "چار لے آؤٹس ملازم رجسٹر، تنخواہ سلپ/رپورٹ، ملازم لیجر اندراج/اسٹیٹمنٹ اور قرض رسید/رپورٹ شامل کرتے ہیں۔ موجودہ مجاز اندراجات اور ٹوٹل برقرار ہیں۔" } },
  { documentType: "reports", label: "Loading and vehicle reports", currentEntryPoints: ["src/components/reports/ReportTable.tsx", "src/components/reports/VehicleWiseReport.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover supported filtered Loading and Vehicle-wise reports. Adda branding is withheld for mixed or unresolved owners.", ur: "چار لے آؤٹس فلٹر شدہ لوڈنگ اور گاڑی وار رپورٹس شامل کرتے ہیں۔ مخلوط یا غیر تصدیق شدہ ملکیت میں اڈہ برانڈنگ نہیں دکھتی۔" } },
  { documentType: "audit_log", label: "Audit Logs", currentEntryPoints: ["src/components/audit-logs/AuditLogPrint.tsx"], legacyPrintAvailable: true, newTemplateStatus: "implemented_flows", coverageNote: { en: "Four layouts cover the currently authorized, single-Adda filtered audit log report; unresolved or mixed contexts are blocked.", ur: "چار لے آؤٹس موجودہ مجاز ایک اڈے کی فلٹر شدہ آڈٹ لاگ رپورٹ شامل کرتے ہیں؛ غیر تصدیق شدہ یا مخلوط سیاق بند ہے۔" } },
] as const;

export function getPrintTemplate(id: PrintTemplateId): PrintTemplateDefinition {
  const definition = PRINT_TEMPLATES.find((template) => template.id === id);
  if (!definition) throw new Error(`Unknown print template: ${id}`);
  return definition;
}

/** The four layouts are released for the supported individual and ledger/report document flows. */
const implementedDocumentTypes: readonly PrintDocumentType[] = [
  "bilty", "bilty_chakkar", "loading", "packing_slip", "voucher", "parchi", "cashbook",
  "customer_ledger", "party_ledger", "broker_ledger", "driver_ledger", "owner_ledger",
  "vehicle_ledger", "vehicle_monthly_hisab", "owner_gari_account", "adda_account",
  "other_adda_receipt", "payment_receipt", "diesel", "petrol_pump", "oil", "tyre",
  "workshop", "vehicle_document", "employee", "reports", "audit_log",
];

export function isPrintTemplateImplementedForDocument(
  documentType: PrintDocumentType,
  templateId: PrintTemplateId,
): boolean {
  return implementedDocumentTypes.includes(documentType)
    && PRINT_TEMPLATES.some((template) => template.id === templateId);
}

export function getPrintTemplateStatusForDocument(
  documentType: PrintDocumentType,
  templateId: PrintTemplateId,
): "ready" | "foundation_preview_only" | "planned" {
  if (isPrintTemplateImplementedForDocument(documentType, templateId)) return "ready";
  return templateId === "traditional_pad" ? "foundation_preview_only" : "planned";
}

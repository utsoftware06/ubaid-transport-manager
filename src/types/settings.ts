export type AppLanguage = "en" | "ur";

export type AppCurrency = "PKR";

export type AppDateFormat = "DD-MM-YYYY" | "MM-DD-YYYY" | "YYYY-MM-DD";

export type AppTheme = "light" | "dark" | "system";

export type PaperSize = "A4" | "A5" | "thermal-80mm";

export interface CompanySettings {
  id: string;
  adda_id: string;

  company_name: string;
  business_tagline: string | null;
  logo_url: string | null;

  phone: string | null;
  alternate_phone: string | null;
  email: string | null;
  address: string | null;
  city: string | null;

  ntn_number: string | null;
  gst_number: string | null;

  language: AppLanguage;
  currency: AppCurrency;
  date_format: AppDateFormat;
  theme: AppTheme;

  bilty_prefix: string;
  loading_prefix: string;
  receipt_prefix: string;

  paper_size: PaperSize;
  show_logo_on_print: boolean;
  show_signature_on_print: boolean;
  print_footer_text: string | null;

  created_at: string;
  updated_at: string;
}

export interface CompanySettingsFormValues {
  companyName: string;
  businessTagline: string;
  logoUrl: string;

  phone: string;
  alternatePhone: string;
  email: string;
  address: string;
  city: string;

  ntnNumber: string;
  gstNumber: string;

  language: AppLanguage;
  currency: AppCurrency;
  dateFormat: AppDateFormat;
  theme: AppTheme;

  biltyPrefix: string;
  loadingPrefix: string;
  receiptPrefix: string;

  paperSize: PaperSize;
  showLogoOnPrint: boolean;
  showSignatureOnPrint: boolean;
  printFooterText: string;
}

export type SettingsSaveStatus = "idle" | "saving" | "success" | "error";

export type SettingsTab = "company" | "localization" | "numbering" | "printing";

export type SettingsTabItem = {
  id: SettingsTab;
  label: string;
  description: string;
};

export const defaultCompanySettingsFormValues: CompanySettingsFormValues = {
  companyName: "",
  businessTagline: "",
  logoUrl: "",
  phone: "",
  alternatePhone: "",
  email: "",
  address: "",
  city: "",
  ntnNumber: "",
  gstNumber: "",
  language: "en",
  currency: "PKR",
  dateFormat: "DD-MM-YYYY",
  theme: "light",
  biltyPrefix: "BLT",
  loadingPrefix: "LDG",
  receiptPrefix: "RCP",
  paperSize: "A4",
  showLogoOnPrint: true,
  showSignatureOnPrint: true,
  printFooterText: "",
};

export const settingsTabs: SettingsTabItem[] = [
  {
    id: "company",
    label: "Company Profile",
    description: "Business identity and contact information",
  },
  {
    id: "localization",
    label: "Language & Regional",
    description: "Language, currency, date format and theme",
  },
  {
    id: "numbering",
    label: "Document Numbering",
    description: "Prefixes used for bilty, loading and receipts",
  },
  {
    id: "printing",
    label: "Print Settings",
    description: "Paper size, logo, signature and print footer",
  },
];
"use client";

import { useEffect, useEffectEvent, useState } from "react";
import CompanyProfileForm from "@/components/settings/CompanyProfileForm";
import DocumentNumberingForm from "@/components/settings/DocumentNumberingForm";
import LocalizationSettingsForm from "@/components/settings/LocalizationSettingsForm";
import PrintSettingsForm from "@/components/settings/PrintSettingsForm";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import {
  type CompanySettings,
  type CompanySettingsFormValues,
  type SettingsSaveStatus,
  defaultCompanySettingsFormValues,
} from "@/types/settings";

type SettingsManagerProps = {
  addaId: string;
};

type CompanySettingsPayload = {
  adda_id: string;
  company_name: string;
  business_tagline: string | null;
  logo_url: string | null;
  phone: string;
  alternate_phone: string | null;
  email: string | null;
  address: string | null;
  city: string | null;
  ntn_number: string | null;
  gst_number: string | null;
  language: CompanySettingsFormValues["language"];
  currency: CompanySettingsFormValues["currency"];
  date_format: CompanySettingsFormValues["dateFormat"];
  theme: CompanySettingsFormValues["theme"];
  bilty_prefix: string;
  loading_prefix: string;
  receipt_prefix: string;
  paper_size: CompanySettingsFormValues["paperSize"];
  show_logo_on_print: boolean;
  show_signature_on_print: boolean;
  print_footer_text: string | null;
};

function nullableTrimmedValue(value: string) {
  const trimmedValue = value.trim();
  return trimmedValue.length > 0 ? trimmedValue : null;
}

function mapDatabaseSettingsToFormValues(
  settings: CompanySettings
): CompanySettingsFormValues {
  return {
    companyName: settings.company_name,
    businessTagline: settings.business_tagline ?? "",
    logoUrl: settings.logo_url ?? "",
    phone: settings.phone ?? "",
    alternatePhone: settings.alternate_phone ?? "",
    email: settings.email ?? "",
    address: settings.address ?? "",
    city: settings.city ?? "",
    ntnNumber: settings.ntn_number ?? "",
    gstNumber: settings.gst_number ?? "",
    language: settings.language,
    currency: settings.currency,
    dateFormat: settings.date_format,
    theme: settings.theme,
    biltyPrefix: settings.bilty_prefix,
    loadingPrefix: settings.loading_prefix,
    receiptPrefix: settings.receipt_prefix,
    paperSize: settings.paper_size,
    showLogoOnPrint: settings.show_logo_on_print,
    showSignatureOnPrint: settings.show_signature_on_print,
    printFooterText: settings.print_footer_text ?? "",
  };
}

function mapFormValuesToDatabasePayload(
  values: CompanySettingsFormValues,
  addaId: string
): CompanySettingsPayload {
  return {
    adda_id: addaId,
    company_name: values.companyName.trim(),
    business_tagline: nullableTrimmedValue(values.businessTagline),
    logo_url: nullableTrimmedValue(values.logoUrl),
    phone: values.phone.trim(),
    alternate_phone: nullableTrimmedValue(values.alternatePhone),
    email: nullableTrimmedValue(values.email),
    address: nullableTrimmedValue(values.address),
    city: nullableTrimmedValue(values.city),
    ntn_number: nullableTrimmedValue(values.ntnNumber),
    gst_number: nullableTrimmedValue(values.gstNumber),
    language: values.language,
    currency: values.currency,
    date_format: values.dateFormat,
    theme: values.theme,
    bilty_prefix: values.biltyPrefix.trim(),
    loading_prefix: values.loadingPrefix.trim(),
    receipt_prefix: values.receiptPrefix.trim(),
    paper_size: values.paperSize,
    show_logo_on_print: values.showLogoOnPrint,
    show_signature_on_print: values.showSignatureOnPrint,
    print_footer_text: nullableTrimmedValue(values.printFooterText),
  };
}

export default function SettingsManager({ addaId }: SettingsManagerProps) {
  const { setLanguage, t } = useLanguage();

  const [formValues, setFormValues] = useState<CompanySettingsFormValues>(
    defaultCompanySettingsFormValues
  );
  const [initialValues, setInitialValues] = useState<CompanySettingsFormValues>(
    defaultCompanySettingsFormValues
  );
  const [isLoading, setIsLoading] = useState(true);
  const [saveStatus, setSaveStatus] = useState<SettingsSaveStatus>("idle");
  const [errorMessage, setErrorMessage] = useState("");

  const showLoadError = useEffectEvent(() => {
    setErrorMessage(t("settings.loadError"));
  });

  useEffect(() => {
    let isActive = true;

    async function loadSettings() {
      setIsLoading(true);
      setErrorMessage("");

      try {
        const { data, error } = await supabase
          .from("company_settings")
          .select("*")
          .eq("adda_id", addaId)
          .maybeSingle();

        if (!isActive) return;

        if (error) {
          throw new Error(error.message || "Unable to load company settings.");
        }

        if (data) {
          const mappedValues = mapDatabaseSettingsToFormValues(
            data as CompanySettings
          );

          setLanguage(mappedValues.language);
          setFormValues(mappedValues);
          setInitialValues(mappedValues);
          return;
        }

        setLanguage(defaultCompanySettingsFormValues.language);
        setFormValues(defaultCompanySettingsFormValues);
        setInitialValues(defaultCompanySettingsFormValues);
      } catch (error) {
        if (!isActive) return;
        console.error("Unable to load company settings:", error);
        showLoadError();
      } finally {
        if (isActive) {
          setIsLoading(false);
        }
      }
    }

    const loadTimer = window.setTimeout(() => {
      void loadSettings();
    }, 0);

    return () => {
      isActive = false;
      window.clearTimeout(loadTimer);
    };
  }, [addaId, setLanguage]);

  useEffect(() => {
    if (saveStatus !== "success") return;

    const timeoutId = window.setTimeout(() => {
      setSaveStatus("idle");
    }, 3000);

    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [saveStatus]);

  function updateField<K extends keyof CompanySettingsFormValues>(
    field: K,
    value: CompanySettingsFormValues[K]
  ) {
    setFormValues((currentValues) => ({
      ...currentValues,
      [field]: value,
    }));
  }

  function resetSettings() {
    setFormValues(initialValues);
    setLanguage(initialValues.language);
    setSaveStatus("idle");
    setErrorMessage("");
  }

  async function saveSettings() {
    setSaveStatus("saving");
    setErrorMessage("");

    if (!formValues.companyName.trim()) {
      setSaveStatus("error");
      setErrorMessage(t("settings.validation.companyNameRequired"));
      return;
    }

    if (!formValues.phone.trim()) {
      setSaveStatus("error");
      setErrorMessage(t("settings.validation.phoneRequired"));
      return;
    }

    if (!formValues.biltyPrefix.trim()) {
      setSaveStatus("error");
      setErrorMessage(t("settings.validation.biltyPrefixRequired"));
      return;
    }

    if (!formValues.loadingPrefix.trim()) {
      setSaveStatus("error");
      setErrorMessage(t("settings.validation.loadingPrefixRequired"));
      return;
    }

    if (!formValues.receiptPrefix.trim()) {
      setSaveStatus("error");
      setErrorMessage(t("settings.validation.receiptPrefixRequired"));
      return;
    }

    try {
      const payload = mapFormValuesToDatabasePayload(formValues, addaId);

      const { data, error } = await supabase
        .from("company_settings")
        .upsert(payload, {
          onConflict: "adda_id",
        })
        .select("*")
        .single();

      if (error) {
        throw new Error(error.message || "Unable to save company settings.");
      }

      const mappedValues = mapDatabaseSettingsToFormValues(
        data as CompanySettings
      );

      setLanguage(mappedValues.language);
      setFormValues(mappedValues);
      setInitialValues(mappedValues);
      setSaveStatus("success");
    } catch (error) {
      console.error("Unable to save company settings:", error);
      setSaveStatus("error");
      setErrorMessage(t("settings.saveError"));
    }
  }

  if (isLoading) {
    return (
      <div className="rounded-2xl border border-gray-200 bg-white p-8 text-center shadow-md">
        <p className="text-base font-extrabold text-gray-900">
          {t("settings.loading")}
        </p>
      </div>
    );
  }

  return (
    <section className="ut-module-page space-y-6">
      {errorMessage && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
          {errorMessage}
        </div>
      )}

      <div id="company" className="scroll-mt-24">
        <CompanyProfileForm
          contextKey={addaId}
          values={formValues}
          onChange={updateField}
          onSave={saveSettings}
          onReset={resetSettings}
          saveStatus={saveStatus}
        />
      </div>

      <div id="localization" className="scroll-mt-24">
        <LocalizationSettingsForm
          values={formValues}
          onChange={updateField}
          onSave={saveSettings}
          onReset={resetSettings}
          saveStatus={saveStatus}
        />
      </div>

      <div id="numbering" className="scroll-mt-24">
        <DocumentNumberingForm
          values={formValues}
          onChange={updateField}
          onSave={saveSettings}
          onReset={resetSettings}
          saveStatus={saveStatus}
        />
      </div>

      <div id="printing" className="scroll-mt-24">
        <PrintSettingsForm
          values={formValues}
          onChange={updateField}
          onSave={saveSettings}
          onReset={resetSettings}
          saveStatus={saveStatus}
        />
      </div>
    </section>
  );
}

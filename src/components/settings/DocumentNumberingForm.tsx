import { FileText, Hash, Receipt, Truck } from "lucide-react";
import { useLanguage } from "@/contexts/LanguageContext";
import type {
  CompanySettingsFormValues,
  SettingsSaveStatus,
} from "@/types/settings";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type DocumentNumberingFormProps = {
  values: CompanySettingsFormValues;
  onChange: <K extends keyof CompanySettingsFormValues>(
    field: K,
    value: CompanySettingsFormValues[K]
  ) => void;
  onSave: () => void | Promise<void>;
  onReset: () => void;
  saveStatus: SettingsSaveStatus;
};

type PrefixCard = {
  titleKey: string;
  descriptionKey: string;
  name: "biltyPrefix" | "loadingPrefix" | "receiptPrefix";
  value: string;
  placeholder: string;
  icon: typeof FileText;
  iconClassName: string;
};

export default function DocumentNumberingForm({
  values,
  onChange,
  onSave,
  onReset,
  saveStatus,
}: DocumentNumberingFormProps) {
  const { t, dir } = useLanguage();
  const isSaving = saveStatus === "saving";

  const prefixCards: PrefixCard[] = [
    {
      titleKey: "documentNumbering.biltyPrefix",
      descriptionKey: "documentNumbering.biltyPrefixDescription",
      name: "biltyPrefix",
      value: values.biltyPrefix,
      placeholder: "BLT",
      icon: FileText,
      iconClassName: "bg-blue-100 text-blue-700",
    },
    {
      titleKey: "documentNumbering.loadingPrefix",
      descriptionKey: "documentNumbering.loadingPrefixDescription",
      name: "loadingPrefix",
      value: values.loadingPrefix,
      placeholder: "LDG",
      icon: Truck,
      iconClassName: "bg-green-100 text-green-700",
    },
    {
      titleKey: "documentNumbering.receiptPrefix",
      descriptionKey: "documentNumbering.receiptPrefixDescription",
      name: "receiptPrefix",
      value: values.receiptPrefix,
      placeholder: "RCP",
      icon: Receipt,
      iconClassName: "bg-purple-100 text-purple-700",
    },
  ];

  function handlePrefixChange(
    field: "biltyPrefix" | "loadingPrefix" | "receiptPrefix",
    value: string
  ) {
    onChange(field, value.toUpperCase());
  }

  return (
    <section
      dir={dir}
      className="rounded-2xl border border-gray-200 bg-white p-6 shadow-md"
    >
      <div className="border-b border-gray-200 pb-5">
        <h2 className="text-2xl font-extrabold text-gray-900">
          {t("documentNumbering.title")}
        </h2>
        <p className="mt-2 text-sm font-semibold text-gray-900">
          {t("documentNumbering.description")}
        </p>
      </div>

      <form
        className="mt-6 space-y-6"
        onSubmit={(event) => {
          event.preventDefault();
          void onSave();
        }}
      >
        <div className="flex items-start gap-4 rounded-2xl border border-blue-200 bg-blue-50 p-5">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-white text-blue-700 shadow-sm">
            <Hash className="h-6 w-6" aria-hidden="true" />
          </div>
          <p className="text-sm font-bold leading-6 text-gray-900">
            {t("documentNumbering.infoBanner")}
          </p>
        </div>

        <div className="grid grid-cols-1 gap-5 lg:grid-cols-3">
          {prefixCards.map((card) => {
            const Icon = card.icon;

            return (
              <div
                key={card.name}
                className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm"
              >
                <div className="flex items-start gap-4">
                  <div
                    className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-xl ${card.iconClassName}`}
                  >
                    <Icon className="h-6 w-6" aria-hidden="true" />
                  </div>


                  <div className="min-w-0 flex-1">
                    <label
                      htmlFor={card.name}
                      className="text-sm font-extrabold text-gray-900"
                    >
                      {t(card.titleKey)}
                    </label>
                    <p className="mt-1 text-sm font-semibold text-gray-900">
                      {t(card.descriptionKey)}
                    </p>

                    <VoiceTypingField fieldLabel={card.placeholder} mode="text"><input
                      id={card.name}
                      name={card.name}
                      type="text"
                      value={card.value}
                      onChange={(event) =>
                        handlePrefixChange(card.name, event.target.value)
                      }
                      placeholder={card.placeholder}
                      className="mt-4 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold uppercase text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                    /></VoiceTypingField>
                  </div>

                </div>
              </div>
            );
          })}
        </div>

        <div className="space-y-4 border-t border-gray-200 pt-6">
          <div className="flex flex-col gap-3 sm:flex-row sm:justify-end">
            <button
              type="button"
              onClick={onReset}
              disabled={isSaving}
              className="rounded-xl bg-gray-200 px-6 py-3 text-sm font-extrabold text-gray-900 shadow-sm transition hover:bg-gray-300 disabled:cursor-not-allowed disabled:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gray-500 focus-visible:ring-offset-2"
            >
              {t("common.reset")}
            </button>

            <button
              type="submit"
              disabled={isSaving}
              className="rounded-xl bg-blue-600 px-6 py-3 text-sm font-extrabold text-white shadow-sm transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
            >
              {saveStatus === "saving"
                ? t("documentNumbering.saving")
                : saveStatus === "success"
                  ? t("documentNumbering.savedSuccessfully")
                  : t("common.saveChanges")}
            </button>
          </div>

          {saveStatus === "success" && (
            <div className="rounded-xl border border-green-200 bg-green-50 p-4 text-sm font-bold text-green-700">
              {t("documentNumbering.successMessage")}
            </div>
          )}

          {saveStatus === "error" && (
            <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
              {t("documentNumbering.errorMessage")}
            </div>
          )}
        </div>
      </form>
    </section>
  );
}
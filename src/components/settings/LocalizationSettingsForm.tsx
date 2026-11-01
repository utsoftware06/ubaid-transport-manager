import { CalendarDays, Coins, Languages, Palette } from "lucide-react";
import { useLanguage } from "@/contexts/LanguageContext";
import type { AppLanguage } from "@/i18n/translations";
import type {
  CompanySettingsFormValues,
  SettingsSaveStatus,
} from "@/types/settings";

type LocalizationSettingsFormProps = {
  values: CompanySettingsFormValues;
  onChange: <K extends keyof CompanySettingsFormValues>(
    field: K,
    value: CompanySettingsFormValues[K]
  ) => void;
  onSave: () => void | Promise<void>;
  onReset: () => void;
  saveStatus: SettingsSaveStatus;
};

export default function LocalizationSettingsForm({
  values,
  onChange,
  onSave,
  onReset,
  saveStatus,
}: LocalizationSettingsFormProps) {
  const { t, setLanguage, dir } = useLanguage();
  const isSaving = saveStatus === "saving";

  return (
    <section
      dir={dir}
      className="rounded-2xl border border-gray-200 bg-white p-6 shadow-md"
    >
      <div className="border-b border-gray-200 pb-5">
        <h2 className="text-2xl font-extrabold text-gray-900">
          {t("localization.title")}
        </h2>
        <p className="mt-2 text-sm font-semibold text-gray-900">
          {t("localization.description")}
        </p>
      </div>

      <form
        className="mt-6 space-y-6"
        onSubmit={(event) => {
          event.preventDefault();
          void onSave();
        }}
      >
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
          <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-blue-100 text-blue-700">
                <Languages className="h-6 w-6" aria-hidden="true" />
              </div>

              <div className="min-w-0 flex-1">
                <label
                  htmlFor="settings-language"
                  className="text-sm font-extrabold text-gray-900"
                >
                  {t("localization.applicationLanguage")}
                </label>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  {t("localization.applicationLanguageDescription")}
                </p>

                <select
                  id="settings-language"
                  name="language"
                  value={values.language}
                  onChange={(event) => {
                    const selectedLanguage = event.target.value as AppLanguage;
                    onChange("language", selectedLanguage);
                    setLanguage(selectedLanguage);
                  }}
                  className="mt-4 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                >
                  <option value="en">{t("localization.english")}</option>
                  <option value="ur">{t("localization.urdu")}</option>
                </select>
              </div>
            </div>
          </div>

          <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-green-100 text-green-700">
                <Coins className="h-6 w-6" aria-hidden="true" />
              </div>

              <div className="min-w-0 flex-1">
                <label
                  htmlFor="settings-currency"
                  className="text-sm font-extrabold text-gray-900"
                >
                  {t("localization.currency")}
                </label>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  {t("localization.currencyDescription")}
                </p>

                <select
                  id="settings-currency"
                  name="currency"
                  value={values.currency}
                  disabled
                  className="mt-4 w-full cursor-not-allowed rounded-xl border border-gray-300 bg-gray-50 px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none"
                >
                  <option value="PKR">{t("localization.pakistaniRupee")}</option>
                </select>
              </div>
            </div>
          </div>

          <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-indigo-100 text-indigo-700">
                <CalendarDays className="h-6 w-6" aria-hidden="true" />
              </div>

              <div className="min-w-0 flex-1">
                <label
                  htmlFor="settings-date-format"
                  className="text-sm font-extrabold text-gray-900"
                >
                  {t("localization.dateFormat")}
                </label>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  {t("localization.dateFormatDescription")}
                </p>

                <select
                  id="settings-date-format"
                  name="dateFormat"
                  value={values.dateFormat}
                  onChange={(event) =>
                    onChange(
                      "dateFormat",
                      event.target
                        .value as CompanySettingsFormValues["dateFormat"]
                    )
                  }
                  className="mt-4 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                >
                  <option value="DD-MM-YYYY">DD-MM-YYYY</option>
                  <option value="MM-DD-YYYY">MM-DD-YYYY</option>
                  <option value="YYYY-MM-DD">YYYY-MM-DD</option>
                </select>
              </div>
            </div>
          </div>

          <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-purple-100 text-purple-700">
                <Palette className="h-6 w-6" aria-hidden="true" />
              </div>

              <div className="min-w-0 flex-1">
                <label
                  htmlFor="settings-theme"
                  className="text-sm font-extrabold text-gray-900"
                >
                  {t("localization.appearance")}
                </label>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  {t("localization.appearanceDescription")}
                </p>

                <select
                  id="settings-theme"
                  name="theme"
                  value={values.theme}
                  onChange={(event) =>
                    onChange(
                      "theme",
                      event.target.value as CompanySettingsFormValues["theme"]
                    )
                  }
                  className="mt-4 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                >
                  <option value="light">{t("localization.light")}</option>
                  <option value="dark">{t("localization.dark")}</option>
                  <option value="system">
                    {t("localization.systemDefault")}
                  </option>
                </select>
              </div>
            </div>
          </div>
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
                ? t("localization.saving")
                : saveStatus === "success"
                  ? t("localization.savedSuccessfully")
                  : t("common.saveChanges")}
            </button>
          </div>

          {saveStatus === "success" && (
            <div className="rounded-xl border border-green-200 bg-green-50 p-4 text-sm font-bold text-green-700">
              {t("localization.successMessage")}
            </div>
          )}

          {saveStatus === "error" && (
            <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
              {t("localization.errorMessage")}
            </div>
          )}
        </div>
      </form>
    </section>
  );
}
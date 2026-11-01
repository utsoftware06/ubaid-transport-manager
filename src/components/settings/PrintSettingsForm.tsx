import {
  AlignLeft,
  FileText,
  Image as ImageIcon,
  Printer,
  Signature,
} from "lucide-react";
import { useLanguage } from "@/contexts/LanguageContext";
import type {
  CompanySettingsFormValues,
  SettingsSaveStatus,
} from "@/types/settings";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type PrintSettingsFormProps = {
  values: CompanySettingsFormValues;
  onChange: <K extends keyof CompanySettingsFormValues>(
    field: K,
    value: CompanySettingsFormValues[K]
  ) => void;
  onSave: () => void | Promise<void>;
  onReset: () => void;
  saveStatus: SettingsSaveStatus;
};

export default function PrintSettingsForm({
  values,
  onChange,
  onSave,
  onReset,
  saveStatus,
}: PrintSettingsFormProps) {
  const { t, dir } = useLanguage();
  const isSaving = saveStatus === "saving";

  return (
    <section
      dir={dir}
      className="rounded-2xl border border-gray-200 bg-white p-6 shadow-md"
    >
      <div className="border-b border-gray-200 pb-5">
        <h2 className="text-2xl font-extrabold text-gray-900">
          {t("printSettingsForm.title")}
        </h2>
        <p className="mt-2 text-sm font-semibold text-gray-900">
          {t("printSettingsForm.description")}
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
            <Printer className="h-6 w-6" aria-hidden="true" />
          </div>
          <p className="text-sm font-bold leading-6 text-gray-900">
            {t("printSettingsForm.infoBanner")}
          </p>
        </div>

        <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
          <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-blue-100 text-blue-700">
                <FileText className="h-6 w-6" aria-hidden="true" />
              </div>

              <div className="min-w-0 flex-1">
                <label
                  htmlFor="settings-paper-size"
                  className="text-sm font-extrabold text-gray-900"
                >
                  {t("printSettingsForm.paperSize")}
                </label>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  {t("printSettingsForm.paperSizeDescription")}
                </p>

                <select
                  id="settings-paper-size"
                  name="paperSize"
                  value={values.paperSize}
                  onChange={(event) =>
                    onChange(
                      "paperSize",
                      event.target
                        .value as CompanySettingsFormValues["paperSize"]
                    )
                  }
                  className="mt-4 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                >
                  <option value="A4">{t("printSettingsForm.a4")}</option>
                  <option value="A5">{t("printSettingsForm.a5")}</option>
                  <option value="thermal-80mm">
                    {t("printSettingsForm.thermal80mm")}
                  </option>
                </select>
              </div>
            </div>
          </div>

          <label className="block rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-green-100 text-green-700">
                <ImageIcon className="h-6 w-6" aria-hidden="true" />
              </div>

              <div className="min-w-0 flex-1">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <span className="text-sm font-extrabold text-gray-900">
                      {t("printSettingsForm.showLogo")}
                    </span>
                    <p className="mt-1 text-sm font-semibold text-gray-900">
                      {t("printSettingsForm.showLogoDescription")}
                    </p>
                  </div>

                  <input
                    type="checkbox"
                    name="showLogoOnPrint"
                    checked={values.showLogoOnPrint}
                    onChange={(event) =>
                      onChange("showLogoOnPrint", event.target.checked)
                    }
                    className="mt-1 h-5 w-5 shrink-0 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                  />
                </div>
              </div>
            </div>
          </label>

          <label className="block rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-purple-100 text-purple-700">
                <Signature className="h-6 w-6" aria-hidden="true" />
              </div>

              <div className="min-w-0 flex-1">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <span className="text-sm font-extrabold text-gray-900">
                      {t("printSettingsForm.showSignature")}
                    </span>
                    <p className="mt-1 text-sm font-semibold text-gray-900">
                      {t("printSettingsForm.showSignatureDescription")}
                    </p>
                  </div>

                  <input
                    type="checkbox"
                    name="showSignatureOnPrint"
                    checked={values.showSignatureOnPrint}
                    onChange={(event) =>
                      onChange("showSignatureOnPrint", event.target.checked)
                    }
                    className="mt-1 h-5 w-5 shrink-0 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                  />
                </div>
              </div>
            </div>
          </label>

          <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm lg:col-span-2">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-indigo-100 text-indigo-700">
                <AlignLeft className="h-6 w-6" aria-hidden="true" />
              </div>


              <div className="min-w-0 flex-1">
                <label
                  htmlFor="settings-print-footer-text"
                  className="text-sm font-extrabold text-gray-900"
                >
                  {t("printSettingsForm.footerText")}
                </label>
                <p className="mt-1 text-sm font-semibold text-gray-900">
                  {t("printSettingsForm.footerTextDescription")}
                </p>

                <VoiceTypingField fieldLabel={t("printSettingsForm.footerTextPlaceholder")} mode="text"><textarea
                  id="settings-print-footer-text"
                  name="printFooterText"
                  rows={4}
                  value={values.printFooterText}
                  onChange={(event) =>
                    onChange("printFooterText", event.target.value)
                  }
                  placeholder={t("printSettingsForm.footerTextPlaceholder")}
                  className="mt-4 w-full resize-none rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                /></VoiceTypingField>
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
                ? t("printSettingsForm.saving")
                : saveStatus === "success"
                  ? t("printSettingsForm.savedSuccessfully")
                  : t("common.saveChanges")}
            </button>
          </div>

          {saveStatus === "success" && (
            <div className="rounded-xl border border-green-200 bg-green-50 p-4 text-sm font-bold text-green-700">
              {t("printSettingsForm.successMessage")}
            </div>
          )}

          {saveStatus === "error" && (
            <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
              {t("printSettingsForm.errorMessage")}
            </div>
          )}
        </div>
      </form>
    </section>
  );
}

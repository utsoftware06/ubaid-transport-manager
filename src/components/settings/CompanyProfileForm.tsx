import { useLanguage } from "@/contexts/LanguageContext";
import CompanyLogoUpload from "@/components/settings/CompanyLogoUpload";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import type {
  CompanySettingsFormValues,
  SettingsSaveStatus,
} from "@/types/settings";

type CompanyProfileFormProps = {
  contextKey?: string;
  values: CompanySettingsFormValues;
  onChange: <K extends keyof CompanySettingsFormValues>(
    field: K,
    value: CompanySettingsFormValues[K]
  ) => void;
  onSave: () => void | Promise<void>;
  onReset: () => void;
  saveStatus: SettingsSaveStatus;
  addaId: string;
  settingsExists: boolean;
  canManageLogo: boolean;
  onLogoSaved: (reference: string) => void;
  onLogoBusyChange: (busy: boolean) => void;
};

export default function CompanyProfileForm({
  contextKey = "",
  values,
  onChange,
  onSave,
  onReset,
  saveStatus,
  addaId,
  settingsExists,
  canManageLogo,
  onLogoSaved,
  onLogoBusyChange,
}: CompanyProfileFormProps) {
  const { t, dir } = useLanguage();
  const isSaving = saveStatus === "saving";

  return (
    <section
      dir={dir}
      className="rounded-2xl border border-gray-200 bg-white p-6 shadow-md"
    >
      <div className="border-b border-gray-200 pb-5">
        <h2 className="text-2xl font-extrabold text-gray-900">
          {t("companyProfile.title")}
        </h2>
        <p className="mt-2 text-sm font-semibold text-gray-900">
          {t("companyProfile.description")}
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
          <label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.companyName")} *
            </span>
            <VoiceTypingField fieldLabel={t("companyProfile.companyName")} value={values.companyName} onValueChange={(value) => onChange("companyName", value)} contextKey={contextKey}>
              <input
                type="text"
                name="companyName"
                value={values.companyName}
                onChange={(event) => onChange("companyName", event.target.value)}
                placeholder={t("companyProfile.companyNamePlaceholder")}
                className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </VoiceTypingField>
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.businessTagline")}
            </span>
            <VoiceTypingField fieldLabel={t("companyProfile.businessTagline")} value={values.businessTagline} onValueChange={(value) => onChange("businessTagline", value)} contextKey={contextKey}>
              <input
                type="text"
                name="businessTagline"
                value={values.businessTagline}
                onChange={(event) => onChange("businessTagline", event.target.value)}
                placeholder={t("companyProfile.businessTaglinePlaceholder")}
                className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </VoiceTypingField>
          </label>


          <CompanyLogoUpload
            key={contextKey}
            addaId={addaId}
            logoReference={values.logoUrl}
            settingsExists={settingsExists}
            canManage={canManageLogo}
            onSaved={onLogoSaved}
            onBusyChange={onLogoBusyChange}
          />



          <VoiceTypingField fieldLabel={t("companyProfile.phonePlaceholder")} mode="phone"><label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.phone")} *
            </span>
            <input
              type="tel"
              name="phone"
              value={values.phone}
              onChange={(event) => onChange("phone", event.target.value)}
              placeholder={t("companyProfile.phonePlaceholder")}
              className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>



          <VoiceTypingField fieldLabel={t("companyProfile.alternatePhonePlaceholder")} mode="phone"><label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.alternatePhone")}
            </span>
            <input
              type="tel"
              name="alternatePhone"
              value={values.alternatePhone}
              onChange={(event) =>
                onChange("alternatePhone", event.target.value)
              }
              placeholder={t("companyProfile.alternatePhonePlaceholder")}
              className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>



          <VoiceTypingField fieldLabel={t("companyProfile.emailPlaceholder")} mode="email"><label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.email")}
            </span>
            <input
              type="email"
              name="email"
              value={values.email}
              onChange={(event) => onChange("email", event.target.value)}
              placeholder={t("companyProfile.emailPlaceholder")}
              className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>


          <label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.city")}
            </span>
            <VoiceTypingField fieldLabel={t("companyProfile.city")} value={values.city} onValueChange={(value) => onChange("city", value)} contextKey={contextKey}>
              <input
                type="text"
                name="city"
                value={values.city}
                onChange={(event) => onChange("city", event.target.value)}
                placeholder={t("companyProfile.cityPlaceholder")}
                className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </VoiceTypingField>
          </label>

          <label className="block lg:col-span-2">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.address")}
            </span>
            <VoiceTypingField fieldLabel={t("companyProfile.address")} value={values.address} onValueChange={(value) => onChange("address", value)} contextKey={contextKey}>
              <textarea
                name="address"
                rows={4}
                value={values.address}
                onChange={(event) => onChange("address", event.target.value)}
                placeholder={t("companyProfile.addressPlaceholder")}
                className="mt-2 w-full resize-none rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
              />
            </VoiceTypingField>
          </label>


          <VoiceTypingField fieldLabel={t("companyProfile.ntnNumberPlaceholder")} mode="identifier"><label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.ntnNumber")}
            </span>
            <input
              type="text"
              name="ntnNumber"
              value={values.ntnNumber}
              onChange={(event) => onChange("ntnNumber", event.target.value)}
              placeholder={t("companyProfile.ntnNumberPlaceholder")}
              className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>



          <VoiceTypingField fieldLabel={t("companyProfile.gstNumberPlaceholder")} mode="identifier"><label className="block">
            <span className="text-sm font-extrabold text-gray-900">
              {t("companyProfile.gstNumber")}
            </span>
            <input
              type="text"
              name="gstNumber"
              value={values.gstNumber}
              onChange={(event) => onChange("gstNumber", event.target.value)}
              placeholder={t("companyProfile.gstNumberPlaceholder")}
              className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 shadow-sm outline-none transition placeholder:text-gray-500 focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </label></VoiceTypingField>

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
                ? t("companyProfile.saving")
                : saveStatus === "success"
                  ? t("companyProfile.savedSuccessfully")
                  : t("common.saveChanges")}
            </button>
          </div>

          {saveStatus === "success" && (
            <div className="rounded-xl border border-green-200 bg-green-50 p-4 text-sm font-bold text-green-700">
              {t("companyProfile.successMessage")}
            </div>
          )}

          {saveStatus === "error" && (
            <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
              {t("companyProfile.errorMessage")}
            </div>
          )}
        </div>
      </form>
    </section>
  );
}

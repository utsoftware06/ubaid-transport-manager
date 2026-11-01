"use client";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  contextKey: string;
  brokerName: string;
  setBrokerName: (value: string) => void;
  contactPerson: string;
  setContactPerson: (value: string) => void;
  phone: string;
  setPhone: (value: string) => void;
  cnic: string;
  setCnic: (value: string) => void;
  address: string;
  setAddress: (value: string) => void;
  openingBalance: string;
  setOpeningBalance: (value: string) => void;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

export default function BrokerForm({
  contextKey,
  brokerName,
  setBrokerName,
  contactPerson,
  setContactPerson,
  phone,
  setPhone,
  cnic,
  setCnic,
  address,
  setAddress,
  openingBalance,
  setOpeningBalance,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
}: Props) {
  const { t, dir } = useLanguage();
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? t("brokers.edit") : t("brokers.add")}
          </h2>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("brokers.formDescription")}
          </p>
        </div>

        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg bg-gray-200 px-5 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            {t("common.cancelEdit")}
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("brokers.name")}
          </label>
          <VoiceTypingField fieldLabel={t("brokers.name")} value={brokerName} onValueChange={setBrokerName} contextKey={contextKey}>
          <input
            type="text"
            value={brokerName}
            onChange={(event) => setBrokerName(event.target.value)}
            placeholder={t("brokers.name")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("brokers.contactPerson")}
          </label>
          <VoiceTypingField fieldLabel={t("brokers.contactPerson")} value={contactPerson} onValueChange={setContactPerson} contextKey={contextKey}>
          <input
            type="text"
            value={contactPerson}
            onChange={(event) => setContactPerson(event.target.value)}
            placeholder={t("brokers.contactPerson")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("brokers.phone")}
          </label>
          <VoiceTypingField fieldLabel={t("brokers.phone")} value={phone} onValueChange={setPhone} mode="phone" contextKey={contextKey}>
          <input
            type="text"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            placeholder={t("brokers.phone")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("brokers.cnic")}
          </label>
          <VoiceTypingField fieldLabel={t("brokers.cnic")} value={cnic} onValueChange={setCnic} mode="cnic" contextKey={contextKey}>
          <input
            type="text"
            value={cnic}
            onChange={(event) => setCnic(event.target.value)}
            placeholder={t("brokers.cnic")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.openingBalance")}
          </label>
          <VoiceTypingField fieldLabel={t("common.openingBalance")} value={openingBalance} onValueChange={setOpeningBalance} mode="amount" contextKey={contextKey}>
          <input
            type="number"
            value={openingBalance}
            onChange={(event) => setOpeningBalance(event.target.value)}
            placeholder="0"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("brokers.address")}
          </label>
          <VoiceTypingField fieldLabel={t("brokers.address")} value={address} onValueChange={setAddress} contextKey={contextKey}>
          <input
            type="text"
            value={address}
            onChange={(event) => setAddress(event.target.value)}
            placeholder={t("brokers.address")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>
      </div>

      <div className="mt-6 flex justify-end">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? t("common.saving")
            : isEditing
              ? t("brokers.update")
              : t("brokers.save")}
        </button>
      </div>
    </div>
  );
}

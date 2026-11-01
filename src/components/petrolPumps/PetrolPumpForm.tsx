"use client";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  pumpName: string;
  setPumpName: (value: string) => void;
  ownerName: string;
  setOwnerName: (value: string) => void;
  phone: string;
  setPhone: (value: string) => void;
  address: string;
  setAddress: (value: string) => void;
  openingBalance: string;
  setOpeningBalance: (value: string) => void;
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
};

export default function PetrolPumpForm({
  pumpName,
  setPumpName,
  ownerName,
  setOwnerName,
  phone,
  setPhone,
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
    <form
      dir={dir}
      onSubmit={(event) => {
        event.preventDefault();
        onSave();
      }}
      className="rounded-xl bg-white p-6 shadow-md md:p-8"
    >
      <div className="mb-6 flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            {isEditing ? t("petrolPumps.actions.edit") : t("petrolPumps.actions.add")}
          </h2>

          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("petrolPumps.formDescription")}
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

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-5">
        <div>
          <label htmlFor="petrol-pump-name" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumps.fields.pumpName")}
          </label>

          <VoiceTypingField fieldLabel={t("petrolPumps.fields.pumpName")} value={pumpName} onValueChange={setPumpName} contextKey={isEditing ? "edit" : "new"}>
            <input
              id="petrol-pump-name"
              type="text"
              value={pumpName}
              onChange={(event) => setPumpName(event.target.value)}
              placeholder={t("petrolPumps.placeholders.pumpName")}
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>

        <div>
          <label htmlFor="petrol-pump-owner" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumps.fields.ownerName")}
          </label>

          <VoiceTypingField fieldLabel={t("petrolPumps.fields.ownerName")} value={ownerName} onValueChange={setOwnerName} contextKey={isEditing ? "edit" : "new"}>
            <input
              id="petrol-pump-owner"
              type="text"
              value={ownerName}
              onChange={(event) => setOwnerName(event.target.value)}
              placeholder={t("petrolPumps.placeholders.ownerName")}
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>


        <div>
          <label htmlFor="petrol-pump-phone" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumps.fields.phone")}
          </label>

          <VoiceTypingField fieldLabel={t("petrolPumps.placeholders.phone")} mode="phone"><input
            id="petrol-pump-phone"
            type="text"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            placeholder={t("petrolPumps.placeholders.phone")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label htmlFor="petrol-pump-address" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumps.fields.address")}
          </label>

          <VoiceTypingField fieldLabel={t("petrolPumps.fields.address")} value={address} onValueChange={setAddress} contextKey={isEditing ? "edit" : "new"}>
            <input
              id="petrol-pump-address"
              type="text"
              value={address}
              onChange={(event) => setAddress(event.target.value)}
              placeholder={t("petrolPumps.placeholders.address")}
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>


        <div>
          <label htmlFor="petrol-pump-opening-balance" className="mb-2 block text-sm font-bold text-gray-900">
            {t("petrolPumps.fields.openingBalance")}
          </label>

          <VoiceTypingField fieldLabel={t("petrolPumps.fields.openingBalance")} mode="amount"><input
            id="petrol-pump-opening-balance"
            type="number"
            min="0"
            step="0.01"
            value={openingBalance}
            onChange={(event) => setOpeningBalance(event.target.value)}
            placeholder="0"
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>

      </div>

      <div className="mt-6 flex justify-end">
        <button
          type="submit"
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-400"
        >
          {isSaving
            ? t("common.saving")
            : isEditing
              ? t("petrolPumps.actions.update")
              : t("petrolPumps.actions.save")}
        </button>
      </div>
    </form>
  );
}

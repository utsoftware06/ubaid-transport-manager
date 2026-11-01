"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import {
  type CashbookEntryType,
  type CashbookPersonType,
  type CashbookPaymentMethod,
  type VehicleOption,
  type DriverOption,
  type LoadingOption,
} from "./Cashbook";

type Props = {
  voiceContextKey: string;
  entryDate: string;
  setEntryDate: (value: string) => void;
  entryType: CashbookEntryType;
  setEntryType: (value: CashbookEntryType) => void;
  personType: CashbookPersonType;
  setPersonType: (value: CashbookPersonType) => void;
  personName: string;
  setPersonName: (value: string) => void;
  vehicleId: string;
  setVehicleId: (value: string) => void;
  driverId: string;
  setDriverId: (value: string) => void;
  loadingId: string;
  setLoadingId: (value: string) => void;
  paymentMethod: CashbookPaymentMethod;
  setPaymentMethod: (value: CashbookPaymentMethod) => void;
  amount: string;
  setAmount: (value: string) => void;
  description: string;
  setDescription: (value: string) => void;
  vehicles: VehicleOption[];
  drivers: DriverOption[];
  loadings: LoadingOption[];
  onSave: () => void;
  onCancel: () => void;
  isEditing: boolean;
  isSaving: boolean;
};

const entryTypes: CashbookEntryType[] = ["Cash In", "Cash Out"];

const personTypes: CashbookPersonType[] = [
  "Customer",
  "Driver",
  "Vehicle Owner",
  "Broker",
  "Adda",
  "Petrol Pump",
  "Workshop",
  "Other",
];

const paymentMethods: CashbookPaymentMethod[] = [
  "Cash",
  "Bank",
  "Cheque",
  "Online Transfer",
  "Account",
];

export default function CashbookForm({
  voiceContextKey,
  entryDate,
  setEntryDate,
  entryType,
  setEntryType,
  personType,
  setPersonType,
  personName,
  setPersonName,
  vehicleId,
  setVehicleId,
  driverId,
  setDriverId,
  loadingId,
  setLoadingId,
  paymentMethod,
  setPaymentMethod,
  amount,
  setAmount,
  description,
  setDescription,
  vehicles,
  drivers,
  loadings,
  onSave,
  onCancel,
  isEditing,
  isSaving,
}: Props) {
  const { t, dir } = useLanguage();
  const entryTypeLabel = (type: CashbookEntryType) =>
    t(`cashbook.entryTypes.${type === "Cash In" ? "cashIn" : "cashOut"}`);
  const personTypeLabel = (type: CashbookPersonType) => {
    const keys: Record<CashbookPersonType, string> = {
      Customer: "customer",
      Driver: "driver",
      "Vehicle Owner": "vehicleOwner",
      Broker: "broker",
      Adda: "adda",
      "Petrol Pump": "petrolPump",
      Workshop: "workshop",
      Other: "other",
    };
    return t(`cashbook.personTypes.${keys[type]}`);
  };
  const paymentMethodLabel = (method: CashbookPaymentMethod) => {
    const keys: Record<CashbookPaymentMethod, string> = {
      Cash: "cash",
      Bank: "bank",
      Cheque: "cheque",
      "Online Transfer": "onlineTransfer",
      Account: "account",
    };
    return t(`cashbook.paymentMethods.${keys[method]}`);
  };
  const selectedLoading =
    loadings.find((loading) => loading.id === loadingId) ?? null;

  function handleLoadingChange(value: string) {
    setLoadingId(value);
    const loading = loadings.find((item) => item.id === value);
    setPersonName(loading?.senderName === "Customer" ? "" : loading?.senderName ?? "");
    setVehicleId(loading?.vehicleId ?? "");
    setDriverId(loading?.driverId ?? "");
  }

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {t("cashbook.form.title")}
        </h2>
        <p className="mt-1 text-sm font-medium text-gray-900">
          {t("cashbook.form.description")}
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.entryDate")}
          </label>
          <VoiceTypingField fieldLabel={t("cashbook.fields.entryDate")} value={entryDate} onValueChange={setEntryDate} mode="date" contextKey={voiceContextKey}>
          <input
            type="date"
            aria-label={t("cashbook.fields.entryDate")}
            dir="ltr"
            value={entryDate}
            onChange={(event) => setEntryDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.entryType")}
          </label>
          <select
            aria-label={t("cashbook.fields.entryType")}
            value={entryType}
            onChange={(event) =>
              setEntryType(event.target.value as CashbookEntryType)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {entryTypes.map((type) => (
              <option key={type} value={type}>
                {entryTypeLabel(type)}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.personType")}
          </label>
          <select
            aria-label={t("cashbook.fields.personType")}
            value={personType}
            onChange={(event) =>
              setPersonType(event.target.value as CashbookPersonType)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {personTypes.map((type) => (
              <option key={type} value={type}>
                {personTypeLabel(type)}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.personName")}
          </label>
          <VoiceTypingField fieldLabel={t("cashbook.fields.personName")} value={personName} onValueChange={setPersonName} contextKey={voiceContextKey}>
          <input
            type="text"
            aria-label={t("cashbook.fields.personName")}
            value={personName}
            onChange={(event) => setPersonName(event.target.value)}
            placeholder={t("cashbook.placeholders.personName")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.vehicleOptional")}
          </label>
          <select
            aria-label={t("cashbook.fields.vehicleOptional")}
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("cashbook.placeholders.selectVehicle")}</option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.vehicleNo}
                {vehicle.ownerName && vehicle.ownerName !== "-"
                  ? ` - ${vehicle.ownerName}`
                  : ""}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.driverOptional")}
          </label>
          <select
            aria-label={t("cashbook.fields.driverOptional")}
            value={driverId}
            onChange={(event) => setDriverId(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("cashbook.placeholders.selectDriver")}</option>
            {drivers.map((driver) => (
              <option key={driver.id} value={driver.id}>
                {driver.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.loadingOptional")}
          </label>
          <select
            aria-label={t("cashbook.fields.loadingOptional")}
            value={loadingId}
            onChange={(event) => handleLoadingChange(event.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("cashbook.placeholders.selectLoading")}</option>
            {loadings.map((loading) => (
              <option key={loading.id} value={loading.id}>
                {loading.loadingNo} - {loading.vehicleNo} - {loading.route}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("cashbook.fields.paymentMethod")}
          </label>
          <select
            aria-label={t("cashbook.fields.paymentMethod")}
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as CashbookPaymentMethod)
            }
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            {paymentMethods.map((method) => (
              <option key={method} value={method}>
                {paymentMethodLabel(method)}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.amount")}
          </label>
          <VoiceTypingField fieldLabel={t("common.amount")} value={amount} onValueChange={setAmount} mode="amount" contextKey={voiceContextKey}>
          <input
            type="number"
            aria-label={t("common.amount")}
            min="0"
            step="0.01"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            placeholder={t("cashbook.placeholders.amount")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          />
          </VoiceTypingField>
        </div>


        <div className="md:col-span-2 xl:col-span-3">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.description")}
          </label>
          <VoiceTypingField fieldLabel={t("common.description")} value={description} onValueChange={setDescription} mode="text" contextKey={voiceContextKey}><input
            type="text"
            aria-label={t("common.description")}
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            placeholder={t("cashbook.placeholders.description")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>

      </div>

      {selectedLoading && (
        <div className="mt-6 rounded-lg border border-blue-100 bg-blue-50 p-4">
          <p className="text-sm font-bold text-gray-900">
            {t("cashbook.form.selectedLoading")}:{" "}
            <span dir="ltr">{selectedLoading.loadingNo}</span>
          </p>
          <p className="mt-1 text-sm font-semibold text-gray-900">
            {t("common.vehicle")}:{" "}
            <span dir="ltr">{selectedLoading.vehicleNo}</span> |{" "}
            {t("common.driver")}: {selectedLoading.driverName} |{" "}
            {t("common.route")}: {selectedLoading.route}
          </p>
        </div>
      )}

      <div className="mt-6 flex flex-wrap justify-end gap-3">
        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving ? t("common.states.saving") : t(isEditing ? "common.actions.update" : "cashbook.actions.saveEntry")}
        </button>
        {isEditing && (
          <button type="button" onClick={onCancel} disabled={isSaving} className="rounded-lg border border-gray-300 bg-white px-8 py-3 text-sm font-bold">
            {t("common.actions.cancel")}
          </button>
        )}
      </div>
    </div>
  );
}

"use client";

import { useMemo, useState } from "react";

import {
  type VehicleOption,
  type WorkshopPaymentStatus,
  type WorkshopOption,
  formatAmount,
} from "./Workshop";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import WorkshopWorkItems from "./WorkshopWorkItems";
import type { WorkshopWorkItem } from "./workshopWorkTypes";

type Props = {
  workDate: string;
  setWorkDate: (value: string) => void;
  vehicleId: string;
  setVehicleId: (value: string) => void;
  workshopName: string;
  workshopId: string;
  onWorkshopChange: (value: string) => void;
  workshops: WorkshopOption[];
  mechanicName: string;
  setMechanicName: (value: string) => void;
  workItems: WorkshopWorkItem[];
  setWorkItems: (value: WorkshopWorkItem[]) => void;
  billNo: string;
  setBillNo: (value: string) => void;
  paidAmount: string;
  setPaidAmount: (value: string) => void;
  nextServiceDate: string;
  setNextServiceDate: (value: string) => void;
  odometer: string;
  setOdometer: (value: string) => void;
  remarks: string;
  setRemarks: (value: string) => void;
  vehicles: VehicleOption[];
  onSave: () => void;
  isSaving: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
  vehicleLocked?: boolean;
};

function getPaymentStatus(
  paidAmount: number,
  totalCost: number
): WorkshopPaymentStatus {
  if (paidAmount <= 0) return "Unpaid";
  if (paidAmount >= totalCost) return "Paid";
  return "Partial";
}

function getStatusClass(status: WorkshopPaymentStatus) {
  if (status === "Paid") return "border-green-200 bg-green-100 text-green-700";
  if (status === "Partial") {
    return "border-yellow-200 bg-yellow-100 text-yellow-700";
  }
  return "border-red-200 bg-red-100 text-red-700";
}

export default function WorkshopForm({
  workDate,
  setWorkDate,
  vehicleId,
  setVehicleId,
  workshopName,
  workshopId,
  onWorkshopChange,
  workshops,
  mechanicName,
  setMechanicName,
  workItems,
  setWorkItems,
  billNo,
  setBillNo,
  paidAmount,
  setPaidAmount,
  nextServiceDate,
  setNextServiceDate,
  odometer,
  setOdometer,
  remarks,
  setRemarks,
  vehicles,
  onSave,
  isSaving,
  isEditing,
  onCancelEdit,
  vehicleLocked = false,
}: Props) {
  const { t, dir } = useLanguage();
  const [workshopSearch, setWorkshopSearch] = useState("");
  const visibleWorkshops = useMemo(() => {
    const keyword = workshopSearch.trim().toLowerCase();
    if (!keyword) return workshops;
    return workshops.filter((workshop) =>
      [workshop.workshopName, workshop.ownerName, workshop.phone]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [workshopSearch, workshops]);
  const paid = Number(paidAmount || 0);
  const totalCost = workItems.reduce((total, item) => total + item.amount, 0);
  const remainingAmount = Math.max(totalCost - paid, 0);
  const paymentStatus = getPaymentStatus(paid, totalCost);

  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">
          {isEditing ? t("workshop.actions.edit") : t("workshop.actions.add")}
        </h2>
        <p className="mt-1 text-sm font-medium text-gray-900">
          {t("workshop.formDescription")}
        </p>
      </div>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-4">

        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.workDate")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.fields.workDate")} mode="date"><input
            type="date"
            dir="ltr"
            value={workDate}
            onChange={(event) => setWorkDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.vehicle")}
          </label>
          {vehicleLocked ? (
            <input
              type="text"
              value={vehicles.find((vehicle) => vehicle.id === vehicleId)?.vehicleNo ?? ""}
              readOnly
              aria-readonly="true"
              className="w-full rounded-lg border border-gray-300 bg-gray-100 px-4 py-3 text-sm font-semibold text-gray-900"
            />
          ) : (
            <select
              value={vehicleId}
              onChange={(event) => setVehicleId(event.target.value)}
              className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            >
              <option value="">{t("workshop.placeholders.selectVehicle")}</option>
              {vehicles.map((vehicle) => (
                <option key={vehicle.id} value={vehicle.id}>
                  {vehicle.vehicleNo} - {vehicle.ownerName}
                </option>
              ))}
            </select>
          )}
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.workshopName")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.placeholders.searchWorkshop")} mode="text"><input
            type="search"
            value={workshopSearch}
            onChange={(event) => setWorkshopSearch(event.target.value)}
            placeholder={t("workshop.placeholders.searchWorkshop")}
            className="mb-2 w-full rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-semibold text-gray-900 placeholder:text-gray-600 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
          <select
            value={workshopId}
            onChange={(event) => onWorkshopChange(event.target.value)}
            aria-label={t("workshop.placeholders.selectWorkshop")}
            className="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          >
            <option value="">{t("workshop.placeholders.selectWorkshop")}</option>
            {visibleWorkshops.map((workshop) => (
              <option key={workshop.id} value={workshop.id}>
                {workshop.workshopName}{workshop.ownerName ? ` — ${workshop.ownerName}` : ""}
              </option>
            ))}
          </select>
          {!workshopId && workshopName && (
            <p className="mt-2 text-xs font-semibold text-amber-800">
              {t("workshop.messages.legacyWorkshop")}: {workshopName}
            </p>
          )}
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.mechanicName")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.fields.mechanicName")} value={mechanicName} onValueChange={setMechanicName} contextKey={`${vehicleId}:${workshopId}`}>
            <input
              type="text"
              value={mechanicName}
              onChange={(event) => setMechanicName(event.target.value)}
              placeholder={t("workshop.placeholders.mechanicName")}
              className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.billNo")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.placeholders.billNo")} mode="identifier"><input
            type="text"
            value={billNo}
            onChange={(event) => setBillNo(event.target.value)}
            placeholder={t("workshop.placeholders.billNo")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("workshop.fields.totalCost")}</p>
          <p dir="ltr" className="mt-2 text-xl font-extrabold text-gray-900">
            {formatAmount(totalCost)}
          </p>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.paidAmount")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.fields.paidAmount")} mode="amount"><input
            type="number"
            min="0"
            value={paidAmount}
            onChange={(event) => setPaidAmount(event.target.value)}
            placeholder="0"
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("workshop.fields.remainingAmount")}</p>
          <p dir="ltr" className="mt-2 text-xl font-extrabold text-red-700">
            {formatAmount(remainingAmount)}
          </p>
        </div>

        <div className="rounded-lg border border-gray-300 bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-gray-900">{t("workshop.fields.paymentStatus")}</p>
          <span
            className={`mt-3 inline-flex rounded-full border px-3 py-1 text-sm font-bold ${getStatusClass(
              paymentStatus
            )}`}
          >
            {t(`workshop.statuses.${paymentStatus.toLowerCase()}`)}
          </span>
        </div>


        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.nextServiceDate")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.fields.nextServiceDate")} mode="date"><input
            type="date"
            dir="ltr"
            value={nextServiceDate}
            onChange={(event) => setNextServiceDate(event.target.value)}
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>



        <div>
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("workshop.fields.odometer")}
          </label>
          <VoiceTypingField fieldLabel={t("workshop.placeholders.odometer")} mode="number"><input
            type="number"
            min="0"
            value={odometer}
            onChange={(event) => setOdometer(event.target.value)}
            placeholder={t("workshop.placeholders.odometer")}
            dir="ltr"
            className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
          /></VoiceTypingField>
        </div>


        <div className="md:col-span-2 xl:col-span-3">
          <label className="mb-2 block text-sm font-bold text-gray-900">
            {t("common.remarks")}
          </label>
          <VoiceTypingField fieldLabel={t("common.remarks")} value={remarks} onValueChange={setRemarks} contextKey={`${vehicleId}:${workshopId}`}>
            <input
              type="text"
              value={remarks}
              onChange={(event) => setRemarks(event.target.value)}
              placeholder={t("workshop.placeholders.remarks")}
              className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm font-semibold text-gray-900 placeholder:text-gray-700 outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
            />
          </VoiceTypingField>
        </div>
      </div>

      <WorkshopWorkItems items={workItems} onChange={setWorkItems} />

      <div className="mt-6 flex flex-col justify-end gap-3 sm:flex-row">
        {isEditing && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="rounded-lg bg-gray-200 px-6 py-3 text-sm font-bold text-gray-900 transition hover:bg-gray-300"
          >
            {t("common.cancelEdit")}
          </button>
        )}

        <button
          type="button"
          onClick={onSave}
          disabled={isSaving}
          className="rounded-lg bg-blue-600 px-8 py-3 text-sm font-bold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed"
        >
          {isSaving
            ? t("common.saving")
            : isEditing
              ? t("workshop.actions.update")
              : t("workshop.actions.save")}
        </button>
      </div>
    </div>
  );
}

"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  type VehicleDocumentStatus,
  type VehicleOption,
} from "./VehicleDocuments";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  vehicles: VehicleOption[];
  documentTypes: string[];
  search: string;
  setSearch: Dispatch<SetStateAction<string>>;
  selectedVehicle: string;
  setSelectedVehicle: Dispatch<SetStateAction<string>>;
  selectedStatus: string;
  setSelectedStatus: Dispatch<SetStateAction<string>>;
  selectedDocumentType: string;
  setSelectedDocumentType: Dispatch<SetStateAction<string>>;
};

const statuses: VehicleDocumentStatus[] = [
  "Permanent",
  "Active",
  "Expiring Soon",
  "Expired",
];

export default function VehicleDocumentFilters({
  vehicles,
  documentTypes,
  search,
  setSearch,
  selectedVehicle,
  setSelectedVehicle,
  selectedStatus,
  setSelectedStatus,
  selectedDocumentType,
  setSelectedDocumentType,
}: Props) {
  const { t, dir } = useLanguage();
  const statusLabel = (status: VehicleDocumentStatus) =>
    t(`vehicleDocuments.statuses.${status === "Expiring Soon" ? "expiringSoon" : status.toLowerCase()}`);
  const documentTypeLabel = (type: string) =>
    t(`vehicleDocuments.documentTypes.${type.replaceAll(" ", "").replace(/^./, (character) => character.toLowerCase())}`);
  return (
    <div dir={dir} className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <h2 className="text-2xl font-bold text-gray-900">
        {t("vehicleDocuments.filters.title")}
      </h2>


      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <VoiceTypingField fieldLabel={t("vehicleDocuments.filters.searchPlaceholder")} mode="text"><input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t("vehicleDocuments.filters.searchPlaceholder")}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600"
        /></VoiceTypingField>

        <select
          value={selectedVehicle}
          onChange={(event) => setSelectedVehicle(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="">{t("vehicleDocuments.filters.allVehicles")}</option>
          {vehicles.map((vehicle) => (
            <option key={vehicle.id} value={vehicle.id}>
              {vehicle.vehicleNo}
            </option>
          ))}
        </select>

        <select
          value={selectedDocumentType}
          onChange={(event) => setSelectedDocumentType(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="">{t("vehicleDocuments.filters.allTypes")}</option>
          {documentTypes.map((documentType) => (
            <option key={documentType} value={documentType}>
              {documentTypeLabel(documentType)}
            </option>
          ))}
        </select>

        <select
          value={selectedStatus}
          onChange={(event) => setSelectedStatus(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="">{t("vehicleDocuments.filters.allStatuses")}</option>
          {statuses.map((status) => (
            <option key={status} value={status}>
              {statusLabel(status)}
            </option>
          ))}
        </select>
      </div>

    </div>
  );
}

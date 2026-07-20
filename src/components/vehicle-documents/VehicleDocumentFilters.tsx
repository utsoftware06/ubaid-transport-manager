"use client";

import type { Dispatch, SetStateAction } from "react";
import {
  type VehicleDocumentStatus,
  type VehicleOption,
} from "./VehicleDocuments";

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
  return (
    <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
      <h2 className="text-2xl font-bold text-gray-900">
        Vehicle Document Filters
      </h2>

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search documents..."
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900 placeholder:text-gray-600"
        />

        <select
          value={selectedVehicle}
          onChange={(event) => setSelectedVehicle(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="">All Vehicles</option>
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
          <option value="">All Document Types</option>
          {documentTypes.map((documentType) => (
            <option key={documentType} value={documentType}>
              {documentType}
            </option>
          ))}
        </select>

        <select
          value={selectedStatus}
          onChange={(event) => setSelectedStatus(event.target.value)}
          className="rounded-lg border border-gray-300 bg-white p-3 font-medium text-gray-900"
        >
          <option value="">All Status</option>
          {statuses.map((status) => (
            <option key={status} value={status}>
              {status}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}
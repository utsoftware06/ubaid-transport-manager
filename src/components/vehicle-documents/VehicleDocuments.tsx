"use client";

import { useEffect, useMemo, useState } from "react";
import VehicleDocumentCards from "@/components/vehicle-documents/VehicleDocumentCards";
import VehicleDocumentFilters from "@/components/vehicle-documents/VehicleDocumentFilters";
import VehicleDocumentForm from "@/components/vehicle-documents/VehicleDocumentForm";
import VehicleDocumentPrint from "@/components/vehicle-documents/VehicleDocumentPrint";
import VehicleDocumentTable from "@/components/vehicle-documents/VehicleDocumentTable";
import { supabase } from "@/lib/supabase/client";

export type VehicleDocumentType =
  | "Token Tax"
  | "Route Permit"
  | "Fitness Certificate"
  | "Insurance"
  | "Registration Book"
  | "National Permit"
  | "Provincial Permit"
  | "Vehicle Tax"
  | "Other";

export const VEHICLE_DOCUMENT_TYPES: VehicleDocumentType[] = [
  "Token Tax",
  "Route Permit",
  "Fitness Certificate",
  "Insurance",
  "Registration Book",
  "National Permit",
  "Provincial Permit",
  "Vehicle Tax",
  "Other",
];

export type VehicleDocumentStatus =
  | "Permanent"
  | "Active"
  | "Expiring Soon"
  | "Expired";

export type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

export type VehicleDocumentRecord = {
  id: string;
  adda_id: string | null;
  vehicle_id: string;
  document_type: VehicleDocumentType;
  document_number: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  fee_amount: number;
  payment_method: string | null;
  reference_no: string | null;
  authority_name: string | null;
  attachment_url: string | null;
  remarks: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
};

export type VehicleDocumentWithStatus = VehicleDocumentRecord & {
  vehicleNo: string;
  ownerName: string;
  status: VehicleDocumentStatus;
  daysRemaining: number | null;
};

export type VehicleDocumentPayload = {
  adda_id?: string | null;
  vehicle_id: string;
  document_type: VehicleDocumentType;
  document_number?: string | null;
  issue_date?: string | null;
  expiry_date?: string | null;
  fee_amount?: number;
  payment_method?: string | null;
  reference_no?: string | null;
  authority_name?: string | null;
  attachment_url?: string | null;
  remarks?: string | null;
  created_by?: string | null;
};

export type VehicleDocumentSummary = {
  totalDocuments: number;
  activeDocuments: number;
  expiredDocuments: number;
  expiringSoonDocuments: number;
  permanentDocuments: number;
  totalFees: number;
};

type VehicleDbRow = {
  id: string;
  vehicle_no: string | null;
  owner_name: string | null;
};

type VehicleDocumentDbRow = {
  id: string;
  adda_id: string | null;
  vehicle_id: string;
  document_type: string;
  document_number: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  fee_amount: number | string | null;
  payment_method: string | null;
  reference_no: string | null;
  authority_name: string | null;
  attachment_url: string | null;
  remarks: string | null;
  created_by: string | null;
  created_at: string | null;
  updated_at: string | null;
};

export function formatAmount(value: number) {
  return `Rs. ${Math.round(Number(value || 0)).toLocaleString("en-PK")}`;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function toVehicleDocumentType(value: string): VehicleDocumentType {
  if (VEHICLE_DOCUMENT_TYPES.includes(value as VehicleDocumentType)) {
    return value as VehicleDocumentType;
  }

  return "Other";
}

export function calculateDocumentStatus(expiryDate: string | null): {
  status: VehicleDocumentStatus;
  daysRemaining: number | null;
} {
  if (!expiryDate) {
    return {
      status: "Permanent",
      daysRemaining: null,
    };
  }

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const expiry = new Date(`${expiryDate}T00:00:00`);
  const millisecondsPerDay = 1000 * 60 * 60 * 24;
  const daysRemaining = Math.ceil(
    (expiry.getTime() - today.getTime()) / millisecondsPerDay
  );

  if (daysRemaining < 0) {
    return {
      status: "Expired",
      daysRemaining,
    };
  }

  if (daysRemaining <= 30) {
    return {
      status: "Expiring Soon",
      daysRemaining,
    };
  }

  return {
    status: "Active",
    daysRemaining,
  };
}

function mapDocumentRow(row: VehicleDocumentDbRow): VehicleDocumentRecord {
  return {
    id: row.id,
    adda_id: row.adda_id,
    vehicle_id: row.vehicle_id,
    document_type: toVehicleDocumentType(row.document_type),
    document_number: row.document_number,
    issue_date: row.issue_date,
    expiry_date: row.expiry_date,
    fee_amount: toNumber(row.fee_amount),
    payment_method: row.payment_method,
    reference_no: row.reference_no,
    authority_name: row.authority_name,
    attachment_url: row.attachment_url,
    remarks: row.remarks,
    created_by: row.created_by,
    created_at: row.created_at ?? "",
    updated_at: row.updated_at ?? "",
  };
}

export default function VehicleDocuments() {
  const [documents, setDocuments] = useState<VehicleDocumentRecord[]>([]);
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [selectedDocument, setSelectedDocument] =
    useState<VehicleDocumentWithStatus | null>(null);
  const [search, setSearch] = useState("");
  const [selectedVehicle, setSelectedVehicle] = useState("");
  const [selectedStatus, setSelectedStatus] = useState("");
  const [selectedDocumentType, setSelectedDocumentType] = useState("");

  const vehicleLookup = useMemo(() => {
    return new Map(vehicles.map((vehicle) => [vehicle.id, vehicle]));
  }, [vehicles]);

  const documentsWithStatus = useMemo<VehicleDocumentWithStatus[]>(() => {
    return documents.map((document) => {
      const vehicle = vehicleLookup.get(document.vehicle_id);
      const statusInfo = calculateDocumentStatus(document.expiry_date);

      return {
        ...document,
        vehicleNo: vehicle?.vehicleNo ?? "-",
        ownerName: vehicle?.ownerName ?? "-",
        status: statusInfo.status,
        daysRemaining: statusInfo.daysRemaining,
      };
    });
  }, [documents, vehicleLookup]);

  const filteredDocuments = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    return documentsWithStatus.filter((document) => {
      if (selectedVehicle && document.vehicle_id !== selectedVehicle) {
        return false;
      }

      if (selectedStatus && document.status !== selectedStatus) {
        return false;
      }

      if (
        selectedDocumentType &&
        document.document_type !== selectedDocumentType
      ) {
        return false;
      }

      if (!keyword) return true;

      const searchableText = [
        document.vehicleNo,
        document.ownerName,
        document.document_type,
        document.document_number ?? "",
        document.payment_method ?? "",
        document.reference_no ?? "",
        document.authority_name ?? "",
        document.remarks ?? "",
        document.status,
      ]
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [
    documentsWithStatus,
    search,
    selectedDocumentType,
    selectedStatus,
    selectedVehicle,
  ]);

  const summary = useMemo<VehicleDocumentSummary>(() => {
    return filteredDocuments.reduce(
      (total, document) => {
        total.totalDocuments += 1;
        total.totalFees += document.fee_amount;

        if (document.status === "Active") total.activeDocuments += 1;
        if (document.status === "Expired") total.expiredDocuments += 1;
        if (document.status === "Expiring Soon") {
          total.expiringSoonDocuments += 1;
        }
        if (document.status === "Permanent") total.permanentDocuments += 1;

        return total;
      },
      {
        totalDocuments: 0,
        activeDocuments: 0,
        expiredDocuments: 0,
        expiringSoonDocuments: 0,
        permanentDocuments: 0,
        totalFees: 0,
      }
    );
  }, [filteredDocuments]);

  useEffect(() => {
    refreshDocuments();
  }, []);

  async function loadVehicles() {
    const { data, error: vehiclesError } = await supabase
      .from("vehicles")
      .select("id, vehicle_no, owner_name")
      .order("vehicle_no", { ascending: true });

    if (vehiclesError) {
      throw new Error(vehiclesError.message);
    }

    const vehicleRows = (data ?? []) as VehicleDbRow[];

    setVehicles(
      vehicleRows.map((vehicle) => ({
        id: vehicle.id,
        vehicleNo: vehicle.vehicle_no ?? "",
        ownerName: vehicle.owner_name ?? "",
      }))
    );
  }

  async function loadDocuments() {
    const { data, error: documentsError } = await supabase
      .from("vehicle_documents")
      .select(
        `
        id,
        adda_id,
        vehicle_id,
        document_type,
        document_number,
        issue_date,
        expiry_date,
        fee_amount,
        payment_method,
        reference_no,
        authority_name,
        attachment_url,
        remarks,
        created_by,
        created_at,
        updated_at
      `
      )
      .order("created_at", { ascending: false });

    if (documentsError) {
      throw new Error(documentsError.message);
    }

    const documentRows = (data ?? []) as VehicleDocumentDbRow[];
    setDocuments(documentRows.map(mapDocumentRow));
  }

  async function refreshDocuments() {
    setLoading(true);
    setError("");

    try {
      await Promise.all([loadVehicles(), loadDocuments()]);
    } catch (refreshError) {
      setError(
        refreshError instanceof Error
          ? refreshError.message
          : "Unable to load vehicle documents."
      );
    } finally {
      setLoading(false);
    }
  }

  async function createDocument(payload: VehicleDocumentPayload) {
    setSaving(true);
    setError("");

    try {
      const { error: createError } = await supabase
        .from("vehicle_documents")
        .insert({
          ...payload,
          fee_amount: payload.fee_amount ?? 0,
        });

      if (createError) {
        throw new Error(createError.message);
      }

      await loadDocuments();
      return true;
    } catch (createError) {
      setError(
        createError instanceof Error
          ? createError.message
          : "Unable to create vehicle document."
      );
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function updateDocument(id: string, payload: VehicleDocumentPayload) {
    setSaving(true);
    setError("");

    try {
      const { error: updateError } = await supabase
        .from("vehicle_documents")
        .update({
          ...payload,
          fee_amount: payload.fee_amount ?? 0,
        })
        .eq("id", id);

      if (updateError) {
        throw new Error(updateError.message);
      }

      setSelectedDocument(null);
      await loadDocuments();
      return true;
    } catch (updateError) {
      setError(
        updateError instanceof Error
          ? updateError.message
          : "Unable to update vehicle document."
      );
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function deleteDocument(id: string) {
    const confirmed = window.confirm("Delete this vehicle document record?");

    if (!confirmed) return false;

    setSaving(true);
    setError("");

    try {
      const { error: deleteError } = await supabase
        .from("vehicle_documents")
        .delete()
        .eq("id", id);

      if (deleteError) {
        throw new Error(deleteError.message);
      }

      if (selectedDocument?.id === id) {
        setSelectedDocument(null);
      }

      await loadDocuments();
      return true;
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Unable to delete vehicle document."
      );
      return false;
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">
          Vehicle Documents
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Manage vehicle permits, fitness, route permits, insurance and document
          expiry tracking.
        </p>
      </div>

      <VehicleDocumentCards summary={summary} loading={loading} />

      <VehicleDocumentFilters
        vehicles={vehicles}
        documentTypes={VEHICLE_DOCUMENT_TYPES}
        search={search}
        setSearch={setSearch}
        selectedVehicle={selectedVehicle}
        setSelectedVehicle={setSelectedVehicle}
        selectedStatus={selectedStatus}
        setSelectedStatus={setSelectedStatus}
        selectedDocumentType={selectedDocumentType}
        setSelectedDocumentType={setSelectedDocumentType}
      />

      <VehicleDocumentForm
        vehicles={vehicles}
        selectedDocument={selectedDocument}
        saving={saving}
        error={error}
        onCreate={createDocument}
        onUpdate={updateDocument}
        onCancel={() => setSelectedDocument(null)}
      />

      <VehicleDocumentTable
        documents={filteredDocuments}
        loading={loading}
        saving={saving}
        error={error}
        onSelect={setSelectedDocument}
        onDelete={deleteDocument}
        onRefresh={refreshDocuments}
      />

      <VehicleDocumentPrint
        documents={filteredDocuments}
        summary={summary}
        selectedDocument={selectedDocument}
      />
    </div>
  );
}
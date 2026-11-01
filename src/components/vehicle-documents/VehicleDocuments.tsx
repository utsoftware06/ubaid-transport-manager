"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import VehicleDocumentCards from "@/components/vehicle-documents/VehicleDocumentCards";
import VehicleDocumentFilters from "@/components/vehicle-documents/VehicleDocumentFilters";
import VehicleDocumentForm from "@/components/vehicle-documents/VehicleDocumentForm";
import VehicleDocumentPrint from "@/components/vehicle-documents/VehicleDocumentPrint";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
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
  const { t, dir } = useLanguage();
  const [documents, setDocuments] = useState<VehicleDocumentRecord[]>([]);
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const mutationInFlightRef = useRef(false);
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

  const loadVehicles = useCallback(async () => {
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
  }, []);

  const loadDocuments = useCallback(async () => {
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
  }, []);

  const refreshDocuments = useCallback(async () => {
    setLoading(true);
    setError("");

    try {
      await Promise.all([loadVehicles(), loadDocuments()]);
    } catch (refreshError) {
      console.error("Failed to load vehicle documents:", refreshError);
      setError(t("vehicleDocuments.messages.loadFailed"));
    } finally {
      setLoading(false);
    }
  }, [loadDocuments, loadVehicles, t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void refreshDocuments(), 0);
    return () => window.clearTimeout(timer);
  }, [refreshDocuments]);

  async function createDocument(payload: VehicleDocumentPayload) {
    if (mutationInFlightRef.current) return false;
    mutationInFlightRef.current = true;
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
      console.error("Failed to create vehicle document:", createError);
      setError(t("vehicleDocuments.messages.createFailed"));
      return false;
    } finally {
      mutationInFlightRef.current = false;
      setSaving(false);
    }
  }

  async function updateDocument(id: string, payload: VehicleDocumentPayload) {
    if (mutationInFlightRef.current) return false;
    mutationInFlightRef.current = true;
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
      console.error("Failed to update vehicle document:", updateError);
      setError(t("vehicleDocuments.messages.updateFailed"));
      return false;
    } finally {
      mutationInFlightRef.current = false;
      setSaving(false);
    }
  }

  async function deleteDocument(id: string) {
    if (mutationInFlightRef.current) return false;
    const confirmed = window.confirm(t("vehicleDocuments.messages.deleteConfirm"));

    if (!confirmed) return false;

    mutationInFlightRef.current = true;
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
      console.error("Failed to delete vehicle document:", deleteError);
      setError(t("vehicleDocuments.messages.deleteFailed"));
      return false;
    } finally {
      mutationInFlightRef.current = false;
      setSaving(false);
    }
  }

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="vehicle" accent="blue" title={t("vehicleDocuments.title")} description={t("vehicleDocuments.description")} />
      </header>

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

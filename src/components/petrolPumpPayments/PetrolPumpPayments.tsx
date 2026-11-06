"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import PetrolPumpPaymentForm from "@/components/petrolPumpPayments/PetrolPumpPaymentForm";
import PetrolPumpPaymentTable from "@/components/petrolPumpPayments/PetrolPumpPaymentTable";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { getDeleteFailureKey, type DeleteRpcError } from "@/components/petrolPumpPayments/deleteError";
import ManualDieselPaymentCorrectionModal from "@/components/petrolPumpPayments/ManualDieselPaymentCorrectionModal";
import type { ManualDieselCorrectionHistoryView, ManualDieselLinkedPaymentView } from "@/components/petrolPumpPayments/manualDieselPaymentTypes";
import { buildManualDieselCorrectionRpcPayload } from "@/lib/expenses/manualDieselPaymentCorrection";
import { publishManualDieselPaymentCorrection } from "@/lib/expenses/manualDieselPaymentCorrectionEvents";

export type PumpBalanceStatus = "Payable" | "Paid" | "Advance";

export type PetrolPumpPaymentMethod =
  | "Cash"
  | "Bank"
  | "Cheque"
  | "Online Transfer";

export type PetrolPumpOption = {
  id: string;
  pumpName: string;
  ownerName: string;
  openingBalance: number;
  totalDiesel: number;
  dieselPaid: number;
  manualPayments: number;
  currentBalance: number;
  payableAmount: number;
  advanceAmount: number;
  balanceStatus: PumpBalanceStatus;
};

export type PetrolPumpPaymentRow = {
  id: number;
  petrolPumpId: string;
  paymentDate: string;
  pumpName: string;
  ownerName: string;
  amount: number;
  advanceUsed: number;
  paymentNow: number;
  availableAdvanceBefore: number;
  currentPayableBefore: number;
  remainingPayable: number;
  remainingAdvance: number;
  settlementStatus: PumpBalanceStatus;
  paymentMethod: PetrolPumpPaymentMethod;
  referenceNo: string;
  remarks: string;
  createdAt: string;
};

type PetrolPumpDatabaseRow = {
  id: string;
  pump_name: string | null;
  owner_name: string | null;
  opening_balance: number | string | null;
};

type DieselEntryDatabaseRow = {
  id: number;
  petrol_pump_id: string | null;
  total_amount: number | string | null;
  paid_amount: number | string | null;
  remaining_amount: number | string | null;
  entry_date: string | null;
};

type PetrolPumpPaymentDatabaseRow = {
  id: number;
  petrol_pump_id: string | null;
  payment_date: string | null;
  amount: number | string | null;
  advance_used: number | string | null;
  payment_now: number | string | null;
  opening_applied: number | string | null;
  advance_created: number | string | null;
  available_advance_before: number | string | null;
  current_payable_before: number | string | null;
  remaining_payable: number | string | null;
  remaining_advance: number | string | null;
  settlement_status: string | null;
  payment_method: string | null;
  reference_no: string | null;
  remarks: string | null;
  created_at: string | null;
};

type ManualDieselInitialPaymentRow = {
  request_id: string;
  voucher_id: number;
  manual_voucher_id: string;
  adda_id: string;
  vehicle_id: string;
  diesel_entry_id: number;
  payment_id: number | null;
  payment_date: string;
  paid_amount: number | string;
  payment_method: string;
  reference_no: string | null;
  payment_remarks: string | null;
  correction_status: "active" | "voided";
};

type CorrectionHistoryDatabaseRow = {
  id: number;
  original_payment_id: number;
  replacement_payment_id: number | null;
  adda_id: string;
  voucher_id: number;
  diesel_entry_id: number;
  action: "void" | "replace";
  reason: string;
  created_at: string;
  original_snapshot: Record<string, unknown>;
  replacement_snapshot: Record<string, unknown> | null;
};

type AddaOption = { id: string; name: string };

function isMissingCorrectionSchema(error: { code?: string | null } | null) {
  return error?.code === "42P01" || error?.code === "42703" || error?.code === "PGRST205" || error?.code === "PGRST204";
}

function getCorrectionErrorKey(error: { message?: string | null; code?: string | null }) {
  const message = error.message ?? "";
  if (message.includes("REQUEST_REUSED")) return "request_reused";
  if (error.code === "42501" || message.includes("ADMIN_REQUIRED") || message.includes("ADDA_MISMATCH")) return "authorization";
  if (message.includes("VOUCHER_CONTEXT") || message.includes("VEHICLE_CONTEXT") || message.includes("PUMP_TENANT")) return "context";
  if (message.includes("ALLOCATION")) return "allocation";
  if (message.includes("CASHBOOK")) return "cashbook";
  if (message.includes("SNAPSHOT_CHANGED") || message.includes("VOUCHER")) return "finalized";
  return null;
}

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", {
    maximumFractionDigits: 0,
  })}`;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function toPaymentMethod(value: string | null): PetrolPumpPaymentMethod {
  if (
    value === "Cash" ||
    value === "Bank" ||
    value === "Cheque" ||
    value === "Online Transfer"
  ) {
    return value;
  }

  return "Cash";
}

function getBalanceStatus(
  payableAmount: number,
  advanceAmount: number
): PumpBalanceStatus {
  if (payableAmount > 0) return "Payable";
  if (advanceAmount > 0) return "Advance";
  return "Paid";
}

export default function PetrolPumpPayments() {
  const { t, dir } = useLanguage();
  const [addaId, setAddaId] = useState<string | null>(null);
  const [profileRole, setProfileRole] = useState<string | null>(null);
  const [profileActive, setProfileActive] = useState(false);
  const [addas, setAddas] = useState<AddaOption[]>([]);
  const [paymentDate, setPaymentDate] = useState("");
  const [petrolPumpId, setPetrolPumpId] = useState("");
  const [advanceUsed, setAdvanceUsed] = useState("0");
  const [paymentNow, setPaymentNow] = useState("0");
  const [paymentMethod, setPaymentMethod] =
    useState<PetrolPumpPaymentMethod>("Cash");
  const [referenceNo, setReferenceNo] = useState("");
  const [remarks, setRemarks] = useState("");

  const [pumpRows, setPumpRows] = useState<PetrolPumpDatabaseRow[]>([]);
  const [dieselEntries, setDieselEntries] = useState<
    DieselEntryDatabaseRow[]
  >([]);
  const [payments, setPayments] = useState<PetrolPumpPaymentDatabaseRow[]>([]);
  const [manualDieselLinks, setManualDieselLinks] = useState<ManualDieselLinkedPaymentView[]>([]);
  const [correctionHistory, setCorrectionHistory] = useState<ManualDieselCorrectionHistoryView[]>([]);
  const [correctionSetupState, setCorrectionSetupState] = useState<"ready" | "not_deployed" | "error" | "needs_adda">("ready");
  const [correctionLoadError, setCorrectionLoadError] = useState("");
  const [selectedCorrection, setSelectedCorrection] = useState<ManualDieselLinkedPaymentView | null>(null);
  const [search, setSearch] = useState("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [isCorrecting, setIsCorrecting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const saveInProgressRef = useRef(false);
  const deleteInProgressRef = useRef(false);
  const correctionInProgressRef = useRef(false);

  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const { data: profile, error: profileError } = await supabase.from("profiles").select("role,adda_id,is_active").eq("id", data.user.id).maybeSingle();
      if (!active || profileError || !profile?.is_active) return;
      setProfileRole(profile.role);
      setProfileActive(true);
      if (profile.role === "super_admin") {
        const { data: addaRows, error: addasError } = await supabase.from("addas").select("id,name").order("name");
        if (!active) return;
        if (addasError) {
          setErrorMessage(t("petrolPumpPayments.messages.loadFailed"));
          return;
        }
        setAddas((addaRows ?? []).map((row) => ({ id: String(row.id), name: row.name ?? String(row.id) })));
        return;
      }
      if (profile.adda_id) setAddaId(String(profile.adda_id));
    });
    return () => { active = false; };
  }, [t]);

  const loadPumps = useCallback(async () => {
    const { data, error } = await supabase
      .from("petrol_pumps")
      .select("id, pump_name, owner_name, opening_balance")
      .order("pump_name", { ascending: true });

    if (error) {
      console.error("Failed to load petrol pumps for payments:", error);
      setErrorMessage(t("petrolPumpPayments.messages.loadFailed"));
      setPumpRows([]);
      return;
    }

    setPumpRows((data ?? []) as PetrolPumpDatabaseRow[]);
  }, [t]);

  const loadDieselEntries = useCallback(async () => {
    const { data, error } = await supabase
      .from("diesel_entries")
      .select("id, petrol_pump_id, total_amount, paid_amount, remaining_amount, entry_date");

    if (error) {
      console.error("Failed to load diesel balances for payments:", error);
      setErrorMessage(t("petrolPumpPayments.messages.loadFailed"));
      setDieselEntries([]);
      return;
    }

    setDieselEntries((data ?? []) as DieselEntryDatabaseRow[]);
  }, [t]);

  const loadPayments = useCallback(async () => {
    const { data, error } = await supabase
      .from("petrol_pump_payments")
      .select(
        "id, petrol_pump_id, payment_date, amount, advance_used, payment_now, opening_applied, advance_created, available_advance_before, current_payable_before, remaining_payable, remaining_advance, settlement_status, payment_method, reference_no, remarks, created_at"
      )
      .order("payment_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Failed to load petrol pump payments:", error);
      setErrorMessage(t("petrolPumpPayments.messages.loadFailed"));
      setPayments([]);
      return;
    }

    setPayments((data ?? []) as PetrolPumpPaymentDatabaseRow[]);
  }, [t]);

  const loadManualDieselCorrectionData = useCallback(async () => {
    setManualDieselLinks([]);
    setCorrectionHistory([]);
    setCorrectionLoadError("");
    if (!addaId) {
      setCorrectionSetupState(profileRole === "super_admin" ? "needs_adda" : "ready");
      return;
    }

    const [linkResult, historyResult] = await Promise.all([
      supabase
        .from("manual_voucher_diesel_initial_payments")
        .select("request_id,voucher_id,manual_voucher_id,adda_id,vehicle_id,diesel_entry_id,payment_id,payment_date,paid_amount,payment_method,reference_no,payment_remarks,correction_status")
        .eq("adda_id", addaId)
        .eq("correction_status", "active")
        .not("payment_id", "is", null),
      supabase
        .from("manual_voucher_diesel_payment_corrections")
        .select("id,original_payment_id,replacement_payment_id,adda_id,voucher_id,diesel_entry_id,action,reason,created_at,original_snapshot,replacement_snapshot")
        .eq("adda_id", addaId)
        .order("created_at", { ascending: false })
        .limit(100),
    ]);
    const schemaError = isMissingCorrectionSchema(linkResult.error) || isMissingCorrectionSchema(historyResult.error);
    if (schemaError) {
      setCorrectionSetupState("not_deployed");
      return;
    }
    if (linkResult.error || historyResult.error) {
      console.error("Unable to load linked Manual Voucher payment correction data:", {
        linkError: linkResult.error?.code,
        historyError: historyResult.error?.code,
      });
      setCorrectionSetupState("error");
      setCorrectionLoadError(t("petrolPumpPayments.correction.loadFailed"));
      return;
    }

    const rawLinks = (linkResult.data ?? []) as unknown as ManualDieselInitialPaymentRow[];
    const historyRows = (historyResult.data ?? []) as unknown as CorrectionHistoryDatabaseRow[];
    const voucherIds = Array.from(new Set([
      ...rawLinks.map((row) => Number(row.voucher_id)),
      ...historyRows.map((row) => Number(row.voucher_id)),
    ]));
    const manualVoucherIds = Array.from(new Set(rawLinks.map((row) => row.manual_voucher_id)));
    const dieselIds = Array.from(new Set(rawLinks.map((row) => Number(row.diesel_entry_id))));
    const vehicleIds = Array.from(new Set(rawLinks.map((row) => row.vehicle_id)));
    const [voucherResult, detailResult, dieselResult, vehicleResult] = await Promise.all([
      voucherIds.length ? supabase.from("expenses").select("id,expense_no,voucher_source,loading_id,movement_group_id,archived_at").in("id", voucherIds) : Promise.resolve({ data: [], error: null }),
      manualVoucherIds.length ? supabase.from("manual_voucher_details").select("id,voucher_id,adda_id,vehicle_id,status").in("id", manualVoucherIds) : Promise.resolve({ data: [], error: null }),
      dieselIds.length ? supabase.from("diesel_entries").select("id,expense_id,manual_voucher_id,vehicle_id,total_amount,paid_amount,remaining_amount,payment_status").in("id", dieselIds) : Promise.resolve({ data: [], error: null }),
      vehicleIds.length ? supabase.from("vehicles").select("id,adda_id,vehicle_no").in("id", vehicleIds) : Promise.resolve({ data: [], error: null }),
    ]);
    const relationshipError = voucherResult.error || detailResult.error || dieselResult.error || vehicleResult.error;
    if (relationshipError) {
      console.error("Unable to resolve linked Manual Voucher payment references:", { code: relationshipError.code });
      setCorrectionSetupState("error");
      setCorrectionLoadError(t("petrolPumpPayments.correction.loadFailed"));
      return;
    }
    const vouchers = new Map((voucherResult.data ?? []).map((row) => [Number(row.id), row]));
    const details = new Map((detailResult.data ?? []).map((row) => [String(row.id), row]));
    const diesels = new Map((dieselResult.data ?? []).map((row) => [Number(row.id), row]));
    const vehicles = new Map((vehicleResult.data ?? []).map((row) => [String(row.id), row]));
    const mappedLinks: ManualDieselLinkedPaymentView[] = [];
    for (const link of rawLinks) {
      const voucher = vouchers.get(Number(link.voucher_id));
      const detail = details.get(link.manual_voucher_id);
      const diesel = diesels.get(Number(link.diesel_entry_id));
      const vehicle = vehicles.get(link.vehicle_id);
      if (
        !link.payment_id || !voucher || !detail || !diesel || !vehicle ||
        Number(voucher.id) !== Number(link.voucher_id) || voucher.voucher_source !== "manual" ||
        voucher.loading_id !== null || voucher.movement_group_id !== null || voucher.archived_at !== null ||
        Number(detail.voucher_id) !== Number(link.voucher_id) || detail.adda_id !== addaId ||
        detail.vehicle_id !== link.vehicle_id || Number(diesel.expense_id) !== Number(link.voucher_id) ||
        diesel.manual_voucher_id !== link.manual_voucher_id || diesel.vehicle_id !== link.vehicle_id ||
        vehicle.adda_id !== addaId || !["draft", "finalized"].includes(detail.status)
      ) {
        setCorrectionSetupState("error");
        setCorrectionLoadError(t("petrolPumpPayments.correction.loadFailed"));
        return;
      }
      mappedLinks.push({
        requestId: link.request_id,
        paymentId: Number(link.payment_id),
        addaId: link.adda_id,
        voucherId: Number(link.voucher_id),
        voucherNumber: voucher.expense_no?.trim() || "—",
        manualVoucherId: link.manual_voucher_id,
        voucherStatus: detail.status as "draft" | "finalized",
        dieselEntryId: Number(link.diesel_entry_id),
        vehicleNo: vehicle.vehicle_no || "—",
        correctionStatus: link.correction_status,
        paymentDate: link.payment_date,
        paidAmount: toNumber(link.paid_amount),
        paymentMethod: link.payment_method,
        referenceNo: link.reference_no,
        paymentRemarks: link.payment_remarks,
        dieselTotal: toNumber(diesel.total_amount),
        dieselPaid: toNumber(diesel.paid_amount),
        dieselRemaining: toNumber(diesel.remaining_amount),
        dieselStatus: diesel.payment_status || "Unpaid",
      });
    }
    setManualDieselLinks(mappedLinks);
    setCorrectionHistory(historyRows.map((row) => {
      const voucher = vouchers.get(Number(row.voucher_id));
      return {
        id: Number(row.id),
        originalPaymentId: Number(row.original_payment_id),
        replacementPaymentId: row.replacement_payment_id === null ? null : Number(row.replacement_payment_id),
        addaId: row.adda_id,
        voucherNumber: voucher?.expense_no?.trim() || "—",
        dieselEntryId: Number(row.diesel_entry_id),
        action: row.action,
        reason: row.reason,
        createdAt: row.created_at,
        originalSnapshot: row.original_snapshot ?? {},
        replacementSnapshot: row.replacement_snapshot,
      };
    }));
    setCorrectionSetupState("ready");
  }, [addaId, profileRole, t]);

  const loadInitialData = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage("");
    await Promise.all([loadPumps(), loadDieselEntries(), loadPayments()]);
    setIsLoading(false);
  }, [loadDieselEntries, loadPayments, loadPumps]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadInitialData(), 0);
    return () => window.clearTimeout(timer);
  }, [loadInitialData]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadManualDieselCorrectionData(), 0);
    return () => window.clearTimeout(timer);
  }, [loadManualDieselCorrectionData]);

  const pumps = useMemo<PetrolPumpOption[]>(() => {
    return pumpRows.map((pump) => {
      const linkedDiesel = dieselEntries.filter(
        (entry) => entry.petrol_pump_id === pump.id
      );
      const linkedPayments = payments.filter(
        (payment) => payment.petrol_pump_id === pump.id
      );

      const openingBalance = toNumber(pump.opening_balance);
      const totalDiesel = linkedDiesel.reduce(
        (total, entry) => total + toNumber(entry.total_amount),
        0
      );
      const dieselPaid = linkedDiesel.reduce(
        (total, entry) => total + toNumber(entry.paid_amount),
        0
      );
      const manualPayments = linkedPayments.reduce(
        (total, payment) => total + toNumber(payment.payment_now),
        0
      );
      const payableAmount = linkedDiesel.reduce(
          (total, entry) => total + toNumber(entry.remaining_amount),
          Math.max(
            Math.max(openingBalance, 0) -
              linkedPayments.reduce(
                (total, payment) =>
                  total + toNumber(payment.opening_applied),
                0
              ),
            0
          )
        );
      const advanceAmount = linkedPayments.reduce(
          (total, payment) =>
            total +
            toNumber(payment.advance_created) -
            toNumber(payment.advance_used),
          Math.max(-openingBalance, 0)
        );
      const currentBalance = payableAmount - Math.max(advanceAmount, 0);

      return {
        id: pump.id,
        pumpName: pump.pump_name ?? "-",
        ownerName: pump.owner_name ?? "-",
        openingBalance,
        totalDiesel,
        dieselPaid,
        manualPayments,
        currentBalance,
        payableAmount,
        advanceAmount: Math.max(advanceAmount, 0),
        balanceStatus: getBalanceStatus(payableAmount, advanceAmount),
      };
    });
  }, [dieselEntries, payments, pumpRows]);

  const paymentRows = useMemo<PetrolPumpPaymentRow[]>(() => {
    return payments.map((payment) => {
      const pump = pumps.find((item) => item.id === payment.petrol_pump_id);

      return {
        id: payment.id,
        petrolPumpId: payment.petrol_pump_id ?? "",
        paymentDate: payment.payment_date ?? "",
        pumpName: pump?.pumpName ?? "-",
        ownerName: pump?.ownerName ?? "-",
        amount: toNumber(payment.amount),
        advanceUsed: toNumber(payment.advance_used),
        paymentNow: toNumber(payment.payment_now),
        availableAdvanceBefore: toNumber(payment.available_advance_before),
        currentPayableBefore: toNumber(payment.current_payable_before),
        remainingPayable: toNumber(payment.remaining_payable),
        remainingAdvance: toNumber(payment.remaining_advance),
        settlementStatus:
          payment.settlement_status === "Paid" ||
          payment.settlement_status === "Advance"
            ? payment.settlement_status
            : "Payable",
        paymentMethod: toPaymentMethod(payment.payment_method),
        referenceNo: payment.reference_no ?? "-",
        remarks: payment.remarks ?? "-",
        createdAt: payment.created_at ?? "",
      };
    });
  }, [payments, pumps]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return paymentRows;

    return paymentRows.filter((row) =>
      [
        row.pumpName,
        row.ownerName,
        row.paymentMethod,
        row.referenceNo,
        row.remarks,
        String(row.amount),
        row.paymentDate,
      ]
        .join(" ")
        .toLowerCase()
        .includes(keyword)
    );
  }, [paymentRows, search]);

  const selectedPump = useMemo(() => {
    return pumps.find((pump) => pump.id === petrolPumpId) ?? null;
  }, [petrolPumpId, pumps]);

  function resetForm() {
    setPaymentDate("");
    setPetrolPumpId("");
    setAdvanceUsed("0");
    setPaymentNow("0");
    setPaymentMethod("Cash");
    setReferenceNo("");
    setRemarks("");
    setEditingId(null);
  }

  function validateForm() {
    if (!paymentDate) {
      alert(t("petrolPumpPayments.validation.dateRequired"));
      return false;
    }

    if (!petrolPumpId) {
      alert(t("petrolPumpPayments.validation.pumpRequired"));
      return false;
    }

    const advanceValue = Number(advanceUsed);
    const paymentValue = Number(paymentNow);
    if (
      !Number.isFinite(advanceValue) ||
      !Number.isFinite(paymentValue) ||
      advanceValue < 0 ||
      paymentValue < 0
    ) {
      alert(t("petrolPumpPayments.validation.splitAmountsNonNegative"));
      return false;
    }
    if (advanceValue + paymentValue <= 0) {
      alert(t("petrolPumpPayments.validation.settlementPositive"));
      return false;
    }
    const availableAdvance = editingId
      ? paymentRows.find((row) => row.id === editingId)?.availableAdvanceBefore ?? 0
      : selectedPump?.advanceAmount ?? 0;
    const currentPayable = editingId
      ? paymentRows.find((row) => row.id === editingId)?.currentPayableBefore ?? 0
      : selectedPump?.payableAmount ?? 0;
    if (advanceValue > availableAdvance || advanceValue > currentPayable) {
      alert(t("petrolPumpPayments.validation.advanceExceedsLimit"));
      return false;
    }

    if (!paymentMethod) {
      alert(t("petrolPumpPayments.validation.methodRequired"));
      return false;
    }

    return true;
  }

  async function handleSave() {
    if (saveInProgressRef.current) return;
    if (!validateForm()) return;

    saveInProgressRef.current = true;
    setIsSaving(true);

    try {
      const { error } = await supabase.rpc("save_petrol_pump_payment", {
        p_payment_id: editingId,
        p_petrol_pump_id: petrolPumpId,
        p_payment_date: paymentDate,
        p_advance_used: Number(advanceUsed),
        p_payment_now: Number(paymentNow),
        p_payment_method: paymentMethod,
        p_reference_no: referenceNo.trim(),
        p_remarks: remarks.trim(),
      });

      if (error) throw new Error(error.message);
      alert(
        t(
          editingId
            ? "petrolPumpPayments.messages.updated"
            : "petrolPumpPayments.messages.saved"
        )
      );
      resetForm();
      await Promise.all([loadPayments(), loadDieselEntries()]);
    } catch (error) {
      console.error("Failed to save petrol pump payment:", error);
      alert(t("petrolPumpPayments.messages.saveFailed"));
    } finally {
      saveInProgressRef.current = false;
      setIsSaving(false);
    }
  }

  function handleEdit(row: PetrolPumpPaymentRow) {
    setEditingId(row.id);
    setPaymentDate(row.paymentDate);
    setPetrolPumpId(row.petrolPumpId);
    setAdvanceUsed(String(row.advanceUsed));
    setPaymentNow(String(row.paymentNow));
    setPaymentMethod(row.paymentMethod);
    setReferenceNo(row.referenceNo === "-" ? "" : row.referenceNo);
    setRemarks(row.remarks === "-" ? "" : row.remarks);
  }

  async function handleDelete(row: PetrolPumpPaymentRow) {
    if (deleteInProgressRef.current) return;
    const confirmed = window.confirm(
      `${t("petrolPumpPayments.messages.deleteConfirm")} ${row.pumpName} (${formatAmount(row.amount)})?`
    );

    if (!confirmed) return;

    deleteInProgressRef.current = true;
    setIsDeleting(true);

    try {
      const { error } = await supabase.rpc("delete_petrol_pump_payment", {
        p_payment_id: row.id,
      });

      if (error) {
        const deleteError = error as DeleteRpcError;
        console.error("Failed to delete petrol pump payment:", {
          code: deleteError.code,
          message: deleteError.message,
        });
        alert(t(getDeleteFailureKey(deleteError)));
        return;
      }

      if (editingId === row.id) resetForm();

      alert(t("petrolPumpPayments.messages.deleted"));
      await Promise.all([loadPayments(), loadDieselEntries()]);
    } catch (error) {
      console.error("Failed to delete petrol pump payment:", error);
      alert(t("petrolPumpPayments.messages.deleteFailed"));
    } finally {
      deleteInProgressRef.current = false;
      setIsDeleting(false);
    }
  }

  const canCorrectManualDieselPayments = profileActive &&
    (profileRole === "adda_admin" || profileRole === "super_admin") &&
    Boolean(addaId) && correctionSetupState === "ready";

  async function handleManualDieselCorrection(input: {
    action: "void" | "replace";
    reason: string;
    replacementDate?: string;
    replacementAmount?: string;
    replacementMethod?: string;
    replacementReference?: string;
    replacementRemarks?: string;
  }) {
    if (correctionInProgressRef.current || !selectedCorrection || !addaId || !canCorrectManualDieselPayments) return;
    let payload;
    try {
      payload = buildManualDieselCorrectionRpcPayload({
        paymentId: selectedCorrection.paymentId,
        addaId,
        requestId: window.crypto.randomUUID(),
        ...input,
      });
    } catch (error) {
      const key = error instanceof Error ? error.message : "replacement_details_required";
      const knownKey = ["payment_id_invalid", "context_required", "reason_required", "replacement_details_required", "replacement_amount_invalid"].includes(key)
        ? key
        : "failed";
      alert(t(`petrolPumpPayments.correction.errors.${knownKey}`));
      return;
    }

    correctionInProgressRef.current = true;
    setIsCorrecting(true);
    try {
      const { error } = await supabase.rpc("correct_manual_voucher_diesel_payment", payload);
      if (error) {
        console.error("Manual Voucher Diesel payment correction failed:", { code: error.code, message: error.message });
        const specificKey = getCorrectionErrorKey(error);
        alert(specificKey
          ? t(`petrolPumpPayments.correction.errors.${specificKey}`)
          : t("petrolPumpPayments.correction.failed"));
        return;
      }
      setSelectedCorrection(null);
      publishManualDieselPaymentCorrection();
      await Promise.all([loadPayments(), loadDieselEntries(), loadManualDieselCorrectionData()]);
      alert(t("petrolPumpPayments.correction.success"));
    } catch (error) {
      console.error("Manual Voucher Diesel payment correction request failed:", error);
      alert(t("petrolPumpPayments.correction.failed"));
    } finally {
      correctionInProgressRef.current = false;
      setIsCorrecting(false);
    }
  }

  function selectCorrectionAdda(nextAddaId: string) {
    setSelectedCorrection(null);
    setManualDieselLinks([]);
    setCorrectionHistory([]);
    setCorrectionLoadError("");
    setAddaId(nextAddaId || null);
  }

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="payment" accent="green" title={t("petrolPumpPayments.title")} description={t("petrolPumpPayments.description")} />
        {profileRole === "super_admin" && (
          <label className="mt-4 block max-w-xl text-sm font-bold text-slate-800">
            {t("petrolPumpPayments.correction.selectAdda")}
            <select value={addaId ?? ""} onChange={(event) => selectCorrectionAdda(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 bg-white p-3">
              <option value="">{t("petrolPumpPayments.correction.selectAddaPlaceholder")}</option>
              {addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}
            </select>
          </label>
        )}
      </header>

      <PetrolPumpPaymentForm
        paymentDate={paymentDate}
        setPaymentDate={setPaymentDate}
        petrolPumpId={petrolPumpId}
        setPetrolPumpId={setPetrolPumpId}
        advanceUsed={advanceUsed}
        setAdvanceUsed={setAdvanceUsed}
        paymentNow={paymentNow}
        setPaymentNow={setPaymentNow}
        paymentMethod={paymentMethod}
        setPaymentMethod={setPaymentMethod}
        referenceNo={referenceNo}
        setReferenceNo={setReferenceNo}
        remarks={remarks}
        setRemarks={setRemarks}
        pumps={pumps}
        selectedPump={selectedPump}
        editingPayment={
          editingId
            ? paymentRows.find((row) => row.id === editingId) ?? null
            : null
        }
        onSave={handleSave}
        isSaving={isSaving}
        isEditing={Boolean(editingId)}
        onCancelEdit={resetForm}
      />

      <PetrolPumpPaymentTable
        rows={filteredRows}
        addaId={addaId}
        search={search}
        setSearch={setSearch}
        onEdit={handleEdit}
        onDelete={handleDelete}
        isDeleting={isDeleting}
        isLoading={isLoading}
        errorMessage={errorMessage}
        pumps={pumps}
        manualDieselLinks={manualDieselLinks}
        correctionHistory={correctionHistory}
        correctionSetupState={correctionSetupState}
        correctionLoadError={correctionLoadError}
        canCorrectManualDieselPayments={canCorrectManualDieselPayments}
        onCorrectManualDieselPayment={setSelectedCorrection}
      />
      {selectedCorrection && (
        <ManualDieselPaymentCorrectionModal
          payment={selectedCorrection}
          isSaving={isCorrecting}
          onCancel={() => setSelectedCorrection(null)}
          onSubmit={(input) => void handleManualDieselCorrection(input)}
        />
      )}
    </div>
  );
}

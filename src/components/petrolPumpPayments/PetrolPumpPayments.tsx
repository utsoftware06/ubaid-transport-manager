"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import PetrolPumpPaymentForm from "@/components/petrolPumpPayments/PetrolPumpPaymentForm";
import PetrolPumpPaymentTable from "@/components/petrolPumpPayments/PetrolPumpPaymentTable";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

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
  const [search, setSearch] = useState("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const saveInProgressRef = useRef(false);
  const deleteInProgressRef = useRef(false);

  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const { data: profile } = await supabase.from("profiles").select("adda_id,is_active").eq("id", data.user.id).maybeSingle();
      if (active && profile?.is_active && profile.adda_id) setAddaId(String(profile.adda_id));
    });
    return () => { active = false; };
  }, []);

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

      if (error) throw new Error(error.message);

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

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="payment" accent="green" title={t("petrolPumpPayments.title")} description={t("petrolPumpPayments.description")} />
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
      />
    </div>
  );
}

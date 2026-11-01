"use client";

import { useEffect, useEffectEvent, useRef, useState } from "react";
import PaymentReceiptForm from "@/components/paymentReceipts/PaymentReceiptForm";
import PaymentReceiptTable from "@/components/paymentReceipts/PaymentReceiptTable";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import type {
  PaymentReceiptLoading,
  PaymentReceiptRecord,
} from "@/types/paymentReceipts";

type ProfileRow = { adda_id: string | null };

function getSingleRelation<T>(relation: T | T[] | null | undefined): T | null {
  return Array.isArray(relation) ? relation[0] ?? null : relation ?? null;
}

function toNumber(value: number | string | null | undefined) {
  const number = Number(value ?? 0);
  return Number.isFinite(number) ? number : 0;
}

export default function PaymentReceipts() {
  const { t, dir } = useLanguage();
  const [receiptNo, setReceiptNo] = useState("");
  const [receiptDate, setReceiptDate] = useState("");
  const [loadingId, setLoadingId] = useState("");
  const [amount, setAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("Cash");
  const [remarks, setRemarks] = useState("");
  const [loadings, setLoadings] = useState<PaymentReceiptLoading[]>([]);
  const [receipts, setReceipts] = useState<PaymentReceiptRecord[]>([]);
  const [addaId, setAddaId] = useState<string | null>(null);
  const [editingReceipt, setEditingReceipt] =
    useState<PaymentReceiptRecord | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState("");
  const saveInProgressRef = useRef(false);
  const deleteInProgressRef = useRef(false);

  async function loadTenantData() {
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) throw authError ?? new Error("No user.");
    const { data: profileData, error: profileError } = await supabase
      .from("profiles")
      .select("adda_id")
      .eq("id", authData.user.id)
      .maybeSingle();
    const profile = profileData as ProfileRow | null;
    if (profileError || !profile?.adda_id) {
      throw profileError ?? new Error("No Adda.");
    }
    setAddaId(profile.adda_id);

    const { data: bookingData, error: bookingError } = await supabase
      .from("bookings")
      .select("id")
      .eq("adda_id", profile.adda_id);
    if (bookingError) throw bookingError;
    const bookingIds = (bookingData ?? []).map((booking) => String(booking.id));
    if (bookingIds.length === 0) {
      setLoadings([]);
      setReceipts([]);
      return;
    }

    const { data: loadingData, error: loadingError } = await supabase
      .from("loadings")
      .select(
        "id, loading_no, loading_date, advance_amount, remaining_amount, payment_status, booking_id, bookings(booking_no, sender_name, freight, parties(name))"
      )
      .in("booking_id", bookingIds)
      .order("loading_date", { ascending: false });
    if (loadingError) throw loadingError;
    const tenantLoadings = (loadingData ?? []).map((loading) => {
      const booking = getSingleRelation(loading.bookings);
      return {
        id: Number(loading.id),
        loading_no: loading.loading_no,
        loading_date: loading.loading_date,
        advance_amount: loading.advance_amount,
        remaining_amount: loading.remaining_amount,
        payment_status: loading.payment_status,
        bookings: booking
          ? {
              ...booking,
              parties: getSingleRelation(booking.parties),
            }
          : null,
      } as PaymentReceiptLoading;
    });
    setLoadings(tenantLoadings);

    const loadingIds = tenantLoadings.map((loading) => loading.id);
    if (loadingIds.length === 0) {
      setReceipts([]);
      return;
    }
    const { data: receiptData, error: receiptError } = await supabase
      .from("payment_receipts")
      .select(
        "id, receipt_no, receipt_date, loading_id, amount, payment_method, remarks, created_at, loadings(id, loading_no, advance_amount, remaining_amount, payment_status, bookings(booking_no, sender_name, freight, parties(name)))"
      )
      .in("loading_id", loadingIds)
      .order("receipt_date", { ascending: false })
      .order("created_at", { ascending: false });
    if (receiptError) throw receiptError;
    setReceipts(
      (receiptData ?? []).map((receipt) => {
        const loading = getSingleRelation(receipt.loadings);
        return {
          ...receipt,
          id: String(receipt.id),
          amount: toNumber(receipt.amount),
          loadings: loading
            ? {
                ...loading,
                bookings: (() => {
                  const booking = getSingleRelation(loading.bookings);
                  return booking
                    ? {
                        ...booking,
                        parties: getSingleRelation(booking.parties),
                      }
                    : null;
                })(),
              }
            : null,
        } as PaymentReceiptRecord;
      })
    );
  }

  const loadInitialData = useEffectEvent(async () => {
    setIsLoading(true);
    setErrorMessage("");
    try {
      await loadTenantData();
    } catch (error) {
      console.error("Unable to load payment receipts:", error);
      setErrorMessage(t("paymentReceipts.messages.loadFailed"));
    } finally {
      setIsLoading(false);
    }
  });

  useEffect(() => {
    const timer = window.setTimeout(() => void loadInitialData(), 0);
    return () => window.clearTimeout(timer);
  }, []);

  function resetForm() {
    setEditingReceipt(null);
    setReceiptNo("");
    setReceiptDate("");
    setLoadingId("");
    setAmount("");
    setPaymentMethod("Cash");
    setRemarks("");
  }

  function startEdit(receipt: PaymentReceiptRecord) {
    setEditingReceipt(receipt);
    setReceiptNo(receipt.receipt_no);
    setReceiptDate(receipt.receipt_date);
    setLoadingId(String(receipt.loading_id));
    setAmount(String(receipt.amount));
    setPaymentMethod(receipt.payment_method);
    setRemarks(receipt.remarks ?? "");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function handleSaveReceipt() {
    if (saveInProgressRef.current || isSaving) return;
    if (!receiptNo.trim()) return alert(t("paymentReceipts.validation.numberRequired"));
    if (!receiptDate) return alert(t("paymentReceipts.validation.dateRequired"));
    if (!loadingId) return alert(t("paymentReceipts.validation.loadingRequired"));
    const receivedAmount = Number(amount);
    if (!Number.isFinite(receivedAmount) || receivedAmount <= 0) {
      return alert(t("paymentReceipts.validation.amountPositive"));
    }
    const selectedLoading = loadings.find((loading) => String(loading.id) === loadingId);
    if (!selectedLoading) return alert(t("paymentReceipts.validation.loadingNotFound"));
    if (editingReceipt && String(editingReceipt.loading_id) !== loadingId) {
      return alert(t("paymentReceipts.validation.loadingCannotChange"));
    }

    const oldAmount = editingReceipt?.amount ?? 0;
    const delta = receivedAmount - oldAmount;
    const currentAdvance = toNumber(selectedLoading.advance_amount);
    const newAdvance = currentAdvance + delta;
    if (newAdvance < 0 || delta > toNumber(selectedLoading.remaining_amount)) {
      return alert(t("paymentReceipts.validation.exceedsRemaining"));
    }

    saveInProgressRef.current = true;
    setIsSaving(true);
    const values = {
      receipt_no: receiptNo.trim(),
      receipt_date: receiptDate,
      loading_id: Number(loadingId),
      amount: receivedAmount,
      payment_method: paymentMethod,
      remarks: remarks.trim(),
    };
    try {
      const receiptQuery = editingReceipt
        ? supabase
            .from("payment_receipts")
            .update(values)
            .eq("id", editingReceipt.id)
            .eq("loading_id", Number(loadingId))
        : supabase.from("payment_receipts").insert(values);
      const { error: receiptError } = await receiptQuery;
      if (receiptError) throw receiptError;

      alert(
        t(
          editingReceipt
            ? "paymentReceipts.messages.updated"
            : "paymentReceipts.messages.saved"
        )
      );
      resetForm();
      try {
        await loadTenantData();
      } catch (refreshError) {
        console.error(
          "Unable to refresh Payment Receipts after synchronized save:",
          refreshError
        );
        setErrorMessage(t("paymentReceipts.messages.loadFailed"));
      }
    } catch (error) {
      console.error("Unable to save synchronized Payment Receipt:", error);
      alert(t("paymentReceipts.messages.saveFailed"));
    } finally {
      saveInProgressRef.current = false;
      setIsSaving(false);
    }
  }

  async function handleDeleteReceipt(receipt: PaymentReceiptRecord) {
    if (
      deleteInProgressRef.current ||
      deletingId ||
      !window.confirm(t("paymentReceipts.messages.deleteConfirm"))
    ) {
      return;
    }
    deleteInProgressRef.current = true;
    setDeletingId(receipt.id);
    try {
      const { error: deleteError } = await supabase
        .from("payment_receipts")
        .delete()
        .eq("id", receipt.id)
        .eq("loading_id", receipt.loading_id);
      if (deleteError) throw deleteError;

      alert(t("paymentReceipts.messages.deleted"));
      if (editingReceipt?.id === receipt.id) resetForm();
      try {
        await loadTenantData();
      } catch (refreshError) {
        console.error(
          "Unable to refresh Payment Receipts after synchronized delete:",
          refreshError
        );
        setErrorMessage(t("paymentReceipts.messages.loadFailed"));
      }
    } catch (error) {
      console.error("Unable to delete synchronized Payment Receipt:", error);
      const code =
        typeof error === "object" &&
        error !== null &&
        "code" in error &&
        typeof error.code === "string"
          ? error.code
          : "";
      alert(
        t(
          code === "23503"
            ? "paymentReceipts.messages.linkedRecords"
            : "paymentReceipts.messages.deleteFailed"
        )
      );
    } finally {
      deleteInProgressRef.current = false;
      setDeletingId(null);
    }
  }

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="receipt" accent="green" title={t("paymentReceipts.history")} />
      </header>
      <PaymentReceiptForm
        receiptNo={receiptNo} setReceiptNo={setReceiptNo}
        receiptDate={receiptDate} setReceiptDate={setReceiptDate}
        loadingId={loadingId} setLoadingId={setLoadingId}
        amount={amount} setAmount={setAmount}
        paymentMethod={paymentMethod} setPaymentMethod={setPaymentMethod}
        remarks={remarks} setRemarks={setRemarks}
        loadings={loadings} onSave={handleSaveReceipt}
        onCancel={resetForm} isEditing={Boolean(editingReceipt)}
        lockLoading={Boolean(editingReceipt)} isSaving={isSaving}
      />
      <PaymentReceiptTable
        receipts={receipts}
        addaId={addaId}
        isLoading={isLoading}
        errorMessage={errorMessage}
        deletingId={deletingId}
        onEdit={startEdit}
        onDelete={handleDeleteReceipt}
      />
    </div>
  );
}

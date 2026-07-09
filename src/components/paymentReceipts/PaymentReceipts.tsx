"use client";

import { useEffect, useState } from "react";
import PaymentReceiptForm from "@/components/paymentReceipts/PaymentReceiptForm";
import PaymentReceiptTable from "@/components/paymentReceipts/PaymentReceiptTable";
import { supabase } from "@/lib/supabase/client";

type BookingRelation = {
  booking_no: string | null;
  sender_name: string | null;
  freight: number | string | null;
};

type LoadingRecord = {
  id: number;
  loading_no: string | null;
  loading_date: string | null;
  advance_amount: number | string | null;
  remaining_amount: number | string | null;
  payment_status: string | null;
  bookings: BookingRelation | BookingRelation[] | null;
};

type PaymentReceiptRecord = {
  id: string;
  receipt_no: string;
  receipt_date: string;
  loading_id: number;
  amount: number | string;
  payment_method: string;
  remarks: string | null;
  created_at?: string | null;
  loadings?: {
    loading_no: string | null;
    bookings?: BookingRelation | BookingRelation[] | null;
  } | null;
};

function getSingleRelation<T>(relation: T | T[] | null | undefined): T | null {
  if (Array.isArray(relation)) {
    return relation[0] ?? null;
  }

  return relation ?? null;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

export default function PaymentReceipts() {
  const [receiptNo, setReceiptNo] = useState("");
  const [receiptDate, setReceiptDate] = useState("");
  const [loadingId, setLoadingId] = useState("");
  const [amount, setAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("Cash");
  const [remarks, setRemarks] = useState("");
  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [receipts, setReceipts] = useState<PaymentReceiptRecord[]>([]);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    loadLoadings();
    loadReceipts();
  }, []);

  async function loadLoadings() {
    const { data, error } = await supabase
      .from("loadings")
      .select(
        `
        id,
        loading_no,
        loading_date,
        advance_amount,
        remaining_amount,
        payment_status,
        bookings(
          booking_no,
          sender_name,
          freight
        )
      `
      )
      .gt("remaining_amount", 0)
      .order("loading_date", { ascending: false });

    if (error) {
      alert(error.message);
      setLoadings([]);
      return;
    }

    setLoadings((data ?? []) as LoadingRecord[]);
  }

  async function loadReceipts() {
    const { data, error } = await supabase
      .from("payment_receipts")
      .select(
        `
        id,
        receipt_no,
        receipt_date,
        loading_id,
        amount,
        payment_method,
        remarks,
        created_at,
        loadings(
          loading_no,
          bookings(
            booking_no,
            sender_name,
            freight
          )
        )
      `
      )
      .order("receipt_date", { ascending: false });

    if (error) {
      alert(error.message);
      setReceipts([]);
      return;
    }

    setReceipts((data ?? []) as PaymentReceiptRecord[]);
  }

  function resetForm() {
    setReceiptNo("");
    setReceiptDate("");
    setLoadingId("");
    setAmount("");
    setPaymentMethod("Cash");
    setRemarks("");
  }

  function validateForm() {
    if (!receiptNo.trim()) {
      alert("Receipt No is required.");
      return false;
    }

    if (!receiptDate) {
      alert("Receipt Date is required.");
      return false;
    }

    if (!loadingId) {
      alert("Please select a loading.");
      return false;
    }

    if (!amount || Number(amount) <= 0) {
      alert("Amount must be greater than 0.");
      return false;
    }

    return true;
  }

  async function handleSaveReceipt() {
    if (!validateForm()) return;

    const selectedLoading = loadings.find(
      (loading) => String(loading.id) === loadingId
    );

    if (!selectedLoading) {
      alert("Selected loading was not found.");
      return;
    }

    const remainingAmount = Number(selectedLoading.remaining_amount ?? 0);
    const receivedAmount = Number(amount);

    if (remainingAmount <= 0) {
      alert("This loading is already fully paid.");
      return;
    }

    if (receivedAmount > remainingAmount) {
      alert("Receipt amount cannot be greater than remaining amount.");
      return;
    }

    const booking = getSingleRelation(selectedLoading.bookings);
    const freight = toNumber(booking?.freight);
    const currentAdvance = toNumber(selectedLoading.advance_amount);
    const newAdvance = currentAdvance + receivedAmount;
    const newRemaining = Math.max(freight - newAdvance, 0);

    let paymentStatus = "Unpaid";

    if (newAdvance <= 0) {
      paymentStatus = "Unpaid";
    } else if (newRemaining <= 0 || newAdvance >= freight) {
      paymentStatus = "Paid";
    } else {
      paymentStatus = "Partial";
    }

    setIsSaving(true);

    const { error: receiptError } = await supabase
      .from("payment_receipts")
      .insert({
        receipt_no: receiptNo.trim(),
        receipt_date: receiptDate,
        loading_id: Number(loadingId),
        amount: receivedAmount,
        payment_method: paymentMethod,
        remarks: remarks.trim(),
      });

    if (receiptError) {
      setIsSaving(false);
      alert(receiptError.message);
      return;
    }

    const { error: loadingError } = await supabase
      .from("loadings")
      .update({
        advance_amount: newAdvance,
        remaining_amount: newRemaining,
        payment_status: paymentStatus,
      })
      .eq("id", Number(loadingId));

    setIsSaving(false);

    if (loadingError) {
      alert(loadingError.message);
      return;
    }

    alert("Payment receipt saved successfully!");
    resetForm();
    await loadLoadings();
    await loadReceipts();
  }

  return (
    <div className="space-y-8">
      <PaymentReceiptForm
        receiptNo={receiptNo}
        setReceiptNo={setReceiptNo}
        receiptDate={receiptDate}
        setReceiptDate={setReceiptDate}
        loadingId={loadingId}
        setLoadingId={setLoadingId}
        amount={amount}
        setAmount={setAmount}
        paymentMethod={paymentMethod}
        setPaymentMethod={setPaymentMethod}
        remarks={remarks}
        setRemarks={setRemarks}
        loadings={loadings}
        onSave={handleSaveReceipt}
        isSaving={isSaving}
      />

      <PaymentReceiptTable receipts={receipts} />
    </div>
  );
}
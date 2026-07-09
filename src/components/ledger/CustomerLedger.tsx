"use client";

import { useEffect, useMemo, useState } from "react";
import CustomerLedgerCards from "./CustomerLedgerCards";
import CustomerLedgerTable from "./CustomerLedgerTable";
import { supabase } from "@/lib/supabase/client";

export type PaymentStatus = "Paid" | "Partial" | "Unpaid";

export type CustomerLedgerRow = {
  bookingId: string;
  loadingId: number | null;
  date: string;
  bookingNo: string;
  sender: string;
  receiver: string;
  route: string;
  freight: number;
  advanceAmount: number;
  receiptAmount: number;
  totalReceived: number;
  remainingAmount: number;
  paymentStatus: PaymentStatus;
};

export type CustomerLedgerSummary = {
  totalBookings: number;
  totalFreight: number;
  receivedAmount: number;
  pendingAmount: number;
};

type DatabaseRow = Record<string, unknown>;

type BookingRecord = {
  id: string;
  booking_no: string | null;
  booking_date: string | null;
  created_at: string | null;
  sender_name: string | null;
  receiver_name: string | null;
  route: string | null;
  freight: number;
};

type LoadingRecord = {
  id: number;
  booking_id: string | null;
  route: string | null;
  advance_amount: number;
  remaining_amount: number;
  payment_status: string | null;
};

type PaymentReceiptRecord = {
  id: number | string;
  loading_id: number | null;
  amount: number;
};

export function formatAmount(value: number) {
  return new Intl.NumberFormat("en-PK", {
    style: "currency",
    currency: "PKR",
    maximumFractionDigits: 0,
  })
    .format(Number(value || 0))
    .replace("PKR", "Rs.");
}

function toNumber(value: unknown) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function toStringValue(value: unknown) {
  return typeof value === "string" ? value : "";
}

function formatDate(value: string) {
  if (!value) return "-";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleDateString("en-PK", {
    year: "numeric",
    month: "short",
    day: "2-digit",
  });
}

function mapBooking(row: DatabaseRow): BookingRecord {
  return {
    id: String(row.id ?? ""),
    booking_no: toStringValue(row.booking_no) || null,
    booking_date: toStringValue(row.booking_date) || null,
    created_at: toStringValue(row.created_at) || null,
    sender_name: toStringValue(row.sender_name) || null,
    receiver_name: toStringValue(row.receiver_name) || null,
    route: toStringValue(row.route) || null,
    freight: toNumber(row.freight),
  };
}

function mapLoading(row: DatabaseRow): LoadingRecord {
  return {
    id: toNumber(row.id),
    booking_id: toStringValue(row.booking_id) || null,
    route: toStringValue(row.route) || null,
    advance_amount: toNumber(row.advance_amount),
    remaining_amount: toNumber(row.remaining_amount),
    payment_status: toStringValue(row.payment_status) || null,
  };
}

function mapPaymentReceipt(row: DatabaseRow): PaymentReceiptRecord {
  return {
    id: typeof row.id === "number" || typeof row.id === "string" ? row.id : "",
    loading_id: row.loading_id === null ? null : toNumber(row.loading_id),
    amount: toNumber(row.amount),
  };
}

function getPaymentStatus(totalReceived: number, remainingAmount: number) {
  if (remainingAmount <= 0) return "Paid";
  if (totalReceived > 0) return "Partial";
  return "Unpaid";
}

export default function CustomerLedger() {
  const [bookings, setBookings] = useState<BookingRecord[]>([]);
  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [paymentReceipts, setPaymentReceipts] = useState<
    PaymentReceiptRecord[]
  >([]);
  const [search, setSearch] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    loadCustomerLedger();
  }, []);

  async function loadCustomerLedger() {
    setIsLoading(true);
    setErrorMessage("");

    const [bookingsResult, loadingsResult, receiptsResult] = await Promise.all([
      supabase.from("bookings").select("*"),
      supabase.from("loadings").select("*"),
      supabase.from("payment_receipts").select("*"),
    ]);

    if (bookingsResult.error) {
      setErrorMessage(bookingsResult.error.message);
      setBookings([]);
      setLoadings([]);
      setPaymentReceipts([]);
      setIsLoading(false);
      return;
    }

    if (loadingsResult.error) {
      setErrorMessage(loadingsResult.error.message);
      setBookings([]);
      setLoadings([]);
      setPaymentReceipts([]);
      setIsLoading(false);
      return;
    }

    if (receiptsResult.error) {
      setErrorMessage(receiptsResult.error.message);
      setBookings([]);
      setLoadings([]);
      setPaymentReceipts([]);
      setIsLoading(false);
      return;
    }

    setBookings(((bookingsResult.data ?? []) as DatabaseRow[]).map(mapBooking));
    setLoadings(((loadingsResult.data ?? []) as DatabaseRow[]).map(mapLoading));
    setPaymentReceipts(
      ((receiptsResult.data ?? []) as DatabaseRow[]).map(mapPaymentReceipt)
    );
    setIsLoading(false);
  }

  const rows = useMemo<CustomerLedgerRow[]>(() => {
    return bookings.map((booking) => {
      const loading =
        loadings.find((item) => item.booking_id === booking.id) ?? null;

      const receiptAmount = loading
        ? paymentReceipts
            .filter((receipt) => receipt.loading_id === loading.id)
            .reduce((total, receipt) => total + receipt.amount, 0)
        : 0;

      const freight = booking.freight;
      const advanceAmount = loading?.advance_amount ?? 0;
      const totalReceived = advanceAmount + receiptAmount;
      const remainingAmount = Math.max(freight - totalReceived, 0);
      const paymentStatus = getPaymentStatus(totalReceived, remainingAmount);

      return {
        bookingId: booking.id,
        loadingId: loading?.id ?? null,
        date: formatDate(booking.booking_date ?? booking.created_at ?? ""),
        bookingNo: booking.booking_no ?? "-",
        sender: booking.sender_name ?? "-",
        receiver: booking.receiver_name ?? "-",
        route: loading?.route ?? booking.route ?? "-",
        freight,
        advanceAmount,
        receiptAmount,
        totalReceived,
        remainingAmount,
        paymentStatus,
      };
    });
  }, [bookings, loadings, paymentReceipts]);

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    if (!keyword) return rows;

    return rows.filter((row) => {
      const searchableText = [
        row.date,
        row.bookingNo,
        row.sender,
        row.receiver,
        row.route,
        String(row.freight),
        String(row.advanceAmount),
        String(row.receiptAmount),
        String(row.totalReceived),
        String(row.remainingAmount),
        row.paymentStatus,
      ]
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [rows, search]);

  const summary = useMemo<CustomerLedgerSummary>(() => {
    return filteredRows.reduce(
      (total, row) => ({
        totalBookings: total.totalBookings + 1,
        totalFreight: total.totalFreight + row.freight,
        receivedAmount: total.receivedAmount + row.totalReceived,
        pendingAmount: total.pendingAmount + row.remainingAmount,
      }),
      {
        totalBookings: 0,
        totalFreight: 0,
        receivedAmount: 0,
        pendingAmount: 0,
      }
    );
  }, [filteredRows]);

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">Customer Ledger</h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Track customer freight, received payments, pending balance and payment
          status.
        </p>
      </div>

      <CustomerLedgerCards summary={summary} />

      <CustomerLedgerTable
        rows={filteredRows}
        search={search}
        setSearch={setSearch}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}
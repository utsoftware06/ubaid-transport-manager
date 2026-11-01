"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import CustomerLedgerCards from "./CustomerLedgerCards";
import CustomerLedgerTable from "./CustomerLedgerTable";
import CustomerLedgerFilters from "./CustomerLedgerFilters";
import type {
  CustomerLedgerFilterValues,
  SenderOption,
} from "@/types/customerLedger";
import { useLanguage } from "@/contexts/LanguageContext";
import { supabase } from "@/lib/supabase/client";
import ModulePageHeading from "@/components/shared/ModulePageHeading";

export type PaymentStatus = "Paid" | "Partial" | "Unpaid";

export type CustomerLedgerRow = {
  bookingId: string;
  addaId: string | null;
  loadingId: number | null;
  rawDate: string;
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
  adda_id: string | null;
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

export const formatCurrency = (value: number) =>
  `₨ ${Math.round(value).toLocaleString("en-PK")}`;

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
    adda_id: toStringValue(row.adda_id) || null,
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
  const { t, dir } = useLanguage();

  useEffect(() => {
    if (process.env.NODE_ENV === "development") {
      console.info(
        "[CustomerLedger] rendered from src/components/ledger/CustomerLedger.tsx"
      );
    }
  }, []);

  const [bookings, setBookings] = useState<BookingRecord[]>([]);
  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [paymentReceipts, setPaymentReceipts] = useState<
    PaymentReceiptRecord[]
  >([]);
  const emptyFilters: CustomerLedgerFilterValues = {
    senderName: "",
    fromDate: "",
    toDate: "",
    search: "",
  };
  const [filterValues, setFilterValues] =
    useState<CustomerLedgerFilterValues>(emptyFilters);
  const [appliedFilters, setAppliedFilters] =
    useState<CustomerLedgerFilterValues>(emptyFilters);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  const loadCustomerLedger = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage("");

    const [bookingsResult, loadingsResult, receiptsResult] = await Promise.all([
      supabase.from("bookings").select("*"),
      supabase.from("loadings").select("*"),
      supabase.from("payment_receipts").select("*"),
    ]);

    if (bookingsResult.error) {
      console.error("Unable to load customer ledger bookings:", bookingsResult.error);
      setErrorMessage(t("customerLedger.messages.loadError"));
      setBookings([]);
      setLoadings([]);
      setPaymentReceipts([]);
      setIsLoading(false);
      return;
    }

    if (loadingsResult.error) {
      console.error("Unable to load customer ledger loadings:", loadingsResult.error);
      setErrorMessage(t("customerLedger.messages.loadError"));
      setBookings([]);
      setLoadings([]);
      setPaymentReceipts([]);
      setIsLoading(false);
      return;
    }

    if (receiptsResult.error) {
      console.error("Unable to load customer ledger receipts:", receiptsResult.error);
      setErrorMessage(t("customerLedger.messages.loadError"));
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
  }, [t]);

  useEffect(() => {
    const loadTimer = window.setTimeout(() => {
      void loadCustomerLedger();
    }, 0);

    return () => window.clearTimeout(loadTimer);
  }, [loadCustomerLedger]);

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
        addaId: booking.adda_id,
        loadingId: loading?.id ?? null,
        rawDate: (booking.booking_date ?? booking.created_at ?? "").slice(0, 10),
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
    const keyword = appliedFilters.search.trim().toLowerCase();

    return rows.filter((row) => {
      if (
        appliedFilters.senderName &&
        row.sender !== appliedFilters.senderName
      ) {
        return false;
      }
      if (appliedFilters.fromDate && row.rawDate < appliedFilters.fromDate) {
        return false;
      }
      if (appliedFilters.toDate && row.rawDate > appliedFilters.toDate) {
        return false;
      }
      if (!keyword) return true;
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
  }, [appliedFilters, rows]);

  const senders = useMemo<SenderOption[]>(() => {
    return Array.from(
      new Set(rows.map((row) => row.sender).filter((name) => name !== "-"))
    )
      .sort((first, second) => first.localeCompare(second))
      .map((name) => ({ name }));
  }, [rows]);

  function handleSearch() {
    if (
      filterValues.fromDate &&
      filterValues.toDate &&
      filterValues.fromDate > filterValues.toDate
    ) {
      window.alert(t("reports.validation.invalidDateRange"));
      return;
    }
    setAppliedFilters({
      ...filterValues,
      search: filterValues.search.trim(),
    });
  }

  function handleReset() {
    setFilterValues(emptyFilters);
    setAppliedFilters(emptyFilters);
  }

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
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="ledger" accent="purple" title={t("customerLedger.title")} description={t("customerLedger.pageDescription")} />
      </header>

      <CustomerLedgerCards summary={summary} />

      <CustomerLedgerFilters
        senders={senders}
        filterValues={filterValues}
        setFilterValues={setFilterValues}
        onSearch={handleSearch}
        onReset={handleReset}
      />

      <CustomerLedgerTable
        key={`${appliedFilters.senderName}|${appliedFilters.fromDate}|${appliedFilters.toDate}|${appliedFilters.search}`}
        rows={filteredRows}
        summary={summary}
        fromDate={appliedFilters.fromDate}
        toDate={appliedFilters.toDate}
        isLoading={isLoading}
        errorMessage={errorMessage}
      />
    </div>
  );
}

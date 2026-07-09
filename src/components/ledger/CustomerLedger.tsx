"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";

import CustomerLedgerCards from "./CustomerLedgerCards";
import CustomerLedgerFilters from "./CustomerLedgerFilters";
import CustomerLedgerTable from "./CustomerLedgerTable";

export type SenderOption = {
  name: string;
};

export type CustomerLedgerFilterValues = {
  senderName: string;
  fromDate: string;
  toDate: string;
  search: string;
};

export type CustomerLedgerRow = {
  id: string;
  bookingNo: string;
  bookingDate: string;
  senderName: string;
  receiverName: string;
  route: string;
  goodsName: string;
  quantity: number;
  weight: number;
  freight: number;
  status: string;
};

export type CustomerLedgerSummary = {
  totalBookings: number;
  totalFreight: number;
  receivedAmount: number;
  pendingAmount: number;
};

type BookingRecord = {
  id: string;
  booking_no: string | null;
  booking_date: string | null;
  sender_name: string | null;
  receiver_name: string | null;
  from_city: string | null;
  to_city: string | null;
  goods_name: string | null;
  quantity: number | string | null;
  weight: number | string | null;
  freight: number | string | null;
  status: string | null;
};

const emptyFilters: CustomerLedgerFilterValues = {
  senderName: "",
  fromDate: "",
  toDate: "",
  search: "",
};

function toNumber(value: number | string | null | undefined): number {
  const parsedValue = Number(value ?? 0);
  return Number.isFinite(parsedValue) ? parsedValue : 0;
}

export default function CustomerLedger() {
  const [bookings, setBookings] = useState<BookingRecord[]>([]);
  const [filterValues, setFilterValues] =
    useState<CustomerLedgerFilterValues>(emptyFilters);
  const [appliedFilters, setAppliedFilters] =
    useState<CustomerLedgerFilterValues>(emptyFilters);

  const [loading, setLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let isMounted = true;

    async function loadCustomerLedger() {
      setLoading(true);
      setErrorMessage("");

      const { data, error } = await supabase
        .from("bookings")
        .select(
          `
          id,
          booking_no,
          booking_date,
          sender_name,
          receiver_name,
          from_city,
          to_city,
          goods_name,
          quantity,
          weight,
          freight,
          status
        `
        )
        .order("booking_date", { ascending: false });

      if (!isMounted) return;

      if (error) {
        setBookings([]);
        setErrorMessage(error.message);
        setLoading(false);
        return;
      }

      setBookings((data ?? []) as BookingRecord[]);
      setLoading(false);
    }

    void loadCustomerLedger();

    return () => {
      isMounted = false;
    };
  }, []);

  const senders = useMemo<SenderOption[]>(() => {
    const senderSet = new Set<string>();

    bookings.forEach((booking) => {
      const senderName = booking.sender_name?.trim();
      if (senderName) senderSet.add(senderName);
    });

    return Array.from(senderSet)
      .sort((a, b) => a.localeCompare(b))
      .map((name) => ({ name }));
  }, [bookings]);

  const rows = useMemo<CustomerLedgerRow[]>(() => {
    return bookings.map((booking) => ({
      id: booking.id,
      bookingNo: booking.booking_no ?? booking.id,
      bookingDate: booking.booking_date?.slice(0, 10) ?? "-",
      senderName: booking.sender_name ?? "-",
      receiverName: booking.receiver_name ?? "-",
      route: `${booking.from_city ?? "-"} → ${booking.to_city ?? "-"}`,
      goodsName: booking.goods_name ?? "-",
      quantity: toNumber(booking.quantity),
      weight: toNumber(booking.weight),
      freight: toNumber(booking.freight),
      status: booking.status ?? "-",
    }));
  }, [bookings]);

  const filteredRows = useMemo(() => {
    return rows.filter((row) => {
      if (
        appliedFilters.senderName &&
        row.senderName !== appliedFilters.senderName
      ) {
        return false;
      }

      if (
        appliedFilters.fromDate &&
        row.bookingDate !== "-" &&
        row.bookingDate < appliedFilters.fromDate
      ) {
        return false;
      }

      if (
        appliedFilters.toDate &&
        row.bookingDate !== "-" &&
        row.bookingDate > appliedFilters.toDate
      ) {
        return false;
      }

      const searchText = appliedFilters.search.trim().toLowerCase();

      if (searchText) {
        const combinedText = `
          ${row.bookingNo}
          ${row.senderName}
          ${row.receiverName}
          ${row.route}
          ${row.goodsName}
          ${row.status}
        `.toLowerCase();

        if (!combinedText.includes(searchText)) return false;
      }

      return true;
    });
  }, [rows, appliedFilters]);

  const summary = useMemo<CustomerLedgerSummary>(() => {
    const totalFreight = filteredRows.reduce(
      (sum, row) => sum + row.freight,
      0
    );

    return {
      totalBookings: filteredRows.length,
      totalFreight,
      receivedAmount: totalFreight,
      pendingAmount: 0,
    };
  }, [filteredRows]);

  function handleSearch() {
    setAppliedFilters(filterValues);
  }

  function handleReset() {
    setFilterValues(emptyFilters);
    setAppliedFilters(emptyFilters);
  }

  return (
    <div className="space-y-6">
      <CustomerLedgerFilters
        senders={senders}
        filterValues={filterValues}
        setFilterValues={setFilterValues}
        onSearch={handleSearch}
        onReset={handleReset}
      />

      <CustomerLedgerCards summary={summary} />

      {errorMessage ? (
        <div className="rounded-xl border border-red-200 bg-red-50 p-6 text-red-700 shadow-md">
          <p className="font-bold">Unable to load Customer Ledger.</p>
          <p className="mt-1 text-sm font-medium">{errorMessage}</p>
        </div>
      ) : (
        <CustomerLedgerTable loading={loading} rows={filteredRows} />
      )}
    </div>
  );
}
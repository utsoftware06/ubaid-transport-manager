"use client";

import { useEffect, useMemo, useState } from "react";
import TripCards from "@/components/trip-management/TripCards";
import TripDetailsModal from "@/components/trip-management/TripDetailsModal";
import TripFilters from "@/components/trip-management/TripFilters";
import TripForm from "@/components/trip-management/TripForm";
import TripPrint from "@/components/trip-management/TripPrint";
import TripTable from "@/components/trip-management/TripTable";
import { supabase } from "@/lib/supabase/client";

export type TripStatus =
  | "Planned"
  | "Loading"
  | "In Transit"
  | "Delivered"
  | "Completed"
  | "Cancelled";

export const TRIP_STATUSES: TripStatus[] = [
  "Planned",
  "Loading",
  "In Transit",
  "Delivered",
  "Completed",
  "Cancelled",
];

export type TripDateFilter =
  | "all"
  | "today"
  | "last7Days"
  | "thisMonth"
  | "last6Months"
  | "thisYear"
  | "custom";

export type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

export type DriverOption = {
  id: string;
  name: string;
};

export type BookingOption = {
  id: string;
  customerName: string;
  customerPhone: string;
  loadingFrom: string;
  deliveryTo: string;
  goodsDescription: string;
  freightAmount: number;
};

export type TripRecord = {
  id: string;
  adda_id: string | null;
  vehicle_id: string;
  driver_id: string | null;
  booking_id: string | null;
  trip_no: string;
  trip_date: string;
  customer_name: string | null;
  customer_phone: string | null;
  loading_from: string;
  delivery_to: string;
  goods_description: string | null;
  freight_amount: number;
  customer_advance: number;
  driver_advance: number;
  total_expense: number;
  received_amount: number;
  payment_balance: number;
  net_profit: number;
  trip_status: TripStatus;
  start_date: string | null;
  completion_date: string | null;
  remarks: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  vehicleNo: string;
  ownerName: string;
  driverName: string;
  bookingCustomerName: string;
};

export type TripPayload = {
  vehicle_id: string;
  driver_id: string | null;
  booking_id: string | null;
  trip_no: string;
  trip_date: string;
  customer_name: string | null;
  customer_phone: string | null;
  loading_from: string;
  delivery_to: string;
  goods_description: string | null;
  freight_amount: number;
  customer_advance: number;
  driver_advance: number;
  total_expense: number;
  received_amount: number;
  trip_status: TripStatus;
  start_date: string | null;
  completion_date: string | null;
  remarks: string | null;
};

export type TripSummary = {
  totalTrips: number;
  plannedTrips: number;
  activeTrips: number;
  completedTrips: number;
  cancelledTrips: number;
  totalFreight: number;
  totalReceived: number;
  totalBalance: number;
  totalExpenses: number;
  totalProfit: number;
};

type CurrentContext = {
  userId: string;
  addaId: string;
};

type VehicleRelation = {
  vehicle_no: string | null;
  owner_name: string | null;
};

type DriverRelation = {
  name: string | null;
};

type BookingRelation = {
  sender_name: string | null;
};

type RelationValue<T> = T | T[] | null;

type TripDbRow = {
  id: string;
  adda_id: string | null;
  vehicle_id: string;
  driver_id: string | null;
  booking_id: string | null;
  trip_no: string | null;
  trip_date: string | null;
  customer_name: string | null;
  customer_phone: string | null;
  loading_from: string | null;
  delivery_to: string | null;
  goods_description: string | null;
  freight_amount: number | string | null;
  customer_advance: number | string | null;
  driver_advance: number | string | null;
  total_expense: number | string | null;
  received_amount: number | string | null;
  payment_balance: number | string | null;
  net_profit: number | string | null;
  trip_status: string | null;
  start_date: string | null;
  completion_date: string | null;
  remarks: string | null;
  created_by: string | null;
  created_at: string | null;
  updated_at: string | null;
  vehicles?: RelationValue<VehicleRelation>;
  drivers?: RelationValue<DriverRelation>;
  bookings?: RelationValue<BookingRelation>;
};

type VehicleDbRow = {
  id: string;
  vehicle_no: string | null;
  owner_name: string | null;
};

type DriverDbRow = {
  id: string;
  name: string | null;
};

type BookingDbRow = {
  id: string;
  sender_name: string | null;
  sender_phone: string | null;
  from_city: string | null;
  to_city: string | null;
  goods_name: string | null;
  freight: number | string | null;
};

type ProfileRow = {
  adda_id: string | null;
};

export function formatAmount(value: number) {
  return `Rs. ${Math.round(Number(value || 0)).toLocaleString("en-PK")}`;
}

function toNumber(value: number | string | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function readRelation<T>(value: RelationValue<T> | undefined) {
  if (!value) return null;
  return Array.isArray(value) ? value[0] ?? null : value;
}

function toTripStatus(value: string | null): TripStatus {
  return TRIP_STATUSES.includes(value as TripStatus)
    ? (value as TripStatus)
    : "Planned";
}

function getTodayDate() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date;
}

function parseLocalDate(value: string) {
  const date = new Date(`${value}T00:00:00`);
  date.setHours(0, 0, 0, 0);
  return date;
}

function isTripInDateFilter(
  tripDate: string,
  filter: TripDateFilter,
  fromDate: string,
  toDate: string
) {
  if (!tripDate || filter === "all") return true;

  const date = parseLocalDate(tripDate);
  const today = getTodayDate();

  if (Number.isNaN(date.getTime())) return false;

  if (filter === "today") {
    return date.getTime() === today.getTime();
  }

  if (filter === "last7Days") {
    const start = new Date(today);
    start.setDate(start.getDate() - 6);
    return date >= start && date <= today;
  }

  if (filter === "thisMonth") {
    return (
      date.getFullYear() === today.getFullYear() &&
      date.getMonth() === today.getMonth()
    );
  }

  if (filter === "last6Months") {
    const start = new Date(today);
    start.setMonth(start.getMonth() - 6);
    return date >= start && date <= today;
  }

  if (filter === "thisYear") {
    return date.getFullYear() === today.getFullYear();
  }

  if (filter === "custom") {
    if (fromDate && date < parseLocalDate(fromDate)) return false;
    if (toDate && date > parseLocalDate(toDate)) return false;
    return true;
  }

  return true;
}

export default function TripManagement() {
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [drivers, setDrivers] = useState<DriverOption[]>([]);
  const [bookings, setBookings] = useState<BookingOption[]>([]);
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [currentAddaId, setCurrentAddaId] = useState<string | null>(null);

  const [selectedTrip, setSelectedTrip] = useState<TripRecord | null>(null);
  const [viewingTrip, setViewingTrip] = useState<TripRecord | null>(null);

  const [search, setSearch] = useState("");
  const [selectedVehicle, setSelectedVehicle] = useState("");
  const [selectedDriver, setSelectedDriver] = useState("");
  const [selectedStatus, setSelectedStatus] = useState("");
  const [selectedTripDateFilter, setSelectedTripDateFilter] =
    useState<TripDateFilter>("all");
  const [customFromDate, setCustomFromDate] = useState("");
  const [customToDate, setCustomToDate] = useState("");

  const filteredTrips = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    return trips.filter((trip) => {
      if (selectedVehicle && trip.vehicle_id !== selectedVehicle) return false;
      if (selectedDriver && trip.driver_id !== selectedDriver) return false;
      if (selectedStatus && trip.trip_status !== selectedStatus) return false;

      if (
        !isTripInDateFilter(
          trip.trip_date,
          selectedTripDateFilter,
          customFromDate,
          customToDate
        )
      ) {
        return false;
      }

      if (!keyword) return true;

      const searchableText = [
        trip.trip_no,
        trip.vehicleNo,
        trip.ownerName,
        trip.driverName,
        trip.customer_name ?? "",
        trip.customer_phone ?? "",
        trip.loading_from,
        trip.delivery_to,
        trip.goods_description ?? "",
      ]
        .join(" ")
        .toLowerCase();

      return searchableText.includes(keyword);
    });
  }, [
    customFromDate,
    customToDate,
    search,
    selectedDriver,
    selectedStatus,
    selectedTripDateFilter,
    selectedVehicle,
    trips,
  ]);

  const summary = useMemo<TripSummary>(() => {
    return filteredTrips.reduce(
      (total, trip) => {
        total.totalTrips += 1;
        total.totalFreight += trip.freight_amount;
        total.totalReceived += trip.received_amount;
        total.totalBalance += trip.payment_balance;
        total.totalExpenses += trip.total_expense;
        total.totalProfit += trip.net_profit;

        if (trip.trip_status === "Planned") total.plannedTrips += 1;

        if (
          trip.trip_status === "Loading" ||
          trip.trip_status === "In Transit" ||
          trip.trip_status === "Delivered"
        ) {
          total.activeTrips += 1;
        }

        if (trip.trip_status === "Completed") total.completedTrips += 1;
        if (trip.trip_status === "Cancelled") total.cancelledTrips += 1;

        return total;
      },
      {
        totalTrips: 0,
        plannedTrips: 0,
        activeTrips: 0,
        completedTrips: 0,
        cancelledTrips: 0,
        totalFreight: 0,
        totalReceived: 0,
        totalBalance: 0,
        totalExpenses: 0,
        totalProfit: 0,
      }
    );
  }, [filteredTrips]);

  useEffect(() => {
    refreshTrips();
  }, []);

  async function loadCurrentContext(): Promise<CurrentContext> {
    const { data: userData, error: authError } = await supabase.auth.getUser();

    if (authError) {
      throw new Error(authError.message || "Unable to verify current user.");
    }

    const userId = userData.user?.id;

    if (!userId) {
      throw new Error("No authenticated user found. Please log in again.");
    }

    const { data: profileData, error: profileError } = await supabase
      .from("profiles")
      .select("adda_id")
      .eq("id", userId)
      .maybeSingle();

    if (profileError) {
      throw new Error(profileError.message || "Unable to load user profile.");
    }

    const profile = profileData as ProfileRow | null;
    const addaId = profile?.adda_id;

    if (!addaId) {
      throw new Error("No adda is assigned to the current user.");
    }

    setCurrentUserId(userId);
    setCurrentAddaId(addaId);

    return {
      userId,
      addaId,
    };
  }

  async function loadVehicles(addaId: string) {
    const { data, error: vehiclesError } = await supabase
      .from("vehicles")
      .select("id, vehicle_no, owner_name")
      .eq("adda_id", addaId)
      .order("vehicle_no", { ascending: true });

    if (vehiclesError) {
      throw new Error(vehiclesError.message || "Unable to load vehicles.");
    }

    const rows = (data ?? []) as VehicleDbRow[];

    setVehicles(
      rows.map((vehicle) => ({
        id: vehicle.id,
        vehicleNo: vehicle.vehicle_no ?? "",
        ownerName: vehicle.owner_name ?? "",
      }))
    );
  }

  async function loadDrivers(addaId: string) {
    const { data, error: driversError } = await supabase
      .from("drivers")
      .select("id, name")
      .eq("adda_id", addaId)
      .order("name", { ascending: true });

    if (driversError) {
      throw new Error(driversError.message || "Unable to load drivers.");
    }

    const rows = (data ?? []) as DriverDbRow[];

    setDrivers(
      rows.map((driver) => ({
        id: driver.id,
        name: driver.name ?? "",
      }))
    );
  }

  async function loadBookings(addaId: string) {
    const { data, error: bookingsError } = await supabase
      .from("bookings")
      .select(
        "id, sender_name, sender_phone, from_city, to_city, goods_name, freight"
      )
      .eq("adda_id", addaId)
      .order("created_at", { ascending: false });

    if (bookingsError) {
      throw new Error(bookingsError.message || "Unable to load bookings.");
    }

    const rows = (data ?? []) as BookingDbRow[];

    setBookings(
      rows.map((booking) => ({
        id: booking.id,
        customerName: booking.sender_name ?? "",
        customerPhone: booking.sender_phone ?? "",
        loadingFrom: booking.from_city ?? "",
        deliveryTo: booking.to_city ?? "",
        goodsDescription: booking.goods_name ?? "",
        freightAmount: toNumber(booking.freight),
      }))
    );
  }

  async function loadTrips(addaId: string) {
    const { data, error: tripsError } = await supabase
      .from("trips")
      .select(
        `
        id,
        adda_id,
        vehicle_id,
        driver_id,
        booking_id,
        trip_no,
        trip_date,
        customer_name,
        customer_phone,
        loading_from,
        delivery_to,
        goods_description,
        freight_amount,
        customer_advance,
        driver_advance,
        total_expense,
        received_amount,
        payment_balance,
        net_profit,
        trip_status,
        start_date,
        completion_date,
        remarks,
        created_by,
        created_at,
        updated_at,
        vehicles(vehicle_no, owner_name),
        drivers(name),
        bookings(sender_name)
      `
      )
      .eq("adda_id", addaId)
      .order("trip_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (tripsError) {
      throw new Error(tripsError.message || "Unable to load trips.");
    }

    const rows = (data ?? []) as TripDbRow[];

    setTrips(
      rows.map((trip) => {
        const vehicle = readRelation(trip.vehicles);
        const driver = readRelation(trip.drivers);
        const booking = readRelation(trip.bookings);

        return {
          id: trip.id,
          adda_id: trip.adda_id,
          vehicle_id: trip.vehicle_id,
          driver_id: trip.driver_id,
          booking_id: trip.booking_id,
          trip_no: trip.trip_no ?? "",
          trip_date: trip.trip_date ?? "",
          customer_name: trip.customer_name,
          customer_phone: trip.customer_phone,
          loading_from: trip.loading_from ?? "",
          delivery_to: trip.delivery_to ?? "",
          goods_description: trip.goods_description,
          freight_amount: toNumber(trip.freight_amount),
          customer_advance: toNumber(trip.customer_advance),
          driver_advance: toNumber(trip.driver_advance),
          total_expense: toNumber(trip.total_expense),
          received_amount: toNumber(trip.received_amount),
          payment_balance: toNumber(trip.payment_balance),
          net_profit: toNumber(trip.net_profit),
          trip_status: toTripStatus(trip.trip_status),
          start_date: trip.start_date,
          completion_date: trip.completion_date,
          remarks: trip.remarks,
          created_by: trip.created_by,
          created_at: trip.created_at ?? "",
          updated_at: trip.updated_at ?? "",
          vehicleNo: vehicle?.vehicle_no ?? "-",
          ownerName: vehicle?.owner_name ?? "-",
          driverName: driver?.name ?? "-",
          bookingCustomerName: booking?.sender_name ?? "-",
        };
      })
    );
  }

  async function refreshTrips() {
    setLoading(true);
    setError("");

    try {
      const context = await loadCurrentContext();

      await Promise.all([
        loadVehicles(context.addaId),
        loadDrivers(context.addaId),
        loadBookings(context.addaId),
        loadTrips(context.addaId),
      ]);
    } catch (refreshError) {
      setError(
        refreshError instanceof Error
          ? refreshError.message
          : "Unable to load trip management data."
      );
    } finally {
      setLoading(false);
    }
  }

  async function createTrip(payload: TripPayload) {
    setSaving(true);
    setError("");

    try {
      if (!currentUserId || !currentAddaId) {
        throw new Error(
          "User or adda context is missing. Please refresh the page and try again."
        );
      }

      const { error: createError } = await supabase.from("trips").insert({
        ...payload,
        adda_id: currentAddaId,
        created_by: currentUserId,
      });

      if (createError) {
        throw new Error(createError.message || "Unable to create trip.");
      }

      await loadTrips(currentAddaId);
      return true;
    } catch (createError) {
      setError(
        createError instanceof Error
          ? createError.message
          : "Unable to create trip."
      );
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function updateTrip(id: string, payload: TripPayload) {
    setSaving(true);
    setError("");

    try {
      if (!currentAddaId) {
        throw new Error(
          "Adda context is missing. Please refresh the page and try again."
        );
      }

      const { error: updateError } = await supabase
        .from("trips")
        .update(payload)
        .eq("id", id)
        .eq("adda_id", currentAddaId);

      if (updateError) {
        throw new Error(updateError.message || "Unable to update trip.");
      }

      setSelectedTrip(null);
      await loadTrips(currentAddaId);
      return true;
    } catch (updateError) {
      setError(
        updateError instanceof Error
          ? updateError.message
          : "Unable to update trip."
      );
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function deleteTrip(id: string) {
    const confirmed = window.confirm("Delete this trip record?");

    if (!confirmed) return false;

    setSaving(true);
    setError("");

    try {
      if (!currentAddaId) {
        throw new Error(
          "Adda context is missing. Please refresh the page and try again."
        );
      }

      const { error: deleteError } = await supabase
        .from("trips")
        .delete()
        .eq("id", id)
        .eq("adda_id", currentAddaId);

      if (deleteError) {
        throw new Error(deleteError.message || "Unable to delete trip.");
      }

      if (selectedTrip?.id === id) setSelectedTrip(null);
      if (viewingTrip?.id === id) setViewingTrip(null);

      await loadTrips(currentAddaId);
      return true;
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Unable to delete trip."
      );
      return false;
    } finally {
      setSaving(false);
    }
  }

  function resetFilters() {
    setSearch("");
    setSelectedVehicle("");
    setSelectedDriver("");
    setSelectedStatus("");
    setSelectedTripDateFilter("all");
    setCustomFromDate("");
    setCustomToDate("");
  }

  return (
    <div className="space-y-8">
      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <h1 className="text-3xl font-bold text-gray-900">
          Trip / Chakkar Management
        </h1>
        <p className="mt-2 text-base font-medium text-gray-900">
          Manage vehicle trips, routes, freight, advances, expenses, payments
          and trip status.
        </p>
      </div>

      <TripCards summary={summary} loading={loading} />

      <TripFilters
        search={search}
        setSearch={setSearch}
        vehicles={vehicles}
        selectedVehicle={selectedVehicle}
        setSelectedVehicle={setSelectedVehicle}
        drivers={drivers}
        selectedDriver={selectedDriver}
        setSelectedDriver={setSelectedDriver}
        selectedStatus={selectedStatus}
        setSelectedStatus={setSelectedStatus}
        selectedTripDateFilter={selectedTripDateFilter}
        setSelectedTripDateFilter={setSelectedTripDateFilter}
        customFromDate={customFromDate}
        setCustomFromDate={setCustomFromDate}
        customToDate={customToDate}
        setCustomToDate={setCustomToDate}
        onReset={resetFilters}
      />

      <TripForm
        vehicles={vehicles}
        drivers={drivers}
        bookings={bookings}
        selectedTrip={selectedTrip}
        saving={saving}
        error={error}
        onCreate={createTrip}
        onUpdate={updateTrip}
        onCancel={() => setSelectedTrip(null)}
      />

      <TripTable
        trips={filteredTrips}
        loading={loading}
        saving={saving}
        error={error}
        onSelect={setSelectedTrip}
        onDelete={deleteTrip}
        onView={setViewingTrip}
        onRefresh={refreshTrips}
      />

      <TripPrint
        trips={filteredTrips}
        summary={summary}
        selectedTrip={selectedTrip ?? viewingTrip}
      />

      <TripDetailsModal trip={viewingTrip} onClose={() => setViewingTrip(null)} />
    </div>
  );
}
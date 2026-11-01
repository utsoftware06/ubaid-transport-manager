"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ComponentType,
  type Dispatch,
  type SetStateAction,
} from "react";
import VehicleLedgerCards from "@/components/vehicleLedger/VehicleLedgerCards";
import VehicleLedgerFilters from "@/components/vehicleLedger/VehicleLedgerFilters";
import VehicleLedgerTable from "@/components/vehicleLedger/VehicleLedgerTable";
import VehicleTripsModal from "@/components/vehicleLedger/VehicleTripsModal";
import { supabase } from "@/lib/supabase/client";
import { getParchiVehicleSettlementTotalsForBookings } from "@/lib/parchi/vehicleSettlement";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { buildVehicleReports, isVehicleTripDateInRange, matchesBiltyVoucherNumber } from "@/components/vehicleLedger/reporting";
import OwnerLedgerView from "@/components/ownerLedger/OwnerLedgerView";
import DriverLedgerView from "@/components/ledger/DriverLedgerView";
export { formatAmount } from "@/components/vehicleLedger/reporting";

export type VehicleFilterType =
  | "all"
  | "today"
  | "week"
  | "month"
  | "sixMonths"
  | "year"
  | "custom";

export type VehiclePaymentStatus = "Unpaid" | "Partial" | "Paid" | "Not tracked";

export type VehicleLedgerFilterValues = {
  vehicleId: string;
  vehicle: string;
  filterType: VehicleFilterType;
  fromDate: string;
  toDate: string;
  search: string;
  biltyVoucherNo: string;
  paymentStatus: string;
  loadingSource: string;
  collectFrom: string;
};

export type VehicleTripExpense = {
  id: string;
  category: string;
  amount: number;
  source: string;
  sourceVoucherId?: string;
  sourceExpenseItemId?: string;
  sourceLoadingId?: string;
  diesel?: {
    pump: string;
    liters: number;
    rate: number;
    total: number;
    paid: number;
    remaining: number;
    status: string;
    slipNo: string;
  };
};

export type VehicleTripFreightLeg = {
  bookingId: string;
  bookingDate: string;
  loadingId: string | null;
  loadingIds: string[];
  driverId: string | null;
  driverName: string;
  loadingDrivers: Array<{ loadingId: string; driverId: string | null; driverName: string }>;
  vehicleNo: string;
  side: string;
  biltyNo: string;
  route: string;
  loadedThrough: string;
  collectFrom: string;
  rawVehicleFreight: number;
  brokerCommission: number;
  overweightCharges: number;
  loloCharges: number;
  detainCharges: number;
  adjustedVehicleFreight: number;
  advanceVehicle: number;
  laterVehiclePayments: number;
  totalVehiclePaid: number;
  parchiVehicleWithheld: number;
  totalVehicleEntitlementSettled: number;
  balance: number;
  paymentStatus: Exclude<VehiclePaymentStatus, "Not tracked">;
};

export type VehicleTrip = {
  id: string;
  voucherIds: string[];
  addaId: string | null;
  vehicleId: string;
  driverId: string | null;
  vehicleNo: string;
  sourceType: "bilty" | "manual";
  loadingNo: string;
  biltyNo: string;
  biltyNumbers: string[];
  voucherNo: string;
  date: string;
  tripType: string;
  driverName: string;
  ownerName: string;
  route: string;
  loadedThrough: string;
  collectFrom: string;
  rawVehicleFreight: number | null;
  brokerCommission: number;
  overweightCharges: number;
  loloCharges: number;
  detainCharges: number;
  freightLegs?: VehicleTripFreightLeg[];
  income: number;
  advanceVehicle: number | null;
  laterVehiclePayments: number | null;
  totalVehiclePaid: number | null;
  parchiVehicleWithheld: number;
  totalVehicleEntitlementSettled: number | null;
  vehicleBalance: number | null;
  paymentStatus: VehiclePaymentStatus;
  expenseItems: VehicleTripExpense[];
  totalExpense: number;
  profit: number;
  chakkarDays: number | null;
  remarks: string;
  finalizedAt: string;
};

export type VehicleReport = {
  vehicleId: string;
  addaId: string | null;
  vehicleNo: string;
  ownerName: string;
  totalTrips: number;
  totalVehicleFreight: number;
  totalReceived: number;
  totalParchiVehicleWithheld: number;
  totalVehicleEntitlementSettled: number;
  totalOutstanding: number;
  totalExpense: number;
  netVehicleEarnings: number;
  trips: VehicleTrip[];
};

export type VehicleLedgerSummary = {
  totalVehicles: number;
  totalTrips: number;
  totalVehicleFreight: number;
  totalReceived: number;
  totalParchiVehicleWithheld: number;
  totalVehicleEntitlementSettled: number;
  totalOutstanding: number;
  totalExpense: number;
  netVehicleEarnings: number;
};

type VehicleOption = {
  id: string;
  vehicleNo: string;
  ownerName: string;
};

type RelatedRecord<T> = T | T[] | null;
type Numeric = number | string | null;

type VehicleRelation = { vehicle_no: string | null; owner_name: string | null };
type DriverRelation = { name: string | null };
type CounterpartyRelation = { name: string | null };
type BrokerRelation = { broker_name: string | null };
type BookingRelation = {
  id: string;
  bilty_group_id: string | null;
  vehicle_id: string | null;
  adda_id: string | null;
  booking_no: string | null;
  booking_date: string | null;
  loading_date: string | null;
  trip_type: string | null;
  from_city: string | null;
  to_city: string | null;
  vehicle_freight: Numeric;
  advance_vehicle: Numeric;
  broker_commission: Numeric;
  overweight_charges: Numeric;
  lolo_charges: Numeric;
  detain_charges: Numeric;
  party_id: string | null;
  broker_id: string | null;
  loading_source: string | null;
  loading_source_other_adda_id: string | null;
  freight_receivable_from: string | null;
  freight_receivable_other_adda_id: string | null;
  parties: RelatedRecord<CounterpartyRelation>;
  brokers: RelatedRecord<BrokerRelation>;
};
type ExpenseItemRelation = {
  id: string | number;
  expense_type: string | null;
  expense_class: string | null;
  amount: Numeric;
  remarks: string | null;
};
type ExpenseRelation = {
  id: string | number;
  expense_no: string | null;
  loading_id: string | number | null;
};
type VoucherExpenseItem = ExpenseItemRelation & { expense_id: string | number };
type VoucherLoadingRelation = { voucher_id: string | number; loading_id: string | number };
type VoucherWorkshopLink = { voucher_id: string | number; workshop_entry_id: string | number };
type VoucherOilLink = { voucher_id: string | number; oil_vehicle_entry_id: string | number };
type VoucherTyreLink = { voucher_id: string | number; tyre_vehicle_entry_id: string | number };
type WorkshopSource = { id: string | number; workshop_name: string | null; mechanic_name: string | null; bill_no: string | null };
type OilSource = { id: string | number; bill_no: string | null; oil_shops: RelatedRecord<{ shop_name: string | null }> };
type TyreSource = { id: string | number; bill_no: string | null; work_type: string | null; tyre_shops: RelatedRecord<{ shop_name: string | null }> };
type ExpenseHeader = {
  id: string | number;
  expense_no: string | null;
  loading_id: string | number | null;
  movement_group_id: string | null;
};
type LoadingWithRelations = {
  id: string | number;
  loading_no: string | number | null;
  loading_date: string | null;
  route: string | null;
  vehicle_id: string | null;
  driver_id: string | null;
  booking_id: string | null;
  vehicles: RelatedRecord<VehicleRelation>;
  drivers: RelatedRecord<DriverRelation>;
  bookings: RelatedRecord<BookingRelation>;
};
type ManualSettlement = {
  id: string;
  manual_voucher_id: string;
  voucher_id: string | number;
  adda_id: string;
  vehicle_id: string;
  driver_id: string | null;
  settlement_date: string;
  chakkar_days: number | null;
  total_freight: Numeric;
  total_expense_amount: Numeric;
  net_vehicle_amount: Numeric;
  expense_snapshot: unknown;
  finalized_at: string;
};
type ManualVoucherDetail = {
  id: string;
  voucher_id: string | number;
  chakkar_days: number;
  remarks: string | null;
  status: string;
};
type ManualFreightRouteItem = {
  id: string;
  manual_voucher_id: string;
  freight_type: "outbound" | "local" | "return";
  description: string | null;
  sequence_no: number;
};
type BiltySettlementVoucher = { movement_group_id: string; voucher_id: string | number; vehicle_id: string };
type ManualVoucherNumber = { id: string | number; expense_no: string | null };
type DieselRelation = { pump_name: string | null; owner_name: string | null };
type DieselEntry = {
  id: string | number;
  expense_id: string | number;
  expense_item_id: string | number | null;
  loading_id: string | number | null;
  manual_voucher_id: string | null;
  petrol_pump_id: string | null;
  liters: Numeric;
  rate: Numeric;
  total_amount: Numeric;
  paid_amount: Numeric;
  remaining_amount: Numeric;
  payment_status: string | null;
  slip_no: string | null;
  petrol_pumps: RelatedRecord<DieselRelation>;
};
type OtherAddaName = { id: string; adda_name: string | null };
type VehicleLedgerCardsProps = { summary: VehicleLedgerSummary };
type VehicleLedgerFiltersProps = {
  filters: VehicleLedgerFilterValues;
  setFilters: Dispatch<SetStateAction<VehicleLedgerFilterValues>>;
  vehicleOptions: VehicleOption[];
  paymentStatuses: string[];
  loadingSources: string[];
  counterparties: string[];
};
type VehicleLedgerTableProps = {
  reports: VehicleReport[];
  page: number;
  setPage: Dispatch<SetStateAction<number>>;
  onViewTrips: (vehicleReport: VehicleReport) => void;
};
type VehicleTripsModalProps = { vehicleReport: VehicleReport; period: { filterType: VehicleFilterType; fromDate: string; toDate: string }; onClose: () => void };

export function getSingleRelation<T>(relation: RelatedRecord<T>): T | null {
  if (Array.isArray(relation)) return relation[0] ?? null;
  return relation ?? null;
}

export function toNumber(value: Numeric | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function toText(value: string | number | null | undefined) {
  return value === null || value === undefined || value === "" ? "" : String(value);
}

function parseManualRouteSegment(description: string): string[] | null {
  const separators = [/\s*→\s*/, /\s*->\s*/, /\s+to\s+/i, /\s+-\s+/];
  for (const separator of separators) {
    const stops = description.split(separator).map((stop) => stop.trim()).filter(Boolean);
    if (stops.length >= 2) return stops;
  }
  return null;
}

function buildManualRoute(freightItems: ManualFreightRouteItem[]) {
  const descriptions = [...freightItems]
    .sort((left, right) => left.sequence_no - right.sequence_no)
    .map((item) => item.description?.trim() || "")
    .filter(Boolean);
  if (descriptions.length === 0) return "—";

  const segments = descriptions.map(parseManualRouteSegment);
  if (segments.some((segment) => segment === null)) return descriptions.join(" · ");

  const [first, ...rest] = segments as string[][];
  const stops = [...first];
  for (const segment of rest) {
    const previousStop = stops.at(-1)?.toLocaleLowerCase();
    const nextStart = segment[0]?.toLocaleLowerCase();
    if (!previousStop || previousStop !== nextStart) return descriptions.join(" · ");
    stops.push(...segment.slice(1));
  }
  return stops.join(" → ");
}

function displayOtherAdda(value: string | null, names: Map<string, string>, t: (key: string) => string) {
  if (!value) return "";
  const name = names.get(value);
  return name ? `${t("vehicleLedger.fields.otherAdda")}: ${name}` : t("vehicleLedger.fields.otherAddaUnrecorded");
}

function getLoadingSource(booking: BookingRelation, otherAddaNames: Map<string, string>, t: (key: string) => string) {
  if (booking.loading_source === "own_adda") return t("vehicleLedger.fields.ownAdda");
  if (booking.loading_source === "other_adda") {
    const name = displayOtherAdda(booking.loading_source_other_adda_id, otherAddaNames, t);
    return name || t("vehicleLedger.fields.otherAddaUnrecorded");
  }
  return t("vehicleLedger.fields.notRecorded");
}

function getCollectFrom(booking: BookingRelation, otherAddaNames: Map<string, string>, t: (key: string) => string) {
  if (booking.freight_receivable_from === "other_adda") {
    const name = displayOtherAdda(booking.freight_receivable_other_adda_id, otherAddaNames, t);
    return name || t("vehicleLedger.fields.otherAddaUnrecorded");
  }
  if (booking.freight_receivable_from === "existing_counterparty") {
    const partyName = getSingleRelation(booking.parties)?.name?.trim() || "";
    const brokerName = getSingleRelation(booking.brokers)?.broker_name?.trim() || "";
    if (partyName && brokerName) return `${t("vehicleLedger.fields.partyBroker")}: ${partyName} / ${brokerName}`;
    if (partyName) return `${t("vehicleLedger.fields.party")}: ${partyName}`;
    if (brokerName) return `${t("vehicleLedger.fields.broker")}: ${brokerName}`;
    return t("vehicleLedger.fields.existingCounterpartyUnlinked");
  }
  return t("vehicleLedger.fields.notSpecified");
}

function parseExpenseSnapshot(snapshot: unknown): Array<{
  expense_type?: unknown;
  expense_class?: unknown;
  amount?: unknown;
  remarks?: unknown;
}> {
  if (!Array.isArray(snapshot)) return [];
  return snapshot.filter((item): item is Record<string, unknown> =>
    Boolean(item && typeof item === "object" && !Array.isArray(item))
  ) as Array<{
    expense_type?: unknown;
    expense_class?: unknown;
    amount?: unknown;
    remarks?: unknown;
  }>;
}

function enrichExpenseItems(
  rows: Array<{ id: string; category: string; amount: number; source: string; sourceVoucherId?: string; sourceExpenseItemId?: string; sourceLoadingId?: string }>,
  dieselRows: DieselEntry[],
  voucherId: string,
  loadingId?: string,
  manualVoucherId?: string,
): VehicleTripExpense[] {
  const usedDieselIds = new Set<string>();
  return rows.map((row) => {
    const diesel = dieselRows.find((entry) => {
      if (usedDieselIds.has(String(entry.id))) return false;
      if (String(entry.expense_id) !== (row.sourceVoucherId || voucherId)) return false;
      if (manualVoucherId && entry.manual_voucher_id !== manualVoucherId) return false;
      const expectedLoadingId = row.sourceLoadingId || loadingId;
      if (expectedLoadingId && entry.loading_id !== null && String(entry.loading_id) !== expectedLoadingId) return false;
      if (row.sourceExpenseItemId && String(entry.expense_item_id) !== row.sourceExpenseItemId) return false;
      return row.category.toLowerCase().includes("fuel") || row.category.toLowerCase().includes("diesel");
    });
    if (!diesel) return row;
    usedDieselIds.add(String(diesel.id));
    const pump = getSingleRelation(diesel.petrol_pumps);
    const pumpName = pump?.pump_name?.trim() || pump?.owner_name?.trim() || "Petrol Pump";
    const liters = toNumber(diesel.liters);
    const rate = toNumber(diesel.rate);
    const sourceParts = [pumpName, liters ? `${liters.toLocaleString("en-PK")} L` : "", rate ? `@ Rs. ${rate.toLocaleString("en-PK")}` : "", diesel.slip_no ? `Slip ${diesel.slip_no}` : ""]
      .filter(Boolean);
    return {
      ...row,
      category: "Diesel / Fuel",
      source: sourceParts.join(" · ") || row.source,
      diesel: {
        pump: pumpName,
        liters,
        rate,
        total: toNumber(diesel.total_amount),
        paid: toNumber(diesel.paid_amount),
        remaining: toNumber(diesel.remaining_amount),
        status: diesel.payment_status || "Unpaid",
        slipNo: diesel.slip_no || "—",
      },
    };
  });
}

export default function VehicleLedger({ view = "vehicle" }: { view?: "vehicle" | "owner" | "driver" }) {
  const { t, dir } = useLanguage();
  const [trips, setTrips] = useState<VehicleTrip[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [filters, setFilters] = useState<VehicleLedgerFilterValues>({
    vehicleId: "",
    vehicle: "",
    filterType: "all",
    fromDate: "",
    toDate: "",
    search: "",
    biltyVoucherNo: "",
    paymentStatus: "",
    loadingSource: "",
    collectFrom: "",
  });
  const [page, setPage] = useState(1);
  const [selectedVehicleReport, setSelectedVehicleReport] = useState<VehicleReport | null>(null);

  const CardsComponent = VehicleLedgerCards as ComponentType<VehicleLedgerCardsProps>;
  const FiltersComponent = VehicleLedgerFilters as ComponentType<VehicleLedgerFiltersProps>;
  const TableComponent = VehicleLedgerTable as ComponentType<VehicleLedgerTableProps>;
  const TripsModalComponent = VehicleTripsModal as ComponentType<VehicleTripsModalProps>;

  const loadVehicleLedgerData = useCallback(async () => {
    setIsLoading(true);
    try {
      const [loadingResult, settlementResult] = await Promise.all([
        fetchAllRows<LoadingWithRelations>("loadings with vehicle, driver, and booking embeds", (from, to) => supabase
          .from("loadings")
          .select(`
            id, loading_no, loading_date, route, vehicle_id, driver_id, booking_id,
            vehicles(vehicle_no, owner_name), drivers(name),
            bookings(
              id, bilty_group_id, vehicle_id, adda_id, booking_no, booking_date, loading_date, trip_type, from_city, to_city,
              vehicle_freight, advance_vehicle, broker_commission, overweight_charges,
              lolo_charges, detain_charges, party_id, broker_id, loading_source,
              loading_source_other_adda_id, freight_receivable_from, freight_receivable_other_adda_id,
              parties(name), brokers(broker_name)
            )
          `)
          .order("loading_date", { ascending: false })
          .order("id", { ascending: false })
          .range(from, to)),
        fetchAllRows<ManualSettlement>("manual_vehicle_chakkar_settlements", (from, to) => supabase
          .from("manual_vehicle_chakkar_settlements")
          .select("id, manual_voucher_id, voucher_id, adda_id, vehicle_id, driver_id, settlement_date, chakkar_days, total_freight, total_expense_amount, net_vehicle_amount, expense_snapshot, finalized_at")
          .order("settlement_date", { ascending: false })
          .order("id", { ascending: false })
          .range(from, to)),
      ]);
      if (loadingResult.error) throw loadingResult.error;
      if (settlementResult.error) throw settlementResult.error;

      const loadingRows = loadingResult.data ?? [];
      const settlements = settlementResult.data ?? [];
      const settlementIds = settlements.map((row) => row.manual_voucher_id);
      const voucherIds = settlements.map((row) => String(row.voucher_id));
      const driverIds = Array.from(new Set(settlements.map((row) => row.driver_id).filter((id): id is string => Boolean(id))));
      const loadingIds = loadingRows.map((row) => String(row.id));
      const movementGroupIds = Array.from(new Set(loadingRows.flatMap((row) => {
        const booking = getSingleRelation(row.bookings);
        return booking?.bilty_group_id ? [booking.bilty_group_id] : [];
      })));
      const [biltyBookingsResult, voucherLoadingResult, directExpenseHeadersResult, groupExpenseHeadersResult, detailsResult, vouchersResult, manualDriversResult, manualFreightItemsResult, biltySettlementsResult] = await Promise.all([
        movementGroupIds.length
          ? fetchRowsForIdsBestEffort<BookingRelation>("bookings by bilty_group_id", movementGroupIds, (batch, from, to) => supabase.from("bookings").select(`
              id, bilty_group_id, vehicle_id, adda_id, booking_no, booking_date, loading_date, trip_type, from_city, to_city,
              vehicle_freight, advance_vehicle, broker_commission, overweight_charges, lolo_charges,
              detain_charges, party_id, broker_id, loading_source, loading_source_other_adda_id,
              freight_receivable_from, freight_receivable_other_adda_id, parties(name), brokers(broker_name)
            `).in("bilty_group_id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        loadingIds.length
          ? fetchRowsForIdsBestEffort<VoucherLoadingRelation>("voucher_loadings by loading_id", loadingIds, (batch, from, to) => supabase.from("voucher_loadings").select("voucher_id, loading_id").in("loading_id", batch).order("voucher_id").order("loading_id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        loadingIds.length
          ? fetchRowsForIdsBestEffort<ExpenseHeader>("expenses by loading_id", loadingIds, (batch, from, to) => supabase.from("expenses").select("id, expense_no, loading_id, movement_group_id").in("loading_id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        movementGroupIds.length
          ? fetchRowsForIdsBestEffort<ExpenseHeader>("active expenses by movement_group_id", movementGroupIds, (batch, from, to) => supabase.from("expenses").select("id, expense_no, loading_id, movement_group_id").in("movement_group_id", batch).is("archived_at", null).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        settlementIds.length
          ? fetchRowsForIds<ManualVoucherDetail>("manual_voucher_details by settlement", settlementIds, (batch, from, to) => supabase.from("manual_voucher_details").select("id, voucher_id, chakkar_days, remarks, status").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        voucherIds.length
          ? fetchRowsForIds<ManualVoucherNumber>("manual Voucher numbers by expenses.id", voucherIds, (batch, from, to) => supabase.from("expenses").select("id, expense_no").in("id", batch).eq("voucher_source", "manual").order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        driverIds.length
          ? fetchRowsForIds<{ id: string; name: string | null }>("drivers by id", driverIds, (batch, from, to) => supabase.from("drivers").select("id, name").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        settlementIds.length
          ? fetchRowsForIds<ManualFreightRouteItem>("manual_voucher_freight_items by Manual Voucher detail", settlementIds, (batch, from, to) => supabase.from("manual_voucher_freight_items").select("id, manual_voucher_id, freight_type, description, sequence_no").in("manual_voucher_id", batch).order("sequence_no").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        movementGroupIds.length
          ? fetchRowsForIdsBestEffort<BiltySettlementVoucher>("vehicle_chakkar_settlements by movement_group_id", movementGroupIds, (batch, from, to) => supabase.from("vehicle_chakkar_settlements").select("movement_group_id, voucher_id, vehicle_id").in("movement_group_id", batch).order("movement_group_id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
      ]);
      if (detailsResult.error) throw detailsResult.error;
      if (vouchersResult.error) throw vouchersResult.error;
      if (manualDriversResult.error) throw manualDriversResult.error;
      if (manualFreightItemsResult.error) throw manualFreightItemsResult.error;

      const detailsById = new Map(((detailsResult.data ?? []) as unknown as ManualVoucherDetail[]).map((row) => [row.id, row]));
      const manualFreightByDetail = new Map<string, ManualFreightRouteItem[]>();
      for (const row of manualFreightItemsResult.data ?? []) {
        const freightRows = manualFreightByDetail.get(row.manual_voucher_id) ?? [];
        freightRows.push(row);
        manualFreightByDetail.set(row.manual_voucher_id, freightRows);
      }
      const vouchersById = new Map(((vouchersResult.data ?? []) as unknown as ManualVoucherNumber[]).map((row) => [String(row.id), row.expense_no || String(row.id)]));
      const driversById = new Map(((manualDriversResult.data ?? []) as unknown as Array<{ id: string; name: string | null }>).map((row) => [row.id, row.name || "—"]));

      const bookingsById = new Map<string, BookingRelation>();
      for (const booking of biltyBookingsResult.data ?? []) bookingsById.set(booking.id, booking);
      const otherAddaIds = new Set<string>();
      const biltyGroups = new Map<string, LoadingWithRelations[]>();
      for (const loading of loadingRows) {
        const booking = getSingleRelation(loading.bookings);
        if (!booking?.id) continue;
        bookingsById.set(booking.id, booking);
        if (booking.loading_source_other_adda_id) otherAddaIds.add(booking.loading_source_other_adda_id);
        if (booking.freight_receivable_other_adda_id) otherAddaIds.add(booking.freight_receivable_other_adda_id);
        const groupKey = booking.bilty_group_id || booking.id;
        const current = biltyGroups.get(groupKey) ?? [];
        current.push(loading);
        biltyGroups.set(groupKey, current);
      }
      for (const booking of bookingsById.values()) {
        if (booking.loading_source_other_adda_id) otherAddaIds.add(booking.loading_source_other_adda_id);
        if (booking.freight_receivable_other_adda_id) otherAddaIds.add(booking.freight_receivable_other_adda_id);
      }
      const manualDetailIds = settlements
        .filter((row) => detailsById.get(row.manual_voucher_id)?.status === "finalized")
        .map((row) => row.manual_voucher_id);
      const uniqueVoucherIds = Array.from(new Set([
        ...voucherIds,
        ...((biltySettlementsResult.data ?? []) as unknown as BiltySettlementVoucher[]).map((row) => String(row.voucher_id)),
        ...((directExpenseHeadersResult.data ?? []) as unknown as ExpenseHeader[]).map((row) => String(row.id)),
        ...((groupExpenseHeadersResult.data ?? []) as unknown as ExpenseHeader[]).map((row) => String(row.id)),
        ...((voucherLoadingResult.data ?? []) as unknown as VoucherLoadingRelation[]).map((row) => String(row.voucher_id)),
      ]));
      const vehicleIds = Array.from(new Set([
        ...Array.from(bookingsById.values()).map((row) => row.vehicle_id).filter((id): id is string => Boolean(id)),
        ...settlements.map((row) => row.vehicle_id).filter(Boolean),
        ...((biltySettlementsResult.data ?? []) as unknown as BiltySettlementVoucher[]).map((row) => row.vehicle_id).filter(Boolean),
      ]));
      const [otherAddaResult, biltyPayments, biltyDieselResult, manualDieselResult, linkedExpensesResult, linkedExpenseItemsResult, vehiclesResult, workshopLinksResult, oilLinksResult, tyreLinksResult] = await Promise.all([
        otherAddaIds.size
          ? fetchRowsForIds<OtherAddaName>("other_addas by id", Array.from(otherAddaIds), (batch, from, to) => supabase.from("other_addas").select("id, adda_name").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        loadBiltyVehiclePayments(Array.from(bookingsById.values())),
        loadingIds.length
          ? fetchRowsForIds<DieselEntry>("diesel_entries by loading_id with petrol_pumps embed", loadingIds, (batch, from, to) => supabase.from("diesel_entries").select("id, expense_id, expense_item_id, loading_id, manual_voucher_id, petrol_pump_id, liters, rate, total_amount, paid_amount, remaining_amount, payment_status, slip_no, petrol_pumps(pump_name, owner_name)").in("loading_id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        manualDetailIds.length
          ? fetchRowsForIds<DieselEntry>("diesel_entries by manual_voucher_id with petrol_pumps embed", manualDetailIds, (batch, from, to) => supabase.from("diesel_entries").select("id, expense_id, expense_item_id, loading_id, manual_voucher_id, petrol_pump_id, liters, rate, total_amount, paid_amount, remaining_amount, payment_status, slip_no, petrol_pumps(pump_name, owner_name)").in("manual_voucher_id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        uniqueVoucherIds.length
          ? fetchRowsForIdsBestEffort<ExpenseRelation>("expenses by authoritative Voucher IDs", uniqueVoucherIds, (batch, from, to) => supabase.from("expenses").select("id, expense_no, loading_id").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        uniqueVoucherIds.length
          ? fetchRowsForIds<VoucherExpenseItem>("expense_items by unique expense_id", uniqueVoucherIds, (batch, from, to) => supabase.from("expense_items").select("id, expense_id, expense_class, expense_type, amount, remarks").in("expense_id", batch).order("expense_id").order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        vehicleIds.length
          ? fetchRowsForIds<{ id: string; vehicle_no: string | null; owner_name: string | null }>("vehicles by id", vehicleIds, (batch, from, to) => supabase.from("vehicles").select("id, vehicle_no, owner_name").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        uniqueVoucherIds.length
          ? fetchRowsForIdsBestEffort<VoucherWorkshopLink>("voucher_workshop_entries by voucher_id", uniqueVoucherIds, (batch, from, to) => supabase.from("voucher_workshop_entries").select("voucher_id, workshop_entry_id").in("voucher_id", batch).order("voucher_id").order("workshop_entry_id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        uniqueVoucherIds.length
          ? fetchRowsForIdsBestEffort<VoucherOilLink>("voucher_oil_entries by voucher_id", uniqueVoucherIds, (batch, from, to) => supabase.from("voucher_oil_entries").select("voucher_id, oil_vehicle_entry_id").in("voucher_id", batch).order("voucher_id").order("oil_vehicle_entry_id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        uniqueVoucherIds.length
          ? fetchRowsForIdsBestEffort<VoucherTyreLink>("voucher_tyre_entries by voucher_id", uniqueVoucherIds, (batch, from, to) => supabase.from("voucher_tyre_entries").select("voucher_id, tyre_vehicle_entry_id").in("voucher_id", batch).order("voucher_id").order("tyre_vehicle_entry_id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
      ]);
      if (otherAddaResult.error) throw otherAddaResult.error;
      if (biltyDieselResult.error) throw biltyDieselResult.error;
      if (manualDieselResult.error) throw manualDieselResult.error;
      if (vehiclesResult.error) throw vehiclesResult.error;

      const workshopEntryIds = Array.from(new Set(((workshopLinksResult.data ?? []) as unknown as VoucherWorkshopLink[]).map((link) => String(link.workshop_entry_id))));
      const oilEntryIds = Array.from(new Set(((oilLinksResult.data ?? []) as unknown as VoucherOilLink[]).map((link) => String(link.oil_vehicle_entry_id))));
      const tyreEntryIds = Array.from(new Set(((tyreLinksResult.data ?? []) as unknown as VoucherTyreLink[]).map((link) => String(link.tyre_vehicle_entry_id))));
      const [workshopSourcesResult, oilSourcesResult, tyreSourcesResult] = await Promise.all([
        workshopEntryIds.length
          ? fetchRowsForIdsBestEffort<WorkshopSource>("workshop_entries by Voucher source link", workshopEntryIds, (batch, from, to) => supabase.from("workshop_entries").select("id, workshop_name, mechanic_name, bill_no").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        oilEntryIds.length
          ? fetchRowsForIdsBestEffort<OilSource>("oil_vehicle_entries by Voucher source link", oilEntryIds, (batch, from, to) => supabase.from("oil_vehicle_entries").select("id, bill_no, oil_shops(shop_name)").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
        tyreEntryIds.length
          ? fetchRowsForIdsBestEffort<TyreSource>("tyre_vehicle_entries by Voucher source link", tyreEntryIds, (batch, from, to) => supabase.from("tyre_vehicle_entries").select("id, bill_no, work_type, tyre_shops(shop_name)").in("id", batch).order("id").range(from, to))
          : Promise.resolve({ data: [], error: null }),
      ]);

      const otherAddaNames = new Map(((otherAddaResult.data ?? []) as unknown as OtherAddaName[]).map((row) => [row.id, row.adda_name || "Other Adda"]));
      const vehiclesById = new Map(((vehiclesResult.data ?? []) as unknown as Array<{ id: string; vehicle_no: string | null; owner_name: string | null }>).map((row) => [row.id, row]));
      const expensesById = new Map(((linkedExpensesResult.data ?? []) as unknown as ExpenseRelation[]).map((row) => [String(row.id), row]));
      const expenseItemsById = new Map<string, VoucherExpenseItem>();
      for (const row of (linkedExpenseItemsResult.data ?? []) as unknown as VoucherExpenseItem[]) {
        const expenseItemId = String(row.id);
        if (!expenseItemsById.has(expenseItemId)) expenseItemsById.set(expenseItemId, row);
      }
      const workshopSourcesById = new Map(((workshopSourcesResult.data ?? []) as unknown as WorkshopSource[]).map((row) => [String(row.id), row]));
      const oilSourcesById = new Map(((oilSourcesResult.data ?? []) as unknown as OilSource[]).map((row) => [String(row.id), row]));
      const tyreSourcesById = new Map(((tyreSourcesResult.data ?? []) as unknown as TyreSource[]).map((row) => [String(row.id), row]));
      const voucherSourceLabels = new Map<string, { workshop: Set<string>; oil: Set<string>; tyre: Set<string> }>();
      const sourceLabelSet = (voucherId: string) => {
        const current = voucherSourceLabels.get(voucherId) ?? { workshop: new Set<string>(), oil: new Set<string>(), tyre: new Set<string>() };
        voucherSourceLabels.set(voucherId, current);
        return current;
      };
      for (const link of (workshopLinksResult.data ?? []) as unknown as VoucherWorkshopLink[]) {
        const source = workshopSourcesById.get(String(link.workshop_entry_id));
        if (!source) continue;
        const label = [source.workshop_name, source.mechanic_name, source.bill_no].map((value) => value?.trim()).filter(Boolean).join(" · ");
        if (label) sourceLabelSet(String(link.voucher_id)).workshop.add(label);
      }
      for (const link of (oilLinksResult.data ?? []) as unknown as VoucherOilLink[]) {
        const source = oilSourcesById.get(String(link.oil_vehicle_entry_id));
        if (!source) continue;
        const shop = getSingleRelation(source.oil_shops)?.shop_name?.trim();
        const label = [shop, source.bill_no?.trim()].filter(Boolean).join(" · ");
        if (label) sourceLabelSet(String(link.voucher_id)).oil.add(label);
      }
      for (const link of (tyreLinksResult.data ?? []) as unknown as VoucherTyreLink[]) {
        const source = tyreSourcesById.get(String(link.tyre_vehicle_entry_id));
        if (!source) continue;
        const shop = getSingleRelation(source.tyre_shops)?.shop_name?.trim();
        const label = [shop, source.work_type?.trim(), source.bill_no?.trim()].filter(Boolean).join(" · ");
        if (label) sourceLabelSet(String(link.voucher_id)).tyre.add(label);
      }
      const getVoucherSourceLabel = (voucherId: string, expenseType: string) => {
        const sourceSets = voucherSourceLabels.get(voucherId);
        const normalizedType = expenseType.toLowerCase();
        const labels = normalizedType.includes("workshop")
          ? sourceSets?.workshop
          : normalizedType.includes("oil") || normalizedType.includes("lubricant")
            ? sourceSets?.oil
            : normalizedType.includes("tyre") || normalizedType.includes("tire")
              ? sourceSets?.tyre
              : undefined;
        return labels ? Array.from(labels).join("; ") : "";
      };
      const settledVoucherIdsByMovementGroup = new Map<string, Set<string>>();
      for (const row of (biltySettlementsResult.data ?? []) as unknown as BiltySettlementVoucher[]) {
        const groupId = String(row.movement_group_id);
        const voucherSet = settledVoucherIdsByMovementGroup.get(groupId) ?? new Set<string>();
        voucherSet.add(String(row.voucher_id));
        settledVoucherIdsByMovementGroup.set(groupId, voucherSet);
      }
      const directVoucherIdsByMovementGroup = new Map<string, Set<string>>();
      for (const row of (groupExpenseHeadersResult.data ?? []) as unknown as ExpenseHeader[]) {
        if (!row.movement_group_id) continue;
        const groupId = String(row.movement_group_id);
        const voucherSet = directVoucherIdsByMovementGroup.get(groupId) ?? new Set<string>();
        voucherSet.add(String(row.id));
        directVoucherIdsByMovementGroup.set(groupId, voucherSet);
      }
      const dieselRows = [
        ...((biltyDieselResult.data ?? []) as unknown as DieselEntry[]),
        ...((manualDieselResult.data ?? []) as unknown as DieselEntry[]),
      ];
      const expenseResolutionQueryErrors = [
        ["bookings by bilty_group_id", biltyBookingsResult.error],
        ["vehicle_chakkar_settlements by movement_group_id", biltySettlementsResult.error],
        ["expenses by movement_group_id", groupExpenseHeadersResult.error],
        ["expenses by loading_id", directExpenseHeadersResult.error],
        ["voucher_loadings by loading_id", voucherLoadingResult.error],
        ["expenses by authoritative Voucher IDs", linkedExpensesResult.error],
        ["expense_items by expense_id", linkedExpenseItemsResult.error],
        ["voucher_workshop_entries by voucher_id", workshopLinksResult.error],
        ["voucher_oil_entries by voucher_id", oilLinksResult.error],
        ["voucher_tyre_entries by voucher_id", tyreLinksResult.error],
      ].flatMap(([queryName, error]) => error ? [describeVehicleLedgerQueryError(String(queryName), error)] : []);

      const biltyTripRows = Array.from(biltyGroups.entries()).flatMap(([groupId, groupRows]) => {
        try {
        const members = Array.from(bookingsById.values()).filter((booking) => (booking.bilty_group_id || booking.id) === groupId);
        if (members.length === 0) return [];
        const memberVehicleIds = new Set(members.map((booking) => booking.vehicle_id).filter((id): id is string => Boolean(id)));
        const loadedVehicleIds = new Set(groupRows.map((loading) => loading.vehicle_id).filter((id): id is string => Boolean(id)));
        const groupSettlementRows = ((biltySettlementsResult.data ?? []) as unknown as BiltySettlementVoucher[])
          .filter((row) => String(row.movement_group_id) === String(groupId));
        const settlementVehicleId = groupSettlementRows.find((row) => Boolean(row.vehicle_id))?.vehicle_id ?? null;
        const vehicleContextDetails = {
          movement_group_id: groupId,
          bookings: members.map((booking) => ({ id: booking.id, booking_no: booking.booking_no, vehicle_id: booking.vehicle_id })),
          settlement_vehicle_id: settlementVehicleId,
          loadings: groupRows.map((loading) => ({ id: loading.id, loading_no: loading.loading_no, booking_id: loading.booking_id, vehicle_id: loading.vehicle_id })),
        };
        const bookingVehicleId = memberVehicleIds.size === 1 ? Array.from(memberVehicleIds)[0] : null;
        const loadingVehicleId = loadedVehicleIds.size === 1 ? Array.from(loadedVehicleIds)[0] : null;
        const vehicleId = settlementVehicleId || bookingVehicleId || loadingVehicleId;
        if (!vehicleId) {
          console.warn("[VehicleLedger] Skipping Bilty movement group with no resolvable vehicle context.", vehicleContextDetails);
          return [];
        }
        const vehicle = vehiclesById.get(vehicleId);
        const sortedLoads = [...groupRows].sort((left, right) =>
          String(right.loading_date || "").localeCompare(String(left.loading_date || ""))
        );
        const sortedMembers = [...members].sort((left, right) => {
          const order = (type: string | null) => type === "outbound" ? 0 : type === "local" ? 1 : type === "return" ? 2 : 3;
          return order(left.trip_type) - order(right.trip_type) || String(left.booking_no || left.id).localeCompare(String(right.booking_no || right.id));
        });
        const representative = sortedLoads[0];
        const identityBooking = sortedMembers.find((booking) => booking.trip_type === "return") || sortedMembers[0];
        const groupLoadingIds = new Set(groupRows.map((loading) => String(loading.id)));
        const loadingVoucherIds = new Set(((directExpenseHeadersResult.data ?? []) as unknown as ExpenseHeader[])
          .filter((row) => row.loading_id !== null && groupLoadingIds.has(String(row.loading_id)))
          .map((row) => String(row.id)));
        const voucherLoadingVoucherIds = new Set(((voucherLoadingResult.data ?? []) as unknown as VoucherLoadingRelation[])
          .filter((row) => groupLoadingIds.has(String(row.loading_id)))
          .map((row) => String(row.voucher_id)));
        const groupVoucherIds = new Set([
          ...Array.from(directVoucherIdsByMovementGroup.get(String(groupId)) ?? []),
          ...Array.from(settledVoucherIdsByMovementGroup.get(String(groupId)) ?? []),
          ...Array.from(loadingVoucherIds),
          ...Array.from(voucherLoadingVoucherIds),
        ]);
        const voucherNumbers = new Set<string>();
        for (const voucherId of groupVoucherIds) {
          const expense = expensesById.get(voucherId);
          if (expense?.expense_no) voucherNumbers.add(expense.expense_no);
        }
        const expenses = Array.from(expenseItemsById.values())
          .filter((item) => groupVoucherIds.has(String(item.expense_id)))
          .map((item) => ({
          id: String(item.id),
          category: item.expense_type?.trim() || "Other",
          amount: toNumber(item.amount),
          source: item.remarks?.trim() || getVoucherSourceLabel(String(item.expense_id), item.expense_type?.trim() || "") || "—",
          sourceVoucherId: String(item.expense_id),
          sourceExpenseItemId: String(item.id),
        }));
        const expenseItems = enrichExpenseItems(expenses, dieselRows, "");
        const normalizedBiltyNos = new Set(sortedMembers.map((booking) => String(booking.booking_no || "").trim().replace(/^0+/, "") || "0"));
        if (["1", "2", "3", "4"].every((bookingNo) => normalizedBiltyNos.has(bookingNo))) {
          const directMovementGroupVoucherIds = Array.from(directVoucherIdsByMovementGroup.get(String(groupId)) ?? []);
          const settlementVoucherIds = Array.from(settledVoucherIdsByMovementGroup.get(String(groupId)) ?? []);
          const voucherLoadingEdges = (voucherLoadingResult.data ?? [])
            .filter((row) => groupLoadingIds.has(String(row.loading_id)))
            .map((row) => ({ loading_id: row.loading_id, voucher_id: row.voucher_id }));
          const expenseItemRows = Array.from(expenseItemsById.values())
            .filter((item) => groupVoucherIds.has(String(item.expense_id)))
            .map((item) => ({
              voucher_id: String(item.expense_id),
              expense_item_id: item.id,
              amount: item.amount,
              expense_type: item.expense_type,
              expense_class: item.expense_class,
            }));
          console.info("[VehicleLedger][Expense resolution 0001/0002/0003/0004]", {
            movementGroupId: groupId,
            bookingIds: sortedMembers.map((booking) => booking.id),
            loadingIds: Array.from(groupLoadingIds),
            directMovementGroupVoucherIds,
            settlementVoucherIds,
            loadingVoucherIds: Array.from(loadingVoucherIds),
            voucherLoadingVoucherIds: Array.from(voucherLoadingVoucherIds),
            finalVoucherIds: Array.from(groupVoucherIds),
            expenseItemIds: expenseItemRows.map((item) => item.expense_item_id),
            expenseItemAmounts: expenseItemRows.map((item) => ({ expenseItemId: item.expense_item_id, amount: item.amount })),
            linkQueryErrors: expenseResolutionQueryErrors,
            expenseItemsQuerySucceeded: linkedExpenseItemsResult.error === null,
            expenseRowsReturned: Array.from(groupVoucherIds).filter((voucherId) => expensesById.has(voucherId)).length,
            displayedExpenseItemCount: expenseItems.length,
            displayedExpenseTotal: expenseItems.reduce((sum, item) => sum + item.amount, 0),
            voucherLoadingEdges,
          });
        }
        const freightParts = sortedMembers.map((booking) => ({
          booking,
          raw: toNumber(booking.vehicle_freight),
          commission: toNumber(booking.broker_commission),
          overweight: toNumber(booking.overweight_charges),
          lolo: toNumber(booking.lolo_charges),
          detain: toNumber(booking.detain_charges),
          advance: toNumber(booking.advance_vehicle),
          adjusted: toNumber(booking.vehicle_freight) - toNumber(booking.broker_commission)
            + toNumber(booking.overweight_charges) + toNumber(booking.lolo_charges) + toNumber(booking.detain_charges),
          payment: biltyPayments.get(booking.id),
        }));
        let localLegNumber = 0;
        const localLegCount = freightParts.filter((part) => part.booking.trip_type === "local").length;
        const freightLegs: VehicleTripFreightLeg[] = freightParts.map((part) => {
          const booking = part.booking;
          const bookingLoads = sortedLoads.filter((loading) => String(loading.booking_id) === booking.id);
          const loadingDrivers = bookingLoads.map((loading) => ({
            loadingId: String(loading.id),
            driverId: loading.driver_id,
            driverName: loading.driver_id
              ? getSingleRelation(loading.drivers)?.name?.trim() || t("driverLedger.notRecorded")
              : t("driverLedger.notRecorded"),
          }));
          const knownDriverIds = Array.from(new Set(loadingDrivers
            .map((assignment) => assignment.driverId)
            .filter((id): id is string => Boolean(id))));
          const knownDriverNames = Array.from(new Set(loadingDrivers
            .filter((assignment) => assignment.driverId)
            .map((assignment) => assignment.driverName)));
          const laterVehiclePayments = part.payment?.laterVehiclePaid
            ?? Math.max((part.payment?.totalVehiclePaid ?? part.advance) - part.advance, 0);
          const totalVehiclePaid = part.payment?.totalVehiclePaid ?? part.advance;
          const parchiVehicleWithheld = part.payment?.parchiVehicleWithheld ?? 0;
          const totalVehicleEntitlementSettled = totalVehiclePaid + parchiVehicleWithheld;
          const balance = Math.max(part.adjusted - totalVehicleEntitlementSettled, 0);
          const paymentStatus: Exclude<VehiclePaymentStatus, "Not tracked"> = totalVehicleEntitlementSettled <= 0
            ? "Unpaid"
            : balance <= 0 ? "Paid" : "Partial";
          const translatedSide = booking.trip_type
            ? t(`bilty.tripTypes.${booking.trip_type}`)
            : t("vehicleLedger.fields.notRecorded");
          let side = translatedSide;
          if (booking.trip_type === "local" && localLegCount > 1) {
            side = `${translatedSide} ${++localLegNumber}`;
          }
          return {
            bookingId: booking.id,
            bookingDate: (booking.booking_date || booking.loading_date || bookingLoads[0]?.loading_date || "").slice(0, 10),
            loadingId: bookingLoads.length === 1 ? String(bookingLoads[0].id) : null,
            loadingIds: bookingLoads.map((loading) => String(loading.id)),
            driverId: knownDriverIds.length === 1 ? knownDriverIds[0] : null,
            driverName: knownDriverNames.length === 0
              ? t("driverLedger.notRecorded")
              : knownDriverNames.join(", "),
            loadingDrivers,
            vehicleNo: vehiclesById.get(booking.vehicle_id || vehicleId)?.vehicle_no?.trim()
              || getSingleRelation(bookingLoads[0]?.vehicles)?.vehicle_no?.trim()
              || "—",
            side,
            biltyNo: booking.booking_no || booking.id,
            route: [booking.from_city, booking.to_city].filter(Boolean).join(" → ") || "—",
            loadedThrough: getLoadingSource(booking, otherAddaNames, t) || "—",
            collectFrom: getCollectFrom(booking, otherAddaNames, t) || "—",
            rawVehicleFreight: part.raw,
            brokerCommission: part.commission,
            overweightCharges: part.overweight,
            loloCharges: part.lolo,
            detainCharges: part.detain,
            adjustedVehicleFreight: part.adjusted,
            advanceVehicle: part.advance,
            laterVehiclePayments,
            totalVehiclePaid,
            parchiVehicleWithheld,
            totalVehicleEntitlementSettled,
            balance,
            paymentStatus,
          };
        });
        const rawFreight = freightLegs.reduce((sum, leg) => sum + leg.rawVehicleFreight, 0);
        const brokerCommission = freightLegs.reduce((sum, leg) => sum + leg.brokerCommission, 0);
        const overweightCharges = freightLegs.reduce((sum, leg) => sum + leg.overweightCharges, 0);
        const loloCharges = freightLegs.reduce((sum, leg) => sum + leg.loloCharges, 0);
        const detainCharges = freightLegs.reduce((sum, leg) => sum + leg.detainCharges, 0);
        const adjustedFreight = freightLegs.reduce((sum, leg) => sum + leg.adjustedVehicleFreight, 0);
        const advanceVehicle = freightLegs.reduce((sum, leg) => sum + leg.advanceVehicle, 0);
        const paid = freightLegs.reduce((sum, leg) => sum + leg.totalVehiclePaid, 0);
        const parchiVehicleWithheld = freightLegs.reduce((sum, leg) => sum + leg.parchiVehicleWithheld, 0);
        const totalVehicleEntitlementSettled = paid + parchiVehicleWithheld;
        const laterVehiclePayments = freightLegs.reduce((sum, leg) => sum + leg.laterVehiclePayments, 0);
        const balance = freightLegs.reduce((sum, leg) => sum + leg.balance, 0);
        const paymentStatus: VehiclePaymentStatus = totalVehicleEntitlementSettled <= 0 ? "Unpaid" : balance <= 0 ? "Paid" : "Partial";
        const loadedThrough = Array.from(new Set(sortedMembers.map((booking) => getLoadingSource(booking, otherAddaNames, t)))).join(" · ");
        const collectFrom = Array.from(new Set(sortedMembers.map((booking) => getCollectFrom(booking, otherAddaNames, t)))).join(" · ");
        const routes = Array.from(new Set(sortedMembers.map((booking) => [booking.from_city, booking.to_city].filter(Boolean).join(" → ")).filter(Boolean)));
        const drivers = Array.from(new Set(sortedLoads.map((loading) => getSingleRelation(loading.drivers)?.name?.trim()).filter((name): name is string => Boolean(name))));
        const loadingNos = Array.from(new Set(sortedLoads.map((loading) => toText(loading.loading_no)).filter(Boolean)));
        const biltyNos = sortedMembers.map((booking) => booking.booking_no || booking.id);
        const date = identityBooking.booking_date || representative.loading_date || identityBooking.loading_date || "";
        const totalExpense = expenseItems.reduce((sum, item) => sum + item.amount, 0);
        return [{
          id: `bilty:${identityBooking.id}`,
          voucherIds: Array.from(groupVoucherIds),
          addaId: identityBooking.adda_id,
          vehicleId,
          driverId: null,
          vehicleNo: vehicle?.vehicle_no?.trim() || getSingleRelation(representative.vehicles)?.vehicle_no?.trim() || "—",
          sourceType: "bilty" as const,
          loadingNo: loadingNos.join(", ") || "—",
          biltyNo: biltyNos.join(" / "),
          biltyNumbers: sortedMembers.map((booking) => booking.booking_no?.trim() || "").filter(Boolean),
          voucherNo: Array.from(voucherNumbers).join(", ") || "—",
          date: date.slice(0, 10),
          tripType: sortedMembers.map((booking) => booking.trip_type ? t(`bilty.tripTypes.${booking.trip_type}`) : "").filter(Boolean).join(" / ") || "—",
          driverName: drivers.join(", ") || t("driverLedger.notRecorded"),
          ownerName: vehicle?.owner_name?.trim() || getSingleRelation(representative.vehicles)?.owner_name?.trim() || "—",
          route: routes.join(" · ") || representative.route || "—",
          loadedThrough,
          collectFrom,
          rawVehicleFreight: rawFreight,
          brokerCommission,
          overweightCharges,
          loloCharges,
          detainCharges,
          freightLegs,
          income: adjustedFreight,
          advanceVehicle,
          laterVehiclePayments,
          totalVehiclePaid: paid,
          parchiVehicleWithheld,
          totalVehicleEntitlementSettled,
          vehicleBalance: balance,
          paymentStatus,
          expenseItems,
          totalExpense,
          profit: adjustedFreight - totalExpense,
          chakkarDays: null,
          remarks: "",
          finalizedAt: "",
        } satisfies VehicleTrip];
        } catch (error) {
          console.error("[VehicleLedger] Skipping malformed Bilty movement group; other trips remain available.", {
            movement_group_id: groupId,
            error,
          });
          return [];
        }
      });

      const manualTripRows = settlements.flatMap((settlement) => {
        const detail = detailsById.get(settlement.manual_voucher_id);
        if (!detail || detail.status !== "finalized") return [];
        const vehicle = vehiclesById.get(settlement.vehicle_id);
        const voucherNo = vouchersById.get(String(settlement.voucher_id)) || String(settlement.voucher_id);
        const liveExpenseItems = Array.from(expenseItemsById.values())
          .filter((item) => String(item.expense_id) === String(settlement.voucher_id))
          .sort((left, right) => String(left.id).localeCompare(String(right.id), "en", { numeric: true }));
        const matchedExpenseItemIds = new Set<string>();
        const snapshotItems = parseExpenseSnapshot(settlement.expense_snapshot).map((item, index) => {
          const category = typeof item.expense_type === "string" ? item.expense_type : "Other";
          const amount = toNumber(item.amount as Numeric);
          const source = typeof item.remarks === "string" ? item.remarks : "";
          const liveMatch = liveExpenseItems.find((candidate) => {
            const candidateId = String(candidate.id);
            return !matchedExpenseItemIds.has(candidateId)
              && candidate.expense_type === category
              && toNumber(candidate.amount) === amount
              && (candidate.remarks || "") === source
              && (typeof item.expense_class !== "string" || candidate.expense_class === item.expense_class);
          });
          if (liveMatch) matchedExpenseItemIds.add(String(liveMatch.id));
          return {
            id: `manual-${settlement.id}-expense-${index}`,
            category,
            amount,
            source,
            sourceVoucherId: String(settlement.voucher_id),
            sourceExpenseItemId: liveMatch ? String(liveMatch.id) : undefined,
          };
        });
        const expenseItems = enrichExpenseItems(snapshotItems, dieselRows, String(settlement.voucher_id), undefined, settlement.manual_voucher_id);
        return [{
          id: `manual:${String(settlement.voucher_id)}`,
          voucherIds: [String(settlement.voucher_id)],
          addaId: settlement.adda_id,
          vehicleId: settlement.vehicle_id,
          driverId: settlement.driver_id,
          vehicleNo: vehicle?.vehicle_no?.trim() || "—",
          sourceType: "manual" as const,
          loadingNo: "—",
          biltyNo: "—",
          biltyNumbers: [],
          voucherNo,
          date: settlement.settlement_date.slice(0, 10),
          tripType: t("expenses.manual.manualWithoutBilty"),
          driverName: settlement.driver_id ? driversById.get(settlement.driver_id) || t("driverLedger.notRecorded") : t("driverLedger.notRecorded"),
          ownerName: vehicle?.owner_name?.trim() || "—",
          route: buildManualRoute(manualFreightByDetail.get(settlement.manual_voucher_id) ?? []),
          loadedThrough: t("vehicleLedger.fields.manualOwnAdda"),
          collectFrom: t("vehicleLedger.fields.manualOwnAdda"),
          rawVehicleFreight: null,
          brokerCommission: 0,
          overweightCharges: 0,
          loloCharges: 0,
          detainCharges: 0,
          income: toNumber(settlement.total_freight),
          advanceVehicle: null,
          laterVehiclePayments: null,
          totalVehiclePaid: null,
          parchiVehicleWithheld: 0,
          totalVehicleEntitlementSettled: null,
          vehicleBalance: null,
          paymentStatus: "Not tracked" as const,
          expenseItems,
          totalExpense: toNumber(settlement.total_expense_amount),
          // The settlement snapshot is the accounting authority for finalized Manual trips.
          profit: toNumber(settlement.net_vehicle_amount),
          chakkarDays: detail.chakkar_days || settlement.chakkar_days,
          remarks: detail.remarks || "",
          finalizedAt: settlement.finalized_at,
        } satisfies VehicleTrip];
      });

      const nextTrips = [...biltyTripRows, ...manualTripRows].sort((left, right) =>
        right.date.localeCompare(left.date) || left.id.localeCompare(right.id)
      );
      setTrips(nextTrips);
    } catch (error) {
      if (error instanceof VehicleLedgerQueryError) {
        console.error(`[VehicleLedger] load stopped at query: ${error.queryName}`, error.supabaseError);
      } else {
        console.error("[VehicleLedger] unexpected load failure", error);
      }
      alert(t("vehicleLedger.messages.loadFailed"));
      setTrips([]);
    } finally {
      setIsLoading(false);
    }
  }, [t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadVehicleLedgerData(), 0);
    return () => window.clearTimeout(timer);
  }, [loadVehicleLedgerData]);

  const vehicleOptions = useMemo<VehicleOption[]>(() => {
    const vehicles = new Map<string, VehicleOption>();
    for (const trip of trips) {
      if (!trip.vehicleId || vehicles.has(trip.vehicleId)) continue;
      vehicles.set(trip.vehicleId, { id: trip.vehicleId, vehicleNo: trip.vehicleNo, ownerName: trip.ownerName });
    }
    return Array.from(vehicles.values()).sort((left, right) => left.vehicleNo.localeCompare(right.vehicleNo));
  }, [trips]);

  const filteredTrips = useMemo(() => {
    const selectedVehicle = (filters.vehicleId || filters.vehicle).trim().toLowerCase();
    const keyword = filters.search.trim().toLowerCase();
    const biltyVoucherNumber = filters.biltyVoucherNo.trim().toLowerCase();
    return trips.filter((trip) => {
      if (!isVehicleTripDateInRange(trip.date, filters)) return false;
      if (selectedVehicle && trip.vehicleId.toLowerCase() !== selectedVehicle && trip.vehicleNo.toLowerCase() !== selectedVehicle) return false;
      if (filters.paymentStatus && trip.paymentStatus !== filters.paymentStatus) return false;
      if (filters.loadingSource && trip.loadedThrough !== filters.loadingSource) return false;
      if (filters.collectFrom && trip.collectFrom !== filters.collectFrom) return false;
      if (biltyVoucherNumber && !matchesBiltyVoucherNumber(trip, biltyVoucherNumber)) return false;
      if (!keyword) return true;
      const text = [trip.loadingNo, trip.biltyNo, trip.voucherNo, trip.date, trip.tripType, trip.driverName, trip.ownerName,
        trip.route, trip.loadedThrough, trip.collectFrom, ...trip.expenseItems.flatMap((item) => [item.category, item.source])]
        .join(" ").toLowerCase();
      return text.includes(keyword);
    });
  }, [filters, trips]);

  const reports = useMemo<VehicleReport[]>(() => buildVehicleReports(filteredTrips), [filteredTrips]);

  const summary = useMemo<VehicleLedgerSummary>(() => reports.reduce((total, report) => ({
    totalVehicles: total.totalVehicles + 1,
    totalTrips: total.totalTrips + report.totalTrips,
    totalVehicleFreight: total.totalVehicleFreight + report.totalVehicleFreight,
    totalReceived: total.totalReceived + report.totalReceived,
    totalParchiVehicleWithheld: total.totalParchiVehicleWithheld + report.totalParchiVehicleWithheld,
    totalVehicleEntitlementSettled: total.totalVehicleEntitlementSettled + report.totalVehicleEntitlementSettled,
    totalOutstanding: total.totalOutstanding + report.totalOutstanding,
    totalExpense: total.totalExpense + report.totalExpense,
    netVehicleEarnings: total.netVehicleEarnings + report.netVehicleEarnings,
  }), {
    totalVehicles: 0, totalTrips: 0, totalVehicleFreight: 0, totalReceived: 0,
    totalParchiVehicleWithheld: 0, totalVehicleEntitlementSettled: 0,
    totalOutstanding: 0, totalExpense: 0, netVehicleEarnings: 0,
  }), [reports]);

  const paymentStatuses = useMemo(() => Array.from(new Set(trips.map((trip) => trip.paymentStatus))), [trips]);
  const loadingSources = useMemo(() => Array.from(new Set(trips.map((trip) => trip.loadedThrough))).sort(), [trips]);
  const counterparties = useMemo(() => Array.from(new Set(trips.map((trip) => trip.collectFrom))).sort(), [trips]);
  const setFiltersAndResetPage: Dispatch<SetStateAction<VehicleLedgerFilterValues>> = (nextFilters) => {
    setFilters(nextFilters);
    setPage(1);
  };

  if (view === "owner") return <OwnerLedgerView trips={trips} isLoading={isLoading} />;
  if (view === "driver") return <DriverLedgerView trips={trips} isLoading={isLoading} />;

  return (
    <div dir={dir} className="ut-module-page space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="ledger" accent="blue" title={t("vehicleLedger.title")} description={t("vehicleLedger.description")} />
      </header>
      <CardsComponent summary={summary} />
      <FiltersComponent filters={filters} setFilters={setFiltersAndResetPage} vehicleOptions={vehicleOptions}
        paymentStatuses={paymentStatuses} loadingSources={loadingSources} counterparties={counterparties} />
      {isLoading ? (
        <div className="rounded-xl bg-white p-8 text-center font-semibold text-gray-700">{t("common.loading")}</div>
      ) : (
        <TableComponent reports={reports} page={page} setPage={setPage} onViewTrips={setSelectedVehicleReport} />
      )}
      {selectedVehicleReport && <TripsModalComponent vehicleReport={selectedVehicleReport} period={{ filterType: filters.filterType, fromDate: filters.fromDate, toDate: filters.toDate }} onClose={() => setSelectedVehicleReport(null)} />}
    </div>
  );
}

type PageResponse = { data: unknown[] | null; error: unknown | null };

class VehicleLedgerQueryError extends Error {
  constructor(readonly queryName: string, readonly supabaseError: unknown) {
    super(`Vehicle Ledger query failed: ${queryName}`);
    this.name = "VehicleLedgerQueryError";
  }
}

function logVehicleLedgerQueryError(queryName: string, error: unknown) {
  const details = error && typeof error === "object" ? error as Record<string, unknown> : {};
  console.error("[VehicleLedger] Supabase read failed", {
    queryName,
    code: details.code ?? null,
    message: details.message ?? (error instanceof Error ? error.message : String(error)),
    details: details.details ?? null,
    hint: details.hint ?? null,
  });
}

async function fetchAllRows<T>(
  queryName: string,
  buildQuery: (from: number, to: number) => PromiseLike<PageResponse>,
): Promise<{ data: T[]; error: null }> {
  const rows: T[] = [];
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    let result: PageResponse;
    try {
      result = await buildQuery(from, from + pageSize - 1);
    } catch (error) {
      logVehicleLedgerQueryError(queryName, error);
      throw new VehicleLedgerQueryError(queryName, error);
    }
    const { data, error } = result;
    if (error) {
      logVehicleLedgerQueryError(queryName, error);
      throw new VehicleLedgerQueryError(queryName, error);
    }
    const page = (data ?? []) as T[];
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return { data: rows, error: null };
}

async function fetchRowsForIds<T>(
  queryName: string,
  ids: string[],
  buildQuery: (ids: string[], from: number, to: number) => PromiseLike<PageResponse>,
): Promise<{ data: T[]; error: null }> {
  const rows: T[] = [];
  const idBatchSize = 500;
  for (let offset = 0; offset < ids.length; offset += idBatchSize) {
    const batch = ids.slice(offset, offset + idBatchSize);
    const result = await fetchAllRows<T>(queryName, (from, to) => buildQuery(batch, from, to));
    rows.push(...result.data);
  }
  return { data: rows, error: null };
}

async function fetchRowsForIdsBestEffort<T>(
  queryName: string,
  ids: string[],
  buildQuery: (ids: string[], from: number, to: number) => PromiseLike<PageResponse>,
): Promise<{ data: T[]; error: unknown | null }> {
  try {
    const result = await fetchRowsForIds<T>(queryName, ids, buildQuery);
    return { data: result.data, error: null };
  } catch (error) {
    return {
      data: [],
      error: error instanceof VehicleLedgerQueryError ? error.supabaseError : error,
    };
  }
}

function describeVehicleLedgerQueryError(queryName: string, error: unknown) {
  const details = error && typeof error === "object" ? error as Record<string, unknown> : {};
  return {
    queryName,
    code: details.code ?? null,
    message: details.message ?? (error instanceof Error ? error.message : String(error)),
    details: details.details ?? null,
    hint: details.hint ?? null,
  };
}

async function loadBiltyVehiclePayments(bookings: BookingRelation[]) {
  const paymentMap = new Map<string, { totalVehiclePaid: number; laterVehiclePaid: number; parchiVehicleWithheld: number }>();
  const parchiTotals = await getParchiVehicleSettlementTotalsForBookings(bookings);
  for (let offset = 0; offset < bookings.length; offset += 500) {
    const batch = bookings.slice(offset, offset + 500);
    const bookingIds = batch.map((booking) => booking.id);
    const { data } = await fetchAllRows<{ bilty_id: string | null; amount: Numeric }>("bilty_payments filtered to vehicle side", (from, to) => supabase
      .from("bilty_payments")
      .select("bilty_id, amount")
      .in("bilty_id", bookingIds)
      .eq("payment_side", "vehicle")
      .order("bilty_id")
      .order("amount")
      .range(from, to));
    const laterByBooking = new Map<string, number>();
    for (const payment of data) {
      if (!payment.bilty_id) continue;
      const bookingId = String(payment.bilty_id);
      laterByBooking.set(bookingId, (laterByBooking.get(bookingId) ?? 0) + toNumber(payment.amount));
    }
    for (const booking of batch) {
      const laterVehiclePaid = laterByBooking.get(booking.id) ?? 0;
      paymentMap.set(booking.id, {
        totalVehiclePaid: toNumber(booking.advance_vehicle) + laterVehiclePaid,
        laterVehiclePaid,
        parchiVehicleWithheld: parchiTotals.get(booking.id)?.withheldCommission ?? 0,
      });
    }
  }
  return paymentMap;
}

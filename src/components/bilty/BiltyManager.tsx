"use client";

import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ClipboardList,
  Eye,
  FileText,
  MapPin,
  Package,
  Pencil,
  Plus,
  Printer,
  Trash2,
  Truck,
  UsersRound,
  Wallet,
  type LucideIcon,
} from "lucide-react";

import { USER_ROLES } from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import type { BiltyCopyType, BiltyPrintFinancialSummary } from "@/lib/print/biltyPresentation";
import { supabase } from "@/lib/supabase/client";
import {
  applyParchiWithholdingToFinancialSummary,
  buildVehicleSettlementDisplay,
  getBiltyVehicleCashPayments,
  getParchiVehicleSettlementTotalsForBookings,
  type VehicleSettlementDisplay,
} from "@/lib/parchi/vehicleSettlement";
import { listOtherAddas } from "@/components/other-addas/api";
import type { OtherAdda } from "@/components/other-addas/types";

import ChakkarDetailsModal, { sortChakkarBilties } from "./ChakkarDetailsModal";
import BiltyDetailsModal from "./BiltyDetailsModal";
import BiltyTemplatePrint from "./BiltyTemplatePrint";
import LocationSearchField from "./LocationSearchField";
import { getOpenMovementGroups, movementGroupReference } from "./movementGroups";
import { printBilty } from "./BiltyPrint";
import {
  applyBiltyPatch,
  createEmptyBiltyForm,
  createEmptyBiltyItem,
  normalizeBiltyDraft,
  setBiltyField,
} from "./formState";
import type {
  BiltyFormState,
  BiltyItemDraft,
  BiltyItemRow,
  BiltyLoadingCreationResult,
  BiltyMovementGroup,
  BiltyRow,
  VehicleOption,
} from "./types";

type ProfileRow = { role: string | null; adda_id: string | null; is_active: boolean | null };
type AddaRow = { id: string; name: string };
type PartyRow = { id: string; adda_id: string; name: string };
type BrokerRow = { id: string; broker_name: string };

type BiltyFinancialSummary = {
  bilty_id: string;
  total_bilty_rs: number;
  advance_received: number;
  later_received: number;
  total_received: number;
  balance_receivable: number;
  payment_status: "UNPAID" | "PARTIAL" | "PAID";
  vehicle_freight: number;
  advance_vehicle: number;
  later_vehicle_paid: number;
  total_vehicle_paid: number;
  vehicle_balance: number;
  actual_vehicle_cash_paid?: number | null;
  parchi_withheld_commission?: number;
  vehicle_entitlement_settled?: number | null;
  adda_commission: number;
  broker_brokerage: number;
  xl_weight: number;
  mt_receivable: number;
  mt_payable: number;
  lolo_charges: number;
  other_income: number;
  less_deduction: number;
};

type BiltyFinancialColumns = {
  vehicle_freight?: number | null;
  lolo_charges?: number | null;
  detain_charges?: number | null;
};

type PaymentSide = "party_broker" | "vehicle";

type PaymentDraft = {
  date: string;
  amount: string;
  method: string;
  referenceNo: string;
  remarks: string;
};

function relation<T>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

function amountOrZero(value: number | string | null | undefined): number {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

function biltyLoadingRetryKey(addaId: string, bookingId: string) {
  return `ut-bilty-loading-retry:${addaId}:${bookingId}`;
}

function readBiltyLoadingRetryId(addaId: string, bookingId: string) {
  try {
    return window.sessionStorage.getItem(biltyLoadingRetryKey(addaId, bookingId));
  } catch {
    return null;
  }
}

function writeBiltyLoadingRetryId(addaId: string, bookingId: string, requestId: string | null) {
  try {
    const key = biltyLoadingRetryKey(addaId, bookingId);
    if (requestId) window.sessionStorage.setItem(key, requestId);
    else window.sessionStorage.removeItem(key);
  } catch {
    // In-memory idempotency remains available when browser storage is disabled.
  }
}

function isFiniteNonNegative(value: string) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0;
}

function isFinitePositive(value: string) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0;
}

function canonicalDecimal(value: unknown): string | null {
  const text = String(value);
  const match = /^(-?)(\d+)(?:\.(\d+))?$/.exec(text);
  if (!match) return null;
  const whole = match[2].replace(/^0+(?=\d)/, "");
  const fraction = (match[3] ?? "").replace(/0+$/, "");
  return `${match[1]}${whole}${fraction ? `.${fraction}` : ""}`;
}

function FormSectionHeading({
  icon: Icon,
  title,
}: {
  icon: LucideIcon;
  title: string;
}) {
  return (
    <div className="mb-4 flex items-center gap-3 border-b border-slate-100 pb-3">
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-50 text-blue-700">
        <Icon className="h-5 w-5" aria-hidden="true" />
      </span>
      <h3 className="text-base font-black tracking-tight text-slate-900 sm:text-lg">
        {title}
      </h3>
    </div>
  );
}

export default function BiltyManager() {
  const { t, dir, language } = useLanguage();
  const searchParams = useSearchParams();
  const movementGroupId = searchParams.get("movementGroupId");
  const targetBookingId = searchParams.get("bookingId");
  const nextItemId = useRef(2);
  const saveLock = useRef(false);
  const selectedAddaIdRef = useRef("");
  const loadDataRequestRef = useRef(0);
  const linkedEvidenceAddaIdRef = useRef("");
  const linkedOtherAddaBookingIdsRef = useRef<Set<string>>(new Set());
  const otherAddaDueDatesByBookingIdRef = useRef<Record<string, string | null>>({});
  const loadedBrokerAddaIdRef = useRef("");
  const brokerLoadRequestRef = useRef(0);
  const loadedOtherAddaTenantRef = useRef("");
  const otherAddaLoadRequestRef = useRef(0);
  const handledMovementGroupId = useRef<string | null>(null);
  const handledBookingId = useRef<string | null>(null);
  const pendingLoadingRequestIdsRef = useRef<Map<string, string>>(new Map());
  const unresolvedSavedBiltyRef = useRef(false);
  const [profile, setProfile] = useState<ProfileRow | null>(null);
  const [addas, setAddas] = useState<AddaRow[]>([]);
  const [parties, setParties] = useState<PartyRow[]>([]);
  const [brokers, setBrokers] = useState<BrokerRow[]>([]);
  const [otherAddas, setOtherAddas] = useState<OtherAdda[]>([]);
  const [linkedOtherAddaBookingIds, setLinkedOtherAddaBookingIds] = useState<Set<string>>(() => new Set());
  const [vehicles, setVehicles] = useState<VehicleOption[]>([]);
  const [movementGroups, setMovementGroups] = useState<BiltyMovementGroup[]>([]);
  const [groupSearch, setGroupSearch] = useState("");
  const [bilties, setBilties] = useState<BiltyRow[]>([]);
  const [listVehicleSettlementByBooking, setListVehicleSettlementByBooking] = useState<Map<string, VehicleSettlementDisplay | null>>(() => new Map());
  const [listVehicleSettlementLoadFailed, setListVehicleSettlementLoadFailed] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [successMessage, setSuccessMessage] = useState("");
  const [search, setSearch] = useState("");
  const [tripFilter, setTripFilter] = useState("");
  const [freightFilter, setFreightFilter] = useState("");
  const [vehicleTypeFilter, setVehicleTypeFilter] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [selectedBilty, setSelectedBilty] = useState<BiltyRow | null>(null);
  const [selectedChakkarBilties, setSelectedChakkarBilties] = useState<BiltyRow[] | null>(null);
  const [printBiltyTarget, setPrintBiltyTarget] = useState<BiltyRow | null>(null);
  const [vehicleFreight, setVehicleFreight] = useState("0");
  const [loloCharges, setLoloCharges] = useState("0");
  const [financialSummary, setFinancialSummary] = useState<BiltyFinancialSummary | null>(null);
  const [isFinancialSummaryLoading, setIsFinancialSummaryLoading] = useState(false);
  const financialSummaryRequestRef = useRef(0);
  const [paymentSide, setPaymentSide] = useState<PaymentSide | null>(null);
  const [isPaymentSaving, setIsPaymentSaving] = useState(false);
  const [paymentDraft, setPaymentDraft] = useState<PaymentDraft>({
    date: new Date().toISOString().slice(0, 10),
    amount: "",
    method: "",
    referenceNo: "",
    remarks: "",
  });
  const [form, setForm] = useState<BiltyFormState>(() =>
    createEmptyBiltyForm("", "item-1")
  );

  const isSuperAdmin = profile?.role === USER_ROLES.superAdmin;

  const updateForm = useCallback(
    <Key extends keyof BiltyFormState>(key: Key, value: BiltyFormState[Key]) => {
      setForm((current) => setBiltyField(current, key, value));
    },
    []
  );

  async function loadBrokersForAdda(addaId: string) {
    const requestId = ++brokerLoadRequestRef.current;
    if (!addaId) {
      setBrokers([]);
      loadedBrokerAddaIdRef.current = "";
      return;
    }

    setBrokers([]);
    loadedBrokerAddaIdRef.current = "";
    const { data, error } = await supabase.rpc("get_brokers_for_adda", {
      p_adda_id: addaId,
    });
    if (requestId !== brokerLoadRequestRef.current) return;
    if (error) {
      console.error("Unable to load Brokers for Adda:", error);
      setBrokers([]);
      loadedBrokerAddaIdRef.current = "";
      throw error;
    }

    setBrokers(((data ?? []) as BrokerRow[]).map((broker) => ({
      id: broker.id,
      broker_name: broker.broker_name,
    })));
    loadedBrokerAddaIdRef.current = addaId;
  }

  async function loadOtherAddasForAdda(addaId: string) {
    const requestId = ++otherAddaLoadRequestRef.current;
    setOtherAddas([]);
    loadedOtherAddaTenantRef.current = "";
    if (!addaId) return;
    const collected: OtherAdda[] = [];
    for (let batchNumber = 0; ; batchNumber++) {
      if (batchNumber >= 1000) throw new Error("The Other Adda list is too large to load safely.");
      const batch = await listOtherAddas({ adda_id: addaId, offset: collected.length, limit: 1000 });
      if (requestId !== otherAddaLoadRequestRef.current) return;
      for (const master of batch) {
        if (master.adda_id !== addaId) throw new Error("Other Adda response scope mismatch.");
        collected.push(master);
      }
      if (batch.length < 1000) break;
    }
    if (requestId !== otherAddaLoadRequestRef.current) return;
    setOtherAddas(collected);
    loadedOtherAddaTenantRef.current = addaId;
  }

  const loadData = useCallback(async () => {
    const requestId = ++loadDataRequestRef.current;
    setIsLoading(true);
    setErrorMessage("");
    linkedEvidenceAddaIdRef.current = "";
    linkedOtherAddaBookingIdsRef.current = new Set();
    otherAddaDueDatesByBookingIdRef.current = {};
    setLinkedOtherAddaBookingIds(new Set());
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) throw authError ?? new Error("Missing authenticated user");

      const { data: profileData, error: profileError } = await supabase
        .from("profiles")
        .select("role, adda_id, is_active")
        .eq("id", authData.user.id)
        .maybeSingle();
      if (profileError || !profileData?.is_active) throw profileError ?? new Error("Inactive user");
      if (requestId !== loadDataRequestRef.current) return false;

      const currentProfile = profileData as ProfileRow;
      const superAdmin = currentProfile.role === USER_ROLES.superAdmin;
      if (!superAdmin && !currentProfile.adda_id) throw new Error("Missing user Adda");
      setProfile(currentProfile);
      if (!superAdmin) selectedAddaIdRef.current = currentProfile.adda_id ?? "";
      if (currentProfile.adda_id) {
        if (!selectedAddaIdRef.current) selectedAddaIdRef.current = currentProfile.adda_id;
        setForm((current) => ({ ...current, addaId: current.addaId || currentProfile.adda_id || "" }));
      }

      const biltyQuery = supabase
        .from("bookings")
        .select(`
          id, adda_id, party_id, broker_id, vehicle_id, booking_no, booking_date, loading_date,
          bilty_group_id, trip_type, loading_source, loading_source_other_adda_id,
          freight_receivable_from, freight_receivable_other_adda_id,
          freight_type, bilty_type, reference_no,
          departure_date, arrival_date,
          sender_name, sender_phone, receiver_name, receiver_phone, from_city, to_city,
          from_location_id, to_location_id, external_vehicle_no, external_vehicle_type,
          external_owner_name, container_no, container_size, container_weight,
          container_serial, container_port, clearing_agent, shipping_line, container_cargo,
          freight, vehicle_freight, advance_vehicle, advance_bilty, advance_commission,
          overweight_charges, detain_charges, mt_charges_receivable, mt_charges_payable,
          party_commission, broker_commission, advance_brokerage, lolo_charges, other_income,
          deduction_adjustment, account_type, status, created_at,
          parties(name), brokers(broker_name), vehicles(vehicle_no, vehicle_type, owner_name),
          from_location:pakistan_locations!bookings_from_location_id_fkey(id, name, location_type),
          to_location:pakistan_locations!bookings_to_location_id_fkey(id, name, location_type),
          bilty_items(id, goods_name, quantity, weight, unit, remarks, line_no)
        `)
        .order("created_at", { ascending: false });
      if (!superAdmin && currentProfile.adda_id) biltyQuery.eq("adda_id", currentProfile.adda_id);

      const partyQuery = supabase.from("parties").select("id, adda_id, name").eq("is_active", true).order("name");
      const vehicleQuery = supabase.from("vehicles").select("id, adda_id, vehicle_no, vehicle_type, owner_name").order("vehicle_no");
      const addaQuery = supabase.from("addas").select("id, name").order("name");
      if (!superAdmin && currentProfile.adda_id) {
        partyQuery.eq("adda_id", currentProfile.adda_id);
        vehicleQuery.eq("adda_id", currentProfile.adda_id);
        addaQuery.eq("id", currentProfile.adda_id);
      }

      const brokerAddaId = superAdmin
        ? selectedAddaIdRef.current
        : currentProfile.adda_id ?? "";
      const otherAddaTenantId = superAdmin ? selectedAddaIdRef.current : currentProfile.adda_id ?? "";

      const [results] = await Promise.all([
        Promise.all([
          addaQuery,
          partyQuery,
          vehicleQuery,
          supabase.from("bilty_movement_groups").select("id, adda_id, outbound_bilty_id, status, outbound:bookings!bilty_movement_groups_outbound_bilty_id_fkey(booking_no, vehicle_id, vehicles(vehicle_no))"),
          biltyQuery,
        ]),
        loadBrokersForAdda(brokerAddaId),
        loadOtherAddasForAdda(otherAddaTenantId),
      ]);
      if (requestId !== loadDataRequestRef.current || selectedAddaIdRef.current !== otherAddaTenantId) return false;
      const firstError = results.map((result) => result.error).find(Boolean);
      if (firstError) throw firstError;

      setAddas((results[0].data ?? []) as AddaRow[]);
      setParties((results[1].data ?? []) as PartyRow[]);
      setVehicles((results[2].data ?? []) as VehicleOption[]);
      const groupRows = (results[3].data ?? []).map((row) => {
        const outbound = relation((row as { outbound?: { booking_no: string; vehicle_id: string | null; vehicles?: { vehicle_no: string | null } | { vehicle_no: string | null }[] | null } | { booking_no: string; vehicle_id: string | null; vehicles?: { vehicle_no: string | null } | { vehicle_no: string | null }[] | null }[] }).outbound);
        const outboundVehicle = relation(outbound?.vehicles);
        return { id: row.id, adda_id: row.adda_id, outbound_bilty_id: row.outbound_bilty_id, status: row.status, outbound_bilty_no: outbound?.booking_no ?? "-", outbound_vehicle_id: outbound?.vehicle_id ?? "", outbound_vehicle_no: outboundVehicle?.vehicle_no ?? "-" } as BiltyMovementGroup;
      });
      const groupMap = new Map(groupRows.map((group) => [group.id, group]));
      const loadedBilties = ((results[4].data ?? []) as BiltyRow[]).map((bilty) => ({
        ...bilty,
        movement_group: groupMap.get(bilty.bilty_group_id) ?? null,
      }));
      let listSettlementMap = new Map<string, VehicleSettlementDisplay | null>();
      let settlementLoadFailed = false;
      try {
        const [parchiTotals, laterCashByBooking] = await Promise.all([
          getParchiVehicleSettlementTotalsForBookings(loadedBilties.map((bilty) => ({ id: bilty.id, adda_id: bilty.adda_id }))),
          getBiltyVehicleCashPayments(loadedBilties.map((bilty) => bilty.id)),
        ]);
        listSettlementMap = new Map(loadedBilties.map((bilty) => {
          const rawEntitlement = bilty.vehicle_freight;
          const entitlement = rawEntitlement == null ? null
            : amountOrZero(rawEntitlement) - amountOrZero(bilty.broker_commission)
              + amountOrZero(bilty.overweight_charges) + amountOrZero(bilty.lolo_charges) + amountOrZero(bilty.detain_charges);
          const actualCashPaid = rawEntitlement == null ? null
            : amountOrZero(bilty.advance_vehicle) + (laterCashByBooking.get(bilty.id) ?? 0);
          return [bilty.id, buildVehicleSettlementDisplay(
            entitlement,
            actualCashPaid,
            parchiTotals.get(bilty.id)?.withheldCommission ?? 0,
          )];
        }));
      } catch (settlementError) {
        settlementLoadFailed = true;
        console.error("Unable to load Parchi-adjusted Bilty settlement display:", settlementError);
      }
      if (requestId !== loadDataRequestRef.current || selectedAddaIdRef.current !== otherAddaTenantId) return false;
      setListVehicleSettlementByBooking(listSettlementMap);
      setListVehicleSettlementLoadFailed(settlementLoadFailed);
      const linkedIds = new Set<string>();
      const linksByBookingId = new Map<string, { obligation_transaction_id: string; adda_id: string; other_adda_id: string }>();
      const bookingIds = loadedBilties
        .filter((bilty) => Boolean(otherAddaTenantId)
          && bilty.adda_id === otherAddaTenantId
          && bilty.freight_receivable_from === "other_adda"
          && Boolean(bilty.freight_receivable_other_adda_id))
        .map((bilty) => bilty.id);
      for (let offset = 0; offset < bookingIds.length; offset += 100) {
        const { data: linkRows, error: linkError } = await supabase
          .from("other_adda_bilty_obligation_links")
          .select("booking_id, adda_id, other_adda_id, obligation_transaction_id")
          .eq("adda_id", otherAddaTenantId)
          .in("booking_id", bookingIds.slice(offset, offset + 100));
        if (linkError) throw linkError;
        if (requestId !== loadDataRequestRef.current || selectedAddaIdRef.current !== otherAddaTenantId) return false;
        for (const row of linkRows ?? []) {
          if (linksByBookingId.has(row.booking_id)) throw new Error("Duplicate Bilty obligation link returned.");
          linkedIds.add(row.booking_id);
          linksByBookingId.set(row.booking_id, row);
        }
      }
      const dueDatesByBookingId: Record<string, string | null> = {};
      const linkedTransactionIds = Array.from(linksByBookingId.values(), (link) => link.obligation_transaction_id);
      for (let offset = 0; offset < linkedTransactionIds.length; offset += 100) {
        const batchIds = linkedTransactionIds.slice(offset, offset + 100);
        const { data: obligationRows, error: obligationError } = await supabase
          .from("other_adda_transactions")
          .select("id, adda_id, other_adda_id, event_type, origin, side, amount, due_date")
          .in("id", batchIds);
        if (obligationError) throw obligationError;
        if (requestId !== loadDataRequestRef.current || selectedAddaIdRef.current !== otherAddaTenantId) return false;
        const obligationById = new Map((obligationRows ?? []).map((row) => [row.id, row]));
        for (const [bookingId, link] of linksByBookingId) {
          if (!batchIds.includes(link.obligation_transaction_id)) continue;
          const booking = loadedBilties.find((candidate) => candidate.id === bookingId);
          const obligation = obligationById.get(link.obligation_transaction_id);
          if (!booking || !obligation
            || link.adda_id !== booking.adda_id
            || booking.freight_receivable_from !== "other_adda"
            || link.other_adda_id !== booking.freight_receivable_other_adda_id
            || obligation.adda_id !== link.adda_id
            || obligation.other_adda_id !== link.other_adda_id
            || obligation.event_type !== "obligation"
            || obligation.origin !== "bilty"
            || obligation.side !== "receivable"
            || canonicalDecimal(obligation.amount) !== canonicalDecimal(booking.freight)) {
            throw new Error("Bilty Other Adda obligation link evidence is inconsistent.");
          }
          dueDatesByBookingId[bookingId] = obligation.due_date;
        }
      }
      setMovementGroups(groupRows);
      setBilties(loadedBilties);
      linkedEvidenceAddaIdRef.current = otherAddaTenantId;
      linkedOtherAddaBookingIdsRef.current = linkedIds;
      otherAddaDueDatesByBookingIdRef.current = dueDatesByBookingId;
      setLinkedOtherAddaBookingIds(linkedIds);

      if (!movementGroupId) {
        handledMovementGroupId.current = null;
      } else if (handledMovementGroupId.current !== movementGroupId) {
        handledMovementGroupId.current = movementGroupId;
        const groupBilties = loadedBilties.filter(
          (bilty) => bilty.bilty_group_id === movementGroupId
        );

        if (groupBilties.length > 0) {
          setSelectedChakkarBilties(sortChakkarBilties(groupBilties));
        } else {
          setErrorMessage(t("bilty.messages.chakkarNotFound"));
        }
      }
      if (targetBookingId && handledBookingId.current !== targetBookingId) {
        handledBookingId.current = targetBookingId;
        const target = loadedBilties.find((bilty) => bilty.id === targetBookingId);
        if (target) setSelectedBilty(target);
        else setErrorMessage(t("bilty.messages.targetBiltyNotFound"));
      }
      return true;
    } catch (error) {
      if (requestId !== loadDataRequestRef.current) return false;
      console.error("Unable to load Bilty foundation data:", error);
      setErrorMessage(t("bilty.messages.loadFailed"));
      return false;
    } finally {
      if (requestId === loadDataRequestRef.current) setIsLoading(false);
    }
  }, [movementGroupId, targetBookingId, t]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadData(), 0);
    return () => window.clearTimeout(timer);
  }, [loadData]);

  const availableParties = useMemo(() => parties.filter((party) => party.adda_id === form.addaId), [form.addaId, parties]);
  const availableOtherAddas = useMemo(() => otherAddas.filter((otherAdda) => otherAdda.adda_id === form.addaId), [form.addaId, otherAddas]);
  const editingHasOtherAddaObligation = editingId !== null && linkedOtherAddaBookingIds.has(editingId);
  const availableVehicles = useMemo(() => vehicles.filter((vehicle) => vehicle.adda_id === form.addaId), [form.addaId, vehicles]);
  const selectedMovementGroup = useMemo(
    () => movementGroups.find((group) => group.id === form.groupId && group.adda_id === form.addaId) ?? null,
    [form.addaId, form.groupId, movementGroups]
  );
  const groupVehicleLocked = (form.tripType === "local" || form.tripType === "return") && Boolean(form.groupId);
  const effectiveBiltyType: BiltyFormState["biltyType"] = groupVehicleLocked ? "self_vehicle" : form.biltyType;
  const effectiveVehicleId = groupVehicleLocked ? selectedMovementGroup?.outbound_vehicle_id ?? "" : form.vehicleId;
  const selectedVehicle = useMemo(
    () => availableVehicles.find((vehicle) => vehicle.id === effectiveVehicleId) ?? null,
    [availableVehicles, effectiveVehicleId]
  );
  const groups = useMemo(() => getOpenMovementGroups(movementGroups, form.addaId, bilties).filter((group) =>
    movementGroupReference(group, t("bilty.movement.group")).toLocaleLowerCase().includes(groupSearch.trim().toLocaleLowerCase())
  ).concat(editingId && form.groupId
    ? movementGroups.filter((group) => group.id === form.groupId && group.status !== "open")
    : []), [bilties, editingId, form.addaId, form.groupId, groupSearch, movementGroups, t]);
  const visibleBilties = useMemo(() => {
    const keyword = search.trim().toLocaleLowerCase();
    return bilties.filter((bilty) => {
      if (isSuperAdmin && form.addaId && bilty.adda_id !== form.addaId) return false;
      if (tripFilter && bilty.trip_type !== tripFilter) return false;
      if (freightFilter && bilty.freight_type !== freightFilter) return false;
      if (vehicleTypeFilter && bilty.bilty_type !== vehicleTypeFilter) return false;
      const searchable = [
        bilty.booking_no,
        bilty.reference_no,
        relation(bilty.parties)?.name,
        relation(bilty.brokers)?.broker_name,
        relation(bilty.vehicles)?.vehicle_no,
        bilty.external_vehicle_no,
        bilty.sender_name,
        bilty.receiver_name,
        bilty.from_city,
        bilty.to_city,
      ].filter(Boolean).join(" ").toLocaleLowerCase();
      return !keyword || searchable.includes(keyword);
    });
  }, [bilties, form.addaId, freightFilter, isSuperAdmin, search, tripFilter, vehicleTypeFilter]);

  const loadFinancialSummary = useCallback(async (biltyId: string, addaId: string) => {
    const requestId = ++financialSummaryRequestRef.current;
    setFinancialSummary(null);
    setIsFinancialSummaryLoading(true);
    try {
      const [summaryResult, parchiTotals] = await Promise.all([
        supabase.rpc("get_bilty_financial_summary", { p_bilty_id: biltyId }),
        getParchiVehicleSettlementTotalsForBookings([{ id: biltyId, adda_id: addaId }]),
      ]);
      if (summaryResult.error) throw summaryResult.error;
      const row = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
      if (!row) throw new Error("BILTY_FINANCIAL_SUMMARY_UNAVAILABLE");
      if (requestId !== financialSummaryRequestRef.current) return;
      setFinancialSummary(applyParchiWithholdingToFinancialSummary(
        row as BiltyFinancialSummary,
        parchiTotals.get(biltyId)?.withheldCommission ?? 0,
      ));
    } catch (error) {
      console.error("Unable to load Bilty financial summary:", error);
      if (requestId === financialSummaryRequestRef.current) setFinancialSummary(null);
    } finally {
      if (requestId === financialSummaryRequestRef.current) setIsFinancialSummaryLoading(false);
    }
  }, []);

  const resetForm = useCallback(() => {
    financialSummaryRequestRef.current += 1;
    setIsFinancialSummaryLoading(false);
    unresolvedSavedBiltyRef.current = false;
    setEditingId(null);
    const resetAddaId = profile?.adda_id ?? "";
    selectedAddaIdRef.current = resetAddaId;
    setForm(createEmptyBiltyForm(resetAddaId, `item-${nextItemId.current++}`));
    if (loadedOtherAddaTenantRef.current !== resetAddaId) {
      void loadOtherAddasForAdda(resetAddaId).catch(() => setErrorMessage(t("bilty.messages.loadFailed")));
    }
    if (loadedBrokerAddaIdRef.current !== resetAddaId) {
      void loadBrokersForAdda(resetAddaId).catch(() => {
        setErrorMessage(t("bilty.messages.loadFailed"));
      });
    }
    setVehicleFreight("0");
    setLoloCharges("0");
    setFinancialSummary(null);
    setPrintBiltyTarget(null);
    setPaymentSide(null);
    setPaymentDraft({
      date: new Date().toISOString().slice(0, 10),
      amount: "",
      method: "",
      referenceNo: "",
      remarks: "",
    });
    setGroupSearch("");
  }, [profile?.adda_id, t]);

  async function editBilty(bilty: BiltyRow) {
    unresolvedSavedBiltyRef.current = false;
    selectedAddaIdRef.current = bilty.adda_id;
    if (linkedEvidenceAddaIdRef.current !== bilty.adda_id) {
      const evidenceLoaded = await loadData();
      if (!evidenceLoaded || linkedEvidenceAddaIdRef.current !== bilty.adda_id) {
        setErrorMessage(t("bilty.messages.loadFailed"));
        return;
      }
    }
    if (loadedOtherAddaTenantRef.current !== bilty.adda_id) {
      void loadOtherAddasForAdda(bilty.adda_id).catch(() => setErrorMessage(t("bilty.messages.loadFailed")));
    }
    if (loadedBrokerAddaIdRef.current !== bilty.adda_id) {
      void loadBrokersForAdda(bilty.adda_id).catch(() => {
        setErrorMessage(t("bilty.messages.loadFailed"));
      });
    }
    const itemRows = [...(bilty.bilty_items ?? [])].sort((a, b) => a.line_no - b.line_no);
    const financialBilty = bilty as BiltyRow & BiltyFinancialColumns;
    setEditingId(bilty.id);
    setVehicleFreight(String(financialBilty.vehicle_freight ?? 0));
    setLoloCharges(String(financialBilty.lolo_charges ?? 0));
    void loadFinancialSummary(bilty.id, bilty.adda_id);
    setForm(applyBiltyPatch(createEmptyBiltyForm(bilty.adda_id, `item-${nextItemId.current++}`), normalizeBiltyDraft({
      addaId: bilty.adda_id,
      biltyNo: bilty.booking_no,
      biltyDate: bilty.booking_date,
      loadingDate: bilty.loading_date ?? "",
      groupId: bilty.bilty_group_id,
      tripType: bilty.trip_type ?? "outbound",
      loadingSource: bilty.loading_source ?? "",
      loadingSourceOtherAddaId: bilty.loading_source_other_adda_id ?? "",
      freightReceivableFrom: bilty.freight_receivable_from ?? "",
      freightReceivableOtherAddaId: bilty.freight_receivable_other_adda_id ?? "",
      otherAddaDueDate: otherAddaDueDatesByBookingIdRef.current[bilty.id] ?? "",
      freightType: bilty.freight_type ?? "to_pay",
      biltyType: bilty.bilty_type ?? "self_vehicle",
      partyId: bilty.party_id ?? "",
      brokerId: bilty.broker_id ?? "",
      referenceNo: bilty.reference_no ?? "",
      departureDate: bilty.departure_date ?? "",
      arrivalDate: bilty.arrival_date ?? "",
      vehicleId: bilty.vehicle_id ?? "",
      externalVehicleNo: bilty.external_vehicle_no ?? "",
      externalVehicleType: bilty.external_vehicle_type ?? "",
      externalOwnerName: bilty.external_owner_name ?? "",
      containerNo: bilty.container_no ?? "",
      containerSize: bilty.container_size ?? "",
      containerWeight: String(bilty.container_weight ?? ""),
      containerSerial: bilty.container_serial ?? "",
      containerPort: bilty.container_port ?? "",
      clearingAgent: bilty.clearing_agent ?? "",
      shippingLine: bilty.shipping_line ?? "",
      containerCargo: bilty.container_cargo ?? "",
      fromLocationId: bilty.from_location_id ?? "",
      toLocationId: bilty.to_location_id ?? "",
      fromLocationSearch: relation(bilty.from_location)?.name ?? bilty.from_city ?? "",
      toLocationSearch: relation(bilty.to_location)?.name ?? bilty.to_city ?? "",
      senderName: bilty.sender_name ?? "",
      senderPhone: bilty.sender_phone ?? "",
      receiverName: bilty.receiver_name ?? "",
      receiverPhone: bilty.receiver_phone ?? "",
      freight: String(bilty.freight ?? ""),
      advanceVehicle: String(bilty.advance_vehicle ?? 0),
      advanceBilty: String(bilty.advance_bilty ?? 0),
      advanceCommission: String(bilty.advance_commission ?? 0),
      overweightCharges: String(bilty.overweight_charges ?? 0),
      detainCharges: String(financialBilty.detain_charges ?? 0),
      mtChargesReceivable: String(bilty.mt_charges_receivable ?? 0),
      mtChargesPayable: String(bilty.mt_charges_payable ?? 0),
      partyCommission: String(bilty.party_commission ?? 0),
      brokerCommission: String(bilty.broker_commission ?? 0),
      advanceBrokerage: String(bilty.advance_brokerage ?? 0),
      otherIncome: String(bilty.other_income ?? 0),
      deductionAdjustment: String(bilty.deduction_adjustment ?? 0),
      accountType: bilty.account_type ?? "",
      items: itemRows.length
        ? itemRows.map((item: BiltyItemRow) => ({
            clientId: item.id,
            goodsName: item.goods_name,
            quantity: String(item.quantity),
            weight: item.weight === null ? "" : String(item.weight),
            unit: item.unit,
            remarks: item.remarks ?? "",
          }))
        : [createEmptyBiltyItem(`item-${nextItemId.current++}`)],
    })));
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function updateItem(clientId: string, field: keyof Omit<BiltyItemDraft, "clientId">, value: string) {
    setForm((current) => ({
      ...current,
      items: current.items.map((item) => item.clientId === clientId ? { ...item, [field]: value } : item),
    }));
  }

  function addItem() {
    setForm((current) => ({ ...current, items: [...current.items, createEmptyBiltyItem(`item-${nextItemId.current++}`)] }));
  }

  function removeItem(clientId: string) {
    setForm((current) => ({
      ...current,
      items: current.items.length === 1 ? current.items : current.items.filter((item) => item.clientId !== clientId),
    }));
  }

  async function saveBilty(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saveLock.current) return;
    if (unresolvedSavedBiltyRef.current) {
      setErrorMessage(t("bilty.messages.loadingPendingMissingId"));
      return;
    }
    setErrorMessage("");
    setSuccessMessage("");

    const invalidItem = form.items.some((item) =>
      !item.goodsName.trim() || !item.unit.trim() || !isFinitePositive(item.quantity) ||
      (item.weight !== "" && !isFiniteNonNegative(item.weight))
    );
    const normalizedBiltyNo = form.biltyNo.trim().toLocaleLowerCase();
    const duplicateNumber = bilties.some(
      (bilty) =>
        bilty.id !== editingId &&
        bilty.adda_id === form.addaId &&
        bilty.booking_no.trim().toLocaleLowerCase() === normalizedBiltyNo
    );
    if (duplicateNumber) {
      setErrorMessage(t("bilty.validation.duplicateNumber"));
      return;
    }
    if (
      form.departureDate &&
      form.arrivalDate &&
      form.arrivalDate < form.departureDate
    ) {
      setErrorMessage(t("bilty.validation.arrivalBeforeDeparture"));
      return;
    }
    const optionalAmounts = [
      vehicleFreight,
      loloCharges,
      form.advanceVehicle,
      form.advanceBilty,
      form.advanceCommission,
      form.overweightCharges,
      form.mtChargesReceivable,
      form.mtChargesPayable,
      form.partyCommission,
      form.brokerCommission,
      form.advanceBrokerage,
      form.otherIncome,
      form.deductionAdjustment,
    ];
    if (
      optionalAmounts.some((value) => !isFiniteNonNegative(value || "0")) ||
      (form.containerWeight !== "" && !isFiniteNonNegative(form.containerWeight))
    ) {
      setErrorMessage(t("bilty.validation.amountsNonNegative"));
      return;
    }
    if (!form.addaId || !form.biltyNo.trim() || !form.biltyDate || !form.fromLocationId ||
      !form.toLocationId || invalidItem || !isFiniteNonNegative(form.freight)) {
      setErrorMessage(t("bilty.validation.required"));
      return;
    }
    if ((form.tripType === "return" || form.tripType === "local") && !form.groupId) {
      setErrorMessage(t("bilty.validation.movementGroupRequired"));
      return;
    }
    if (
      !form.loadingSource ||
      (form.loadingSource === "other_adda" && !form.loadingSourceOtherAddaId) ||
      !form.freightReceivableFrom ||
      (form.freightReceivableFrom === "other_adda" && !form.freightReceivableOtherAddaId)
    ) {
      setErrorMessage(t("bilty.validation.phase3cRequired"));
      return;
    }
    const originalBilty = editingId ? bilties.find((bilty) => bilty.id === editingId) : null;
    if (form.freightReceivableFrom === "other_adda"
      && Number(form.advanceBilty || 0) > 0
      && (!originalBilty || originalBilty.freight_receivable_from !== "other_adda")) {
      setErrorMessage("Bilty advance cannot settle an Other Adda receivable. Record settlement through the Other Adda account.");
      return;
    }
    if (effectiveBiltyType === "self_vehicle" && !effectiveVehicleId) {
      setErrorMessage(t("bilty.validation.vehicleRequired"));
      return;
    }
    if (effectiveBiltyType === "other_vehicle" && !form.externalVehicleNo.trim()) {
      setErrorMessage(t("bilty.validation.externalVehicleRequired"));
      return;
    }

    saveLock.current = true;
    setIsSaving(true);
    try {
      const { data: savedBookingData, error } = await supabase.rpc("save_bilty_with_items_v2", {
        p_bilty_id: editingId,
        p_adda_id: form.addaId,
        p_booking_no: form.biltyNo.trim(),
        p_booking_date: form.biltyDate,
        p_loading_date: form.loadingDate || null,
        p_group_id: form.groupId || null,
        p_trip_type: form.tripType,
        p_freight_type: form.freightType,
        p_bilty_type: effectiveBiltyType,
        p_party_id: form.partyId || null,
        p_broker_id: form.brokerId || null,
        p_reference_no: form.referenceNo.trim() || null,
        p_departure_date: form.departureDate || null,
        p_arrival_date: form.arrivalDate || null,
        p_vehicle_id: effectiveVehicleId || null,
        p_external_vehicle_no: form.externalVehicleNo.trim() || null,
        p_external_vehicle_type: form.externalVehicleType.trim() || null,
        p_external_owner_name: form.externalOwnerName.trim() || null,
        p_container_no: form.containerNo.trim() || null,
        p_container_size: form.containerSize.trim() || null,
        p_container_weight: form.containerWeight ? Number(form.containerWeight) : null,
        p_container_serial: form.containerSerial.trim() || null,
        p_container_port: form.containerPort.trim() || null,
        p_clearing_agent: form.clearingAgent.trim() || null,
        p_shipping_line: form.shippingLine.trim() || null,
        p_container_cargo: form.containerCargo.trim() || null,
        p_from_location_id: form.fromLocationId,
        p_to_location_id: form.toLocationId,
        p_sender_name: form.senderName.trim(),
        p_sender_phone: form.senderPhone.trim(),
        p_receiver_name: form.receiverName.trim(),
        p_receiver_phone: form.receiverPhone.trim(),
        p_freight: Number(form.freight),
        p_vehicle_freight: amountOrZero(vehicleFreight),
        p_advance_vehicle: Number(form.advanceVehicle || 0),
        p_advance_bilty: form.freightReceivableFrom === "other_adda" && !editingId
          ? 0
          : Number(form.advanceBilty || 0),
        p_advance_commission: Number(form.advanceCommission || 0),
        p_overweight_charges: amountOrZero(form.overweightCharges),
        p_mt_charges_receivable: Number(form.mtChargesReceivable || 0),
        p_mt_charges_payable: Number(form.mtChargesPayable || 0),
        p_party_commission: Number(form.partyCommission || 0),
        p_broker_commission: amountOrZero(form.brokerCommission),
        p_advance_brokerage: Number(form.advanceBrokerage || 0),
        p_lolo_charges: amountOrZero(loloCharges),
        p_other_income: Number(form.otherIncome || 0),
        p_deduction_adjustment: Number(form.deductionAdjustment || 0),
        p_account_type: form.accountType || null,
        p_items: form.items.map((item) => ({
          goods_name: item.goodsName.trim(),
          quantity: Number(item.quantity),
          weight: item.weight ? Number(item.weight) : null,
          unit: item.unit.trim(),
          remarks: item.remarks.trim() || null,
        })),
        p_loading_source: form.loadingSource,
        p_loading_source_other_adda_id: form.loadingSource === "other_adda" ? form.loadingSourceOtherAddaId : null,
        p_freight_receivable_from: form.freightReceivableFrom,
        p_freight_receivable_other_adda_id: form.freightReceivableFrom === "other_adda" ? form.freightReceivableOtherAddaId : null,
        p_other_adda_due_date: form.freightReceivableFrom === "other_adda" ? form.otherAddaDueDate || null : null,
      });
      if (error) throw error;

      let savedBookingId = typeof savedBookingData === "string" ? savedBookingData : editingId;
      if (!savedBookingId) {
        // The deployed save RPC returns the Booking UUID. This tenant-scoped
        // exact-key lookup is a compatibility fallback if PostgREST omits it.
        const { data: savedBooking, error: lookupError } = await supabase
          .from("bookings")
          .select("id")
          .eq("adda_id", form.addaId)
          .eq("booking_no", form.biltyNo.trim())
          .maybeSingle();
        if (lookupError || !savedBooking?.id) {
          unresolvedSavedBiltyRef.current = true;
          console.error("Bilty saved, but its Booking ID could not be resolved for Loading creation:", lookupError);
          setErrorMessage(
            `${t("bilty.messages.loadingPendingMissingId")}${lookupError?.message ? ` ${lookupError.message}` : ""}`
          );
          return;
        }
        savedBookingId = savedBooking.id;
      }
      if (!savedBookingId) {
        unresolvedSavedBiltyRef.current = true;
        setErrorMessage(t("bilty.messages.loadingPendingMissingId"));
        return;
      }
      const bookingId = savedBookingId;

      const wasEditing = Boolean(editingId);
      const pendingRequestId = pendingLoadingRequestIdsRef.current.get(bookingId)
        ?? readBiltyLoadingRetryId(form.addaId, bookingId);
      const shouldEnsureLoading = !wasEditing || Boolean(pendingRequestId);
      if (shouldEnsureLoading) {
        const requestId = pendingRequestId ?? crypto.randomUUID();
        pendingLoadingRequestIdsRef.current.set(bookingId, requestId);
        writeBiltyLoadingRetryId(form.addaId, bookingId, requestId);
        setEditingId(bookingId);

        let loadingData: unknown = null;
        let loadingError: { message?: string; details?: string; hint?: string; code?: string } | null = null;
        try {
          const loadingResponse = await supabase.rpc("create_loading_from_bilty", {
            p_adda_id: form.addaId,
            p_booking_id: bookingId,
            p_request_id: requestId,
          });
          loadingData = loadingResponse.data;
          loadingError = loadingResponse.error;
        } catch (requestError) {
          loadingError = requestError as { message?: string; details?: string; hint?: string; code?: string };
        }
        const loadingResult = (Array.isArray(loadingData) ? loadingData[0] : loadingData) as
          | BiltyLoadingCreationResult
          | null;

        if (loadingError || !loadingResult?.loading_id) {
          console.error("Bilty was saved, but its Loading could not be created:", loadingError);
          await loadData();
          setErrorMessage(
            `${t("bilty.messages.loadingPending")}${loadingError?.message ? ` ${loadingError.message}` : ""}`
          );
          return;
        }

        const loadingMessage = loadingResult.loading_created
          ? t("bilty.messages.loadingCreated")
          : t("bilty.messages.loadingReused");
        const marginMessage = loadingResult.margin_status === "recognized"
          ? Number(loadingResult.margin_amount) > 0
            ? t("bilty.messages.marginRecognized")
            : t("bilty.messages.lossRecognized")
          : loadingResult.margin_status === "zero_margin"
            ? t("bilty.messages.zeroMargin")
            : loadingResult.margin_status === "other_adda_no_own_margin"
              ? t("bilty.messages.otherAddaNoMargin")
              : loadingResult.margin_status === "reversed"
                ? t("bilty.messages.loadingMarginReversed")
                : t("bilty.messages.existingLoadingNoRecognition");

        pendingLoadingRequestIdsRef.current.delete(bookingId);
        writeBiltyLoadingRetryId(form.addaId, bookingId, null);
        setSuccessMessage([
          t(wasEditing ? "bilty.messages.updated" : "bilty.messages.saved"),
          loadingMessage,
          marginMessage,
        ].join(" "));
      } else {
        setSuccessMessage(t("bilty.messages.updated"));
      }
      const { error: detainError } = await supabase.rpc("save_bilty_detain_charges", {
        p_adda_id: form.addaId,
        p_bilty_id: bookingId,
        p_detain_charges: amountOrZero(form.detainCharges),
      });
      if (detainError) throw detainError;
      resetForm();
      await loadData();
    } catch (error) {
      console.error("Unable to save Bilty:", error);
      setSuccessMessage("");
      const code = typeof error === "object" && error !== null && "code" in error ? String(error.code) : "";
      const message = typeof error === "object" && error !== null && "message" in error ? String(error.message) : "";
      const linkedFieldError = /linked.*(immutable|field)|immutable.*(bilty|field)|other_adda.*linked/i.test(message);
      setErrorMessage(message.includes("BILTY_FINANCIAL_FIELDS_LOCKED_AFTER_LOADING_MARGIN")
        ? t("bilty.messages.loadingMarginLocked")
        : linkedFieldError
          ? t("bilty.messages.linkedObligationLocked")
          : t(code === "23505" ? "bilty.validation.duplicateNumber" : "bilty.messages.saveFailed"));
    } finally {
      saveLock.current = false;
      setIsSaving(false);
    }
  }

  const isOtherAddaReceivable = form.freightReceivableFrom === "other_adda";
  const laterReceived = isOtherAddaReceivable ? 0 : amountOrZero(financialSummary?.later_received);
  const laterVehiclePaid = amountOrZero(financialSummary?.later_vehicle_paid);
  const totalBiltyRs = amountOrZero(form.freight);
  const advanceReceived = isOtherAddaReceivable ? 0 : amountOrZero(form.advanceBilty);
  const totalReceived = advanceReceived + laterReceived;
  const balanceReceivable = Math.max(totalBiltyRs - totalReceived, 0);
  const paymentStatus: "UNPAID" | "PARTIAL" | "PAID" =
    totalReceived <= 0 ? "UNPAID" : balanceReceivable <= 0 ? "PAID" : "PARTIAL";

  const vehicleFreightAmount = amountOrZero(vehicleFreight);
  const brokerCommissionAmount = amountOrZero(form.brokerCommission);
  const overweightChargesAmount = amountOrZero(form.overweightCharges);
  const loloChargesAmount = amountOrZero(loloCharges);
  const detainChargesAmount = amountOrZero(form.detainCharges);
  const adjustedVehicleFreight =
    vehicleFreightAmount - brokerCommissionAmount + overweightChargesAmount + loloChargesAmount + detainChargesAmount;
  const advanceVehicleAmount = amountOrZero(form.advanceVehicle);
  const totalVehiclePaid = advanceVehicleAmount + laterVehiclePaid;
  const vehicleSettlementVerified = !editingId || Boolean(financialSummary);
  const parchiVehicleWithheld = financialSummary?.parchi_withheld_commission ?? 0;
  const vehicleEntitlementSettled = vehicleSettlementVerified
    ? totalVehiclePaid + parchiVehicleWithheld
    : null;
  const vehicleBalance = vehicleSettlementVerified
    ? Math.max(adjustedVehicleFreight - totalVehiclePaid - parchiVehicleWithheld, 0)
    : null;
  const addaCommission = totalBiltyRs - vehicleFreightAmount;

  const formatMoney = (value: number) =>
    new Intl.NumberFormat("en-PK", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(Number.isFinite(value) ? value : 0);

  function openPayment(side: PaymentSide) {
    if (side === "party_broker" && isOtherAddaReceivable) {
      setErrorMessage("Party/Broker payments are unavailable for an Other Adda receivable. Record settlement through the Other Adda account.");
      return;
    }
    if (!editingId) {
      setErrorMessage("Save the Bilty first, then add later payments.");
      return;
    }
    setPaymentSide(side);
    setPaymentDraft({
      date: new Date().toISOString().slice(0, 10),
      amount: "",
      method: "",
      referenceNo: "",
      remarks: "",
    });
  }

  async function saveLaterPayment() {
    if (!editingId || !paymentSide) return;
    if (paymentSide === "party_broker" && isOtherAddaReceivable) {
      setPaymentSide(null);
      setErrorMessage("Party/Broker payments are unavailable for an Other Adda receivable. Record settlement through the Other Adda account.");
      return;
    }
    const amount = Number(paymentDraft.amount);
    if (!paymentDraft.date || !Number.isFinite(amount) || amount <= 0) {
      setErrorMessage("Enter a valid payment date and amount.");
      return;
    }

    setIsPaymentSaving(true);
    setErrorMessage("");
    setSuccessMessage("");
    try {
      const { error } = await supabase.rpc("add_bilty_payment", {
        p_bilty_id: editingId,
        p_payment_side: paymentSide,
        p_payment_date: paymentDraft.date,
        p_amount: amount,
        p_payment_method: paymentDraft.method.trim() || null,
        p_reference_no: paymentDraft.referenceNo.trim() || null,
        p_remarks: paymentDraft.remarks.trim() || null,
      });
      if (error) throw error;

      await loadFinancialSummary(editingId, form.addaId);
      setPaymentSide(null);
      setPaymentDraft({
        date: new Date().toISOString().slice(0, 10),
        amount: "",
        method: "",
        referenceNo: "",
        remarks: "",
      });
      setSuccessMessage(
        paymentSide === "party_broker"
          ? "Bilty payment added successfully."
          : "Vehicle payment added successfully."
      );
    } catch (error) {
      console.error("Unable to add Bilty payment:", error);
      const message =
        typeof error === "object" && error !== null && "message" in error
          ? String(error.message)
          : "Unable to add payment.";
      setErrorMessage(message);
    } finally {
      setIsPaymentSaving(false);
    }
  }

  function openPrintOptions(bilty: BiltyRow) {
    setPrintBiltyTarget(bilty);
  }

  function handleLegacyPrint(
    includeBiltyDetails: boolean,
    includeVehicleDetails: boolean,
    copyType: BiltyCopyType,
    financialSummary: BiltyPrintFinancialSummary | null,
  ) {
    if (!printBiltyTarget) return;

    const printed = printBilty(
      printBiltyTarget,
      t,
      language,
      dir,
      {
        includeBiltyRsDetails: includeBiltyDetails,
        includeVehicleFreightDetails: includeVehicleDetails,
        copyType,
        financialSummary,
      }
    );

    if (!printed) {
      setErrorMessage(t("bilty.messages.popupBlocked"));
      return;
    }

    setPrintBiltyTarget(null);
  }

  const inputClass = "w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 font-medium text-slate-900 placeholder:text-slate-500 shadow-sm outline-none transition focus:border-blue-500 focus:ring-4 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-700";
  const labelClass = "mb-1.5 block text-xs font-extrabold uppercase tracking-wide text-slate-600";
  const sectionClass = "rounded-2xl border border-slate-200/80 bg-white p-4 shadow-[0_8px_26px_rgb(22_47_82_/_4%)] sm:p-5";

  const textField = (
    field: "senderName" | "senderPhone" | "receiverName" | "receiverPhone",
    labelKey: string,
    technical = false
  ) => (

    <VoiceTypingField fieldLabel={t(labelKey)} mode="text"><label key={field}>
      <span className={labelClass}>{t(labelKey)}</span>
      <input
        name={field}
        dir={technical ? "ltr" : undefined}
        value={form[field]}
        onChange={(event) => updateForm(field, event.target.value)}
        className={inputClass}
      />
    </label></VoiceTypingField>

  );

  const amountField = (
    field:
      | "freight"
      | "advanceVehicle"
      | "advanceBilty"
      | "advanceCommission"
      | "overweightCharges"
      | "detainCharges"
      | "mtChargesReceivable"
      | "mtChargesPayable"
      | "partyCommission"
      | "brokerCommission"
      | "advanceBrokerage"
      | "otherIncome"
      | "deductionAdjustment",
    labelKey: string,
    required = false
  ) => (

    <VoiceTypingField fieldLabel={t(labelKey)} mode="number"><label key={field}>
      <span className={labelClass}>{t(labelKey)}</span>
      <input
        required={required}
        name={field}
        type="number"
        min="0"
        step="0.01"
        dir="ltr"
        value={form[field]}
        onChange={(event) => updateForm(field, event.target.value)}
        className={inputClass}
      />
    </label></VoiceTypingField>

  );

  return (
    <main dir={dir} className="min-h-screen bg-slate-50 p-3 text-slate-900 sm:p-4 lg:p-6">
      <div className="mx-auto max-w-[1600px] space-y-5 sm:space-y-6">
        <header className="flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-blue-100 bg-gradient-to-r from-white via-white to-blue-50 p-5 shadow-[0_14px_40px_rgb(22_47_82_/_6%)] sm:p-6">
          <div>
            <div className="mb-2 inline-flex items-center gap-2 rounded-full border border-blue-100 bg-blue-50 px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-blue-700">
              <FileText className="h-3.5 w-3.5" aria-hidden="true" />
              UT Software
            </div>
            <h1 className="text-2xl font-black tracking-tight text-slate-950 sm:text-3xl">{t("bilty.title")}</h1>
            <p className="mt-1 max-w-3xl text-sm font-medium leading-6 text-slate-600">{t("bilty.description")}</p>
          </div>
          {isSuperAdmin && (
            <div className="inline-flex max-w-full items-center gap-2 rounded-2xl border border-blue-100 bg-white/90 px-4 py-3 shadow-sm">
              <span className="text-xs font-extrabold uppercase tracking-wide text-slate-500">{t("bilty.form.adda")}</span>
              <span className="max-w-56 truncate text-sm font-black text-blue-800">
                {addas.find((adda) => adda.id === form.addaId)?.name ?? t("bilty.form.selectAdda")}
              </span>
            </div>
          )}
        </header>

        {errorMessage && <div role="alert" className="rounded-2xl border border-rose-200 bg-rose-50 p-4 font-semibold text-rose-800 shadow-sm">{errorMessage}</div>}
        {successMessage && <div role="status" className="rounded-2xl border border-emerald-200 bg-emerald-50 p-4 font-semibold text-emerald-800 shadow-sm">{successMessage}</div>}

        <form onSubmit={saveBilty} className="space-y-5 rounded-3xl border border-slate-200/80 bg-white p-3 shadow-[0_14px_40px_rgb(22_47_82_/_6%)] sm:space-y-6 sm:p-5 lg:p-6">
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-blue-100 bg-gradient-to-r from-blue-50/90 via-white to-white px-4 py-4">
            <div className="flex items-center gap-3">
              <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-blue-600 text-white shadow-sm"><ClipboardList className="h-5 w-5" aria-hidden="true" /></span>
              <h2 className="text-lg font-black text-slate-950 sm:text-xl">{t(editingId ? "bilty.form.editTitle" : "bilty.form.createTitle")}</h2>
            </div>
            {editingId && <button type="button" onClick={resetForm} className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm font-extrabold text-slate-700 transition hover:border-blue-200 hover:bg-blue-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500">{t("common.actions.cancel")}</button>}
          </div>

          <section className={sectionClass}>
            <FormSectionHeading icon={FileText} title={t("bilty.sections.information")} />
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              <label><span className={labelClass}>{t("bilty.form.adda")}</span><select required name="addaId" value={form.addaId} onChange={(event) => { const addaId = event.target.value; selectedAddaIdRef.current = addaId; linkedEvidenceAddaIdRef.current = ""; linkedOtherAddaBookingIdsRef.current = new Set(); otherAddaDueDatesByBookingIdRef.current = {}; setLinkedOtherAddaBookingIds(new Set()); setForm((current) => ({ ...current, addaId, partyId: "", brokerId: "", vehicleId: "", groupId: "", loadingSourceOtherAddaId: "", freightReceivableOtherAddaId: "", otherAddaDueDate: "", advanceBilty: !editingId && current.freightReceivableFrom === "other_adda" ? "0" : current.advanceBilty })); if (addaId) { void loadData(); } else { loadDataRequestRef.current += 1; setIsLoading(false); void loadBrokersForAdda(""); void loadOtherAddasForAdda(""); } }} disabled={!isSuperAdmin || Boolean(editingId)} className={inputClass}><option value="">{t("bilty.form.selectAdda")}</option>{addas.map((adda) => <option key={adda.id} value={adda.id}>{adda.name}</option>)}</select></label>

              <VoiceTypingField fieldLabel={t("bilty.form.biltyNo")} mode="identifier"><label><span className={labelClass}>{t("bilty.form.biltyNo")}</span><input required name="biltyNo" dir="ltr" value={form.biltyNo} onChange={(event) => updateForm("biltyNo", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.form.date")} mode="date"><label><span className={labelClass}>{t("bilty.form.date")}</span><input required name="biltyDate" type="date" dir="ltr" value={form.biltyDate} onChange={(event) => updateForm("biltyDate", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.form.loadingDate")} mode="date"><label><span className={labelClass}>{t("bilty.form.loadingDate")}</span><input name="loadingDate" type="date" dir="ltr" value={form.loadingDate} onChange={(event) => updateForm("loadingDate", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.form.departureDate")} mode="date"><label><span className={labelClass}>{t("bilty.form.departureDate")}</span><input name="departureDate" type="date" dir="ltr" value={form.departureDate} onChange={(event) => updateForm("departureDate", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.form.arrivalDate")} mode="date"><label><span className={labelClass}>{t("bilty.form.arrivalDate")}</span><input name="arrivalDate" type="date" dir="ltr" min={form.departureDate || undefined} value={form.arrivalDate} onChange={(event) => updateForm("arrivalDate", event.target.value)} className={inputClass} /></label></VoiceTypingField>

              <label><span className={labelClass}>{t("bilty.form.tripType")}</span><select name="tripType" disabled={Boolean(editingId)} value={form.tripType} onChange={(event) => setForm((current) => ({ ...current, tripType: event.target.value as BiltyFormState["tripType"], groupId: "", vehicleId: "" }))} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}><option value="outbound">{t("bilty.tripTypes.outbound")}</option><option value="return">{t("bilty.tripTypes.return")}</option><option value="local">{t("bilty.tripTypes.local")}</option></select></label>
              {form.tripType === "outbound" ? (
                <div className="rounded-2xl border border-blue-100 bg-gradient-to-br from-blue-50 to-white p-4 xl:col-span-2">
                  <span className={labelClass}>{t("bilty.form.group")}</span>
                  <p className="font-bold text-blue-950">{editingId && form.groupId ? `${form.biltyNo} — ${t("bilty.movement.group")} ${form.groupId.replaceAll("-", "").slice(0, 6).toUpperCase()}` : `${form.biltyNo.trim() || t("bilty.form.biltyNo")} — ${t("bilty.movement.newMovementGroup")}`}</p>
                  {!editingId && <p className="mt-1 text-sm font-medium text-blue-700">{t("bilty.movement.createdOnSave")}</p>}
                </div>
              ) : (

                <div className="rounded-2xl border border-slate-200 bg-slate-50/70 p-4 xl:col-span-2">
                  <label htmlFor="bilty-group-search" className={labelClass}>{t("bilty.movement.selectOutbound")}</label>
                  <VoiceTypingField fieldLabel={t("bilty.movement.searchPlaceholder")} mode="text"><input id="bilty-group-search" type="search" value={groupSearch} onChange={(event) => setGroupSearch(event.target.value)} placeholder={t("bilty.movement.searchPlaceholder")} className={inputClass} /></VoiceTypingField>
                  <select required name="groupId" value={form.groupId} onChange={(event) => { const group = movementGroups.find((item) => item.id === event.target.value && item.adda_id === form.addaId); setForm((current) => ({ ...current, groupId: event.target.value, biltyType: "self_vehicle", vehicleId: group?.outbound_vehicle_id ?? "", externalVehicleNo: "", externalVehicleType: "", externalOwnerName: "" })); }} className={`${inputClass} mt-2`}><option value="">{t("bilty.movement.selectOutbound")}</option>{groups.map((group) => <option key={group.id} value={group.id}>{movementGroupReference(group, t("bilty.movement.group"))} — {group.outbound_vehicle_no}</option>)}</select>
                </div>

              )}
            </div>
          </section>

          <section className={sectionClass}>
            <FormSectionHeading icon={MapPin} title={t("bilty.sections.loadingFreight")} />
            <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
              <div className="rounded-2xl border border-cyan-100 bg-cyan-50/40 p-4 sm:p-5">
                <h4 className="mb-4 text-sm font-black text-cyan-950">{t("bilty.form.loadingSource")}</h4>
                <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                  <label><span className={labelClass}>{t("bilty.form.loadingSource")}</span><select required name="loadingSource" value={form.loadingSource} disabled={editingHasOtherAddaObligation} onChange={(event) => { const loadingSource = event.target.value as BiltyFormState["loadingSource"]; setForm((current) => ({ ...current, loadingSource, loadingSourceOtherAddaId: loadingSource === "other_adda" && current.loadingSource === "other_adda" ? current.loadingSourceOtherAddaId : "" })); }} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}><option value="">{t("bilty.form.select")}</option><option value="own_adda">{t("bilty.form.ownAdda")}</option><option value="other_adda">{t("bilty.form.otherAdda")}</option></select></label>
                  {form.loadingSource === "other_adda" && <label><span className={labelClass}>{t("bilty.form.loadingSourceOtherAdda")}</span><select required name="loadingSourceOtherAddaId" value={form.loadingSourceOtherAddaId} disabled={editingHasOtherAddaObligation} onChange={(event) => updateForm("loadingSourceOtherAddaId", event.target.value)} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}><option value="">{t("bilty.form.selectOtherAdda")}</option>{availableOtherAddas.map((otherAdda) => <option key={otherAdda.id} value={otherAdda.id} disabled={otherAdda.status !== "active"}>{otherAdda.adda_name}{otherAdda.status !== "active" ? " (Archived)" : ""}</option>)}</select></label>}
                </div>
              </div>
              <div className="rounded-2xl border border-indigo-100 bg-indigo-50/35 p-4 sm:p-5">
                <h4 className="mb-4 text-sm font-black text-indigo-950">{t("bilty.form.freightReceivableFrom")}</h4>
                <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                  <label><span className={labelClass}>{t("bilty.form.freightReceivableFrom")}</span><select required name="freightReceivableFrom" value={form.freightReceivableFrom} disabled={editingHasOtherAddaObligation} onChange={(event) => { const freightReceivableFrom = event.target.value as BiltyFormState["freightReceivableFrom"]; setForm((current) => ({ ...current, freightReceivableFrom, freightReceivableOtherAddaId: freightReceivableFrom === "other_adda" && current.freightReceivableFrom === "other_adda" ? current.freightReceivableOtherAddaId : "", otherAddaDueDate: freightReceivableFrom === "other_adda" && current.freightReceivableFrom === "other_adda" ? current.otherAddaDueDate : "", advanceBilty: !editingId && freightReceivableFrom === "other_adda" ? "0" : current.advanceBilty })); }} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}><option value="">{t("bilty.form.select")}</option><option value="existing_counterparty">{t("bilty.form.existingCounterparty")}</option><option value="other_adda">{t("bilty.form.otherAdda")}</option></select></label>
                  {form.freightReceivableFrom === "other_adda" && <>
                    <label><span className={labelClass}>{t("bilty.form.financialOtherAdda")}</span><select required name="freightReceivableOtherAddaId" value={form.freightReceivableOtherAddaId} disabled={editingHasOtherAddaObligation} onChange={(event) => updateForm("freightReceivableOtherAddaId", event.target.value)} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}><option value="">{t("bilty.form.selectOtherAdda")}</option>{availableOtherAddas.map((otherAdda) => <option key={otherAdda.id} value={otherAdda.id} disabled={otherAdda.status !== "active"}>{otherAdda.adda_name}{otherAdda.status !== "active" ? " (Archived)" : ""}</option>)}</select></label>

                    <VoiceTypingField fieldLabel={t("bilty.form.otherAddaDueDate")} mode="date"><label><span className={labelClass}>{t("bilty.form.otherAddaDueDate")}</span><input type="date" name="otherAddaDueDate" dir="ltr" value={form.otherAddaDueDate} disabled={editingHasOtherAddaObligation} onChange={(event) => updateForm("otherAddaDueDate", event.target.value)} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`} /></label></VoiceTypingField>

                  </>}
                </div>
              </div>
            </div>
            {editingHasOtherAddaObligation && <p role="status" className="mt-4 rounded-2xl border border-amber-200 bg-gradient-to-r from-amber-50 to-white p-4 text-sm font-semibold leading-6 text-amber-950 shadow-sm">{t("bilty.form.linkedOtherAddaFieldsLocked")}</p>}
          </section>

          <section className={sectionClass}>
            <FormSectionHeading icon={UsersRound} title={t("bilty.sections.partyBroker")} />
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
              <label><span className={labelClass}>{t("bilty.form.freightType")}</span><select name="freightType" value={form.freightType} onChange={(event) => updateForm("freightType", event.target.value as BiltyFormState["freightType"])} className={inputClass}><option value="paid">{t("bilty.freightTypes.paid")}</option><option value="advance">{t("bilty.freightTypes.advance")}</option><option value="to_pay">{t("bilty.freightTypes.toPay")}</option></select></label>
              <label><span className={labelClass}>{t("bilty.form.party")}</span><select name="partyId" value={form.partyId} onChange={(event) => updateForm("partyId", event.target.value)} className={inputClass}><option value="">{t("bilty.form.optional")}</option>{availableParties.map((party) => <option key={party.id} value={party.id}>{party.name}</option>)}</select></label>
              <label><span className={labelClass}>{t("bilty.form.broker")}</span><select name="brokerId" value={form.brokerId} onChange={(event) => updateForm("brokerId", event.target.value)} className={inputClass}><option value="">{t("bilty.form.optional")}</option>{brokers.map((broker) => <option key={broker.id} value={broker.id}>{broker.broker_name}</option>)}</select></label>

              <VoiceTypingField fieldLabel={t("bilty.form.reference")} mode="identifier"><label><span className={labelClass}>{t("bilty.form.reference")}</span><input name="referenceNo" dir="ltr" value={form.referenceNo} onChange={(event) => updateForm("referenceNo", event.target.value)} className={inputClass} /></label></VoiceTypingField>

            </div>
          </section>

          <section className={sectionClass}>
            <FormSectionHeading icon={Truck} title={t("bilty.sections.vehicle")} />
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
              <label><span className={labelClass}>{t("bilty.form.biltyType")}</span><select name="biltyType" value={groupVehicleLocked ? "self_vehicle" : form.biltyType} disabled={groupVehicleLocked} onChange={(event) => setForm((current) => ({ ...current, biltyType: event.target.value as BiltyFormState["biltyType"], vehicleId: "", externalVehicleNo: "", externalVehicleType: "", externalOwnerName: "" }))} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}><option value="self_vehicle">{t("bilty.biltyTypes.self")}</option><option value="other_vehicle">{t("bilty.biltyTypes.other")}</option></select></label>
              {effectiveBiltyType === "self_vehicle" ? (
                <>
                  <label><span className={labelClass}>{t("bilty.form.vehicle")}</span><select required name="vehicleId" value={effectiveVehicleId} disabled={groupVehicleLocked} onChange={(event) => updateForm("vehicleId", event.target.value)} className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}><option value="">{t("bilty.form.selectVehicle")}</option>{availableVehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicle_no} — {vehicle.owner_name ?? "-"}</option>)}</select>{groupVehicleLocked && <span className="mt-1 block text-xs font-bold text-blue-800">{t("bilty.movement.vehicleFromGroup")}</span>}</label>
                  <label><span className={labelClass}>{t("bilty.form.ownerName")}</span><input readOnly value={selectedVehicle?.owner_name ?? ""} placeholder={t("bilty.form.ownerAutoFilled")} className={`${inputClass} bg-slate-100`} /></label>
                </>
              ) : (
                <>

                  <VoiceTypingField fieldLabel={t("bilty.form.externalVehicleNo")} mode="identifier"><label><span className={labelClass}>{t("bilty.form.externalVehicleNo")}</span><input required name="externalVehicleNo" dir="ltr" value={form.externalVehicleNo} onChange={(event) => updateForm("externalVehicleNo", event.target.value)} className={inputClass} /></label></VoiceTypingField>


                  <VoiceTypingField fieldLabel={t("bilty.form.vehicleType")} mode="text"><label><span className={labelClass}>{t("bilty.form.vehicleType")}</span><input name="externalVehicleType" value={form.externalVehicleType} onChange={(event) => updateForm("externalVehicleType", event.target.value)} className={inputClass} /></label></VoiceTypingField>


                  <VoiceTypingField fieldLabel={t("bilty.form.ownerName")} mode="text"><label><span className={labelClass}>{t("bilty.form.ownerName")}</span><input name="externalOwnerName" value={form.externalOwnerName} onChange={(event) => updateForm("externalOwnerName", event.target.value)} className={inputClass} /></label></VoiceTypingField>

                </>
              )}
            </div>
          </section>

          <section className={sectionClass}>
            <FormSectionHeading icon={MapPin} title={t("bilty.sections.route")} />
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
              <LocationSearchField required label={t("bilty.form.fromSearch")} placeholder={t("bilty.form.searchLocation")} noResults={t("bilty.form.noMatchingLocation")} searchFailed={t("bilty.form.locationSearchFailed")} clearLabel={t("bilty.form.clearLocation")} value={form.fromLocationSearch} selectedId={form.fromLocationId} onChange={(fromLocationSearch, fromLocationId) => setForm((current) => ({ ...current, fromLocationSearch, fromLocationId }))} />
              <LocationSearchField required label={t("bilty.form.toSearch")} placeholder={t("bilty.form.searchLocation")} noResults={t("bilty.form.noMatchingLocation")} searchFailed={t("bilty.form.locationSearchFailed")} clearLabel={t("bilty.form.clearLocation")} value={form.toLocationSearch} selectedId={form.toLocationId} onChange={(toLocationSearch, toLocationId) => setForm((current) => ({ ...current, toLocationSearch, toLocationId }))} />
              {textField("senderName", "bilty.form.senderName")}
              {textField("senderPhone", "bilty.form.senderPhone", true)}
              {textField("receiverName", "bilty.form.receiverName")}
              {textField("receiverPhone", "bilty.form.receiverPhone", true)}
            </div>
          </section>

          <details className={sectionClass}>
            <summary className="flex cursor-pointer list-none items-center gap-3 rounded-xl text-lg font-black text-slate-950 marker:hidden focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500">
              <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-violet-50 text-violet-700"><Package className="h-5 w-5" aria-hidden="true" /></span>
              <span>{t("bilty.container.title")}</span>
            </summary>
            <p className="mt-3 border-b border-slate-100 pb-4 text-sm font-medium text-slate-600">{t("bilty.container.description")}</p>
            <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">

              <VoiceTypingField fieldLabel={t("bilty.container.number")} mode="identifier"><label><span className={labelClass}>{t("bilty.container.number")}</span><input name="containerNo" dir="ltr" value={form.containerNo} onChange={(event) => updateForm("containerNo", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.container.size")} mode="text"><label><span className={labelClass}>{t("bilty.container.size")}</span><input name="containerSize" dir="ltr" value={form.containerSize} onChange={(event) => updateForm("containerSize", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.container.weight")} mode="number"><label><span className={labelClass}>{t("bilty.container.weight")}</span><input name="containerWeight" type="number" min="0" step="any" dir="ltr" value={form.containerWeight} onChange={(event) => updateForm("containerWeight", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.container.serial")} mode="identifier"><label><span className={labelClass}>{t("bilty.container.serial")}</span><input name="containerSerial" dir="ltr" value={form.containerSerial} onChange={(event) => updateForm("containerSerial", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.container.port")} mode="text"><label><span className={labelClass}>{t("bilty.container.port")}</span><input name="containerPort" value={form.containerPort} onChange={(event) => updateForm("containerPort", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.container.clearingAgent")} mode="text"><label><span className={labelClass}>{t("bilty.container.clearingAgent")}</span><input name="clearingAgent" value={form.clearingAgent} onChange={(event) => updateForm("clearingAgent", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.container.shippingLine")} mode="text"><label><span className={labelClass}>{t("bilty.container.shippingLine")}</span><input name="shippingLine" value={form.shippingLine} onChange={(event) => updateForm("shippingLine", event.target.value)} className={inputClass} /></label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("bilty.container.cargo")} mode="text"><label><span className={labelClass}>{t("bilty.container.cargo")}</span><input name="containerCargo" value={form.containerCargo} onChange={(event) => updateForm("containerCargo", event.target.value)} className={inputClass} /></label></VoiceTypingField>

            </div>
          </details>

          <section className={sectionClass} aria-labelledby="bilty-financial-title">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div className="flex items-center gap-3">
                  <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-50 text-emerald-700"><Wallet className="h-5 w-5" aria-hidden="true" /></span>
                  <h3 id="bilty-financial-title" className="text-lg font-black text-slate-950">
                    {t("bilty.financial.title")}
                  </h3>
                </div>
                <p className="mt-2 text-sm font-medium text-slate-600">
                  {isOtherAddaReceivable
                    ? "Other Adda settlements are managed separately through the Other Adda account."
                    : "Private Adda financial values. Later payments are preserved as payment history."}
                </p>
              </div>
              {editingId && (
                <div className="text-sm font-semibold text-slate-600">
                  {isFinancialSummaryLoading
                    ? (isOtherAddaReceivable ? "Loading vehicle payment totals..." : "Loading payment totals...")
                    : (isOtherAddaReceivable ? "Vehicle payment totals loaded" : "Payment totals loaded")}
                </div>
              )}
            </div>

            <div className="mt-5">
              <h4 className="mb-3 text-base font-black text-blue-900">
                {isOtherAddaReceivable ? "Other Adda Receivable" : "Party / Broker Side"}
              </h4>
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">

                <VoiceTypingField fieldLabel="freight" mode="amount"><label>
                  <span className={labelClass}>{isOtherAddaReceivable ? "Other Adda Receivable Freight" : "Total Bilty Rs"}</span>
                  <input
                    required
                    name="freight"
                    type="number"
                    min="0"
                    step="0.01"
                    dir="ltr"
                    value={form.freight}
                    onChange={(event) => updateForm("freight", event.target.value)}
                    disabled={editingHasOtherAddaObligation}
                    className={`${inputClass} disabled:cursor-not-allowed disabled:bg-slate-100`}
                  />
                </label></VoiceTypingField>

                {isOtherAddaReceivable ? (
              <div className="rounded-2xl border border-indigo-200 bg-gradient-to-br from-indigo-50 to-white p-4 text-sm font-semibold leading-6 text-indigo-950 lg:col-span-3">
                    <p>Other Adda settlements are recorded in the Other Adda account through Phase 3B.</p>
                    {Number(form.advanceBilty || 0) > 0 && editingId && (
                      <p className="mt-1">Stored legacy Bilty advance: Rs. {formatMoney(Number(form.advanceBilty))}. This is not counted as an Other Adda settlement.</p>
                    )}
                  </div>
                ) : (
                  <>

                    <VoiceTypingField fieldLabel="Bilty Advance Received" mode="amount"><label>
                      <span className={labelClass}>Bilty Advance Received</span>
                      <input
                        name="advanceBilty"
                        type="number"
                        min="0"
                        step="0.01"
                        dir="ltr"
                        value={form.advanceBilty}
                        onChange={(event) => updateForm("advanceBilty", event.target.value)}
                        className={inputClass}
                      />
                    </label></VoiceTypingField>


                    <div className="rounded-2xl border border-slate-200 bg-slate-50/80 p-4 shadow-sm">
                      <span className={labelClass}>Later Payments</span>
                      <div dir="ltr" className="text-lg font-black text-slate-950">
                        Rs. {formatMoney(laterReceived)}
                      </div>
                      <button
                        type="button"
                        onClick={() => openPayment("party_broker")}
                        disabled={!editingId}
                        className="mt-3 w-full rounded-xl bg-emerald-600 px-3 py-2.5 text-sm font-extrabold text-white shadow-sm transition hover:bg-emerald-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-600"
                      >
                        Update Bilty Payment
                      </button>
                      {!editingId && (
                        <p className="mt-1 text-xs font-semibold text-slate-500">Available after Bilty is saved.</p>
                      )}
                    </div>

                    <div className="rounded-2xl border border-emerald-100 bg-emerald-50/50 p-4 shadow-sm">
                      <span className={labelClass}>Total Received [AUTO]</span>
                      <div dir="ltr" className="text-lg font-black text-emerald-700">
                        Rs. {formatMoney(totalReceived)}
                      </div>
                    </div>

                    <div className="rounded-2xl border border-amber-100 bg-amber-50/50 p-4 shadow-sm">
                      <span className={labelClass}>Balance Receivable [AUTO]</span>
                      <div dir="ltr" className="text-lg font-black text-amber-700">
                        Rs. {formatMoney(balanceReceivable)}
                      </div>
                    </div>

                    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
                      <span className={labelClass}>Status [AUTO]</span>
                      <div
                        className={`inline-flex rounded-full px-3 py-1 text-sm font-black ${
                          paymentStatus === "PAID"
                            ? "bg-emerald-100 text-emerald-800"
                            : paymentStatus === "PARTIAL"
                              ? "bg-amber-100 text-amber-800"
                              : "bg-red-100 text-red-800"
                        }`}
                      >
                        {paymentStatus}
                      </div>
                    </div>
                  </>
                )}
              </div>
            </div>

            <div className="mt-6 border-t border-slate-200 pt-5">
              <h4 className="mb-3 text-base font-black text-blue-900">Vehicle Side</h4>
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">

                <VoiceTypingField fieldLabel={t("bilty.financial.originalVehicleFreight")} mode="amount"><label>
                  <span className={labelClass}>{t("bilty.financial.originalVehicleFreight")}</span>
                  <input
                    required
                    name="vehicleFreight"
                    type="number"
                    min="0"
                    step="0.01"
                    dir="ltr"
                    value={vehicleFreight}
                    onChange={(event) => setVehicleFreight(event.target.value)}
                    className={inputClass}
                  />
                </label></VoiceTypingField>


                {amountField("advanceVehicle", "bilty.financial.advanceVehicle")}

                <div className="rounded-2xl border border-slate-200 bg-slate-50/80 p-4 shadow-sm">
                  <span className={labelClass}>Later Vehicle Payments</span>
                  <div dir="ltr" className="text-lg font-black text-slate-950">
                    Rs. {formatMoney(laterVehiclePaid)}
                  </div>
                  <button
                    type="button"
                    onClick={() => openPayment("vehicle")}
                    disabled={!editingId}
                    className="mt-3 w-full rounded-xl bg-emerald-600 px-3 py-2.5 text-sm font-extrabold text-white shadow-sm transition hover:bg-emerald-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-600"
                  >
                    Update Vehicle Payment
                  </button>
                  {!editingId && (
                    <p className="mt-1 text-xs font-semibold text-slate-500">Available after Bilty is saved.</p>
                  )}
                </div>

                <div className="rounded-2xl border border-emerald-100 bg-emerald-50/50 p-4 shadow-sm">
                  <span className={labelClass}>{t("bilty.financial.actualVehicleCashPaid")}</span>
                  <div dir="ltr" className="text-lg font-black text-emerald-700">
                    Rs. {formatMoney(totalVehiclePaid)}
                  </div>
                </div>

                <div className="rounded-2xl border border-violet-100 bg-violet-50/50 p-4 shadow-sm">
                  <span className={labelClass}>{t("bilty.financial.parchiWithheldCommission")}</span>
                  <div dir="ltr" className="text-lg font-black text-violet-800">
                    {vehicleSettlementVerified ? `Rs. ${formatMoney(parchiVehicleWithheld)}` : t("driverLedger.notRecorded")}
                  </div>
                </div>

                <div className="rounded-2xl border border-blue-100 bg-blue-50/50 p-4 shadow-sm">
                  <span className={labelClass}>{t("bilty.financial.vehicleEntitlementSettled")}</span>
                  <div dir="ltr" className="text-lg font-black text-blue-900">
                    {vehicleEntitlementSettled === null ? t("driverLedger.notRecorded") : `Rs. ${formatMoney(vehicleEntitlementSettled)}`}
                  </div>
                </div>

                <div className="rounded-2xl border border-amber-100 bg-amber-50/50 p-4 shadow-sm">
                  <span className={labelClass}>{t("bilty.financial.vehicleOutstanding")}</span>
                  <div dir="ltr" className="text-lg font-black text-amber-700">
                    {vehicleBalance === null ? t("driverLedger.notRecorded") : `Rs. ${formatMoney(vehicleBalance)}`}
                  </div>
                  {vehicleSettlementVerified && vehicleEntitlementSettled !== null && <p className="mt-1 text-xs font-bold text-amber-900">{t(`vehicleLedger.filters.status.${vehicleEntitlementSettled <= 0 ? "unpaid" : vehicleBalance === 0 ? "paid" : "partial"}`)}</p>}
                </div>

                <div className="rounded-2xl border border-blue-200 bg-gradient-to-br from-blue-50 to-white p-4 shadow-sm">
                  <span className={labelClass}>Adda Commission [AUTO]</span>
                  <div dir="ltr" className="text-lg font-black text-blue-900">
                    Rs. {formatMoney(addaCommission)}
                  </div>
                  <p className="mt-1 text-xs font-semibold text-blue-700">
                    Total Bilty Rs − Vehicle Freight
                  </p>
                </div>
              </div>
            </div>

            <div className="mt-6 border-t border-slate-100 pt-5">
              <h4 className="mb-3 text-base font-black text-blue-900">Vehicle Freight Adjustments</h4>
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
                {amountField("brokerCommission", "bilty.financial.brokerCommission")}
                {amountField("overweightCharges", "bilty.financial.overweightCharges")}
                {amountField("detainCharges", "bilty.financial.detainCharges")}

                <VoiceTypingField fieldLabel={t("bilty.financial.loloCharges")} mode="amount"><label>
                  <span className={labelClass}>{t("bilty.financial.loloCharges")}</span>
                  <input
                    name="loloCharges"
                    type="number"
                    min="0"
                    step="0.01"
                    dir="ltr"
                    value={loloCharges}
                    onChange={(event) => setLoloCharges(event.target.value)}
                    className={inputClass}
                  />
                </label></VoiceTypingField>


              </div>
            </div>

            <div className="mt-6 grid grid-cols-1 gap-4 rounded-2xl border border-blue-100 bg-gradient-to-br from-slate-50 to-blue-50/50 p-4 sm:p-5 lg:grid-cols-3">
              {!isOtherAddaReceivable && (
                <div className="rounded-2xl border border-blue-100 bg-white p-4 shadow-sm">
                  <h4 className="mb-2 font-black text-slate-950">Party / Broker Summary</h4>
                  <div className="space-y-1 text-sm font-semibold">
                    <p>Total Bilty Rs: <span dir="ltr">Rs. {formatMoney(totalBiltyRs)}</span></p>
                    <p>Advance Received: <span dir="ltr">Rs. {formatMoney(advanceReceived)}</span></p>
                    <p>Later Payments: <span dir="ltr">Rs. {formatMoney(laterReceived)}</span></p>
                    <p>Total Received: <span dir="ltr">Rs. {formatMoney(totalReceived)}</span></p>
                    <p>Balance Receivable: <span dir="ltr">Rs. {formatMoney(balanceReceivable)}</span></p>
                    <p>Status: {paymentStatus}</p>
                  </div>
                </div>
              )}

                <div className="rounded-2xl border border-emerald-100 bg-white p-4 shadow-sm">
                <h4 className="mb-2 font-black text-slate-950">Vehicle Summary</h4>
                <div className="space-y-1 text-sm font-semibold">
                  <p>{t("bilty.financial.originalVehicleFreight")}: <span dir="ltr">Rs. {formatMoney(vehicleFreightAmount)}</span></p>
                  <p>{t("bilty.financial.brokerCommission")}: <span dir="ltr">-Rs. {formatMoney(brokerCommissionAmount)}</span></p>
                  <p>{t("bilty.financial.overweightCharges")}: <span dir="ltr">+Rs. {formatMoney(overweightChargesAmount)}</span></p>
                  <p>{t("bilty.financial.loloCharges")}: <span dir="ltr">+Rs. {formatMoney(loloChargesAmount)}</span></p>
                  <p>{t("bilty.financial.detainCharges")}: <span dir="ltr">+Rs. {formatMoney(detainChargesAmount)}</span></p>
                  <p className="font-black">{t("bilty.financial.adjustedVehicleFreight")}: <span dir="ltr">Rs. {formatMoney(adjustedVehicleFreight)}</span></p>
                  <p>Advance Vehicle: <span dir="ltr">Rs. {formatMoney(advanceVehicleAmount)}</span></p>
                  <p>Later Vehicle Payments: <span dir="ltr">Rs. {formatMoney(laterVehiclePaid)}</span></p>
                  <p>{t("bilty.financial.actualVehicleCashPaid")}: <span dir="ltr">Rs. {formatMoney(totalVehiclePaid)}</span></p>
                  <p>{t("bilty.financial.parchiWithheldCommission")}: <span dir="ltr">{vehicleSettlementVerified ? `Rs. ${formatMoney(parchiVehicleWithheld)}` : t("driverLedger.notRecorded")}</span></p>
                  <p>{t("bilty.financial.vehicleEntitlementSettled")}: <span dir="ltr">{vehicleEntitlementSettled === null ? t("driverLedger.notRecorded") : `Rs. ${formatMoney(vehicleEntitlementSettled)}`}</span></p>
                  <p>{t("bilty.financial.vehicleOutstanding")}: <span dir="ltr">{vehicleBalance === null ? t("driverLedger.notRecorded") : `Rs. ${formatMoney(vehicleBalance)}`}</span></p>
                </div>
              </div>

                <div className="rounded-2xl border border-violet-100 bg-white p-4 shadow-sm">
                <h4 className="mb-2 font-black text-slate-950">Other Summary</h4>
                <div className="space-y-1 text-sm font-semibold">
                  <p>Adda Commission: <span dir="ltr">Rs. {formatMoney(addaCommission)}</span></p>
                </div>
              </div>
            </div>
          </section>

          <section className={sectionClass}>
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
              <FormSectionHeading icon={Package} title={t("bilty.items.title")} />
              <button type="button" onClick={addItem} className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 font-extrabold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"><Plus size={18} aria-hidden="true" />{t("bilty.items.add")}</button>
            </div>
            <p className="-mt-2 mb-4 text-sm font-medium text-slate-600">{t("bilty.items.description")}</p>
            <div className="space-y-3">
              {form.items.map((item, index) => (
                <div key={item.clientId} className="grid grid-cols-1 gap-3 rounded-2xl border border-slate-200 bg-slate-50/60 p-3 sm:p-4 md:grid-cols-2 lg:grid-cols-6">

                  <VoiceTypingField fieldLabel={t("bilty.items.goods")} mode="text"><label className="lg:col-span-2"><span className={labelClass}>{t("bilty.items.goods")}</span><input required name={`items.${index}.goodsName`} value={item.goodsName} onChange={(event) => updateItem(item.clientId, "goodsName", event.target.value)} className={inputClass} /></label></VoiceTypingField>


                  <VoiceTypingField fieldLabel={t("common.quantity")} mode="number"><label><span className={labelClass}>{t("common.quantity")}</span><input required name={`items.${index}.quantity`} type="number" min="0.000001" step="any" dir="ltr" value={item.quantity} onChange={(event) => updateItem(item.clientId, "quantity", event.target.value)} className={inputClass} /></label></VoiceTypingField>


                  <VoiceTypingField fieldLabel={t("common.weight")} mode="number"><label><span className={labelClass}>{t("common.weight")}</span><input name={`items.${index}.weight`} type="number" min="0" step="any" dir="ltr" value={item.weight} onChange={(event) => updateItem(item.clientId, "weight", event.target.value)} className={inputClass} /></label></VoiceTypingField>


                  <VoiceTypingField fieldLabel={t("common.unit")} mode="text"><label><span className={labelClass}>{t("common.unit")}</span><input required name={`items.${index}.unit`} value={item.unit} onChange={(event) => updateItem(item.clientId, "unit", event.target.value)} className={inputClass} /></label></VoiceTypingField>

                  <div className="flex items-end gap-2">
                  <VoiceTypingField fieldLabel={t("common.remarks")} mode="text"><label className="min-w-0 flex-1"><span className={labelClass}>{t("common.remarks")}</span><input name={`items.${index}.remarks`} value={item.remarks} onChange={(event) => updateItem(item.clientId, "remarks", event.target.value)} className={inputClass} /></label></VoiceTypingField>
                  <button type="button" aria-label={`${t("bilty.items.remove")} ${index + 1}`} disabled={form.items.length === 1} onClick={() => removeItem(item.clientId)} className="rounded-lg border border-red-300 bg-white p-3 text-red-700 hover:bg-red-50 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-500"><Trash2 size={18} aria-hidden="true" /></button></div>
                </div>
              ))}
            </div>
          </section>

          <button type="submit" disabled={isSaving} className="min-h-12 w-full rounded-2xl bg-gradient-to-r from-blue-700 to-blue-600 px-5 py-3.5 font-black text-white shadow-lg shadow-blue-900/10 transition hover:from-blue-800 hover:to-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:from-blue-300 disabled:to-blue-300 disabled:text-slate-800">{isSaving ? t("common.states.saving") : t(editingId ? "bilty.form.update" : "bilty.form.save")}</button>
        </form>

        <section className="rounded-3xl border border-slate-200/80 bg-white p-3 shadow-[0_14px_40px_rgb(22_47_82_/_6%)] sm:p-4 md:p-6">
          <div className="mb-5 space-y-4">
            <div className="flex items-center gap-3">
              <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-50 text-blue-700"><ClipboardList className="h-5 w-5" aria-hidden="true" /></span>
              <div><h2 className="text-xl font-black tracking-tight text-slate-950">{t("bilty.list.title")}</h2><p className="mt-0.5 text-sm font-medium text-slate-500">{t("bilty.description")}</p></div>
            </div>
            <div className="grid grid-cols-1 gap-3 rounded-2xl border border-slate-200 bg-slate-50/70 p-3 sm:p-4 md:grid-cols-2 xl:grid-cols-5">

              <VoiceTypingField fieldLabel={t("bilty.list.search")} mode="text"><label><span className={labelClass}>{t("common.actions.search")}</span><input type="search" name="biltySearch" placeholder={t("bilty.list.search")} value={search} onChange={(event) => setSearch(event.target.value)} className={inputClass} /></label></VoiceTypingField>

              <label><span className={labelClass}>{t("bilty.form.tripType")}</span><select value={tripFilter} onChange={(event) => setTripFilter(event.target.value)} className={inputClass}><option value="">{t("bilty.filters.all")}</option><option value="outbound">{t("bilty.tripTypes.outbound")}</option><option value="return">{t("bilty.tripTypes.return")}</option><option value="local">{t("bilty.tripTypes.local")}</option></select></label>
              <label><span className={labelClass}>{t("bilty.form.freightType")}</span><select value={freightFilter} onChange={(event) => setFreightFilter(event.target.value)} className={inputClass}><option value="">{t("bilty.filters.all")}</option><option value="paid">{t("bilty.freightTypes.paid")}</option><option value="advance">{t("bilty.freightTypes.advance")}</option><option value="to_pay">{t("bilty.freightTypes.toPay")}</option></select></label>
              <label><span className={labelClass}>{t("bilty.form.biltyType")}</span><select value={vehicleTypeFilter} onChange={(event) => setVehicleTypeFilter(event.target.value)} className={inputClass}><option value="">{t("bilty.filters.all")}</option><option value="self_vehicle">{t("bilty.biltyTypes.self")}</option><option value="other_vehicle">{t("bilty.biltyTypes.other")}</option></select></label>
              <button type="button" onClick={() => { setSearch(""); setTripFilter(""); setFreightFilter(""); setVehicleTypeFilter(""); }} className="min-h-11 self-end rounded-xl border border-slate-200 bg-white px-4 py-2.5 font-extrabold text-slate-700 shadow-sm transition hover:border-blue-200 hover:bg-blue-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500">{t("common.actions.reset")}</button>
            </div>
          </div>
          {listVehicleSettlementLoadFailed && <p role="status" className="mb-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-semibold text-amber-900">{t("bilty.states.vehicleSettlementUnavailable")}</p>}
          {isLoading ? <p role="status" className="rounded-2xl border border-slate-100 bg-slate-50 px-4 py-8 text-center font-semibold text-slate-600">{t("bilty.states.loading")}</p> : visibleBilties.length === 0 ? <p className="rounded-2xl border border-dashed border-slate-200 bg-slate-50 px-4 py-8 text-center font-semibold text-slate-600">{t("bilty.states.empty")}</p> : (
            <div className="overflow-x-auto rounded-2xl border border-slate-200 shadow-sm">
              <table className="w-full min-w-[1400px] border-collapse bg-white text-sm">
                <thead className="bg-slate-900 text-white"><tr>{["number", "date", "group", "party", "route", "trip", "freightType", "vehicle", "vehicleSettlement", "status", "items", "actions"].map((key) => <th key={key} scope="col" className="whitespace-nowrap px-4 py-3.5 text-start text-xs font-extrabold uppercase tracking-wide">{t(`bilty.table.${key}`)}</th>)}</tr></thead>
                <tbody className="divide-y divide-slate-100">{visibleBilties.map((bilty) => {
               const vehicle = relation(bilty.vehicles);
               const party = relation(bilty.parties)?.name;
               const broker = relation(bilty.brokers)?.broker_name;
               const from = relation(bilty.from_location)?.name ?? bilty.from_city;
               const to = relation(bilty.to_location)?.name ?? bilty.to_city;
               const vehicleSettlement = listVehicleSettlementByBooking.get(bilty.id);
               return <tr key={bilty.id} className="transition-colors hover:bg-blue-50/40">
                 <td dir="ltr" className="whitespace-nowrap px-4 py-3.5 font-extrabold text-blue-900">{bilty.booking_no}</td>
                 <td dir="ltr" className="whitespace-nowrap px-4 py-3.5 text-slate-600">{bilty.booking_date}</td>
                 <td dir="ltr" className="whitespace-nowrap px-4 py-3.5 font-semibold text-slate-600">{bilty.movement_group ? movementGroupReference(bilty.movement_group, t("bilty.movement.group")) : "-"}</td>
                 <td className="max-w-52 px-4 py-3.5"><span className="block truncate font-bold text-slate-800">{party || broker || "-"}</span>{party && broker && <span className="mt-0.5 block truncate text-xs font-medium text-slate-500">{broker}</span>}</td>
                 <td className="whitespace-nowrap px-4 py-3.5 text-slate-700"><span className="font-semibold">{from ?? "-"}</span><span className="mx-2 text-blue-400">→</span><span className="font-semibold">{to ?? "-"}</span></td>
                 <td className="whitespace-nowrap px-4 py-3.5">{bilty.trip_type ? <span className="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-extrabold text-blue-800">{t(`bilty.tripTypes.${bilty.trip_type}`)}</span> : <span className="text-slate-500">{t("bilty.legacy")}</span>}</td>
                 <td className="whitespace-nowrap px-4 py-3.5">{bilty.freight_type ? <span className="rounded-full bg-violet-50 px-2.5 py-1 text-xs font-extrabold text-violet-800">{t(`bilty.freightTypes.${bilty.freight_type}`)}</span> : <span className="text-slate-500">{t("bilty.legacy")}</span>}</td>
                 <td dir="ltr" className="whitespace-nowrap px-4 py-3.5 font-semibold text-slate-700">{vehicle?.vehicle_no ?? bilty.external_vehicle_no ?? "-"}</td>
                 <td className="px-4 py-3.5 text-xs"><div>{t("bilty.financial.actualVehicleCashPaid")}: <span dir="ltr" className="font-semibold">{vehicleSettlement ? formatMoney(vehicleSettlement.actualCashPaid) : t("driverLedger.notRecorded")}</span></div><div className="mt-1">{t("bilty.financial.parchiWithheldCommission")}: <span dir="ltr" className="font-semibold">{vehicleSettlement ? formatMoney(vehicleSettlement.parchiWithheldCommission) : t("driverLedger.notRecorded")}</span></div><div className="mt-1">{t("bilty.financial.vehicleEntitlementSettled")}: <span dir="ltr" className="font-bold">{vehicleSettlement ? formatMoney(vehicleSettlement.entitlementSettled) : t("driverLedger.notRecorded")}</span></div><div className="mt-1">{t("bilty.financial.vehicleOutstanding")}: <span dir="ltr" className="font-bold">{vehicleSettlement ? formatMoney(vehicleSettlement.outstanding) : t("driverLedger.notRecorded")}</span>{vehicleSettlement && <span className="ms-2 font-bold">{t(`vehicleLedger.filters.status.${vehicleSettlement.status.toLowerCase()}`)}</span>}</div></td>
                 <td className="whitespace-nowrap px-4 py-3.5"><span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-extrabold uppercase text-slate-700">{bilty.status ?? t("bilty.legacy")}</span></td>
                 <td dir="ltr" className="px-4 py-3.5 text-center font-semibold text-slate-600">{bilty.bilty_items?.length ?? 0}</td>
                 <td className="px-4 py-3.5"><div className="flex min-w-max flex-nowrap gap-2"><button type="button" onClick={() => setSelectedBilty(bilty)} aria-label={`${t("bilty.actions.view")} ${bilty.booking_no}`} className="inline-flex items-center gap-1.5 rounded-xl border border-blue-100 bg-blue-50 px-3 py-2 font-extrabold text-blue-800 transition hover:bg-blue-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"><Eye size={16} aria-hidden="true" />{t("bilty.actions.view")}</button><button type="button" onClick={() => void editBilty(bilty)} disabled={isLoading} aria-label={`${t("common.actions.edit")} ${bilty.booking_no}`} className="inline-flex items-center gap-1.5 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 font-extrabold text-amber-800 transition hover:bg-amber-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500 disabled:cursor-not-allowed disabled:opacity-50"><Pencil size={16} aria-hidden="true" />{t("common.actions.edit")}</button><button type="button" onClick={() => openPrintOptions(bilty)} aria-label={`${t("bilty.actions.print")} ${bilty.booking_no}`} className="inline-flex items-center gap-1.5 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 font-extrabold text-emerald-800 transition hover:bg-emerald-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500"><Printer size={16} aria-hidden="true" />{t("bilty.actions.print")}</button></div></td>
               </tr>;
            })}</tbody></table></div>
          )}
        </section>
      </div>

      {selectedBilty && <BiltyDetailsModal bilty={selectedBilty} onClose={() => setSelectedBilty(null)} onPrint={() => openPrintOptions(selectedBilty)} />}

      {selectedChakkarBilties && (
        <ChakkarDetailsModal
          bilties={selectedChakkarBilties}
          onClose={() => setSelectedChakkarBilties(null)}
        />
      )}

      {printBiltyTarget && (
        <BiltyTemplatePrint
          key={`${printBiltyTarget.adda_id}:${printBiltyTarget.id}`}
          bilty={printBiltyTarget}
          language={language === "ur" ? "ur" : "en"}
          onClose={() => setPrintBiltyTarget(null)}
          onLegacyPrint={handleLegacyPrint}
        />
      )}

      {paymentSide && !(paymentSide === "party_broker" && isOtherAddaReceivable) && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/65 p-3 backdrop-blur-sm sm:p-4">
          <div className="w-full max-w-lg rounded-3xl border border-slate-200 bg-white p-4 shadow-2xl sm:p-6">
            <div className="mb-4 flex items-start justify-between gap-3">
              <div>
                <h3 className="text-xl font-black text-slate-950">
                  {paymentSide === "party_broker" ? "Update Bilty Payment" : "Update Vehicle Payment"}
                </h3>
                <p className="mt-1 text-sm font-medium text-slate-600">
                  A new history entry will be added. Existing payment amounts are not overwritten.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setPaymentSide(null)}
                className="rounded-xl border border-slate-200 px-3 py-2 font-extrabold text-slate-700 transition hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
              >
                Close
              </button>
            </div>

            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">

              <VoiceTypingField fieldLabel="Date" mode="date"><label>
                <span className={labelClass}>Date</span>
                <input
                  type="date"
                  value={paymentDraft.date}
                  onChange={(event) => setPaymentDraft((current) => ({ ...current, date: event.target.value }))}
                  className={inputClass}
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Amount" mode="amount"><label>
                <span className={labelClass}>Amount</span>
                <input
                  type="number"
                  min="0.01"
                  step="0.01"
                  dir="ltr"
                  value={paymentDraft.amount}
                  onChange={(event) => setPaymentDraft((current) => ({ ...current, amount: event.target.value }))}
                  className={inputClass}
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Payment Method" mode="text"><label>
                <span className={labelClass}>Payment Method</span>
                <input
                  value={paymentDraft.method}
                  onChange={(event) => setPaymentDraft((current) => ({ ...current, method: event.target.value }))}
                  placeholder="Cash / Bank / Online"
                  className={inputClass}
                />
              </label></VoiceTypingField>



              <VoiceTypingField fieldLabel="Reference No" mode="identifier"><label>
                <span className={labelClass}>Reference No</span>
                <input
                  dir="ltr"
                  value={paymentDraft.referenceNo}
                  onChange={(event) => setPaymentDraft((current) => ({ ...current, referenceNo: event.target.value }))}
                  className={inputClass}
                />
              </label></VoiceTypingField>


              <label className="md:col-span-2">
                <span className={labelClass}>Remarks</span>
                <VoiceTypingField fieldLabel={t("common.remarks")} value={paymentDraft.remarks} onValueChange={(remarks) => setPaymentDraft((current) => ({ ...current, remarks }))} contextKey={selectedBilty?.id ?? ""}>
                  <textarea
                    value={paymentDraft.remarks}
                    onChange={(event) => setPaymentDraft((current) => ({ ...current, remarks: event.target.value }))}
                    className={`${inputClass} min-h-24`}
                  />
                </VoiceTypingField>
              </label>
            </div>

            <button
              type="button"
              onClick={() => void saveLaterPayment()}
              disabled={isPaymentSaving}
              className="mt-5 min-h-12 w-full rounded-2xl bg-emerald-600 px-4 py-3 font-black text-white shadow-sm transition hover:bg-emerald-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:bg-emerald-300"
            >
              {isPaymentSaving ? "Saving Payment..." : "Save Payment"}
            </button>
          </div>
        </div>
      )}
    </main>
  );
}

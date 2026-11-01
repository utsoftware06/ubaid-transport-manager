"use client";


import { useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import ExpenseForm, { type VoucherMovementOption, type VoucherMovementSummary } from "@/components/expenses/ExpenseForm";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import ExpenseItems from "@/components/expenses/ExpenseItems";
import {
  createEmptyVoucherWorkshopData,
  type VoucherWorkshopCreateData,
  type VoucherWorkshopMasterOption,
  type VoucherWorkshopMode,
  type VoucherWorkshopOption,
} from "@/components/expenses/VoucherWorkshopSelector";
import VoucherWorkshopSelector from "@/components/expenses/VoucherWorkshopSelector";
import VoucherOilSelector from "@/components/expenses/VoucherOilSelector";
import ManualWorkshopEditModal from "@/components/expenses/ManualWorkshopEditModal";
import ManualOilEditModal from "@/components/expenses/ManualOilEditModal";
import VoucherTyreSelector from "@/components/expenses/VoucherTyreSelector";
import type {
  VoucherOilCreatePayload,
  VoucherOilOption,
  VoucherOilProductOption,
  VoucherOilShopOption,
} from "@/components/expenses/VoucherOilSelector";
import type {
  VoucherTyreCreatePayload,
  VoucherTyreOption,
  VoucherTyreShopOption,
} from "@/components/expenses/VoucherTyreSelector";
import type {
  TyreAsset,
  TyrePosition,
  TyreProduct,
} from "@/components/tyre/types";
import type { VoucherDriverEarningOption } from "@/components/expenses/VoucherDriverEarningSelector";
import {
  EXPENSE_TYPES_BY_CLASS,
  expenseTypeLabelKey,
  normalizeExpenseClass,
  type ExpenseClass,
} from "@/components/expenses/expenseClassification";
import ExpenseTable from "@/components/expenses/ExpenseTable";
import VoucherAdjustmentModal from "@/components/expenses/VoucherAdjustmentModal";
import ManualVoucherAdjustmentModal, { type ManualVoucherAdjustment } from "@/components/expenses/ManualVoucherAdjustmentModal";
import VoucherTemplatePrint from "@/components/expenses/VoucherTemplatePrint";
import {
  createVoucherPrintPresentation,
  resolveVoucherPrintOwnerAddaId,
  type VoucherPrintExpense,
  type VoucherPrintPresentation,
  type VoucherPrintSourceReference,
} from "@/lib/print/voucherPresentation";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { getInclusiveManualChakkarDays, getManualVoucherDateState } from "@/lib/expenses/manualVoucherDates";
import { getParchiVehicleSettlementTotalsForBookings } from "@/lib/parchi/vehicleSettlement";

type ReceiptStatus = "idle" | "uploading" | "replacing" | "deleting";
type ManualVoucherSourceEditTarget =
  | { kind: "workshop"; id: number }
  | { kind: "oil"; id: string };

class VoucherFinalizationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VoucherFinalizationError";
  }
}

type ExpenseItemRow = {
  rowId: number;
  dbId?: number;
  expenseClass: ExpenseClass;
  expenseType: string;
  amount: string;
  paymentMethod: string;
  remarks: string;
  receiptUrl: string | null;
  receiptName: string | null;
  receiptFile: File | null;
  receiptStatus: ReceiptStatus;
  receiptError: string;
  petrolPumpId: string;
  liters: string;
  rate: string;
  paidAmount: string;
  slipNo: string;
};

type VehicleRelation = {
  vehicle_no: string | null;
  owner_name?: string | null;
};

type DriverRelation = {
  name: string | null;
};

type BookingRelation = {
  id: string;
  adda_id: string | null;
  vehicle_id?: string | null;
  booking_no?: string | null;
  trip_type?: string | null;
  bilty_group_id?: string | null;
  departure_date?: string | null;
  arrival_date?: string | null;
  freight: number | string | null;
  vehicle_freight?: number | string | null;
  advance_vehicle?: number | string | null;
  vehicles?: VehicleRelation | VehicleRelation[] | null;
};

type MovementGroupRecord = {
  id: string;
  adda_id: string;
  outbound_bilty_id: string;
  status: "open" | "completed" | "voucher_created";
  completed_at: string | null;
};

type LoadingRecord = {
  id: number;
  loading_no: string;
  loading_date: string;
  route: string;
  booking_id?: string | null;
  vehicle_id: string | null;
  driver_id: string | null;
  vehicles?: VehicleRelation | null;
  drivers?: DriverRelation | null;
  bookings?: BookingRelation | BookingRelation[] | null;
};

type BiltyVehiclePaymentRecord = {
  bilty_id: string;
  amount: number | string;
};

type BiltyVehicleSettlement = {
  biltyId: string;
  biltyNo: string;
  loadingIds: number[];
  loadingNumbers: string[];
  route: string;
  vehicleNo: string;
  tripType: string;
  vehicleFreight: number;
  advanceVehicle: number;
  laterVehiclePaid: number;
  totalVehiclePaid: number;
  parchiWithheldCommission: number;
  vehicleEntitlementSettled: number;
  vehicleBalance: number | null;
  paymentStatus: "unpaid" | "partial" | "paid" | "unverified";
};

type BiltyVehicleSettlementTotals = Pick<BiltyVehicleSettlement,
  "vehicleFreight" | "advanceVehicle" | "laterVehiclePaid" | "totalVehiclePaid"
  | "parchiWithheldCommission" | "vehicleEntitlementSettled"
> & { vehicleBalance: number | null };

type PetrolPumpOption = {
  id: string;
  pumpName: string;
  openingBalance: number;
};

type ExpenseItemRecord = {
  id: number;
  expense_id: number;
  expense_type: string;
  expense_class?: string | null;
  amount: number | string;
  payment_method: string;
  remarks: string | null;
  receipt_url: string | null;
  receipt_name: string | null;
};

type DieselEntryRecord = {
  id: number;
  expense_id: number;
  expense_item_id: number;
  entry_date: string;
  petrol_pump_id: string;
  vehicle_id: string;
  driver_id: string | null;
  loading_id: number | null;
  manual_voucher_id?: string | null;
  manual_request_id?: string | null;
  slip_no: string | null;
  liters: number | string;
  rate: number | string;
  total_amount: number | string;
  paid_amount: number | string;
  remaining_amount: number | string;
  payment_status: string;
  remarks: string | null;
  initial_payment_date?: string | null;
  initial_payment_method?: string | null;
  initial_payment_reference?: string | null;
  initial_payment_remarks?: string | null;
  petrol_pumps?: {
    pump_name: string | null;
  } | null;
};

type VoucherWorkshopDatabaseRow = {
  id: number; adda_id: string; work_date: string | null; workshop_name: string | null;
  vehicle_id: string | null; bill_no: string | null; work_type: string | null;
  total_cost: number | string | null;
  vehicles?: { vehicle_no: string | null } | Array<{ vehicle_no: string | null }> | null;
  workshop_entry_items?: Array<{ line_no: number; work_type: string }> | null;
};

type VoucherWorkshopLinkRow = {
  workshop_entry_id: number;
  voucher_id: number;
  link_origin?: "existing_link" | "voucher_created";
};

type VoucherWorkshopMetadataRow = {
  id: number;
  expense_no: string | null;
  expense_date: string | null;
};

type VoucherOilDatabaseRow = {
  id: string; adda_id: string; entry_date: string; vehicle_id: string; source_type: "external_shop" | "adda_stock";
  oil_shop_id: string | null; oil_product_id: string; liters: number | string; rate_per_liter: number | string;
  total_amount: number | string; bill_no: string | null;
  vehicles?: { vehicle_no: string | null } | Array<{ vehicle_no: string | null }> | null;
  oil_products?: { oil_type: string; brand: string | null; grade: string | null } | Array<{ oil_type: string; brand: string | null; grade: string | null }> | null;
  oil_shops?: { shop_name: string | null } | Array<{ shop_name: string | null }> | null;
};
type VoucherOilLinkRow = { oil_vehicle_entry_id: string; voucher_id: number; link_origin?: "existing_link" | "voucher_created" };
type VoucherTyreDatabaseRow = {id:string;adda_id:string;entry_date:string;vehicle_id:string;tyre_shop_id:string|null;work_type:string;bill_no:string|null;total_amount:number|string;vehicles?:{vehicle_no:string|null}|Array<{vehicle_no:string|null}>|null;tyre_shops?:{shop_name:string|null}|Array<{shop_name:string|null}>|null;tyre_vehicle_entry_items?:Array<{line_no:number;tyre_assets?:{serial_number:string}|Array<{serial_number:string}>|null;vehicle_tyre_positions?:{position_label:string}|Array<{position_label:string}>|null}>|null};
type VoucherTyreLinkRow = {
  tyre_vehicle_entry_id: string;
  voucher_id: number;
  link_origin?: "existing_link" | "voucher_created";
};
type VoucherDriverEarningDatabaseRow = {
  id: string; adda_id: string; driver_id: string; vehicle_id: string; salary_date: string; salary_month: string;
  earning_type: string; basic_salary: number | string; trip_pay: number | string; bonus_allowance: number | string;
  deduction_fine: number | string; gross_expense: number | string; paid_amount: number | string;
  remaining_amount: number | string; payment_status: string;
  drivers?: { name: string | null } | Array<{ name: string | null }> | null;
  vehicles?: { vehicle_no: string | null } | Array<{ vehicle_no: string | null }> | null;
};
type VoucherDriverEarningLinkRow = { driver_earning_id: string; voucher_id: number };

type VoucherAdjustmentSummary = {
  id: string;
  status: string;
  totalAmount: number;
  finalizedAt: string | null;
};

type ManualFreightType = "outbound" | "local" | "return";
type ManualFreightInput = {
  clientId: string;
  freightType: ManualFreightType;
  amount: string;
  description: string;
};
type ManualDieselInput = {
  clientId: string;
  dieselEntryId: number | null;
  requestId: string;
  entryDate: string;
  petrolPumpId: string;
  liters: string;
  rate: string;
  paidAmount: string;
  paymentDate: string;
  paymentMethod: string;
  paymentReference: string;
  paymentRemarks: string;
  paymentRecorded: boolean;
  slipNo: string;
  remarks: string;
};
type ManualVehicleOption = { id: string; adda_id: string; vehicle_no: string };
type ManualDriverOption = { id: string; adda_id: string; name: string };
type ManualFreightRecord = {
  id: string;
  manual_voucher_id: string;
  freight_type: ManualFreightType;
  amount: number | string;
  description: string | null;
  sequence_no: number;
};
type ManualVoucherDetailRecord = {
  id: string;
  voucher_id: number;
  adda_id: string;
  vehicle_id: string;
  driver_id: string | null;
  voucher_date: string;
  chakkar_days: number;
  departure_date?: string | null;
  arrival_date?: string | null;
  remarks: string | null;
  status: "draft" | "finalized";
  finalized_at?: string | null;
  finalized_by?: string | null;
  manual_vehicle_chakkar_settlements?: ManualSettlementRecord[];
  manual_voucher_freight_items?: ManualFreightRecord[];
  vehicle_no?: string;
  vehicle_owner?: string | null;
  driver_name?: string | null;
};

type ManualSettlementRecord = {
  id: string;
  voucher_id?: number;
  total_freight: number | string;
  regular_expense_total: number | string;
  periodic_expense_total: number | string;
  total_expense_amount: number | string;
  net_vehicle_amount: number | string;
  freight_snapshot?: Array<{ freight_type: ManualFreightType; amount: number | string; description: string | null; sequence_no: number }>;
  expense_snapshot?: Array<{ expense_class: string; expense_type: string; amount: number | string; remarks: string | null }>;
  finalized_at: string;
};

type ManualSourceKind = "workshop" | "oil" | "tyre";
type ManualSourceCreatedTotals = Partial<Record<ManualSourceKind, { id: string; amount: number }>>;

const MANUAL_EXPENSE_TYPES = [
  "Toll Tax", "Food", "Labour", "Maintenance", "Police", "Parking", "Other",
  "Driver Kharcha", "Munshiana", "Loading / Unloading",
] as const;

function createManualFreightInput(freightType: ManualFreightType): ManualFreightInput {
  return {
    clientId: `${freightType}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    freightType,
    amount: "",
    description: "",
  };
}

function createManualDieselInput(entryDate = ""): ManualDieselInput {
  const requestId = crypto.randomUUID();
  return {
    clientId: requestId,
    dieselEntryId: null,
    requestId,
    entryDate,
    petrolPumpId: "",
    liters: "",
    rate: "",
    paidAmount: "0",
    paymentDate: entryDate,
    paymentMethod: "Cash",
    paymentReference: "",
    paymentRemarks: "",
    paymentRecorded: false,
    slipNo: "",
    remarks: "",
  };
}

type ExpenseVoucher = {
  id: number;
  expense_no: string;
  expense_date: string;
  start_date?: string | null;
  end_date?: string | null;
  loading_id: number | null;
  movement_group_id?: string | null;
  description: string | null;
  created_at?: string | null;
  archived_at?: string | null;
  archived_by?: string | null;
  archive_reason?: string | null;
  voucher_source?: "bilty" | "manual" | null;
  manual_voucher_details?: ManualVoucherDetailRecord | null;
  movement_group?: MovementGroupRecord | MovementGroupRecord[] | null;
  movement_group_bilties?: BookingRelation[];
  vehicle_chakkar_settlements?: Array<{
    id: string;
    movement_group_id: string;
    finalized_at: string;
  }>;
  loadings?: LoadingRecord | null;
  voucher_loadings?: Array<{
    loading_id: number;
    loadings?: LoadingRecord | null;
  }>;
  expense_items?: ExpenseItemRecord[];
  diesel_entries?: DieselEntryRecord[];
  voucher_workshop_entries?: Array<{ workshop_entry_id: number; link_origin?: "existing_link" | "voucher_created"; workshop_entries?: VoucherWorkshopDatabaseRow | null }>;
  voucher_oil_entries?: Array<{ oil_vehicle_entry_id: string; link_origin?: "existing_link" | "voucher_created"; oil_vehicle_entries?: VoucherOilDatabaseRow | null }>;
  voucher_tyre_entries?: Array<{ tyre_vehicle_entry_id: string; link_origin?: "existing_link" | "voucher_created"; tyre_vehicle_entries?: VoucherTyreDatabaseRow | null }>;
  voucher_driver_earnings?: Array<{ driver_earning_id: string; driver_earnings?: VoucherDriverEarningDatabaseRow | null }>;
  voucher_adjustment_summaries?: VoucherAdjustmentSummary[];
  manual_voucher_adjustments?: ManualVoucherAdjustment[];
};

type VoucherPrintSettings = {
  business_tagline: string | null;
  logo_url: string | null;
  paper_size: "A4" | "A5" | "thermal-80mm";
  show_logo_on_print: boolean;
  show_signature_on_print: boolean;
  print_footer_text: string | null;
};

let nextExpenseItemRowId = 1;

function createEmptyExpenseItem(
  expenseClass: ExpenseClass = "regular_trip"
): ExpenseItemRow {
  const row: ExpenseItemRow = {
    rowId: nextExpenseItemRowId,
    expenseClass,
    expenseType: "",
    amount: "",
    paymentMethod: "Cash",
    remarks: "",
    receiptUrl: null,
    receiptName: null,
    receiptFile: null,
    receiptStatus: "idle",
    receiptError: "",
    petrolPumpId: "",
    liters: "",
    rate: "",
    paidAmount: "",
    slipNo: "",
  };

  nextExpenseItemRowId += 1;
  return row;
}

function toNumber(value: number | string | null | undefined) {
  const numericValue = Number(value ?? 0);
  return Number.isFinite(numericValue) ? numericValue : 0;
}

function money(value: number) {
  return new Intl.NumberFormat("en-PK", {
    maximumFractionDigits: 2,
  }).format(Number.isFinite(value) ? value : 0);
}

function relationOne<T>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

function logExpenseLoadQueryError(query: string, table: string, error: unknown) {
  const details = error as {
    code?: string;
    message?: string;
    details?: string | null;
    hint?: string | null;
  } | null;
  console.error("[/expenses] Supabase read failed", {
    query,
    table,
    code: details?.code ?? null,
    message: details?.message ?? null,
    details: details?.details ?? null,
    hint: details?.hint ?? null,
    error,
  });
}

function relationMany<T>(value: T | T[] | null | undefined): T[] {
  return value == null ? [] : Array.isArray(value) ? value : [value];
}

function loadingBooking(loading: LoadingRecord | null | undefined) {
  return relationOne(loading?.bookings);
}

function loadingBelongsToMovementGroup(
  loading: LoadingRecord,
  groupId: string,
  movementBilties: BookingRelation[]
) {
  return (
    relationMany(loading.bookings).some(
      (booking) => String(booking.bilty_group_id) === String(groupId)
    ) ||
    movementBilties.some(
      (bilty) =>
        String(bilty.id) === String(loading.booking_id) &&
        bilty.bilty_group_id !== null &&
        bilty.bilty_group_id !== undefined &&
        String(bilty.bilty_group_id) === String(groupId)
    )
  );
}

function getMovementGroupLoadings(
  loadings: LoadingRecord[],
  groupId: string,
  movementBilties: BookingRelation[]
) {
  const groupBilties = movementBilties.filter(
    (bilty) => String(bilty.bilty_group_id) === String(groupId)
  );
  const bookingOrder = new Map(
    [...groupBilties]
      .sort((left, right) => {
        const tripOrder = { outbound: 0, local: 1, return: 2 } as const;
        const leftOrder = tripOrder[left.trip_type as keyof typeof tripOrder] ?? 3;
        const rightOrder = tripOrder[right.trip_type as keyof typeof tripOrder] ?? 3;
        return leftOrder - rightOrder;
      })
      .map((bilty, index) => [String(bilty.id), index])
  );

  return loadings
    .filter((loading) =>
      loadingBelongsToMovementGroup(loading, groupId, movementBilties)
    )
    .sort((left, right) =>
      (bookingOrder.get(String(left.booking_id)) ?? Number.MAX_SAFE_INTEGER) -
      (bookingOrder.get(String(right.booking_id)) ?? Number.MAX_SAFE_INTEGER)
    );
}

function movementGroupLabel(outboundBiltyNo: string, groupId: string, groupLabel: string) {
  return `${outboundBiltyNo} — ${groupLabel} ${groupId.replaceAll("-", "").slice(0, 6).toUpperCase()}`;
}

function calendarDayDifference(startDate: string, endDate: string) {
  const datePattern = /^(\d{4})-(\d{2})-(\d{2})$/;
  const startMatch = datePattern.exec(startDate);
  const endMatch = datePattern.exec(endDate);
  if (!startMatch || !endMatch) return null;
  const start = Date.UTC(Number(startMatch[1]), Number(startMatch[2]) - 1, Number(startMatch[3]));
  const end = Date.UTC(Number(endMatch[1]), Number(endMatch[2]) - 1, Number(endMatch[3]));
  const days = (end - start) / 86_400_000;
  return Number.isInteger(days) && days >= 0 ? days : null;
}

function getVoucherLoadings(voucher: ExpenseVoucher) {
  const related = (voucher.voucher_loadings ?? []).flatMap((relation) =>
    relation.loadings ? [relation.loadings] : []
  );
  const candidates =
    related.length > 0 ? related : voucher.loadings ? [voucher.loadings] : [];

  return Array.from(
    new Map(candidates.map((loading) => [String(loading.id), loading])).values()
  );
}

function getVoucherMovementGroupId(voucher: ExpenseVoucher) {
  if (voucher.movement_group_id) return voucher.movement_group_id;
  const groupIds = Array.from(
    new Set(
      getVoucherLoadings(voucher)
        .map((loading) => loadingBooking(loading)?.bilty_group_id)
        .filter((id): id is string => Boolean(id))
    )
  );
  return groupIds.length === 1 ? groupIds[0] : null;
}

function getDieselStatus(paidAmount: number, totalAmount: number) {
  if (paidAmount <= 0) return "Unpaid";
  if (paidAmount >= totalAmount) return "Paid";
  return "Partial";
}

function getReceiptPath(fileUrl: string) {
  const marker = "/expense-receipts/";
  const markerIndex = fileUrl.indexOf(marker);

  if (markerIndex >= 0) {
    return fileUrl.slice(markerIndex + marker.length);
  }

  return "";
}

function isAllowedReceipt(file: File) {
  const allowedTypes = [
    "image/jpeg",
    "image/png",
    "image/webp",
    "application/pdf",
  ];
  const allowedExtensions = [".jpg", ".jpeg", ".png", ".webp", ".pdf"];
  const lowerName = file.name.toLowerCase();

  return (
    allowedTypes.includes(file.type) ||
    allowedExtensions.some((extension) => lowerName.endsWith(extension))
  );
}

export default function ExpensesPage() {
  const { t, dir, language } = useLanguage();
  const [voucherMode, setVoucherMode] = useState<"bilty" | "manual">("bilty");
  const [expenseNo, setExpenseNo] = useState("");
  const [expenseDate, setExpenseDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [selectedLoadingIds, setSelectedLoadingIds] = useState<string[]>([]);
  const [selectedMovementGroupId, setSelectedMovementGroupId] = useState<string | null>(null);
  const [description, setDescription] = useState("");
  const [manualVehicles, setManualVehicles] = useState<ManualVehicleOption[]>([]);
  const [manualDrivers, setManualDrivers] = useState<ManualDriverOption[]>([]);
  const [manualVehicleId, setManualVehicleId] = useState("");
  const [manualDriverId, setManualDriverId] = useState("");
  const [manualChakkarDays, setManualChakkarDays] = useState("");
  const [manualDepartureDate, setManualDepartureDate] = useState("");
  const [manualArrivalDate, setManualArrivalDate] = useState("");
  const [hasPersistedManualDates, setHasPersistedManualDates] = useState(false);
  const [manualFreightRows, setManualFreightRows] = useState<ManualFreightInput[]>([
    createManualFreightInput("outbound"),
    createManualFreightInput("local"),
    createManualFreightInput("return"),
  ]);
  const [manualDieselRows, setManualDieselRows] = useState<ManualDieselInput[]>([]);

  const [loadings, setLoadings] = useState<LoadingRecord[]>([]);
  const [movementGroups, setMovementGroups] = useState<MovementGroupRecord[]>([]);
  const [movementBilties, setMovementBilties] = useState<BookingRelation[]>([]);
  const [petrolPumps, setPetrolPumps] = useState<PetrolPumpOption[]>([]);
  const [workshopEntries, setWorkshopEntries] = useState<VoucherWorkshopOption[]>([]);
  const [selectedWorkshopEntryIds, setSelectedWorkshopEntryIds] = useState<number[]>([]);
  const [workshopMasters, setWorkshopMasters] = useState<VoucherWorkshopMasterOption[]>([]);
  const [workshopMode, setWorkshopMode] = useState<VoucherWorkshopMode>("existing");
  const [oilMode, setOilMode] = useState<"existing" | "create">("existing");
  const [tyreMode, setTyreMode] = useState<"existing" | "create">("existing");
  const [manualSourceCreatedTotals, setManualSourceCreatedTotals] = useState<ManualSourceCreatedTotals>({});
  const [workshopCreateData, setWorkshopCreateData] = useState<VoucherWorkshopCreateData>(
    createEmptyVoucherWorkshopData()
  );
  const [oilEntries, setOilEntries] = useState<VoucherOilOption[]>([]);
  const [selectedOilEntryIds, setSelectedOilEntryIds] = useState<string[]>([]);
  const [oilProducts, setOilProducts] = useState<VoucherOilProductOption[]>([]);
  const [oilShops, setOilShops] = useState<VoucherOilShopOption[]>([]);
  const [pendingOilCreatePayload, setPendingOilCreatePayload] =
    useState<VoucherOilCreatePayload | null>(null);
  const [isCreatingOilEntry, setIsCreatingOilEntry] = useState(false);
  const [tyreEntries, setTyreEntries] = useState<VoucherTyreOption[]>([]);
  const [selectedTyreEntryIds, setSelectedTyreEntryIds] = useState<string[]>([]);
  const [tyreShops, setTyreShops] = useState<VoucherTyreShopOption[]>([]);
  const [tyreProducts, setTyreProducts] = useState<TyreProduct[]>([]);
  const [tyreAssets, setTyreAssets] = useState<TyreAsset[]>([]);
  const [tyrePositions, setTyrePositions] = useState<TyrePosition[]>([]);
  const [pendingTyreCreatePayload, setPendingTyreCreatePayload] =
    useState<VoucherTyreCreatePayload | null>(null);
  const [isCreatingTyreEntry, setIsCreatingTyreEntry] = useState(false);
  const [driverEarnings, setDriverEarnings] = useState<VoucherDriverEarningOption[]>([]);
  const [selectedDriverEarningIds, setSelectedDriverEarningIds] = useState<string[]>([]);
  const [vehiclePaymentsByBilty, setVehiclePaymentsByBilty] = useState<Record<string, number>>({});
  const [vehiclePaymentsLoadFailed, setVehiclePaymentsLoadFailed] = useState(false);
  const [vehiclePaymentsScopeKey, setVehiclePaymentsScopeKey] = useState("");
  const [parchiWithheldByBilty, setParchiWithheldByBilty] = useState<Record<string, number>>({});
  const [parchiSettlementScopeKey, setParchiSettlementScopeKey] = useState("");
  const [isParchiSettlementLoading, setIsParchiSettlementLoading] = useState(false);
  const [parchiSettlementLoadFailed, setParchiSettlementLoadFailed] = useState(false);
  const [isBiltySettlementLoading, setIsBiltySettlementLoading] = useState(false);
  const [expenseItems, setExpenseItems] = useState<ExpenseItemRow[]>([
    createEmptyExpenseItem(),
  ]);
  const [expenseVouchers, setExpenseVouchers] = useState<ExpenseVoucher[]>([]);
  const [viewingExpense, setViewingExpense] = useState<ExpenseVoucher | null>(
    null
  );
  const [voucherPrintPresentation, setVoucherPrintPresentation] = useState<VoucherPrintPresentation | null>(null);
  const [voucherPrintVoucher, setVoucherPrintVoucher] = useState<ExpenseVoucher | null>(null);

  const [search, setSearch] = useState("");
  const [fromDateFilter, setFromDateFilter] = useState("");
  const [toDateFilter, setToDateFilter] = useState("");
  const [vehicleFilter, setVehicleFilter] = useState("");
  const [driverFilter, setDriverFilter] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("");
  const [paymentMethodFilter, setPaymentMethodFilter] = useState("");
  const [page, setPage] = useState(1);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [manualSourceEditTarget, setManualSourceEditTarget] = useState<ManualVoucherSourceEditTarget | null>(null);
  const resumeManualVoucherHandledRef = useRef(false);
  const voucherViewHandledIdRef = useRef<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isPreparingMovementLoading, setIsPreparingMovementLoading] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [finalizingVoucherId, setFinalizingVoucherId] = useState<number | null>(null);
  const [adjustmentVoucher, setAdjustmentVoucher] = useState<ExpenseVoucher | null>(null);
  const [manualAdjustmentVoucher, setManualAdjustmentVoucher] = useState<ExpenseVoucher | null>(null);

  const selectedLoadings = useMemo(
    () =>
      selectedLoadingIds.flatMap((id) => {
        const loading = loadings.find((item) => String(item.id) === id);
        return loading ? [loading] : [];
      }),
    [loadings, selectedLoadingIds]
  );

  const selectedLoading = useMemo(() => {
    return selectedLoadings[0] ?? null;
  }, [selectedLoadings]);

  const movementGroupsById = useMemo(
    () => new Map(movementGroups.map((group) => [group.id, group])),
    [movementGroups]
  );

  const selectedMovementGroup = useMemo(() => {
    return selectedMovementGroupId ? movementGroupsById.get(selectedMovementGroupId) ?? null : null;
  }, [movementGroupsById, selectedMovementGroupId]);

  const selectedOutboundBilty = useMemo(
    () => selectedMovementGroup
      ? movementBilties.find((bilty) => bilty.id === selectedMovementGroup.outbound_bilty_id) ?? null
      : null,
    [movementBilties, selectedMovementGroup]
  );

  const selectedVehicleId = selectedOutboundBilty?.vehicle_id ?? selectedLoading?.vehicle_id ?? null;
  const selectedVehicleNo =
    selectedLoading?.vehicles?.vehicle_no ??
    relationOne(selectedOutboundBilty?.vehicles)?.vehicle_no ??
    "";

  const manualVehicle = manualVehicles.find((vehicle) => vehicle.id === manualVehicleId);
  const activeVoucherVehicleId = voucherMode === "manual" ? manualVehicleId || null : selectedVehicleId;
  const activeVoucherAddaId = voucherMode === "manual"
    ? manualVehicle?.adda_id ?? null
    : selectedMovementGroup?.adda_id ?? loadingBooking(selectedLoading)?.adda_id ?? null;

  const eligibleWorkshopEntries = useMemo(() => workshopEntries.filter((entry) =>
    entry.vehicleId === activeVoucherVehicleId &&
    Boolean(activeVoucherAddaId && entry.addaId === activeVoucherAddaId) &&
    (entry.attachedVoucherId === null || entry.attachedVoucherId === editingId)
  ), [activeVoucherAddaId, activeVoucherVehicleId, editingId, workshopEntries]);
  const eligibleOilEntries = useMemo(() => oilEntries.filter((entry) =>
    entry.vehicleId === activeVoucherVehicleId &&
    Boolean(activeVoucherAddaId && entry.addaId === activeVoucherAddaId) &&
    (entry.attachedVoucherId === null || entry.attachedVoucherId === editingId)
  ), [activeVoucherAddaId, activeVoucherVehicleId, editingId, oilEntries]);
  const eligibleTyreEntries = useMemo(() => tyreEntries.filter((entry) =>
    entry.vehicleId === activeVoucherVehicleId &&
    Boolean(activeVoucherAddaId && entry.addaId === activeVoucherAddaId) &&
    (entry.attachedVoucherId === null || entry.attachedVoucherId === editingId)
  ), [activeVoucherAddaId, activeVoucherVehicleId, editingId, tyreEntries]);
  const eligibleDriverEarnings = useMemo(() => driverEarnings.filter((entry) =>
    entry.vehicleId === selectedVehicleId &&
    (entry.attachedVoucherId === null || entry.attachedVoucherId === editingId)
  ), [driverEarnings, editingId, selectedVehicleId]);

  const selectedGroupBilties = useMemo(
    () => {
      if (selectedMovementGroup) {
        return movementBilties.filter(
          (bilty) => bilty.bilty_group_id === selectedMovementGroup.id
        );
      }
      return Array.from(
        new Map(
          selectedLoadings.flatMap((loading) =>
            loadingBooking(loading)
              ? [[loadingBooking(loading)!.id, loadingBooking(loading)!] as const]
              : []
          )
        ).values()
      );
    },
    [movementBilties, selectedLoadings, selectedMovementGroup]
  );

  const movementSummary = useMemo<VoucherMovementSummary | null>(() => {
    if (!selectedMovementGroup) return null;
    const groupLoadings = getMovementGroupLoadings(
      loadings,
      selectedMovementGroup.id,
      movementBilties
    );
    const uniqueBilties = new Map(movementBilties.filter((bilty) => bilty.bilty_group_id === selectedMovementGroup.id).map((bilty) => [bilty.id, bilty]));
    const outbound = uniqueBilties.get(selectedMovementGroup.outbound_bilty_id);
    return {
      id: selectedMovementGroup.id,
      label: movementGroupLabel(outbound?.booking_no ?? "-", selectedMovementGroup.id, t("bilty.movement.group")),
      outboundBiltyNo: outbound?.booking_no ?? "-",
      biltyCount: uniqueBilties.size,
      tripTypes: Array.from(new Set(Array.from(uniqueBilties.values()).map((bilty) => bilty.trip_type).filter((trip): trip is string => Boolean(trip)))).map((trip) => t(`bilty.tripTypes.${trip}`)),
      loadingNumbers: groupLoadings.map((loading) => loading.loading_no),
    };
  }, [loadings, movementBilties, selectedMovementGroup, t]);

  const completedMovementGroups = useMemo<VoucherMovementOption[]>(() => {
    return movementGroups.flatMap((group) => {
      if (group.status !== "completed") return [];
      const groupLoadings = getMovementGroupLoadings(
        loadings,
        group.id,
        movementBilties
      );
      const uniqueBilties = new Map(
        movementBilties
          .filter((bilty) => bilty.bilty_group_id === group.id)
          .map((bilty) => [bilty.id, bilty])
      );

      const outbound = uniqueBilties.get(group.outbound_bilty_id);
      const bilties = Array.from(uniqueBilties.values());
      const outboundBilties = bilties.filter((bilty) => bilty.trip_type === "outbound");
      const returnBilties = bilties.filter((bilty) => bilty.trip_type === "return");
      const vehicleIds = new Set(bilties.map((bilty) => bilty.vehicle_id).filter((id): id is string => Boolean(id)));
      const hasConflictingAdda = bilties.some(
        (bilty) => bilty.adda_id !== null && bilty.adda_id !== group.adda_id
      );

      if (
        !group.adda_id ||
        outboundBilties.length !== 1 ||
        returnBilties.length !== 1 ||
        !outbound ||
        outbound.trip_type !== "outbound" ||
        vehicleIds.size !== 1 ||
        hasConflictingAdda
      ) {
        return [];
      }

      const linkedVoucher = expenseVouchers.find((voucher) =>
        voucher.movement_group_id === group.id ||
        (voucher.movement_group_id === null && getVoucherLoadings(voucher).some(
          (loading) => loadingBelongsToMovementGroup(loading, group.id, movementBilties)
        ))
      );
      const selectable = !linkedVoucher || linkedVoucher.id === editingId;

      return [{
        id: group.id,
        label: movementGroupLabel(
          outbound.booking_no ?? "-",
          group.id,
          t("bilty.movement.group")
        ),
        outboundBiltyNo: outbound.booking_no ?? "-",
        biltyCount: uniqueBilties.size,
        tripTypes: Array.from(
          new Set(
            Array.from(uniqueBilties.values())
              .map((bilty) => bilty.trip_type)
              .filter((trip): trip is string => Boolean(trip))
          )
        ).map((trip) => t(`bilty.tripTypes.${trip}`)),
        loadingNumbers: groupLoadings.map((loading) => loading.loading_no),
        loadingIds: groupLoadings.map((loading) => String(loading.id)),
        voucherStatus: linkedVoucher ? "voucher_created" : "available",
        linkedVoucherId: linkedVoucher?.id ?? null,
        linkedVoucherNo: linkedVoucher?.expense_no ?? null,
        linkedVoucherDate: linkedVoucher?.start_date ?? linkedVoucher?.expense_date ?? null,
        selectable,
      }];
    });
  }, [editingId, expenseVouchers, loadings, movementBilties, movementGroups, t]);

  const totalDays = useMemo(
    () => calendarDayDifference(expenseDate, endDate),
    [endDate, expenseDate]
  );

  function datesForMovementGroup(groupId: string) {
    const bookings = movementBilties.filter((bilty) => bilty.bilty_group_id === groupId);
    return {
      startDate: bookings.find((booking) => booking.trip_type === "outbound")?.departure_date ?? "",
      endDate: bookings.find((booking) => booking.trip_type === "return")?.arrival_date ?? "",
    };
  }

  async function handleMovementGroupSelection(groupId: string) {
    const group = completedMovementGroups.find((item) => item.id === groupId);
    if (!group || !group.selectable || isPreparingMovementLoading) return;

    setIsPreparingMovementLoading(true);
    setSelectedMovementGroupId(null);
    setSelectedLoadingIds([]);
    try {
      const groupLoadings = await prepareMovementGroupLoadings(group.id);
      setSelectedMovementGroupId(group.id);
      setSelectedLoadingIds(groupLoadings.map((loading) => String(loading.id)));
      setSelectedWorkshopEntryIds([]);
      setSelectedOilEntryIds([]);
      setPendingOilCreatePayload(null);
      setSelectedTyreEntryIds([]);
      setPendingTyreCreatePayload(null);
      setSelectedDriverEarningIds([]);
      setExpenseItems((items) => items.map((item) => ["Workshop", "Oil / Lubricants", "Tyre", "Driver Salary"].includes(item.expenseType) ? { ...item, amount: "" } : item));
      const dates = datesForMovementGroup(group.id);
      if (dates.startDate) setExpenseDate(dates.startDate);
      if (dates.endDate) setEndDate(dates.endDate);
    } catch (error) {
      console.error("Unable to prepare Movement Group Loading:", error);
      alert(t("expenses.messages.movementGroupLoadingPrepareFailed"));
    } finally {
      setIsPreparingMovementLoading(false);
    }
  }

  useEffect(() => {
    const biltyIds = selectedGroupBilties.map((bilty) => bilty.id);

    if (biltyIds.length === 0) {
      const clearTimer = window.setTimeout(() => {
        setVehiclePaymentsByBilty({});
        setVehiclePaymentsLoadFailed(false);
        setVehiclePaymentsScopeKey("");
        setParchiWithheldByBilty({});
        setParchiSettlementScopeKey("");
        setParchiSettlementLoadFailed(false);
        setIsParchiSettlementLoading(false);
        setIsBiltySettlementLoading(false);
      }, 0);
      return () => window.clearTimeout(clearTimer);
    }

    let cancelled = false;

    async function loadVehiclePayments() {
      setIsBiltySettlementLoading(true);
      setVehiclePaymentsLoadFailed(false);
      setIsParchiSettlementLoading(true);
      setParchiWithheldByBilty({});
      setParchiSettlementLoadFailed(false);

      const { data, error } = await supabase
        .from("bilty_payments")
        .select("bilty_id, amount")
        .in("bilty_id", biltyIds)
        .eq("payment_side", "vehicle");

      if (cancelled) return;

      if (error) {
        console.error("Unable to load Bilty vehicle payments for Voucher:", error);
        setVehiclePaymentsByBilty({});
        setVehiclePaymentsLoadFailed(true);
        setVehiclePaymentsScopeKey("");
        setIsBiltySettlementLoading(false);
      } else {
        const totals: Record<string, number> = {};
        ((data ?? []) as BiltyVehiclePaymentRecord[]).forEach((payment) => {
          totals[payment.bilty_id] =
            (totals[payment.bilty_id] ?? 0) + toNumber(payment.amount);
        });

        setVehiclePaymentsByBilty(totals);
        setVehiclePaymentsLoadFailed(false);
        setVehiclePaymentsScopeKey(selectedGroupBilties.map((booking) => `${booking.adda_id ?? ""}:${booking.id}`).sort().join("|"));
        setIsBiltySettlementLoading(false);
      }

      try {
        const parchiTotals = await getParchiVehicleSettlementTotalsForBookings(
          selectedGroupBilties.map((booking) => ({ id: booking.id, adda_id: booking.adda_id }))
        );
        if (cancelled) return;
        const withheld: Record<string, number> = {};
        for (const [bookingId, total] of parchiTotals) withheld[bookingId] = total.withheldCommission;
        setParchiWithheldByBilty(withheld);
        setParchiSettlementScopeKey(selectedGroupBilties.map((booking) => `${booking.adda_id ?? ""}:${booking.id}`).sort().join("|"));
      } catch (parchiError) {
        if (cancelled) return;
        console.error("Unable to load Parchi vehicle settlement totals for Voucher:", parchiError);
        setParchiWithheldByBilty({});
        setParchiSettlementScopeKey("");
        setParchiSettlementLoadFailed(true);
      } finally {
        if (!cancelled) setIsParchiSettlementLoading(false);
      }
    }

    void loadVehiclePayments();

    return () => {
      cancelled = true;
    };
  }, [selectedGroupBilties]);

  const selectedBiltyScopeKey = selectedGroupBilties.map((booking) => `${booking.adda_id ?? ""}:${booking.id}`).sort().join("|");
  const settlementReadsVerified = Boolean(selectedBiltyScopeKey)
    && vehiclePaymentsScopeKey === selectedBiltyScopeKey
    && parchiSettlementScopeKey === selectedBiltyScopeKey
    && !isBiltySettlementLoading && !isParchiSettlementLoading
    && !vehiclePaymentsLoadFailed && !parchiSettlementLoadFailed;

  const selectedBiltySettlements = useMemo<BiltyVehicleSettlement[]>(() => {
    return selectedGroupBilties.map((booking) => {
      const biltyLoadings = selectedLoadings.filter(
        (loading) =>
          String(loading.booking_id) === String(booking.id) ||
          String(loadingBooking(loading)?.id) === String(booking.id)
      );
      const firstLoading = biltyLoadings[0];

      const vehicleFreight = toNumber(booking.vehicle_freight);
      const advanceVehicle = toNumber(booking.advance_vehicle);
      const laterVehiclePaid = vehiclePaymentsByBilty[booking.id] ?? 0;
      const totalVehiclePaid = advanceVehicle + laterVehiclePaid;
      const parchiWithheldCommission = parchiWithheldByBilty[booking.id] ?? 0;
      const vehicleEntitlementSettled = totalVehiclePaid + parchiWithheldCommission;
      const verified = settlementReadsVerified;

      return {
        biltyId: booking.id,
        biltyNo: booking.booking_no ?? "-",
        loadingIds: biltyLoadings.map((loading) => loading.id),
        loadingNumbers: biltyLoadings.map((loading) => loading.loading_no),
        route: firstLoading?.route ?? "-",
        vehicleNo: firstLoading?.vehicles?.vehicle_no ?? "-",
        tripType: booking.trip_type ?? "-",
        vehicleFreight,
        advanceVehicle,
        laterVehiclePaid,
        totalVehiclePaid,
        parchiWithheldCommission,
        vehicleEntitlementSettled,
        vehicleBalance: verified ? Math.max(vehicleFreight - vehicleEntitlementSettled, 0) : null,
        paymentStatus: !verified ? "unverified" as const
          : vehicleEntitlementSettled <= 0 ? "unpaid" as const
            : vehicleFreight - vehicleEntitlementSettled <= 0 ? "paid" as const : "partial" as const,
      };
    });
  }, [selectedGroupBilties, selectedLoadings, vehiclePaymentsByBilty, parchiWithheldByBilty, settlementReadsVerified]);

  const selectedBiltySettlementTotals = useMemo(() => {
    return selectedBiltySettlements.reduce<BiltyVehicleSettlementTotals>(
      (totals, settlement) => ({
        vehicleFreight: totals.vehicleFreight + settlement.vehicleFreight,
        advanceVehicle: totals.advanceVehicle + settlement.advanceVehicle,
        laterVehiclePaid: totals.laterVehiclePaid + settlement.laterVehiclePaid,
        totalVehiclePaid: totals.totalVehiclePaid + settlement.totalVehiclePaid,
        parchiWithheldCommission: totals.parchiWithheldCommission + settlement.parchiWithheldCommission,
        vehicleEntitlementSettled: totals.vehicleEntitlementSettled + settlement.vehicleEntitlementSettled,
        vehicleBalance: totals.vehicleBalance === null || settlement.vehicleBalance === null ? null : totals.vehicleBalance + settlement.vehicleBalance,
      }),
      {
        vehicleFreight: 0,
        advanceVehicle: 0,
        laterVehiclePaid: 0,
        totalVehiclePaid: 0,
        parchiWithheldCommission: 0,
        vehicleEntitlementSettled: 0,
        vehicleBalance: 0,
      }
    );
  }, [selectedBiltySettlements]);

  const grandTotal = useMemo(() => {
    return expenseItems.reduce((total, item) => total + toNumber(item.amount), 0);
  }, [expenseItems]);

  const manualTotalFreight = useMemo(
    () => manualFreightRows.reduce((total, row) => total + Math.max(0, toNumber(row.amount)), 0),
    [manualFreightRows]
  );

  const manualTotalExpenses = useMemo(
    () => {
      const plainExpenses = expenseItems.reduce((total, item) => total + Math.max(0, toNumber(item.amount)), 0);
      const workshopTotal = workshopMode === "create"
        ? workshopCreateTotal(workshopCreateData)
        : selectedWorkshopEntryIds.reduce((sum, id) => sum + (
            eligibleWorkshopEntries.find((entry) => entry.id === id)?.totalCost ??
            (manualSourceCreatedTotals.workshop?.id === String(id) ? manualSourceCreatedTotals.workshop.amount : 0)
          ), 0);
      const oilTotal = pendingOilCreatePayload
        ? pendingOilCreatePayload.liters * pendingOilCreatePayload.ratePerLiter
        : selectedOilEntryIds.reduce((sum, id) => sum + (
            eligibleOilEntries.find((entry) => entry.id === id)?.totalAmount ??
            (manualSourceCreatedTotals.oil?.id === id ? manualSourceCreatedTotals.oil.amount : 0)
          ), 0);
      const tyreTotal = pendingTyreCreatePayload
        ? pendingTyreCreatePayload.items.reduce((sum, line) => sum + line.quantity * line.rate, 0)
        : selectedTyreEntryIds.reduce((sum, id) => sum + (
            eligibleTyreEntries.find((entry) => entry.id === id)?.totalAmount ??
            (manualSourceCreatedTotals.tyre?.id === id ? manualSourceCreatedTotals.tyre.amount : 0)
          ), 0);
      const dieselTotal = manualDieselRows.reduce(
        (sum, row) => sum + Math.max(0, Math.round(toNumber(row.liters) * toNumber(row.rate) * 100) / 100),
        0
      );
      return plainExpenses + workshopTotal + oilTotal + tyreTotal + dieselTotal;
    },
    [eligibleOilEntries, eligibleTyreEntries, eligibleWorkshopEntries, expenseItems, manualSourceCreatedTotals,
      manualDieselRows, pendingOilCreatePayload, pendingTyreCreatePayload, selectedOilEntryIds, selectedTyreEntryIds,
      selectedWorkshopEntryIds, workshopCreateData, workshopMode]
  );

  const expenseClassTotals = useMemo(
    () =>
      expenseItems.reduce(
        (totals, item) => {
          totals[item.expenseClass] += toNumber(item.amount);
          return totals;
        },
        { regular_trip: 0, vehicle_periodic: 0 } as Record<ExpenseClass, number>
      ),
    [expenseItems]
  );

  const vehicleProfitLoss =
    selectedBiltySettlementTotals.vehicleFreight -
    grandTotal;

  const filteredExpenseVouchers = useMemo(() => {
    const keyword = search.trim().toLowerCase();

    return expenseVouchers.filter((voucher) => {
      const voucherLoadings = getVoucherLoadings(voucher);
      const text = [
        voucher.expense_no,
        voucher.start_date ?? voucher.expense_date,
        voucher.end_date ?? voucher.expense_date,
        voucher.description ?? "",
        voucher.voucher_source === "manual" ? t("expenses.manual.manualWithoutBilty") : "",
        voucher.manual_voucher_details?.vehicle_no ?? "",
        voucher.manual_voucher_details?.driver_name ?? "",
        ...(voucher.manual_voucher_details?.manual_voucher_freight_items ?? []).flatMap((row) => [
          row.freight_type,
          String(row.amount ?? ""),
          row.description ?? "",
        ]),
        ...voucherLoadings.flatMap((loading) => [
          loading.loading_no,
          loading.vehicles?.vehicle_no ?? "",
          loading.drivers?.name ?? "",
          loading.route,
        ]),
        ...(voucher.expense_items ?? []).flatMap((item) => [
          item.expense_type,
          String(item.amount ?? ""),
          item.payment_method,
          item.remarks ?? "",
          item.receipt_name ?? "",
        ]),
        ...(voucher.diesel_entries ?? []).flatMap((diesel) => [
          diesel.petrol_pumps?.pump_name ?? "",
          diesel.slip_no ?? "",
          String(diesel.liters ?? ""),
          String(diesel.rate ?? ""),
          String(diesel.paid_amount ?? ""),
          diesel.payment_status,
        ]),
      ]
        .join(" ")
        .toLowerCase();

      const matchesSearch = !keyword || text.includes(keyword);
      const matchesFromDate =
        !fromDateFilter ||
        (voucher.start_date ?? voucher.expense_date) >= fromDateFilter;
      const matchesToDate =
        !toDateFilter ||
        (voucher.end_date ?? voucher.expense_date) <= toDateFilter;
      const matchesVehicle =
        !vehicleFilter ||
        voucherLoadings.some((loading) => loading.vehicle_id === vehicleFilter) ||
        voucher.manual_voucher_details?.vehicle_id === vehicleFilter;
      const matchesDriver =
        !driverFilter ||
        voucherLoadings.some((loading) => loading.driver_id === driverFilter) ||
        voucher.manual_voucher_details?.driver_id === driverFilter;
      const matchesCategory =
        !categoryFilter ||
        (voucher.expense_items ?? []).some(
          (item) => item.expense_type === categoryFilter
        );
      const matchesPaymentMethod =
        !paymentMethodFilter ||
        (voucher.expense_items ?? []).some(
          (item) => item.payment_method === paymentMethodFilter
        );

      return (
        matchesSearch &&
        matchesFromDate &&
        matchesToDate &&
        matchesVehicle &&
        matchesDriver &&
        matchesCategory &&
        matchesPaymentMethod
      );
    });
  }, [
    categoryFilter,
    driverFilter,
    expenseVouchers,
    fromDateFilter,
    paymentMethodFilter,
    search,
    t,
    toDateFilter,
    vehicleFilter,
  ]);

  const expenseFilterOptions = useMemo(() => {
    const vehicles = new Map<string, string>();
    const drivers = new Map<string, string>();
    expenseVouchers.forEach((voucher) => {
      const manualDetail = voucher.manual_voucher_details;
      if (manualDetail?.vehicle_id && manualDetail.vehicle_no) {
        vehicles.set(manualDetail.vehicle_id, manualDetail.vehicle_no);
      }
      if (manualDetail?.driver_id && manualDetail.driver_name) {
        drivers.set(manualDetail.driver_id, manualDetail.driver_name);
      }
      getVoucherLoadings(voucher).forEach((loading) => {
        if (loading.vehicle_id && loading.vehicles?.vehicle_no) {
          vehicles.set(loading.vehicle_id, loading.vehicles.vehicle_no);
        }
        if (loading.driver_id && loading.drivers?.name) {
          drivers.set(loading.driver_id, loading.drivers.name);
        }
      });
    });
    return {
      vehicles: Array.from(vehicles, ([id, label]) => ({ id, label })),
      drivers: Array.from(drivers, ([id, label]) => ({ id, label })),
    };
  }, [expenseVouchers]);

  const editingManualVoucher = editingId === null
    ? null
    : expenseVouchers.find((voucher) => voucher.id === editingId && voucher.voucher_source === "manual") ?? null;
  const manualSourceOwnershipLocked = Boolean(
    editingManualVoucher?.voucher_workshop_entries?.some((link) => link.link_origin === "voucher_created") ||
    editingManualVoucher?.voucher_oil_entries?.some((link) => link.link_origin === "voucher_created") ||
    editingManualVoucher?.voucher_tyre_entries?.some((link) => link.link_origin === "voucher_created")
  );

  const linkedManualWorkshopEntries = (editingManualVoucher?.voucher_workshop_entries ?? [])
    .flatMap((link) => workshopEntries.filter((entry) => entry.id === link.workshop_entry_id));
  const linkedManualOilEntries = (editingManualVoucher?.voucher_oil_entries ?? [])
    .flatMap((link) => oilEntries.filter((entry) => entry.id === link.oil_vehicle_entry_id));
  const linkedManualTyreEntries = (editingManualVoucher?.voucher_tyre_entries ?? [])
    .flatMap((link) => tyreEntries.filter((entry) => entry.id === link.tyre_vehicle_entry_id));
  const manualWorkshopEditEntry = manualSourceEditTarget?.kind === "workshop"
    ? linkedManualWorkshopEntries.find((entry) => entry.id === manualSourceEditTarget.id) ?? null
    : null;
  const manualOilEditEntry = manualSourceEditTarget?.kind === "oil"
    ? linkedManualOilEntries.find((entry) => entry.id === manualSourceEditTarget.id) ?? null
    : null;

  function editManualLinkedSource(module: "workshop" | "oil", sourceId: string | number) {
    const voucher = editingManualVoucher;
    if (!voucher || voucher.manual_voucher_details?.status !== "draft") return;
    setManualSourceEditTarget(module === "workshop"
      ? { kind: "workshop", id: Number(sourceId) }
      : { kind: "oil", id: String(sourceId) });
  }

  async function refreshManualVoucherAfterSourceEdit() {
    await Promise.all([loadExpenseVouchers(), loadWorkshopEntries(), loadOilEntries()]);
  }

  function resetExpenseFilters() {
    setSearch("");
    setFromDateFilter("");
    setToDateFilter("");
    setVehicleFilter("");
    setDriverFilter("");
    setCategoryFilter("");
    setPaymentMethodFilter("");
    setPage(1);
  }

  const loadInitialData = useEffectEvent(async () => {
    setIsLoading(true);
    try {
      const movementBookingIds = await loadMovementGroups();
      await Promise.all([
        loadLoadings(movementBookingIds),
        loadManualVoucherMasters(),
        loadPetrolPumps(),
        loadWorkshopMasters(),
        loadWorkshopEntries(),
        loadOilMasters(),
        loadOilEntries(),
        loadTyreMasters(),
        loadTyreEntries(),
        loadDriverEarnings(),
        loadExpenseVouchers(),
      ]);
    } finally {
      setIsLoading(false);
    }
  });

  useEffect(() => {
    const loadTimer = window.setTimeout(() => {
      void loadInitialData();
    }, 0);

    return () => window.clearTimeout(loadTimer);
  }, []);

  async function loadLoadings(movementBookingIds: string[] = []) {
    const loadingSelect = `
      *,
      vehicles(vehicle_no, owner_name),
      drivers(name),
      bookings(
        id,
        adda_id,
        booking_no,
        trip_type,
        bilty_group_id,
        vehicle_id,
        departure_date,
        arrival_date,
        freight,
        vehicle_freight,
        advance_vehicle
      )
    `;
    const [allLoadingsResult, movementLoadingsResult] = await Promise.all([
      supabase.from("loadings").select(loadingSelect).order("id", { ascending: false }),
      movementBookingIds.length > 0
        ? supabase
            .from("loadings")
            .select(loadingSelect)
            .in("booking_id", movementBookingIds)
            .order("id", { ascending: false })
        : Promise.resolve({ data: [], error: null }),
    ]);

    if (allLoadingsResult.error || movementLoadingsResult.error) {
      if (allLoadingsResult.error) {
        logExpenseLoadQueryError(
          "select loadings with vehicles, drivers, and bookings; order by id desc",
          "public.loadings",
          allLoadingsResult.error
        );
      }
      if (movementLoadingsResult.error) {
        logExpenseLoadQueryError(
          "select loadings by movement booking ids with vehicles, drivers, and bookings",
          "public.loadings",
          movementLoadingsResult.error
        );
      }
      alert(t("common.messages.loadFailed"));
      return null;
    }

    const rowsById = new Map<string, LoadingRecord>();
    [...(allLoadingsResult.data ?? []), ...(movementLoadingsResult.data ?? [])].forEach((loading) => {
      rowsById.set(String(loading.id), loading as LoadingRecord);
    });
    const loadedRows = Array.from(rowsById.values());
    setLoadings(loadedRows);
    return loadedRows;
  }

  async function loadManualVoucherMasters() {
    const [vehicleResult, driverResult] = await Promise.all([
      supabase.from("vehicles").select("id, adda_id, vehicle_no").order("vehicle_no"),
      supabase.from("drivers").select("id, adda_id, name").order("name"),
    ]);

    if (vehicleResult.error || driverResult.error) {
      if (vehicleResult.error) {
        logExpenseLoadQueryError(
          "select id, adda_id, vehicle_no from vehicles order by vehicle_no",
          "public.vehicles",
          vehicleResult.error
        );
      }
      if (driverResult.error) {
        logExpenseLoadQueryError(
          "select id, adda_id, name from drivers order by name",
          "public.drivers",
          driverResult.error
        );
      }
      alert(t("common.messages.loadFailed"));
      return;
    }

    setManualVehicles((vehicleResult.data ?? []) as ManualVehicleOption[]);
    setManualDrivers((driverResult.data ?? []) as ManualDriverOption[]);
  }

  async function prepareMovementGroupLoadings(groupId: string) {
    const { data: preparedLoadingId, error } = await supabase.rpc(
      "prepare_voucher_movement_group_loading",
      { p_movement_group_id: groupId }
    );

    if (error) throw new Error(error.message);

    const groupBookingIds = movementBilties
      .filter((bilty) => String(bilty.bilty_group_id) === String(groupId))
      .map((bilty) => bilty.id);
    const refreshedLoadings = await loadLoadings(groupBookingIds);

    if (!refreshedLoadings) {
      throw new Error("Movement Group Loadings could not be reloaded.");
    }

    const groupLoadings = getMovementGroupLoadings(
      refreshedLoadings,
      groupId,
      movementBilties
    );
    const preparedId = String(preparedLoadingId ?? "");

    if (
      groupLoadings.length === 0 ||
      !groupLoadings.some((loading) => String(loading.id) === preparedId)
    ) {
      throw new Error("The prepared Loading was not returned by the authoritative group query.");
    }

    return groupLoadings;
  }

  async function loadMovementGroups(): Promise<string[]> {
    const [groupsResult, biltiesResult] = await Promise.all([
      supabase
        .from("bilty_movement_groups")
        .select("id, adda_id, outbound_bilty_id, status, completed_at"),
      supabase
        .from("bookings")
        .select("id, adda_id, booking_no, trip_type, bilty_group_id, vehicle_id, departure_date, arrival_date, freight, vehicle_freight, advance_vehicle")
        .not("bilty_group_id", "is", null),
    ]);

    if (groupsResult.error || biltiesResult.error) {
      console.error(
        "loadMovementGroups failed:",
        groupsResult.error ?? biltiesResult.error
      );
      return [];
    }

    setMovementGroups((groupsResult.data ?? []) as MovementGroupRecord[]);
    const bilties = (biltiesResult.data ?? []) as BookingRelation[];
    setMovementBilties(bilties);
    return bilties.map((bilty) => String(bilty.id));
  }

  async function loadPetrolPumps() {
    const { data, error } = await supabase
      .from("petrol_pumps")
      .select("id, pump_name, opening_balance")
      .order("pump_name", { ascending: true });

    if (error) {
      logExpenseLoadQueryError(
        "select id, pump_name, opening_balance from petrol_pumps order by pump_name",
        "public.petrol_pumps",
        error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }

    setPetrolPumps(
      (data ?? []).map((pump) => ({
        id: String(pump.id),
        pumpName: pump.pump_name ?? "-",
        openingBalance: toNumber(pump.opening_balance),
      }))
    );
  }

  async function loadWorkshopMasters() {
    const { data, error } = await supabase
      .from("workshops")
      .select("id, workshop_name")
      .order("workshop_name", { ascending: true });

    if (error) {
      console.error("Unable to load Workshop Master options for Voucher:", error);
      setWorkshopMasters([]);
      return;
    }

    setWorkshopMasters(
      (data ?? []).map((workshop) => ({
        id: String(workshop.id),
        workshopName: workshop.workshop_name ?? "-",
      }))
    );
  }

  async function loadWorkshopEntries() {
    const { data, error } = await supabase.from("workshop_entries").select(`
      id, adda_id, work_date, workshop_name, vehicle_id, bill_no, work_type, total_cost,
      vehicles(vehicle_no), workshop_entry_items(line_no, work_type)
    `).gt("total_cost", 0).order("work_date", { ascending: false });
    if (error) {
      console.error("Unable to load available Workshop work for Voucher:", error);
      setWorkshopEntries([]);
      return;
    }
    const workshopRows = (data ?? []) as VoucherWorkshopDatabaseRow[];
    const workshopEntryIds = workshopRows.map((entry) => entry.id);
    const { data: linkData, error: linkError } = workshopEntryIds.length === 0
      ? { data: [] as VoucherWorkshopLinkRow[], error: null }
      : await supabase
          .from("voucher_workshop_entries")
          .select("workshop_entry_id, voucher_id, link_origin")
          .in("workshop_entry_id", workshopEntryIds);
    if (linkError) {
      console.error("Unable to resolve Workshop Voucher attachment status:", linkError);
      setWorkshopEntries([]);
      return;
    }
    const linksByWorkshopEntry = new Map(
      ((linkData ?? []) as VoucherWorkshopLinkRow[]).map((link) => [link.workshop_entry_id, link])
    );
    const voucherIds = Array.from(new Set(
      ((linkData ?? []) as VoucherWorkshopLinkRow[]).map((link) => link.voucher_id)
    ));
    const { data: voucherData, error: voucherError } = voucherIds.length === 0
      ? { data: [] as VoucherWorkshopMetadataRow[], error: null }
      : await supabase
          .from("expenses")
          .select("id, expense_no, expense_date")
          .in("id", voucherIds);
    if (voucherError) {
      console.error("Unable to resolve attached Voucher metadata:", voucherError);
      setWorkshopEntries([]);
      return;
    }
    const vouchersById = new Map(
      ((voucherData ?? []) as VoucherWorkshopMetadataRow[]).map((voucher) => [voucher.id, voucher])
    );

    setWorkshopEntries(workshopRows.map((entry) => {
      const items = [...(entry.workshop_entry_items ?? [])].sort((a,b) => a.line_no-b.line_no);
      const first = items[0]?.work_type ?? entry.work_type ?? "-";
      const voucherLink = linksByWorkshopEntry.get(entry.id);
      const voucher = voucherLink ? vouchersById.get(voucherLink.voucher_id) : undefined;
      return { id: entry.id, addaId: entry.adda_id, workDate: entry.work_date ?? "-", workshopName: entry.workshop_name ?? "-",
        vehicleId: entry.vehicle_id ?? "", vehicleNo: relationOne(entry.vehicles)?.vehicle_no ?? "-", billNo: entry.bill_no ?? "",
        totalCost: toNumber(entry.total_cost), workSummary: items.length > 1 ? `${first} +${items.length-1}` : first,
        attachedVoucherId: voucherLink?.voucher_id ?? null,
        attachedVoucherNo: voucher?.expense_no ?? null,
        attachedVoucherDate: voucher?.expense_date ?? null };
    }));
  }

  async function loadOilMasters() {
    const [productsResult, shopsResult] = await Promise.all([
      supabase
        .from("oil_products")
        .select("id, adda_id, oil_type, brand, grade, is_active")
        .eq("is_active", true)
        .order("oil_type", { ascending: true }),
      supabase
        .from("oil_shops")
        .select("id, adda_id, shop_name, shop_type, is_active")
        .eq("is_active", true)
        .eq("shop_type", "external_supplier")
        .order("shop_name", { ascending: true }),
    ]);

    if (productsResult.error) {
      console.error("Unable to load Oil Product options for Voucher:", productsResult.error);
      setOilProducts([]);
    } else {
      setOilProducts(
        (productsResult.data ?? []).map((product) => ({
          id: String(product.id),
          addaId: String(product.adda_id ?? ""),
          oilType: product.oil_type ?? "-",
          brand: product.brand ?? "",
          grade: product.grade ?? "",
        }))
      );
    }

    if (shopsResult.error) {
      console.error("Unable to load Oil Shop options for Voucher:", shopsResult.error);
      setOilShops([]);
    } else {
      setOilShops(
        (shopsResult.data ?? []).map((shop) => ({
          id: String(shop.id),
          addaId: String(shop.adda_id ?? ""),
          shopName: shop.shop_name ?? "-",
        }))
      );
    }
  }

  async function loadOilEntries() {
    const { data, error } = await supabase.from("oil_vehicle_entries").select(`
      id, adda_id, entry_date, vehicle_id, source_type, oil_shop_id, oil_product_id,
      liters, rate_per_liter, total_amount, bill_no,
      vehicles(vehicle_no), oil_products(oil_type, brand, grade), oil_shops(shop_name)
    `).gt("total_amount", 0).order("entry_date", { ascending: false });
    if (error) {
      console.error("Unable to load available Oil Entries for Voucher:", error);
      setOilEntries([]);
      return;
    }
    const rows = (data ?? []) as VoucherOilDatabaseRow[];
    const ids = rows.map((entry) => entry.id);
    const { data: linkData, error: linkError } = ids.length === 0
      ? { data: [] as VoucherOilLinkRow[], error: null }
      : await supabase.from("voucher_oil_entries").select("oil_vehicle_entry_id, voucher_id, link_origin").in("oil_vehicle_entry_id", ids);
    if (linkError) {
      console.error("Unable to resolve Oil Voucher attachment status:", linkError);
      setOilEntries([]);
      return;
    }
    const links = new Map(((linkData ?? []) as VoucherOilLinkRow[]).map((link) => [link.oil_vehicle_entry_id, link]));
    const voucherIds = Array.from(new Set(((linkData ?? []) as VoucherOilLinkRow[]).map((link) => link.voucher_id)));
    const { data: voucherData, error: voucherError } = voucherIds.length === 0
      ? { data: [] as VoucherWorkshopMetadataRow[], error: null }
      : await supabase.from("expenses").select("id, expense_no, expense_date").in("id", voucherIds);
    if (voucherError) {
      console.error("Unable to resolve Oil-linked Voucher metadata:", voucherError);
      setOilEntries([]);
      return;
    }
    const vouchers = new Map(((voucherData ?? []) as VoucherWorkshopMetadataRow[]).map((voucher) => [voucher.id, voucher]));
    setOilEntries(rows.map((entry) => {
      const product = relationOne(entry.oil_products);
      const vehicle = relationOne(entry.vehicles);
      const shop = relationOne(entry.oil_shops);
      const link = links.get(entry.id);
      const voucher = link ? vouchers.get(link.voucher_id) : undefined;
      return {
        id: entry.id, addaId: entry.adda_id, entryDate: entry.entry_date, vehicleId: entry.vehicle_id,
        vehicleNo: vehicle?.vehicle_no ?? "-",
        productName: [product?.oil_type, product?.brand, product?.grade].filter(Boolean).join(" · ") || "-",
        liters: toNumber(entry.liters), ratePerLiter: toNumber(entry.rate_per_liter), totalAmount: toNumber(entry.total_amount),
        billNo: entry.bill_no ?? "", sourceType: entry.source_type,
        oilShopName: shop?.shop_name ?? "",
        attachedVoucherId: link?.voucher_id ?? null, attachedVoucherNo: voucher?.expense_no ?? null,
        attachedVoucherDate: voucher?.expense_date ?? null,
      };
    }));
  }

  async function loadTyreMasters() {
    const [shopsResult, productsResult, assetsResult, positionsResult] =
      await Promise.all([
        supabase
          .from("tyre_shops")
          .select("id, adda_id, shop_name, shop_type, is_active")
          .eq("shop_type", "external_supplier")
          .eq("is_active", true)
          .order("shop_name", { ascending: true }),
        supabase
          .from("tyre_products")
          .select(
            "id, adda_id, brand, size, model_pattern, tyre_type, manufacturer, notes, is_active"
          )
          .eq("is_active", true)
          .order("brand", { ascending: true }),
        supabase
          .from("tyre_assets")
          .select(
            "id, adda_id, tyre_product_id, serial_number, normalized_serial_number, source_type, tyre_shop_id, purchase_reference, purchase_date, purchase_cost, current_status, current_vehicle_id, current_position_id, current_odometer"
          )
          .order("serial_number", { ascending: true }),
        supabase
          .from("vehicle_tyre_positions")
          .select(
            "id, adda_id, vehicle_id, axle_number, side, slot_number, is_spare, position_code, position_label, sort_order, is_active"
          )
          .eq("is_active", true)
          .order("sort_order", { ascending: true }),
      ]);

    if (shopsResult.error) {
      console.error("Unable to load Tyre Shop options for Voucher:", shopsResult.error);
      setTyreShops([]);
    } else {
      setTyreShops(
        (shopsResult.data ?? []).map((shop) => ({
          id: String(shop.id),
          addaId: String(shop.adda_id ?? ""),
          shopName: shop.shop_name ?? "-",
        }))
      );
    }

    if (productsResult.error) {
      console.error("Unable to load Tyre Products for Voucher:", productsResult.error);
      setTyreProducts([]);
    } else {
      setTyreProducts(
        (productsResult.data ?? []).map((product) => ({
          id: String(product.id),
          addaId: String(product.adda_id ?? ""),
          brand: product.brand ?? "",
          size: product.size ?? "",
          modelPattern: product.model_pattern ?? "",
          tyreType: product.tyre_type,
          manufacturer: product.manufacturer ?? "",
          notes: product.notes ?? "",
          isActive: Boolean(product.is_active),
        })) as TyreProduct[]
      );
    }

    if (assetsResult.error) {
      console.error("Unable to load Tyre Assets for Voucher:", assetsResult.error);
      setTyreAssets([]);
    } else {
      setTyreAssets(
        (assetsResult.data ?? []).map((asset) => ({
          id: String(asset.id),
          addaId: String(asset.adda_id ?? ""),
          tyreProductId: String(asset.tyre_product_id ?? ""),
          serialNumber: asset.serial_number ?? "",
          normalizedSerialNumber: asset.normalized_serial_number ?? "",
          sourceType: asset.source_type,
          tyreShopId: asset.tyre_shop_id ? String(asset.tyre_shop_id) : "",
          purchaseReference: asset.purchase_reference ?? "",
          purchaseDate: asset.purchase_date ?? "",
          purchaseCost: toNumber(asset.purchase_cost),
          currentStatus: asset.current_status,
          currentVehicleId: asset.current_vehicle_id
            ? String(asset.current_vehicle_id)
            : "",
          currentPositionId: asset.current_position_id
            ? String(asset.current_position_id)
            : "",
          currentOdometer:
            asset.current_odometer === null || asset.current_odometer === undefined
              ? null
              : toNumber(asset.current_odometer),
        })) as TyreAsset[]
      );
    }

    if (positionsResult.error) {
      console.error(
        "Unable to load Vehicle Tyre Positions for Voucher:",
        positionsResult.error
      );
      setTyrePositions([]);
    } else {
      setTyrePositions(
        (positionsResult.data ?? []).map((position) => ({
          id: String(position.id),
          addaId: String(position.adda_id ?? ""),
          vehicleId: String(position.vehicle_id ?? ""),
          axleNumber:
            position.axle_number === null || position.axle_number === undefined
              ? null
              : Number(position.axle_number),
          side: position.side,
          slotNumber: Number(position.slot_number ?? 0),
          isSpare: Boolean(position.is_spare),
          positionCode: position.position_code ?? "",
          positionLabel: position.position_label ?? "",
          sortOrder: Number(position.sort_order ?? 0),
          isActive: Boolean(position.is_active),
        })) as TyrePosition[]
      );
    }
  }

  async function loadTyreEntries() {
    const {data,error}=await supabase.from("tyre_vehicle_entries").select(`id,adda_id,entry_date,vehicle_id,tyre_shop_id,work_type,bill_no,total_amount,vehicles(vehicle_no),tyre_shops(shop_name),tyre_vehicle_entry_items(line_no,tyre_assets(serial_number),vehicle_tyre_positions(position_label))`).gt("total_amount",0).order("entry_date",{ascending:false});
    if(error){console.error("Unable to load Tyre Entries for Voucher:",error);setTyreEntries([]);return}const rows=(data??[])as unknown as VoucherTyreDatabaseRow[];const ids=rows.map(e=>e.id);const linksResult=ids.length?await supabase.from("voucher_tyre_entries").select("tyre_vehicle_entry_id,voucher_id,link_origin").in("tyre_vehicle_entry_id",ids):{data:[] as VoucherTyreLinkRow[],error:null};if(linksResult.error){console.error("Unable to resolve Tyre Voucher links:",linksResult.error);setTyreEntries([]);return}const links=new Map(((linksResult.data??[])as VoucherTyreLinkRow[]).map(x=>[x.tyre_vehicle_entry_id,x]));const voucherIds=Array.from(new Set(((linksResult.data??[])as VoucherTyreLinkRow[]).map(x=>x.voucher_id)));const vouchersResult=voucherIds.length?await supabase.from("expenses").select("id,expense_no,expense_date").in("id",voucherIds):{data:[] as VoucherWorkshopMetadataRow[],error:null};if(vouchersResult.error){console.error("Unable to resolve Tyre-linked Voucher metadata:",vouchersResult.error);setTyreEntries([]);return}const vouchers=new Map(((vouchersResult.data??[])as VoucherWorkshopMetadataRow[]).map(x=>[x.id,x]));setTyreEntries(rows.map(entry=>{const link=links.get(entry.id),voucher=link?vouchers.get(link.voucher_id):undefined;const itemRows=entry.tyre_vehicle_entry_items??[];return{id:entry.id,addaId:entry.adda_id,entryDate:entry.entry_date,vehicleId:entry.vehicle_id,vehicleNo:relationOne(entry.vehicles)?.vehicle_no??"-",shopName:relationOne(entry.tyre_shops)?.shop_name??"",billNo:entry.bill_no??"",workType:entry.work_type,serials:itemRows.flatMap(i=>{const a=relationOne(i.tyre_assets);return a?.serial_number?[a.serial_number]:[]}),positions:itemRows.flatMap(i=>{const p=relationOne(i.vehicle_tyre_positions);return p?.position_label?[p.position_label]:[]}),totalAmount:toNumber(entry.total_amount),attachedVoucherId:link?.voucher_id??null,attachedVoucherNo:voucher?.expense_no??null,attachedVoucherDate:voucher?.expense_date??null}}));
  }

  async function loadDriverEarnings() {
    const { data, error } = await supabase.from("driver_earnings").select(`
      id, adda_id, driver_id, vehicle_id, salary_date, salary_month, earning_type,
      basic_salary, trip_pay, bonus_allowance, deduction_fine, gross_expense,
      paid_amount, remaining_amount, payment_status, drivers(name), vehicles(vehicle_no)
    `).gt("gross_expense", 0).order("salary_date", { ascending: false });
    if (error) {
      console.error("Unable to load Driver earnings for Voucher:", error);
      setDriverEarnings([]);
      return;
    }
    const rows = (data ?? []) as unknown as VoucherDriverEarningDatabaseRow[];
    const ids = rows.map((entry) => entry.id);
    const linksResult = ids.length
      ? await supabase.from("voucher_driver_earnings").select("driver_earning_id, voucher_id").in("driver_earning_id", ids)
      : { data: [] as VoucherDriverEarningLinkRow[], error: null };
    if (linksResult.error) {
      console.error("Unable to resolve Driver earning Voucher links:", linksResult.error);
      setDriverEarnings([]);
      return;
    }
    const linkRows = (linksResult.data ?? []) as VoucherDriverEarningLinkRow[];
    const links = new Map(linkRows.map((link) => [link.driver_earning_id, link]));
    const voucherIds = Array.from(new Set(linkRows.map((link) => link.voucher_id)));
    const vouchersResult = voucherIds.length
      ? await supabase.from("expenses").select("id, expense_no, expense_date").in("id", voucherIds)
      : { data: [] as VoucherWorkshopMetadataRow[], error: null };
    if (vouchersResult.error) {
      console.error("Unable to resolve Driver-linked Voucher metadata:", vouchersResult.error);
      setDriverEarnings([]);
      return;
    }
    const vouchers = new Map(((vouchersResult.data ?? []) as VoucherWorkshopMetadataRow[]).map((voucher) => [voucher.id, voucher]));
    setDriverEarnings(rows.map((entry) => {
      const link = links.get(entry.id);
      const voucher = link ? vouchers.get(link.voucher_id) : undefined;
      return {
        id: entry.id,
        driverId: entry.driver_id,
        driverName: relationOne(entry.drivers)?.name ?? "-",
        salaryDate: entry.salary_date,
        salaryMonth: entry.salary_month,
        vehicleId: entry.vehicle_id,
        vehicleNo: relationOne(entry.vehicles)?.vehicle_no ?? "-",
        earningType: entry.earning_type,
        basicSalary: toNumber(entry.basic_salary),
        tripPay: toNumber(entry.trip_pay),
        bonusAllowance: toNumber(entry.bonus_allowance),
        deductionFine: toNumber(entry.deduction_fine),
        grossExpense: toNumber(entry.gross_expense),
        paidAmount: toNumber(entry.paid_amount),
        remainingAmount: toNumber(entry.remaining_amount),
        paymentStatus: entry.payment_status,
        attachedVoucherId: link?.voucher_id ?? null,
        attachedVoucherNo: voucher?.expense_no ?? null,
        attachedVoucherDate: voucher?.expense_date ?? null,
      };
    }));
  }

  async function loadExpenseVouchers() {
    const { data, error } = await supabase
      .from("expenses")
      .select(
        `
        *,
        loadings(
          *,
          vehicles(vehicle_no, owner_name),
          drivers(name),
          bookings(id, adda_id, booking_no, trip_type, bilty_group_id, vehicle_id, departure_date, arrival_date, freight, vehicle_freight, advance_vehicle)
        ),
        voucher_loadings(
          loading_id,
          loadings(
            id,
            loading_no,
            loading_date,
            route,
            vehicle_id,
            driver_id,
            vehicles(vehicle_no, owner_name),
            drivers(name),
            bookings(id, adda_id, booking_no, trip_type, bilty_group_id, vehicle_id, departure_date, arrival_date, freight, vehicle_freight, advance_vehicle)
          )
        ),
        expense_items(*),
        voucher_workshop_entries(
          workshop_entry_id,
          link_origin,
          workshop_entries(id, adda_id, work_date, workshop_name, vehicle_id, bill_no, work_type, total_cost, vehicles(vehicle_no), workshop_entry_items(line_no, work_type))
        ),
        voucher_oil_entries(
          oil_vehicle_entry_id,
          link_origin,
          oil_vehicle_entries(id, adda_id, entry_date, vehicle_id, source_type, oil_shop_id, oil_product_id, liters, rate_per_liter, total_amount, bill_no, vehicles(vehicle_no), oil_products(oil_type, brand, grade), oil_shops(shop_name))
        ),
        voucher_tyre_entries(
          tyre_vehicle_entry_id,
          link_origin,
          tyre_vehicle_entries(id, adda_id, entry_date, vehicle_id, tyre_shop_id, work_type, bill_no, total_amount, vehicles(vehicle_no), tyre_shops(shop_name), tyre_vehicle_entry_items(line_no, tyre_assets(serial_number), vehicle_tyre_positions(position_label)))
        ),
        voucher_driver_earnings(
          driver_earning_id,
          driver_earnings(id, adda_id, driver_id, vehicle_id, salary_date, salary_month, earning_type, basic_salary, trip_pay, bonus_allowance, deduction_fine, gross_expense, paid_amount, remaining_amount, payment_status, drivers(name), vehicles(vehicle_no))
        )
      `
      )
      .is("archived_at", null)
      .order("id", { ascending: false });

    if (error) {
      logExpenseLoadQueryError(
        "select expenses with loading, voucher-loading, expense-item, Workshop/Oil/Tyre, and driver-earning relations where archived_at is null; order by id desc",
        "public.expenses",
        error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }

    const vouchers = (data ?? []) as ExpenseVoucher[];
    const voucherIds = vouchers.map((voucher) => voucher.id);

    if (voucherIds.length === 0) {
      setExpenseVouchers([]);
      return;
    }

    // Manual Voucher expenses are loaded explicitly by their persisted FK.
    // Keep the existing embedded read for Bilty Vouchers unchanged, while
    // avoiding a nested-relation/client-mapping dependency for Manual rows.
    const manualVoucherIds = vouchers
      .filter((voucher) => voucher.voucher_source === "manual")
      .map((voucher) => voucher.id);
    const manualExpenseItemsResult = manualVoucherIds.length > 0
      ? await supabase
          .from("expense_items")
          .select("*")
          .in("expense_id", manualVoucherIds)
          .order("id", { ascending: true })
      : { data: [] as ExpenseItemRecord[], error: null };

    if (manualExpenseItemsResult.error) {
      logExpenseLoadQueryError(
        "select * from expense_items where expense_id in Manual Voucher ids order by id",
        "public.expense_items",
        manualExpenseItemsResult.error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }

    const manualExpenseItemsByVoucher = new Map<number, ExpenseItemRecord[]>();
    ((manualExpenseItemsResult.data ?? []) as ExpenseItemRecord[]).forEach((item) => {
      const voucherId = Number(item.expense_id);
      const currentItems = manualExpenseItemsByVoucher.get(voucherId) ?? [];
      currentItems.push(item);
      manualExpenseItemsByVoucher.set(voucherId, currentItems);
    });

    const [dieselResult, settlementResult, adjustmentResult, dieselPaymentResult] = await Promise.all([
      supabase
        .from("diesel_entries")
        .select(
          `
          *,
          petrol_pumps(pump_name)
        `
        )
        .in("expense_id", voucherIds),

      supabase
        .from("vehicle_chakkar_settlements")
        .select("id, voucher_id, movement_group_id, finalized_at")
        .in("voucher_id", voucherIds),

      // Load all Voucher Adjustments for the visible vouchers.
      // select("*") is intentional so this page does not depend on one exact
      // adjustment-total/status column name.
      supabase
        .from("voucher_adjustments")
        .select("*")
        .in("voucher_id", voucherIds),

      supabase
        .from("manual_voucher_diesel_initial_payments")
        .select("voucher_id,diesel_entry_id,payment_date,payment_method,reference_no,payment_remarks")
        .in("voucher_id", voucherIds),
    ]);

    if (dieselResult.error) {
      logExpenseLoadQueryError(
        "select diesel_entries with petrol_pumps where expense_id in visible Voucher ids",
        "public.diesel_entries",
        dieselResult.error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (settlementResult.error) {
      logExpenseLoadQueryError(
        "select id, voucher_id, movement_group_id, finalized_at from vehicle_chakkar_settlements where voucher_id in visible Voucher ids",
        "public.vehicle_chakkar_settlements",
        settlementResult.error
      );
      alert(
        "Finalized Voucher status could not be loaded. Please check the console."
      );
      return;
    }

    const dieselPaymentError = dieselPaymentResult.error;
    const manualDieselPaymentTableNotInstalled =
      dieselPaymentError?.code === "42P01" ||
      dieselPaymentError?.code === "PGRST205";
    if (manualDieselPaymentTableNotInstalled) {
      // This metadata table is introduced by the separately deployed Manual
      // Diesel payment migration. Until then, Diesel payment metadata is
      // optional and must not prevent the existing Voucher page from loading.
      console.warn("[/expenses] Optional Supabase query is not available yet:", {
        query: "select voucher_id,diesel_entry_id,payment_date,payment_method,reference_no,payment_remarks from public.manual_voucher_diesel_initial_payments filtered by voucher_id",
        table: "public.manual_voucher_diesel_initial_payments",
        code: dieselPaymentError.code,
        message: dieselPaymentError.message,
        details: dieselPaymentError.details,
        hint: dieselPaymentError.hint,
      });
    } else if (dieselPaymentError) {
      console.error("[/expenses] Supabase query failed:", {
        query: "select voucher_id,diesel_entry_id,payment_date,payment_method,reference_no,payment_remarks from public.manual_voucher_diesel_initial_payments filtered by voucher_id",
        table: "public.manual_voucher_diesel_initial_payments",
        code: dieselPaymentError.code,
        message: dieselPaymentError.message,
        details: dieselPaymentError.details,
        hint: dieselPaymentError.hint,
        error: dieselPaymentError,
      });
      alert(t("common.messages.loadFailed"));
      return;
    }

    if (adjustmentResult.error) {
      logExpenseLoadQueryError(
        "select * from voucher_adjustments where voucher_id in visible Voucher ids",
        "public.voucher_adjustments",
        adjustmentResult.error
      );
      alert("Voucher Adjustment summary could not be loaded. Please check the console.");
      return;
    }

    type AdjustmentRawRow = Record<string, unknown> & {
      id: string;
      voucher_id: number;
    };

    type AdjustmentItemRawRow = Record<string, unknown> & {
      adjustment_id: string;
    };

    const adjustmentRows = (adjustmentResult.data ?? []) as AdjustmentRawRow[];
    const adjustmentIds = adjustmentRows.map((row) => String(row.id));

    const adjustmentItemsResult =
      adjustmentIds.length === 0
        ? { data: [] as AdjustmentItemRawRow[], error: null }
        : await supabase
            .from("voucher_adjustment_items")
            .select("*")
            .in("adjustment_id", adjustmentIds);

    if (adjustmentItemsResult.error) {
      logExpenseLoadQueryError(
        "select * from voucher_adjustment_items where adjustment_id in visible Voucher Adjustment ids",
        "public.voucher_adjustment_items",
        adjustmentItemsResult.error
      );
      alert("Voucher Adjustment items could not be loaded. Please check the console.");
      return;
    }

    const adjustmentItemRows =
      (adjustmentItemsResult.data ?? []) as AdjustmentItemRawRow[];

    const manualDetailsResult = await supabase
      .from("manual_voucher_details")
      .select("*")
      .in("voucher_id", voucherIds);
    if (manualDetailsResult.error) {
      logExpenseLoadQueryError(
        "select * from manual_voucher_details where voucher_id in visible Voucher ids",
        "public.manual_voucher_details",
        manualDetailsResult.error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }
    const manualDetails = (manualDetailsResult.data ?? []) as ManualVoucherDetailRecord[];
    const manualSettlementResult = manualDetails.length > 0
      ? await supabase
          .from("manual_vehicle_chakkar_settlements")
          .select("id, voucher_id, total_freight, regular_expense_total, periodic_expense_total, total_expense_amount, net_vehicle_amount, freight_snapshot, expense_snapshot, finalized_at")
          .in("voucher_id", manualDetails.map((detail) => detail.voucher_id))
      : { data: [], error: null };
    if (manualSettlementResult.error) {
      logExpenseLoadQueryError(
        "select Manual settlement summary fields where voucher_id in Manual Voucher detail ids",
        "public.manual_vehicle_chakkar_settlements",
        manualSettlementResult.error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }
    const manualSettlementsByVoucher = new Map<number, ManualSettlementRecord>();
    (manualSettlementResult.data ?? []).forEach((settlement) => {
      manualSettlementsByVoucher.set(Number(settlement.voucher_id), settlement as unknown as ManualSettlementRecord);
    });
    const manualDetailIds = manualDetails.map((detail) => detail.id);
    const manualFreightResult = manualDetailIds.length > 0
      ? await supabase
          .from("manual_voucher_freight_items")
          .select("id, manual_voucher_id, freight_type, amount, description, sequence_no")
          .in("manual_voucher_id", manualDetailIds)
          .order("sequence_no")
      : { data: [] as ManualFreightRecord[], error: null };
    if (manualFreightResult.error) {
      logExpenseLoadQueryError(
        "select freight fields from manual_voucher_freight_items where manual_voucher_id in Manual Voucher detail ids order by sequence_no",
        "public.manual_voucher_freight_items",
        manualFreightResult.error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }
    const manualAdjustmentResult = manualDetails.length > 0
      ? await supabase
          .from("manual_voucher_adjustments")
          .select("*")
          .in("voucher_id", manualDetails.map((detail) => detail.voucher_id))
          .order("created_at", { ascending: true })
      : { data: [] as ManualVoucherAdjustment[], error: null };
    if (manualAdjustmentResult.error) {
      logExpenseLoadQueryError(
        "select Manual Voucher adjustments where voucher_id in visible Manual Voucher ids order by created_at",
        "public.manual_voucher_adjustments",
        manualAdjustmentResult.error
      );
      alert(t("common.messages.loadFailed"));
      return;
    }
    const manualAdjustmentsByVoucher = new Map<number, ManualVoucherAdjustment[]>();
    ((manualAdjustmentResult.data ?? []) as ManualVoucherAdjustment[]).forEach((adjustment) => {
      const rows = manualAdjustmentsByVoucher.get(adjustment.voucher_id) ?? [];
      rows.push(adjustment);
      manualAdjustmentsByVoucher.set(adjustment.voucher_id, rows);
    });
    const vehicleIds = Array.from(new Set(manualDetails.map((detail) => detail.vehicle_id)));
    const driverIds = Array.from(new Set(manualDetails.flatMap((detail) => detail.driver_id ? [detail.driver_id] : [])));
    const [manualVehicleResult, manualDriverResult] = await Promise.all([
      vehicleIds.length > 0
        ? supabase.from("vehicles").select("id, vehicle_no, owner_name").in("id", vehicleIds)
        : Promise.resolve({ data: [], error: null }),
      driverIds.length > 0
        ? supabase.from("drivers").select("id, name").in("id", driverIds)
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (manualVehicleResult.error || manualDriverResult.error) {
      if (manualVehicleResult.error) {
        logExpenseLoadQueryError(
          "select id, vehicle_no, owner_name from vehicles where id in Manual Voucher vehicle ids",
          "public.vehicles",
          manualVehicleResult.error
        );
      }
      if (manualDriverResult.error) {
        logExpenseLoadQueryError(
          "select id, name from drivers where id in Manual Voucher driver ids",
          "public.drivers",
          manualDriverResult.error
        );
      }
      alert(t("common.messages.loadFailed"));
      return;
    }
    const manualVehiclesById = new Map((manualVehicleResult.data ?? []).map((row) => [row.id, { vehicleNo: row.vehicle_no, ownerName: row.owner_name }]));
    const manualDriversById = new Map((manualDriverResult.data ?? []).map((row) => [row.id, row.name]));
    const manualFreightByDetail = new Map<string, ManualFreightRecord[]>();
    (manualFreightResult.data ?? []).forEach((row) => {
      const rows = manualFreightByDetail.get(row.manual_voucher_id) ?? [];
      rows.push(row);
      manualFreightByDetail.set(row.manual_voucher_id, rows);
    });
    const manualDetailsByVoucher = new Map<number, ManualVoucherDetailRecord>();
    manualDetails.forEach((detail) => {
      manualDetailsByVoucher.set(detail.voucher_id, {
        ...detail,
        manual_vehicle_chakkar_settlements: manualSettlementsByVoucher.has(detail.voucher_id)
          ? [manualSettlementsByVoucher.get(detail.voucher_id)!]
          : [],
        vehicle_no: manualVehiclesById.get(detail.vehicle_id)?.vehicleNo ?? "-",
        vehicle_owner: manualVehiclesById.get(detail.vehicle_id)?.ownerName ?? null,
        driver_name: detail.driver_id ? manualDriversById.get(detail.driver_id) ?? null : null,
        manual_voucher_freight_items: manualFreightByDetail.get(detail.id) ?? [],
      });
    });

    const readNumeric = (row: Record<string, unknown>, keys: string[]) => {
      for (const key of keys) {
        const value = row[key];
        if (value !== null && value !== undefined && value !== "") {
          const numeric = Number(value);
          if (Number.isFinite(numeric)) return numeric;
        }
      }
      return 0;
    };

    const readText = (row: Record<string, unknown>, keys: string[]) => {
      for (const key of keys) {
        const value = row[key];
        if (typeof value === "string" && value.trim()) return value.trim();
      }
      return "";
    };

    const adjustmentItemsByAdjustment = new Map<string, AdjustmentItemRawRow[]>();
    adjustmentItemRows.forEach((item) => {
      const key = String(item.adjustment_id);
      const current = adjustmentItemsByAdjustment.get(key) ?? [];
      current.push(item);
      adjustmentItemsByAdjustment.set(key, current);
    });

    const adjustmentSummariesByVoucher = new Map<number, VoucherAdjustmentSummary[]>();

    adjustmentRows.forEach((row) => {
      const itemRows = adjustmentItemsByAdjustment.get(String(row.id)) ?? [];
      const itemTotal = itemRows.reduce(
        (sum, item) =>
          sum +
          readNumeric(item, [
            "amount",
            "total_amount",
            "expense_amount",
            "adjustment_amount",
          ]),
        0
      );

      const headerTotal = readNumeric(row, [
        "total_amount",
        "adjustment_total",
        "total_adjustment",
        "amount",
      ]);

      const status =
        readText(row, ["status", "adjustment_status"]) ||
        (row["finalized_at"] ? "finalized" : "draft");

      const summary: VoucherAdjustmentSummary = {
        id: String(row.id),
        status,
        totalAmount: headerTotal > 0 ? headerTotal : itemTotal,
        finalizedAt:
          typeof row["finalized_at"] === "string"
            ? String(row["finalized_at"])
            : null,
      };

      const voucherId = Number(row.voucher_id);
      const current = adjustmentSummariesByVoucher.get(voucherId) ?? [];
      current.push(summary);
      adjustmentSummariesByVoucher.set(voucherId, current);
    });

    const dieselPaymentDetails = new Map<number, {
      paymentDate: string;
      paymentMethod: string;
      paymentReference: string | null;
      paymentRemarks: string | null;
    }>();
    (manualDieselPaymentTableNotInstalled ? [] : dieselPaymentResult.data ?? []).forEach((row) => {
      dieselPaymentDetails.set(Number(row.diesel_entry_id), {
        paymentDate: row.payment_date,
        paymentMethod: row.payment_method,
        paymentReference: row.reference_no,
        paymentRemarks: row.payment_remarks,
      });
    });
    const dieselEntries = ((dieselResult.data ?? []) as DieselEntryRecord[]).map((diesel) => {
      const payment = dieselPaymentDetails.get(diesel.id);
      return {
        ...diesel,
        initial_payment_date: payment?.paymentDate ?? null,
        initial_payment_method: payment?.paymentMethod ?? null,
        initial_payment_reference: payment?.paymentReference ?? null,
        initial_payment_remarks: payment?.paymentRemarks ?? null,
      };
    });

    type SettlementListRow = {
      id: string;
      voucher_id: number;
      movement_group_id: string;
      finalized_at: string;
    };

    const settlementRows =
      (settlementResult.data ?? []) as SettlementListRow[];

    const settlementsByVoucher = new Map<number, SettlementListRow[]>();

    settlementRows.forEach((settlement) => {
      const current = settlementsByVoucher.get(settlement.voucher_id) ?? [];
      current.push(settlement);
      settlementsByVoucher.set(settlement.voucher_id, current);
    });

    setExpenseVouchers(
      vouchers.map((voucher) => ({
        ...voucher,
        expense_items: voucher.voucher_source === "manual"
          ? manualExpenseItemsByVoucher.get(voucher.id) ?? []
          : voucher.expense_items ?? [],
        vehicle_chakkar_settlements:
          settlementsByVoucher.get(voucher.id) ?? [],
        voucher_adjustment_summaries:
          adjustmentSummariesByVoucher.get(voucher.id) ?? [],
        manual_voucher_adjustments:
          manualAdjustmentsByVoucher.get(voucher.id) ?? [],
        manual_voucher_details: manualDetailsByVoucher.get(voucher.id) ?? null,
        diesel_entries: dieselEntries.filter(
          (diesel) => diesel.expense_id === voucher.id
        ),
      }))
    );
  }

  function resetForm() {
    setVoucherMode("bilty");
    setExpenseNo("");
    setExpenseDate("");
    setEndDate("");
    setSelectedLoadingIds([]);
    setSelectedMovementGroupId(null);
    setSelectedWorkshopEntryIds([]);
    setWorkshopMode("existing");
    setWorkshopCreateData(createEmptyVoucherWorkshopData());
    setOilMode("existing");
    setSelectedOilEntryIds([]);
    setPendingOilCreatePayload(null);
    setTyreMode("existing");
    setSelectedTyreEntryIds([]);
    setPendingTyreCreatePayload(null);
    setManualSourceCreatedTotals({});
    setSelectedDriverEarningIds([]);
    setDescription("");
    setManualVehicleId("");
    setManualDriverId("");
    setManualChakkarDays("");
    setManualDepartureDate("");
    setManualArrivalDate("");
    setHasPersistedManualDates(false);
    setManualFreightRows([
      createManualFreightInput("outbound"),
      createManualFreightInput("local"),
      createManualFreightInput("return"),
    ]);
    setManualDieselRows([]);
    setExpenseItems([createEmptyExpenseItem()]);
    setManualSourceEditTarget(null);
    setEditingId(null);
  }

  function updateManualFreightRow(clientId: string, field: "amount" | "description", value: string) {
    setManualFreightRows((rows) => rows.map((row) =>
      row.clientId === clientId ? { ...row, [field]: value } : row
    ));
  }

  function addManualLocalRow() {
    setManualFreightRows((rows) => [...rows, createManualFreightInput("local")]);
  }

  function removeManualLocalRow(clientId: string) {
    setManualFreightRows((rows) => rows.filter((row) =>
      row.clientId !== clientId || row.freightType !== "local"
    ));
  }

  function addManualDieselRow() {
    setManualDieselRows((rows) => [...rows, createManualDieselInput(expenseDate)]);
  }

  function updateManualDieselRow(
    clientId: string,
    field: keyof Omit<ManualDieselInput, "clientId" | "dieselEntryId" | "requestId" | "paymentRecorded">,
    value: string
  ) {
    setManualDieselRows((rows) => rows.map((row) =>
      row.clientId === clientId ? { ...row, [field]: value } : row
    ));
  }

  function removeManualDieselRow(clientId: string) {
    setManualDieselRows((rows) => rows.filter((row) =>
      row.clientId !== clientId || row.dieselEntryId !== null
    ));
  }

  function changeVoucherMode(nextMode: "bilty" | "manual") {
    if (editingId !== null || isSaving) return;
    setVoucherMode(nextMode);
    setExpenseNo("");
    setExpenseDate("");
    setDescription("");
    setSelectedLoadingIds([]);
    setSelectedMovementGroupId(null);
    setExpenseItems([createEmptyExpenseItem()]);
    if (nextMode === "manual") {
      setManualDepartureDate("");
      setManualArrivalDate("");
      setHasPersistedManualDates(false);
      setEndDate("");
      setSelectedWorkshopEntryIds([]);
      setWorkshopMode("existing");
      setWorkshopCreateData(createEmptyVoucherWorkshopData());
      setSelectedOilEntryIds([]);
      setOilMode("existing");
      setPendingOilCreatePayload(null);
      setSelectedTyreEntryIds([]);
      setTyreMode("existing");
      setPendingTyreCreatePayload(null);
      setManualSourceCreatedTotals({});
      setSelectedDriverEarningIds([]);
      setManualDieselRows([]);
    } else {
      setManualVehicleId("");
      setManualDriverId("");
      setManualChakkarDays("");
      setManualDepartureDate("");
      setManualArrivalDate("");
      setHasPersistedManualDates(false);
      setManualDieselRows([]);
      setManualFreightRows([
        createManualFreightInput("outbound"),
        createManualFreightInput("local"),
        createManualFreightInput("return"),
      ]);
    }
  }

  function handleAddExpenseItem(expenseClass: ExpenseClass) {
    setExpenseItems((previous) => [
      ...previous,
      createEmptyExpenseItem(expenseClass),
    ]);
  }

  function handleDeleteExpenseItem(rowId: number) {
    if (expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Workshop") {
      setSelectedWorkshopEntryIds([]);
      setWorkshopMode("existing");
      setWorkshopCreateData(createEmptyVoucherWorkshopData());
    }
    if (expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Oil / Lubricants") {
      setSelectedOilEntryIds([]);
      setPendingOilCreatePayload(null);
    }
    if (expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Tyre") {
      setSelectedTyreEntryIds([]);
      setPendingTyreCreatePayload(null);
    }
    if (expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Driver Salary") setSelectedDriverEarningIds([]);
    setExpenseItems((previous) =>
      previous.length === 1
        ? [createEmptyExpenseItem()]
        : previous.filter((item) => item.rowId !== rowId)
    );
  }

  function onExpenseItemChange(
    rowId: number,
    field: keyof ExpenseItemRow,
    value: string
  ) {
    if (field === "expenseType" && value !== "Workshop" && expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Workshop") {
      setSelectedWorkshopEntryIds([]);
      setWorkshopMode("existing");
      setWorkshopCreateData(createEmptyVoucherWorkshopData());
    }
    if (field === "expenseType" && value !== "Oil / Lubricants" && expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Oil / Lubricants") {
      setSelectedOilEntryIds([]);
      setPendingOilCreatePayload(null);
    }
    if (
      field === "expenseType" &&
      value !== "Tyre" &&
      expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Tyre"
    ) {
      setSelectedTyreEntryIds([]);
      setPendingTyreCreatePayload(null);
    }
    if (field === "expenseType" && value !== "Driver Salary" && expenseItems.find((item) => item.rowId === rowId)?.expenseType === "Driver Salary") setSelectedDriverEarningIds([]);
    setExpenseItems((previous) =>
      previous.map((item) => {
        if (item.rowId !== rowId) return item;

        const updated: ExpenseItemRow = {
          ...item,
          [field]: value,
        };

        if (field === "expenseClass") {
          const nextClass = normalizeExpenseClass(value);
          updated.expenseClass = nextClass;
          if (!EXPENSE_TYPES_BY_CLASS[nextClass].includes(updated.expenseType)) {
            updated.expenseType = "";
          }
        }

        if (field === "expenseType" && value !== "Fuel") {
          updated.petrolPumpId = "";
          updated.liters = "";
          updated.rate = "";
          updated.paidAmount = "";
          updated.slipNo = "";
        }

        if (field === "expenseType" && value === "Driver Salary") {
          updated.amount = "";
        }

        if (
          updated.expenseType === "Fuel" &&
          (field === "liters" || field === "rate")
        ) {
          const totalAmount = toNumber(updated.liters) * toNumber(updated.rate);
          updated.amount = totalAmount > 0 ? String(totalAmount) : "";
        }

        return updated;
      })
    );
  }

  function workshopCreateTotal(data: VoucherWorkshopCreateData) {
    return data.items.reduce(
      (sum, item) => sum + toNumber(item.quantity) * toNumber(item.rate),
      0
    );
  }

  function handleWorkshopModeChange(mode: VoucherWorkshopMode) {
    setWorkshopMode(mode);

    if (mode === "create") {
      setSelectedWorkshopEntryIds([]);
      const total = workshopCreateTotal(workshopCreateData);
      setExpenseItems((items) =>
        items.map((item) =>
          item.expenseType === "Workshop"
            ? { ...item, amount: total > 0 ? String(total) : "" }
            : item
        )
      );
      return;
    }

    const total = eligibleWorkshopEntries
      .filter((entry) => selectedWorkshopEntryIds.includes(entry.id))
      .reduce((sum, entry) => sum + entry.totalCost, 0);

    setExpenseItems((items) =>
      items.map((item) =>
        item.expenseType === "Workshop"
          ? { ...item, amount: total > 0 ? String(total) : "" }
          : item
      )
    );
  }

  function handleWorkshopCreateDataChange(data: VoucherWorkshopCreateData) {
    setWorkshopCreateData(data);

    if (workshopMode !== "create") return;

    const total = workshopCreateTotal(data);
    setExpenseItems((items) =>
      items.map((item) =>
        item.expenseType === "Workshop"
          ? {
              ...item,
              amount: total > 0 ? String(total) : "",
              paymentMethod: data.paymentMethod || item.paymentMethod,
              remarks: data.voucherItemRemarks,
            }
          : item
      )
    );
  }

  function handleWorkshopSelectionChange(ids: number[]) {
    if (!activeVoucherVehicleId) {
      setSelectedWorkshopEntryIds([]);
      setExpenseItems((items) =>
        items.map((item) =>
          item.expenseType === "Workshop" ? { ...item, amount: "" } : item
        )
      );
      return;
    }

    const allowedIds = new Set(
      eligibleWorkshopEntries
        .filter((entry) => entry.vehicleId === activeVoucherVehicleId)
        .map((entry) => entry.id)
    );

    const uniqueIds = Array.from(new Set(ids)).filter((id) =>
      allowedIds.has(id)
    );

    const total = eligibleWorkshopEntries
      .filter(
        (entry) =>
          entry.vehicleId === activeVoucherVehicleId &&
          uniqueIds.includes(entry.id)
      )
      .reduce((sum, entry) => sum + entry.totalCost, 0);

    setWorkshopMode("existing");
    setSelectedWorkshopEntryIds(uniqueIds);
    setExpenseItems((items) =>
      items.map((item) =>
        item.expenseType === "Workshop"
          ? { ...item, amount: total > 0 ? String(total) : "" }
          : item
      )
    );
  }

  function handleOilSelectionChange(ids: string[]) {
    const uniqueIds = Array.from(new Set(ids));
    const total = eligibleOilEntries
      .filter((entry) => uniqueIds.includes(entry.id))
      .reduce((sum, entry) => sum + entry.totalAmount, 0);

    setPendingOilCreatePayload(null);
    setSelectedOilEntryIds(uniqueIds);
    setExpenseItems((items) =>
      items.map((item) =>
        item.expenseType === "Oil / Lubricants"
          ? { ...item, amount: total > 0 ? String(total) : "" }
          : item
      )
    );
  }

  function handleOilModeChange(mode: "existing" | "create") {
    setOilMode(mode);
    setPendingOilCreatePayload(null);
    if (mode === "create") setSelectedOilEntryIds([]);
  }

  async function handleCreateOilEntry(payload: VoucherOilCreatePayload) {
    if (!activeVoucherVehicleId) {
      alert("Voucher Vehicle select karein.");
      return;
    }

    const total = payload.liters * payload.ratePerLiter;
    if (!Number.isFinite(total) || total <= 0) {
      alert("Oil Total zero se zyada hona chahiye.");
      return;
    }

    setIsCreatingOilEntry(true);
    try {
      setSelectedOilEntryIds([]);
      setPendingOilCreatePayload(payload);
      setExpenseItems((items) =>
        items.map((item) =>
          item.expenseType === "Oil / Lubricants"
            ? {
                ...item,
                amount: String(total),
                paymentMethod: payload.paymentMethod || item.paymentMethod,
                remarks: payload.voucherItemRemarks,
              }
            : item
        )
      );
    } finally {
      setIsCreatingOilEntry(false);
    }
  }
  function handleTyreSelectionChange(ids: string[]) {
    const uniqueIds = Array.from(new Set(ids));
    const total = eligibleTyreEntries
      .filter((entry) => uniqueIds.includes(entry.id))
      .reduce((sum, entry) => sum + entry.totalAmount, 0);

    setPendingTyreCreatePayload(null);
    setSelectedTyreEntryIds(uniqueIds);
    setExpenseItems((items) =>
      items.map((item) =>
        item.expenseType === "Tyre"
          ? { ...item, amount: total > 0 ? String(total) : "" }
          : item
      )
    );
  }

  function handleTyreModeChange(mode: "existing" | "create") {
    setTyreMode(mode);
    setPendingTyreCreatePayload(null);
    if (mode === "create") setSelectedTyreEntryIds([]);
  }

  function handleCreateTyreEntry(payload: VoucherTyreCreatePayload) {
    if (!activeVoucherVehicleId) {
      alert("Voucher Vehicle select karein.");
      return;
    }

    const total = payload.items.reduce(
      (sum, item) => sum + item.quantity * item.rate,
      0
    );

    if (!Number.isFinite(total) || total <= 0) {
      alert("Tyre Total zero se zyada hona chahiye.");
      return;
    }

    setIsCreatingTyreEntry(true);
    try {
      setSelectedTyreEntryIds([]);
      setPendingTyreCreatePayload(payload);
      setExpenseItems((items) =>
        items.map((item) =>
          item.expenseType === "Tyre"
            ? {
                ...item,
                amount: String(total),
                paymentMethod: payload.paymentMethod || item.paymentMethod,
                remarks: payload.voucherItemRemarks,
              }
            : item
        )
      );
    } finally {
      setIsCreatingTyreEntry(false);
    }
  }
  function handleDriverEarningSelectionChange(ids: string[]) {
    const uniqueIds = Array.from(new Set(ids));
    const total = eligibleDriverEarnings.filter((entry) => uniqueIds.includes(entry.id)).reduce((sum, entry) => sum + entry.grossExpense, 0);
    setSelectedDriverEarningIds(uniqueIds);
    setExpenseItems((items) => items.map((item) => item.expenseType === "Driver Salary" ? { ...item, amount: total > 0 ? String(total) : "" } : item));
  }

  function handleReceiptSelected(rowId: number, file: File) {
    setExpenseItems((previous) =>
      previous.map((item) => {
        if (item.rowId !== rowId) return item;

        if (!isAllowedReceipt(file)) {
          return {
            ...item,
            receiptFile: null,
            receiptError: t("expenses.validation.receiptType"),
          };
        }

        if (file.size > 5 * 1024 * 1024) {
          return {
            ...item,
            receiptFile: null,
            receiptError: t("expenses.validation.receiptSize"),
          };
        }

        return {
          ...item,
          receiptFile: file,
          receiptName: file.name,
          receiptError: "",
        };
      })
    );
  }

  async function handleReceiptDelete(rowId: number) {
    const item = expenseItems.find((currentItem) => currentItem.rowId === rowId);

    if (!item) return;

    setExpenseItems((previous) =>
      previous.map((currentItem) =>
        currentItem.rowId === rowId
          ? { ...currentItem, receiptStatus: "deleting", receiptError: "" }
          : currentItem
      )
    );

    try {
      if (item.receiptUrl) {
        const path = getReceiptPath(item.receiptUrl);

        if (path) {
          const { error } = await supabase.storage
            .from("expense-receipts")
            .remove([path]);

          if (error) throw new Error(error.message);
        }
      }

      if (item.dbId) {
        const { error } = await supabase
          .from("expense_items")
          .update({
            receipt_url: null,
            receipt_name: null,
          })
          .eq("id", item.dbId);

        if (error) throw new Error(error.message);
      }

      setExpenseItems((previous) =>
        previous.map((currentItem) =>
          currentItem.rowId === rowId
            ? {
                ...currentItem,
                receiptUrl: null,
                receiptName: null,
                receiptFile: null,
                receiptStatus: "idle",
                receiptError: "",
              }
            : currentItem
        )
      );
    } catch (error) {
      console.error("Unable to delete expense receipt:", error);

      setExpenseItems((previous) =>
        previous.map((currentItem) =>
          currentItem.rowId === rowId
            ? {
                ...currentItem,
                receiptStatus: "idle",
                receiptError: t("common.messages.deleteFailed"),
              }
            : currentItem
        )
      );
    }
  }

  function handlePreviewReceipt(receiptUrl: string) {
    const previewWindow = window.open(receiptUrl, "_blank");
    if (!previewWindow) {
      alert(t("expenses.messages.allowPopups"));
    }
  }

  function validateExpenseVoucher(fuelLoading: LoadingRecord | null = selectedLoading) {
    if (!expenseNo.trim()) {
      alert(t("expenses.validation.voucherNoRequired"));
      return false;
    }

    if (!expenseDate) {
      alert(t("expenses.validation.startDateRequired"));
      return false;
    }

    if (!endDate) {
      alert(t("expenses.validation.endDateRequired"));
      return false;
    }

    if (endDate < expenseDate) {
      alert(t("expenses.validation.endBeforeStart"));
      return false;
    }

    if (!selectedMovementGroupId) {
      alert(t("expenses.validation.movementGroupRequired"));
      return false;
    }

    const selectedGroup = completedMovementGroups.find((group) => group.id === selectedMovementGroupId);
    if (!selectedGroup || !selectedGroup.selectable) {
      alert(t("expenses.validation.movementGroupAlreadyVouchered"));
      return false;
    }

    if (expenseItems.length === 0) {
      alert(t("expenses.validation.itemRequired"));
      return false;
    }

    const workshopRows = expenseItems.filter((item) => item.expenseType === "Workshop");
    if (workshopRows.length > 1) {
      alert(t("expenses.workshopLink.validation.singleRow"));
      return false;
    }

    if (workshopRows.length === 1) {
      if (workshopRows[0].expenseClass !== "vehicle_periodic") {
        alert(t("expenses.workshopLink.validation.required"));
        return false;
      }

      if (workshopMode === "existing") {
        const expected = eligibleWorkshopEntries
          .filter((entry) => selectedWorkshopEntryIds.includes(entry.id))
          .reduce((sum, entry) => sum + entry.totalCost, 0);

        if (selectedWorkshopEntryIds.length === 0 || expected <= 0) {
          alert(t("expenses.workshopLink.validation.required"));
          return false;
        }

        if (toNumber(workshopRows[0].amount) !== expected) {
          alert(t("expenses.workshopLink.validation.amountMismatch"));
          return false;
        }
      } else {
        const total = workshopCreateTotal(workshopCreateData);
        const paid = toNumber(workshopCreateData.paidAmount);

        if (selectedWorkshopEntryIds.length > 0) {
          alert("Create New Workshop Bill ke sath existing Workshop Bill select nahi ho sakta.");
          return false;
        }

        if (!workshopCreateData.workDate) {
          alert("Workshop Work Date required hai.");
          return false;
        }

        if (!workshopCreateData.workshopId) {
          alert("Workshop select karein.");
          return false;
        }

        if (
          workshopCreateData.items.length === 0 ||
          workshopCreateData.items.some(
            (item) =>
              !item.workType.trim() ||
              toNumber(item.quantity) <= 0 ||
              toNumber(item.rate) < 0
          )
        ) {
          alert("Workshop Work Items complete karein: Work Type, Quantity aur Rate required hain.");
          return false;
        }

        if (total <= 0) {
          alert("Workshop Bill Total zero se zyada hona chahiye.");
          return false;
        }

        if (paid < 0 || paid > total) {
          alert("Workshop Paid Amount 0 se kam ya Total Bill se zyada nahi ho sakta.");
          return false;
        }

        if (!workshopCreateData.paymentMethod.trim()) {
          alert("Workshop Payment Method required hai.");
          return false;
        }

        if (toNumber(workshopRows[0].amount) !== total) {
          alert("Workshop Voucher amount aur Workshop Work Items total match nahi kar rahe.");
          return false;
        }
      }
    } else if (
      selectedWorkshopEntryIds.length > 0 ||
      workshopMode === "create"
    ) {
      alert(t("expenses.workshopLink.validation.required"));
      return false;
    }

    const oilRows = expenseItems.filter((item) => item.expenseType === "Oil / Lubricants");
    if (oilRows.length > 1) {
      alert(t("expenses.oilLink.validation.singleRow"));
      return false;
    }

    if (oilRows.length === 1) {
      if (oilRows[0].expenseClass !== "vehicle_periodic") {
        alert(t("expenses.oilLink.validation.required"));
        return false;
      }

      if (pendingOilCreatePayload) {
        const createTotal =
          pendingOilCreatePayload.liters * pendingOilCreatePayload.ratePerLiter;

        if (selectedOilEntryIds.length > 0) {
          alert("Create New Oil Entry ke sath existing Oil Entry select nahi ho sakti.");
          return false;
        }

        if (!pendingOilCreatePayload.entryDate) {
          alert("Oil Entry Date required hai.");
          return false;
        }

        if (!pendingOilCreatePayload.oilProductId) {
          alert("Oil Product select karein.");
          return false;
        }

        if (
          pendingOilCreatePayload.sourceType === "external_shop" &&
          !pendingOilCreatePayload.oilShopId
        ) {
          alert("External Oil Shop select karein.");
          return false;
        }

        if (
          !Number.isFinite(pendingOilCreatePayload.liters) ||
          pendingOilCreatePayload.liters <= 0 ||
          !Number.isFinite(pendingOilCreatePayload.ratePerLiter) ||
          pendingOilCreatePayload.ratePerLiter < 0 ||
          createTotal <= 0
        ) {
          alert("Oil Litres aur Rate valid honay chahiye.");
          return false;
        }

        if (toNumber(oilRows[0].amount) !== createTotal) {
          alert("Oil Voucher amount aur Create New Oil total match nahi kar rahe.");
          return false;
        }
      } else {
        const expected = eligibleOilEntries
          .filter((entry) => selectedOilEntryIds.includes(entry.id))
          .reduce((sum, entry) => sum + entry.totalAmount, 0);

        if (selectedOilEntryIds.length === 0 || expected <= 0) {
          alert(t("expenses.oilLink.validation.required"));
          return false;
        }

        if (toNumber(oilRows[0].amount) !== expected) {
          alert(t("expenses.oilLink.validation.amountMismatch"));
          return false;
        }
      }
    } else if (selectedOilEntryIds.length > 0 || pendingOilCreatePayload) {
      alert(t("expenses.oilLink.validation.required"));
      return false;
    }

    const tyreRows = expenseItems.filter((item) => item.expenseType === "Tyre");
    if (tyreRows.length > 1) {
      alert(t("expenses.tyreLink.validation.singleRow"));
      return false;
    }

    if (tyreRows.length === 1) {
      if (tyreRows[0].expenseClass !== "vehicle_periodic") {
        alert(t("expenses.tyreLink.validation.required"));
        return false;
      }

      if (pendingTyreCreatePayload) {
        const createTotal = pendingTyreCreatePayload.items.reduce(
          (sum, item) => sum + item.quantity * item.rate,
          0
        );

        if (selectedTyreEntryIds.length > 0) {
          alert("Create New Tyre Entry ke sath existing Tyre Entry select nahi ho sakti.");
          return false;
        }

        if (!pendingTyreCreatePayload.entryDate) {
          alert("Tyre Entry Date required hai.");
          return false;
        }

        if (
          pendingTyreCreatePayload.sourceType === "external_shop" &&
          !pendingTyreCreatePayload.tyreShopId
        ) {
          alert("External Tyre Shop select karein.");
          return false;
        }

        if (
          pendingTyreCreatePayload.items.length === 0 ||
          pendingTyreCreatePayload.items.some(
            (item) =>
              !item.workType ||
              !Number.isFinite(item.quantity) ||
              item.quantity <= 0 ||
              !Number.isFinite(item.rate) ||
              item.rate < 0
          ) ||
          !Number.isFinite(createTotal) ||
          createTotal <= 0
        ) {
          alert("Tyre lines, Quantity aur Rate complete karein.");
          return false;
        }

        if (!pendingTyreCreatePayload.paymentMethod.trim()) {
          alert("Tyre Payment Method required hai.");
          return false;
        }

        if (toNumber(tyreRows[0].amount) !== createTotal) {
          alert("Tyre Voucher amount aur Create New Tyre total match nahi kar rahe.");
          return false;
        }
      } else {
        const expected = eligibleTyreEntries
          .filter((entry) => selectedTyreEntryIds.includes(entry.id))
          .reduce((sum, entry) => sum + entry.totalAmount, 0);

        if (selectedTyreEntryIds.length === 0 || expected <= 0) {
          alert(t("expenses.tyreLink.validation.required"));
          return false;
        }

        if (toNumber(tyreRows[0].amount) !== expected) {
          alert(t("expenses.tyreLink.validation.amountMismatch"));
          return false;
        }
      }
    } else if (selectedTyreEntryIds.length > 0 || pendingTyreCreatePayload) {
      alert(t("expenses.tyreLink.validation.required"));
      return false;
    }

    const driverRows = expenseItems.filter((item) => item.expenseType === "Driver Salary");
    if (driverRows.length > 1) { alert(t("expenses.driverLink.validation.singleRow")); return false; }
    if (driverRows.length === 1) {
      const expected = eligibleDriverEarnings.filter((entry) => selectedDriverEarningIds.includes(entry.id)).reduce((sum, entry) => sum + entry.grossExpense, 0);
      if (driverRows[0].expenseClass !== "vehicle_periodic" || selectedDriverEarningIds.length === 0 || expected <= 0) {
        alert(t("expenses.driverLink.validation.required")); return false;
      }
      if (toNumber(driverRows[0].amount) !== expected) { alert(t("expenses.driverLink.validation.amountMismatch")); return false; }
    } else if (selectedDriverEarningIds.length > 0) { alert(t("expenses.driverLink.validation.required")); return false; }

    for (const item of expenseItems) {
      if (!item.expenseType) {
        alert(t("expenses.validation.typeRequired"));
        return false;
      }

      if (!EXPENSE_TYPES_BY_CLASS[item.expenseClass].includes(item.expenseType)) {
        alert(t("expenses.validation.typeClassMismatch"));
        return false;
      }

      if (toNumber(item.amount) <= 0) {
        alert(t("expenses.validation.amountPositive"));
        return false;
      }

      if (!item.paymentMethod) {
        alert(t("expenses.validation.paymentMethodRequired"));
        return false;
      }

      if (item.expenseType === "Fuel") {
        if (!fuelLoading) {
          alert(t("expenses.validation.fuelLoadingRequired"));
          return false;
        }

        if (!fuelLoading.vehicle_id) {
          alert(t("expenses.validation.fuelVehicleRequired"));
          return false;
        }

        if (!item.petrolPumpId) {
          alert(t("expenses.validation.petrolPumpRequired"));
          return false;
        }

        if (toNumber(item.liters) <= 0) {
          alert(t("expenses.validation.litresPositive"));
          return false;
        }

        if (toNumber(item.rate) <= 0) {
          alert(t("expenses.validation.ratePositive"));
          return false;
        }

        const totalAmount = toNumber(item.amount);
        const paid = toNumber(item.paidAmount);

        if (totalAmount <= 0) {
          alert(t("expenses.validation.totalPositive"));
          return false;
        }

        if (paid < 0) {
          alert(t("expenses.validation.paidNonNegative"));
          return false;
        }

        if (paid > totalAmount) {
          alert(t("expenses.validation.paidExceedsTotal"));
          return false;
        }
      }
    }

    return true;
  }

  async function uploadReceipt(
    expenseId: number,
    expenseItemId: number,
    item: ExpenseItemRow
  ) {
    if (!item.receiptFile) {
      return {
        receiptUrl: item.receiptUrl,
        receiptName: item.receiptName,
      };
    }

    const extension = item.receiptFile.name.split(".").pop() ?? "file";
    const filePath = `${expenseId}/${expenseItemId}-${Date.now()}.${extension}`;

    setExpenseItems((previous) =>
      previous.map((currentItem) =>
        currentItem.rowId === item.rowId
          ? {
              ...currentItem,
              receiptStatus: item.receiptUrl ? "replacing" : "uploading",
              receiptError: "",
            }
          : currentItem
      )
    );

    if (item.receiptUrl) {
      const oldPath = getReceiptPath(item.receiptUrl);

      if (oldPath) {
        await supabase.storage.from("expense-receipts").remove([oldPath]);
      }
    }

    const { error: uploadError } = await supabase.storage
      .from("expense-receipts")
      .upload(filePath, item.receiptFile, { upsert: true });

    if (uploadError) throw new Error(uploadError.message);

    const { data } = supabase.storage
      .from("expense-receipts")
      .getPublicUrl(filePath);

    return {
      receiptUrl: data.publicUrl,
      receiptName: item.receiptFile.name,
    };
  }

  async function createDieselEntries(
    expenseId: number,
    insertedItems: ExpenseItemRecord[],
    sourceItems: ExpenseItemRow[],
    fuelLoading: LoadingRecord | null
  ) {
    if (!fuelLoading) return;

    for (let index = 0; index < sourceItems.length; index += 1) {
      const sourceItem = sourceItems[index];
      const insertedItem = insertedItems[index];

      if (!insertedItem || sourceItem.expenseType !== "Fuel") continue;

      const totalAmount = toNumber(sourceItem.amount);
      const paid = toNumber(sourceItem.paidAmount);
      const remaining = Math.max(totalAmount - paid, 0);

      const { error } = await supabase
        .from("diesel_entries")
        .insert({
          expense_id: expenseId,
          expense_item_id: insertedItem.id,
          entry_date: expenseDate,
          petrol_pump_id: sourceItem.petrolPumpId,
          vehicle_id: fuelLoading.vehicle_id,
          driver_id: fuelLoading.driver_id || null,
          loading_id: fuelLoading.id,
          slip_no: sourceItem.slipNo.trim(),
          liters: toNumber(sourceItem.liters),
          rate: toNumber(sourceItem.rate),
          total_amount: totalAmount,
          paid_amount: paid,
          remaining_amount: remaining,
          payment_status: getDieselStatus(paid, totalAmount),
          remarks: sourceItem.remarks.trim(),
        });

      if (error) throw new Error(`Diesel entry failed: ${error.message}`);

    }
  }

  async function insertExpenseItemsWithReceipts(
    expenseId: number,
    fuelLoading: LoadingRecord | null
  ) {
    const sourceItems = expenseItems.filter((item) => {
      if (workshopMode === "create" && item.expenseType === "Workshop") {
        return false;
      }
      if (pendingOilCreatePayload && item.expenseType === "Oil / Lubricants") {
        return false;
      }
      if (pendingTyreCreatePayload && item.expenseType === "Tyre") {
        return false;
      }
      return true;
    });

    if (sourceItems.length === 0) return;

    const itemsPayload = sourceItems.map((item) => ({
      expense_id: expenseId,
      expense_class: item.expenseClass,
      expense_type: item.expenseType,
      amount: toNumber(item.amount),
      payment_method: item.paymentMethod,
      remarks: item.remarks.trim(),
      receipt_url: item.receiptUrl,
      receipt_name: item.receiptName,
    }));

    const { data, error } = await supabase
      .from("expense_items")
      .insert(itemsPayload)
      .select("*");

    if (error) throw new Error(error.message);

    const insertedItems = (data ?? []) as ExpenseItemRecord[];

    for (let index = 0; index < insertedItems.length; index += 1) {
      const insertedItem = insertedItems[index];
      const sourceItem = sourceItems[index];

      if (!sourceItem) continue;

      const receipt = await uploadReceipt(expenseId, insertedItem.id, sourceItem);

      if (receipt.receiptUrl || receipt.receiptName) {
        const { error: receiptError } = await supabase
          .from("expense_items")
          .update({
            receipt_url: receipt.receiptUrl,
            receipt_name: receipt.receiptName,
          })
          .eq("id", insertedItem.id);

        if (receiptError) throw new Error(receiptError.message);

        insertedItem.receipt_url = receipt.receiptUrl;
        insertedItem.receipt_name = receipt.receiptName;
      }
    }

    await createDieselEntries(expenseId, insertedItems, sourceItems, fuelLoading);
  }

  async function createWorkshopEntryFromVoucher(expenseId: number, manual = false) {
    if (workshopMode !== "create") return null;

    const { data, error } = await supabase.rpc(manual ? "create_manual_voucher_workshop_entry" : "create_voucher_workshop_entry", {
      p_voucher_id: expenseId,
      p_work_date: workshopCreateData.workDate,
      p_workshop_id: workshopCreateData.workshopId,
      p_mechanic_name: workshopCreateData.mechanicName.trim() || null,
      p_bill_no: workshopCreateData.billNo.trim() || null,
      p_paid_amount: toNumber(workshopCreateData.paidAmount),
      p_next_service_date: workshopCreateData.nextServiceDate || null,
      p_odometer: workshopCreateData.odometer
        ? Math.trunc(toNumber(workshopCreateData.odometer))
        : null,
      p_workshop_remarks: workshopCreateData.workshopRemarks.trim() || null,
      p_payment_method: workshopCreateData.paymentMethod,
      p_voucher_item_remarks: workshopCreateData.voucherItemRemarks.trim(),
      p_items: workshopCreateData.items.map((item) => ({
        work_type: item.workType.trim(),
        category: item.category.trim() || null,
        quantity: toNumber(item.quantity),
        rate: toNumber(item.rate),
        remarks: item.remarks.trim() || null,
      })),
    });

    if (error) {
      console.error("Voucher-created Workshop RPC failed:", {
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
        voucherId: expenseId,
      });
      throw new Error(error.message);
    }
    const entryId = Number((data as { workshop_entry_id?: number | string } | null)?.workshop_entry_id);
    if (!Number.isSafeInteger(entryId) || entryId <= 0) {
      throw new Error("Voucher-created Workshop RPC returned no Workshop Entry ID.");
    }
    return entryId;
  }

  async function createOilEntryFromVoucher(expenseId: number, manual = false) {
    if (!pendingOilCreatePayload) return null;

    const sourceItem = expenseItems.find(
      (item) => item.expenseType === "Oil / Lubricants"
    );

    const { data: createdOilEntryId, error } = await supabase.rpc(
      manual ? "create_manual_voucher_oil_entry" : "create_voucher_oil_entry",
      {
        p_voucher_id: expenseId,
        p_entry_date: pendingOilCreatePayload.entryDate,
        p_source_type: pendingOilCreatePayload.sourceType,
        p_oil_shop_id:
          pendingOilCreatePayload.sourceType === "external_shop"
            ? pendingOilCreatePayload.oilShopId || null
            : null,
        p_oil_product_id: pendingOilCreatePayload.oilProductId,
        p_liters: pendingOilCreatePayload.liters,
        p_rate_per_liter: pendingOilCreatePayload.ratePerLiter,
        p_bill_no: pendingOilCreatePayload.billNo.trim() || null,
        p_odometer: pendingOilCreatePayload.odometer,
        p_next_oil_change_date:
          pendingOilCreatePayload.nextOilChangeDate || null,
        p_oil_remarks: pendingOilCreatePayload.oilRemarks.trim() || null,
        p_payment_method: pendingOilCreatePayload.paymentMethod || "Cash",
        p_voucher_item_remarks:
          pendingOilCreatePayload.voucherItemRemarks.trim() || null,
      }
    );

    if (error) {
      console.error("Voucher-created Oil RPC failed:", {
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
        voucherId: expenseId,
      });
      throw new Error(error.message);
    }

    if (!createdOilEntryId) {
      throw new Error("Voucher-created Oil RPC returned no Oil Entry ID.");
    }

    if (sourceItem && (sourceItem.receiptFile || sourceItem.receiptUrl)) {
      const { data: oilItem, error: oilItemError } = await supabase
        .from("expense_items")
        .select("*")
        .eq("expense_id", expenseId)
        .eq("expense_type", "Oil / Lubricants")
        .eq("expense_class", "vehicle_periodic")
        .single();

      if (oilItemError) {
        throw new Error(oilItemError.message);
      }

      const insertedItem = oilItem as ExpenseItemRecord;
      const receipt = await uploadReceipt(expenseId, insertedItem.id, sourceItem);

      if (receipt.receiptUrl || receipt.receiptName) {
        const { error: receiptError } = await supabase
          .from("expense_items")
          .update({
            receipt_url: receipt.receiptUrl,
            receipt_name: receipt.receiptName,
          })
          .eq("id", insertedItem.id);

        if (receiptError) {
          throw new Error(receiptError.message);
        }
      }
    }
    return String(createdOilEntryId);
  }

  async function createTyreEntryFromVoucher(expenseId: number, manual = false) {
    if (!pendingTyreCreatePayload) return null;

    const sourceItem = expenseItems.find(
      (item) => item.expenseType === "Tyre"
    );

    const { data: createdTyreEntryId, error } = await supabase.rpc(
      manual ? "create_manual_voucher_tyre_entry" : "create_voucher_tyre_entry",
      {
        p_voucher_id: expenseId,
        p_entry_date: pendingTyreCreatePayload.entryDate,
        p_source_type: pendingTyreCreatePayload.sourceType,
        p_tyre_shop_id:
          pendingTyreCreatePayload.sourceType === "external_shop"
            ? pendingTyreCreatePayload.tyreShopId || null
            : null,
        p_work_type: pendingTyreCreatePayload.workType,
        p_bill_no: pendingTyreCreatePayload.billNo.trim() || null,
        p_odometer: pendingTyreCreatePayload.odometer,
        p_tyre_remarks:
          pendingTyreCreatePayload.tyreRemarks.trim() || null,
        p_payment_method:
          pendingTyreCreatePayload.paymentMethod || "Cash",
        p_voucher_item_remarks:
          pendingTyreCreatePayload.voucherItemRemarks.trim() || null,
        p_items: pendingTyreCreatePayload.items.map((item) => ({
          work_type: item.workType,
          tyre_asset_id: item.tyreAssetId || null,
          position_id: item.positionId || null,
          quantity: item.quantity,
          rate: item.rate,
          remarks: item.remarks.trim() || null,
          removal_reason: item.removalReason.trim() || null,
        })),
      }
    );

    if (error) {
      console.error("Voucher-created Tyre RPC failed:", {
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
        voucherId: expenseId,
      });
      throw new Error(error.message);
    }

    if (!createdTyreEntryId) {
      throw new Error("Voucher-created Tyre RPC returned no Tyre Entry ID.");
    }

    if (sourceItem && (sourceItem.receiptFile || sourceItem.receiptUrl)) {
      const { data: tyreItem, error: tyreItemError } = await supabase
        .from("expense_items")
        .select("*")
        .eq("expense_id", expenseId)
        .eq("expense_type", "Tyre")
        .eq("expense_class", "vehicle_periodic")
        .single();

      if (tyreItemError) {
        throw new Error(tyreItemError.message);
      }

      const insertedItem = tyreItem as ExpenseItemRecord;
      const receipt = await uploadReceipt(
        expenseId,
        insertedItem.id,
        sourceItem
      );

      if (receipt.receiptUrl || receipt.receiptName) {
        const { error: receiptError } = await supabase
          .from("expense_items")
          .update({
            receipt_url: receipt.receiptUrl,
            receipt_name: receipt.receiptName,
          })
          .eq("id", insertedItem.id);

        if (receiptError) {
          throw new Error(receiptError.message);
        }
      }
    }
    return String(createdTyreEntryId);
  }

  async function finalizeSavedVoucher(movementGroupId: string | null, voucherId: number) {
    if (!movementGroupId) return null;

    setFinalizingVoucherId(voucherId);
    try {
      const { data: settlementId, error: finalizationError } = await supabase.rpc(
        "finalize_vehicle_chakkar_voucher",
        {
          p_movement_group_id: movementGroupId,
          p_voucher_id: voucherId,
        }
      );

      if (finalizationError) {
        console.error("Voucher Chakkar finalization RPC failed", {
          code: finalizationError.code,
          message: finalizationError.message,
          details: finalizationError.details,
          hint: finalizationError.hint,
          movementGroupId,
          voucherId,
        });
        throw new VoucherFinalizationError(finalizationError.message);
      }

      return settlementId;
    } finally {
      setFinalizingVoucherId(null);
    }
  }

  async function handleSaveExpenseVoucher() {
    setIsSaving(true);
    let workshopLinkSyncFailed = false;
    let oilLinkSyncFailed = false;
    let tyreLinkSyncFailed = false;
    let driverLinkSyncFailed = false;

    try {
      if (voucherMode === "manual") {
        const dateState = getManualVoucherDateState(manualDepartureDate, manualArrivalDate);
        const datedDays = getInclusiveManualChakkarDays(manualDepartureDate, manualArrivalDate);
        const datesRequired = editingId === null || hasPersistedManualDates;
        if (dateState === "incomplete") {
          alert(t("expenses.manual.validation.datePairRequired"));
          return;
        }
        if (dateState === "invalid") {
          alert(t("expenses.manual.validation.datesInvalid"));
          return;
        }
        if (dateState === "reversed") {
          alert(t("expenses.manual.validation.arrivalBeforeDeparture"));
          return;
        }
        if (datesRequired && dateState !== "valid") {
          alert(t("expenses.manual.validation.tripDatesRequired"));
          return;
        }
        const days = dateState === "valid" ? datedDays : Number(manualChakkarDays);
        if (days === null) {
          alert(t("expenses.manual.validation.datesInvalid"));
          return;
        }
        const freightRows = manualFreightRows
          .map((row, index) => ({ row, sequenceNo: index + 1, amount: Number(row.amount) }))
          .filter(({ amount }) => Number.isFinite(amount) && amount > 0);

        if (!expenseNo.trim()) {
          alert(t("expenses.validation.voucherNoRequired"));
          return;
        }
        if (!expenseDate) {
          alert(t("expenses.validation.dateRequired"));
          return;
        }
        if (!manualVehicleId) {
          alert(t("expenses.manual.validation.vehicleRequired"));
          return;
        }
        if (!Number.isSafeInteger(days) || days <= 0) {
          alert(t("expenses.manual.validation.daysPositiveWhole"));
          return;
        }
        const invalidFreightInput = manualFreightRows.some((row) => {
          if (!row.amount.trim()) return false;
          const amount = Number(row.amount);
          return !Number.isFinite(amount) || amount < 0;
        });
        if (invalidFreightInput) {
          alert(t("expenses.manual.validation.freightAmountInvalid"));
          return;
        }
        const hasSubcentFreight = manualFreightRows.some((row) => {
          const amount = Number(row.amount);
          return Number.isFinite(amount) && amount > 0 && Math.abs(amount * 100 - Math.round(amount * 100)) > 0.000001;
        });
        if (hasSubcentFreight) {
          alert(t("expenses.manual.validation.amountPrecision"));
          return;
        }
        if (freightRows.length === 0) {
          alert(t("expenses.manual.validation.freightRequired"));
          return;
        }

      const dieselRows = manualDieselRows.filter((row) =>
          row.dieselEntryId !== null || row.petrolPumpId || row.liters.trim() ||
          row.rate.trim() || row.paidAmount.trim() && Number(row.paidAmount) !== 0 ||
          row.paymentReference.trim() || row.paymentRemarks.trim() ||
          row.slipNo.trim() || row.remarks.trim()
        );
        const dieselPayload = dieselRows.map((row) => {
          const liters = Number(row.liters);
          const rate = Number(row.rate);
          const totalAmount = Math.round(liters * rate * 100) / 100;
          const paidAmount = row.paidAmount.trim() ? Number(row.paidAmount) : 0;
          return { row, entryDate: row.entryDate || expenseDate, liters, rate, totalAmount, paidAmount };
        });
        if (dieselPayload.some(({ row, entryDate, liters, rate, totalAmount, paidAmount }) =>
          !entryDate || !row.petrolPumpId || !Number.isFinite(liters) || liters <= 0 ||
          !Number.isFinite(rate) || rate <= 0 || !Number.isFinite(totalAmount) || totalAmount <= 0 ||
          !Number.isFinite(paidAmount) || paidAmount < 0 || paidAmount > totalAmount ||
          Math.abs(paidAmount * 100 - Math.round(paidAmount * 100)) > 0.000001 ||
          (paidAmount > 0 && (!row.paymentDate || !row.paymentMethod))
        )) {
          alert(t("expenses.manual.validation.dieselFieldsInvalid"));
          return;
        }

        const manualExpenseRows = expenseItems.filter((item) =>
          item.expenseType.trim() || item.amount.trim() || item.remarks.trim()
        );
        const manualExpensePayload: Array<{ expense_class: string; expense_type: string; amount: number; remarks: string | null }> = [];
        for (const item of manualExpenseRows) {
          const amount = Number(item.amount);
          if (!MANUAL_EXPENSE_TYPES.includes(item.expenseType as (typeof MANUAL_EXPENSE_TYPES)[number])) {
            alert(t("expenses.manual.validation.expenseTypeUnsupported"));
            return;
          }
          if (!Number.isFinite(amount) || amount <= 0 || Math.abs(amount * 100 - Math.round(amount * 100)) > 0.000001) {
            alert(t("expenses.manual.validation.expenseAmountInvalid"));
            return;
          }
          manualExpensePayload.push({
            expense_class: "regular_trip",
            expense_type: item.expenseType,
            amount,
            remarks: item.remarks.trim() || null,
          });
        }

        const { data: savedManualVoucherId, error: manualSaveError } = await supabase.rpc(
          "save_manual_voucher_phase2_with_dates",
          {
            p_voucher_id: editingId,
            p_expense_no: expenseNo.trim(),
            p_voucher_date: expenseDate,
            p_vehicle_id: manualVehicleId,
            p_driver_id: manualDriverId || null,
            p_chakkar_days: days,
            p_departure_date: dateState === "valid" ? manualDepartureDate : null,
            p_arrival_date: dateState === "valid" ? manualArrivalDate : null,
            p_remarks: description.trim() || null,
            p_freight_items: freightRows.map(({ row, sequenceNo, amount }) => ({
              freight_type: row.freightType,
              amount,
              description: row.description.trim() || null,
              sequence_no: sequenceNo,
            })),
            p_expense_items: manualExpensePayload,
          }
        );
        if (manualSaveError) throw new Error(manualSaveError.message);
        const savedId = Number(savedManualVoucherId);
        if (!Number.isSafeInteger(savedId) || savedId <= 0) {
          throw new Error("Manual Voucher save returned an invalid identifier.");
        }
        setEditingId(savedId);
        if (dateState === "valid") setHasPersistedManualDates(true);

        for (const diesel of dieselPayload) {
          const { data: savedDieselId, error: dieselSaveError } = await supabase.rpc(
            "save_manual_voucher_diesel_with_payment",
            {
              p_voucher_id: savedId,
              p_diesel_entry_id: diesel.row.dieselEntryId,
              p_request_id: diesel.row.requestId,
              p_entry_date: diesel.entryDate,
              p_petrol_pump_id: diesel.row.petrolPumpId,
              p_liters: diesel.liters,
              p_rate: diesel.rate,
              p_slip_no: diesel.row.slipNo.trim() || null,
              p_remarks: diesel.row.remarks.trim() || null,
              p_payment_date: diesel.paidAmount > 0 ? diesel.row.paymentDate : null,
              p_paid_amount: diesel.paidAmount,
              p_payment_method: diesel.paidAmount > 0 ? diesel.row.paymentMethod : null,
              p_payment_reference: diesel.row.paymentReference.trim() || null,
              p_payment_remarks: diesel.row.paymentRemarks.trim() || null,
            }
          );
          if (dieselSaveError) throw new Error(dieselSaveError.message);
          const dieselEntryId = Number(savedDieselId);
          if (!Number.isSafeInteger(dieselEntryId) || dieselEntryId <= 0) {
            throw new Error("Manual Diesel save returned an invalid identifier.");
          }
          setManualDieselRows((rows) => rows.map((row) => row.clientId === diesel.row.clientId
            ? { ...row, dieselEntryId }
            : row
          ));
        }

        let manualWorkshopIds = selectedWorkshopEntryIds;
        let manualOilIds = selectedOilEntryIds;
        let manualTyreIds = selectedTyreEntryIds;

        if (workshopMode === "create") {
          const createdId = await createWorkshopEntryFromVoucher(savedId, true);
          if (!createdId) throw new Error("Manual Workshop creation returned no source ID.");
          manualWorkshopIds = [createdId];
          setSelectedWorkshopEntryIds(manualWorkshopIds);
          setWorkshopMode("existing");
          setManualSourceCreatedTotals((current) => ({
            ...current,
            workshop: { id: String(createdId), amount: workshopCreateTotal(workshopCreateData) },
          }));
        }

        if (pendingOilCreatePayload) {
          const createdId = await createOilEntryFromVoucher(savedId, true);
          if (!createdId) throw new Error("Manual Oil creation returned no source ID.");
          manualOilIds = [createdId];
          setSelectedOilEntryIds(manualOilIds);
          setPendingOilCreatePayload(null);
          setOilMode("existing");
          setManualSourceCreatedTotals((current) => ({
            ...current,
            oil: { id: createdId, amount: pendingOilCreatePayload.liters * pendingOilCreatePayload.ratePerLiter },
          }));
        }

        if (pendingTyreCreatePayload) {
          const createdId = await createTyreEntryFromVoucher(savedId, true);
          if (!createdId) throw new Error("Manual Tyre creation returned no source ID.");
          manualTyreIds = [createdId];
          setSelectedTyreEntryIds(manualTyreIds);
          setPendingTyreCreatePayload(null);
          setTyreMode("existing");
          setManualSourceCreatedTotals((current) => ({
            ...current,
            tyre: { id: createdId, amount: pendingTyreCreatePayload.items.reduce((sum, line) => sum + line.quantity * line.rate, 0) },
          }));
        }

        const { error: manualSourceSyncError } = await supabase.rpc(
          "sync_manual_voucher_source_entries",
          {
            p_voucher_id: savedId,
            p_workshop_entry_ids: manualWorkshopIds,
            p_oil_vehicle_entry_ids: manualOilIds,
            p_tyre_vehicle_entry_ids: manualTyreIds,
          }
        );
        if (manualSourceSyncError) {
          console.error("Manual Voucher source synchronization failed:", {
            code: manualSourceSyncError.code,
            message: manualSourceSyncError.message,
            details: manualSourceSyncError.details,
            hint: manualSourceSyncError.hint,
            voucherId: savedId,
          });
          throw new Error(manualSourceSyncError.message);
        }

        alert(t(editingId ? "expenses.messages.manualUpdated" : "expenses.messages.manualSaved"));
        resetForm();
        await Promise.all([loadExpenseVouchers(), loadWorkshopEntries(), loadOilEntries(), loadTyreEntries()]);
        return;
      }

      let effectiveLoadings = selectedLoadings;
      if (selectedMovementGroupId && effectiveLoadings.length === 0) {
        effectiveLoadings = await prepareMovementGroupLoadings(selectedMovementGroupId);
        setSelectedLoadingIds(effectiveLoadings.map((loading) => String(loading.id)));
      }

      const effectiveLoading = effectiveLoadings[0] ?? null;
      if (!validateExpenseVoucher(effectiveLoading)) return;

      const { data: savedVoucherId, error: saveVoucherError } =
        await supabase.rpc("save_voucher_with_movement_group", {
          p_voucher_id: editingId ? String(editingId) : null,
          p_expense_no: expenseNo.trim(),
          p_start_date: expenseDate,
          p_end_date: endDate,
          p_description: description.trim(),
          p_movement_group_id: selectedMovementGroupId,
          p_loading_ids: effectiveLoadings.map((loading) => String(loading.id)),
        });

      if (saveVoucherError) throw new Error(saveVoucherError.message);

      const expenseId = Number(savedVoucherId);
      if (!Number.isSafeInteger(expenseId) || expenseId <= 0) {
        throw new Error("Voucher save returned an invalid identifier.");
      }

      if (editingId) {
        const { error: deleteItemsError } = await supabase
          .from("expense_items")
          .delete()
          .eq("expense_id", editingId);

        if (deleteItemsError) throw new Error(deleteItemsError.message);

        await insertExpenseItemsWithReceipts(editingId, effectiveLoading);

        if (workshopMode === "create") {
          await createWorkshopEntryFromVoucher(editingId);
        } else {
          const { error: workshopLinkError } = await supabase.rpc("sync_voucher_workshop_entries", {
            p_voucher_id: editingId,
            p_workshop_entry_ids: selectedWorkshopEntryIds,
          });

          if (workshopLinkError) {
            console.error("Workshop attachment RPC failed", {
              code: workshopLinkError.code,
              message: workshopLinkError.message,
              details: workshopLinkError.details,
              hint: workshopLinkError.hint,
              voucherId: editingId,
              workshopEntryIds: selectedWorkshopEntryIds,
              primaryLoadingId: selectedLoading?.id ?? null,
              voucherVehicleId: selectedLoading?.vehicle_id ?? null,
              voucherAddaId: loadingBooking(selectedLoading)?.adda_id ?? null,
              selectedWorkshopEntries: workshopEntries
                .filter((entry) => selectedWorkshopEntryIds.includes(entry.id))
                .map((entry) => ({
                  id: entry.id,
                  vehicleId: entry.vehicleId,
                  totalCost: entry.totalCost,
                  attachedVoucherId: entry.attachedVoucherId,
                })),
            });
            workshopLinkSyncFailed = true;
            throw new Error(workshopLinkError.message);
          }
        }
        if (pendingOilCreatePayload) {
          const { error: detachOilError } = await supabase.rpc("sync_voucher_oil_entries", {
            p_voucher_id: editingId,
            p_oil_vehicle_entry_ids: [],
          });
          if (detachOilError) {
            console.error("Unable to prepare existing Oil links for Voucher-created Oil:", detachOilError);
            oilLinkSyncFailed = true;
            throw new Error(detachOilError.message);
          }
          await createOilEntryFromVoucher(editingId);
        } else {
          const { error: oilLinkError } = await supabase.rpc("sync_voucher_oil_entries", {
            p_voucher_id: editingId,
            p_oil_vehicle_entry_ids: selectedOilEntryIds,
          });
          if (oilLinkError) {
            console.error("Oil attachment RPC failed", {
              code: oilLinkError.code,
              message: oilLinkError.message,
              details: oilLinkError.details,
              hint: oilLinkError.hint,
              voucherId: editingId,
              oilVehicleEntryIds: selectedOilEntryIds,
            });
            oilLinkSyncFailed = true;
            throw new Error(oilLinkError.message);
          }
        }
        if (pendingTyreCreatePayload) {
          const { error: detachTyreError } = await supabase.rpc(
            "sync_voucher_tyre_entries",
            {
              p_voucher_id: editingId,
              p_tyre_vehicle_entry_ids: [],
            }
          );
          if (detachTyreError) {
            console.error(
              "Unable to prepare existing Tyre links for Voucher-created Tyre:",
              detachTyreError
            );
            tyreLinkSyncFailed = true;
            throw new Error(detachTyreError.message);
          }
          await createTyreEntryFromVoucher(editingId);
        } else {
          const { error: tyreLinkError } = await supabase.rpc(
            "sync_voucher_tyre_entries",
            {
              p_voucher_id: editingId,
              p_tyre_vehicle_entry_ids: selectedTyreEntryIds,
            }
          );
          if (tyreLinkError) {
            console.error("Tyre attachment RPC failed", {
              code: tyreLinkError.code,
              message: tyreLinkError.message,
              details: tyreLinkError.details,
              hint: tyreLinkError.hint,
              voucherId: editingId,
              tyreVehicleEntryIds: selectedTyreEntryIds,
            });
            tyreLinkSyncFailed = true;
            throw new Error(tyreLinkError.message);
          }
        }
        const { error: driverLinkError } = await supabase.rpc("sync_voucher_driver_earnings", {
          p_voucher_id: editingId, p_driver_earning_ids: selectedDriverEarningIds,
        });
        if (driverLinkError) {
          console.error("Driver earning attachment RPC failed", { code: driverLinkError.code, message: driverLinkError.message, details: driverLinkError.details, hint: driverLinkError.hint, voucherId: editingId, driverEarningIds: selectedDriverEarningIds });
          driverLinkSyncFailed = true;
          throw new Error(driverLinkError.message);
        }

        await finalizeSavedVoucher(selectedMovementGroupId, expenseId);

        alert(t("expenses.messages.updatedSuccessfully"));
        resetForm();
        await Promise.all([loadExpenseVouchers(), loadWorkshopEntries(), loadOilEntries(), loadTyreEntries(), loadDriverEarnings()]);
        return;
      }

      await insertExpenseItemsWithReceipts(expenseId, effectiveLoading);

      if (workshopMode === "create") {
        await createWorkshopEntryFromVoucher(expenseId);
      } else {
        const { error: workshopLinkError } = await supabase.rpc("sync_voucher_workshop_entries", {
          p_voucher_id: expenseId,
          p_workshop_entry_ids: selectedWorkshopEntryIds,
        });

        if (workshopLinkError) {
          console.error("Workshop attachment RPC failed", {
            code: workshopLinkError.code,
            message: workshopLinkError.message,
            details: workshopLinkError.details,
            hint: workshopLinkError.hint,
            voucherId: expenseId,
            workshopEntryIds: selectedWorkshopEntryIds,
            primaryLoadingId: selectedLoading?.id ?? null,
            voucherVehicleId: selectedLoading?.vehicle_id ?? null,
            voucherAddaId: loadingBooking(selectedLoading)?.adda_id ?? null,
            selectedWorkshopEntries: workshopEntries
              .filter((entry) => selectedWorkshopEntryIds.includes(entry.id))
              .map((entry) => ({
                id: entry.id,
                vehicleId: entry.vehicleId,
                totalCost: entry.totalCost,
                attachedVoucherId: entry.attachedVoucherId,
              })),
          });
          workshopLinkSyncFailed = true;
          throw new Error(workshopLinkError.message);
        }
      }
      if (pendingOilCreatePayload) {
        await createOilEntryFromVoucher(expenseId);
      } else {
        const { error: oilLinkError } = await supabase.rpc("sync_voucher_oil_entries", {
          p_voucher_id: expenseId,
          p_oil_vehicle_entry_ids: selectedOilEntryIds,
        });
        if (oilLinkError) {
          console.error("Oil attachment RPC failed", {
            code: oilLinkError.code,
            message: oilLinkError.message,
            details: oilLinkError.details,
            hint: oilLinkError.hint,
            voucherId: expenseId,
            oilVehicleEntryIds: selectedOilEntryIds,
          });
          oilLinkSyncFailed = true;
          throw new Error(oilLinkError.message);
        }
      }
      if (pendingTyreCreatePayload) {
        await createTyreEntryFromVoucher(expenseId);
      } else {
        const { error: tyreLinkError } = await supabase.rpc(
          "sync_voucher_tyre_entries",
          {
            p_voucher_id: expenseId,
            p_tyre_vehicle_entry_ids: selectedTyreEntryIds,
          }
        );
        if (tyreLinkError) {
          console.error("Tyre attachment RPC failed", {
            code: tyreLinkError.code,
            message: tyreLinkError.message,
            details: tyreLinkError.details,
            hint: tyreLinkError.hint,
            voucherId: expenseId,
            tyreVehicleEntryIds: selectedTyreEntryIds,
          });
          tyreLinkSyncFailed = true;
          throw new Error(tyreLinkError.message);
        }
      }
      const { error: driverLinkError } = await supabase.rpc("sync_voucher_driver_earnings", {
        p_voucher_id: expenseId, p_driver_earning_ids: selectedDriverEarningIds,
      });
      if (driverLinkError) {
        console.error("Driver earning attachment RPC failed", { code: driverLinkError.code, message: driverLinkError.message, details: driverLinkError.details, hint: driverLinkError.hint, voucherId: expenseId, driverEarningIds: selectedDriverEarningIds });
        driverLinkSyncFailed = true;
        throw new Error(driverLinkError.message);
      }

      await finalizeSavedVoucher(selectedMovementGroupId, expenseId);

      alert(t("expenses.messages.savedSuccessfully"));
      resetForm();
      await Promise.all([loadExpenseVouchers(), loadWorkshopEntries(), loadOilEntries(), loadTyreEntries(), loadDriverEarnings()]);
    } catch (error) {
      console.error("Unable to save expense voucher:", error);
      if (voucherMode === "manual" && error instanceof Error) {
        alert(`${t("common.messages.saveFailed")}\n${error.message}`);
      } else if (error instanceof VoucherFinalizationError) {
        alert(`${t("expenses.messages.finalizationFailed")}\n${error.message}`);
      } else {
        alert(t(workshopLinkSyncFailed ? "expenses.workshopLink.validation.syncFailed" : oilLinkSyncFailed ? "expenses.oilLink.validation.syncFailed" : tyreLinkSyncFailed ? "expenses.tyreLink.validation.syncFailed" : driverLinkSyncFailed ? "expenses.driverLink.validation.syncFailed" : "common.messages.saveFailed"));
      }
    } finally {
      setIsSaving(false);

      setExpenseItems((previous) =>
        previous.map((item) => ({
          ...item,
          receiptStatus: "idle",
        }))
      );
    }
  }

  function handleEditExpenseVoucher(voucher: ExpenseVoucher) {
    setManualSourceEditTarget(null);
    if (voucher.voucher_source === "manual") {
      const detail = voucher.manual_voucher_details;
      if (!detail || detail.status !== "draft") {
        alert(t("expenses.manual.detailsUnavailable"));
        return;
      }
      setVoucherMode("manual");
      setEditingId(voucher.id);
      setExpenseNo(voucher.expense_no ?? "");
      setExpenseDate(detail.voucher_date ?? voucher.expense_date ?? "");
      setEndDate("");
      setDescription(detail.remarks ?? voucher.description ?? "");
      setSelectedLoadingIds([]);
      setSelectedMovementGroupId(null);
      setSelectedWorkshopEntryIds((voucher.voucher_workshop_entries ?? []).map((link) => link.workshop_entry_id));
      setWorkshopMode("existing");
      setSelectedOilEntryIds((voucher.voucher_oil_entries ?? []).map((link) => link.oil_vehicle_entry_id));
      setOilMode("existing");
      setPendingOilCreatePayload(null);
      setSelectedTyreEntryIds((voucher.voucher_tyre_entries ?? []).map((link) => link.tyre_vehicle_entry_id));
      setTyreMode("existing");
      setPendingTyreCreatePayload(null);
      setManualSourceCreatedTotals({});
      setSelectedDriverEarningIds([]);
      setManualVehicleId(detail.vehicle_id);
      setManualDriverId(detail.driver_id ?? "");
      setManualChakkarDays(String(detail.chakkar_days));
      setManualDepartureDate(detail.departure_date ?? "");
      setManualArrivalDate(detail.arrival_date ?? "");
      setHasPersistedManualDates(Boolean(detail.departure_date && detail.arrival_date));

      const savedRows = [...(detail.manual_voucher_freight_items ?? [])]
        .sort((left, right) => left.sequence_no - right.sequence_no)
        .map((row) => ({
          clientId: `saved-${row.id}`,
          freightType: row.freight_type,
          amount: String(row.amount ?? ""),
          description: row.description ?? "",
        }));
      const outbound = savedRows.find((row) => row.freightType === "outbound") ?? createManualFreightInput("outbound");
      const returnRow = savedRows.find((row) => row.freightType === "return") ?? createManualFreightInput("return");
      const locals = savedRows.filter((row) => row.freightType === "local");
      setManualFreightRows([outbound, ...locals, returnRow]);
      const manualItems = (voucher.expense_items ?? [])
        .filter((item) => item.expense_class === "regular_trip" && MANUAL_EXPENSE_TYPES.includes(item.expense_type as (typeof MANUAL_EXPENSE_TYPES)[number]))
        .map((item) => {
        const row = createEmptyExpenseItem("regular_trip");
        return {
          ...row,
          dbId: item.id,
          expenseType: item.expense_type ?? "",
          amount: String(item.amount ?? ""),
          paymentMethod: "Not Paid",
          remarks: item.remarks ?? "",
        };
      });
      setExpenseItems(manualItems.length > 0 ? manualItems : [createEmptyExpenseItem("regular_trip")]);
      const manualDiesel = (voucher.diesel_entries ?? [])
        .filter((diesel) => diesel.manual_voucher_id === detail.id)
        .sort((left, right) => left.id - right.id)
        .map((diesel) => ({
          clientId: `diesel-${diesel.id}`,
          dieselEntryId: diesel.id,
          requestId: diesel.manual_request_id ?? crypto.randomUUID(),
          entryDate: diesel.entry_date,
          petrolPumpId: diesel.petrol_pump_id,
          liters: String(diesel.liters ?? ""),
          rate: String(diesel.rate ?? ""),
          paidAmount: String(diesel.paid_amount ?? "0"),
          paymentDate: diesel.initial_payment_date ?? diesel.entry_date,
          paymentMethod: diesel.initial_payment_method ?? "Cash",
          paymentReference: diesel.initial_payment_reference ?? "",
          paymentRemarks: diesel.initial_payment_remarks ?? "",
          paymentRecorded: diesel.initial_payment_date !== null && diesel.initial_payment_date !== undefined,
          slipNo: diesel.slip_no ?? "",
          remarks: diesel.remarks ?? "",
        }));
      setManualDieselRows(manualDiesel);
      return;
    }

    setVoucherMode("bilty");
    setEditingId(voucher.id);
    setExpenseNo(voucher.expense_no ?? "");
    const storedStartDate = voucher.start_date ?? voucher.expense_date ?? "";
    const storedEndDate = voucher.end_date ?? voucher.start_date ?? voucher.expense_date ?? "";
    const relatedLoadingIds = (voucher.voucher_loadings ?? []).map(
      (relation) => String(relation.loading_id)
    );
    const editLoadingIds =
      relatedLoadingIds.length > 0
        ? relatedLoadingIds
        : voucher.loading_id
          ? [String(voucher.loading_id)]
          : [];
    setSelectedLoadingIds(editLoadingIds);
    const editGroupIds = Array.from(new Set(editLoadingIds.flatMap((id) => {
      const matchedLoading = loadings.find((loading) => String(loading.id) === id);
      const groupId = matchedLoading ? loadingBooking(matchedLoading)?.bilty_group_id : null;
      return groupId ? [groupId] : [];
    })));
    setSelectedMovementGroupId(voucher.movement_group_id ?? (editGroupIds.length === 1 ? editGroupIds[0] : null));
    const derivedDates = editGroupIds.length === 1 ? datesForMovementGroup(editGroupIds[0]) : { startDate: "", endDate: "" };
    setExpenseDate(storedStartDate || derivedDates.startDate);
    setEndDate(storedEndDate || derivedDates.endDate);
    setDescription(voucher.description ?? "");
    setSelectedWorkshopEntryIds((voucher.voucher_workshop_entries ?? []).map((relation) => relation.workshop_entry_id));
    setWorkshopMode("existing");
    setWorkshopCreateData(createEmptyVoucherWorkshopData());
    setSelectedOilEntryIds((voucher.voucher_oil_entries ?? []).map((relation) => relation.oil_vehicle_entry_id));
    setPendingOilCreatePayload(null);
    setSelectedTyreEntryIds(
      (voucher.voucher_tyre_entries ?? []).map(
        (relation) => relation.tyre_vehicle_entry_id
      )
    );
    setPendingTyreCreatePayload(null);
    setSelectedDriverEarningIds((voucher.voucher_driver_earnings ?? []).map((relation) => relation.driver_earning_id));

    const dieselByItemId = new Map<number, DieselEntryRecord>();
    (voucher.diesel_entries ?? []).forEach((diesel) => {
      dieselByItemId.set(diesel.expense_item_id, diesel);
    });

    const mappedItems =
      voucher.expense_items?.map((item) => {
        const diesel = dieselByItemId.get(item.id);

        const row: ExpenseItemRow = {
          rowId: nextExpenseItemRowId,
          dbId: item.id,
          expenseClass: normalizeExpenseClass(item.expense_class, item.expense_type),
          expenseType: item.expense_type ?? "",
          amount: String(item.amount ?? ""),
          paymentMethod: item.payment_method ?? "Cash",
          remarks: item.remarks ?? "",
          receiptUrl: item.receipt_url,
          receiptName: item.receipt_name,
          receiptFile: null,
          receiptStatus: "idle",
          receiptError: "",
          petrolPumpId: diesel?.petrol_pump_id ?? "",
          liters: diesel ? String(diesel.liters ?? "") : "",
          rate: diesel ? String(diesel.rate ?? "") : "",
          paidAmount: diesel ? String(diesel.paid_amount ?? "") : "",
          slipNo: diesel?.slip_no ?? "",
        };

        nextExpenseItemRowId += 1;
        return row;
      }) ?? [];

    setExpenseItems(mappedItems.length > 0 ? mappedItems : [createEmptyExpenseItem()]);
  }

  const resumeManualVoucherAfterSourceEdit = useEffectEvent(() => {
    if (isLoading || resumeManualVoucherHandledRef.current || typeof window === "undefined") return;
    const params = new URLSearchParams(window.location.search);
    const resumeId = Number(params.get("resumeManualVoucherId"));
    if (!Number.isSafeInteger(resumeId) || resumeId <= 0) return;

    const voucher = expenseVouchers.find((candidate) => candidate.id === resumeId);
    if (!voucher) return;

    resumeManualVoucherHandledRef.current = true;
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${window.location.hash}`);
    window.setTimeout(() => handleEditExpenseVoucher(voucher), 0);
  });

  useEffect(() => {
    resumeManualVoucherAfterSourceEdit();
  }, [expenseVouchers, isLoading]);

  useEffect(() => {
    if (isLoading || typeof window === "undefined") return;
    const params = new URLSearchParams(window.location.search);
    const rawVoucherId = params.get("voucherId");
    if (!rawVoucherId || voucherViewHandledIdRef.current === rawVoucherId) return;
    const voucherId = Number(rawVoucherId);
    if (!Number.isSafeInteger(voucherId) || voucherId <= 0) return;
    const voucher = expenseVouchers.find((candidate) => candidate.id === voucherId);
    if (!voucher) return;
    voucherViewHandledIdRef.current = rawVoucherId;
    window.setTimeout(() => setViewingExpense(voucher), 0);
  }, [expenseVouchers, isLoading]);

  async function handleFinalizeExpenseVoucher(voucher: ExpenseVoucher) {
    if (voucher.voucher_source === "manual") {
      if (voucher.archived_at || voucher.manual_voucher_details?.status !== "draft") {
        alert(t("expenses.messages.finalizationUnavailable"));
        return;
      }
      setFinalizingVoucherId(voucher.id);
      try {
        const { error } = await supabase.rpc("finalize_manual_voucher", {
          p_voucher_id: voucher.id,
        });
        if (error) throw new Error(error.message);
        alert(t("expenses.manual.finalizedSuccessfully"));
        await loadExpenseVouchers();
      } catch (error) {
        console.error("Unable to finalize Manual Voucher:", error);
        const message = error instanceof Error ? error.message : String(error);
        alert(`${t("expenses.messages.finalizationFailed")}\n${message}`);
      } finally {
        setFinalizingVoucherId(null);
      }
      return;
    }
    const movementGroupId = getVoucherMovementGroupId(voucher);
    if (!movementGroupId || voucher.archived_at) {
      alert(t("expenses.messages.finalizationUnavailable"));
      return;
    }

    try {
      await finalizeSavedVoucher(movementGroupId, voucher.id);
      alert(t("expenses.messages.finalizedSuccessfully"));
      await loadExpenseVouchers();
    } catch (error) {
      console.error("Unable to finalize expense voucher:", error);
      const message = error instanceof Error ? error.message : String(error);
      alert(`${t("expenses.messages.finalizationFailed")}\n${message}`);
    }
  }

  function handleCreateAdjustment(voucher: ExpenseVoucher) {
    if (voucher.voucher_source === "manual") {
      const finalized = voucher.manual_voucher_details?.status === "finalized"
        && Boolean(voucher.manual_voucher_details.manual_vehicle_chakkar_settlements?.[0]);
      if (!finalized) {
        alert("Adjustment is available only after the Manual Voucher is finalized.");
        return;
      }
      if (voucher.archived_at) {
        alert("Archived Voucher cannot be adjusted.");
        return;
      }
      setViewingExpense(null);
      setManualAdjustmentVoucher(voucher);
      return;
    }

    const isFinalized =
      (voucher.vehicle_chakkar_settlements ?? []).length > 0;

    if (!isFinalized) {
      alert("Adjustment is available only after the Voucher is finalized.");
      return;
    }

    if (voucher.archived_at) {
      alert("Archived Voucher cannot be adjusted.");
      return;
    }

    setViewingExpense(null);
    setAdjustmentVoucher(voucher);
  }

  async function handleAdjustmentChanged() {
    await Promise.all([
      loadExpenseVouchers(),
      loadWorkshopEntries(),
    ]);
  }

  function closeVoucherView() {
    setViewingExpense(null);
    if (typeof window === "undefined") return;
    const url = new URL(window.location.href);
    url.searchParams.delete("voucherId");
    window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}${url.hash}`);
    voucherViewHandledIdRef.current = null;
  }

  async function handleDeleteExpenseVoucher(voucher: ExpenseVoucher) {
    setIsDeleting(true);

    try {
      if (voucher.voucher_source === "manual") {
        if (!window.confirm(`${t("expenses.messages.deleteConfirm")} ${voucher.expense_no}?`)) return;
        const { error } = await supabase.rpc("delete_manual_voucher_draft", {
          p_voucher_id: voucher.id,
        });
        if (error) {
          console.error("Manual Voucher draft deletion refused:", error);
          alert(`${t("expenses.messages.safeDeleteFailed")}\n${error.message}`);
          return;
        }
        if (editingId === voucher.id) resetForm();
        if (viewingExpense?.id === voucher.id) setViewingExpense(null);
        alert(t("expenses.messages.deletedSuccessfully"));
        await loadExpenseVouchers();
        return;
      }

      const { data: dispositionData, error: dispositionError } = await supabase.rpc(
        "get_voucher_removal_disposition",
        { p_voucher_id: voucher.id }
      );

      if (dispositionError) {
        console.error("Voucher removal classification failed:", {
          code: dispositionError.code,
          message: dispositionError.message,
          details: dispositionError.details,
          hint: dispositionError.hint,
          voucherId: voucher.id,
          voucherNo: voucher.expense_no,
        });
        alert(t("expenses.messages.dispositionFailed"));
        return;
      }

      const disposition = typeof dispositionData === "string" ? dispositionData : "";

      if (disposition === "PROTECTED_COMPLETED") {
        alert(t("expenses.messages.protectedDelete"));
        return;
      }

      if (disposition === "CONFLICT_REQUIRES_REVIEW") {
        alert(t("expenses.messages.contextConflict"));
        return;
      }

      if (disposition === "ALREADY_ARCHIVED") {
        alert(t("expenses.messages.alreadyArchived"));
        await loadExpenseVouchers();
        return;
      }

      if (disposition === "ARCHIVE_REQUIRED") {
        const confirmed = window.confirm(
          `${t("expenses.messages.archiveConfirm")} ${voucher.expense_no}?`
        );
        if (!confirmed) return;

        const { data: archiveResult, error: archiveError } = await supabase.rpc(
          "archive_voucher_safely",
          { p_voucher_id: voucher.id, p_reason: null }
        );

        if (archiveError) {
          console.error("Safe Voucher archive refused:", {
            code: archiveError.code,
            message: archiveError.message,
            details: archiveError.details,
            hint: archiveError.hint,
            voucherId: voucher.id,
            voucherNo: voucher.expense_no,
          });
          if (archiveError.message.includes("PROTECTED_COMPLETED_VOUCHER")) {
            alert(t("expenses.messages.protectedDelete"));
          } else if (archiveError.message.includes("VOUCHER_ARCHIVE_CONTEXT_CONFLICT")) {
            alert(t("expenses.messages.contextConflict"));
          } else {
            alert(t("expenses.messages.archiveFailed"));
          }
          return;
        }

        if (archiveResult !== "ARCHIVED" && archiveResult !== "ALREADY_ARCHIVED") {
          console.error("Unexpected Voucher archive result:", {
            archiveResult,
            voucherId: voucher.id,
            voucherNo: voucher.expense_no,
          });
          alert(t("expenses.messages.archiveFailed"));
          return;
        }

        if (editingId === voucher.id) resetForm();
        if (viewingExpense?.id === voucher.id) setViewingExpense(null);
        alert(t("expenses.messages.archivedSuccessfully"));
        await loadExpenseVouchers();
        return;
      }

      if (disposition !== "SAFE_DELETE") {
        console.error("Unknown Voucher removal disposition:", {
          disposition,
          voucherId: voucher.id,
          voucherNo: voucher.expense_no,
        });
        alert(t("expenses.messages.dispositionFailed"));
        return;
      }

      const confirmed = window.confirm(
        `${t("expenses.messages.deleteConfirm")} ${voucher.expense_no}?`
      );
      if (!confirmed) return;

      const receiptPaths = (voucher.expense_items ?? [])
        .map((item) => item.receipt_url ? getReceiptPath(item.receipt_url) : null)
        .filter((path): path is string => Boolean(path));
      const { error } = await supabase.rpc("delete_voucher_safely", {
        p_voucher_id: voucher.id,
      });

      if (error) {
        console.error("Safe Voucher deletion refused:", {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          voucherId: voucher.id,
          voucherNo: voucher.expense_no,
        });
        if (error.message.includes("PROTECTED_COMPLETED_VOUCHER")) {
          alert(t("expenses.messages.protectedDelete"));
        } else if (error.message.includes("VOUCHER_DIESEL_PAYMENT_DEPENDENCY") ||
          error.message.includes("VOUCHER_NON_AUTOMATIC_CASHBOOK_DEPENDENCY")) {
          alert(t("expenses.messages.accountingDeleteBlocked"));
        } else {
          alert(t("expenses.messages.safeDeleteFailed"));
        }
        return;
      }

      if (receiptPaths.length > 0) {
        const { error: receiptError } = await supabase.storage
          .from("expense-receipts")
          .remove(receiptPaths);
        if (receiptError) console.error("Voucher deleted, but receipt cleanup failed:", receiptError);
      }

      if (editingId === voucher.id) resetForm();
      if (viewingExpense?.id === voucher.id) setViewingExpense(null);

      alert(t("expenses.messages.deletedSuccessfully"));
      await Promise.all([loadExpenseVouchers(), loadWorkshopEntries(), loadOilEntries(), loadTyreEntries(), loadDriverEarnings()]);
    } catch (error) {
      console.error("Unable to delete expense voucher:", error);
      alert(t("expenses.messages.safeDeleteFailed"));
    } finally {
      setIsDeleting(false);
    }
  }

  function buildVoucherPrintPresentation(voucher: ExpenseVoucher, laterVehiclePaid: number, parchiWithheld: number): VoucherPrintPresentation | null {
    const manual = voucher.voucher_source === "manual";
    const detail = voucher.manual_voucher_details;
    if (manual && !detail) return null;

    const voucherLoadings = getVoucherLoadings(voucher);
    const groupId = getVoucherMovementGroupId(voucher);
    const group = groupId
      ? movementGroupsById.get(groupId) ?? relationOne(voucher.movement_group)
      : null;
    const groupBilties = groupId
      ? movementBilties.filter((bilty) => String(bilty.bilty_group_id) === String(groupId))
      : [];
    const linkedBilties = new Map<string, BookingRelation>();
    voucherLoadings.forEach((loading) => {
      const booking = loadingBooking(loading);
      if (booking) linkedBilties.set(String(booking.id), booking);
    });
    const linkedBookingAddas = groupId
      ? [...groupBilties.map((booking) => booking.adda_id), ...Array.from(linkedBilties.values()).map((booking) => booking.adda_id)]
      : voucherLoadings.map((loading) => loadingBooking(loading)?.adda_id ?? null);
    const addaId = resolveVoucherPrintOwnerAddaId({
      kind: manual ? "manual" : "standard",
      manualAddaId: detail?.adda_id,
      movementGroupId: groupId,
      movementGroupAddaId: group?.adda_id ?? null,
      linkedBookingAddaIds: linkedBookingAddas,
    });
    if (!addaId) return null;

    const tripLoadings = groupId && groupBilties.length
      ? getMovementGroupLoadings(loadings, groupId, groupBilties)
      : voucherLoadings;
    const allGroupLegs = groupId && groupBilties.length
      ? [...groupBilties].sort((left, right) => {
          const order = { outbound: 0, local: 1, return: 2 } as const;
          return (order[left.trip_type as keyof typeof order] ?? 3) - (order[right.trip_type as keyof typeof order] ?? 3);
        })
      : Array.from(linkedBilties.values());
    const loadingByBooking = new Map<string, LoadingRecord>();
    tripLoadings.forEach((loading) => {
      if (loading.booking_id) loadingByBooking.set(String(loading.booking_id), loading);
    });
    const legs = manual ? [] : allGroupLegs.map((booking) => {
      const loading = loadingByBooking.get(String(booking.id));
      return {
        loadingNo: loading?.loading_no ?? null,
        biltyNo: booking.booking_no ?? null,
        tripType: booking.trip_type ?? null,
        route: loading?.route ?? null,
        vehicleNo: loading?.vehicles?.vehicle_no ?? relationOne(booking.vehicles)?.vehicle_no ?? null,
        vehicleOwner: loading?.vehicles?.owner_name ?? relationOne(booking.vehicles)?.owner_name ?? null,
        driverName: loading?.drivers?.name ?? null,
        loadingDate: loading?.loading_date ?? null,
        departureDate: booking.departure_date ?? null,
        arrivalDate: booking.arrival_date ?? null,
      };
    });

    const expenseRows: VoucherPrintExpense[] = manual && detail?.status === "finalized" && detail.manual_vehicle_chakkar_settlements?.[0]?.expense_snapshot
      ? detail.manual_vehicle_chakkar_settlements[0].expense_snapshot.map((item, index) => ({
          id: `manual-snapshot-${voucher.id}-${index}`,
          expenseClass: normalizeExpenseClass(item.expense_class, item.expense_type),
          expenseType: item.expense_type,
          amount: item.amount,
          paymentMethod: null,
          remarks: item.remarks,
          receiptName: null,
          sourceDetails: [],
        }))
      : (voucher.expense_items ?? []).map((item) => ({
          id: item.id,
          expenseClass: normalizeExpenseClass(item.expense_class, item.expense_type),
          expenseType: item.expense_type,
          amount: item.amount,
          paymentMethod: item.payment_method,
          remarks: item.remarks,
          receiptName: item.receipt_name,
          sourceDetails: [],
        }));
    const expenseIndexById = new Map(expenseRows.flatMap((item, index) =>
      typeof item.id === "number" ? [[item.id, index] as const] : []));
    const unassignedSourceReferences: VoucherPrintSourceReference[] = [];

    (voucher.diesel_entries ?? []).filter((diesel) => manual
      ? diesel.manual_voucher_id === detail?.id
      : voucherLoadings.some((loading) => String(loading.id) === String(diesel.loading_id))).forEach((diesel) => {
      const source = [diesel.petrol_pumps?.pump_name, diesel.slip_no].filter(Boolean).join(" · ");
      if (!source) return;
      const index = expenseIndexById.get(diesel.expense_item_id)
        ?? (manual ? expenseRows.findIndex((item) => item.expenseType === "Fuel") : -1);
      if (index !== undefined && index >= 0) expenseRows[index].sourceDetails.push(source);
      else unassignedSourceReferences.push({ category: "Fuel", detail: source });
    });

    const addLinkedSource = (category: string, detailText: string) => {
      if (!detailText) return;
      const matching = expenseRows.find((item) => item.expenseType === category);
      if (matching) matching.sourceDetails.push(detailText);
      else unassignedSourceReferences.push({ category, detail: detailText });
    };
    (voucher.voucher_workshop_entries ?? []).forEach(({ workshop_entries: entry }) => {
      if (entry?.adda_id === addaId) addLinkedSource("Workshop", [entry.work_date, entry.workshop_name, entry.bill_no].filter(Boolean).join(" · "));
    });
    (voucher.voucher_oil_entries ?? []).forEach(({ oil_vehicle_entries: entry }) => {
      if (!entry || entry.adda_id !== addaId) return;
      const product = relationOne(entry.oil_products);
      const shop = relationOne(entry.oil_shops);
      addLinkedSource("Oil / Lubricants", [entry.entry_date, shop?.shop_name, product?.oil_type, product?.brand, product?.grade, entry.bill_no].filter(Boolean).join(" · "));
    });
    (voucher.voucher_tyre_entries ?? []).forEach(({ tyre_vehicle_entries: entry }) => {
      if (entry?.adda_id === addaId) addLinkedSource("Tyre", [entry.entry_date, relationOne(entry.tyre_shops)?.shop_name, entry.bill_no].filter(Boolean).join(" · "));
    });
    (voucher.voucher_driver_earnings ?? []).forEach(({ driver_earnings: entry }) => {
      if (entry?.adda_id === addaId) addLinkedSource("Driver Salary", [entry.salary_date, relationOne(entry.drivers)?.name, relationOne(entry.vehicles)?.vehicle_no].filter(Boolean).join(" · "));
    });

    const manualSettlement = detail?.manual_vehicle_chakkar_settlements?.[0];
    const manualUsesSnapshot = detail?.status === "finalized" && Boolean(manualSettlement);
    const manualFreightRows = manualUsesSnapshot
      ? manualSettlement?.freight_snapshot ?? []
      : detail?.manual_voucher_freight_items ?? [];
    const manualExpenseTotal = (voucher.expense_items ?? []).reduce((sum, item) => sum + toNumber(item.amount), 0);
    const manualFreightTotal = manualUsesSnapshot
      ? toNumber(manualSettlement?.total_freight)
      : (detail?.manual_voucher_freight_items ?? []).reduce((sum, row) => sum + toNumber(row.amount), 0);
    const totalExpenseAmount = manualUsesSnapshot
      ? toNumber(manualSettlement?.total_expense_amount)
      : manualExpenseTotal;
    const manualNet = manualUsesSnapshot
      ? toNumber(manualSettlement?.net_vehicle_amount)
      : manualFreightTotal - totalExpenseAmount;
    const uniqueLinkedBilties = new Map(voucherLoadings.flatMap((loading) => {
      const booking = loadingBooking(loading);
      return booking ? [[booking.id, booking] as const] : [];
    }));
    const linkedBiltiesForSummary = Array.from(uniqueLinkedBilties.values());
    const vehicleFreight = linkedBiltiesForSummary.reduce((sum, booking) => sum + toNumber(booking.vehicle_freight), 0);
    const vehicleAdvance = linkedBiltiesForSummary.reduce((sum, booking) => sum + toNumber(booking.advance_vehicle), 0);
    const totalVehiclePaid = vehicleAdvance + laterVehiclePaid;
    const totalTripExpenses = (voucher.expense_items ?? []).reduce((sum, item) => sum + toNumber(item.amount), 0);
    const groupOutboundNo = groupId ? groupBilties.find((booking) => String(booking.id) === String(group?.outbound_bilty_id))?.booking_no : null;
    const groupDisplay = groupId ? [groupOutboundNo, groupId].filter(Boolean).join(" · ") : null;

    return createVoucherPrintPresentation({
      kind: manual ? "manual" : "standard",
      addaId,
      voucherNo: voucher.expense_no,
      voucherDate: manual ? detail?.voucher_date ?? voucher.expense_date : voucher.expense_date,
      // Manual Voucher expense dates retain their legacy voucher_date semantics.
      // Only the dedicated saved departure/arrival fields represent trip dates.
      startDate: manual ? null : voucher.start_date ?? voucher.expense_date,
      endDate: manual ? null : voucher.end_date ?? voucher.expense_date,
      totalDays: voucher.start_date && voucher.end_date ? calendarDayDifference(voucher.start_date, voucher.end_date) : null,
      movementGroupNo: groupDisplay,
      loadingNumbers: tripLoadings.map((loading) => loading.loading_no).filter(Boolean),
      legs,
      vehicleNo: detail?.vehicle_no ?? null,
      vehicleOwner: detail?.vehicle_owner ?? null,
      driverName: detail?.driver_name ?? null,
      chakkarDays: detail?.chakkar_days ?? null,
      departureDate: manual ? detail?.departure_date ?? null : null,
      arrivalDate: manual ? detail?.arrival_date ?? null : null,
      status: detail?.status ?? null,
      remarks: detail?.remarks ?? voucher.description,
      freightItems: manual ? manualFreightRows.map((row, index) => ({
        id: index,
        tripType: row.freight_type,
        amount: row.amount,
        description: row.description,
      })) : [],
      expenseItems: expenseRows,
      unassignedSourceReferences,
      summary: {
        vehicleFreight: manual ? null : vehicleFreight,
        vehicleAdvance: manual ? null : vehicleAdvance,
        vehicleLaterPaid: manual ? null : laterVehiclePaid,
        vehicleTotalPaid: manual ? null : totalVehiclePaid,
        vehicleParchiWithheld: manual ? null : parchiWithheld,
        vehicleEntitlementSettled: manual ? null : totalVehiclePaid + parchiWithheld,
        vehicleBalance: manual ? null : Math.max(vehicleFreight - totalVehiclePaid - parchiWithheld, 0),
        regularExpenseTotal: manual ? null : (voucher.expense_items ?? []).filter((item) => normalizeExpenseClass(item.expense_class, item.expense_type) === "regular_trip").reduce((sum, item) => sum + toNumber(item.amount), 0),
        periodicExpenseTotal: manual ? null : (voucher.expense_items ?? []).filter((item) => normalizeExpenseClass(item.expense_class, item.expense_type) === "vehicle_periodic").reduce((sum, item) => sum + toNumber(item.amount), 0),
        totalTripExpenses: manual ? null : totalTripExpenses,
        vehicleProfitLoss: manual ? null : vehicleFreight - totalTripExpenses,
        manualTotalFreight: manual ? manualFreightTotal : null,
        manualTotalExpenses: manual ? totalExpenseAmount : null,
        manualNetVehicleEarnings: manual ? manualNet : null,
      },
    });
  }

  async function handlePrintExpenseVoucher(voucher: ExpenseVoucher) {
    try {
      let laterVehiclePaid = 0;
      let parchiWithheld = 0;
      if (voucher.voucher_source !== "manual") {
        const linkedBilties = new Map(getVoucherLoadings(voucher).flatMap((loading) => {
          const booking = loadingBooking(loading);
          return booking ? [[booking.id, booking] as const] : [];
        }));
        const linkedBiltyIds = Array.from(linkedBilties.keys());
        if (linkedBiltyIds.length) {
          const { data, error } = await supabase.from("bilty_payments").select("amount").in("bilty_id", linkedBiltyIds).eq("payment_side", "vehicle");
          if (error) throw new Error(error.message);
          laterVehiclePaid = (data ?? []).reduce((sum, payment) => sum + toNumber(payment.amount), 0);
          const parchiTotals = await getParchiVehicleSettlementTotalsForBookings(
            Array.from(linkedBilties.values(), (booking) => ({ id: booking.id, adda_id: booking.adda_id }))
          );
          parchiWithheld = Array.from(parchiTotals.values()).reduce((sum, total) => sum + total.withheldCommission, 0);
        }
      }
      const presentation = buildVoucherPrintPresentation(voucher, laterVehiclePaid, parchiWithheld);
      if (!presentation) {
        alert(language === "ur"
          ? "واؤچر کا مالک اڈہ محفوظ حوالوں سے تصدیق نہیں ہو سکا۔ موجودہ پرنٹ کھولا جا رہا ہے۔"
          : "The Voucher owner Adda could not be verified from its saved relationships. Opening the existing print.");
        await handleLegacyPrintExpenseVoucher(voucher);
        return;
      }
      setVoucherPrintVoucher(voucher);
      setVoucherPrintPresentation(presentation);
    } catch (error) {
      console.error("Unable to prepare Voucher print presentation:", error);
      alert(language === "ur"
        ? "مطلوبہ محفوظ ادائیگی معلومات لوڈ نہیں ہو سکیں۔ موجودہ پرنٹ کھولا جا رہا ہے۔"
        : "Required saved Voucher payment details could not be loaded. Opening the existing print.");
      await handleLegacyPrintExpenseVoucher(voucher);
    }
  }

  async function handleLegacyPrintExpenseVoucher(voucher: ExpenseVoucher) {
    if (voucher.voucher_source === "manual") {
      const detail = voucher.manual_voucher_details;
      if (!detail) return;
      const settlement = detail.manual_vehicle_chakkar_settlements?.[0];
      const useFinalizedSnapshot = detail.status === "finalized" && Boolean(settlement);
      const freightRows = useFinalizedSnapshot
        ? settlement?.freight_snapshot ?? []
        : detail.manual_voucher_freight_items ?? [];
      const persistedExpenseRows = (voucher.expense_items ?? []).map((item) => ({
        expense_class: item.expense_class ?? "regular_trip",
        expense_type: item.expense_type,
        amount: item.amount,
        remarks: item.remarks,
      }));
      const expenseRows = useFinalizedSnapshot
        ? settlement?.expense_snapshot ?? []
        : persistedExpenseRows;
      const totalFreight = Number(useFinalizedSnapshot
        ? settlement?.total_freight ?? 0
        : (detail.manual_voucher_freight_items ?? []).reduce((sum, row) => sum + toNumber(row.amount), 0));
      const persistedExpenseTotal = persistedExpenseRows.reduce((sum, item) => sum + toNumber(item.amount), 0);
      const totalExpenses = useFinalizedSnapshot
        ? Number(settlement?.total_expense_amount ?? 0)
        : persistedExpenseTotal;
      const net = useFinalizedSnapshot
        ? Number(settlement?.net_vehicle_amount ?? 0)
        : totalFreight - totalExpenses;
      const popup = window.open("", "_blank", "width=1000,height=800");
      if (!popup) {
        alert(t("expenses.messages.allowPopups"));
        return;
      }
      const esc = (value: unknown) => escapeHtml(value ?? "—");
      const freightHtml = freightRows.map((row) => `<tr><td>${esc(t(`expenses.manual.freightTypes.${row.freight_type}`))}</td><td class="money">Rs. ${esc(money(toNumber(row.amount)))}</td><td>${esc(row.description || "—")}</td></tr>`).join("");
      const manualDieselEntries = [...(voucher.diesel_entries ?? [])]
        .filter((diesel) => diesel.manual_voucher_id === detail.id)
        .sort((left, right) => left.expense_item_id - right.expense_item_id);
      let manualDieselIndex = 0;
      const expenseHtml = expenseRows.map((row) => {
        const diesel = row.expense_type === "Fuel" ? manualDieselEntries[manualDieselIndex++] : null;
        const dieselDetails = diesel
          ? `<div>${esc(t("expenses.diesel.petrolPump"))}: ${esc(diesel.petrol_pumps?.pump_name)} · ${esc(t("common.date"))}: ${esc(diesel.entry_date)} · ${esc(t("expenses.diesel.litres"))}: ${esc(diesel.liters)} · ${esc(t("expenses.diesel.rate"))}: ${esc(diesel.rate)} · ${esc(t("common.paid"))}: ${esc(diesel.paid_amount)} · ${esc(t("common.remaining"))}: ${esc(diesel.remaining_amount)} · ${esc(t("expenses.diesel.slipNo"))}: ${esc(diesel.slip_no)} · ${esc(t("common.status"))}: ${esc(t(`common.paymentStatus.${diesel.payment_status.toLowerCase()}`))}</div>`
          : "";
        return `<tr><td>${esc(row.expense_type)}</td><td class="money">Rs. ${esc(money(toNumber(row.amount)))}</td><td>${esc(row.remarks || "—")}${dieselDetails}</td></tr>`;
      }).join("");
      const manualTripDatesHtml = detail.departure_date && detail.arrival_date
        ? `<div class="box"><span>${esc(t("expenses.manual.departureDate"))}</span><strong>${esc(detail.departure_date)}</strong></div><div class="box"><span>${esc(t("expenses.manual.arrivalDate"))}</span><strong>${esc(detail.arrival_date)}</strong></div>`
        : "";
      void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${esc(language)}" dir="${esc(dir)}"><head><meta charset="utf-8"><title>${esc(t("expenses.manual.printTitle"))}</title><style>@page{size:A4 portrait;margin:14mm}body{font-family:Arial,sans-serif;color:#0f172a}h1,h2{text-align:center;margin:5px}.meta,.summary{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin:16px 0}.box{border:1px solid #cbd5e1;border-radius:8px;padding:10px}.box span{display:block;color:#475569;font-size:11px;font-weight:bold}.box strong{display:block;margin-top:5px}table{width:100%;border-collapse:collapse;margin:12px 0}th,td{border:1px solid #cbd5e1;padding:8px;text-align:start}th{background:#1d4ed8;color:white}.money{direction:ltr;text-align:right;white-space:nowrap}.net{font-size:18px;font-weight:bold;color:${net < 0 ? "#b91c1c" : "#047857"}}@media print{body{padding:0}}</style></head><body><h1>${PRINT_ADDA_NAME_TOKEN}</h1><h2>${esc(t("expenses.manual.printTitle"))}</h2><div class="meta"><div class="box"><span>${esc(t("expenses.table.voucherNo"))}</span><strong>${esc(voucher.expense_no)}</strong></div><div class="box"><span>${esc(t("expenses.manual.voucherType"))}</span><strong>${esc(t("expenses.manual.manualWithoutBilty"))}</strong></div><div class="box"><span>${esc(t("expenses.manual.voucherDate"))}</span><strong>${esc(detail.voucher_date)}</strong></div><div class="box"><span>${esc(t("common.vehicle"))}</span><strong>${esc(detail.vehicle_no)}</strong></div><div class="box"><span>${esc(t("common.driver"))}</span><strong>${esc(detail.driver_name || "—")}</strong></div><div class="box"><span>${esc(t("expenses.manual.chakkarDays"))}</span><strong>${esc(detail.chakkar_days)}</strong></div><div class="box"><span>${esc(t("common.status"))}</span><strong>${esc(detail.status === "finalized" ? t("expenses.manual.finalized") : t("expenses.manual.draft"))}</strong></div>${manualTripDatesHtml}</div><h3>${esc(t("expenses.manual.freightTitle"))}</h3><table><thead><tr><th>${esc(t("expenses.manual.freightType"))}</th><th>${esc(t("common.amount"))}</th><th>${esc(t("expenses.manual.routeRemarks"))}</th></tr></thead><tbody>${freightHtml}</tbody></table><h3>${esc(t("expenses.manual.expensesTitle"))}</h3><table><thead><tr><th>${esc(t("expenses.items.expenseType"))}</th><th>${esc(t("common.amount"))}</th><th>${esc(t("common.remarks"))}</th></tr></thead><tbody>${expenseHtml || `<tr><td colspan="3">${esc(t("expenses.manual.noExpenses"))}</td></tr>`}</tbody></table><div class="summary"><div class="box"><span>${esc(t("expenses.manual.totalFreight"))}</span><strong class="money">Rs. ${esc(money(totalFreight))}</strong></div><div class="box"><span>${esc(t("expenses.manual.totalExpenses"))}</span><strong class="money">Rs. ${esc(money(totalExpenses))}</strong></div><div class="box"><span>${esc(t("expenses.manual.netVehicleEarnings"))}</span><strong class="money net">Rs. ${esc(money(net))}</strong></div></div><p>${esc(t("common.remarks"))}: ${esc(detail.remarks || "—")}</p><script>window.onload=()=>{window.focus();window.print()}</script></body></html>`, detail.adda_id, language === "ur" ? "ur" : "en");
      return;
    }
    const printWindow = window.open("", "_blank", "width=1100,height=800");

    if (!printWindow) {
      alert(t("expenses.messages.allowPopups"));
      return;
    }

    const label = (key: string) => escapeHtml(t(key));
    const value = (input: unknown) => escapeHtml(input ?? "-");
    printWindow.document.write(
      `<!doctype html><html dir="${value(dir)}" lang="${value(language)}"><body>${label("common.loading")}</body></html>`
    );
    const voucherLoadings = getVoucherLoadings(voucher);
    const loadingNumbers = voucherLoadings
      .map((loading) => loading.loading_no)
      .filter(Boolean)
      .join(", ");
    const totalDays =
      voucher.start_date && voucher.end_date
        ? calendarDayDifference(voucher.start_date, voucher.end_date)
        : null;
    const totalAmount = (voucher.expense_items ?? []).reduce(
      (total, item) => total + toNumber(item.amount),
      0
    );
    const regularItems = (voucher.expense_items ?? []).filter(
      (item) => normalizeExpenseClass(item.expense_class, item.expense_type) === "regular_trip"
    );
    const periodicItems = (voucher.expense_items ?? []).filter(
      (item) => normalizeExpenseClass(item.expense_class, item.expense_type) === "vehicle_periodic"
    );
    const linkedWorkshopEntries = (voucher.voucher_workshop_entries ?? []).flatMap((relation) => relation.workshop_entries ? [relation.workshop_entries] : []);
    const linkedOilEntries = (voucher.voucher_oil_entries ?? []).flatMap((relation) => relation.oil_vehicle_entries ? [relation.oil_vehicle_entries] : []);
    const linkedTyreEntries=(voucher.voucher_tyre_entries??[]).flatMap(relation=>relation.tyre_vehicle_entries?[relation.tyre_vehicle_entries]:[]);
    const linkedDriverEarnings = (voucher.voucher_driver_earnings ?? []).flatMap((relation) => relation.driver_earnings ? [relation.driver_earnings] : []);
    const periodicPrintableItems = periodicItems.filter((item) =>
      !(linkedWorkshopEntries.length > 0 && item.expense_type === "Workshop") &&
      !(linkedOilEntries.length > 0 && item.expense_type === "Oil / Lubricants") &&
      !(linkedTyreEntries.length > 0 && item.expense_type === "Tyre") &&
      !(linkedDriverEarnings.length > 0 && item.expense_type === "Driver Salary")
    );
    const regularTripTotal = regularItems.reduce(
      (total, item) => total + toNumber(item.amount),
      0
    );
    const periodicExpenseTotal = periodicItems.reduce(
      (total, item) => total + toNumber(item.amount),
      0
    );
    // The Voucher item total is the exact-once trip expense authority here:
    // linked Workshop/Oil/Tyre/Driver rows are reference items in this sum and
    // their source-table totals are printed as detail only, never added again.
    const totalTripExpenses = totalAmount;
    const uniqueLinkedBilties = new Map(
      voucherLoadings.flatMap((loading) =>
        loadingBooking(loading)
          ? [[loadingBooking(loading)!.id, loadingBooking(loading)!] as const]
          : []
      )
    );
    const totalVehicleFreight = Array.from(uniqueLinkedBilties.values()).reduce(
      (total, bilty) => total + toNumber(bilty.vehicle_freight),
      0
    );
    const totalAdvanceVehicle = Array.from(uniqueLinkedBilties.values()).reduce(
      (total, bilty) => total + toNumber(bilty.advance_vehicle),
      0
    );
    const linkedBiltyIds = Array.from(uniqueLinkedBilties.keys());
    let laterVehiclePaid = 0;
    let parchiWithheld = 0;

    if (linkedBiltyIds.length > 0) {
      const { data: vehiclePayments, error: vehiclePaymentsError } = await supabase
        .from("bilty_payments")
        .select("amount")
        .in("bilty_id", linkedBiltyIds)
        .eq("payment_side", "vehicle");

      if (vehiclePaymentsError) {
        console.error("Unable to load Voucher print vehicle payments:", vehiclePaymentsError);
        alert(t("expenses.messages.printDataLoadFailed"));
        return;
      } else {
        laterVehiclePaid = (vehiclePayments ?? []).reduce(
          (total, payment) => total + toNumber(payment.amount),
          0
        );
      }
      try {
        const parchiTotals = await getParchiVehicleSettlementTotalsForBookings(
          Array.from(uniqueLinkedBilties.values(), (booking) => ({ id: booking.id, adda_id: booking.adda_id }))
        );
        parchiWithheld = Array.from(parchiTotals.values()).reduce((sum, total) => sum + total.withheldCommission, 0);
      } catch (parchiError) {
        console.error("Unable to load Voucher Parchi vehicle settlement totals:", parchiError);
        alert(t("bilty.states.vehicleSettlementUnavailable"));
        return;
      }
    }

    const totalVehiclePaid = totalAdvanceVehicle + laterVehiclePaid;
    const vehicleEntitlementSettled = totalVehiclePaid + parchiWithheld;
    const vehicleBalance = Math.max(totalVehicleFreight - vehicleEntitlementSettled, 0);
    const vehicleProfitLoss = totalVehicleFreight - totalTripExpenses;
    const voucherOwnerIds = Array.from(new Set(voucherLoadings.map((loading) => loadingBooking(loading)?.adda_id).filter((id): id is string => Boolean(id))));
    const addaId = voucherOwnerIds.length === 1 ? voucherOwnerIds[0] : null;
    let printSettings: VoucherPrintSettings | null = null;

    if (addaId) {
      const { data: settingsData, error: settingsError } = await supabase
        .from("company_settings")
        .select(
          "business_tagline, logo_url, paper_size, show_logo_on_print, show_signature_on_print, print_footer_text"
        )
        .eq("adda_id", addaId)
        .maybeSingle();

      if (settingsError) {
        console.error("Unable to load Voucher print settings:", settingsError);
      } else {
        printSettings = settingsData as VoucherPrintSettings | null;
      }
    }

    const companyTagline = value(printSettings?.business_tagline ?? "");
    const logo =
      printSettings?.show_logo_on_print && printSettings.logo_url
        ? `<img class="logo" src="${value(printSettings.logo_url)}" alt="" />`
        : "";
    const showSignatures = printSettings?.show_signature_on_print !== false;
    const footerText = value(printSettings?.print_footer_text ?? "");
    const paperSize =
      printSettings?.paper_size === "A5"
        ? "A5"
        : printSettings?.paper_size === "thermal-80mm"
          ? "80mm auto"
          : "A4";
    const dieselByItemId = new Map<number, DieselEntryRecord>();
    (voucher.diesel_entries ?? []).forEach((diesel) => {
      dieselByItemId.set(diesel.expense_item_id, diesel);
    });

    function renderItemRows(items: ExpenseItemRecord[]) {
      return items
            .map((item, index) => {
              const diesel = dieselByItemId.get(item.id);
              const dieselDetails = diesel
                ? `
                  <div class="diesel">
                    <strong>${label("expenses.diesel.petrolPump")}:</strong> ${value(
                      diesel.petrol_pumps?.pump_name
                    )} |
                    <strong>${label("expenses.diesel.litres")}:</strong> ${value(diesel.liters)} |
                    <strong>${label("expenses.diesel.rate")}:</strong> ${value(diesel.rate)} |
                    <strong>${label("common.total")}:</strong> ${value(diesel.total_amount)} |
                    <strong>${label("common.paid")}:</strong> ${value(diesel.paid_amount)} |
                    <strong>${label("common.remaining")}:</strong> ${value(diesel.remaining_amount)} |
                    <strong>${label("common.status")}:</strong> ${label(`common.paymentStatus.${diesel.payment_status.toLowerCase()}`)} |
                    <strong>${label("expenses.diesel.slipNo")}:</strong> ${value(diesel.slip_no)}
                  </div>
                `
                : "";

              return `
                <tr>
                  <td>${index + 1}</td>
                  <td>${label(expenseTypeLabelKey(item.expense_type))}</td>
                  <td class="technical">${value(Number(item.amount || 0).toLocaleString())}</td>
                  <td>${value(item.payment_method)}</td>
                  <td>${value(item.remarks)}${dieselDetails}</td>
                  <td>${value(item.receipt_name)}</td>
                </tr>
              `;
            })
            .join("");
    }

    const regularItemRows = renderItemRows(regularItems);
    const periodicItemRows = renderItemRows(periodicPrintableItems);
    const linkedWorkshopRows = linkedWorkshopEntries.map((entry, index) => {
      const items = [...(entry.workshop_entry_items ?? [])].sort((a,b) => a.line_no-b.line_no);
      const work = items.length ? `${items[0].work_type}${items.length > 1 ? ` +${items.length-1}` : ""}` : entry.work_type ?? "-";
      return `<tr><td>${index+1}</td><td class="technical">${value(entry.work_date)}</td><td>${value(entry.workshop_name)}</td><td class="technical">${value(relationOne(entry.vehicles)?.vehicle_no)}</td><td>${value(work)}</td><td class="technical">${value(entry.bill_no)}</td><td class="technical">Rs. ${value(toNumber(entry.total_cost).toLocaleString())}</td></tr>`;
    }).join("");
    const linkedWorkshopTotal = linkedWorkshopEntries.reduce((sum, entry) => sum + toNumber(entry.total_cost), 0);
    const linkedOilRows = linkedOilEntries.map((entry, index) => {
      const product = relationOne(entry.oil_products);
      const vehicle = relationOne(entry.vehicles);
      const shop = relationOne(entry.oil_shops);
      const productName = [product?.oil_type, product?.brand, product?.grade].filter(Boolean).join(" · ") || "-";
      const source = t(`oil.options.${entry.source_type === "adda_stock" ? "addaStock" : "externalShop"}`);
      return `<tr><td>${index+1}</td><td class="technical">${value(entry.entry_date)}</td><td class="technical">${value(vehicle?.vehicle_no)}</td><td>${value(productName)}</td><td class="technical">${value(entry.liters)} L</td><td class="technical">Rs. ${value(toNumber(entry.rate_per_liter).toLocaleString())}</td><td>${value(source)}${shop?.shop_name ? ` · ${value(shop.shop_name)}` : ""}</td><td class="technical">${value(entry.bill_no)}</td><td class="technical">Rs. ${value(toNumber(entry.total_amount).toLocaleString())}</td></tr>`;
    }).join("");
    const linkedOilTotal = linkedOilEntries.reduce((sum, entry) => sum + toNumber(entry.total_amount), 0);
    const linkedTyreRows=linkedTyreEntries.map((entry,index)=>{const vehicle=relationOne(entry.vehicles),shop=relationOne(entry.tyre_shops),itemRows=entry.tyre_vehicle_entry_items??[];const serials=itemRows.flatMap(item=>{const asset=relationOne(item.tyre_assets);return asset?.serial_number?[asset.serial_number]:[]}).join(", ");const positions=itemRows.flatMap(item=>{const position=relationOne(item.vehicle_tyre_positions);return position?.position_label?[position.position_label]:[]}).join(", ");return `<tr><td>${index+1}</td><td>${value(entry.entry_date)}</td><td>${value(vehicle?.vehicle_no)}</td><td>${value(shop?.shop_name)}</td><td>${value(entry.bill_no)}</td><td>${label(`tyre.work.${entry.work_type}`)}</td><td>${value(serials)}</td><td>${value(positions)}</td><td>Rs. ${value(toNumber(entry.total_amount).toLocaleString())}</td></tr>`}).join("");
    const linkedTyreTotal=linkedTyreEntries.reduce((sum,entry)=>sum+toNumber(entry.total_amount),0);
    const linkedDriverRows = linkedDriverEarnings.map((entry, index) => {
      const driver = relationOne(entry.drivers);
      const vehicle = relationOne(entry.vehicles);
      return `<tr><td>${index + 1}</td><td>${value(driver?.name)}</td><td class="technical">${value(entry.salary_date)}</td><td class="technical">${value(entry.salary_month)}</td><td>${value(vehicle?.vehicle_no)}</td><td>${label(`drivers.account.earningTypes.${entry.earning_type}`)}</td><td class="technical">Rs. ${value(toNumber(entry.gross_expense).toLocaleString("en-PK"))}</td><td class="technical">Rs. ${value(toNumber(entry.paid_amount).toLocaleString("en-PK"))}</td><td class="technical">Rs. ${value(toNumber(entry.remaining_amount).toLocaleString("en-PK"))}</td></tr>`;
    }).join("");
    const linkedDriverTotal = linkedDriverEarnings.reduce((sum, entry) => sum + toNumber(entry.gross_expense), 0);

    void writeAddaBrandedPrintDocument(printWindow, `
      <!doctype html>
      <html dir="${value(dir)}" lang="${value(language)}">
        <head>
          <title>${label("expenses.title")} - ${value(voucher.expense_no)}</title>
          <style>
            @page { size: ${paperSize}; margin: 12mm; }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 28px;
              color: #111827;
              font-family: Arial, sans-serif;
              background: #ffffff;
            }
            .voucher {
              max-width: 1000px;
              margin: 0 auto;
              border: 1px solid #d1d5db;
              border-radius: 10px;
              padding: 24px;
            }
            .header {
              display: flex;
              justify-content: space-between;
              gap: 20px;
              border-bottom: 2px solid #111827;
              padding-bottom: 16px;
              margin-bottom: 18px;
            }
            .brand { display: flex; align-items: center; gap: 12px; }
            .logo { width: 64px; height: 64px; object-fit: contain; }
            .tagline { margin-top: 4px; font-size: 12px; }
            h1 { margin: 0; font-size: 28px; color: #111827; }
            .meta { text-align: right; line-height: 1.7; font-size: 14px; }
            .details {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 10px 24px;
              margin-bottom: 20px;
            }
            .details div {
              border-bottom: 1px solid #e5e7eb;
              padding-bottom: 8px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 13px;
            }
            th {
              background: #2563eb;
              color: #ffffff;
              text-align: left;
              padding: 9px;
              border: 1px solid #2563eb;
            }
            td {
              padding: 9px;
              border: 1px solid #d1d5db;
              vertical-align: top;
            }
            tfoot td {
              font-weight: 800;
              background: #f9fafb;
            }
            .diesel {
              margin-top: 6px;
              line-height: 1.6;
              font-size: 12px;
            }
            .empty {
              text-align: center;
              font-weight: 700;
            }
            .signatures {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 24px;
              margin-top: 48px;
            }
            .signature {
              border-top: 1px solid #111827;
              padding-top: 8px;
              text-align: center;
            }
            .technical {
              direction: ltr;
              unicode-bidi: isolate;
            }
            .footer { margin-top: 24px; text-align: center; font-size: 12px; }
            .expense-section { margin-top: 20px; }
            .expense-section h2 { margin: 0 0 8px; font-size: 16px; }
          </style>
        </head>
        <body>
          <div class="voucher">
            <div class="header">
              <div>
                <div class="brand">
                  ${logo}
                  <div>
                    <h1>${PRINT_ADDA_NAME_TOKEN}</h1>
                    <div class="tagline">${companyTagline}</div>
                    <div>${label("expenses.print.title")}</div>
                  </div>
                </div>
              </div>
              <div class="meta">
                <div><strong>${label("expenses.table.voucherNo")}:</strong> <span class="technical">${value(voucher.expense_no)}</span></div>
                <div><strong>${label("expenses.form.startDate")}:</strong> <span class="technical">${value(voucher.start_date ?? voucher.expense_date)}</span></div>
                <div><strong>${label("expenses.form.endDate")}:</strong> <span class="technical">${value(voucher.end_date ?? voucher.expense_date)}</span></div>
                ${totalDays === null ? "" : `<div><strong>${label("expenses.form.totalDays")}:</strong> <span class="technical">${value(totalDays)} ${label("expenses.form.days")}</span></div>`}
              </div>
            </div>

            <div class="details">
              <div><strong>${label("expenses.table.loadingNumbers")}:</strong> <span class="technical">${value(loadingNumbers)}</span></div>
              <div><strong>${label("expenses.table.loadingCount")}:</strong> <span class="technical">${value(voucherLoadings.length)}</span></div>
              <div><strong>${label("expenses.biltyFinance.totalVehicleFreight")}:</strong> <span class="technical">Rs. ${value(totalVehicleFreight.toLocaleString())}</span></div>
              <div><strong>${label("expenses.items.regularTotal")}:</strong> <span class="technical">Rs. ${value(regularTripTotal.toLocaleString())}</span></div>
              <div><strong>${label("expenses.items.periodicTotal")}:</strong> <span class="technical">Rs. ${value(periodicExpenseTotal.toLocaleString())}</span></div>
              <div><strong>${label("expenses.biltyFinance.totalTripExpenses")}:</strong> <span class="technical">Rs. ${value(totalTripExpenses.toLocaleString())}</span></div>
              <div><strong>${label("expenses.table.voucherTotal")}:</strong> <span class="technical">Rs. ${value(totalAmount.toLocaleString())}</span></div>
              <div><strong>${label("expenses.biltyFinance.vehicleProfitLoss")}:</strong> <span class="technical">Rs. ${value(vehicleProfitLoss.toLocaleString())}</span></div>
              <div><strong>${label("expenses.biltyFinance.totalVehiclePaid")}:</strong> <span class="technical">Rs. ${value(totalVehiclePaid.toLocaleString())}</span></div>
              <div><strong>${label("expenses.biltyFinance.parchiWithheldCommission")}:</strong> <span class="technical">Rs. ${value(parchiWithheld.toLocaleString())}</span></div>
              <div><strong>${label("expenses.biltyFinance.vehicleEntitlementSettled")}:</strong> <span class="technical">Rs. ${value(vehicleEntitlementSettled.toLocaleString())}</span></div>
              <div><strong>${label("expenses.biltyFinance.vehicleBalance")}:</strong> <span class="technical">Rs. ${value(vehicleBalance.toLocaleString())}</span></div>
            </div>

            ${regularItems.length === 0 ? "" : `
              <section class="expense-section">
                <h2>${label("expenses.items.regularTrip")}</h2>
                <table>
                  <thead><tr>
                    <th>#</th><th>${label("expenses.items.expenseType")}</th><th>${label("common.amount")}</th>
                    <th>${label("expenses.print.payment")}</th><th>${label("expenses.print.remarksDiesel")}</th><th>${label("common.receipt")}</th>
                  </tr></thead>
                  <tbody>${regularItemRows}</tbody>
                  <tfoot><tr><td colspan="2">${label("expenses.items.regularTotal")}</td><td colspan="4" class="technical">Rs. ${value(regularTripTotal.toLocaleString())}</td></tr></tfoot>
                </table>
              </section>`}

            ${periodicPrintableItems.length === 0 ? "" : `
              <section class="expense-section">
                <h2>${label("expenses.items.vehiclePeriodic")}</h2>
                <table>
                  <thead><tr>
                    <th>#</th><th>${label("expenses.items.expenseType")}</th><th>${label("common.amount")}</th>
                    <th>${label("expenses.print.payment")}</th><th>${label("expenses.print.remarksDiesel")}</th><th>${label("common.receipt")}</th>
                  </tr></thead>
                  <tbody>${periodicItemRows}</tbody>
                  <tfoot><tr><td colspan="2">${label("expenses.items.periodicTotal")}</td><td colspan="4" class="technical">Rs. ${value(periodicExpenseTotal.toLocaleString())}</td></tr></tfoot>
                </table>
              </section>`}

            ${linkedWorkshopEntries.length === 0 ? "" : `<section class="expense-section"><h2>${label("expenses.workshopLink.printTitle")}</h2><table><thead><tr><th>#</th><th>${label("workshop.fields.workDate")}</th><th>${label("workshop.fields.workshopName")}</th><th>${label("workshop.table.vehicle")}</th><th>${label("workshop.fields.workType")}</th><th>${label("workshop.fields.billNo")}</th><th>${label("common.amount")}</th></tr></thead><tbody>${linkedWorkshopRows}</tbody><tfoot><tr><td colspan="6">${label("expenses.workshopLink.selectedTotal")}</td><td class="technical">Rs. ${value(linkedWorkshopTotal.toLocaleString())}</td></tr></tfoot></table></section>`}

            ${linkedOilEntries.length === 0 ? "" : `<section class="expense-section"><h2>${label("expenses.oilLink.printTitle")}</h2><table><thead><tr><th>#</th><th>${label("oil.fields.date")}</th><th>${label("oil.fields.vehicle")}</th><th>${label("oil.fields.oilProduct")}</th><th>${label("oil.fields.liters")}</th><th>${label("oil.fields.rate")}</th><th>${label("oil.fields.source")}</th><th>${label("oil.fields.billNo")}</th><th>${label("common.amount")}</th></tr></thead><tbody>${linkedOilRows}</tbody><tfoot><tr><td colspan="8">${label("expenses.oilLink.selectedTotal")}</td><td class="technical">Rs. ${value(linkedOilTotal.toLocaleString())}</td></tr></tfoot></table></section>`}

            ${linkedTyreEntries.length===0?"":`<section class="expense-section"><h2>${label("expenses.tyreLink.printTitle")}</h2><table><thead><tr><th>#</th><th>${label("tyre.fields.date")}</th><th>${label("tyre.fields.vehicle")}</th><th>${label("tyre.fields.shopName")}</th><th>${label("tyre.fields.billNo")}</th><th>${label("tyre.fields.workType")}</th><th>${label("tyre.fields.serial")}</th><th>${label("tyre.fields.position")}</th><th>${label("common.amount")}</th></tr></thead><tbody>${linkedTyreRows}</tbody><tfoot><tr><td colspan="8">${label("expenses.tyreLink.selectedTotal")}</td><td>Rs. ${value(linkedTyreTotal.toLocaleString())}</td></tr></tfoot></table></section>`}

            ${linkedDriverEarnings.length === 0 ? "" : `<section class="expense-section"><h2>${label("expenses.driverLink.printTitle")}</h2><table><thead><tr><th>#</th><th>${label("expenses.driverLink.driver")}</th><th>${label("drivers.account.salaryDate")}</th><th>${label("drivers.account.salaryMonth")}</th><th>${label("drivers.master.vehicle")}</th><th>${label("drivers.account.earningType")}</th><th>${label("drivers.account.grossExpense")}</th><th>${label("expenses.driverLink.settled")}</th><th>${label("common.remaining")}</th></tr></thead><tbody>${linkedDriverRows}</tbody><tfoot><tr><td colspan="8">${label("expenses.driverLink.selectedTotal")}</td><td class="technical">Rs. ${value(linkedDriverTotal.toLocaleString("en-PK"))}</td></tr></tfoot></table></section>`}

            <div class="expense-section"><strong>${label("expenses.items.grandTotal")}:</strong> <span class="technical">Rs. ${value(totalAmount.toLocaleString())}</span></div>

            ${
              showSignatures
                ? `<div class="signatures">
                    <div class="signature">${label("expenses.print.preparedBy")}</div>
                    <div class="signature">${label("expenses.print.approvedBy")}</div>
                    <div class="signature">${label("expenses.print.receivedBy")}</div>
                  </div>`
                : ""
            }
            ${footerText ? `<div class="footer">${footerText}</div>` : ""}
          </div>

          <script>
            window.onload = function () {
              window.focus();
              window.print();
            };
          </script>
        </body>
      </html>
    `, addaId, language === "ur" ? "ur" : "en");
  }

  const manualDateState = getManualVoucherDateState(manualDepartureDate, manualArrivalDate);
  const calculatedManualDays = getInclusiveManualChakkarDays(manualDepartureDate, manualArrivalDate);
  const manualDaysAreDerived = manualDateState === "valid" || editingId === null || hasPersistedManualDates;
  const manualDaysValue = manualDateState === "valid" ? String(calculatedManualDays ?? "") : manualChakkarDays;

  return (
    <div dir={dir} className="ut-module-page mx-auto max-w-7xl space-y-6">
      <header className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <ModulePageHeading icon="expenses" accent="green" title={t("expenses.title")} description={t("expenses.description")} />
      </header>

      <div className="rounded-xl bg-white p-6 shadow-md md:p-8">
        <div className="mb-6 rounded-xl border border-slate-200 bg-slate-50 p-4">
          <p className="mb-3 font-black text-slate-900">{t("expenses.manual.voucherType")}</p>
          <div className="flex flex-wrap gap-3">
            {(["bilty", "manual"] as const).map((mode) => (
              <button
                key={mode}
                type="button"
                disabled={editingId !== null || isSaving}
                onClick={() => changeVoucherMode(mode)}
                aria-pressed={voucherMode === mode}
                className={`rounded-lg border px-5 py-3 font-bold transition ${voucherMode === mode ? "border-blue-700 bg-blue-700 text-white" : "border-slate-300 bg-white text-slate-900 hover:bg-blue-50"} disabled:cursor-not-allowed disabled:opacity-60`}
              >
                {t(mode === "bilty" ? "expenses.manual.biltyBased" : "expenses.manual.manualWithoutBilty")}
              </button>
            ))}
          </div>
          {editingId !== null && (
            <p className="mt-3 text-sm font-semibold text-slate-700">{t("expenses.manual.editModeLocked")}</p>
          )}
        </div>

        {voucherMode === "bilty" ? (
          <>
        <ExpenseForm
          contextKey={`${activeVoucherAddaId ?? ""}:${editingId ?? "new"}:${movementSummary?.id ?? ""}`}
          expenseNo={expenseNo}
          setExpenseNo={setExpenseNo}
          startDate={expenseDate}
          setStartDate={setExpenseDate}
          endDate={endDate}
          setEndDate={setEndDate}
          onSelectMovementGroup={handleMovementGroupSelection}
          description={description}
          setDescription={setDescription}
          selectedLoadings={selectedLoadings}
          movementSummary={movementSummary}
          movementGroups={completedMovementGroups}
          totalDays={totalDays}
        />

        <section className="mt-6 rounded-xl border border-blue-200 bg-blue-50 p-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-lg font-black text-blue-950">{t("expenses.biltyFinance.title")}</h2>
              <p className="mt-1 text-sm font-semibold text-blue-800">
                {t("expenses.biltyFinance.description")}
              </p>
            </div>
            {isBiltySettlementLoading && (
              <span className="rounded-full bg-white px-3 py-1 text-sm font-bold text-blue-800">
                {t("expenses.biltyFinance.loadingPayments")}
              </span>
            )}
          </div>

          {!selectedMovementGroupId ? (
            <div className="mt-4 rounded-lg border border-blue-200 bg-white p-4 font-semibold text-slate-700">
              {t("expenses.biltyFinance.selectMovement")}
            </div>
          ) : selectedBiltySettlements.length === 0 ? (
            <div className="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-4 font-semibold text-amber-900">
              {t("expenses.biltyFinance.legacyLoading")}
            </div>
          ) : (
            <>
              {parchiSettlementLoadFailed && <p role="alert" className="mt-3 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm font-bold text-amber-900">{t("bilty.states.vehicleSettlementUnavailable")}</p>}
              <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7">
                <div className="rounded-lg border border-blue-200 bg-white p-3">
                  <div className="text-xs font-bold uppercase text-slate-500">{t("expenses.biltyFinance.totalVehicleFreight")}</div>
                  <div dir="ltr" className="mt-1 text-lg font-black text-slate-950">
                    Rs. {money(selectedBiltySettlementTotals.vehicleFreight)}
                  </div>
                </div>
                <div className="rounded-lg border border-blue-200 bg-white p-3">
                  <div className="text-xs font-bold uppercase text-slate-500">{t("expenses.biltyFinance.advanceVehicle")}</div>
                  <div dir="ltr" className="mt-1 text-lg font-black text-slate-950">
                    Rs. {money(selectedBiltySettlementTotals.advanceVehicle)}
                  </div>
                </div>
                <div className="rounded-lg border border-blue-200 bg-white p-3">
                  <div className="text-xs font-bold uppercase text-slate-500">{t("expenses.biltyFinance.laterVehiclePaid")}</div>
                  <div dir="ltr" className="mt-1 text-lg font-black text-slate-950">
                    Rs. {money(selectedBiltySettlementTotals.laterVehiclePaid)}
                  </div>
                </div>
                <div className="rounded-lg border border-blue-200 bg-white p-3">
                  <div className="text-xs font-bold uppercase text-slate-500">{t("vehicleLedger.cards.totalReceived")}</div>
                  <div dir="ltr" className="mt-1 text-lg font-black text-emerald-700">
                    {!settlementReadsVerified ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(selectedBiltySettlementTotals.totalVehiclePaid)}`}
                  </div>
                </div>
                <div className="rounded-lg border border-violet-200 bg-white p-3">
                  <div className="text-xs font-bold uppercase text-violet-700">{t("vehicleLedger.cards.parchiVehicleWithheld")}</div>
                  <div dir="ltr" className="mt-1 text-lg font-black text-violet-900">{!settlementReadsVerified ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(selectedBiltySettlementTotals.parchiWithheldCommission)}`}</div>
                </div>
                <div className="rounded-lg border border-blue-200 bg-white p-3">
                  <div className="text-xs font-bold uppercase text-blue-700">{t("vehicleLedger.cards.vehicleEntitlementSettled")}</div>
                  <div dir="ltr" className="mt-1 text-lg font-black text-blue-900">{!settlementReadsVerified ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(selectedBiltySettlementTotals.vehicleEntitlementSettled)}`}</div>
                </div>
                <div className="rounded-lg border border-amber-300 bg-amber-50 p-3">
                  <div className="text-xs font-bold uppercase text-amber-700">{t("expenses.biltyFinance.vehicleBalance")}</div>
                  <div dir="ltr" className="mt-1 text-lg font-black text-amber-900">
                    {selectedBiltySettlementTotals.vehicleBalance === null ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(selectedBiltySettlementTotals.vehicleBalance)}`}
                  </div>
                </div>
              </div>

              <section className="mt-4 rounded-xl border border-emerald-300 bg-emerald-50 p-4" aria-label={t("expenses.biltyFinance.cycleSummary")}>
                <h3 className="font-black text-emerald-950">{t("expenses.biltyFinance.cycleSummary")}</h3>
                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7">
                  {[
                    [t("expenses.biltyFinance.totalVehicleFreight"), selectedBiltySettlementTotals.vehicleFreight],
                    [t("expenses.items.regularTotal"), expenseClassTotals.regular_trip],
                    [t("expenses.items.periodicTotal"), expenseClassTotals.vehicle_periodic],
                    [t("expenses.biltyFinance.totalTripExpenses"), grandTotal],
                    [t("expenses.biltyFinance.vehicleProfitLoss"), vehicleProfitLoss, "profitLoss"],
                    [t("vehicleLedger.cards.totalReceived"), settlementReadsVerified ? selectedBiltySettlementTotals.totalVehiclePaid : null],
                    [t("vehicleLedger.cards.parchiVehicleWithheld"), selectedBiltySettlementTotals.parchiWithheldCommission],
                    [t("vehicleLedger.cards.vehicleEntitlementSettled"), selectedBiltySettlementTotals.vehicleEntitlementSettled],
                    [t("expenses.biltyFinance.vehicleBalance"), selectedBiltySettlementTotals.vehicleBalance],
                  ].map(([label, value, tone]) => (
                    <div key={String(label)} className="rounded-lg border border-emerald-200 bg-white p-3">
                      <div className="text-xs font-bold uppercase text-slate-600">{label}</div>
                      <div dir="ltr" className={`mt-1 text-lg font-black ${tone === "profitLoss" ? (Number(value) > 0 ? "text-emerald-700" : Number(value) < 0 ? "text-red-700" : "text-slate-700") : "text-emerald-900"}`}>
                        {value === null ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(Number(value))}`}
                      </div>
                    </div>
                  ))}
                </div>
                <p className="mt-3 text-sm font-semibold text-emerald-900">{t("expenses.biltyFinance.readOnlyNotice")}</p>
              </section>

              <div className="mt-4 overflow-x-auto rounded-lg border border-blue-200 bg-white">
                <table className="min-w-full border-collapse text-sm">
                  <thead className="bg-blue-700 text-white">
                    <tr>
                      <th className="whitespace-nowrap px-3 py-2 text-start">Bilty No</th>
                      <th className="whitespace-nowrap px-3 py-2 text-start">Loading</th>
                      <th className="whitespace-nowrap px-3 py-2 text-start">Route</th>
                      <th className="whitespace-nowrap px-3 py-2 text-start">Vehicle</th>
                      <th className="whitespace-nowrap px-3 py-2 text-start">Trip</th>
                      <th className="whitespace-nowrap px-3 py-2 text-end">Vehicle Freight</th>
                      <th className="whitespace-nowrap px-3 py-2 text-end">Advance</th>
                      <th className="whitespace-nowrap px-3 py-2 text-end">Later Paid</th>
                      <th className="whitespace-nowrap px-3 py-2 text-end">{t("vehicleLedger.fields.totalVehiclePaid")}</th>
                      <th className="whitespace-nowrap px-3 py-2 text-end">{t("vehicleLedger.fields.parchiWithheldCommission")}</th>
                      <th className="whitespace-nowrap px-3 py-2 text-end">{t("vehicleLedger.fields.vehicleEntitlementSettled")}</th>
                      <th className="whitespace-nowrap px-3 py-2 text-end">{t("vehicleLedger.fields.vehicleBalance")}</th>
                      <th className="whitespace-nowrap px-3 py-2 text-start">{t("vehicleLedger.fields.paymentStatus")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {selectedBiltySettlements.map((settlement) => (
                      <tr key={settlement.biltyId} className="border-b border-slate-200 last:border-0">
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 font-black">{settlement.biltyNo}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2">{settlement.loadingNumbers.join(", ")}</td>
                        <td className="whitespace-nowrap px-3 py-2">{settlement.route}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2">{settlement.vehicleNo}</td>
                        <td className="whitespace-nowrap px-3 py-2 capitalize">{settlement.tripType}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 text-end">Rs. {money(settlement.vehicleFreight)}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 text-end">Rs. {money(settlement.advanceVehicle)}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 text-end">Rs. {money(settlement.laterVehiclePaid)}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 text-end font-bold text-emerald-700">{!settlementReadsVerified ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(settlement.totalVehiclePaid)}`}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 text-end">{!settlementReadsVerified ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(settlement.parchiWithheldCommission)}`}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 text-end font-bold">{!settlementReadsVerified ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(settlement.vehicleEntitlementSettled)}`}</td>
                        <td dir="ltr" className="whitespace-nowrap px-3 py-2 text-end font-black text-amber-800">{settlement.vehicleBalance === null ? t("vehicleLedger.fields.notTracked") : `Rs. ${money(settlement.vehicleBalance)}`}</td>
                        <td className="whitespace-nowrap px-3 py-2">{settlement.paymentStatus === "unverified" ? t("vehicleLedger.fields.notTracked") : t(`vehicleLedger.filters.status.${settlement.paymentStatus}`)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="mt-3 rounded-lg border border-slate-300 bg-white p-3 text-sm font-semibold text-slate-700">
                Voucher expense items ka Grand Total alag hai. Sirf Expense Item save hone par existing Cashbook trigger Cash Out banata hai.
              </div>
            </>
          )}
        </section>

        <ExpenseItems
          expenseItems={expenseItems}
          grandTotal={grandTotal}
          regularTotal={expenseClassTotals.regular_trip}
          periodicTotal={expenseClassTotals.vehicle_periodic}
          petrolPumps={petrolPumps}
          workshopEntries={eligibleWorkshopEntries}
          selectedWorkshopEntryIds={selectedWorkshopEntryIds}
          onWorkshopSelectionChange={handleWorkshopSelectionChange}
          workshopVoucherVehicleId={selectedVehicleId}
          workshopMasters={workshopMasters}
          workshopMode={workshopMode}
          onWorkshopModeChange={handleWorkshopModeChange}
          workshopCreateData={workshopCreateData}
          onWorkshopCreateDataChange={handleWorkshopCreateDataChange}
          oilEntries={eligibleOilEntries}
          selectedOilEntryIds={selectedOilEntryIds}
          onOilSelectionChange={handleOilSelectionChange}
          oilVoucherVehicleId={selectedVehicleId}
          oilVoucherVehicleNo={selectedVehicleNo}
          oilProducts={oilProducts}
          oilShops={oilShops}
          oilDefaultEntryDate={expenseDate}
          onCreateOilEntry={handleCreateOilEntry}
          isCreatingOilEntry={isCreatingOilEntry}
          tyreEntries={eligibleTyreEntries}
          selectedTyreEntryIds={selectedTyreEntryIds}
          onTyreSelectionChange={handleTyreSelectionChange}
          tyreVoucherVehicleId={selectedVehicleId}
          tyreVoucherVehicleNo={selectedVehicleNo}
          tyreShops={tyreShops}
          tyreAssets={tyreAssets}
          tyreProducts={tyreProducts}
          tyrePositions={tyrePositions}
          tyreDefaultEntryDate={expenseDate}
          onCreateTyreEntry={handleCreateTyreEntry}
          isCreatingTyreEntry={isCreatingTyreEntry}
          driverEarnings={eligibleDriverEarnings}
          selectedDriverEarningIds={selectedDriverEarningIds}
          onDriverEarningSelectionChange={handleDriverEarningSelectionChange}
          onAddExpenseItem={handleAddExpenseItem}
          onDeleteExpenseItem={handleDeleteExpenseItem}
          onExpenseItemChange={onExpenseItemChange}
          onReceiptSelected={handleReceiptSelected}
          onReceiptDelete={handleReceiptDelete}
          onPreviewReceipt={handlePreviewReceipt}
          onSave={handleSaveExpenseVoucher}
          isSaving={isSaving || isPreparingMovementLoading}
        />
          </>
        ) : (
          <section className="space-y-6" aria-label={t("expenses.manual.title")}>
            <header>
              <h2 className="text-2xl font-black text-slate-950">{t("expenses.manual.title")}</h2>
              <p className="mt-1 font-semibold text-slate-700">{t("expenses.manual.description")}</p>
            </header>

            <div className="grid gap-4 rounded-xl border border-slate-200 bg-white p-4 md:grid-cols-2 xl:grid-cols-4">

              <VoiceTypingField fieldLabel={t("expenses.form.voucherNo")} mode="identifier"><label className="font-bold text-slate-900">
                {t("expenses.form.voucherNo")}
                <input value={expenseNo} onChange={(event) => setExpenseNo(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" required />
              </label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("expenses.manual.voucherDate")} mode="date"><label className="font-bold text-slate-900">
                {t("expenses.manual.voucherDate")}
                <input type="date" value={expenseDate} onChange={(event) => setExpenseDate(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" required />
              </label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("expenses.manual.departureDate")} mode="date"><label className="font-bold text-slate-900">
                {t("expenses.manual.departureDate")}
                <input type="date" value={manualDepartureDate} onChange={(event) => setManualDepartureDate(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" required={editingId === null || hasPersistedManualDates} aria-invalid={manualDateState === "incomplete" || manualDateState === "invalid" || manualDateState === "reversed"} />
              </label></VoiceTypingField>


              <VoiceTypingField fieldLabel={t("expenses.manual.arrivalDate")} mode="date"><label className="font-bold text-slate-900">
                {t("expenses.manual.arrivalDate")}
                <input type="date" value={manualArrivalDate} onChange={(event) => setManualArrivalDate(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" required={editingId === null || hasPersistedManualDates} aria-invalid={manualDateState === "incomplete" || manualDateState === "invalid" || manualDateState === "reversed"} />
              </label></VoiceTypingField>

              <label className="font-bold text-slate-900">
                {t("common.vehicle")}
                <select value={manualVehicleId} onChange={(event) => {
                  const nextVehicleId = event.target.value;
                  setManualVehicleId(nextVehicleId);
                  const nextAddaId = manualVehicles.find((vehicle) => vehicle.id === nextVehicleId)?.adda_id;
                  if (manualDrivers.find((driver) => driver.id === manualDriverId)?.adda_id !== nextAddaId) setManualDriverId("");
                }} className="mt-1 w-full rounded-lg border border-slate-300 bg-white p-3 font-medium" required>
                  <option value="">{t("expenses.manual.selectVehicle")}</option>
                  {manualVehicles.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.vehicle_no}</option>)}
                </select>
              </label>
              <label className="font-bold text-slate-900">
                {t("expenses.manual.driverOptional")}
                <select value={manualDriverId} onChange={(event) => setManualDriverId(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 bg-white p-3 font-medium" disabled={!manualVehicleId}>
                  <option value="">{t("expenses.manual.noDriver")}</option>
                  {manualDrivers.filter((driver) => driver.adda_id === manualVehicles.find((vehicle) => vehicle.id === manualVehicleId)?.adda_id).map((driver) => <option key={driver.id} value={driver.id}>{driver.name}</option>)}
                </select>
              </label>

              <VoiceTypingField fieldLabel={t("expenses.manual.chakkarDays")} mode="amount"><label className="font-bold text-slate-900">
                {t("expenses.manual.chakkarDays")}
                <input type="number" min="1" step="1" value={manualDaysValue} onChange={(event) => setManualChakkarDays(event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" readOnly={manualDaysAreDerived} required={!manualDaysAreDerived} aria-readonly={manualDaysAreDerived} />
              </label></VoiceTypingField>

              {manualDateState === "incomplete" || manualDateState === "invalid" || manualDateState === "reversed" || (editingId === null && manualDateState === "empty") ? (
                <p className="text-sm font-semibold text-red-700 md:col-span-2 xl:col-span-4" role="alert">
                  {manualDateState === "incomplete" ? t("expenses.manual.validation.datePairRequired")
                    : manualDateState === "invalid" ? t("expenses.manual.validation.datesInvalid")
                      : manualDateState === "reversed" ? t("expenses.manual.validation.arrivalBeforeDeparture")
                        : t("expenses.manual.validation.tripDatesRequired")}
                </p>
              ) : null}
              <label className="font-bold text-slate-900 md:col-span-2 xl:col-span-3">
                {t("common.remarks")}
                <VoiceTypingField fieldLabel={t("common.remarks")} value={description} onValueChange={setDescription} contextKey={`${editingId ?? "new"}:${manualVehicleId}`}>
                  <textarea value={description} onChange={(event) => setDescription(event.target.value)} rows={2} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" />
                </VoiceTypingField>
              </label>
            </div>

            <div className="rounded-xl border border-blue-200 bg-blue-50 p-4">
              <div className="mb-4">
                <h3 className="text-xl font-black text-blue-950">{t("expenses.manual.freightTitle")}</h3>
                <p className="mt-1 text-sm font-semibold text-blue-800">{t("expenses.manual.freightDescription")}</p>
              </div>
              <div className="space-y-3">
                {manualFreightRows.map((row) => (
                  <div key={row.clientId} className="grid gap-3 rounded-lg border border-blue-200 bg-white p-4 md:grid-cols-[minmax(120px,0.7fr)_minmax(160px,1fr)_minmax(220px,2fr)_auto] md:items-end">
                    <div className="font-black text-blue-950">{t(`expenses.manual.freightTypes.${row.freightType}`)}</div>

                    <VoiceTypingField fieldLabel={t("common.amount")} mode="amount"><label className="font-bold text-slate-900">
                      {t("common.amount")}
                      <input type="number" min="0" step="0.01" value={row.amount} onChange={(event) => updateManualFreightRow(row.clientId, "amount", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" />
                    </label></VoiceTypingField>

                    <label className="font-bold text-slate-900">
                      {t("expenses.manual.routeRemarks")}
                      <VoiceTypingField fieldLabel={t("expenses.manual.routeRemarks")} value={row.description} onValueChange={(value) => updateManualFreightRow(row.clientId, "description", value)} contextKey={`${editingId ?? "new"}:${manualVehicleId}:${row.clientId}`}>
                        <input value={row.description} onChange={(event) => updateManualFreightRow(row.clientId, "description", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" />
                      </VoiceTypingField>
                    </label>
                    {row.freightType === "local" && (
                      <button type="button" onClick={() => removeManualLocalRow(row.clientId)} className="rounded-lg border border-red-300 px-4 py-3 font-bold text-red-700 hover:bg-red-50">{t("expenses.manual.removeLocal")}</button>
                    )}
                  </div>
                ))}
              </div>
              <button type="button" onClick={addManualLocalRow} className="mt-4 rounded-lg border border-blue-700 bg-white px-5 py-3 font-bold text-blue-800 hover:bg-blue-100">+ {t("expenses.manual.addLocal")}</button>
              <div className="mt-4 grid gap-3 rounded-lg border border-blue-300 bg-white p-4 sm:grid-cols-2">
                {(["outbound", "local", "return"] as const).map((freightType) => {
                  const total = manualFreightRows.filter((row) => row.freightType === freightType).reduce((sum, row) => sum + Math.max(0, toNumber(row.amount)), 0);
                  return <div key={freightType} className="font-bold text-slate-800">{t(`expenses.manual.freightTypes.${freightType}`)}: <span dir="ltr" className="font-black text-slate-950">Rs. {money(total)}</span></div>;
                })}
                <div className="border-t border-blue-200 pt-3 text-lg font-black text-blue-950 sm:col-span-2">{t("expenses.manual.totalFreight")}: <span dir="ltr">Rs. {money(manualTotalFreight)}</span></div>
              </div>
            </div>

            <section className="rounded-xl border border-emerald-200 bg-emerald-50 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 className="text-xl font-black text-emerald-950">{t("expenses.manual.expensesTitle")}</h3>
                  <p className="mt-1 text-sm font-semibold text-emerald-900">{t("expenses.manual.expensesDescription")}</p>
                </div>
                <button type="button" onClick={() => setExpenseItems((rows) => [...rows, createEmptyExpenseItem("regular_trip")])} className="rounded-lg border border-emerald-700 bg-white px-4 py-2 font-bold text-emerald-800 hover:bg-emerald-100">+ {t("expenses.manual.addExpense")}</button>
              </div>
              <div className="mt-4 space-y-3">
                {expenseItems.map((item) => (
                  <div key={item.rowId} className="grid gap-3 rounded-lg border border-emerald-200 bg-white p-4 md:grid-cols-[minmax(180px,1fr)_minmax(150px,0.8fr)_minmax(180px,1fr)_auto] md:items-end">
                    <label className="font-bold text-slate-900">{t("expenses.items.expenseType")}
                      <select value={item.expenseType} onChange={(event) => setExpenseItems((rows) => rows.map((row) => row.rowId === item.rowId ? { ...row, expenseClass: "regular_trip", expenseType: event.target.value } : row))} className="mt-1 w-full rounded-lg border border-slate-300 bg-white p-3 font-medium">
                        <option value="">{t("common.actions.select")}</option>
                        {MANUAL_EXPENSE_TYPES.map((type) => <option key={type} value={type}>{t(expenseTypeLabelKey(type))}</option>)}
                      </select>
                    </label>

                    <VoiceTypingField fieldLabel={t("common.amount")} mode="amount"><label className="font-bold text-slate-900">{t("common.amount")}
                      <input type="number" min="0" step="0.01" value={item.amount} onChange={(event) => setExpenseItems((rows) => rows.map((row) => row.rowId === item.rowId ? { ...row, amount: event.target.value } : row))} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" />
                    </label></VoiceTypingField>


                    <VoiceTypingField fieldLabel={t("common.remarks")} mode="text"><label className="font-bold text-slate-900">{t("common.remarks")}
                      <input value={item.remarks} onChange={(event) => setExpenseItems((rows) => rows.map((row) => row.rowId === item.rowId ? { ...row, remarks: event.target.value } : row))} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium" />
                    </label></VoiceTypingField>

                    <button type="button" onClick={() => setExpenseItems((rows) => rows.length <= 1 ? [createEmptyExpenseItem("regular_trip")] : rows.filter((row) => row.rowId !== item.rowId))} className="rounded-lg border border-red-300 px-4 py-3 font-bold text-red-700 hover:bg-red-50">{t("expenses.manual.removeExpense")}</button>
                  </div>
                ))}
              </div>
              <div className="mt-4 rounded-xl border border-emerald-300 bg-white p-4">
                <p className="font-bold text-slate-700">{t("expenses.manual.totalExpenses")}: <span dir="ltr" className="font-black text-slate-950">Rs. {money(manualTotalExpenses)}</span></p>
                <p className="mt-2 text-lg font-black text-emerald-950">{t("expenses.manual.netVehicleEarnings")}: <span dir="ltr">Rs. {money(manualTotalFreight - manualTotalExpenses)}</span></p>
              </div>
            </section>

            <section className="space-y-4 rounded-xl border border-blue-200 bg-blue-50 p-4">
              <header>
                <h3 className="text-xl font-black text-blue-950">{t("expenses.manual.sourceExpenses.title")}</h3>
                <p className="mt-1 text-sm font-semibold text-blue-900">{t("expenses.manual.sourceExpenses.description")}</p>
              </header>
              {manualSourceOwnershipLocked && (
                <p className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm font-bold text-amber-950">
                  {t("expenses.manual.sourceExpenses.createdSourceLocked")}
                </p>
              )}
              {editingManualVoucher?.manual_voucher_details?.status === "draft" &&
                (linkedManualWorkshopEntries.length > 0 || linkedManualOilEntries.length > 0 || linkedManualTyreEntries.length > 0) && (
                  <div className="space-y-2 rounded-lg border border-blue-200 bg-white p-3">
                    <p className="font-bold text-slate-900">{t("expenses.manual.sourceExpenses.draftSourcesEditable")}</p>
                    {linkedManualWorkshopEntries.map((entry) => (
                      <div key={`workshop-${entry.id}`} className="flex flex-wrap items-center justify-between gap-3 rounded-md bg-slate-50 p-3">
                        <span className="font-semibold text-slate-800">{t("expenses.manual.sourceExpenses.workshopEntry")}: {entry.vehicleNo} · {entry.billNo || entry.workDate} · Rs. {money(entry.totalCost)}</span>
                        <button type="button" onClick={() => editManualLinkedSource("workshop", entry.id)} className="rounded-lg bg-blue-700 px-4 py-2 font-bold text-white hover:bg-blue-800">{t("common.edit")}</button>
                      </div>
                    ))}
                    {linkedManualOilEntries.map((entry) => (
                      <div key={`oil-${entry.id}`} className="flex flex-wrap items-center justify-between gap-3 rounded-md bg-slate-50 p-3">
                        <span className="font-semibold text-slate-800">{t("expenses.manual.sourceExpenses.oilEntry")}: {entry.productName} · {entry.billNo || entry.entryDate} · Rs. {money(entry.totalAmount)}</span>
                        <button type="button" onClick={() => editManualLinkedSource("oil", entry.id)} className="rounded-lg bg-blue-700 px-4 py-2 font-bold text-white hover:bg-blue-800">{t("common.edit")}</button>
                      </div>
                    ))}
                    {linkedManualTyreEntries.map((entry) => (
                      <div key={`tyre-${entry.id}`} className="flex flex-wrap items-center justify-between gap-3 rounded-md bg-slate-50 p-3">
                        <span className="font-semibold text-slate-800">{t("expenses.manual.sourceExpenses.tyreEntry")}: {entry.vehicleNo} · {entry.billNo || entry.entryDate} · Rs. {money(entry.totalAmount)}</span>
                        <span className="text-sm font-semibold text-slate-600">{t("expenses.manual.sourceExpenses.tyreEditUnavailable")}</span>
                      </div>
                    ))}
                  </div>
                )}
              <fieldset disabled={manualSourceOwnershipLocked} className="min-w-0 space-y-4 disabled:opacity-70">
                <VoucherWorkshopSelector
                  entries={eligibleWorkshopEntries}
                  selectedIds={selectedWorkshopEntryIds}
                  onChange={handleWorkshopSelectionChange}
                  voucherVehicleId={manualVehicleId || null}
                  workshops={workshopMasters}
                  mode={workshopMode}
                  onModeChange={handleWorkshopModeChange}
                  createData={workshopCreateData}
                  onCreateDataChange={handleWorkshopCreateDataChange}
                />
                <VoucherOilSelector
                  entries={eligibleOilEntries}
                  selectedIds={selectedOilEntryIds}
                  onChange={handleOilSelectionChange}
                  voucherVehicleId={manualVehicleId}
                  voucherVehicleNo={manualVehicle?.vehicle_no ?? ""}
                  products={oilProducts.filter((product) => product.addaId === activeVoucherAddaId)}
                  shops={oilShops.filter((shop) => shop.addaId === activeVoucherAddaId)}
                  defaultEntryDate={expenseDate}
                  onCreate={handleCreateOilEntry}
                  isCreating={isCreatingOilEntry}
                  mode={oilMode}
                  onModeChange={handleOilModeChange}
                />
                <VoucherTyreSelector
                  entries={eligibleTyreEntries}
                  selectedIds={selectedTyreEntryIds}
                  onChange={handleTyreSelectionChange}
                  voucherVehicleId={manualVehicleId}
                  voucherVehicleNo={manualVehicle?.vehicle_no ?? ""}
                  shops={tyreShops.filter((shop) => shop.addaId === activeVoucherAddaId)}
                  assets={tyreAssets.filter((asset) => asset.addaId === activeVoucherAddaId)}
                  products={tyreProducts.filter((product) => product.addaId === activeVoucherAddaId)}
                  positions={tyrePositions.filter((position) => position.addaId === activeVoucherAddaId && position.vehicleId === activeVoucherVehicleId)}
                  defaultEntryDate={expenseDate}
                  onCreate={handleCreateTyreEntry}
                  isCreating={isCreatingTyreEntry}
                  mode={tyreMode}
                  onModeChange={handleTyreModeChange}
                />
              </fieldset>
              <section className="rounded-xl border border-amber-200 bg-amber-50 p-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h4 className="text-lg font-black text-amber-950">{t("expenses.manual.sourceExpenses.dieselTitle")}</h4>
                    <p className="mt-1 text-sm font-semibold text-amber-900">{t("expenses.manual.sourceExpenses.dieselDescription")}</p>
                  </div>
                  <button type="button" onClick={addManualDieselRow} className="rounded-lg border border-amber-700 bg-white px-4 py-2 font-bold text-amber-900 hover:bg-amber-100">+ {t("expenses.manual.sourceExpenses.addDiesel")}</button>
                </div>
                {manualDieselRows.length === 0 ? (
                  <p className="mt-3 rounded-lg bg-white p-3 text-sm font-semibold text-slate-700">{t("expenses.manual.sourceExpenses.noDiesel")}</p>
                ) : (
                  <div className="mt-4 space-y-4">
                    {manualDieselRows.map((row) => {
                      const amount = Math.round(toNumber(row.liters) * toNumber(row.rate) * 100) / 100;
                      const paid = Math.max(0, toNumber(row.paidAmount));
                      const remaining = Math.max(0, amount - paid);
                      const paymentLocked = row.dieselEntryId !== null && (paid > 0 || row.paymentRecorded);
                      const paymentStatusKey = paid <= 0 ? "unpaid" : paid >= amount ? "paid" : "partial";
                      return (
                        <div key={row.clientId} className="grid gap-3 rounded-lg border border-amber-200 bg-white p-4 sm:grid-cols-2 xl:grid-cols-4">

                          <VoiceTypingField fieldLabel={t("common.date")} mode="date"><label className="font-bold text-slate-900">{t("common.date")}<input type="date" value={row.entryDate} disabled={paymentLocked} onChange={(event) => updateManualDieselRow(row.clientId, "entryDate", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>

                          <label className="font-bold text-slate-900">{t("common.vehicle")}<input value={manualVehicle?.vehicle_no ?? "—"} readOnly className="mt-1 w-full rounded-lg border border-slate-200 bg-slate-100 p-3 font-medium text-slate-700" /></label>
                          <label className="font-bold text-slate-900">{t("expenses.diesel.petrolPump")}
                            <select value={row.petrolPumpId} disabled={row.dieselEntryId !== null} onChange={(event) => updateManualDieselRow(row.clientId, "petrolPumpId", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 bg-white p-3 font-medium disabled:bg-slate-100">
                              <option value="">{t("common.actions.select")}</option>{petrolPumps.map((pump) => <option key={pump.id} value={pump.id}>{pump.pumpName}</option>)}
                            </select>
                          </label>

                          <VoiceTypingField fieldLabel={t("expenses.diesel.litres")} mode="amount"><label className="font-bold text-slate-900">{t("expenses.diesel.litres")}<input type="number" min="0" step="0.001" value={row.liters} disabled={paymentLocked} onChange={(event) => updateManualDieselRow(row.clientId, "liters", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>


                          <VoiceTypingField fieldLabel={t("expenses.diesel.rate")} mode="amount"><label className="font-bold text-slate-900">{t("expenses.diesel.rate")}<input type="number" min="0" step="0.01" value={row.rate} disabled={paymentLocked} onChange={(event) => updateManualDieselRow(row.clientId, "rate", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>

                          <label className="font-bold text-slate-900">{t("common.total")}<input value={`Rs. ${money(amount)}`} readOnly className="mt-1 w-full rounded-lg border border-slate-200 bg-slate-100 p-3 font-black text-slate-900" /></label>

                          <VoiceTypingField fieldLabel={t("expenses.manual.sourceExpenses.paidAmount")} mode="amount"><label className="font-bold text-slate-900">{t("expenses.manual.sourceExpenses.paidAmount")}<input type="number" min="0" max={amount} step="0.01" value={row.paidAmount} disabled={paymentLocked} onChange={(event) => updateManualDieselRow(row.clientId, "paidAmount", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>

                          <label className="font-bold text-slate-900">{t("expenses.manual.sourceExpenses.paymentMethod")}<select value={row.paymentMethod} disabled={paymentLocked || paid <= 0} onChange={(event) => updateManualDieselRow(row.clientId, "paymentMethod", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 bg-white p-3 font-medium disabled:bg-slate-100"><option value="Cash">{t("petrolPumpPayments.paymentMethods.cash")}</option><option value="Bank">{t("petrolPumpPayments.paymentMethods.bank")}</option><option value="Cheque">{t("petrolPumpPayments.paymentMethods.cheque")}</option><option value="Online Transfer">{t("petrolPumpPayments.paymentMethods.onlineTransfer")}</option></select></label>

                          <VoiceTypingField fieldLabel={t("expenses.manual.sourceExpenses.paymentDate")} mode="date"><label className="font-bold text-slate-900">{t("expenses.manual.sourceExpenses.paymentDate")}<input type="date" value={row.paymentDate} disabled={paymentLocked || paid <= 0} onChange={(event) => updateManualDieselRow(row.clientId, "paymentDate", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>

                          <div className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm"><div className="font-bold text-slate-900">{t("common.remaining")}: Rs. {money(remaining)}</div><div className="mt-1 text-slate-700">{t("expenses.manual.sourceExpenses.paymentStatus")}: {t(`expenses.manual.sourceExpenses.paymentStatuses.${paymentStatusKey}`)}</div></div>

                          <VoiceTypingField fieldLabel={t("expenses.manual.sourceExpenses.paymentReference")} mode="identifier"><label className="font-bold text-slate-900">{t("expenses.manual.sourceExpenses.paymentReference")}<input value={row.paymentReference} disabled={paymentLocked || paid <= 0} onChange={(event) => updateManualDieselRow(row.clientId, "paymentReference", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>


                          <VoiceTypingField fieldLabel={t("expenses.diesel.slipNo")} mode="identifier"><label className="font-bold text-slate-900">{t("expenses.diesel.slipNo")}<input value={row.slipNo} disabled={paymentLocked} onChange={(event) => updateManualDieselRow(row.clientId, "slipNo", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>


                          <VoiceTypingField fieldLabel={t("expenses.manual.sourceExpenses.paymentNotes")} mode="cnic"><label className="font-bold text-slate-900 sm:col-span-2">{t("expenses.manual.sourceExpenses.paymentNotes")}<input value={row.paymentRemarks} disabled={paymentLocked || paid <= 0} onChange={(event) => updateManualDieselRow(row.clientId, "paymentRemarks", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>


                          <VoiceTypingField fieldLabel={t("common.remarks")} mode="text"><label className="font-bold text-slate-900 sm:col-span-2">{t("common.remarks")}<input value={row.remarks} disabled={paymentLocked} onChange={(event) => updateManualDieselRow(row.clientId, "remarks", event.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 p-3 font-medium disabled:bg-slate-100" /></label></VoiceTypingField>

                          {row.dieselEntryId === null
                            ? <button type="button" onClick={() => removeManualDieselRow(row.clientId)} className="rounded-lg border border-red-300 px-4 py-3 font-bold text-red-700 hover:bg-red-50">{t("expenses.manual.removeExpense")}</button>
                            : <p className="self-center text-sm font-semibold text-slate-600">{paymentLocked ? t("expenses.manual.sourceExpenses.dieselPaidSourceLocked") : t("expenses.manual.sourceExpenses.dieselSourceLocked")}</p>}
                        </div>
                      );
                    })}
                  </div>
                )}
              </section>
            </section>

            <div className="flex flex-wrap gap-3">
              <button type="button" onClick={() => void handleSaveExpenseVoucher()} disabled={isSaving || isLoading} className="rounded-lg bg-blue-700 px-6 py-3 font-black text-white hover:bg-blue-800 disabled:cursor-not-allowed disabled:opacity-60">
                {isSaving ? t("common.states.saving") : t("expenses.actions.saveVoucher")}
              </button>
              {editingId !== null && <button type="button" onClick={resetForm} disabled={isSaving} className="rounded-lg border border-slate-300 bg-white px-6 py-3 font-bold text-slate-900 hover:bg-slate-50">{t("common.actions.cancel")}</button>}
            </div>
          </section>
        )}
      </div>

      <ExpenseTable
        expenseVouchers={filteredExpenseVouchers}
        search={search}
        setSearch={(value) => {
          setSearch(value);
          setPage(1);
        }}
        fromDate={fromDateFilter}
        toDate={toDateFilter}
        vehicleFilter={vehicleFilter}
        driverFilter={driverFilter}
        categoryFilter={categoryFilter}
        paymentMethodFilter={paymentMethodFilter}
        vehicleOptions={expenseFilterOptions.vehicles}
        driverOptions={expenseFilterOptions.drivers}
        page={page}
        setPage={setPage}
        onFromDateChange={(value) => {
          setFromDateFilter(value);
          setPage(1);
        }}
        onToDateChange={(value) => {
          setToDateFilter(value);
          setPage(1);
        }}
        onVehicleFilterChange={(value) => {
          setVehicleFilter(value);
          setPage(1);
        }}
        onDriverFilterChange={(value) => {
          setDriverFilter(value);
          setPage(1);
        }}
        onCategoryFilterChange={(value) => {
          setCategoryFilter(value);
          setPage(1);
        }}
        onPaymentMethodFilterChange={(value) => {
          setPaymentMethodFilter(value);
          setPage(1);
        }}
        onResetFilters={resetExpenseFilters}
        viewingExpense={viewingExpense}
        isLoading={isLoading}
        onCloseView={closeVoucherView}
        onView={setViewingExpense}
        onEdit={handleEditExpenseVoucher}
        onFinalize={handleFinalizeExpenseVoucher}
        onCreateAdjustment={handleCreateAdjustment}
        onDelete={handleDeleteExpenseVoucher}
        onPrint={handlePrintExpenseVoucher}
        onPreviewReceipt={handlePreviewReceipt}
        isDeleting={isDeleting}
        finalizingVoucherId={finalizingVoucherId}
      />

      {voucherPrintPresentation && voucherPrintVoucher ? <VoucherTemplatePrint
        key={`${voucherPrintPresentation.addaId}:${voucherPrintPresentation.voucherNo}`}
        presentation={voucherPrintPresentation}
        language={language}
        onClose={() => { setVoucherPrintPresentation(null); setVoucherPrintVoucher(null); }}
        onLegacyPrint={() => { setVoucherPrintPresentation(null); void handleLegacyPrintExpenseVoucher(voucherPrintVoucher); }}
      /> : null}

      {editingManualVoucher?.manual_voucher_details?.status === "draft" &&
        manualWorkshopEditEntry && activeVoucherAddaId && manualVehicleId && (
          <ManualWorkshopEditModal
            key={`manual-workshop-edit-${editingManualVoucher.id}-${manualWorkshopEditEntry.id}`}
            voucherId={editingManualVoucher.id}
            sourceEntryId={manualWorkshopEditEntry.id}
            addaId={activeVoucherAddaId}
            vehicleId={manualVehicleId}
            vehicleNo={manualWorkshopEditEntry.vehicleNo}
            onClose={() => setManualSourceEditTarget(null)}
            onSaved={refreshManualVoucherAfterSourceEdit}
          />
        )}
      {editingManualVoucher?.manual_voucher_details?.status === "draft" &&
        manualOilEditEntry && activeVoucherAddaId && manualVehicleId && (
          <ManualOilEditModal
            key={`manual-oil-edit-${editingManualVoucher.id}-${manualOilEditEntry.id}`}
            voucherId={editingManualVoucher.id}
            entry={manualOilEditEntry}
            addaId={activeVoucherAddaId}
            vehicleId={manualVehicleId}
            products={oilProducts.filter((product) => product.addaId === activeVoucherAddaId)}
            shops={oilShops.filter((shop) => shop.addaId === activeVoucherAddaId)}
            onClose={() => setManualSourceEditTarget(null)}
            onSaved={refreshManualVoucherAfterSourceEdit}
          />
        )}

      <VoucherAdjustmentModal
        open={adjustmentVoucher !== null}
        voucher={
          adjustmentVoucher
            ? {
                id: adjustmentVoucher.id,
                expenseNo: adjustmentVoucher.expense_no,
                expenseDate: adjustmentVoucher.expense_date,
              }
            : null
        }
        onClose={() => setAdjustmentVoucher(null)}
        onChanged={handleAdjustmentChanged}
      />
      {manualAdjustmentVoucher && <ManualVoucherAdjustmentModal
        key={`manual-adjustment-${manualAdjustmentVoucher.id}`}
        open={manualAdjustmentVoucher !== null}
        voucher={{
          id: manualAdjustmentVoucher.id,
          expenseNo: manualAdjustmentVoucher.expense_no,
          vehicleNo: manualAdjustmentVoucher.manual_voucher_details?.vehicle_no ?? "",
          voucherDate: manualAdjustmentVoucher.manual_voucher_details?.voucher_date ?? manualAdjustmentVoucher.expense_date,
          settlement: manualAdjustmentVoucher.manual_voucher_details?.manual_vehicle_chakkar_settlements?.[0] ?? null,
          adjustments: manualAdjustmentVoucher.manual_voucher_adjustments ?? [],
        }}
        onClose={() => setManualAdjustmentVoucher(null)}
        onChanged={handleAdjustmentChanged}
      />}
    </div>
  );
}

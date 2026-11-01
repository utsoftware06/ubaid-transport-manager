import type { BiltyRow, BiltyItemRow } from "@/components/bilty/types";
import type { PrintBranding } from "./types";
import { createDefaultPrintSettings } from "./settings";
import type { PrintDocumentSettingsRow, PrintDocumentSettingsValues } from "./types";

export type BiltyCopyType = "office" | "party" | "driver";
export type BiltyMoney = number | string | null | undefined;

/** Values returned by the existing authoritative get_bilty_financial_summary RPC. */
export type BiltyPrintFinancialSummary = {
  bilty_id: string;
  total_bilty_rs: BiltyMoney;
  advance_received: BiltyMoney;
  later_received: BiltyMoney;
  total_received: BiltyMoney;
  balance_receivable: BiltyMoney;
  payment_status: string | null;
  vehicle_freight: BiltyMoney;
  advance_vehicle: BiltyMoney;
  later_vehicle_paid: BiltyMoney;
  total_vehicle_paid: BiltyMoney;
  vehicle_balance: BiltyMoney;
  actual_vehicle_cash_paid?: BiltyMoney;
  parchi_withheld_commission?: BiltyMoney;
  vehicle_entitlement_settled?: BiltyMoney;
  adda_commission: BiltyMoney;
  broker_brokerage: BiltyMoney;
  xl_weight: BiltyMoney;
  mt_receivable: BiltyMoney;
  mt_payable: BiltyMoney;
  lolo_charges: BiltyMoney;
  other_income: BiltyMoney;
  less_deduction: BiltyMoney;
};

export type BiltyPrintItem = Pick<BiltyItemRow, "goods_name" | "quantity" | "weight" | "unit" | "remarks" | "line_no">;

export type BiltyCommonPresentation = {
  documentType: "bilty";
  isSyntheticSample: boolean;
  copyType: BiltyCopyType;
  addaId: string;
  biltyNo: string;
  bookingDate: string | null;
  loadingDate: string | null;
  departureDate: string | null;
  arrivalDate: string | null;
  tripType: string | null;
  freightType: string | null;
  biltyType: string | null;
  loadingSource: string | null;
  freightReceivableFrom: string | null;
  referenceNo: string | null;
  movementGroupNo: string | null;
  routeFrom: string | null;
  routeTo: string | null;
  partyName: string | null;
  brokerName: string | null;
  senderName: string | null;
  senderPhone: string | null;
  receiverName: string | null;
  receiverPhone: string | null;
  vehicleNo: string | null;
  vehicleType: string | null;
  vehicleOwner: string | null;
  externalOwner: boolean;
  containerDetails: Array<{ label: string; value: string }>;
  items: BiltyPrintItem[];
};

export type BiltyPrintPresentation =
  | (BiltyCommonPresentation & {
      copyType: "office";
      officeFinancials: Array<{ key: string; value: BiltyMoney }>;
    })
  | (BiltyCommonPresentation & {
      copyType: "party";
      partyFinancials: Array<{ key: string; value: BiltyMoney }>;
    })
  | (BiltyCommonPresentation & { copyType: "driver" });

/** Field ownership follows the existing BiltyPrint party/vehicle section mapping. */
export const BILTY_OFFICE_FINANCIAL_FIELD_OWNERSHIP = {
  totalBiltyFreight: "bilty",
  advanceReceived: "bilty",
  laterReceived: "bilty",
  totalReceived: "bilty",
  balanceReceivable: "bilty",
  paymentStatus: "bilty",
  vehicleFreight: "vehicle",
  advanceVehicle: "vehicle",
  laterVehiclePaid: "vehicle",
  totalVehiclePaid: "vehicle",
  vehicleBalance: "vehicle",
  parchiWithheldCommission: "vehicle",
  vehicleEntitlementSettled: "vehicle",
  savedBrokerCommission: "vehicle",
  savedOverweightCharges: "vehicle",
  loloCharges: "vehicle",
  savedDetainCharges: "vehicle",
  addaCommission: "both",
} as const;

export type BiltyOfficeFinancialSection = "bilty" | "vehicle" | "both";

export function filterBiltyOfficeFinancials(
  presentation: BiltyPrintPresentation,
  includeBiltyDetails: boolean,
  includeVehicleDetails: boolean,
): BiltyPrintPresentation {
  if (presentation.copyType !== "office") return presentation;

  return {
    ...presentation,
    officeFinancials: presentation.officeFinancials.filter(({ key }) => {
      const owner = BILTY_OFFICE_FINANCIAL_FIELD_OWNERSHIP[key as keyof typeof BILTY_OFFICE_FINANCIAL_FIELD_OWNERSHIP];
      if (owner === "bilty") return includeBiltyDetails;
      if (owner === "vehicle") return includeVehicleDetails;
      if (owner === "both") return includeBiltyDetails && includeVehicleDetails;
      return false;
    }),
  };
}

const text = (value: unknown): string | null => {
  if (value === null || value === undefined) return null;
  const normalized = String(value).trim();
  return normalized ? normalized : null;
};

function relation<T>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}

const containerFieldLabels: ReadonlyArray<[keyof BiltyRow, string]> = [
  ["container_no", "Container No."], ["container_size", "Container Size"],
  ["container_weight", "Container Weight"], ["container_serial", "Container Serial"],
  ["container_port", "Port"], ["clearing_agent", "Clearing Agent"],
  ["shipping_line", "Shipping Line"], ["container_cargo", "Cargo"],
];

/** Projects only the selected copy's fields before any template receives the data. */
export function createBiltyPrintPresentation(
  bilty: BiltyRow,
  summary: BiltyPrintFinancialSummary | null,
  copyType: BiltyCopyType,
): BiltyPrintPresentation {
  const vehicle = relation(bilty.vehicles);
  const from = relation(bilty.from_location)?.name ?? bilty.from_city;
  const to = relation(bilty.to_location)?.name ?? bilty.to_city;
  const common: BiltyCommonPresentation = {
    documentType: "bilty",
    isSyntheticSample: false,
    copyType,
    addaId: bilty.adda_id,
    biltyNo: bilty.booking_no,
    bookingDate: text(bilty.booking_date),
    loadingDate: text(bilty.loading_date),
    departureDate: text(bilty.departure_date),
    arrivalDate: text(bilty.arrival_date),
    tripType: text(bilty.trip_type),
    freightType: text(bilty.freight_type),
    biltyType: text(bilty.bilty_type),
    loadingSource: text(bilty.loading_source),
    freightReceivableFrom: text(bilty.freight_receivable_from),
    referenceNo: text(bilty.reference_no),
    movementGroupNo: bilty.bilty_group_id && bilty.bilty_group_id !== bilty.id
      ? text(bilty.movement_group?.outbound_bilty_no)
      : null,
    routeFrom: text(from),
    routeTo: text(to),
    partyName: text(relation(bilty.parties)?.name),
    brokerName: text(relation(bilty.brokers)?.broker_name),
    senderName: text(bilty.sender_name),
    senderPhone: text(bilty.sender_phone),
    receiverName: text(bilty.receiver_name),
    receiverPhone: text(bilty.receiver_phone),
    vehicleNo: text(vehicle?.vehicle_no ?? bilty.external_vehicle_no),
    vehicleType: text(vehicle?.vehicle_type ?? bilty.external_vehicle_type),
    vehicleOwner: text(vehicle?.owner_name ?? bilty.external_owner_name),
    externalOwner: bilty.bilty_type === "other_vehicle",
    containerDetails: containerFieldLabels.flatMap(([field, label]) => {
      const value = text(bilty[field]);
      return value === null ? [] : [{ label, value }];
    }),
    items: [...(bilty.bilty_items ?? [])]
      .sort((left, right) => left.line_no - right.line_no)
      .map(({ goods_name, quantity, weight, unit, remarks, line_no }) => ({ goods_name, quantity, weight, unit, remarks, line_no })),
  };

  if (copyType === "driver") return { ...common, copyType: "driver" };
  if (!summary || summary.bilty_id !== bilty.id) {
    throw new Error("The saved Bilty financial summary is unavailable for this copy.");
  }

  if (copyType === "party") {
    return {
      ...common,
      copyType: "party",
      partyFinancials: [
        { key: "freight", value: summary.total_bilty_rs },
        { key: "advance", value: summary.advance_received },
        { key: "laterReceipts", value: summary.later_received },
        { key: "totalReceived", value: summary.total_received },
        { key: "balance", value: summary.balance_receivable },
        { key: "paymentStatus", value: summary.payment_status },
      ],
    };
  }

  return {
    ...common,
    copyType: "office",
    officeFinancials: [
      { key: "totalBiltyFreight", value: summary.total_bilty_rs },
      { key: "advanceReceived", value: summary.advance_received },
      { key: "laterReceived", value: summary.later_received },
      { key: "totalReceived", value: summary.total_received },
      { key: "balanceReceivable", value: summary.balance_receivable },
      { key: "paymentStatus", value: summary.payment_status },
      { key: "vehicleFreight", value: summary.vehicle_freight },
      { key: "advanceVehicle", value: summary.advance_vehicle },
      { key: "laterVehiclePaid", value: summary.later_vehicle_paid },
      { key: "totalVehiclePaid", value: summary.actual_vehicle_cash_paid ?? summary.total_vehicle_paid },
      { key: "parchiWithheldCommission", value: summary.parchi_withheld_commission ?? 0 },
      { key: "vehicleEntitlementSettled", value: summary.vehicle_entitlement_settled ?? summary.total_vehicle_paid },
      { key: "vehicleBalance", value: summary.vehicle_balance },
      { key: "addaCommission", value: summary.adda_commission },
      { key: "brokerBrokerage", value: summary.broker_brokerage },
      { key: "xlWeight", value: summary.xl_weight },
      { key: "mtReceivable", value: summary.mt_receivable },
      { key: "mtPayable", value: summary.mt_payable },
      { key: "loloCharges", value: summary.lolo_charges },
      { key: "otherIncome", value: summary.other_income },
      { key: "lessDeduction", value: summary.less_deduction },
      { key: "partyCommission", value: bilty.party_commission },
      { key: "advanceCommission", value: bilty.advance_commission },
      { key: "advanceBrokerage", value: bilty.advance_brokerage },
      { key: "savedBrokerCommission", value: bilty.broker_commission },
      { key: "savedOverweightCharges", value: bilty.overweight_charges },
      { key: "savedDetainCharges", value: bilty.detain_charges },
      { key: "savedMtReceivable", value: bilty.mt_charges_receivable },
      { key: "savedMtPayable", value: bilty.mt_charges_payable },
      { key: "savedDeductionAdjustment", value: bilty.deduction_adjustment },
    ],
  };
}

/** Clearly synthetic Settings preview data; never sourced from a business record. */
export function createSyntheticBiltyPresentation(copyType: BiltyCopyType = "office"): BiltyPrintPresentation {
  const common: BiltyCommonPresentation = {
    documentType: "bilty", isSyntheticSample: true, copyType,
    addaId: "synthetic-sample", biltyNo: "DEMO / 0001", bookingDate: "01-01-2000",
    loadingDate: "01-01-2000", departureDate: "02-01-2000", arrivalDate: "03-01-2000",
    tripType: "outbound", freightType: "to_pay", biltyType: "self_vehicle", loadingSource: "own_adda", freightReceivableFrom: "existing_counterparty",
    referenceNo: "DEMO-REF", movementGroupNo: "DEMO GROUP", routeFrom: "Karachi",
    routeTo: "Lahore", partyName: "Sample Party", brokerName: "Sample Broker",
    senderName: "Sample Sender", senderPhone: null, receiverName: "Sample Receiver",
    receiverPhone: null, vehicleNo: "DEMO-000", vehicleType: "Goods Vehicle",
    vehicleOwner: "Sample Owner", externalOwner: false, containerDetails: [],
    items: [{ line_no: 1, goods_name: "Sample goods — preview only", quantity: "12", weight: "240", unit: "bags", remarks: "Synthetic preview" }],
  };
  if (copyType === "driver") return { ...common, copyType: "driver" };
  if (copyType === "party") return {
    ...common, copyType: "party", partyFinancials: [
      { key: "freight", value: "120000" }, { key: "advance", value: "30000" },
      { key: "laterReceipts", value: "25000" }, { key: "totalReceived", value: "55000" },
      { key: "balance", value: "65000" }, { key: "paymentStatus", value: "PARTIAL" },
    ],
  };
  return { ...common, copyType: "office", officeFinancials: [
    { key: "totalBiltyFreight", value: "120000" }, { key: "advanceReceived", value: "30000" },
    { key: "laterReceived", value: "25000" }, { key: "totalReceived", value: "55000" },
    { key: "balanceReceivable", value: "65000" }, { key: "paymentStatus", value: "PARTIAL" },
    { key: "vehicleFreight", value: "80000" }, { key: "advanceVehicle", value: "20000" },
    { key: "laterVehiclePaid", value: "10000" }, { key: "totalVehiclePaid", value: "30000" },
    { key: "parchiWithheldCommission", value: "4000" }, { key: "vehicleEntitlementSettled", value: "34000" },
    { key: "vehicleBalance", value: "46000" }, { key: "savedBrokerCommission", value: "5000" },
    { key: "savedOverweightCharges", value: "0" }, { key: "loloCharges", value: "0" },
    { key: "savedDetainCharges", value: "0" }, { key: "addaCommission", value: "40000" },
  ] };
}

/** The row's owning Adda is the only valid settings scope for this document. */
export function resolveBiltyPrintDefaults(
  ownerAddaId: string,
  branding: PrintBranding,
  rows: readonly PrintDocumentSettingsRow[],
): PrintDocumentSettingsValues {
  if (!ownerAddaId || branding.addaId !== ownerAddaId) {
    throw new Error("Bilty branding does not match the document's owning Adda.");
  }
  const saved = rows.find((row) => row.addaId === ownerAddaId && row.documentType === "bilty");
  return saved ?? createDefaultPrintSettings(branding);
}

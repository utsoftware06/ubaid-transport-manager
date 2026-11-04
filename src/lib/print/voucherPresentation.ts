import type { PrintDocumentSettingsValues, PrintLanguage, PrintTemplateId } from "./types";

export type VoucherPrintKind = "standard" | "manual";
export type VoucherMoney = number | string | null | undefined;
export type VoucherExpenseClass = "regular_trip" | "vehicle_periodic";

export type VoucherPrintExpense = {
  id: string | number;
  expenseClass: VoucherExpenseClass;
  expenseType: string;
  amount: VoucherMoney;
  paymentMethod: string | null;
  remarks: string | null;
  sourceDetails: string[];
};

export type VoucherPrintLeg = {
  loadingNo: string | null;
  biltyNo: string | null;
  tripType: string | null;
  route: string | null;
  vehicleNo: string | null;
  vehicleOwner: string | null;
  driverName: string | null;
  loadingDate: string | null;
  departureDate: string | null;
  arrivalDate: string | null;
};

export type VoucherPrintFreightLine = {
  id: string | number;
  tripType: "outbound" | "local" | "return";
  amount: VoucherMoney;
  description: string | null;
};

export type VoucherPrintSummary = {
  vehicleFreight: VoucherMoney;
  vehicleAdvance: VoucherMoney;
  vehicleLaterPaid: VoucherMoney;
  vehicleTotalPaid: VoucherMoney;
  vehicleParchiWithheld: VoucherMoney;
  vehicleEntitlementSettled: VoucherMoney;
  vehicleBalance: VoucherMoney;
  regularExpenseTotal: VoucherMoney;
  periodicExpenseTotal: VoucherMoney;
  totalTripExpenses: VoucherMoney;
  vehicleProfitLoss: VoucherMoney;
  manualTotalFreight: VoucherMoney;
  manualTotalExpenses: VoucherMoney;
  manualNetVehicleEarnings: VoucherMoney;
};

export type VoucherPrintSourceReference = {
  category: string;
  detail: string;
};

export type VoucherPrintPresentation = {
  documentType: "voucher";
  kind: VoucherPrintKind;
  isSyntheticSample: boolean;
  addaId: string;
  voucherNo: string;
  voucherDate: string | null;
  departureDate: string | null;
  arrivalDate: string | null;
  startDate: string | null;
  endDate: string | null;
  totalDays: number | null;
  movementGroupNo: string | null;
  loadingNumbers: string[];
  legs: VoucherPrintLeg[];
  vehicleNo: string | null;
  vehicleOwner: string | null;
  driverName: string | null;
  chakkarDays: number | null;
  status: "draft" | "finalized" | null;
  remarks: string | null;
  freightItems: VoucherPrintFreightLine[];
  expenseItems: VoucherPrintExpense[];
  unassignedSourceReferences: VoucherPrintSourceReference[];
  summary: VoucherPrintSummary;
};

export type VoucherPrintPresentationInput = Omit<VoucherPrintPresentation, "documentType" | "isSyntheticSample">;

export function createVoucherPrintPresentation(
  input: VoucherPrintPresentationInput,
  isSyntheticSample = false,
): VoucherPrintPresentation {
  return {
    documentType: "voucher",
    isSyntheticSample,
    ...input,
    loadingNumbers: [...input.loadingNumbers],
    legs: [...input.legs],
    freightItems: [...input.freightItems],
    expenseItems: input.expenseItems.map((item) => ({ ...item, sourceDetails: [...item.sourceDetails] })),
    unassignedSourceReferences: [...input.unassignedSourceReferences],
    summary: { ...input.summary },
  };
}

/** Resolve only from the saved voucher's tenant relationships, never the active UI selector. */
export function resolveVoucherPrintOwnerAddaId(input: {
  kind: VoucherPrintKind;
  manualAddaId?: string | null;
  movementGroupId?: string | null;
  movementGroupAddaId?: string | null;
  linkedBookingAddaIds: Array<string | null | undefined>;
}): string | null {
  if (input.kind === "manual") return input.manualAddaId?.trim() || null;

  const groupAddaId = input.movementGroupAddaId?.trim() || null;
  const linkedAddas = input.linkedBookingAddaIds.map((value) => value?.trim() || null);
  const resolvedAddas = new Set(linkedAddas.filter((value): value is string => Boolean(value)));
  const hasUnresolvedBooking = linkedAddas.some((value) => value === null);

  if (groupAddaId) {
    if ([...resolvedAddas].some((addaId) => addaId !== groupAddaId)) return null;
    return groupAddaId;
  }

  if (input.movementGroupId || hasUnresolvedBooking || resolvedAddas.size !== 1) return null;
  return [...resolvedAddas][0] ?? null;
}

export function createSyntheticVoucherPresentation(
  addaId: string,
  kind: VoucherPrintKind,
): VoucherPrintPresentation {
  const base: VoucherPrintPresentationInput = {
    kind,
    addaId,
    voucherNo: kind === "manual" ? "SAMPLE-MAN-0001" : "SAMPLE-VCH-0001",
    voucherDate: "2026-01-01",
    departureDate: kind === "manual" ? "2026-01-01" : null,
    arrivalDate: kind === "manual" ? "2026-01-01" : null,
    startDate: kind === "standard" ? "2026-01-01" : null,
    endDate: kind === "standard" ? "2026-01-02" : null,
    totalDays: kind === "standard" ? 1 : null,
    movementGroupNo: kind === "standard" ? "SAMPLE-BILTY-0001" : null,
    loadingNumbers: kind === "standard" ? ["SAMPLE-LOAD-0001"] : [],
    legs: kind === "standard" ? [{
      loadingNo: "SAMPLE-LOAD-0001", biltyNo: "SAMPLE-BILTY-0001", tripType: "outbound",
      route: "Karachi → Lahore", vehicleNo: "SAMPLE-TRK-001", vehicleOwner: "Sample Owner",
      driverName: "Sample Driver", loadingDate: "2026-01-01", departureDate: null, arrivalDate: null,
    }] : [],
    vehicleNo: kind === "manual" ? "SAMPLE-TRK-001" : null,
    vehicleOwner: kind === "manual" ? "Sample Owner" : null,
    driverName: kind === "manual" ? "Sample Driver" : null,
    chakkarDays: kind === "manual" ? 1 : null,
    status: kind === "manual" ? "finalized" : null,
    remarks: "Synthetic sample only — not a business record.",
    freightItems: kind === "manual" ? [
      { id: "sample-freight-1", tripType: "outbound", amount: 0, description: "Sample route / description" },
      { id: "sample-freight-2", tripType: "local", amount: 0, description: "Sample local leg" },
    ] : [],
    expenseItems: [
      { id: "sample-expense-1", expenseClass: "regular_trip", expenseType: "Fuel", amount: 0, paymentMethod: "Cash", remarks: "Synthetic sample", sourceDetails: [] },
      { id: "sample-expense-2", expenseClass: "regular_trip", expenseType: "Toll Tax", amount: 0, paymentMethod: "Cash", remarks: null, sourceDetails: [] },
    ],
    unassignedSourceReferences: [],
    summary: {
      vehicleFreight: 0, vehicleAdvance: 0, vehicleLaterPaid: 0, vehicleTotalPaid: 0,
      vehicleParchiWithheld: 0, vehicleEntitlementSettled: 0, vehicleBalance: 0,
      regularExpenseTotal: 0, periodicExpenseTotal: 0, totalTripExpenses: 0, vehicleProfitLoss: 0,
      manualTotalFreight: 0, manualTotalExpenses: 0, manualNetVehicleEarnings: 0,
    },
  };

  return createVoucherPrintPresentation(base, true);
}

export function getVoucherPrintDirection(language: PrintLanguage): "ltr" | "rtl" {
  return language === "ur" ? "rtl" : "ltr";
}

export function createVoucherTemplateDefaults<T extends PrintDocumentSettingsValues>(
  settings: T,
  templateId: PrintTemplateId = settings.templateId,
): T {
  const format = templateId === "modern_professional"
    ? { paperSize: "A4" as const, orientation: "landscape" as const }
    : templateId === "compact_pad" || templateId === "traditional_pad"
      ? { paperSize: "A5" as const, orientation: "portrait" as const }
      : { paperSize: "A4" as const, orientation: "portrait" as const };
  return { ...settings, ...format, templateId } as T;
}

import type {
  BiltyDraftInput,
  BiltyFormPatch,
  BiltyFormState,
  BiltyItemDraft,
} from "./types";

export function createEmptyBiltyItem(clientId: string): BiltyItemDraft {
  return {
    clientId,
    goodsName: "",
    quantity: "",
    weight: "",
    unit: "",
    remarks: "",
  };
}

export function createEmptyBiltyForm(
  addaId: string,
  clientId: string
): BiltyFormState {
  return {
    addaId,
    biltyNo: "",
    biltyDate: "",
    loadingDate: "",
    groupId: "",
    tripType: "outbound",
    loadingSource: "",
    loadingSourceOtherAddaId: "",
    freightReceivableFrom: "",
    freightReceivableOtherAddaId: "",
    otherAddaDueDate: "",
    freightType: "to_pay",
    biltyType: "self_vehicle",
    partyId: "",
    brokerId: "",
    referenceNo: "",
    departureDate: "",
    arrivalDate: "",
    vehicleId: "",
    externalVehicleNo: "",
    externalVehicleType: "",
    externalOwnerName: "",
    containerNo: "",
    containerSize: "",
    containerWeight: "",
    containerSerial: "",
    containerPort: "",
    clearingAgent: "",
    shippingLine: "",
    containerCargo: "",
    fromLocationId: "",
    toLocationId: "",
    fromLocationSearch: "",
    toLocationSearch: "",
    senderName: "",
    senderPhone: "",
    receiverName: "",
    receiverPhone: "",
    freight: "",
    advanceVehicle: "0",
    advanceBilty: "0",
    advanceCommission: "0",
    overweightCharges: "0",
    detainCharges: "0",
    mtChargesReceivable: "0",
    mtChargesPayable: "0",
    partyCommission: "0",
    brokerCommission: "0",
    advanceBrokerage: "0",
    otherIncome: "0",
    deductionAdjustment: "0",
    accountType: "",
    items: [createEmptyBiltyItem(clientId)],
  };
}

export function replaceBiltyItems(
  state: BiltyFormState,
  items: BiltyItemDraft[]
): BiltyFormState {
  return { ...state, items: items.map((item) => ({ ...item })) };
}

export function applyBiltyPatch(
  state: BiltyFormState,
  patch: BiltyFormPatch
): BiltyFormState {
  const next = { ...state, ...patch };
  return patch.items ? replaceBiltyItems(next, patch.items) : next;
}

export function setBiltyField<Key extends keyof BiltyFormState>(
  state: BiltyFormState,
  key: Key,
  value: BiltyFormState[Key]
): BiltyFormState {
  return { ...state, [key]: value };
}

export function normalizeBiltyDraft(input: BiltyDraftInput): BiltyFormPatch {
  const normalized: BiltyFormPatch = { ...input };
  if (typeof input.biltyNo === "string") normalized.biltyNo = input.biltyNo.trim();
  if (typeof input.referenceNo === "string") normalized.referenceNo = input.referenceNo.trim();
  if (typeof input.externalVehicleNo === "string") {
    normalized.externalVehicleNo = input.externalVehicleNo.trim();
  }
  if (input.items) {
    normalized.items = input.items.map((item) => ({
      ...item,
      goodsName: item.goodsName.trim(),
      unit: item.unit.trim(),
      remarks: item.remarks.trim(),
    }));
  }
  return normalized;
}

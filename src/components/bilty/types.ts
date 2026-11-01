export type BiltyTripType = "outbound" | "return" | "local";
export type BiltyFreightType = "paid" | "advance" | "to_pay";
export type BiltyVehicleType = "self_vehicle" | "other_vehicle";
export type BiltyMovementStatus = "open" | "completed" | "voucher_created";
export type BiltyAccountType = "party_account" | "mt_account" | "other_account";
export type BiltyLoadingSource = "own_adda" | "other_adda";
export type BiltyFreightReceivableFrom = "existing_counterparty" | "other_adda";

export type BiltyItemDraft = {
  clientId: string;
  goodsName: string;
  quantity: string;
  weight: string;
  unit: string;
  remarks: string;
};

/**
 * Canonical editable Bilty state. Future voice/OCR adapters can populate this
 * shape without coupling themselves to individual React input setters.
 */
export type BiltyFormState = {
  addaId: string;
  biltyNo: string;
  biltyDate: string;
  loadingDate: string;
  groupId: string;
  tripType: BiltyTripType;
  loadingSource: BiltyLoadingSource | "";
  loadingSourceOtherAddaId: string;
  freightReceivableFrom: BiltyFreightReceivableFrom | "";
  freightReceivableOtherAddaId: string;
  otherAddaDueDate: string;
  freightType: BiltyFreightType;
  biltyType: BiltyVehicleType;
  partyId: string;
  brokerId: string;
  referenceNo: string;
  departureDate: string;
  arrivalDate: string;
  vehicleId: string;
  externalVehicleNo: string;
  externalVehicleType: string;
  externalOwnerName: string;
  containerNo: string;
  containerSize: string;
  containerWeight: string;
  containerSerial: string;
  containerPort: string;
  clearingAgent: string;
  shippingLine: string;
  containerCargo: string;
  fromLocationId: string;
  toLocationId: string;
  fromLocationSearch: string;
  toLocationSearch: string;
  senderName: string;
  senderPhone: string;
  receiverName: string;
  receiverPhone: string;
  freight: string;
  advanceVehicle: string;
  advanceBilty: string;
  advanceCommission: string;
  overweightCharges: string;
  detainCharges: string;
  mtChargesReceivable: string;
  mtChargesPayable: string;
  partyCommission: string;
  brokerCommission: string;
  advanceBrokerage: string;
  otherIncome: string;
  deductionAdjustment: string;
  accountType: BiltyAccountType | "";
  items: BiltyItemDraft[];
};

export type BiltyFormPatch = Partial<Omit<BiltyFormState, "items">> & {
  items?: BiltyItemDraft[];
};

/** Normalized adapter boundary for future voice and OCR providers. */
export type BiltyDraftInput = BiltyFormPatch;

export type BiltyItemRow = {
  id: string;
  goods_name: string;
  quantity: number | string;
  weight: number | string | null;
  unit: string;
  remarks: string | null;
  line_no: number;
};

export type BiltyLoadingCreationResult = {
  loading_id: number | string;
  loading_created: boolean;
  margin_status:
    | "recognized"
    | "zero_margin"
    | "other_adda_no_own_margin"
    | "existing_loading_no_recognition"
    | "reversed";
  margin_amount: number | string;
  loading_source: BiltyLoadingSource;
};

export type BiltyRelation = { id?: string; name?: string | null };

export type BiltyRow = {
  id: string;
  adda_id: string;
  party_id: string | null;
  broker_id: string | null;
  vehicle_id: string | null;
  booking_no: string;
  booking_date: string;
  loading_date: string | null;
  bilty_group_id: string;
  trip_type: BiltyTripType | null;
  loading_source?: BiltyLoadingSource | null;
  loading_source_other_adda_id?: string | null;
  freight_receivable_from?: BiltyFreightReceivableFrom | null;
  freight_receivable_other_adda_id?: string | null;
  freight_type: BiltyFreightType | null;
  bilty_type: BiltyVehicleType | null;
  reference_no: string | null;
  departure_date: string | null;
  arrival_date: string | null;
  sender_name: string | null;
  sender_phone: string | null;
  receiver_name: string | null;
  receiver_phone: string | null;
  from_city: string | null;
  to_city: string | null;
  from_location_id: string | null;
  to_location_id: string | null;
  external_vehicle_no: string | null;
  external_vehicle_type: string | null;
  external_owner_name: string | null;
  container_no: string | null;
  container_size: string | null;
  container_weight: number | string | null;
  container_serial: string | null;
  container_port: string | null;
  clearing_agent: string | null;
  shipping_line: string | null;
  container_cargo: string | null;
  freight: number | string | null;
  vehicle_freight?: number | string | null;
  advance_vehicle: number | string | null;
  advance_bilty: number | string | null;
  advance_commission: number | string | null;
  lolo_charges?: number | string | null;
  overweight_charges: number | string | null;
  detain_charges?: number | string | null;
  mt_charges_receivable: number | string | null;
  mt_charges_payable: number | string | null;
  party_commission: number | string | null;
  broker_commission: number | string | null;
  advance_brokerage: number | string | null;
  other_income: number | string | null;
  deduction_adjustment: number | string | null;
  account_type: BiltyAccountType | null;
  status: string | null;
  created_at: string | null;
  parties?: { name: string | null } | { name: string | null }[] | null;
  brokers?: { broker_name: string | null } | { broker_name: string | null }[] | null;
  vehicles?:
    | { vehicle_no: string | null; vehicle_type: string | null; owner_name: string | null }
    | { vehicle_no: string | null; vehicle_type: string | null; owner_name: string | null }[]
    | null;
  from_location?: { id: string; name: string; location_type: string } | { id: string; name: string; location_type: string }[] | null;
  to_location?: { id: string; name: string; location_type: string } | { id: string; name: string; location_type: string }[] | null;
  bilty_items?: BiltyItemRow[] | null;
  movement_group?: BiltyMovementGroup | null;
};

export type BiltyOption = { id: string; name: string; adda_id?: string };
export type VehicleOption = {
  id: string;
  adda_id: string;
  vehicle_no: string;
  vehicle_type: string | null;
  owner_name: string | null;
};
export type LocationOption = {
  id: string;
  parent_id: string | null;
  location_type: "province" | "division" | "district" | "tehsil" | "city" | "town" | "village" | "locality";
  name: string;
  hierarchy_label: string;
};

export type BiltyMovementGroup = {
  id: string;
  adda_id: string;
  outbound_bilty_id: string;
  outbound_bilty_no: string;
  outbound_vehicle_id: string;
  outbound_vehicle_no: string;
  status: BiltyMovementStatus;
};

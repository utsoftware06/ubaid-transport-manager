import type { VehicleFilterType, VehicleReport, VehicleTrip } from "@/components/vehicleLedger/VehicleLedger";

export type OwnerFilterType = VehicleFilterType;

export type OwnerLedgerFilterValues = {
  ownerName: string;
  vehicleId: string;
  filterType: VehicleFilterType;
  fromDate: string;
  toDate: string;
  search: string;
  paymentStatus: string;
  biltyVoucherNo: string;
};

export type OwnerReport = {
  ownerName: string;
  totalVehicles: number;
  totalTrips: number;
  totalVehicleFreight: number;
  totalReceived: number;
  totalParchiVehicleWithheld: number;
  totalVehicleEntitlementSettled: number;
  totalOutstanding: number;
  totalExpenses: number;
  netVehicleEarnings: number;
  trips: VehicleTrip[];
  vehicles: VehicleReport[];
};

export type OwnerLedgerSummary = {
  totalOwners: number;
  totalVehicles: number;
  totalTrips: number;
  totalVehicleFreight: number;
  totalReceived: number;
  totalParchiVehicleWithheld: number;
  totalVehicleEntitlementSettled: number;
  totalOutstanding: number;
  totalExpenses: number;
  netVehicleEarnings: number;
};

export type OwnerVehicleOption = { id: string; vehicleNo: string };

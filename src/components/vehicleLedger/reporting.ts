import type { VehicleReport, VehicleTrip } from "./VehicleLedger";

export type VehicleTripTotals = {
  totalTrips: number;
  totalVehicleFreight: number;
  totalReceived: number;
  totalParchiVehicleWithheld: number;
  totalVehicleEntitlementSettled: number;
  totalOutstanding: number;
  totalExpense: number;
  netVehicleEarnings: number;
};

export type VehicleTripDateFilter = {
  filterType: "all" | "today" | "week" | "month" | "sixMonths" | "year" | "custom";
  fromDate: string;
  toDate: string;
};

export function formatAmount(value: number) {
  return `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 0 })}`;
}

export function summarizeVehicleTrips(trips: VehicleTrip[]): VehicleTripTotals {
  return trips.reduce<VehicleTripTotals>((totals, trip) => ({
    totalTrips: totals.totalTrips + 1,
    totalVehicleFreight: totals.totalVehicleFreight + trip.income,
    totalReceived: totals.totalReceived + (trip.totalVehiclePaid ?? 0),
    totalParchiVehicleWithheld: totals.totalParchiVehicleWithheld + trip.parchiVehicleWithheld,
    totalVehicleEntitlementSettled: totals.totalVehicleEntitlementSettled + (trip.totalVehicleEntitlementSettled ?? 0),
    totalOutstanding: totals.totalOutstanding + (trip.vehicleBalance ?? 0),
    totalExpense: totals.totalExpense + trip.totalExpense,
    netVehicleEarnings: totals.netVehicleEarnings + trip.profit,
  }), {
    totalTrips: 0,
    totalVehicleFreight: 0,
    totalReceived: 0,
    totalParchiVehicleWithheld: 0,
    totalVehicleEntitlementSettled: 0,
    totalOutstanding: 0,
    totalExpense: 0,
    netVehicleEarnings: 0,
  });
}

export function buildVehicleReports(trips: VehicleTrip[]): VehicleReport[] {
  const tripsByVehicle = new Map<string, VehicleTrip[]>();
  for (const trip of trips) {
    const vehicleId = trip.vehicleId || trip.vehicleNo;
    const vehicleTrips = tripsByVehicle.get(vehicleId) ?? [];
    vehicleTrips.push(trip);
    tripsByVehicle.set(vehicleId, vehicleTrips);
  }

  return Array.from(tripsByVehicle, ([vehicleId, vehicleTrips]) => {
    const totals = summarizeVehicleTrips(vehicleTrips);
    const firstTrip = vehicleTrips[0];
    const addaIds = Array.from(new Set(vehicleTrips.map((trip) => trip.addaId).filter((id): id is string => Boolean(id))));
    return {
      vehicleId,
      addaId: addaIds.length === 1 ? addaIds[0] : null,
      vehicleNo: firstTrip.vehicleNo,
      ownerName: firstTrip.ownerName,
      ...totals,
      trips: vehicleTrips,
    };
  }).sort((left, right) => left.vehicleNo.localeCompare(right.vehicleNo));
}

export function isVehicleTripDateInRange(dateValue: string, filters: VehicleTripDateFilter): boolean {
  if (!dateValue || filters.filterType === "all") return true;
  const tripDate = new Date(`${dateValue.slice(0, 10)}T00:00:00`);
  if (!Number.isFinite(tripDate.getTime())) return false;
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let fromDate: Date | null = null;
  let toDate: Date | null = today;
  if (filters.filterType === "today") fromDate = new Date(today);
  if (filters.filterType === "week") {
    fromDate = new Date(today);
    fromDate.setDate(today.getDate() - 6);
  }
  if (filters.filterType === "month") fromDate = new Date(today.getFullYear(), today.getMonth(), 1);
  if (filters.filterType === "sixMonths") {
    fromDate = new Date(today);
    fromDate.setMonth(today.getMonth() - 6);
  }
  if (filters.filterType === "year") fromDate = new Date(today.getFullYear(), 0, 1);
  if (filters.filterType === "custom") {
    fromDate = filters.fromDate ? new Date(`${filters.fromDate}T00:00:00`) : null;
    toDate = filters.toDate ? new Date(`${filters.toDate}T00:00:00`) : null;
  }
  return !(fromDate && tripDate < fromDate) && !(toDate && tripDate > toDate);
}

export function matchesBiltyVoucherNumber(trip: VehicleTrip, searchValue: string): boolean {
  const search = searchValue.trim().toLowerCase();
  if (!search) return true;
  if (trip.biltyNumbers.some((number) => number.trim().toLowerCase() === search)) return true;
  return trip.sourceType === "manual" && trip.voucherNo.trim().toLowerCase() === search;
}

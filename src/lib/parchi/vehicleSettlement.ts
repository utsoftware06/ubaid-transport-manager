import { supabase } from "@/lib/supabase/client";

export type ParchiVehicleSettlementTotal = {
  bookingId: string;
  principalCredit: number;
  actualCashAmount: number;
  withheldCommission: number;
};

export type BookingTenantRef = { id: string; adda_id: string | null };

export type VehicleSettlementDisplay = {
  actualCashPaid: number;
  parchiWithheldCommission: number;
  entitlementSettled: number;
  outstanding: number;
  status: "Unpaid" | "Partial" | "Paid";
};

export async function getBiltyVehicleCashPayments(bookingIds: string[]): Promise<Map<string, number>> {
  const totals = new Map<string, number>();
  const uniqueIds = Array.from(new Set(bookingIds.filter(Boolean)));
  for (let offset = 0; offset < uniqueIds.length; offset += 100) {
    const batch = uniqueIds.slice(offset, offset + 100);
    for (let pageOffset = 0; ; pageOffset += 1000) {
      const { data, error } = await supabase
        .from("bilty_payments")
        .select("bilty_id,amount")
        .in("bilty_id", batch)
        .eq("payment_side", "vehicle")
        .order("bilty_id")
        .order("id")
        .range(pageOffset, pageOffset + 999);
      if (error) throw error;
      const rows = data ?? [];
      for (const row of rows) {
        if (!row.bilty_id) continue;
        const amount = finiteMoney(row.amount);
        totals.set(row.bilty_id, (totals.get(row.bilty_id) ?? 0) + amount);
      }
      if (rows.length < 1000) break;
    }
  }
  return totals;
}

function finiteMoney(value: unknown): number {
  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(amount) || amount < 0) {
    throw new Error("PARCHI_VEHICLE_SETTLEMENT_TOTALS_INVALID");
  }
  return amount;
}

function cents(value: number): number {
  return Math.round(value * 100);
}

/**
 * Fetches net, unreversed linked Parchi settlement totals for one authorized Adda.
 * principalCredit = actualCashAmount + withheldCommission. Since actual cash is
 * already present in bilty_payments, callers add only withheldCommission.
 */
export async function getParchiVehicleSettlementTotals(
  addaId: string,
  bookingIds: string[],
): Promise<Map<string, ParchiVehicleSettlementTotal>> {
  const result = new Map<string, ParchiVehicleSettlementTotal>();
  const uniqueIds = Array.from(new Set(bookingIds.filter(Boolean)));
  for (let offset = 0; offset < uniqueIds.length; offset += 1000) {
    const { data, error } = await supabase.rpc("get_parchi_vehicle_settlement_totals", {
      p_adda_id: addaId,
      p_booking_ids: uniqueIds.slice(offset, offset + 1000),
    });
    if (error) throw error;
    for (const value of (data ?? []) as Array<Record<string, unknown>>) {
      const bookingId = String(value.booking_id ?? "");
      if (!bookingId || result.has(bookingId)) {
        throw new Error("PARCHI_VEHICLE_SETTLEMENT_TOTALS_DUPLICATE_BOOKING");
      }
      const total: ParchiVehicleSettlementTotal = {
        bookingId,
        principalCredit: finiteMoney(value.principal_credit),
        actualCashAmount: finiteMoney(value.actual_cash_amount),
        withheldCommission: finiteMoney(value.withheld_commission),
      };
      if (cents(total.principalCredit) !== cents(total.actualCashAmount + total.withheldCommission)) {
        throw new Error("PARCHI_VEHICLE_SETTLEMENT_TOTALS_COMPONENTS_MISMATCH");
      }
      result.set(bookingId, total);
    }
  }
  return result;
}

/** Groups cross-Adda rows by their saved tenant key; it never infers ownership. */
export async function getParchiVehicleSettlementTotalsForBookings(
  bookings: BookingTenantRef[],
): Promise<Map<string, ParchiVehicleSettlementTotal>> {
  const byAdda = new Map<string, string[]>();
  for (const booking of bookings) {
    if (!booking.adda_id) continue;
    const ids = byAdda.get(booking.adda_id) ?? [];
    ids.push(booking.id);
    byAdda.set(booking.adda_id, ids);
  }
  const grouped = await Promise.all(Array.from(byAdda, async ([addaId, ids]) =>
    getParchiVehicleSettlementTotals(addaId, ids)));
  const result = new Map<string, ParchiVehicleSettlementTotal>();
  for (const totals of grouped) {
    for (const [bookingId, total] of totals) {
      if (result.has(bookingId)) throw new Error("PARCHI_VEHICLE_SETTLEMENT_TOTALS_DUPLICATE_BOOKING");
      result.set(bookingId, total);
    }
  }
  return result;
}

export function buildVehicleSettlementDisplay(
  adjustedEntitlement: number | null,
  actualCashPaid: number | null,
  parchiWithheldCommission: number,
): VehicleSettlementDisplay | null {
  if (adjustedEntitlement === null || actualCashPaid === null
    || !Number.isFinite(adjustedEntitlement) || !Number.isFinite(actualCashPaid)
    || !Number.isFinite(parchiWithheldCommission) || actualCashPaid < 0 || parchiWithheldCommission < 0) {
    return null;
  }
  const entitlementSettled = actualCashPaid + parchiWithheldCommission;
  const outstanding = Math.max(adjustedEntitlement - entitlementSettled, 0);
  return {
    actualCashPaid,
    parchiWithheldCommission,
    entitlementSettled,
    outstanding,
    status: entitlementSettled <= 0 ? "Unpaid" : outstanding <= 0 ? "Paid" : "Partial",
  };
}

export function applyParchiWithholdingToFinancialSummary<T extends {
  total_vehicle_paid: number | string | null | undefined;
  vehicle_balance: number | string | null | undefined;
}>(summary: T, parchiWithheldCommission: number): T & {
  actual_vehicle_cash_paid: number | null;
  parchi_withheld_commission: number;
  vehicle_entitlement_settled: number | null;
  vehicle_balance: number | null;
} {
  const cashValue = summary.total_vehicle_paid;
  const balanceValue = summary.vehicle_balance;
  const actualVehicleCashPaid = cashValue == null ? null : finiteMoney(cashValue);
  const parsedBalance = balanceValue == null ? null : Number(balanceValue);
  if (parsedBalance !== null && !Number.isFinite(parsedBalance)) {
    throw new Error("BILTY_VEHICLE_BALANCE_INVALID");
  }
  const baseBalance = parsedBalance;
  return {
    ...summary,
    actual_vehicle_cash_paid: actualVehicleCashPaid,
    parchi_withheld_commission: parchiWithheldCommission,
    vehicle_entitlement_settled: actualVehicleCashPaid === null
      ? null
      : actualVehicleCashPaid + parchiWithheldCommission,
    vehicle_balance: baseBalance === null ? null : Math.max(baseBalance - parchiWithheldCommission, 0),
  };
}

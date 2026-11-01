"use client";

import { useEffect, useMemo, useState } from "react";
import type { VehicleTrip, VehicleTripFreightLeg } from "@/components/vehicleLedger/VehicleLedger";
import { matchesBiltyVoucherNumber } from "@/components/vehicleLedger/reporting";
import { supabase } from "@/lib/supabase/client";
import { useLanguage } from "@/contexts/LanguageContext";
import ModulePageHeading from "@/components/shared/ModulePageHeading";
import { escapeHtml } from "@/lib/print/escapeHtml";
import { PRINT_ADDA_NAME_TOKEN, writeAddaBrandedPrintDocument } from "@/lib/print/legacyPrintBranding";
import LedgerStatementPrintButton, { singleResolvedAddaId } from "@/components/print/LedgerStatementPrint";
import { driverLedgerPrintPresentation } from "./driverLedgerPrintPresentation";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Driver = { id: string; name: string; adda_id: string | null; opening_balance: number | string | null };
type DriverEarning = {
  id: string; driver_id: string; vehicle_id: string; salary_date: string; earning_type: string;
  gross_expense: number | string; net_payable: number | string; advance_adjusted: number | string;
  paid_amount: number | string; remaining_amount: number | string; payment_status: string;
  remarks: string | null; created_at: string;
};
type DriverPayment = {
  id: number; driver_id: string; payment_date: string; amount: number | string; advance_used: number | string;
  payment_now: number | string; remaining_payable: number | string; remaining_advance: number | string;
  settlement_status: string; payment_method: string | null; reference_no: string | null; remarks: string | null;
  created_at: string;
};
type VoucherEarningLink = { driver_earning_id: string; voucher_id: number | string };
type DriverAssignment = { id: string; name: string };
type KharchaStatus = "attributed" | "unallocated" | "none";
type ActivityRow = {
  id: string;
  trip: VehicleTrip;
  driverId: string | null;
  driverName: string;
  legLabel: string;
  salaryEarnings: number;
  kharcha: number;
  kharchaStatus: KharchaStatus;
};
type AccountEvent = {
  id: string;
  driverId: string;
  date: string;
  kind: "earning" | "payment";
  detail: string;
  earning: number;
  payment: number;
  advance: number;
};
type FilterValues = { driverId: string; vehicleId: string; fromDate: string; toDate: string; biltyVoucherNo: string; search: string };
export type DriverAccountBalance = { payable: number; recoverable: number; balance: number };

const NOT_RECORDED = "__not_recorded__";
const money = (value: number) => `Rs. ${Number(value || 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
const numeric = (value: number | string | null | undefined) => {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
};
const inDateRange = (date: string, filters: FilterValues) =>
  (!filters.fromDate || date >= filters.fromDate) && (!filters.toDate || date <= filters.toDate);

function tripDriverAssignments(trip: VehicleTrip): DriverAssignment[] {
  if (trip.sourceType === "manual") {
    return trip.driverId ? [{ id: trip.driverId, name: trip.driverName }] : [];
  }
  const assignments = (trip.freightLegs ?? []).flatMap((leg) => {
    if (leg.loadingDrivers.length) {
      return leg.loadingDrivers.flatMap((loading) => loading.driverId
        ? [{ id: loading.driverId, name: loading.driverName }]
        : []);
    }
    return leg.driverId ? [{ id: leg.driverId, name: leg.driverName }] : [];
  });
  return Array.from(new Map(assignments.map((assignment) => [assignment.id, assignment])).values());
}

function legDriverIds(leg: VehicleTripFreightLeg): string[] {
  const ids = leg.loadingDrivers.map((assignment) => assignment.driverId).filter((id): id is string => Boolean(id));
  return Array.from(new Set(ids.length ? ids : leg.driverId ? [leg.driverId] : []));
}

function legHasUnrecordedDriver(leg: VehicleTripFreightLeg): boolean {
  return leg.loadingDrivers.length === 0
    ? !leg.driverId
    : leg.loadingDrivers.some((assignment) => !assignment.driverId);
}

function tripHasUnrecordedDriver(trip: VehicleTrip): boolean {
  return trip.sourceType === "manual"
    ? !trip.driverId
    : (trip.freightLegs ?? []).some(legHasUnrecordedDriver);
}

function driverKharcha(trip: VehicleTrip) {
  const amount = trip.expenseItems
    .filter((item) => item.category.trim().toLocaleLowerCase().includes("driver kharcha"))
    .reduce((sum, item) => sum + item.amount, 0);
  const driverIds = tripDriverAssignments(trip).map((driver) => driver.id);
  const uniqueDriverIds = Array.from(new Set(driverIds));
  return {
    amount,
    driverId: uniqueDriverIds.length === 1 ? uniqueDriverIds[0] : null,
    status: amount <= 0 ? "none" as const : uniqueDriverIds.length === 1 ? "attributed" as const : "unallocated" as const,
  };
}

async function fetchAll<T>(
  name: string,
  build: (from: number, to: number) => PromiseLike<{ data: unknown[] | null; error: { code?: string; message?: string; details?: string; hint?: string } | null }>,
): Promise<T[]> {
  const output: T[] = [];
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    const result = await build(from, from + pageSize - 1);
    if (result.error) {
      console.error("[DriverLedger] query failed", { query: name, ...result.error });
      throw new Error(`${name}: ${result.error.message || result.error.code || "query failed"}`);
    }
    const page = (result.data ?? []) as T[];
    output.push(...page);
    if (page.length < pageSize) return output;
  }
}

export default function DriverLedgerView({ trips, isLoading }: { trips: VehicleTrip[]; isLoading: boolean }) {
  const { t, dir, language } = useLanguage();
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [earnings, setEarnings] = useState<DriverEarning[]>([]);
  const [payments, setPayments] = useState<DriverPayment[]>([]);
  const [voucherEarningLinks, setVoucherEarningLinks] = useState<VoucherEarningLink[]>([]);
  const [accountLoading, setAccountLoading] = useState(true);
  const [accountError, setAccountError] = useState("");
  const [filters, setFilters] = useState<FilterValues>({ driverId: "", vehicleId: "", fromDate: "", toDate: "", biltyVoucherNo: "", search: "" });
  const [selectedActivity, setSelectedActivity] = useState<ActivityRow | null>(null);

  useEffect(() => {
    let active = true;
    const load = async () => {
      setAccountLoading(true);
      setAccountError("");
      try {
        const [driverRows, earningRows, paymentRows, linkRows] = await Promise.all([
          fetchAll<Driver>("drivers (Driver Account opening balances)", (from, to) => supabase.from("drivers")
            .select("id, name, adda_id, opening_balance").order("name").order("id").range(from, to)),
          fetchAll<DriverEarning>("driver_earnings", (from, to) => supabase.from("driver_earnings")
            .select("id, driver_id, vehicle_id, salary_date, earning_type, gross_expense, net_payable, advance_adjusted, paid_amount, remaining_amount, payment_status, remarks, created_at")
            .order("salary_date", { ascending: false }).order("id", { ascending: false }).range(from, to)),
          fetchAll<DriverPayment>("driver_payments", (from, to) => supabase.from("driver_payments")
            .select("id, driver_id, payment_date, amount, advance_used, payment_now, remaining_payable, remaining_advance, settlement_status, payment_method, reference_no, remarks, created_at")
            .order("payment_date", { ascending: false }).order("id", { ascending: false }).range(from, to)),
          fetchAll<VoucherEarningLink>("voucher_driver_earnings", (from, to) => supabase.from("voucher_driver_earnings")
            .select("driver_earning_id, voucher_id").order("driver_earning_id").range(from, to)),
        ]);
        if (!active) return;
        setDrivers(driverRows);
        setEarnings(earningRows);
        setPayments(paymentRows);
        setVoucherEarningLinks(linkRows);
      } catch (error) {
        if (!active) return;
        setAccountError(error instanceof Error ? error.message : t("driverLedger.messages.loadError"));
      } finally {
        if (active) setAccountLoading(false);
      }
    };
    void load();
    return () => { active = false; };
  }, [t]);

  const driversById = useMemo(() => new Map(drivers.map((driver) => [driver.id, driver])), [drivers]);
  const earningsById = useMemo(() => new Map(earnings.map((earning) => [earning.id, earning])), [earnings]);
  const vehicleOptions = useMemo(() => Array.from(new Map(trips.map((trip) => [trip.vehicleId, { id: trip.vehicleId, name: trip.vehicleNo }])).values())
    .sort((left, right) => left.name.localeCompare(right.name)), [trips]);

  const filteredTrips = useMemo(() => trips.filter((trip) => {
    if (!inDateRange(trip.date, filters)) return false;
    if (filters.vehicleId && trip.vehicleId !== filters.vehicleId) return false;
    if (filters.biltyVoucherNo && !matchesBiltyVoucherNumber(trip, filters.biltyVoucherNo)) return false;
    const assignments = tripDriverAssignments(trip);
    if (filters.driverId === NOT_RECORDED && !tripHasUnrecordedDriver(trip)) return false;
    if (filters.driverId && filters.driverId !== NOT_RECORDED && !assignments.some((driver) => driver.id === filters.driverId)) return false;
    const search = filters.search.trim().toLocaleLowerCase();
    if (!search) return true;
    const legText = (trip.freightLegs ?? []).flatMap((leg) => [leg.biltyNo, leg.side, leg.route, leg.driverName, leg.vehicleNo]).join(" ");
    return [trip.voucherNo, trip.biltyNo, trip.date, trip.vehicleNo, trip.route, trip.tripType, trip.driverName, legText]
      .join(" ").toLocaleLowerCase().includes(search);
  }), [filters, trips]);

  const activityRows = useMemo<ActivityRow[]>(() => filteredTrips.flatMap((trip) => {
    const assignments = tripDriverAssignments(trip);
    const kharcha = driverKharcha(trip);
    const rowDrivers = filters.driverId === NOT_RECORDED
      ? [{ id: NOT_RECORDED, name: t("driverLedger.notRecorded") }]
      : filters.driverId
        ? assignments.filter((driver) => driver.id === filters.driverId)
        : assignments.length
          ? [...assignments, ...(tripHasUnrecordedDriver(trip) ? [{ id: NOT_RECORDED, name: t("driverLedger.notRecorded") }] : [])]
          : [{ id: NOT_RECORDED, name: t("driverLedger.notRecorded") }];
    return rowDrivers.map((driver) => {
      const assignedLegs = (trip.freightLegs ?? []).filter((leg) => legDriverIds(leg).includes(driver.id));
      const unrecordedLegs = (trip.freightLegs ?? []).filter(legHasUnrecordedDriver);
      const legLabel = driver.id === NOT_RECORDED && unrecordedLegs.length
        ? unrecordedLegs.map((leg) => `${leg.side} · ${leg.biltyNo}`).join(", ")
        : trip.sourceType === "manual"
        ? t("driverLedger.manualChakkar")
        : assignedLegs.length
          ? assignedLegs.map((leg) => `${leg.side} · ${leg.biltyNo}`).join(", ")
          : trip.tripType;
      const voucherIdSet = new Set(trip.voucherIds.map(String));
      const earningIds = new Set(voucherEarningLinks
        .filter((link) => voucherIdSet.has(String(link.voucher_id)))
        .map((link) => link.driver_earning_id));
      const linkedEarnings = Array.from(earningIds)
        .map((id) => earningsById.get(id))
        .filter((earning): earning is DriverEarning => Boolean(earning && earning.driver_id === driver.id));
      return {
        id: `${trip.id}:${driver.id}`,
        trip,
        driverId: driver.id === NOT_RECORDED ? null : driver.id,
        driverName: driver.id === NOT_RECORDED ? driver.name : driversById.get(driver.id)?.name || driver.name,
        legLabel,
        salaryEarnings: linkedEarnings.reduce((sum, earning) => sum + numeric(earning.gross_expense), 0),
        kharcha: kharcha.status === "attributed" && kharcha.driverId === driver.id ? kharcha.amount : 0,
        kharchaStatus: kharcha.status,
      };
    });
  }), [driversById, earningsById, filteredTrips, filters.driverId, t, voucherEarningLinks]);

  const visibleTripIds = useMemo(() => new Set(activityRows.map((row) => row.trip.id)), [activityRows]);
  const visibleTrips = useMemo(() => filteredTrips.filter((trip) => visibleTripIds.has(trip.id)), [filteredTrips, visibleTripIds]);
  const accountDriverIds = useMemo(() => filters.driverId && filters.driverId !== NOT_RECORDED
    ? new Set([filters.driverId])
    : filters.driverId === NOT_RECORDED ? new Set<string>() : new Set(drivers.map((driver) => driver.id)), [drivers, filters.driverId]);

  const accountBalances = useMemo(() => {
    const balances = new Map<string, DriverAccountBalance>();
    for (const driver of drivers) {
      const driverEarnings = earnings.filter((earning) => earning.driver_id === driver.id);
      const driverPayments = payments.filter((payment) => payment.driver_id === driver.id);
      const lastPayment = [...driverPayments].sort((left, right) =>
        left.payment_date.localeCompare(right.payment_date)
        || left.created_at.localeCompare(right.created_at)
        || left.id - right.id
      ).at(-1);
      const opening = numeric(driver.opening_balance);
      const payable = lastPayment
        ? numeric(lastPayment.remaining_payable)
        : Math.max(opening, 0) + driverEarnings.reduce((sum, earning) => sum + numeric(earning.remaining_amount), 0);
      const recoverable = lastPayment
        ? numeric(lastPayment.remaining_advance)
        : Math.max(-opening, 0) + driverEarnings.reduce((sum, earning) => sum + Math.max(-numeric(earning.net_payable), 0), 0);
      balances.set(driver.id, { payable, recoverable, balance: payable - recoverable });
    }
    return balances;
  }, [drivers, earnings, payments]);

  const selectedAccountDrivers = useMemo(() => drivers.filter((driver) => accountDriverIds.has(driver.id)), [accountDriverIds, drivers]);
  const printAddaId = visibleTrips.length
    ? singleResolvedAddaId(visibleTrips.map((trip) => trip.addaId))
    : singleResolvedAddaId(selectedAccountDrivers.map((driver) => driver.adda_id));
  const filteredAccountEarnings = useMemo(() => earnings.filter((earning) => accountDriverIds.has(earning.driver_id)
    && inDateRange(earning.salary_date, filters)
    && (!filters.vehicleId || earning.vehicle_id === filters.vehicleId)), [accountDriverIds, earnings, filters]);
  const filteredAccountPayments = useMemo(() => payments.filter((payment) => accountDriverIds.has(payment.driver_id)
    && inDateRange(payment.payment_date, filters)), [accountDriverIds, filters, payments]);

  const summary = useMemo(() => {
    const uniqueTripIds = new Set(visibleTrips.map((trip) => trip.id));
    const selectedDriverId = filters.driverId && filters.driverId !== NOT_RECORDED ? filters.driverId : null;
    const legCount = visibleTrips.reduce((sum, trip) => {
      if (trip.sourceType === "manual") {
        if (!selectedDriverId && filters.driverId !== NOT_RECORDED) return sum + 1;
        return sum + (trip.driverId === selectedDriverId || (filters.driverId === NOT_RECORDED && !trip.driverId) ? 1 : 0);
      }
      if (!selectedDriverId && filters.driverId !== NOT_RECORDED) return sum + (trip.freightLegs?.length ?? 0);
        return sum + (trip.freightLegs ?? []).filter((leg) => {
        const ids = legDriverIds(leg);
          return filters.driverId === NOT_RECORDED ? legHasUnrecordedDriver(leg) : ids.includes(selectedDriverId || "");
      }).length;
    }, 0);
    const kharchaTotal = visibleTrips.reduce((sum, trip) => {
      const kharcha = driverKharcha(trip);
      return kharcha.status === "attributed" && (!selectedDriverId || kharcha.driverId === selectedDriverId)
        && filters.driverId !== NOT_RECORDED ? sum + kharcha.amount : sum;
    }, 0);
    return {
      totalDrivers: filters.driverId && filters.driverId !== NOT_RECORDED
        ? 1
        : filters.driverId === NOT_RECORDED ? 0 : new Set(visibleTrips.flatMap((trip) => tripDriverAssignments(trip).map((driver) => driver.id))).size,
      totalChakkars: uniqueTripIds.size,
      totalLegs: legCount,
      driverKharcha: kharchaTotal,
      salaryEarnings: filteredAccountEarnings.reduce((sum, earning) => sum + numeric(earning.gross_expense), 0),
      driverPayments: filteredAccountPayments.reduce((sum, payment) => sum + numeric(payment.payment_now), 0),
      driverAccountBalance: selectedAccountDrivers.reduce((sum, driver) => sum + (accountBalances.get(driver.id)?.balance ?? 0), 0),
    };
  }, [accountBalances, filteredAccountEarnings, filteredAccountPayments, filters.driverId, selectedAccountDrivers, visibleTrips]);

  const accountEvents = useMemo<AccountEvent[]>(() => {
    const earningRows = filteredAccountEarnings.map((earning) => {
      const voucherId = voucherEarningLinks.find((link) => link.driver_earning_id === earning.id)?.voucher_id;
      const voucherTrip = voucherId === undefined ? null : trips.find((trip) => trip.voucherIds.some((id) => String(id) === String(voucherId)));
      return {
        id: `earning:${earning.id}`, driverId: earning.driver_id, date: earning.salary_date, kind: "earning" as const,
        detail: `${earning.earning_type}${voucherTrip ? ` · ${voucherTrip.voucherNo}` : ""}${earning.remarks ? ` · ${earning.remarks}` : ""}`,
        earning: numeric(earning.gross_expense), payment: 0, advance: numeric(earning.advance_adjusted),
      };
    });
    const paymentRows = filteredAccountPayments.map((payment) => ({
      id: `payment:${payment.id}`, driverId: payment.driver_id, date: payment.payment_date, kind: "payment" as const,
      detail: [payment.payment_method, payment.reference_no, payment.remarks].filter(Boolean).join(" · ") || "—",
      earning: 0, payment: numeric(payment.payment_now), advance: numeric(payment.advance_used),
    }));
    return [...earningRows, ...paymentRows].sort((left, right) => right.date.localeCompare(left.date) || left.id.localeCompare(right.id));
  }, [filteredAccountEarnings, filteredAccountPayments, trips, voucherEarningLinks]);

  const printDriverIds = useMemo(() => new Set(selectedAccountDrivers
    .filter((driver) => Boolean(printAddaId) && driver.adda_id === printAddaId)
    .map((driver) => driver.id)), [printAddaId, selectedAccountDrivers]);
  const printAccountDrivers = selectedAccountDrivers.filter((driver) => printDriverIds.has(driver.id));
  const printAccountEarnings = filteredAccountEarnings.filter((earning) => printDriverIds.has(earning.driver_id));
  const printAccountPayments = filteredAccountPayments.filter((payment) => printDriverIds.has(payment.driver_id));
  const printActivityRows = activityRows.filter((row) => row.trip.addaId === printAddaId);
  const printAccountEvents = accountEvents.filter((event) => printDriverIds.has(event.driverId));
  const printSummary = {
    ...summary,
    salaryEarnings: printAccountEarnings.reduce((sum, earning) => sum + numeric(earning.gross_expense), 0),
    driverPayments: printAccountPayments.reduce((sum, payment) => sum + numeric(payment.payment_now), 0),
    driverAccountBalance: printAccountDrivers.reduce((sum, driver) => sum + (accountBalances.get(driver.id)?.balance ?? 0), 0),
  };

  const print = () => {
    const popup = window.open("", "_blank", "width=1200,height=850");
    if (!popup) { window.alert(t("reports.messages.allowPopups")); return; }
    const activityHtml = printActivityRows.map((row) => `<tr><td>${escapeHtml(row.trip.date)}</td><td>${escapeHtml(row.trip.sourceType === "manual" ? row.trip.voucherNo : row.trip.biltyNo)}</td><td>${escapeHtml(row.trip.vehicleNo)}</td><td>${escapeHtml(row.legLabel)}</td><td>${escapeHtml(row.trip.route)}</td><td>${escapeHtml(row.driverName)}</td><td>${escapeHtml(row.kharchaStatus === "attributed" ? t("driverLedger.kharcha.attributed") : row.kharchaStatus === "unallocated" ? t("driverLedger.kharcha.unallocated") : t("driverLedger.kharcha.none"))}${row.kharcha ? ` · ${escapeHtml(money(row.kharcha))}` : ""}</td><td>${escapeHtml(money(row.salaryEarnings))}</td></tr>`).join("");
    const accountHtml = printAccountEvents.map((event) => `<tr><td>${escapeHtml(event.date)}</td><td>${escapeHtml(driversById.get(event.driverId)?.name || t("driverLedger.notRecorded"))}</td><td>${escapeHtml(event.kind === "earning" ? t("driverLedger.account.earning") : t("driverLedger.account.payment"))}</td><td>${escapeHtml(event.detail)}</td><td>${escapeHtml(money(event.earning))}</td><td>${escapeHtml(money(event.payment))}</td><td>${escapeHtml(money(event.advance))}</td></tr>`).join("");
    const accountSummaryHtml = printAccountDrivers.map((driver) => {
      const balance = accountBalances.get(driver.id) ?? { payable: 0, recoverable: 0, balance: 0 };
      const driverEarnings = printAccountEarnings.filter((earning) => earning.driver_id === driver.id);
      const driverPayments = printAccountPayments.filter((payment) => payment.driver_id === driver.id);
      return `<tr><td>${escapeHtml(driver.name)}</td><td>${escapeHtml(money(numeric(driver.opening_balance)))}</td><td>${escapeHtml(money(driverEarnings.reduce((sum, earning) => sum + numeric(earning.gross_expense), 0)))}</td><td>${escapeHtml(money(driverPayments.reduce((sum, payment) => sum + numeric(payment.payment_now), 0)))}</td><td>${escapeHtml(money(balance.payable))}</td><td>${escapeHtml(money(balance.recoverable))}</td><td>${escapeHtml(money(balance.balance))}</td></tr>`;
    }).join("");
    void writeAddaBrandedPrintDocument(popup, `<!doctype html><html lang="${escapeHtml(language)}" dir="${escapeHtml(dir)}"><head><meta charset="utf-8"><title>${escapeHtml(t("driverLedger.title"))}</title><style>@page{size:landscape;margin:10mm}body{font-family:Arial,sans-serif;color:#0f172a}h1,h2{margin:0 0 12px}h2{margin-top:22px}table{width:100%;border-collapse:collapse;font-size:11px}th,td{border:1px solid #cbd5e1;padding:6px;text-align:start}th{background:#eff6ff}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}.card{border:1px solid #cbd5e1;padding:10px}.technical{direction:ltr;unicode-bidi:isolate}</style></head><body><h1>${PRINT_ADDA_NAME_TOKEN} · ${escapeHtml(t("driverLedger.title"))}</h1><div>${escapeHtml(t("driverLedger.summary.totalDrivers"))}: ${printSummary.totalDrivers} · ${escapeHtml(t("driverLedger.summary.totalChakkars"))}: ${printSummary.totalChakkars} · ${escapeHtml(t("driverLedger.summary.totalTripLegs"))}: ${printSummary.totalLegs}</div><div class="cards"><div class="card">${escapeHtml(t("driverLedger.summary.driverKharcha"))}<br><b>${escapeHtml(money(printSummary.driverKharcha))}</b></div><div class="card">${escapeHtml(t("driverLedger.summary.salaryEarnings"))}<br><b>${escapeHtml(money(printSummary.salaryEarnings))}</b></div><div class="card">${escapeHtml(t("driverLedger.summary.driverPayments"))}<br><b>${escapeHtml(money(printSummary.driverPayments))}</b></div><div class="card">${escapeHtml(t("driverLedger.summary.driverAccountBalance"))}<br><b>${escapeHtml(money(printSummary.driverAccountBalance))}</b></div></div><h2>${escapeHtml(t("driverLedger.activity.title"))}</h2><table><thead><tr>${["date","chakkar","vehicle","tripLeg","route","driver","driverKharcha","salaryEarnings"].map((key) => `<th>${escapeHtml(t(`driverLedger.table.${key}`))}</th>`).join("")}</tr></thead><tbody>${activityHtml || `<tr><td colspan="8">${escapeHtml(t("driverLedger.table.empty"))}</td></tr>`}</tbody></table><h2>${escapeHtml(t("driverLedger.account.title"))}</h2><table><thead><tr>${["driver","opening","salaryEarnings","driverPayments","payable","recoverable","balance"].map((key) => `<th>${escapeHtml(t(`driverLedger.account.${key}`))}</th>`).join("")}</tr></thead><tbody>${accountSummaryHtml || `<tr><td colspan="7">${escapeHtml(t("driverLedger.account.noAccountForUnrecorded"))}</td></tr>`}</tbody></table><h2>${escapeHtml(t("driverLedger.account.history"))}</h2><table><thead><tr>${["date","driver","type","eventDescription","salaryEarnings","driverPayments","advanceAdjustment"].map((key) => `<th>${escapeHtml(t(`driverLedger.account.${key}`))}</th>`).join("")}</tr></thead><tbody>${accountHtml || `<tr><td colspan="7">${escapeHtml(t("driverLedger.account.empty"))}</td></tr>`}</tbody></table><script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}</script></body></html>`, printAddaId, language === "ur" ? "ur" : "en");
  };

  const printPresentation = (printLanguage: "en" | "ur") => driverLedgerPrintPresentation({
    summary: printSummary,
    activities: printActivityRows,
    accounts: printAccountDrivers.map((driver) => {
      const balance = accountBalances.get(driver.id) ?? { payable: 0, recoverable: 0, balance: 0 };
      const driverEarnings = printAccountEarnings.filter((earning) => earning.driver_id === driver.id);
      const driverPayments = printAccountPayments.filter((payment) => payment.driver_id === driver.id);
      return {
        driverName: driver.name,
        opening: numeric(driver.opening_balance),
        earnings: driverEarnings.reduce((sum, earning) => sum + numeric(earning.gross_expense), 0),
        payments: driverPayments.reduce((sum, payment) => sum + numeric(payment.payment_now), 0),
        balance,
      };
    }),
    events: printAccountEvents.map((event) => ({ ...event, driverName: driversById.get(event.driverId)?.name || t("driverLedger.notRecorded") })),
    fromDate: filters.fromDate,
    toDate: filters.toDate,
  }, printLanguage);

  return <section dir={dir} className="ut-module-page space-y-6">
    <div className="rounded-xl bg-white p-6 shadow-md"><ModulePageHeading icon="ledger" accent="blue" title={t("driverLedger.title")} description={t("driverLedger.description")}/>
      <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        <label className="text-sm font-bold">{t("common.driver")}<select className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2" value={filters.driverId} onChange={(event) => setFilters((value) => ({ ...value, driverId: event.target.value }))}><option value="">{t("driverLedger.filters.allDrivers")}</option>{drivers.map((driver) => <option key={driver.id} value={driver.id}>{driver.name}</option>)}<option value={NOT_RECORDED}>{t("driverLedger.notRecorded")}</option></select></label>
        <label className="text-sm font-bold">{t("common.vehicle")}<select className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2" value={filters.vehicleId} onChange={(event) => setFilters((value) => ({ ...value, vehicleId: event.target.value }))}><option value="">{t("vehicleLedger.filters.allVehicles")}</option>{vehicleOptions.map((vehicle) => <option key={vehicle.id} value={vehicle.id}>{vehicle.name}</option>)}</select></label>

        <VoiceTypingField fieldLabel={t("common.fromDate")} mode="date"><label className="text-sm font-bold">{t("common.fromDate")}<input type="date" className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2" value={filters.fromDate} onChange={(event) => setFilters((value) => ({ ...value, fromDate: event.target.value }))}/></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("common.toDate")} mode="date"><label className="text-sm font-bold">{t("common.toDate")}<input type="date" className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2" value={filters.toDate} onChange={(event) => setFilters((value) => ({ ...value, toDate: event.target.value }))}/></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("driverLedger.filters.biltyVoucherPlaceholder")} mode="text"><label className="text-sm font-bold">{t("driverLedger.filters.biltyVoucherNo")}<input className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2" placeholder={t("driverLedger.filters.biltyVoucherPlaceholder")} value={filters.biltyVoucherNo} onChange={(event) => setFilters((value) => ({ ...value, biltyVoucherNo: event.target.value }))}/></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("driverLedger.filters.searchPlaceholder")} mode="text"><label className="text-sm font-bold">{t("common.actions.search")}<input className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2" placeholder={t("driverLedger.filters.searchPlaceholder")} value={filters.search} onChange={(event) => setFilters((value) => ({ ...value, search: event.target.value }))}/></label></VoiceTypingField>

      </div>
      <div className="mt-3 flex justify-end"><button type="button" onClick={() => setFilters({ driverId: "", vehicleId: "", fromDate: "", toDate: "", biltyVoucherNo: "", search: "" })} className="rounded-lg bg-slate-700 px-4 py-2 text-sm font-bold text-white">{t("common.actions.reset")}</button></div>
    </div>

    {accountError && <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-semibold text-red-800">{t("driverLedger.messages.loadError")} {accountError}</div>}
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7">
      <SummaryCard label={t("driverLedger.summary.totalDrivers")} value={String(summary.totalDrivers)}/>
      <SummaryCard label={t("driverLedger.summary.totalChakkars")} value={String(summary.totalChakkars)}/>
      <SummaryCard label={t("driverLedger.summary.totalTripLegs")} value={String(summary.totalLegs)}/>
      <SummaryCard label={t("driverLedger.summary.driverKharcha")} value={money(summary.driverKharcha)}/>
      <SummaryCard label={t("driverLedger.summary.salaryEarnings")} value={money(summary.salaryEarnings)}/>
      <SummaryCard label={t("driverLedger.summary.driverPayments")} value={money(summary.driverPayments)}/>
      <SummaryCard label={t("driverLedger.summary.driverAccountBalance")} value={money(summary.driverAccountBalance)}/>
    </div>

    <section className="rounded-xl bg-white p-5 shadow-md">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-xl font-black">{t("driverLedger.activity.title")}</h2><p className="text-sm font-medium text-slate-600">{t("driverLedger.activity.description")}</p></div><LedgerStatementPrintButton addaId={printAddaId} documentType="driver_ledger" initialLanguage={language} makePresentation={printPresentation} fallbackLabel={language === "ur" ? "پرانا پرنٹ استعمال کریں" : "Use legacy print"} onLegacyPrint={print} unavailableReason={trips.length && !printAddaId ? (language === "ur" ? "مخلوط یا غیر تصدیق شدہ اڈوں کی سرگرمی پرنٹ نہیں ہو سکتی۔" : "A mixed or unresolved Adda activity report cannot be printed.") : undefined}><button type="button" disabled={!printAddaId} className="rounded-lg bg-blue-600 px-4 py-2 font-bold text-white disabled:opacity-50">{t("common.actions.print")}</button></LedgerStatementPrintButton></div>
      {trips.length && !printAddaId ? <p className="mb-3 text-xs font-semibold text-amber-800">{language === "ur" ? "مخلوط یا غیر تصدیق شدہ اڈوں کی سرگرمی پرنٹ نہیں ہو سکتی۔" : "A mixed or unresolved Adda activity report cannot be printed."}</p> : null}
      {isLoading || accountLoading ? <p className="p-8 text-center font-semibold">{t("driverLedger.loading")}</p> : activityRows.length === 0 ? <p className="rounded-lg bg-slate-50 p-8 text-center font-semibold">{t("driverLedger.table.empty")}</p> : <div className="overflow-x-auto"><table className="min-w-[1150px] w-full border-collapse text-sm"><thead className="bg-slate-100"><tr>{["date","chakkar","vehicle","tripLeg","route","driver","driverKharcha","salaryEarnings","actions"].map((key) => <th key={key} className="p-3 text-start">{t(`driverLedger.table.${key}`)}</th>)}</tr></thead><tbody>{activityRows.map((row) => <tr key={row.id} className="border-b border-slate-200"><td className="p-3">{row.trip.date}</td><td className="p-3 font-semibold">{row.trip.sourceType === "manual" ? row.trip.voucherNo : row.trip.biltyNo}</td><td className="p-3">{row.trip.vehicleNo}</td><td className="p-3">{row.legLabel}</td><td className="p-3">{row.trip.route}</td><td className="p-3">{row.driverName}</td><td className="p-3">{row.kharchaStatus === "attributed" ? `${t("driverLedger.kharcha.attributed")}: ${money(row.kharcha)}` : row.kharchaStatus === "unallocated" ? t("driverLedger.kharcha.unallocated") : t("driverLedger.kharcha.none")}</td><td className="p-3">{money(row.salaryEarnings)}</td><td className="p-3"><button type="button" onClick={() => setSelectedActivity(row)} className="font-bold text-blue-700">{t("driverLedger.table.viewDetail")}</button></td></tr>)}</tbody></table></div>}
    </section>

    <section className="rounded-xl bg-white p-5 shadow-md">
      <div className="mb-4"><h2 className="text-xl font-black">{t("driverLedger.account.title")}</h2><p className="text-sm font-medium text-slate-600">{t("driverLedger.account.description")}</p></div>
      <div className="overflow-x-auto"><table className="min-w-[1000px] w-full border-collapse text-sm"><thead className="bg-slate-100"><tr>{["driver","opening","salaryEarnings","driverPayments","payable","recoverable","balance"].map((key) => <th key={key} className="p-3 text-start">{t(`driverLedger.account.${key}`)}</th>)}</tr></thead><tbody>{selectedAccountDrivers.map((driver) => {
        const balance = accountBalances.get(driver.id) ?? { payable: 0, recoverable: 0, balance: 0 };
        const driverEarnings = filteredAccountEarnings.filter((earning) => earning.driver_id === driver.id);
        const driverPayments = filteredAccountPayments.filter((payment) => payment.driver_id === driver.id);
        return <tr key={driver.id} className="border-b border-slate-200"><td className="p-3 font-semibold">{driver.name}</td><td className="p-3">{money(numeric(driver.opening_balance))}</td><td className="p-3">{money(driverEarnings.reduce((sum, earning) => sum + numeric(earning.gross_expense), 0))}</td><td className="p-3">{money(driverPayments.reduce((sum, payment) => sum + numeric(payment.payment_now), 0))}</td><td className="p-3">{money(balance.payable)}</td><td className="p-3">{money(balance.recoverable)}</td><td className="p-3 font-bold">{money(balance.balance)}</td></tr>;
      })}</tbody></table></div>
      <h3 className="mt-6 text-lg font-black">{t("driverLedger.account.history")}</h3>
      <div className="mt-3 overflow-x-auto"><table className="min-w-[1000px] w-full border-collapse text-sm"><thead className="bg-slate-100"><tr>{["date","driver","type","eventDescription","salaryEarnings","driverPayments","advanceAdjustment"].map((key) => <th key={key} className="p-3 text-start">{t(`driverLedger.account.${key}`)}</th>)}</tr></thead><tbody>{accountEvents.map((event) => <tr key={event.id} className="border-b border-slate-200"><td className="p-3">{event.date}</td><td className="p-3">{driversById.get(event.driverId)?.name || t("driverLedger.notRecorded")}</td><td className="p-3">{t(`driverLedger.account.${event.kind}`)}</td><td className="p-3">{event.detail}</td><td className="p-3">{money(event.earning)}</td><td className="p-3">{money(event.payment)}</td><td className="p-3">{money(event.advance)}</td></tr>)}</tbody></table></div>
      {selectedAccountDrivers.length === 0 && <p className="mt-3 text-sm text-slate-600">{t("driverLedger.account.noAccountForUnrecorded")}</p>}
    </section>

    {selectedActivity && <DriverActivityModal row={selectedActivity} accountBalance={selectedActivity.driverId ? accountBalances.get(selectedActivity.driverId) ?? null : null} onClose={() => setSelectedActivity(null)} />}
  </section>;
}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm"><p className="text-xs font-bold text-slate-600">{label}</p><p className="mt-2 text-xl font-black text-slate-900">{value}</p></div>;
}

function DriverActivityModal({ row, accountBalance, onClose }: { row: ActivityRow; accountBalance: DriverAccountBalance | null; onClose: () => void }) {
  const { t, dir } = useLanguage();
  const kharcha = driverKharcha(row.trip);
  const legs = row.trip.freightLegs ?? [];
  return <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <section role="dialog" aria-modal="true" className="max-h-[90vh] w-full max-w-6xl overflow-auto rounded-2xl bg-white p-5 shadow-2xl" dir={dir}>
      <div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="text-2xl font-black">{row.trip.sourceType === "manual" ? row.trip.voucherNo : row.trip.biltyNo}</h2><p className="mt-1 text-sm font-semibold text-slate-600">{row.trip.date} · {row.trip.vehicleNo} · {row.trip.route}</p></div><button type="button" onClick={onClose} className="rounded-lg border px-4 py-2 font-bold">{t("common.actions.close")}</button></div>
      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        <section className="rounded-xl border border-blue-200 bg-blue-50/40 p-4"><h3 className="font-black">{t("driverLedger.activity.tripDetail")}</h3><Info label={t("common.driver")} value={row.driverName}/><Info label={t("common.vehicle")} value={row.trip.vehicleNo}/><Info label={t("common.route")} value={row.trip.route}/><Info label={t("driverLedger.table.date")} value={row.trip.date}/>
          {row.trip.sourceType === "manual" ? <><Info label={t("driverLedger.table.tripLeg")} value={t("driverLedger.manualChakkar")}/><Info label={t("driverLedger.account.voucherNo")} value={row.trip.voucherNo}/></> : <div className="mt-3 overflow-x-auto"><table className="min-w-[850px] w-full border-collapse text-xs"><thead className="bg-blue-100"><tr>{["sideTripType","biltyNo","date","vehicle","route","driver","loadingId"].map((key) => <th key={key} className="border p-2 text-start">{t(`driverLedger.detail.${key}`)}</th>)}</tr></thead><tbody>{legs.map((leg) => <tr key={leg.bookingId}><td className="border p-2">{leg.side}</td><td className="border p-2">{leg.biltyNo}</td><td className="border p-2">{leg.bookingDate || t("driverLedger.notRecorded")}</td><td className="border p-2">{leg.vehicleNo}</td><td className="border p-2">{leg.route}</td><td className="border p-2">{leg.loadingDrivers.length ? leg.loadingDrivers.map((assignment) => `${assignment.loadingId}: ${assignment.driverName}`).join(" · ") : leg.driverName || t("driverLedger.notRecorded")}</td><td className="border p-2">{leg.loadingIds.length ? leg.loadingIds.join(", ") : t("driverLedger.notRecorded")}</td></tr>)}</tbody></table></div>}
        </section>
        <section className="rounded-xl border border-amber-200 bg-amber-50/30 p-4"><h3 className="font-black">{t("driverLedger.detail.driverFinancials")}</h3><Info label={t("driverLedger.summary.salaryEarnings")} value={money(row.salaryEarnings)}/><Info label={t("driverLedger.summary.driverAccountBalance")} value={accountBalance ? money(accountBalance.balance) : "—"}/><Info label={t("driverLedger.detail.kharchaStatus")} value={kharcha.status === "attributed" ? `${t("driverLedger.kharcha.attributed")} · ${money(kharcha.amount)}` : kharcha.status === "unallocated" ? `${t("driverLedger.kharcha.unallocated")} · ${money(kharcha.amount)}` : t("driverLedger.kharcha.none")}/><p className="mt-3 rounded-lg bg-white p-3 text-xs font-medium text-slate-600">{t("driverLedger.detail.paymentNotTripLinked")}</p>{accountBalance && <p className="mt-3 text-xs font-semibold text-slate-600">{t("driverLedger.account.payable")}: {money(accountBalance.payable)} · {t("driverLedger.account.recoverable")}: {money(accountBalance.recoverable)}</p>}</section>
      </div>
    </section>
  </div>;
}

function Info({ label, value }: { label: string; value: string }) {
  return <div className="flex items-start justify-between gap-4 border-b border-slate-200 py-2"><span className="text-sm font-semibold text-slate-600">{label}</span><span className="text-right text-sm font-bold text-slate-900">{value}</span></div>;
}

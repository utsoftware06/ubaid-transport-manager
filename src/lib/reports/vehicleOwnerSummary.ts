export type SummaryRole = "super_admin" | "adda_admin" | "operator";

export type PeriodSelection =
  | { mode: "month"; month: string }
  | { mode: "custom"; from: string; to: string };

export type SummaryVehicle = {
  id: string;
  adda_id: string;
  vehicle_no: string | null;
  owner_name: string | null;
};

export type MonthlyReport = {
  vehicle: { id: string; adda_id: string; vehicle_no: string | null; owner_name: string | null };
  summary: Record<string, unknown>;
  expense_breakdown: Record<string, unknown>;
  chakkars: Array<Record<string, unknown>>;
};

export type OwnerClosing = {
  account: { vehicle_id: string; adda_id: string; vehicle_no: string | null; owner_name: string | null };
  summary: Record<string, unknown>;
};

export type OwnerStatement = {
  account: { vehicle_id: string; adda_id: string };
  transactions: Array<Record<string, unknown>>;
};

export type VehicleReportBundle = {
  vehicle: SummaryVehicle;
  monthly: MonthlyReport;
  closing: OwnerClosing;
  statement: OwnerStatement;
};

export type VehicleTotals = {
  chakkars: number;
  freight: number;
  expenses: number;
  netEarnings: number;
};

export type SourceLinkIssue = "missing_source_id" | "duplicate_source_id";

export type OwnerTotals = {
  opening: number;
  periodMovement: number;
  recordedChakkarCredits: number;
  verifiedLinkedChakkarCredits: number | null;
  chakkarSourceLinkIssue: SourceLinkIssue | null;
  commissionNet: number;
  recordedVoucherAdjustmentNet: number;
  verifiedLinkedVoucherAdjustmentNet: number | null;
  voucherAdjustmentSourceLinkIssue: SourceLinkIssue | null;
  otherAdjustmentNet: number;
  actualWithdrawals: number;
  withdrawalMovement: number;
  openingSeedMovement: number;
  unclassifiedMovement: number | null;
  closing: number;
  payable: number;
  receivable: number;
};

export type OwnerGroup = OwnerTotals & {
  key: string;
  ownerName: string | null;
  vehicleCount: number;
  vehicleIds: string[];
};

export type Reconciliation = {
  settlementEarnings: number;
  recordedChakkarCredits: number;
  verifiedLinkedChakkarCredits: number | null;
  chakkarSourceLinkIssue: SourceLinkIssue | null;
  differenceBeforeVoucherAdjustments: number | null;
  recordedVoucherAdjustmentNet: number;
  verifiedLinkedVoucherAdjustmentNet: number | null;
  voucherAdjustmentSourceLinkIssue: SourceLinkIssue | null;
  remainingDifference: number | null;
};

export type ExpenseBreakdown = {
  status: "complete" | "partial" | "unavailable";
  categories: Record<"diesel" | "workshop" | "tyre" | "oil" | "driver" | "other", number> | null;
  unallocated: number | null;
};

export type OwnerMovementBreakdown = {
  recordedChakkarCredits: number;
  verifiedLinkedChakkarCredits: number | null;
  chakkarSourceLinkIssue: SourceLinkIssue | null;
  recordedVoucherAdjustmentNet: number;
  verifiedLinkedVoucherAdjustmentNet: number | null;
  voucherAdjustmentSourceLinkIssue: SourceLinkIssue | null;
  commissionNet: number;
  withdrawalMovement: number;
  actualWithdrawals: number;
  otherAdjustmentNet: number;
  openingSeedMovement: number;
  unclassifiedMovement: number | null;
  periodMovement: number;
};

const COMMISSION_TRANSACTION_TYPES = new Set([
  "monthly_adda_commission",
  "monthly_adda_commission_reversal",
  "monthly_adda_commission_reissue",
  "monthly_adda_commission_adjustment_increase",
  "monthly_adda_commission_adjustment_decrease",
  "monthly_adda_commission_correction_reversal_credit",
  "monthly_adda_commission_correction_reversal_debit",
]);

const CHAKKAR_CREDIT_TRANSACTION_TYPES = new Set(["chakkar_net_credit", "manual_chakkar_net"]);
const VOUCHER_ADJUSTMENT_TRANSACTION_TYPES = new Set(["voucher_adjustment_expense", "manual_chakkar_adjustment"]);
const OWNER_GARI_TRANSACTION_TYPES = new Set([
  "opening_seed",
  ...CHAKKAR_CREDIT_TRANSACTION_TYPES,
  ...VOUCHER_ADJUSTMENT_TRANSACTION_TYPES,
  "owner_withdrawal",
  "gari_withdrawal",
  ...COMMISSION_TRANSACTION_TYPES,
  "adjustment_credit",
  "adjustment_debit",
]);

function requiredNumber(record: Record<string, unknown>, key: string): number {
  const value = record[key];
  const parsed = typeof value === "number" || typeof value === "string" ? Number(value) : Number.NaN;
  if (!Number.isFinite(parsed)) throw new Error(`Invalid report value: ${key}`);
  return parsed;
}

function optionalNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = typeof value === "number" || typeof value === "string" ? Number(value) : Number.NaN;
  return Number.isFinite(parsed) ? parsed : null;
}

export function canViewVehicleOwnerSummary(
  role: string | null | undefined,
  isActive: boolean | null | undefined,
  profileAddaId: string | null,
  targetAddaId: string | null,
): boolean {
  if (isActive !== true) return false;
  if (role === "super_admin") return Boolean(targetAddaId);
  return role === "adda_admin" && Boolean(profileAddaId) && profileAddaId === targetAddaId;
}

export function canLoadVehicleOwnerSummary(
  role: SummaryRole,
  profileAddaId: string | null,
  targetAddaId: string | null,
): boolean {
  return canViewVehicleOwnerSummary(role, true, profileAddaId, targetAddaId);
}

export function buildReportPeriodArgs(period: PeriodSelection) {
  if (period.mode === "month") {
    const parts = /^(\d{4})-(\d{2})$/.exec(period.month);
    if (!parts || Number(parts[2]) < 1 || Number(parts[2]) > 12) throw new Error("Select a valid month.");
    return { month: `${period.month}-01`, from: null, to: null };
  }
  const validDate = (value: string) => {
    const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    if (!parts) return false;
    const date = new Date(Date.UTC(Number(parts[1]), Number(parts[2]) - 1, Number(parts[3])));
    return date.getUTCFullYear() === Number(parts[1]) && date.getUTCMonth() + 1 === Number(parts[2]) && date.getUTCDate() === Number(parts[3]);
  };
  if (!validDate(period.from) || !validDate(period.to) || period.from > period.to) throw new Error("Select a valid inclusive date range.");
  return { month: null, from: period.from, to: period.to };
}

export function validateVehicleBundle(
  vehicle: SummaryVehicle,
  addaId: string,
  monthly: unknown,
  closing: unknown,
  statement: unknown,
): VehicleReportBundle {
  const monthlyRow = monthly as MonthlyReport | null;
  const closingRow = closing as OwnerClosing | null;
  const statementRow = statement as OwnerStatement | null;
  if (!monthlyRow?.vehicle || !closingRow?.account || !statementRow?.account) throw new Error("A report source returned an incomplete result.");
  if (monthlyRow.vehicle.id !== vehicle.id || monthlyRow.vehicle.adda_id !== addaId ||
      closingRow.account.vehicle_id !== vehicle.id || closingRow.account.adda_id !== addaId ||
      statementRow.account.vehicle_id !== vehicle.id || statementRow.account.adda_id !== addaId) {
    throw new Error("A report source returned a different vehicle or Adda.");
  }
  const monthlySummary = monthlyRow.summary;
  const closingSummary = closingRow.summary;
  for (const field of ["total_chakkar", "total_vehicle_freight", "total_expenses", "vehicle_monthly_profit"]) {
    requiredNumber(monthlySummary, field);
  }
  for (const field of ["opening_balance", "period_net_change", "closing_balance", "owner_gari_net_commission_charge", "owner_withdrawals", "gari_withdrawals", "voucher_adjustment_expenses", "manual_adjustment_debits"]) {
    requiredNumber(closingSummary, field);
  }
  if (!Array.isArray(monthlyRow.chakkars) || !Array.isArray(statementRow.transactions)) throw new Error("A report source returned an incomplete row set.");
  const settlementKeys = new Set<string>();
  for (const row of monthlyRow.chakkars) {
    const id = row.settlement_id;
    if (typeof id !== "string" || !id) throw new Error("A Chakkar row has no saved settlement identity.");
    if (row.source_type != null && row.source_type !== "bilty" && row.source_type !== "manual") {
      throw new Error("A Chakkar row has an unsupported saved source type.");
    }
    const source = row.source_type === "manual" ? "manual" : "bilty";
    const key = `${source}:${id}`;
    if (settlementKeys.has(key)) throw new Error("A Chakkar settlement was returned more than once.");
    settlementKeys.add(key);
  }
  const transactionIds = new Set<string>();
  let statementMovement = 0;
  for (const transaction of statementRow.transactions) {
    const transactionId = transaction.transaction_id;
    const transactionType = transaction.transaction_type;
    if (typeof transactionId !== "string" || !transactionId || transactionIds.has(transactionId)) {
      throw new Error("An Owner/Gari transaction is missing its unique saved identity.");
    }
    if (typeof transactionType !== "string" || !transactionType) {
      throw new Error("An Owner/Gari transaction is missing its saved type.");
    }
    if (!OWNER_GARI_TRANSACTION_TYPES.has(transactionType)) {
      throw new Error("An Owner/Gari transaction has an unsupported saved type.");
    }
    transactionIds.add(transactionId);
    statementMovement += requiredNumber(transaction, "signed_amount");
  }
  if (Math.abs(roundMoney(statementMovement - requiredNumber(closingSummary, "period_net_change"))) >= 0.01) {
    throw new Error("The Owner/Gari statement rows do not cover the complete period movement.");
  }
  if (Math.abs(roundMoney(requiredNumber(closingSummary, "opening_balance") + requiredNumber(closingSummary, "period_net_change") - requiredNumber(closingSummary, "closing_balance"))) >= 0.01) {
    throw new Error("Owner/Gari opening, period movement and closing do not reconcile.");
  }
  return { vehicle, monthly: monthlyRow, closing: closingRow, statement: statementRow };
}

export function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function aggregateVehicleTotals(reports: readonly VehicleReportBundle[]): VehicleTotals {
  return reports.reduce<VehicleTotals>((total, report) => {
    const summary = report.monthly.summary;
    total.chakkars += requiredNumber(summary, "total_chakkar");
    total.freight += requiredNumber(summary, "total_vehicle_freight");
    total.expenses += requiredNumber(summary, "total_expenses");
    total.netEarnings += requiredNumber(summary, "vehicle_monthly_profit");
    return total;
  }, { chakkars: 0, freight: 0, expenses: 0, netEarnings: 0 });
}

export function assertUniqueVehicleBundles(reports: readonly VehicleReportBundle[]): void {
  const vehicleIds = new Set<string>();
  for (const report of reports) {
    if (vehicleIds.has(report.vehicle.id)) throw new Error("A vehicle report was included more than once.");
    vehicleIds.add(report.vehicle.id);
  }
}

function addNullable(left: number | null, right: number | null): number | null {
  return left === null || right === null ? null : roundMoney(left + right);
}

function savedSourceId(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function calculateOwnerMovementBreakdown(report: VehicleReportBundle): OwnerMovementBreakdown {
  let recordedChakkarCredits = 0;
  let verifiedLinkedChakkarCredits = 0;
  let chakkarSourceLinkIssue: SourceLinkIssue | null = null;
  let recordedVoucherAdjustmentNet = 0;
  let verifiedLinkedVoucherAdjustmentNet = 0;
  let voucherAdjustmentSourceLinkIssue: SourceLinkIssue | null = null;
  let commissionNet = 0;
  let withdrawalMovement = 0;
  let otherAdjustmentNet = 0;
  let openingSeedMovement = 0;
  const chakkarSources = new Set<string>();
  const voucherAdjustmentSources = new Set<string>();

  for (const transaction of report.statement.transactions) {
    const type = String(transaction.transaction_type ?? "");
    const signedAmount = requiredNumber(transaction, "signed_amount");
    if (CHAKKAR_CREDIT_TRANSACTION_TYPES.has(type)) {
      recordedChakkarCredits = roundMoney(recordedChakkarCredits + signedAmount);
      const sourceId = type === "manual_chakkar_net"
        ? savedSourceId(transaction.source_manual_settlement_id)
        : savedSourceId(transaction.source_settlement_id);
      if (!sourceId) chakkarSourceLinkIssue ??= "missing_source_id";
      else if (chakkarSources.has(`${type}:${sourceId}`)) chakkarSourceLinkIssue ??= "duplicate_source_id";
      else {
        chakkarSources.add(`${type}:${sourceId}`);
        verifiedLinkedChakkarCredits = roundMoney(verifiedLinkedChakkarCredits + signedAmount);
      }
    } else if (VOUCHER_ADJUSTMENT_TRANSACTION_TYPES.has(type)) {
      recordedVoucherAdjustmentNet = roundMoney(recordedVoucherAdjustmentNet + signedAmount);
      const sourceId = type === "manual_chakkar_adjustment"
        ? savedSourceId(transaction.source_manual_adjustment_id)
        : savedSourceId(transaction.source_adjustment_id);
      if (!sourceId) voucherAdjustmentSourceLinkIssue ??= "missing_source_id";
      else if (voucherAdjustmentSources.has(`${type}:${sourceId}`)) voucherAdjustmentSourceLinkIssue ??= "duplicate_source_id";
      else {
        voucherAdjustmentSources.add(`${type}:${sourceId}`);
        verifiedLinkedVoucherAdjustmentNet = roundMoney(verifiedLinkedVoucherAdjustmentNet + signedAmount);
      }
    } else if (COMMISSION_TRANSACTION_TYPES.has(type)) {
      commissionNet = roundMoney(commissionNet + signedAmount);
    } else if (type === "owner_withdrawal" || type === "gari_withdrawal") {
      withdrawalMovement = roundMoney(withdrawalMovement + signedAmount);
    } else if (type === "adjustment_credit" || type === "adjustment_debit") {
      otherAdjustmentNet = roundMoney(otherAdjustmentNet + signedAmount);
    } else if (type === "opening_seed") {
      openingSeedMovement = roundMoney(openingSeedMovement + signedAmount);
    }
  }

  const summary = report.closing.summary;
  const periodMovement = requiredNumber(summary, "period_net_change");
  const actualWithdrawals = requiredNumber(summary, "owner_withdrawals") + requiredNumber(summary, "gari_withdrawals");
  const unclassifiedMovement = roundMoney(periodMovement - recordedChakkarCredits - recordedVoucherAdjustmentNet - commissionNet - withdrawalMovement - otherAdjustmentNet - openingSeedMovement);
  return {
    recordedChakkarCredits,
    verifiedLinkedChakkarCredits: chakkarSourceLinkIssue ? null : verifiedLinkedChakkarCredits,
    chakkarSourceLinkIssue,
    recordedVoucherAdjustmentNet,
    verifiedLinkedVoucherAdjustmentNet: voucherAdjustmentSourceLinkIssue ? null : verifiedLinkedVoucherAdjustmentNet,
    voucherAdjustmentSourceLinkIssue,
    commissionNet,
    withdrawalMovement,
    actualWithdrawals,
    otherAdjustmentNet,
    openingSeedMovement,
    unclassifiedMovement,
    periodMovement,
  };
}

function ownerTotals(report: VehicleReportBundle): OwnerTotals {
  const summary = report.closing.summary;
  const movement = calculateOwnerMovementBreakdown(report);
  const opening = requiredNumber(summary, "opening_balance");
  const closing = requiredNumber(summary, "closing_balance");
  return {
    opening,
    periodMovement: movement.periodMovement,
    recordedChakkarCredits: movement.recordedChakkarCredits,
    verifiedLinkedChakkarCredits: movement.verifiedLinkedChakkarCredits,
    chakkarSourceLinkIssue: movement.chakkarSourceLinkIssue,
    commissionNet: movement.commissionNet,
    recordedVoucherAdjustmentNet: movement.recordedVoucherAdjustmentNet,
    verifiedLinkedVoucherAdjustmentNet: movement.verifiedLinkedVoucherAdjustmentNet,
    voucherAdjustmentSourceLinkIssue: movement.voucherAdjustmentSourceLinkIssue,
    otherAdjustmentNet: movement.otherAdjustmentNet,
    actualWithdrawals: movement.actualWithdrawals,
    withdrawalMovement: movement.withdrawalMovement,
    openingSeedMovement: movement.openingSeedMovement,
    unclassifiedMovement: movement.unclassifiedMovement,
    closing,
    payable: Math.max(closing, 0),
    receivable: Math.max(-closing, 0),
  };
}

export function aggregateOwnerTotals(reports: readonly VehicleReportBundle[]): OwnerTotals {
  return reports.reduce<OwnerTotals>((total, report) => {
    const item = ownerTotals(report);
    total.opening += item.opening;
    total.periodMovement += item.periodMovement;
    total.recordedChakkarCredits = roundMoney(total.recordedChakkarCredits + item.recordedChakkarCredits);
    total.verifiedLinkedChakkarCredits = addNullable(total.verifiedLinkedChakkarCredits, item.verifiedLinkedChakkarCredits);
    total.chakkarSourceLinkIssue ??= item.chakkarSourceLinkIssue;
    total.commissionNet = roundMoney(total.commissionNet + item.commissionNet);
    total.recordedVoucherAdjustmentNet = roundMoney(total.recordedVoucherAdjustmentNet + item.recordedVoucherAdjustmentNet);
    total.verifiedLinkedVoucherAdjustmentNet = addNullable(total.verifiedLinkedVoucherAdjustmentNet, item.verifiedLinkedVoucherAdjustmentNet);
    total.voucherAdjustmentSourceLinkIssue ??= item.voucherAdjustmentSourceLinkIssue;
    total.otherAdjustmentNet = roundMoney(total.otherAdjustmentNet + item.otherAdjustmentNet);
    total.actualWithdrawals += item.actualWithdrawals;
    total.withdrawalMovement = roundMoney(total.withdrawalMovement + item.withdrawalMovement);
    total.openingSeedMovement = roundMoney(total.openingSeedMovement + item.openingSeedMovement);
    total.unclassifiedMovement = addNullable(total.unclassifiedMovement, item.unclassifiedMovement);
    total.closing += item.closing;
    total.payable += item.payable;
    total.receivable += item.receivable;
    return total;
  }, { opening: 0, periodMovement: 0, recordedChakkarCredits: 0, verifiedLinkedChakkarCredits: 0, chakkarSourceLinkIssue: null, commissionNet: 0, recordedVoucherAdjustmentNet: 0, verifiedLinkedVoucherAdjustmentNet: 0, voucherAdjustmentSourceLinkIssue: null, otherAdjustmentNet: 0, actualWithdrawals: 0, withdrawalMovement: 0, openingSeedMovement: 0, unclassifiedMovement: 0, closing: 0, payable: 0, receivable: 0 });
}

export function groupOwnersByCurrentName(reports: readonly VehicleReportBundle[]): OwnerGroup[] {
  const groups = new Map<string, OwnerGroup>();
  for (const report of reports) {
    const ownerName = report.vehicle.owner_name?.trim() || null;
    const key = ownerName ? `name:${ownerName.toLocaleLowerCase()}` : `unrecorded:${report.vehicle.id}`;
    const current = groups.get(key) ?? {
      key,
      ownerName,
      vehicleCount: 0,
      vehicleIds: [],
      opening: 0,
      periodMovement: 0,
      recordedChakkarCredits: 0,
      verifiedLinkedChakkarCredits: 0,
      chakkarSourceLinkIssue: null,
      commissionNet: 0,
      recordedVoucherAdjustmentNet: 0,
      verifiedLinkedVoucherAdjustmentNet: 0,
      voucherAdjustmentSourceLinkIssue: null,
      otherAdjustmentNet: 0,
      actualWithdrawals: 0,
      withdrawalMovement: 0,
      openingSeedMovement: 0,
      unclassifiedMovement: 0,
      closing: 0,
      payable: 0,
      receivable: 0,
    };
    const values = ownerTotals(report);
    current.vehicleCount += 1;
    current.vehicleIds.push(report.vehicle.id);
    current.opening += values.opening;
    current.periodMovement += values.periodMovement;
    current.recordedChakkarCredits = roundMoney(current.recordedChakkarCredits + values.recordedChakkarCredits);
    current.verifiedLinkedChakkarCredits = addNullable(current.verifiedLinkedChakkarCredits, values.verifiedLinkedChakkarCredits);
    current.chakkarSourceLinkIssue ??= values.chakkarSourceLinkIssue;
    current.commissionNet = roundMoney(current.commissionNet + values.commissionNet);
    current.recordedVoucherAdjustmentNet = roundMoney(current.recordedVoucherAdjustmentNet + values.recordedVoucherAdjustmentNet);
    current.verifiedLinkedVoucherAdjustmentNet = addNullable(current.verifiedLinkedVoucherAdjustmentNet, values.verifiedLinkedVoucherAdjustmentNet);
    current.voucherAdjustmentSourceLinkIssue ??= values.voucherAdjustmentSourceLinkIssue;
    current.otherAdjustmentNet = roundMoney(current.otherAdjustmentNet + values.otherAdjustmentNet);
    current.actualWithdrawals += values.actualWithdrawals;
    current.withdrawalMovement = roundMoney(current.withdrawalMovement + values.withdrawalMovement);
    current.openingSeedMovement = roundMoney(current.openingSeedMovement + values.openingSeedMovement);
    current.unclassifiedMovement = addNullable(current.unclassifiedMovement, values.unclassifiedMovement);
    current.closing += values.closing;
    current.payable += values.payable;
    current.receivable += values.receivable;
    groups.set(key, current);
  }
  return [...groups.values()].sort((a, b) => (a.ownerName ?? "").localeCompare(b.ownerName ?? ""));
}

export function calculateEarningsReconciliation(reports: readonly VehicleReportBundle[]): Reconciliation {
  let recordedChakkarCredits = 0;
  let verifiedLinkedChakkarCredits: number | null = 0;
  let chakkarSourceLinkIssue: SourceLinkIssue | null = null;
  let recordedVoucherAdjustmentNet = 0;
  let verifiedLinkedVoucherAdjustmentNet: number | null = 0;
  let voucherAdjustmentSourceLinkIssue: SourceLinkIssue | null = null;
  for (const report of reports) {
    const breakdown = calculateOwnerMovementBreakdown(report);
    recordedChakkarCredits = roundMoney(recordedChakkarCredits + breakdown.recordedChakkarCredits);
    recordedVoucherAdjustmentNet = roundMoney(recordedVoucherAdjustmentNet + breakdown.recordedVoucherAdjustmentNet);
    verifiedLinkedChakkarCredits = addNullable(verifiedLinkedChakkarCredits, breakdown.verifiedLinkedChakkarCredits);
    chakkarSourceLinkIssue ??= breakdown.chakkarSourceLinkIssue;
    verifiedLinkedVoucherAdjustmentNet = addNullable(verifiedLinkedVoucherAdjustmentNet, breakdown.verifiedLinkedVoucherAdjustmentNet);
    voucherAdjustmentSourceLinkIssue ??= breakdown.voucherAdjustmentSourceLinkIssue;
  }
  const earnings = aggregateVehicleTotals(reports).netEarnings;
  const differenceBeforeVoucherAdjustments = verifiedLinkedChakkarCredits === null
    ? null
    : roundMoney(earnings - verifiedLinkedChakkarCredits);
  return {
    settlementEarnings: earnings,
    recordedChakkarCredits,
    verifiedLinkedChakkarCredits,
    chakkarSourceLinkIssue,
    differenceBeforeVoucherAdjustments,
    recordedVoucherAdjustmentNet,
    verifiedLinkedVoucherAdjustmentNet,
    voucherAdjustmentSourceLinkIssue,
    remainingDifference: differenceBeforeVoucherAdjustments === null || verifiedLinkedVoucherAdjustmentNet === null
      ? null
      : roundMoney(differenceBeforeVoucherAdjustments - verifiedLinkedVoucherAdjustmentNet),
  };
}

const EXPENSE_BREAKDOWN_FIELDS = ["diesel", "workshop", "tyre", "oil", "driver", "other"] as const;

export function expenseCategoriesForPrint(breakdown: ExpenseBreakdown) {
  if (!breakdown.categories) return [];
  return EXPENSE_BREAKDOWN_FIELDS
    .filter((category) => breakdown.status !== "complete" || breakdown.categories?.[category] !== 0)
    .map((category) => ({ category, amount: breakdown.categories![category] }));
}

export function reconcileExpenseBreakdown(row: Record<string, unknown>, savedTotal: unknown): ExpenseBreakdown {
  if (row.breakdown_status !== "RECONCILED") return { status: "unavailable", categories: null, unallocated: null };
  const total = optionalNumber(savedTotal);
  if (total === null || total < 0) return { status: "unavailable", categories: null, unallocated: null };
  const categories = {} as NonNullable<ExpenseBreakdown["categories"]>;
  let categoryTotal = 0;
  for (const field of EXPENSE_BREAKDOWN_FIELDS) {
    const value = optionalNumber(row[field]);
    if (value === null || value < 0) return { status: "unavailable", categories: null, unallocated: null };
    categories[field] = value;
    categoryTotal += value;
  }
  const unallocated = roundMoney(total - categoryTotal);
  if (unallocated < -0.01) return { status: "unavailable", categories: null, unallocated: null };
  const normalizedGap = unallocated < 0.01 ? 0 : unallocated;
  return {
    status: normalizedGap === 0 ? "complete" : "partial",
    categories,
    unallocated: normalizedGap,
  };
}

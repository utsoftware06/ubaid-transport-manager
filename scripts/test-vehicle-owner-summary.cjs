/* eslint-disable @typescript-eslint/no-require-imports */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const ts = require("typescript");

const helperPath = path.join(__dirname, "../src/lib/reports/vehicleOwnerSummary.ts");
const source = fs.readFileSync(helperPath, "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
});
const loaded = { exports: {} };
new Function("exports", "require", "module", compiled.outputText)(loaded.exports, require, loaded);
const {
  aggregateOwnerTotals,
  aggregateVehicleTotals,
  assertUniqueVehicleBundles,
  buildReportPeriodArgs,
  calculateEarningsReconciliation,
  canLoadVehicleOwnerSummary,
  canViewVehicleOwnerSummary,
  calculateOwnerMovementBreakdown,
  expenseCategoriesForPrint,
  groupOwnersByCurrentName,
  reconcileExpenseBreakdown,
  validateVehicleBundle,
} = loaded.exports;

const translationSource = fs.readFileSync(path.join(__dirname, "../src/i18n/translations.ts"), "utf8");
const translationCompiled = ts.transpileModule(translationSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
});
const translationModule = { exports: {} };
new Function("exports", "require", "module", translationCompiled.outputText)(translationModule.exports, require, translationModule);
function translationShape(value) {
  if (typeof value === "string") return "string";
  return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, translationShape(child)]));
}
assert.deepEqual(
  translationShape(translationModule.exports.translations.en.reports.vehicleOwnerSummary),
  translationShape(translationModule.exports.translations.ur.reports.vehicleOwnerSummary),
  "English and Urdu labels have matching coverage",
);
const requiredTranslationKeys = [
  "table.payable", "table.receivable", "cards.payable", "cards.receivable",
  "cards.commissionNet", "cards.recordedChakkarCredits", "cards.verifiedLinkedChakkarCredits",
  "cards.recordedVoucherAdjustments", "cards.verifiedLinkedVoucherAdjustments", "cards.otherAdjustmentNet",
  "table.recordedChakkarCredits", "table.verifiedLinkedChakkarCredits",
  "table.recordedVoucherAdjustments", "table.verifiedLinkedVoucherAdjustments",
  "table.unclassifiedMovement", "table.unallocated", "table.breakdownStatus",
  "breakdown.complete", "breakdown.partial", "breakdown.unavailable",
  "reconciliation.recordedChakkarCredits", "reconciliation.verifiedLinkedChakkarCredits",
  "reconciliation.differenceBeforeAdjustments", "reconciliation.recordedVoucherAdjustments",
  "reconciliation.verifiedLinkedVoucherAdjustments",
  "reconciliation.remainingDifference", "reconciliation.remainingDifferenceNote",
  "print.reportTotal", "print.allFilteredVehicles", "print.allZeroBreakdown", "print.chakkarLink", "print.voucherAdjustmentLink",
  "sourceLinkIssues.chakkars.missingSourceId", "sourceLinkIssues.chakkars.duplicateSourceId",
  "sourceLinkIssues.voucherAdjustments.missingSourceId", "sourceLinkIssues.voucherAdjustments.duplicateSourceId",
];
for (const language of ["en", "ur"]) {
  const reportTranslations = translationModule.exports.translations[language].reports.vehicleOwnerSummary;
  for (const relativeKey of requiredTranslationKeys) {
    const fullKey = `reports.vehicleOwnerSummary.${relativeKey}`;
    const value = relativeKey.split(".").reduce((node, part) => node && node[part], reportTranslations);
    assert.equal(typeof value, "string", `${language} translation exists for ${fullKey}`);
    assert.notEqual(value, fullKey, `${language} must not render raw key ${fullKey}`);
  }
}

function makeBundle({ id, owner = "Current Owner", chakkars, monthlySummary, closingSummary, transactions }) {
  const vehicle = { id, adda_id: "adda-a", vehicle_no: `TRK-${id}`, owner_name: owner };
  const monthly = {
    vehicle,
    summary: {
      total_chakkar: monthlySummary.count,
      total_vehicle_freight: monthlySummary.freight,
      total_expenses: monthlySummary.expenses,
      vehicle_monthly_profit: monthlySummary.net,
    },
    expense_breakdown: { status: "RECONCILED" },
    chakkars,
  };
  const closing = {
    account: { vehicle_id: id, adda_id: "adda-a", vehicle_no: vehicle.vehicle_no, owner_name: owner },
    summary: {
      opening_balance: closingSummary.opening,
      period_net_change: closingSummary.movement,
      closing_balance: closingSummary.closing,
      owner_gari_net_commission_charge: closingSummary.commission,
      owner_withdrawals: closingSummary.ownerWithdrawals,
      gari_withdrawals: closingSummary.gariWithdrawals,
      voucher_adjustment_expenses: closingSummary.voucherAdjustments,
      manual_adjustment_debits: closingSummary.manualDebits,
    },
  };
  const statement = { account: { vehicle_id: id, adda_id: "adda-a" }, transactions };
  return validateVehicleBundle(vehicle, "adda-a", monthly, closing, statement);
}

const bilty = makeBundle({
  id: "v1",
  chakkars: [{ settlement_id: "s1", source_type: "bilty", chakkar_date: "2026-10-31", vehicle_freight: 100, total_expenses: 10, net_vehicle_amount: 90, breakdown_status: "SNAPSHOT_MISMATCH", diesel: null }],
  monthlySummary: { count: 1, freight: 100, expenses: 10, net: 90 },
  closingSummary: { opening: 10, movement: 70, closing: 80, commission: 7, ownerWithdrawals: 13, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 },
  transactions: [
    { transaction_id: "t1", transaction_date: "2026-11-01", transaction_type: "chakkar_net_credit", signed_amount: 90, source_settlement_id: "s1" },
    { transaction_id: "t2", transaction_date: "2026-11-02", transaction_type: "monthly_adda_commission", signed_amount: -7, source_commission_event_id: "commission-1" },
    { transaction_id: "t3", transaction_date: "2026-11-03", transaction_type: "owner_withdrawal", signed_amount: -13 },
  ],
});
const manual = makeBundle({
  id: "v2",
  chakkars: [{ settlement_id: "m1", source_type: "manual", chakkar_date: "2026-11-02", vehicle_freight: 50, total_expenses: 20, net_vehicle_amount: 30, adjusted_vehicle_freight: 50, adjusted_total_expenses: 20, adjusted_net_vehicle_amount: 30, breakdown_status: "RECONCILED", diesel: 0 }],
  monthlySummary: { count: 1, freight: 50, expenses: 20, net: 30 },
  closingSummary: { opening: -50, movement: 30, closing: -20, commission: 0, ownerWithdrawals: 0, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 },
  transactions: [
    { transaction_id: "t4", transaction_date: "2026-11-03", transaction_type: "manual_chakkar_net", signed_amount: 30, source_manual_settlement_id: "m1" },
    { transaction_id: "t5", transaction_date: "2026-11-04", transaction_type: "manual_chakkar_adjustment", signed_amount: 10, manual_settlement_id: "m1", source_manual_adjustment_id: "adj-1" },
    { transaction_id: "t6", transaction_date: "2026-11-05", transaction_type: "manual_chakkar_adjustment", signed_amount: -10, manual_settlement_id: "m1", source_manual_adjustment_id: "adj-reversal-1", reverses_adjustment_id: "adj-1" },
  ],
});

const reports = [bilty, manual];
assert.deepEqual(aggregateVehicleTotals(reports), { chakkars: 2, freight: 150, expenses: 30, netEarnings: 120 }, "Bilty and finalized Manual Voucher snapshots aggregate once");
const owners = aggregateOwnerTotals(reports);
assert.equal(owners.opening, -40);
assert.equal(owners.periodMovement, 100);
assert.equal(owners.closing, 60);
assert.equal(owners.opening + owners.periodMovement, owners.closing, "opening + signed movements = closing");
assert.equal(owners.commissionNet, -7, "commission retains its signed ledger effect");
assert.equal(owners.recordedVoucherAdjustmentNet, 0, "recorded Voucher adjustments and their reversal net separately");
assert.equal(owners.verifiedLinkedVoucherAdjustmentNet, 0);
assert.equal(owners.actualWithdrawals, 13);
assert.equal(owners.payable, 80, "positive account is payable");
assert.equal(owners.receivable, 20, "negative account remains separately receivable, not netted against payable");
assert.deepEqual(calculateEarningsReconciliation(reports), {
  settlementEarnings: 120,
  recordedChakkarCredits: 120,
  verifiedLinkedChakkarCredits: 120,
  chakkarSourceLinkIssue: null,
  differenceBeforeVoucherAdjustments: 0,
  recordedVoucherAdjustmentNet: 0,
  verifiedLinkedVoucherAdjustmentNet: 0,
  voucherAdjustmentSourceLinkIssue: null,
  remainingDifference: 0,
}, "manual adjustment and its reversal offset once against the linked source");

const changedAxis = makeBundle({
  id: "v3",
  chakkars: [{ settlement_id: "s3", source_type: "bilty", chakkar_date: "2026-10-31", vehicle_freight: 25, total_expenses: 0, net_vehicle_amount: 25, breakdown_status: "RECONCILED" }],
  monthlySummary: { count: 1, freight: 25, expenses: 0, net: 25 },
  closingSummary: { opening: 0, movement: 20, closing: 20, commission: 0, ownerWithdrawals: 0, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 },
  transactions: [{ transaction_id: "t7", transaction_date: "2026-11-02", transaction_type: "chakkar_net_credit", signed_amount: 20, source_settlement_id: "s3" }],
});
assert.equal(calculateEarningsReconciliation([changedAxis]).remainingDifference, 5, "date-axis residual remains visible instead of being forced to zero");
assert.equal(calculateEarningsReconciliation([changedAxis]).differenceBeforeVoucherAdjustments, 5);
assert.equal(calculateEarningsReconciliation([changedAxis]).verifiedLinkedVoucherAdjustmentNet, 0, "an unrelated date-axis residual is not attributed to a Voucher adjustment");

const reconciliationExample = makeBundle({
  id: "reconciliation-example",
  chakkars: [{ settlement_id: "settlement-example", source_type: "bilty", chakkar_date: "2026-11-01", vehicle_freight: 500000, total_expenses: 75800, net_vehicle_amount: 424200, breakdown_status: "RECONCILED", diesel: 0, workshop: 0, tyre: 0, oil: 0, driver: 0, other: 75800 }],
  monthlySummary: { count: 1, freight: 500000, expenses: 75800, net: 424200 },
  closingSummary: { opening: 0, movement: -20800, closing: -20800, commission: 10000, ownerWithdrawals: 435000, gariWithdrawals: 0, voucherAdjustments: 86000, manualDebits: 0 },
  transactions: [
    { transaction_id: "example-chakkar", transaction_date: "2026-11-01", transaction_type: "chakkar_net_credit", signed_amount: 510200, source_settlement_id: "settlement-example" },
    { transaction_id: "example-voucher-original", transaction_date: "2026-11-02", transaction_type: "voucher_adjustment_expense", signed_amount: -100000, source_adjustment_id: "voucher-adjustment-original" },
    { transaction_id: "example-voucher-reversal", transaction_date: "2026-11-03", transaction_type: "voucher_adjustment_expense", signed_amount: 10000, source_adjustment_id: "voucher-adjustment-reversal" },
    { transaction_id: "example-manual-adjustment-reversal", transaction_date: "2026-11-04", transaction_type: "manual_chakkar_adjustment", signed_amount: 4000, source_manual_adjustment_id: "manual-adjustment-reversal", reverses_adjustment_id: "manual-adjustment-original" },
    { transaction_id: "example-commission", transaction_date: "2026-11-05", transaction_type: "monthly_adda_commission", signed_amount: -15000, source_commission_event_id: "commission-charge" },
    { transaction_id: "example-commission-reversal", transaction_date: "2026-11-06", transaction_type: "monthly_adda_commission_reversal", signed_amount: 15000, source_commission_event_id: "commission-reversal" },
    { transaction_id: "example-commission-reissue", transaction_date: "2026-11-07", transaction_type: "monthly_adda_commission_reissue", signed_amount: -10000, source_commission_event_id: "commission-reissue" },
    { transaction_id: "example-commission-increase", transaction_date: "2026-11-08", transaction_type: "monthly_adda_commission_adjustment_increase", signed_amount: -2000, source_commission_event_id: "commission-increase" },
    { transaction_id: "example-commission-decrease", transaction_date: "2026-11-09", transaction_type: "monthly_adda_commission_adjustment_decrease", signed_amount: 2000, source_commission_event_id: "commission-decrease" },
    { transaction_id: "example-commission-correction-credit", transaction_date: "2026-11-09", transaction_type: "monthly_adda_commission_correction_reversal_credit", signed_amount: 3000, source_commission_event_id: "commission-correction-credit" },
    { transaction_id: "example-commission-correction-debit", transaction_date: "2026-11-09", transaction_type: "monthly_adda_commission_correction_reversal_debit", signed_amount: -3000, source_commission_event_id: "commission-correction-debit" },
    { transaction_id: "example-withdrawal", transaction_date: "2026-11-10", transaction_type: "owner_withdrawal", signed_amount: -435000 },
  ],
});
const exampleMovement = calculateOwnerMovementBreakdown(reconciliationExample);
assert.equal(exampleMovement.recordedChakkarCredits, 510200);
assert.equal(exampleMovement.verifiedLinkedChakkarCredits, 510200);
assert.equal(exampleMovement.recordedVoucherAdjustmentNet, -86000, "Voucher adjustment and reversal rows retain signed recorded net effect");
assert.equal(exampleMovement.verifiedLinkedVoucherAdjustmentNet, -86000);
assert.equal(exampleMovement.commissionNet, -10000, "commission charges, reversal, reissue, increase and decrease net by signed ledger amounts");
assert.equal(exampleMovement.actualWithdrawals, 435000);
assert.equal(exampleMovement.periodMovement, -20800);
assert.equal(reconciliationExample.closing.summary.opening_balance + exampleMovement.periodMovement, reconciliationExample.closing.summary.closing_balance);
const exampleOwnerTotals = aggregateOwnerTotals([reconciliationExample]);
assert.equal(exampleOwnerTotals.commissionNet, -10000);
assert.equal(exampleOwnerTotals.recordedVoucherAdjustmentNet, -86000);
assert.equal(exampleOwnerTotals.verifiedLinkedVoucherAdjustmentNet, -86000);
assert.equal(exampleOwnerTotals.actualWithdrawals, 435000);
assert.equal(exampleOwnerTotals.closing, -20800, "example closing remains the saved authoritative balance");
assert.equal(exampleOwnerTotals.payable, 0);
assert.equal(exampleOwnerTotals.receivable, 20800, "negative closing remains separately receivable");
const exampleOwnerGroup = groupOwnersByCurrentName([reconciliationExample])[0];
assert.equal(exampleOwnerGroup.commissionNet, -10000);
assert.equal(exampleOwnerGroup.recordedVoucherAdjustmentNet, -86000);
assert.equal(exampleOwnerGroup.verifiedLinkedVoucherAdjustmentNet, -86000);
assert.equal(exampleOwnerGroup.unclassifiedMovement, 0);
assert.deepEqual(calculateEarningsReconciliation([reconciliationExample]), {
  settlementEarnings: 424200,
  recordedChakkarCredits: 510200,
  verifiedLinkedChakkarCredits: 510200,
  chakkarSourceLinkIssue: null,
  differenceBeforeVoucherAdjustments: -86000,
  recordedVoucherAdjustmentNet: -86000,
  verifiedLinkedVoucherAdjustmentNet: -86000,
  voucherAdjustmentSourceLinkIssue: null,
  remainingDifference: 0,
}, "verified Voucher adjustments explain the visible difference without changing closing");
const missingVoucherSource = {
  ...reconciliationExample,
  statement: {
    ...reconciliationExample.statement,
    transactions: reconciliationExample.statement.transactions.map((transaction) =>
      transaction.transaction_id === "example-voucher-original" ? { ...transaction, source_adjustment_id: null } : transaction,
    ),
  },
};
const missingVoucherReconciliation = calculateEarningsReconciliation([missingVoucherSource]);
assert.equal(missingVoucherReconciliation.recordedVoucherAdjustmentNet, -86000, "missing source IDs do not hide recorded ledger rows");
assert.equal(missingVoucherReconciliation.verifiedLinkedVoucherAdjustmentNet, null, "unlinked Voucher activity is unavailable instead of guessed");
assert.equal(missingVoucherReconciliation.voucherAdjustmentSourceLinkIssue, "missing_source_id");
assert.equal(missingVoucherReconciliation.verifiedLinkedChakkarCredits, 510200, "Voucher link issues do not hide independently verified Chakkar links");
assert.equal(calculateEarningsReconciliation([missingVoucherSource]).remainingDifference, null);

const rowsWithoutLinks = makeBundle({
  id: "recorded-without-links",
  chakkars: [{ settlement_id: "settlement-without-link", source_type: "bilty", chakkar_date: "2026-11-01", vehicle_freight: 500000, total_expenses: 75800, net_vehicle_amount: 424200, breakdown_status: "RECONCILED", diesel: 0, workshop: 0, tyre: 0, oil: 0, driver: 0, other: 75800 }],
  monthlySummary: { count: 1, freight: 500000, expenses: 75800, net: 424200 },
  closingSummary: { opening: 0, movement: 424200, closing: 424200, commission: 0, ownerWithdrawals: 0, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 },
  transactions: [
    { transaction_id: "unlinked-chakkar", transaction_date: "2026-11-01", transaction_type: "chakkar_net_credit", signed_amount: 510200, source_settlement_id: null },
    { transaction_id: "unlinked-voucher-a", transaction_date: "2026-11-02", transaction_type: "voucher_adjustment_expense", signed_amount: -85000, source_adjustment_id: null },
    { transaction_id: "unlinked-voucher-b", transaction_date: "2026-11-03", transaction_type: "voucher_adjustment_expense", signed_amount: -1000, source_adjustment_id: null },
  ],
});
const unlinkedMovement = calculateOwnerMovementBreakdown(rowsWithoutLinks);
assert.equal(unlinkedMovement.recordedChakkarCredits, 510200);
assert.equal(unlinkedMovement.recordedVoucherAdjustmentNet, -86000);
assert.equal(unlinkedMovement.verifiedLinkedChakkarCredits, null);
assert.equal(unlinkedMovement.verifiedLinkedVoucherAdjustmentNet, null);
assert.equal(unlinkedMovement.unclassifiedMovement, 0, "recorded signed amounts remain fully reconcilable without treating references as verified links");
const unlinkedReconciliation = calculateEarningsReconciliation([rowsWithoutLinks]);
assert.equal(unlinkedReconciliation.recordedChakkarCredits, 510200);
assert.equal(unlinkedReconciliation.recordedVoucherAdjustmentNet, -86000);
assert.equal(unlinkedReconciliation.verifiedLinkedChakkarCredits, null);
assert.equal(unlinkedReconciliation.verifiedLinkedVoucherAdjustmentNet, null);
assert.equal(unlinkedReconciliation.differenceBeforeVoucherAdjustments, null);

const duplicateSourceLinks = makeBundle({
  id: "duplicate-source-links",
  chakkars: [{ settlement_id: "duplicate-settlement", source_type: "bilty", chakkar_date: "2026-11-01", vehicle_freight: 20, total_expenses: 0, net_vehicle_amount: 20, breakdown_status: "RECONCILED", diesel: 0, workshop: 0, tyre: 0, oil: 0, driver: 0, other: 0 }],
  monthlySummary: { count: 1, freight: 20, expenses: 0, net: 20 },
  closingSummary: { opening: 0, movement: 20, closing: 20, commission: 0, ownerWithdrawals: 0, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 },
  transactions: [
    { transaction_id: "duplicate-row-a", transaction_date: "2026-11-01", transaction_type: "chakkar_net_credit", signed_amount: 10, source_settlement_id: "same-source" },
    { transaction_id: "duplicate-row-b", transaction_date: "2026-11-02", transaction_type: "chakkar_net_credit", signed_amount: 10, source_settlement_id: "same-source" },
  ],
});
const duplicateSourceBreakdown = calculateOwnerMovementBreakdown(duplicateSourceLinks);
assert.equal(duplicateSourceBreakdown.recordedChakkarCredits, 20, "duplicate links do not hide recorded transaction amounts");
assert.equal(duplicateSourceBreakdown.verifiedLinkedChakkarCredits, null);
assert.equal(duplicateSourceBreakdown.chakkarSourceLinkIssue, "duplicate_source_id");

const ownerStatementMigrations = [
  "../supabase/migrations/202610090001_owner_gari_custom_period_reconciliation.sql",
  "../supabase/migrations/202610100002_manual_voucher_phase2a.sql",
  "../supabase/migrations/202610140002_manual_voucher_adjustments.sql",
].map((relativePath) => fs.readFileSync(path.join(__dirname, relativePath), "utf8")).join("\n");
assert.match(ownerStatementMigrations, /'source_settlement_id',\s*visible_row\.source_settlement_id/, "existing statement RPC projects saved Bilty settlement IDs");
assert.match(ownerStatementMigrations, /'source_manual_settlement_id',\s*settlement\.id/, "existing statement RPC maps Manual Chakkar source IDs");
assert.match(ownerStatementMigrations, /'source_adjustment_id',\s*visible_row\.source_adjustment_id/, "existing statement RPC projects saved Voucher adjustment IDs");
assert.match(ownerStatementMigrations, /'source_manual_adjustment_id',\s*adjustment\.id/, "existing statement RPC maps Manual Voucher adjustment IDs");

const reportComponent = fs.readFileSync(path.join(__dirname, "../src/components/reports/VehicleOwnerSummary.tsx"), "utf8");
const literalSummaryLabels = Array.from(reportComponent.matchAll(/bilingualLabel\("([^"]+)"\)/g), (match) => match[1]);
for (const language of ["en", "ur"]) {
  const reportTranslations = translationModule.exports.translations[language].reports.vehicleOwnerSummary;
  for (const key of [...literalSummaryLabels, "table.diesel", "table.workshop", "table.tyre", "table.oil", "table.driver", "table.other", "breakdown.complete", "breakdown.partial", "breakdown.unavailable"]) {
    const value = key.split(".").reduce((node, part) => node && node[part], reportTranslations);
    assert.equal(typeof value, "string", `${language} print label ${key} must resolve instead of rendering a raw key`);
  }
}
assert.match(reportComponent, /amountValue\(values\.expenses\),\s*printableOptionalAmount\(breakdown\.unallocated/, "expense print totals continue to use the saved authoritative expense amount");
assert.match(reportComponent, /sourceStatus\(ownerTotals\.chakkarSourceLinkIssue,\s*ownerTotals\.voucherAdjustmentSourceLinkIssue,\s*true\)/, "only the filtered report total repeats a clean source-link status");
const sharedPrintRenderer = fs.readFileSync(path.join(__dirname, "../src/components/print/ModuleTransportPrintDocument.tsx"), "utf8");
assert.match(sharedPrintRenderer, /module-print-summary-totals[\s\S]*summaryTotalRows\.map[\s\S]*presentation\.tables/, "Vehicle & Owner Summary totals render before detail tables");
assert.match(sharedPrintRenderer, /presentation\.layoutVariant !== "vehicle_owner_summary" && presentation\.totals\?\.length/, "end-of-document totals remain for other print types but are not repeated for this report");
assert.match(sharedPrintRenderer, /module-print-summary-total-row\{[^}]*break-inside:avoid;page-break-inside:avoid/, "summary card rows stay together across page breaks");

const ownerGroups = groupOwnersByCurrentName(reports);
assert.equal(ownerGroups.length, 1, "vehicles group by their saved current owner name");
assert.equal(ownerGroups[0].closing, 60);
const noOwnerA = makeBundle({ id: "v4", owner: null, chakkars: [], monthlySummary: { count: 0, freight: 0, expenses: 0, net: 0 }, closingSummary: { opening: 0, movement: 0, closing: 0, commission: 0, ownerWithdrawals: 0, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 }, transactions: [] });
const noOwnerB = makeBundle({ id: "v5", owner: null, chakkars: [], monthlySummary: { count: 0, freight: 0, expenses: 0, net: 0 }, closingSummary: { opening: 0, movement: 0, closing: 0, commission: 0, ownerWithdrawals: 0, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 }, transactions: [] });
assert.equal(groupOwnersByCurrentName([noOwnerA, noOwnerB]).length, 2, "vehicles without an owner name are not merged into an invented owner");

const partialBreakdown = reconcileExpenseBreakdown({ source_type: "manual", breakdown_status: "RECONCILED", diesel: 0, workshop: 0, tyre: 0, oil: 0, driver: 20, other: 10 }, 100);
assert.equal(partialBreakdown.status, "partial", "known categories below saved expenses are identified as partial");
assert.equal(partialBreakdown.unallocated, 70, "verified remainder is shown as unallocated, not added to a named category");
assert.deepEqual(expenseCategoriesForPrint(partialBreakdown).map(({ category }) => category), ["diesel", "workshop", "tyre", "oil", "driver", "other"], "partial known breakdown keeps its recorded zero categories visible alongside the remainder");
const completeBreakdown = reconcileExpenseBreakdown({ breakdown_status: "RECONCILED", diesel: 0, workshop: 0, tyre: 0, oil: 0, driver: 5, other: 0 }, 5);
assert.equal(completeBreakdown.status, "complete");
assert.deepEqual(expenseCategoriesForPrint(completeBreakdown), [{ category: "driver", amount: 5 }], "complete print breakdown omits zero categories and preserves its nonzero amount");
const allZeroBreakdown = reconcileExpenseBreakdown({ breakdown_status: "RECONCILED", diesel: 0, workshop: 0, tyre: 0, oil: 0, driver: 0, other: 0 }, 0);
assert.equal(allZeroBreakdown.status, "complete");
assert.deepEqual(expenseCategoriesForPrint(allZeroBreakdown), [], "complete all-zero breakdown can use the concise translated status row");
assert.equal(reconcileExpenseBreakdown({ breakdown_status: "SNAPSHOT_MISMATCH", diesel: 5 }, 10).status, "unavailable", "mismatched snapshots remain unavailable");
assert.equal(reconcileExpenseBreakdown({ breakdown_status: "RECONCILED", diesel: null, workshop: 0, tyre: 0, oil: 0, driver: 0, other: 0 }, 10).status, "unavailable", "missing category is not converted to zero");
assert.equal(reconcileExpenseBreakdown({ breakdown_status: "RECONCILED", diesel: 8, workshop: 0, tyre: 0, oil: 0, driver: 0, other: 0 }, 5).status, "unavailable", "category amounts above the authoritative total are not normalized");
assert.deepEqual(expenseCategoriesForPrint({ status: "unavailable", categories: null, unallocated: null }), [], "unavailable breakdown has no fabricated zero categories");
assert.match(fs.readFileSync(path.join(__dirname, "../src/components/reports/VehicleOwnerSummary.tsx"), "utf8"), /expenseCategoriesForPrint\(breakdown\)/, "print adapter uses zero-row presentation selection");
assert.match(fs.readFileSync(path.join(__dirname, "../src/components/print/ModuleTransportPrintDocument.tsx"), "utf8"), /module-print-table-section[\s\S]*break-after:avoid[\s\S]*break-before:avoid[\s\S]*display:table-header-group/, "report print keeps table headings with tables and repeats table headers");

assert.equal(canViewVehicleOwnerSummary("adda_admin", true, "adda-a", "adda-a"), true);
assert.equal(canViewVehicleOwnerSummary("adda_admin", true, "adda-a", "adda-b"), false);
assert.equal(canViewVehicleOwnerSummary("adda_admin", false, "adda-a", "adda-a"), false);
assert.equal(canViewVehicleOwnerSummary("operator", true, "adda-a", "adda-a"), false);
assert.equal(canViewVehicleOwnerSummary("super_admin", true, null, null), false, "Super Admin needs an explicit Adda");
assert.equal(canLoadVehicleOwnerSummary("super_admin", null, "adda-b"), true);
assert.equal(canLoadVehicleOwnerSummary("operator", "adda-a", "adda-a"), false);

assert.deepEqual(buildReportPeriodArgs({ mode: "month", month: "2026-11" }), { month: "2026-11-01", from: null, to: null });
assert.deepEqual(buildReportPeriodArgs({ mode: "custom", from: "2024-02-29", to: "2024-03-01" }), { month: null, from: "2024-02-29", to: "2024-03-01" }, "custom dates remain date-only and inclusive at RPC boundaries");
assert.throws(() => buildReportPeriodArgs({ mode: "custom", from: "2026-03-02", to: "2026-03-01" }));
assert.throws(() => buildReportPeriodArgs({ mode: "custom", from: "2026-02-30", to: "2026-03-01" }));
assert.throws(() => buildReportPeriodArgs({ mode: "custom", from: "2026-03-01", to: "" }));
assert.throws(() => buildReportPeriodArgs({ mode: "month", month: "2026-13" }));

const duplicate = { ...bilty, monthly: { ...bilty.monthly, chakkars: [...bilty.monthly.chakkars, { ...bilty.monthly.chakkars[0] }] } };
assert.throws(() => validateVehicleBundle(bilty.vehicle, "adda-a", duplicate.monthly, bilty.closing, bilty.statement), /more than once/);
assert.throws(() => validateVehicleBundle(bilty.vehicle, "adda-b", bilty.monthly, bilty.closing, bilty.statement), /different vehicle or Adda/);
assert.throws(() => validateVehicleBundle(bilty.vehicle, "adda-a", null, bilty.closing, bilty.statement), /incomplete result/);
assert.throws(() => validateVehicleBundle(bilty.vehicle, "adda-a", { ...bilty.monthly, chakkars: [{ settlement_id: "unknown", source_type: "unrecognized" }] }, bilty.closing, bilty.statement), /unsupported saved source type/);
assert.throws(() => validateVehicleBundle(bilty.vehicle, "adda-a", bilty.monthly, bilty.closing, { ...bilty.statement, transactions: [{ transaction_id: "bad-type", transaction_type: "unknown_type", signed_amount: 0 }] }), /unsupported saved type/);
assert.throws(() => assertUniqueVehicleBundles([bilty, { ...bilty, closing: bilty.closing }]), /more than once/);

const longRows = Array.from({ length: 1500 }, (_, index) => ({ settlement_id: `s-${index}`, source_type: "bilty", chakkar_date: "2026-11-01" }));
const longBundle = makeBundle({ id: "long", chakkars: longRows, monthlySummary: { count: 1500, freight: 1500, expenses: 0, net: 1500 }, closingSummary: { opening: 0, movement: 0, closing: 0, commission: 0, ownerWithdrawals: 0, gariWithdrawals: 0, voucherAdjustments: 0, manualDebits: 0 }, transactions: [] });
assert.equal(longBundle.monthly.chakkars.length, 1500, "long report arrays are retained in full");
assert.equal(aggregateVehicleTotals([longBundle]).chakkars, 1500);

console.log("PASS: Vehicle & Owner Summary signed categories, Voucher reconciliation, expense residuals, translations, periods, access gates, deduplication, and long results");

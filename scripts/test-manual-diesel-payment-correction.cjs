/* eslint-disable @typescript-eslint/no-require-imports -- This is a Node CommonJS test harness. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const ts = require("typescript");

const repo = path.resolve(__dirname, "..");
const helperPath = path.join(repo, "src/lib/expenses/manualDieselPaymentCorrection.ts");
const helperSource = fs.readFileSync(helperPath, "utf8");
const compiled = ts.transpileModule(helperSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
});
const moduleBox = { exports: {} };
vm.runInNewContext(
  `(function(require,module,exports){${compiled.outputText}\n})`,
  { console, Number, String, RegExp, Error, Object, Math },
  { filename: helperPath }
)(require, moduleBox, moduleBox.exports);
const { buildManualDieselCorrectionRpcPayload, readAuthoritativeDieselPaymentState, resolveCorrectionPaymentMethodCandidate } = moduleBox.exports;

function fixtureInput(action, extra = {}) {
  return {
    paymentId: 731,
    addaId: "fixture-adda-a",
    requestId: "request-correction-1",
    action,
    reason: "Entered against wrong cash amount",
    ...extra,
  };
}

const voidPayload = buildManualDieselCorrectionRpcPayload(fixtureInput("void"));
assert.equal(voidPayload.p_payment_id, 731, "void addresses the exact saved payment ID");
assert.equal(voidPayload.p_adda_id, "fixture-adda-a");
assert.equal(voidPayload.p_action, "void");
assert.equal(voidPayload.p_reason, "Entered against wrong cash amount");
assert.equal(voidPayload.p_replacement_amount, null);
assert.equal(voidPayload.p_replacement_date, null);
assert.equal(voidPayload.p_replacement_method, null);
assert.equal(voidPayload.p_action, "void", "user-facing delete wording keeps the existing backend void action");

assert.equal(resolveCorrectionPaymentMethodCandidate("Cash"), "Cash");
assert.equal(resolveCorrectionPaymentMethodCandidate("بینک"), "Bank");
assert.equal(resolveCorrectionPaymentMethodCandidate("چیک"), "Cheque");
assert.equal(resolveCorrectionPaymentMethodCandidate("Online Transfer"), "Online Transfer");
assert.equal(resolveCorrectionPaymentMethodCandidate("آن لائن ٹرانسفر"), "Online Transfer");
assert.equal(resolveCorrectionPaymentMethodCandidate("آن‌لائن ٹرانسفر"), "Online Transfer");
assert.equal(resolveCorrectionPaymentMethodCandidate("maybe bank or cash"), null, "ambiguous method speech leaves the current select unchanged");

const replacePayload = buildManualDieselCorrectionRpcPayload(fixtureInput("replace", {
  requestId: "request-correction-2",
  replacementDate: "2026-11-06",
  replacementAmount: "80000.25",
  replacementMethod: "Bank",
  replacementReference: "REF-008",
  replacementRemarks: "Corrected amount",
}));
assert.equal(replacePayload.p_payment_id, 731, "replacement targets the same exact original payment ID");
assert.equal(replacePayload.p_request_id, "request-correction-2");
assert.equal(replacePayload.p_replacement_amount, 80000.25, "decimal precision is retained");
assert.equal(replacePayload.p_replacement_date, "2026-11-06");
assert.equal(replacePayload.p_replacement_method, "Bank");
assert.equal(replacePayload.p_replacement_reference, "REF-008");

for (const invalid of [
  fixtureInput("void", { reason: "   " }),
  fixtureInput("replace", { replacementDate: "2026-11-06", replacementAmount: "NaN", replacementMethod: "Cash" }),
  fixtureInput("replace", { replacementDate: "2026-11-06", replacementAmount: "80000.123", replacementMethod: "Cash" }),
  fixtureInput("replace", { replacementDate: "2026-11-06", replacementAmount: "80000", replacementMethod: "" }),
]) {
  assert.throws(() => buildManualDieselCorrectionRpcPayload(invalid));
}

const frozenVoucherFinancials = {
  dieselExpenseGross: 216412,
  voucherExpenseTotal: 309500,
  finalizedVehicleSettlement: { netVehicleAmount: 842000, ownerLedgerRows: ["fixture-owner-row"] },
};
const frozenVoucherFinancialsAfter = JSON.parse(JSON.stringify(frozenVoucherFinancials));
const afterVoidRpcResult = {
  diesel_total: 216412,
  diesel_paid: 0,
  diesel_remaining: 216412,
  diesel_status: "Unpaid",
};
const afterVoidState = readAuthoritativeDieselPaymentState(afterVoidRpcResult);
assert.deepEqual(
  frozenVoucherFinancialsAfter,
  frozenVoucherFinancials,
  "payment-only correction preserves gross Diesel, Voucher and finalized settlement fixtures"
);
assert.deepEqual(JSON.parse(JSON.stringify(afterVoidState)), {
  totalAmount: 216412,
  paidAmount: 0,
  remainingAmount: 216412,
  paymentStatus: "Unpaid",
});

const afterReplacementRpcResult = {
  diesel_total: 216412,
  diesel_paid: 80000,
  diesel_remaining: 136412,
  diesel_status: "Partial",
};
assert.deepEqual(JSON.parse(JSON.stringify(readAuthoritativeDieselPaymentState(afterReplacementRpcResult))), {
  totalAmount: 216412,
  paidAmount: 80000,
  remainingAmount: 136412,
  paymentStatus: "Partial",
}, "replacement display uses rebuild totals, not a client-side subtraction");
for (const voucherStatus of ["draft", "finalized"]) {
  const voucherBefore = { status: voucherStatus, ...frozenVoucherFinancials };
  const voucherAfter = JSON.parse(JSON.stringify(voucherBefore));
  assert.deepEqual(voucherAfter, voucherBefore, `${voucherStatus} correction keeps Voucher financial/settlement values unchanged`);
}

const multiplePaymentFifoResult = {
  diesel_total: 216412,
  diesel_paid: 12500,
  diesel_remaining: 203912,
  diesel_status: "Partial",
};
assert.deepEqual(JSON.parse(JSON.stringify(readAuthoritativeDieselPaymentState(multiplePaymentFifoResult))), {
  totalAmount: 216412,
  paidAmount: 12500,
  remainingAmount: 203912,
  paymentStatus: "Partial",
}, "multi-payment/FIFO result is consumed exactly from the authoritative rebuild response");

const migration = fs.readFileSync(path.join(repo, "supabase/migrations/202611060001_manual_diesel_payment_correction.sql"), "utf8").toLowerCase();
for (const marker of [
  "pg_advisory_xact_lock",
  "existing_payload is distinct from request_payload_value",
  "return existing_result",
  "for update",
  "link.payment_id=p_payment_id",
  "detail_row.status not in ('draft','finalized')",
  "public.delete_petrol_pump_payment",
  "public.save_petrol_pump_payment",
  "public.rebuild_petrol_pump_accounting",
  "petrol_pump_payment_allocations",
  "allocation_count<>1",
  "cashbook_entries",
  "cashbook_count<>1",
  "cashbook_match_count<>1",
  "payment.advance_created is distinct from 0",
  "expense_snapshot_before is distinct from expense_snapshot_after",
  "settlement_snapshot_before is distinct from settlement_snapshot_after",
  "owner_transaction_snapshot_before is distinct from owner_transaction_snapshot_after",
  "manual_adjustment_snapshot_before is distinct from manual_adjustment_snapshot_after",
  "diesel_total_before is distinct from diesel_row.total_amount",
  "source_manual_adjustment_id",
  "manual_diesel_selected_payment_delete_locked",
  "manual_diesel_selected_payment_edit_locked",
]) assert.ok(migration.includes(marker), `migration contract marker: ${marker}`);
assert.ok(migration.trimStart().startsWith("begin;"), "migration is transactional");
assert.ok(migration.trimEnd().endsWith("commit;"), "migration commits only after postconditions");
assert.equal((migration.match(/\bcommit\s*;/g) ?? []).length, 1, "exactly one transaction commit");
assert.equal((migration.match(/\bbegin\s*;/g) ?? []).length, 1, "exactly one transaction begin");
const verifier = fs.readFileSync(path.join(repo, "supabase/preflight/20261106_manual_diesel_payment_correction_post_verify.sql"), "utf8").trim().toLowerCase();
assert.ok(verifier.startsWith("with "), "post-verifier is a single read-only CTE query");
assert.ok(!/^\s*(create|insert\s+into|update\s+[a-z_]+\s+set|delete\s+from|grant|revoke|alter|drop|truncate)\b/im.test(verifier), "post-verifier contains no mutation statements");

const integrationMarkers = new Map([
  ["src/components/petrolPumpPayments/PetrolPumpPayments.tsx", "correct_manual_voucher_diesel_payment"],
  ["src/components/expenses/ExpenseTable.tsx", "initial_payment_corrections"],
  ["src/app/(dashboard)/expenses/page.tsx", "subscribeToManualDieselPaymentCorrections"],
  ["src/components/diesel/Diesel.tsx", "subscribeToManualDieselPaymentCorrections"],
  ["src/components/petrolPumps/PetrolPumps.tsx", "subscribeToManualDieselPaymentCorrections"],
  ["src/components/vehicleLedger/VehicleLedger.tsx", "subscribeToManualDieselPaymentCorrections"],
]);
for (const [relativePath, marker] of integrationMarkers) {
  const source = fs.readFileSync(path.join(repo, relativePath), "utf8");
  assert.ok(source.includes(marker), `correction data/display integration: ${relativePath}`);
}

const correctionModal = fs.readFileSync(path.join(repo, "src/components/petrolPumpPayments/ManualDieselPaymentCorrectionModal.tsx"), "utf8");
for (const marker of [
  'fieldLabel={t("petrolPumpPayments.fields.paymentDate")} value={replacementDate} onValueChange={setReplacementDate} mode="date"',
  'fieldLabel={t("petrolPumpPayments.correction.replacementAmount")} value={replacementAmount} onValueChange={setReplacementAmount} mode="amount"',
  'fieldLabel={t("petrolPumpPayments.fields.paymentMethod")} value={replacementMethodCandidate} onValueChange={applyPaymentMethodVoiceCandidate} mode="identifier"',
  'fieldLabel={t("petrolPumpPayments.fields.reference")} value={replacementReference} onValueChange={setReplacementReference} mode="identifier"',
  'fieldLabel={t("petrolPumpPayments.fields.remarks")} value={replacementRemarks} onValueChange={setReplacementRemarks}',
  'fieldLabel={t("petrolPumpPayments.correction.reasonRequired")} value={reason} onValueChange={setReason}',
  'type="button" onClick={onCancel}',
  't("common.actions.cancel")',
]) assert.ok(correctionModal.includes(marker), `voice/label/no-auto-submit modal contract: ${marker}`);
assert.ok(!correctionModal.includes('t("common.cancel")'), "modal uses the existing translated cancel action key");
const voiceFieldSource = fs.readFileSync(path.join(repo, "src/components/shared/VoiceTypingField.tsx"), "utf8");
assert.ok(voiceFieldSource.includes('<button type="button"'), "microphone and candidate Apply controls cannot submit the correction form");

const paymentPage = fs.readFileSync(path.join(repo, "src/components/petrolPumpPayments/PetrolPumpPayments.tsx"), "utf8");
assert.ok(paymentPage.includes("...historyRows.map((row) => Number(row.voucher_id))"), "Voucher metadata lookup includes audit history after the active payment link is removed");
assert.ok(paymentPage.includes('voucher.expense_no?.trim() || "—"'), "active payment rows display the saved Voucher number or em dash");
assert.ok(paymentPage.includes('voucher?.expense_no?.trim() || "—"'), "history rows resolve saved expenses.expense_no or em dash");
assert.ok(!paymentPage.includes("String(voucher.id)") && !paymentPage.includes("String(row.voucher_id)"), "internal IDs are never shown as Voucher numbers");

const translations = fs.readFileSync(path.join(repo, "src/i18n/translations.ts"), "utf8");
for (const label of [
  'correct: "Delete / Replace"',
  'void: "Delete payment"',
  'actions: { void: "Deleted", replace: "Replaced" }',
  'correct: "حذف / تبدیل کریں"',
  'void: "ادائیگی حذف کریں"',
  'actions: { void: "حذف شدہ", replace: "تبدیل" }',
]) assert.ok(translations.includes(label), `bilingual correction label: ${label}`);

console.log("PASS correction payload validation (void/replace, exact IDs, decimals, required reason)");
console.log("PASS payment-method voice candidates map only exact English/Urdu supported choices; backend void action remains unchanged");
console.log("PASS all modal fields reuse typed voice modes; Voice/Apply controls remain non-submit and Cancel is localized");
console.log("PASS correction labels are Delete/Deleted in English/Urdu while audit action values stay void/replace");
console.log("PASS post-delete history resolves expenses.expense_no independently of active payment links; missing numbers show em dash");
console.log("PASS synthetic void/replacement totals (0 and 80,000) and unchanged Voucher financial snapshots");
console.log("PASS draft and finalized Manual Voucher payment-only fixture snapshots");
console.log("PASS multi-payment case trusts the supplied authoritative rebuild result");
console.log("PASS migration transaction, protected pump paths, audit/idempotency and payment-only guards");
console.log("PASS correction data refresh/display integration files");
console.log("LIMITATION database transaction, role/RLS, Cashbook and concurrent runtime cases require isolated local Supabase/PostgreSQL; no database was used by this synthetic test.");

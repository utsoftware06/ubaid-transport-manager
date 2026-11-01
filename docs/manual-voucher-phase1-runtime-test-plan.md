# Manual Voucher Phase 1 runtime test plan

Run these checks only after manually applying the SQL package in the listed order. This plan does not authorize or perform SQL execution from the application workspace.

## SQL deployment order

1. `supabase/preflight/202610100001_manual_voucher_phase1_preflight.sql` — run first; proceed only if `OVERALL_MANUAL_VOUCHER_PHASE1_PREFLIGHT = PASS` with zero blocking failures.
2. `supabase/migrations/202610100001_manual_voucher_phase1.sql` — user-run forward-only migration.
3. `supabase/preflight/202610100001_manual_voucher_phase1_post_verify.sql` — run after deployment; require `OVERALL_MANUAL_VOUCHER_PHASE1_POST_VERIFY = PASS`.
4. `supabase/preflight/202610100001_manual_voucher_phase1_summary_verify.sql` — compact follow-up grid; require `MANUAL_VOUCHER_PHASE1_SUMMARY_OVERALL = PASS`.

## Browser/runtime scenarios

1. Open Create Voucher and confirm **Bilty Based** is selected by default. Exercise a draft Bilty Voucher create/edit path and verify its Movement Group/Loading, source links, expense items, Cashbook sync, and finalization controls behave as before.
2. Switch to **Manual / Without Bilty**. Confirm the Manual form has Voucher Date, Vehicle, optional Driver, Chakkar Days, Remarks, Outbound, Local, and Return fields; Bilty, Movement Group, Loading, and expense-item/source selectors are absent.
3. Save Manual drafts for: Outbound only, Local only, Return only, multiple Locals, and Outbound + multiple Locals + Return. Verify totals sum each positive amount once and blank, invalid, or non-positive display inputs count as zero.
4. Attempt save without Vehicle, with missing/zero/fractional Chakkar Days, and with no positive freight. Confirm the UI rejects each; also confirm the database RPC independently rejects invalid requests.
5. Select a Driver from a different Adda (for example by a controlled RPC call in a non-production test environment) and confirm the RPC rejects it. Repeat with a Vehicle from another Adda. Do not use production data for negative-ID tests.
6. Reopen a Manual draft, change Vehicle/Driver/Days/Remarks/freight, add/remove Local lines, and save. Confirm the same Voucher ID is updated and freight rows are replaced atomically.
7. Delete a clean Manual draft through the UI. Confirm only its Manual header/detail/freight rows are removed. Verify the RPC refuses archived, settlement-owned, expense-item-bearing, source-linked, or Cashbook-linked rows.
8. Inspect the saved Manual draft: `expenses.voucher_source='manual'`; `loading_id` and `movement_group_id` are NULL; one detail row exists; all saved freight amounts are finite and positive; there is at most one Outbound/Return; Local rows can repeat.
9. In a non-production test environment only, confirm a direct/RPC insert, update, or delete against `expense_items` for a Manual Voucher is rejected by the Manual-only guard trigger.
10. Verify no `expense_items`, Diesel rows, Voucher source links, vehicle settlement, Owner/Gari transaction, or Voucher Cashbook row was created for a new Manual draft. Do not manually insert test accounting rows.
11. Confirm the Manual draft list/detail show Vehicle, optional Driver, Chakkar Days, all freight lines and total; Manual drafts do not offer print/finalize in Phase 1.
12. Test a second fresh Manual Voucher immediately after saving the first. Confirm it creates a distinct Voucher ID (the create RPC receives `p_voucher_id = NULL` after reset).
13. Confirm an existing Bilty Voucher cannot be switched into Manual edit mode and a Manual draft cannot be switched into the Bilty edit flow.

## Phase 1 boundaries

Manual freight is stored only in `manual_voucher_freight_items`; it is not copied into `expense_items`. No settlement, Owner/Gari credit, Cashbook movement, Diesel/Fuel, Voucher finalization, or report integration is part of this phase. Use a disposable non-production tenant for destructive draft-delete tests.

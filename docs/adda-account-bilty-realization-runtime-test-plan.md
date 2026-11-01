# Adda Account Phase 4 — Bilty Margin Realization Runtime Test Plan

Run only after the Phase 4 preflight passes and the migration is applied in the approved environment. Use a test Adda and test Bilties; do not create test records in production unless the business owner has approved them. This phase changes read projections only: it creates no P&L journal rows, Adda Finance settlements, or Cashbook entries.

## Receipt source expectations

- Normal Party/Broker Bilty: `get_bilty_financial_summary(p_bilty_id)` is the authoritative source and must include `advance_bilty` plus effective `party_broker` payments while excluding vehicle-side receipts. The Phase 4 preflight displays the deployed definition for manual confirmation.
- Other Adda receivable Bilty: use the net `other_adda_payment_allocations` for its linked receivable obligation: payment allocations add, reversal allocations subtract. Do not add normal Bilty advance/payment values to this amount.
- Later receipt dates are included in the current-to-date realization of a Bilty whose recognition date is inside the selected date range.

## Base waterfall

Use a recognized positive-margin Bilty with freight Rs. 300,000, vehicle freight Rs. 270,000, and earned margin Rs. 30,000. Check both `get_adda_account_summary_v2` and `get_adda_account_entries_v2` after each receipt state.

| Effective received basis | Earned margin | Realized margin | Pending margin |
| ---: | ---: | ---: | ---: |
| 0 | 30,000 | 0 | 30,000 |
| 150,000 | 30,000 | 0 | 30,000 |
| 270,000 | 30,000 | 0 | 30,000 |
| 280,000 | 30,000 | 10,000 | 20,000 |
| 290,000 | 30,000 | 20,000 | 10,000 |
| 300,000 | 30,000 | 30,000 | 0 |
| 325,000 | 30,000 | 30,000 | 0 |

At every state, total Adda Income remains the full earned amount and `realized + pending = earned`.

## Scenarios

1. Save a Bilty without creating a recognized Loading: no Phase 4 margin projection is returned.
2. Create a new `own_adda` Loading for the test Bilty: existing Phase 3B recognition contributes exactly one Rs. 30,000 earned journal row; Phase 4 reads it.
3. Change effective Party/Broker receipts through the existing Bilty payment flow from Rs. 0 to Rs. 150,000, Rs. 270,000, Rs. 280,000, Rs. 290,000, Rs. 300,000, then above freight. Verify the waterfall table and cap.
4. Record a vehicle-side Bilty payment without changing Party/Broker receipts. Realized margin must not change.
5. Reverse a valid Party/Broker receipt using the existing source flow. Realized margin decreases and pending increases; the earned journal remains unchanged.
6. For `freight_receivable_from='other_adda'`, allocate a payment to the linked Bilty receivable obligation. Verify only net allocations count, including a reversal. Confirm `advance_bilty` and `bilty_payments` are not added to the allocation total.
7. Attempt evidence belonging to another Adda/Other Adda. It must not be included in the selected Adda projection.
8. A zero-margin Loading has no journal row and no realization row.
9. A Bilty Loss remains in total Adda Expenses, returns no realized/pending margin fields, and does not appear as a pending settlement/payable.
10. Filter the Adda ledger by recognition date containing the margin entry, then create a later-dated valid receipt. The included entry shows current-to-date realization even when that receipt date is outside the selected recognition period.
11. Filter a period that excludes the recognition date. The entry and its earned/realized/pending values are excluded from that period.
12. Reconcile summary totals against the ledger for the same recognition date filter: total income remains earned income; pending income replaces the margin's former generic pending amount with the projected pending amount; net profit is unchanged by receipts.
13. Confirm no Adda Finance settlement, P&L journal row, or Cashbook row is created by reads or by recording/reversing a source receipt.
14. Confirm the existing legacy summary and ledger RPCs remain callable for compatibility; the UI uses the Phase 4 v2 read contracts.

## Deployment and rollback

1. Run `supabase/preflight/20261006_adda_account_bilty_realization_preflight.sql` and manually review the live Bilty and Other Adda source definitions/constraints it returns.
2. Apply `supabase/migrations/202610060004_adda_account_bilty_realization.sql` only after preflight contracts match.
3. Run `supabase/preflight/20261006_adda_account_bilty_realization_post_verify.sql` and `supabase/preflight/20261006_adda_account_bilty_realization_summary_verify.sql`.
4. Deploy the UI that calls the v2 read RPCs.
5. Complete the runtime scenarios above with approved test data.

Rollback is a controlled database change: restore the prior UI RPC calls, then remove/revert the three Phase 4 read functions through an approved corrective migration. There are no Phase 4 postings or historical rows to reverse.

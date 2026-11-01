# Adda Account Phase 2 runtime test plan

Run these tests only in a controlled staging environment with test Addas, or in production after an explicitly approved operational test window. Use protected RPCs and unique request UUIDs; never write test rows directly. Do not run tests that create accounting or Cashbook events against live production without approval.

## Deployment sequence

1. Run `supabase/preflight/20261005_adda_account_phase2_preflight.sql` in Supabase SQL Editor and review all labeled result sets. Stop if Phase 1 contracts drift, the new Cashbook reference type already exists, source identities are duplicated, or an object-name collision is reported.
2. Apply `supabase/migrations/202610050002_adda_account_manual_finance.sql` manually.
3. Run `supabase/preflight/20261005_adda_account_phase2_post_verify.sql` and inspect each catalog result set.
4. Run `supabase/preflight/20261005_adda_account_phase2_summary_verify.sql`; require `PHASE_2_OVERALL = PASS` before frontend runtime tests.
5. Use isolated test Adda data to run the cases below, then reconcile every source event, journal row, settlement, and Cashbook reference.

## Test cases and expected evidence

| # | Scenario | Expected result |
|---|---|---|
| 1 | Call `ensure_adda_finance_categories` as Adda Admin for one Adda | Eleven active/manual categories and four system categories are created for that Adda only. No finance postings or Cashbook rows are created. |
| 2 | Retry category provisioning | Returns zero new rows; existing category names and active flags are unchanged; no duplicate `(adda_id, category_code)`. |
| 3 | Call category provisioning as Operator | Authorization denied; category row count remains unchanged. |
| 4 | Post expense Rs. 1,500, paid Rs. 1,500 | One expense source, one full Rs. 1,500 expense journal entry, one settlement, one Cashbook `Cash Out` for Rs. 1,500, pending Rs. 0. |
| 5 | Post expense Rs. 1,500, paid Rs. 0 | One Rs. 1,500 expense source/journal, no settlement or Cashbook entry, pending Rs. 1,500. |
| 6 | Post expense Rs. 1,500, paid Rs. 500 | One Rs. 1,500 expense journal, one Rs. 500 settlement and Cashbook `Cash Out`, pending Rs. 1,000. |
| 7 | Settle the remaining expense by Rs. 500 | No new expense journal; one additional settlement and Cashbook `Cash Out` Rs. 500; pending Rs. 500. |
| 8 | Settle final Rs. 500 | No new expense journal; pending Rs. 0 and status settled/paid. |
| 9 | Attempt an additional Rs. 1 settlement | RPC rejects overpayment; no source, settlement, journal, or Cashbook row is added. |
| 10 | Retry an identical posting/settlement request UUID | Same source/settlement identity is returned; child evidence is validated; no duplicate row is added. |
| 11 | Retry the same request UUID with changed payload | RPC rejects idempotency mismatch; no new accounting or Cashbook row. |
| 12 | Post Other Income Rs. 10,000, received Rs. 0 | One Rs. 10,000 income source/journal; no settlement/Cashbook entry; pending income Rs. 10,000. |
| 13 | Post Other Income Rs. 10,000, received Rs. 4,000 | Full Rs. 10,000 income journal; one Rs. 4,000 settlement and Cashbook `Cash In`; pending income Rs. 6,000. |
| 14 | Receive remaining Rs. 6,000 | No new income journal; Cashbook `Cash In` Rs. 6,000; pending Rs. 0. |
| 15 | Reverse an expense settlement | Original settlement and original Cashbook `Cash Out` remain; one settlement reversal and one opposite Cashbook `Cash In` are appended. Expense recognition is unchanged. |
| 16 | Reverse an income settlement | Original settlement and Cashbook `Cash In` remain; one reversal and opposite Cashbook `Cash Out` are appended. Income recognition is unchanged. |
| 17 | Reverse an original settlement a second time | Rejected; at most one reversal exists for that settlement. |
| 18 | Reverse an entry while settlement net remains non-zero | Rejected with active-settlement guidance; original journal and Cashbook remain untouched. Reverse settlements first. |
| 19 | Reverse a clean unpaid expense | Source reversal and opposite-kind journal reversal are appended; original remains; no Cashbook row is created. |
| 20 | Reverse a clean Other Income entry | Source reversal and opposite-kind journal reversal are appended; original remains; no Cashbook row is created. |
| 21 | Reverse the same journal entry twice | Second reversal is rejected; one reversal source/journal row remains. |
| 22 | Submit a category from another Adda | Rejected by server validation and composite tenant FK; no partial posting. |
| 23 | Submit an employee from another Adda | Rejected; no partial posting. |
| 24 | Adda Admin reads/posts for own Adda and supplies another Adda ID | Own Adda succeeds; another Adda is denied by authoritative helper. |
| 25 | Super Admin opens page without selecting an Adda, then selects one | No finance data or mutation form before selection; selected Adda is sent to protected RPCs and resolved server-side. |
| 26 | Operator opens the page and attempts each write RPC | Reads are tenant-scoped; UI controls are absent and server writes are denied. |
| 27 | Attempt direct browser INSERT/UPDATE/DELETE against the two Phase 2 source tables | Table privileges deny access; append-only triggers also reject unauthorized mutation contexts. |
| 28 | Compare dashboard summary with filtered ledger totals | Active income minus active expenses equals net profit; each direction’s settled and pending amounts reconcile to active journal rows. |
| 29 | Verify Cashbook exact-once identity | Each settlement and reversal has exactly one `reference_type='adda_finance_settlement'` row with `reference_id=settlement.id::text`, correct Adda, amount, date, payment method, and direction. |
| 30 | Inspect immediately after migration, before runtime tests | New source tables contain zero rows; no historical categories or finance postings were backfilled. |

## Reconciliation queries to use during a staging test

For each test request, compare the returned source or settlement UUID with:

- `adda_expenses` / `adda_other_income` source event and its `request_id`;
- `adda_account_entries` by `source_type` and `source_id`;
- `adda_finance_settlements` by `request_id`, `account_entry_id`, and reversal identity;
- `cashbook_entries` by `reference_type='adda_finance_settlement'` and `reference_id=settlement.id::text`.

Confirm Cashbook totals contain only actual paid/received amounts. The posting RPCs do not create Cashbook rows for unpaid expenses or earned-but-unreceived income, and reversals append opposite movements instead of editing or deleting prior Cashbook rows.

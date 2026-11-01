# Manual Voucher Diesel / Fuel Runtime Test Plan

Run this plan only after the preflight passes and the migration is deployed. Use a non-production test Adda and a draft Manual Voucher with a vehicle that belongs to it.

## Deployment order

1. Run `supabase/preflight/20261011_manual_voucher_diesel_preflight.sql` and confirm `MANUAL_VOUCHER_DIESEL_PREFLIGHT_OVERALL = PASS`.
2. Apply `supabase/migrations/202610110006_manual_voucher_diesel_integration.sql` once.
3. Run `supabase/preflight/20261011_manual_voucher_diesel_post_verify.sql` and confirm `MANUAL_VOUCHER_DIESEL_POST_VERIFY_OVERALL = PASS`.
4. Run `supabase/preflight/20261011_manual_voucher_diesel_summary_verify.sql` and confirm `MANUAL_VOUCHER_DIESEL_OVERALL = PASS`.

These SQL files are deployment artifacts only. No production SQL was run while preparing them.

## Runtime cases

1. Create a Manual Voucher draft without any Loading, Bilty, or Movement Group. Add general freight and one Diesel entry. Confirm the Diesel entry saves through `save_manual_voucher_diesel_entry`, has `loading_id IS NULL`, the Manual Voucher context and matching vehicle, and one linked `Fuel` expense item. It begins Unpaid; the Voucher does not accept a direct paid-amount override.
2. Enter 100 liters at Rs. 1,000 per liter. Confirm Diesel total and Fuel expense are Rs. 100,000 and Manual Voucher expenses/net use that amount exactly once.
3. Retry the same create request after a simulated client retry. Confirm the same Diesel entry is returned and no second expense item appears. Reuse the request ID with changed fields and confirm the server rejects the conflict.
4. Create another Diesel entry on the same Voucher with a new request ID. Confirm both entries and both unique Fuel expense items are included in total expenses once.
5. Select a pump already associated with a different Adda's Diesel source and confirm Manual create is rejected. Select a pump with an established source in the same Adda and confirm it succeeds. For a pump with no Diesel source history, confirm its first source row establishes the pump's Adda context; a later row from another Adda must then be rejected.
6. Try a vehicle from another Adda, a Voucher from another Adda, a finalized Voucher, and an archived Voucher. Confirm every write is rejected server-side.
7. Edit liters/rate/remarks while Draft and confirm the existing Diesel ID and request identity stay the same, its Fuel expense amount resyncs, and Manual total expenses/net refresh.
8. Attach a real petrol pump payment of Rs. 30,000 to a Rs. 100,000 Diesel balance through the existing pump payment workflow. Confirm allocation, Diesel paid/remaining values, and exactly one Rs. 30,000 Cashbook OUT follow the existing pump contract. The Manual Voucher writer itself must create no Cashbook row and cannot set paid amount directly.
9. Finalize the Manual Voucher. Confirm the settlement includes Diesel once, net vehicle earnings decrease by the Diesel expense, and exactly one existing Manual Owner/Gari net projection and Monthly Hisab source are created.
10. Try editing the Diesel source after finalization. Confirm the Manual edit RPC rejects it. A later real pump payment may still update only Diesel payment fields through the existing allocation rebuild.
11. Confirm Bilty Voucher Diesel still requires its original Loading and retains its current pump payment, allocation, and Cashbook behavior.
12. Inspect Manual Voucher details and print. Confirm the Diesel pump, date, liters, rate, total, paid/remaining, payment status, and slip number appear with the correct Diesel/Fuel expense.
13. Confirm no fake Loading, Bilty, or Movement Group was created and no generic Manual Voucher Cashbook entry was written.
14. On a fresh pump and same test Adda, create Manual Diesel first and then a Bilty Diesel row. Confirm both are accepted and the authenticated Bilty INSERT policy remains in use.
15. On a different fresh pump and same test Adda, create Bilty Diesel first and then Manual Diesel. Confirm both are accepted.
16. For each insertion order, attempt the second row from another Adda using the same pump. Confirm it is rejected server-side.
17. In a disposable non-production fixture, create unresolved or mixed-Adda Diesel history for one pump, then attempt either context. Confirm the shared pump resolver returns no Adda and both new Bilty and Manual sources are rejected. Do not create or repair such fixtures in production.

## Expected accounting

For Rs. 400,000 freight with Diesel Rs. 100,000, Workshop Rs. 20,000, Oil Rs. 10,000, Tyre Rs. 30,000, and plain expenses Rs. 10,000, total expense is Rs. 170,000 and finalized Manual net is Rs. 230,000. Diesel supplier payment affects the existing pump payable/allocation and Cashbook only for actual payment; it does not create another Voucher expense or Owner/Gari posting.

## Scope note

The deployed petrol pump model has no independent Adda identity. Tenant identity is derived from Diesel source rows: Bilty rows resolve through Loading to Booking, and Manual rows resolve through their Manual Voucher detail. The Bilty INSERT helper, Manual source guard, payment validator, and allocator must all use the same fail-closed pump-history resolver. A previously unused pump is assigned its first Adda context by its first authorized Diesel source row; subsequent sources for that pump must resolve to the same Adda. Draft deletion of a Manual Voucher with a linked Diesel row remains blocked by the existing safe-delete path until a source-aware delete workflow is designed.

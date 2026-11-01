# Adda Account Phase 3B — Loading Margin Runtime Test Plan

Run the migration first, then both read-only verifiers. Run these tests with test tenants/records in a non-production environment or an approved disposable Adda. The implementation does not backfill existing Loadings and does not infer cash receipts from Bilty values.

## Pre-test verification

1. Run `supabase/preflight/20261006_adda_account_loading_margin_post_verify.sql` immediately after migration.
2. Run `supabase/preflight/20261006_adda_account_loading_margin_summary_verify.sql`; require `PHASE_3B_OVERALL = PASS`.
3. Confirm the Loading form now calls `create_loading_with_adda_margin`, direct authenticated Loading INSERT/DELETE privileges are revoked, and `loadings_sync_advance_cashbook` remains enabled.
4. Record the pre-test counts of `adda_loading_margin_events`, `adda_account_entries` where `source_type IN ('bilty_margin','bilty_loss')`, and Cashbook references created by the existing Loading advance path.

## Recognition and exact-once

1. Save a Bilty with freight Rs.300,000 and vehicle freight Rs.270,000 without creating a Loading. Expected: no Adda Account journal entry and no recognition event.
2. Create its first Loading through the Loading UI. Expected: one `bilty_margin` income journal entry for Rs.30,000, with `source_id = loading.id::text`, the same `booking_id`, `loading_id`, selected `vehicle_id`, system category `bilty_margin`, and one recognition event. The existing Loading advance Cashbook behavior remains independent.
3. Retry the same RPC with the same request ID and identical payload. Expected: the existing Loading ID is returned; no second Loading, event, or journal row appears.
4. Retry with a new request ID but the same Booking and identical Loading payload. Expected: the existing recognized Loading is returned; no duplicate journal row appears.
5. Retry the Booking with a changed Loading payload, or reuse a request ID with changed values. Expected: the request is rejected and accounting rows remain unchanged.
6. Repeat with an own vehicle and with another owner’s vehicle that is represented by a valid same-Adda vehicle record. Expected: both create the same Rs.30,000 margin entry.
7. Create a Loading where freight and vehicle freight are equal. Expected: one recognition event with `margin_amount = 0`, no P&L journal row, and no Cashbook row created by margin recognition.
8. Create a Bilty with freight Rs.250,000 and vehicle freight Rs.270,000, then create its Loading. Expected: one `bilty_loss` expense of Rs.20,000, not negative income, and no margin Cashbook row.

## Tenant and role guards

9. Attempt to create a Loading for a Booking with `adda_id IS NULL`. Expected: `LOADING_MARGIN_BOOKING_ADDA_REQUIRED`; no Loading or journal/event rows.
10. Attempt to use another Adda’s Booking, Vehicle, or Driver. Expected: tenant mismatch rejection; no cross-Adda Loading or journal row.
11. As an Operator with normal Loading permission, create an eligible Loading. Expected: the protected create succeeds and the journal is posted server-side. Direct table INSERT remains denied.
12. As an unauthorized user, call the create, delete, reverse, or detail RPC with another Adda’s ID. Expected: authorization failure and no data change.

## Post-recognition locks and deletion

13. After a non-zero margin Loading exists, attempt to update `bookings.freight`. Expected: `BILTY_FINANCIAL_FIELDS_LOCKED_AFTER_LOADING_MARGIN` and no row change.
14. Attempt to update `bookings.vehicle_freight`. Expected: the same rejection.
15. Attempt to move the recognized Loading to another Booking. Expected: `LOADING_MARGIN_BOOKING_LINK_LOCKED`.
16. Attempt to delete the recognized Loading from the UI or table API. Expected: delete is rejected before its Loading items are removed; the UI reports that the recognized Loading cannot be deleted.
17. Delete an unrecognized test Loading through `delete_loading_if_unrecognized`. Expected: its items and Loading are removed atomically, and existing Loading Cashbook delete-capture behavior remains intact.

## Controlled margin reversal

18. Call `reverse_loading_adda_margin` as an authorized Adda Admin/Super Admin with a reason and a new request ID. Expected: the recognition event and original journal row remain; one reversal event is appended; for non-zero margin one opposite-kind journal row references the original through `reverses_entry_id`; no Cashbook row is created.
19. Retry with the same request ID and identical date/reason. Expected: the existing reversal event ID is returned with no duplicate reversal.
20. Try another reversal request for the same recognition. Expected: `LOADING_MARGIN_ALREADY_REVERSED`.
21. Reverse a zero-margin recognition. Expected: a reversal event is appended without creating a zero-value journal row.
22. Try to edit the Booking’s freight after reversal. Expected: financial fields remain locked because recognition history is append-only.

## Other Adda and Cashbook separation

23. Create a Bilty whose `freight_receivable_from = 'other_adda'`, then create its Loading. Expected: the existing Phase 3C full-freight Other Adda obligation remains unchanged; this Adda receives only its calculated margin or loss.
24. Compare Cashbook before/after a zero-advance margin Loading. Expected: no Cashbook row for `bilty_margin` or `bilty_loss`; any actual Loading advance continues through the existing Loading Cashbook trigger exactly once.
25. Confirm journal source rows use only `loading.id::text`, and no `other_adda_transactions` or Phase 3B payment/allocation rows were created by margin recognition.

## Adda Account UI and reconciliation

26. Confirm summary `bilty_margin_income` increases by positive recognized margin and `bilty_loss_expense` is included in `total_expense`; `net_profit = total_income - total_expense` remains consistent.
27. Confirm ledger rows show Bilty number, Loading number/ID, vehicle, route when available, and `Earned` / `Recognized Loss` status. Settled and pending cells remain blank for these entries until the future realization phase.
28. Open the source action and verify it navigates to the existing `/loading-details/[id]` route.
29. Confirm manual expense categories do not offer `bilty_margin` or `bilty_loss`.

## Historical cutover

30. Before/after migration, compare existing Loading IDs and Adda journal rows. Expected: existing Loadings (including IDs at or below the verified high-water mark) remain untouched, no historical journal entries are created, and the new event table starts empty. Recognition begins only for Loading INSERTs after the protected path is deployed.

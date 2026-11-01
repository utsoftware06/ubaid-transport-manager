# Bilty-to-Loading one-click runtime test plan

This change uses a controlled two-step workflow. `save_bilty_with_items_v2` remains the authoritative Bilty save. After it returns the Booking UUID, the client calls `create_loading_from_bilty(p_adda_id, p_booking_id, p_request_id)`. The Loading RPC locks and validates the saved Booking, then either reuses its existing Loading or inserts one Loading and its item rows in one transaction. The existing Phase 3B Loading trigger remains the only Adda Margin/Loss writer.

Do not run the migration until the read-only preflight passes. The migration is prospective and contains no historical Loading scan or backfill.

## Deployment order

1. Run `supabase/preflight/20261006_bilty_loading_one_click_preflight.sql` in Supabase SQL Editor and retain every result row. Stop if any mandatory row is `FAIL`. A nonzero historical Loading count is only an observation; it is not permission to backfill.
2. Deploy `supabase/migrations/202610060003_bilty_loading_one_click.sql` manually.
3. Run `supabase/preflight/20261006_bilty_loading_one_click_post_verify.sql`.
4. Run `supabase/preflight/20261006_bilty_loading_one_click_summary_verify.sql`; require `BILTY_LOADING_ONE_CLICK_OVERALL = PASS`.
5. Deploy the frontend build, then run the cases below using a non-production/test Adda or an explicitly approved production test Bilty. Do not create test rows in production without the project owner’s normal approval process.

## Field mapping and accounting boundary

| Saved Booking / Bilty | New Loading | Handling |
| --- | --- | --- |
| `id` | `booking_id` | Direct UUID link; Booking row is locked during orchestration. |
| `adda_id` | derived through `booking_id` | Required and must match the explicitly authorized Adda. NULL-Adda legacy Bookings are rejected. |
| `booking_no` | `loading_no` | Copied as the Loading reference. |
| `loading_date` or `booking_date` | `loading_date` | Loading date falls back to Bilty date when absent. |
| `from_city`, `to_city` | `route` | Joined with an arrow; both must be present. |
| `vehicle_id` | `vehicle_id` | Copied only when registered and verified in the same Adda; otherwise NULL is preserved. |
| `external_vehicle_no/type/owner` | no Loading text field | Remains on the Booking; no registered vehicle is invented. |
| Bilty form driver | `driver_id` | Bilty has no driver input, so Loading driver remains NULL. |
| `freight`, `vehicle_freight` | margin trigger reads Booking | Not accepted from the browser or duplicated in the RPC payload. |
| `advance_bilty` | `advance_amount = 0` | It is not proven to be an actual Loading Cashbook receipt. This avoids converting the Bilty advance into a duplicate/unverified Cash In through the existing Loading advance trigger. |
| `freight` | `remaining_amount` | Nonnegative informational Loading balance; Other Adda settlement remains authoritative in Phase 3C. |
| `bilty_items.goods_name` | `loading_items.item_name` | Copied without renaming source data. |
| Bilty `quantity`, `weight`, `unit`, `remarks` | same-named Loading item fields | Copied as stored, including nullable/zero weight. |
| Bilty `line_no` | no Loading line column | Rows are inserted in Bilty line order. Loading item order is not persisted as `line_no`; current screens sort by item ID in differing directions. |

The Loading table has no external-vehicle text column and the Bilty UI has no driver field. Nullable Loading columns are therefore a deployment prerequisite. The migration fails closed if `vehicle_id`, `driver_id`, or item `weight` is non-nullable, or if a weight check excludes Bilty-valid NULL/zero values. No migration changes those schema contracts.

## Test cases

For each case, compare Booking count, Loading count for the Booking, Phase 3B recognition event, `adda_account_entries`, Cashbook, Phase 3C Other Adda transaction/allocation history, and displayed Bilty status.

1. **Save only, then one-click create:** Save an own-Adda Bilty with freight 300,000 and vehicle freight 270,000. Before the save workflow completes there should be no margin event. After one successful Bilty Save: one Booking, one Loading, one recognition event, one `bilty_margin` income journal entry for 30,000, and no margin Cashbook row.
2. **Request retry / lost response:** Retry the same saved Booking with the retained request UUID. It must return/reuse its Loading; Loading, recognition, journal, and Cashbook counts must not increase.
3. **Registered vehicle:** Save a Bilty with a valid registered vehicle. Vehicle is copied; the current Bilty form has no driver field, so Loading `driver_id` stays NULL rather than inventing a driver. Exactly one Loading and the same calculated margin result are expected.
4. **External vehicle:** Save an otherwise valid Bilty with external vehicle text and no registered `vehicle_id`. Loading is created with `vehicle_id = NULL`; Booking retains the external number/type/owner. Exactly one margin event is expected for `own_adda`.
5. **Nullable/zero item weight:** Save a Bilty with one NULL weight and one zero weight when allowed by the live schema. Both values and all other item fields are copied; no weight is inferred. The existing schema precondition must pass first.
6. **Other Adda loading source:** Save with `loading_source='other_adda'`. A Loading may be created/reused, but there must be no own-Adda margin event/journal. Any full-freight obligation and its settlement remain solely in Phase 3C.
7. **Zero margin:** Freight equals vehicle freight. One Loading is created; a recognition audit event may record zero under the existing Phase 3B trigger, but no P&L journal entry or Cashbook row is created.
8. **Negative margin:** Freight 250,000 and vehicle freight 270,000, `own_adda`. One expense journal row is created as `bilty_loss` for positive amount 20,000. No negative income and no Cashbook row.
9. **Existing Loading on edit:** Edit a Bilty that already has a Loading. The edit must not create a second Loading. For the normal existing/edit path, the frontend only calls orchestration when this is a new Bilty or a recorded retry after Loading creation failed.
10. **Recognized Booking financial lock:** After own-Adda recognition, attempt to change freight, vehicle freight, or loading source. The existing server trigger rejects it; no journal history changes.
11. **Loading source lock/delete:** Attempt to move or directly delete a recognized own-Adda Loading. Existing Phase 3B guards reject the change/delete. Use only the existing controlled margin reversal path where applicable; this task creates no correction/repost workflow.
12. **Two-step failure and retry:** Force the second RPC to fail after Bilty save. The UI must say the Bilty is saved and Loading creation failed, preserve the saved form/Booking ID, and retain the request ID. Retry must update the same Booking and create/reuse exactly one Loading.
13. **Cross-Adda Booking:** Call the protected RPC with a different Adda from the Booking tenant, or use another tenant’s Booking. The RPC rejects it and creates no Loading/event/journal/Cashbook row.
14. **Other Adda receivable:** Use `freight_receivable_from='other_adda'` and confirm the Phase 3C full-freight obligation is unchanged. The own Adda margin/loss is only `freight - vehicle_freight`, never full freight.
15. **Loading advance/Cashbook:** Set `advance_bilty` on the Booking. The Bilty-specific Loading still has `advance_amount=0`; the existing Loading advance Cashbook trigger remains installed but must create no `loading_advance` Cash In from that unproven value. Separately created genuine Loading/payment receipts continue through existing flows.
16. **Historical rows:** Existing Loading/Bilty rows are not iterated or updated by migration. Calling orchestration for a Booking that already has a Loading reuses it without adding a missing historical margin projection.
17. **Summary reconciliation:** Confirm Bilty Margin enters Adda income, Bilty Loss enters Adda expense, total income minus total expense matches net profit, and no settlement/realized/pending waterfall is introduced in this phase.

## Rollback and operational notes

The migration only adds one protected function and does not mutate existing data. If runtime issues arise, disable the frontend call and keep the Bilty saved. Do not manually insert a Loading or journal row to repair the two-step state. Any database rollback should be reviewed separately and must not remove a Loading/journal record created after deployment.

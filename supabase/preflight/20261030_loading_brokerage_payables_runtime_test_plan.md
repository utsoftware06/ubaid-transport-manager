# Loading Brokerage Payables Phase 1 Runtime Test Plan

Run only against a disposable/staging database with synthetic Adda, active profile, Broker, Booking, Loading, Vehicle and Driver fixtures. Do not run against production. Use the authenticated JWT and selected Adda context for permission tests; use database-admin setup only for creating isolated fixtures. Clean up by dropping the disposable database or rolling back the fixture transaction.

## Posting and uniqueness

1. Create a post-cutover Booking with `broker_commission = 5000`, a same-Adda Broker, Vehicle and linked Loading. Explicitly post the payable. Confirm one accrual for the Booking, amount 5,000, no `broker_transactions` row and no Cashbook row.
2. Add a second Loading for that Booking. Retry the same request ID and payload; confirm the same accrual ID. Submit a different payload with the same request ID; confirm rejection. Submit a fresh request ID while the accrual is active; confirm duplicate accrual rejection.
   In two sessions, concurrently post the same Booking with different request IDs; exactly one accrual should commit. Concurrent payment requests must serialize on the accrual so their combined net amount cannot exceed its payable.
3. Try a pre-cutover Booking with `broker_id` and commission populated; confirm it is not eligible and no rows persist.
   Try changing a Booking's `created_at` after insert; confirm it is immutable. Insert a new Booking while explicitly supplying a pre-cutover `created_at`; confirm the source guard stamps it at creation time so it cannot masquerade as historical and bypass the dedicated workflow.

## Payment and reversal

4. Pay 2,000, then 3,000. Confirm outstanding moves 5,000 → 3,000 → 0 and exactly one Cashbook `Cash Out` exists per payment event. Retry an identical payment request; confirm the original event and no extra Cashbook row. Attempt 3,001 against a 3,000 balance; confirm rejection with no event or Cashbook row.
5. Reverse one payment as Adda Admin. Confirm one opposite `Cash In`, outstanding increases by the reversed amount, and a second reversal is rejected. Reverse the remaining payment; confirm net paid is zero.
6. Reverse the accrual as Adda Admin. Confirm the payable becomes reversed and no Cashbook row is created. Confirm an Operator cannot reverse either payment or accrual. Repost after reversal with a new request ID and confirm a new source revision.

## Authorization and source protection

7. Confirm an active Operator/Adda Admin can post only for their own Adda. Confirm cross-Adda Broker, Booking, Loading, Vehicle or Driver references fail. Confirm a caller-supplied Vehicle must exactly match the Booking/Loading-linked same-Adda Vehicle; an unlinked arbitrary Vehicle is rejected. Confirm Super Admin must pass an existing, explicitly selected Adda. Confirm inactive profiles and unauthorized roles fail.
8. With an active accrual, attempt to change Booking Adda, Broker, commission, Vehicle or cancel status; change/cancel the linked Loading; change a referenced Broker/Vehicle Adda; and delete source rows. Confirm protected changes fail until the relevant accrual is reversed. Confirm historical source rows and the cutover configuration remain retained after reversal.
9. Through the generic Broker save RPC, attempt `Broker Payable` and `Payment To Broker` linked to an eligible new Booking's Loading; confirm both are rejected. Confirm existing generic Broker operations without this new source link retain their prior behavior.
10. Attempt direct authenticated insert/update/delete on the new subledger and forged/relabelled Cashbook rows, including with the custom GUC set. Confirm table ACL/RLS and guards reject them. Confirm source Cashbook rows cannot be edited, deleted or relabelled; the unique event identity prevents duplicates. Confirm the service role retains CRUD but cannot truncate the source/cutover tables.

## Expected accounting result

For a 100,000 Kiraya Booking whose existing `bookings.broker_commission` is 5,000, separately verify the existing vehicle settlement still uses its existing 95,000 entitlement exactly once. The new subledger records a 5,000 Broker payable; its accrual creates no Cashbook entry. Paying 2,000 records 2,000 Cash Out and leaves 3,000 payable. No Parchi, Adda income/expense, or extra vehicle payment is created.

Record results as PASS/FAIL per case. This plan is not a live test result; the migration and runtime cases have not been executed against a database in this task.

# Security Hardening Phase 4 Runtime Test Plan

Run these checks in a staging environment after the preflight passes, the migration is applied, and both SQL verifiers pass. Use disposable pump/payment data for write tests.

## Shared petrol pump master

1. Sign in as an active authenticated operator in each test Adda and open Petrol Pumps, Diesel, Petrol Pump Payments, and Manual Voucher Diesel selection. All seven pump master rows must remain visible, including the five unused pumps and the pump whose old payment history does not resolve to Diesel tenant context.
2. In Petrol Pumps, create a disposable pump, edit its name/contact fields, and delete it. Each operation should succeed for an authenticated user. Confirm the shared list refreshes in the other Adda session too.
3. With an anon key and no user token, try to select, insert, update, and delete a pump through the Supabase REST API. Every request must be denied.

## Payment allocations

4. From an authenticated app session, attempt a direct REST SELECT and direct INSERT/UPDATE/DELETE against `petrol_pump_payment_allocations`. Direct access must be denied because authenticated has no table grants. The security-definer accounting entry points remain the supported write path.
5. In staging, attempt an allocation-helper check using a payment/Diesel pair from another Adda. The authorization helper must return false for a non-Super Admin. A malformed pair, missing parent, different pump, or pump whose Diesel history cannot resolve to exactly one Adda must also fail closed.
6. Confirm a Super Admin can pass the helper only for an existing payment/Diesel pair whose pump resolves to one Adda. Unresolved pump history must still return false for Super Admin.

## Accounting regression

7. Save a normal Petrol Pump Payment using `save_petrol_pump_payment`. Verify the existing FIFO allocation order, Diesel paid/remaining/status values, and one Cashbook OUT for the actual payment amount.
8. Edit and delete that disposable payment using the existing RPCs. Verify allocations rebuild/reverse exactly once, Diesel values return to the expected state, and the corresponding Cashbook row is updated or removed exactly once.
9. Save a Manual Voucher Diesel selected payment using the existing protected Manual wrapper. Verify the amount allocates only to the selected Diesel entry, older Diesel allocation state remains unchanged, and no second Cashbook OUT is created.
10. Exercise the existing Voucher removal guard for a Voucher whose Diesel has payment allocations. Confirm the guard retains its existing behavior and no allocation or payment is directly removed through a client table request.

## Completion checks

11. Reopen the pump master and supplier payment screens in authenticated sessions after the payment tests. Pump choices and balances should load, and no tenant filtering should hide shared or unused pump records.
12. Confirm the five original allocation IDs, payment IDs, Diesel IDs, and amounts remain intact; all five still resolve to the same Adda with matching payment/Diesel pump IDs. Confirm no duplicate payment, allocation, or Cashbook rows were created by retries.

Do not use live financial records for write tests. Do not run production SQL as part of this plan.

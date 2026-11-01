# Diesel Entries Tenant Hardening Runtime Test Plan

This plan validates the RLS/grant change in a non-production test environment before any later Manual Diesel migration is considered. Use dedicated test users and a disposable Bilty Voucher, Loading, Fuel expense item, and pump. Do not test destructive paths against production records.

## Deployment sequence

1. Run `supabase/preflight/20261012_diesel_entries_tenant_hardening_preflight.sql` and review every row. Stop if a mandatory prerequisite fails.
2. Apply `supabase/migrations/20261011000530_diesel_entries_tenant_hardening.sql` once.
3. Run `supabase/preflight/20261012_diesel_entries_tenant_hardening_post_verify.sql`.
4. Run `supabase/preflight/20261012_diesel_entries_tenant_hardening_summary_verify.sql` and require `DIESEL_TENANT_HARDENING_OVERALL = PASS`.
5. Run the cases below using authenticated test sessions for two Addas, a Super Admin, and an anonymous session.

## Access and tenant cases

1. As Adda Admin and Operator for Adda A, list Diesel entries. Only rows whose `loading_id → loadings.booking_id → bookings.adda_id` resolves to Adda A should be returned. Repeat in Diesel, Petrol Pumps, Petrol Pump Payments, and Voucher details screens.
2. As Adda B, verify Adda A Diesel rows are not returned, including when querying a known Diesel ID directly.
3. As Super Admin, verify Diesel entries across Addas remain visible.
4. As `anon`, attempt SELECT, INSERT, UPDATE, and DELETE against `diesel_entries`; each must be denied by table privileges.

## Bilty Voucher write cases

1. As Adda A, create a disposable Bilty Voucher with a selected Loading, vehicle, matching Fuel expense item, amount, and pump. Confirm Voucher save and the existing direct Diesel insert both succeed.
2. Confirm the new row stores the same `expense_id`, `expense_item_id`, `loading_id`, and `vehicle_id` as the Voucher flow, and the Fuel item amount equals `total_amount`.
3. Attempt an authenticated insert with a Loading from Adda B while signed in as Adda A. It must fail the RLS `WITH CHECK` policy.
4. Attempt an insert with a vehicle that differs from the Loading, an unrelated Voucher, a non-Fuel item, a periodic Fuel item, or an amount different from the item. Each must fail.
5. As Super Admin, confirm the normal Bilty insert works for an explicitly selected Loading in another Adda.
6. If the selected pump already has Diesel rows, verify an insert from another Adda is rejected; the existing pump-payment contract requires one pump's Diesel history to resolve to one Adda.
7. Attempt direct authenticated UPDATE and DELETE. Both must be denied. Confirm the application does not use direct table UPDATE/DELETE for existing Bilty Diesel.

## Existing payment and deletion paths

1. Create a Diesel row with a partial amount paid through the existing Voucher form. Verify the existing `diesel_entries` payment values and any established Cashbook behavior match the pre-hardening behavior.
2. Record an actual Petrol Pump payment through the existing payment screen. Confirm `rebuild_petrol_pump_accounting(uuid)` updates Diesel allocations/balances exactly once and produces the same Cashbook result as before.
3. Delete the disposable, eligible Voucher through the existing `delete_voucher_safely(bigint)` UI path. Confirm Diesel and Voucher dependents are removed according to that RPC and pump accounting rebuilds without direct authenticated table DELETE.
4. Confirm no generic Diesel/Voucher Cashbook row was added by the hardening migration. Compare payment/Cashbook rows before and after the RLS-only deployment.

## Historical and Manual Diesel checks

1. Compare Diesel row counts and sampled IDs/payment fields immediately before and after migration; the migration is DDL/ACL/policy only and must not rewrite historical Diesel rows.
2. Confirm no `manual_voucher_id` or `manual_request_id` Diesel columns and no Manual Diesel writer were added by this migration.
3. Keep `202610110006_manual_voucher_diesel_integration.sql` out of this deployment. Before a future batch migration push, assign that pending Manual Diesel migration a version later than this hardening migration and review its Manual SELECT policy with RLS enabled.

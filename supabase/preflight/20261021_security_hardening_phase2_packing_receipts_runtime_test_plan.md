# Security Hardening Phase 2 Runtime Test Plan

Run this plan after the migration and both read-only verifiers pass. Use separate authenticated accounts in two Addas and a Super Admin account. Do not use production rows for destructive tests.

## Tenant visibility

1. As the Adda that owns packing slip `id = 3` (loading `id = 6`, loading no. `098`), open Packing and view the slip and its item. Confirm the legacy row remains visible through `loading.vehicle_id -> vehicles.adda_id` while `loading.booking_id` stays `NULL`.
2. As a user from a different Adda, query/list the same slip and item through the app. Confirm neither is returned and direct API reads do not expose them.
3. As Super Admin, view the legacy slip and ordinary slips from multiple Addas. Confirm resolved rows are visible; unresolved contexts remain inaccessible through the helpers.

## Packing slip writes

4. In a non-production test Adda, create, edit, and delete a packing slip attached to a loading whose booking resolves to that Adda. Confirm all existing Packing UI workflows still work.
5. Attempt to create/update a slip with a loading from another Adda. Confirm it is rejected by RLS.
6. On a disposable staging fixture only, test a loading with `booking_id IS NOT NULL` where the referenced booking is missing or has `adda_id IS NULL`, while the loading vehicle has an Adda. Confirm access is denied and the vehicle fallback is not used. Remove the fixture through the approved test cleanup path.

## Packing slip items

7. For a slip visible to the current Adda, create and delete a packing-slip item through the existing UI. Confirm the parent relationship remains usable.
8. As another Adda, attempt to read, insert, or delete an item under that slip. Confirm each operation is denied. Confirm the app does not depend on direct item UPDATE; authenticated UPDATE privilege is intentionally absent.
9. On a disposable staging fixture only, test an item with a missing parent and confirm it is inaccessible and cannot be inserted with an inaccessible parent.

## Payment receipts and accounting regression

10. As the owning Adda, list, create, edit, and delete a receipt linked to a loading whose booking resolves to that Adda. Verify the existing Payment Receipts UI still works.
11. As another Adda, attempt the same receipt operations against the first Adda's loading. Confirm all are denied. Test an unresolved loading/booking on staging and confirm fail-closed behavior; no vehicle fallback is allowed.
12. Confirm receipt create/edit/delete continues to invoke the existing Cashbook synchronization exactly once. Compare the affected receipt and Cashbook entries before/after the normal app operation; the migration itself must not change either.

## Final checks

13. Re-open the three target screens under authenticated users and verify no permission errors occur for valid tenant-owned records.
14. Confirm anon requests have no direct table access and service-role backend operations retain their prior behavior.
15. Run the read-only post-verifier, then the summary verifier. Both must finish with their overall result `PASS`.

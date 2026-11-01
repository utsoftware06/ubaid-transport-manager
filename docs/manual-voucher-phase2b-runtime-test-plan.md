# Manual Voucher Phase 2B runtime test plan

Run only after the Phase 2B preflight passes and the migrations, post-verifier,
and summary verifier have been applied/run in the specified order. Use a test
Adda, one test vehicle, and non-finalized test source records; do not test by
editing finalized production history. This rollout enables Workshop, Oil, and
Tyre. Diesel is explicitly blocked until a separate reviewed migration updates
the Loading-dependent petrol-pump tenant/payment accounting contract.

## Bilty regression controls

1. Save and finalize a Bilty Voucher with Workshop, Oil, and Tyre sources using
   the existing Bilty UI. Confirm it still resolves the same Movement Group,
   retains its settlement, and uses the existing source-specific Cashbook rules.
2. Confirm Diesel on a Bilty Voucher still requires its real Loading and its
   existing petrol-pump payment/allocation flow is unchanged.

## Manual Workshop / Oil / Tyre

3. Create a Manual Voucher with freight and a plain expense. Attach an eligible
   same-Adda/same-Vehicle existing Workshop entry; save, reload, and confirm one
   `vehicle_periodic / Workshop` item equals the Workshop source total.
4. Repeat with an existing Oil entry and an existing Tyre entry. A source linked
   to another Voucher, Adda, or Vehicle must be rejected.
5. In a Manual draft, use Create New Workshop. Verify its source/detail rows and
   bill totals; any Workshop Cashbook row must equal the source's actual
   `paid_amount`, not its entire payable.
6. Create New Oil with `external_shop`; verify one supplier bill, no synthetic
   supplier payment, and no source-creation Cashbook payment. Repeat with
   `adda_stock`; verify stock issue and no supplier bill/payment.
7. Create New Tyre using registered assets/positions and the deployed work
   types. Verify asset fitment/event history and (for external shop) exactly
   one supplier bill, with no payment created.
8. Attach multiple source kinds to one Manual Voucher. Verify exactly one
   source-backed expense item per kind, and that persisted rows are included in
   Details/Print and the live Manual net summary.
9. Edit the draft's freight/plain expenses and save again. Confirm the expense
   writer replaces only `regular_trip` rows, preserves linked
   `vehicle_periodic` Workshop/Oil/Tyre rows, and source synchronization still
   reconciles them. Attempt to detach a `voucher_created` source; the request
   must fail closed.

## Finalization and Cashbook

10. Finalize a draft with plain + Workshop + Oil + Tyre expenses. Verify the
    immutable Manual settlement has one freight snapshot and one expense
    snapshot, and net equals freight less all eligible expenses. For the
    example Rs.400,000 freight, the currently enabled sources (Workshop
    Rs.20,000, Oil Rs.10,000, Tyre Rs.30,000, Toll Rs.10,000) total Rs.70,000
    and net Rs.330,000. Once Diesel is safely enabled, adding Diesel
    Rs.100,000 would produce expenses Rs.170,000 and net Rs.230,000.
11. Verify exactly one signed `manual_chakkar_net` Owner/Gari projection for
    that settlement and one Manual row in Monthly Hisab. Verify no Bilty
    settlement or Movement Group was created.
12. Confirm Manual freight never creates Cashbook IN; Manual generic Voucher
    items never create generic Voucher Cash Out. Oil/Tyre payment Cashbook rows
    arise only from their existing payment RPCs; Workshop Cashbook amount, if
    any, reflects actual paid amount only.
13. After finalization, attempt ordinary edits/deletes of each linked source
    and each Voucher source link. All must be refused without altering history.

## Diesel limitation

14. Confirm the Manual UI does not offer Diesel/Fuel and no Diesel row is
    created without a real Loading. Manual Diesel remains blocked because pump
    tenant validation and accounting rebuild resolve Adda through
    `diesel_entries.loading_id -> loadings -> bookings.adda_id`. Do not work
    around this by creating fake Loading/Bilty/Movement Group rows, recording
    Diesel as a plain expense, or changing `loading_id` nullability without
    updating and verifying pump allocation/Cashbook tenant logic as one reviewed
    change.

## Tenant and retry checks

15. Repeat link/create/finalize attempts as an authenticated user from another
    Adda; server RPCs must reject them.
16. Retry a successful source creation or finalization request. It must not
    create duplicate source ownership, expense rows, settlements, or
    Owner/Gari projections.

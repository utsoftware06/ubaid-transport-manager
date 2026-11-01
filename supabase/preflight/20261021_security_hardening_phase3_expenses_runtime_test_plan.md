# Security Hardening Phase 3: `expenses` runtime test plan

Run this package in order after reviewing the read-only preflight output:

1. `20261021_security_hardening_phase3_expenses_preflight.sql`
2. `202610210003_security_hardening_phase3_expenses.sql`
3. `20261021_security_hardening_phase3_expenses_post_verify.sql`
4. `20261021_security_hardening_phase3_expenses_summary_verify.sql`

Do not run the migration if the preflight shows missing helpers or relations,
unexpected policies, missing `service_role` access, conflicting tenant evidence,
or if vouchers 13/14 no longer match the reported legacy baseline.

## Database identity and policy checks

- Confirm vouchers 13 and 14 resolve to Adda `44b73002-7582-4c75-aca8-24d853311674`.
- Confirm a non-Manual voucher with a Movement Group still resolves to the same
  Adda and vehicle returned by the existing Movement Group resolver.
- Confirm Manual vouchers still resolve from `manual_voucher_details` and the
  matching vehicle/driver tenant context.
- Confirm a voucher with missing Loading, missing Booking, NULL Booking Adda,
  vehicle/Adda disagreement, or more than one candidate Booking Adda returns no
  resolver context. Use isolated staging fixtures; do not mutate production.
- As an Adda admin/operator, verify only resolvable expenses for the current
  Adda are selectable. Verify vouchers 13 and 14 are visible to their Adda.
- As a different Adda user, verify vouchers 13 and 14 and other-tenant expenses
  are not visible.
- As Super Admin, verify resolvable expenses across Addas are visible while an
  unresolved expense remains hidden.
- Verify `anon` cannot select expenses and `authenticated` cannot directly
  insert, update, or delete expenses.
- Verify service-role reads and writes remain available.

## Application write-path regression

Using disposable staging records and the existing application UI/RPCs, verify:

- Bilty Voucher create, edit, archive/delete, and finalization still work.
- Manual Voucher create/edit, expense-item save, Diesel save, and finalization
  still work.
- Workshop, Oil, Tyre, Diesel, and Driver earning source-link saves continue to
  validate the same Adda/Vehicle and remain linked once.
- Cashbook synchronization, payment flows, Owner/Gari projection, and Monthly
  Hisab remain unchanged; confirm no duplicate postings.
- Review existing historical expenses for unchanged IDs and amounts.

The migration performs no row updates or backfill. Complete these tests in a
staging project before rollout to production.

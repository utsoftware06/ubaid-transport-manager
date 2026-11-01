# Other Adda Phase 3B Runtime Test Plan

Run this plan only after the production preflight returns `GO`, the migration is reviewed and deployed, and test accounts/Adda data are available. Use a non-production test Other Adda with no historical accounting rows. Record the returned payment/reversal UUIDs and the matching Cashbook row IDs. Do not edit or delete posted payment or allocation rows during testing.

## Setup

Create or select an active test Other Adda in one Adda. Post at least three receivable obligations and three payable obligations with distinct dates, creation times, references, and descriptions. Include obligations with due dates so reminder changes can be checked. Save initial balances, reminder rows, payment history, Cashbook row count, and obligation allocation order.

## Payment posting and FIFO

- Post a receivable payment smaller than the total LENA outstanding. Confirm the oldest receivable obligation is allocated first, and a partial remainder is recorded against the next oldest obligation only when needed.
- Post a receivable payment that exactly settles the remaining LENA balance. Confirm gross receivable becomes zero and no displayed outstanding amount becomes negative.
- Repeat the same partial and full tests for payable obligations.
- Submit an amount one cent above the side's outstanding amount. Expect `other_adda_payment_exceeds_outstanding`; verify no payment, allocation, or Cashbook row was committed.
- Post a payment with a stable request UUID, then retry the identical payload/request UUID. Confirm the same payment UUID is returned and source, allocation, and Cashbook counts do not increase.
- Reuse that request UUID with a different date, amount, side, method, reference, or remarks. Expect `idempotency_payload_mismatch` and verify no additional rows.
- Confirm a payment cannot be allocated to an obligation that has already been reversed.

## Cashbook mapping and exact-once behavior

- Receivable payment creates exactly one Cash In row for the exact payment amount.
- Payable payment creates exactly one Cash Out row for the exact payment amount.
- Verify `reference_type='other_adda_payment'`, `reference_id=payment.id::text`, Cashbook `adda_id` matches the persisted Other Adda Adda, and person name comes from the persisted Other Adda master.
- Verify payment date, method, description, and null vehicle/driver/loading links match the payment contract.
- Confirm the unique partial index rejects a duplicate source identity and the Cashbook guard rejects browser insert/update/delete attempts for these rows.

## Payment reversal

- Reverse a receivable payment. Confirm one append-only reversal payment and mirrored allocation rows appear, and Cashbook posts Cash Out for the same amount.
- Reverse a payable payment. Confirm the reversal Cashbook row is Cash In for the same amount.
- Retry the same reversal request UUID and payload; confirm the same reversal UUID returns without extra rows.
- Attempt a second reversal with a different request UUID; expect `other_adda_payment_already_reversed` and no extra rows.
- Confirm the original payment, original allocations, and original Cashbook row remain unchanged.
- Verify the reversal restores the corresponding obligation outstanding and due reminder amount.

## Balances, reminders, and lifecycle

- After a partial payment, confirm gross LENA/DENA is reduced by the allocated amount on only that side.
- After a full payment, confirm gross outstanding on that side is zero.
- Confirm a partially settled due obligation remains in reminders with only its remaining amount.
- Confirm a fully settled due obligation disappears from reminders.
- Attempt to reverse an obligation with active settlement allocation; expect `other_adda_obligation_has_settlement` and no new reversal event.
- Confirm an unsettled obligation can still be reversed using the existing Phase 3A reversal flow.
- Confirm archive is blocked while either side has outstanding obligations or unresolved payment/Cashbook/allocation evidence, and succeeds after all exposure is settled and evidence is consistent.

## Tenant isolation

- As an Adda Admin, post/list/reverse only payments for an Other Adda owned by the profile Adda. Attempts against another Adda must fail server-side even if the browser changes the target ID.
- As a Super Admin, open an account in one Adda and verify the payment RPC derives the tenant from that persisted master. Repeat for a different Adda and verify no account history crosses between them.
- Confirm the payment UI does not send a browser-selected tenant ID and payment history is returned only for the requested authorized Other Adda.

## Historical preservation and append-only protections

- Compare `other_addas` and `other_adda_transactions` counts and historical row snapshots captured by the preflight. They must remain unchanged through migration and test setup should use a separate test master.
- Confirm Phase 3A obligation/reversal event values and behavior remain unchanged.
- Confirm direct INSERT/UPDATE/DELETE/TRUNCATE attempts against both payment ledgers are rejected outside the protected RPC context.
- Confirm payment history exposes no edit or delete action; reversal is an appended event requiring a reason and confirmation.

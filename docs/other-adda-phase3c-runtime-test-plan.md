# Other Adda Phase 3C Runtime Test Plan

This plan is for an isolated staging project after the Phase 3C contracts and the trip-read migration have passed their preflight and review. It is not authorization to run production tests. Use only synthetic Bilties, active test Other Addas, and approved test profiles. Do not edit or remove posted Other Adda transactions, payment allocations, payments, or Cashbook history.

## Execution boundaries

- Run the read-only preflight first and retain its complete results. Verify deployed save-v2, obligation-post, link, immutability, deferred consistency, Phase 3B payment/reversal, and summary contracts before testing.
- Use authenticated application/API sessions for RPC and UI behavior. Do not simulate users with `SET ROLE`, forged JWT GUCs, `set_config`, service-role credentials, or direct privileged writes.
- `BEGIN`/`ROLLBACK` is useful only when the test runs inside a real authenticated database transaction and all calls execute in that same transaction. PostgREST RPC calls commit in their own request, so a SQL editor rollback cannot undo them. Prefer an isolated staging tenant and dedicated synthetic fixtures; treat successful API writes as durable append-only test evidence and reverse/close only through supported RPCs.
- Record case, environment, actor role and Adda, sanitized inputs, request IDs, response/error, resulting booking/link/obligation/payment/allocation/Cashbook IDs, and before/after counts. Do not record tokens or credentials.
- For legacy NULL Phase 3C bookings, test reads only. Do not silently assign fields or attempt a normal save unless an operator has explicitly reviewed the required field choices.

## Fixtures and baseline

Prepare one test Adda with two active Other Addas (`OA_LOADING` and `OA_FINANCIAL`), a synthetic Party/Broker, and an eligible vehicle. `OA_LOADING` and `OA_FINANCIAL` may be the same record for some cases and must be different for the split-role case. Capture Phase 3B balance/payment/Cashbook baselines for both masters. Capture a legacy NULL-fields booking snapshot separately; it is read-only test data.

## Bilty save, linkage, and isolation

1. **Own Adda / existing counterparty:** Save an outbound Bilty with `loading_source=own_adda`, no loading-source Other Adda, `freight_receivable_from=existing_counterparty`, and no financial Other Adda. Confirm save-v2 retains existing Party/Broker behavior and creates no Other Adda obligation/link/payment/Cashbook posting.
2. **Other Adda supplied loading / existing counterparty owes freight:** Save a Bilty with `loading_source=other_adda` and `loading_source_other_adda_id=OA_LOADING`, while `freight_receivable_from=existing_counterparty`. Confirm the booking appears in OA_LOADING's trips list, has no obligation link, and causes no Phase 3B balance/payment/Cashbook change for OA_LOADING.
3. **Other Adda loading and freight receivable:** Save with both roles set to OA_LOADING and `freight_receivable_from=other_adda`. Confirm one receivable obligation with `origin=bilty`, one tenant-safe link, amount equal to persisted booking freight, and no duplicate from retrying an identical Bilty save.
4. **Different loading source and financial Other Adda:** Save with loading source OA_LOADING and financial receivable OA_FINANCIAL. Confirm the trip appears in both relevant account views, but the obligation/link belongs only to OA_FINANCIAL. Confirm OA_LOADING's view displays the financial counterparty separately and does not create a second obligation.
5. **Trip kinds:** Repeat appropriate staging fixtures for `outbound`, `return`, and `local`; verify the existing movement-group contract remains intact and trip type is displayed unchanged.
6. **Required role selection:** Attempt blank/invalid loading source, missing loading-source Other Adda, blank/invalid receivable source, and missing financial Other Adda. Expect server/client validation to reject; confirm no partial booking, link, or obligation is committed.
7. **Cross-tenant rejection:** As an Adda Admin/operator, forge an Other Adda UUID from another tenant in either selector/RPC input. Expect server authorization/composite tenant checks to reject. Confirm no booking or financial evidence appears in either tenant.
8. **Duplicate prevention:** Retry the same valid linked-Bilty save/request behavior and inspect `(adda_id, booking_id)` link uniqueness. Confirm only one linked obligation remains and any mismatched evidence fails closed.
9. **Linked-field lock:** On a Bilty with a linked obligation, attempt to change freight, receivable source, financial Other Adda, loading source, and loading-source Other Adda. UI should render those fields locked; a forged v2 request must be rejected by the production trigger. Confirm the original booking, obligation, and link remain unchanged.
10. **Allowed ordinary edit:** Edit a non-protected field on a linked Bilty. Confirm save-v2 succeeds without changing the obligation identity, amount, tenant, due date, or link. The UI must preserve the persisted obligation due date when it resubmits the v2 payload.

## Trips read and settlement display

11. **Read scope and roles:** Open a test Other Adda account as its tenant user and Super Admin. Verify the RPC derives tenant from the persisted Other Adda master; a normal user cannot see another tenant's trips by changing the UUID. Super Admin can open one explicitly identified account at a time without cross-tenant row mixing.
12. **Operational-only trip:** Confirm a loading-source-only trip appears when freight is receivable from the existing Party/Broker, with no Other Adda obligation and no fabricated Other Adda received/balance values.
13. **Other Adda receivable values:** Before settlement, verify received is zero, balance equals the linked obligation amount, and status is unpaid. Then post an authorized partial and full Phase 3B receivable payment. Verify received/balance/status follow the obligation allocations, with no value inferred from loading advances.
14. **Payment reversal:** Reverse a test payment using the Phase 3B reversal RPC. Verify net allocated formula counts payment allocations positively and reversal allocations negatively; received decreases, balance restores, status updates, and Phase 3B posts the opposite Cashbook direction exactly once.
15. **Reversed obligation:** After reversing all settlement payments, reverse an unsettled Bilty obligation using the Phase 3A/3B-authorized obligation reversal path. Verify the trip remains operationally visible, displays reversed status and no outstanding receivable, and its original obligation/link remain append-only.
16. **Search and paging:** Search by synthetic Bilty number, vehicle, and route. Traverse pages and verify no row repeats or disappears at page boundaries; account scoping remains server-side.
17. **Legacy NULL Phase 3C rows:** Open and list a legacy booking with NULL Phase 3C fields. Confirm it remains readable and shows a legacy/unset receivable state; do not mutate it during this test.

## Phase 3B regression checks

18. Compare pre/post Phase 3B balance, payment, allocation, and Cashbook evidence for unrelated test obligations. Other Adda trip reads must not post Cashbook rows. A Bilty loading advance must remain separate from Other Adda payment settlements.
19. Confirm receivable Phase 3B payment remains Cash In, payable payment remains Cash Out, receivable-payment reversal remains Cash Out, and payable-payment reversal remains Cash In. Check `reference_type='other_adda_payment'`, payment UUID reference identity, tenant Adda, exact amount, and one Cashbook row per payment event.
20. Confirm Phase 3B RPC definitions, ACLs, allocation order, source guards, and exact-once index are unchanged by the read-only trip RPC migration.

## Correction and reversal workflow audit

- **Before an Other Adda obligation is linked:** a Bilty can be corrected through the existing save-v2 lifecycle, subject to its existing validation and ordinary Bilty rules.
- **After a Bilty obligation is linked:** preserve the booking's freight, loading source, loading Other Adda, receivable source, and financial Other Adda. The deployed trigger and deferred evidence check are authoritative; normal edits must not rewrite those values.
- **If a linked obligation needs correction after posting:** first inspect and reverse every related Phase 3B payment through `reverse_other_adda_payment`; the obligation reversal routine rejects reversal while net settlement remains. Then the Phase 3A/3B obligation reversal can append a full reversal.
- **Repost limitation:** the deployed link table is append-only and unique on `(adda_id, booking_id)`. Reversing the old obligation does not free that booking identity, and the deployed deferred trigger still requires a valid matching Bilty obligation at commit. There is no verified safe correction/repost route for the same booking. Do not implement or attempt one. Keep linked fields locked and design a separately reviewed correction workflow (for example, a versioned link/correction model or an explicit replacement booking) before changing this lifecycle.

## Result recording

Mark each case PASS, FAIL, BLOCKED, or SKIPPED. A successful RPC response alone is not a pass: read back the dedicated fixture's booking, link, obligation, settlement allocations, balances, reminders where applicable, and Cashbook row. Any unexplained Phase 3A/3B contract drift stops the related cases. No test in this document has been executed.

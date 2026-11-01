# Received Parchi upfront commission — staging runtime test plan

This is a staging-only test plan. It has not been run. Do not run it against production. Use a disposable staging database, a tenant-scoped operator and Adda Admin, a Super Admin account with an explicitly selected Adda, one authorized Broker, and a synthetic Booking with enough remaining vehicle entitlement. Never use or mutate historical production records.

## Deployed RPC contracts under test

- Existing document create remains `public.create_parchi(uuid,text,uuid,uuid,date,numeric,date,date,text,text,uuid,uuid,uuid,uuid,uuid,bigint,uuid)`.
- Received funding with explicit commission/route is `public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)`.
- Coordinated Received funding reversal is `public.reverse_received_parchi_funding(uuid,date,text,uuid)`.
- Linked vehicle credit read is `public.get_parchi_vehicle_settlement_totals(uuid,uuid[])`.
- Existing Issued Parchi funding/settlement/reversal APIs are regression-only; their signatures and use remain unchanged.

Use real authenticated JWT contexts through the application or staging API for role tests. Do not treat `SET ROLE` alone as proof of tenant authorization. Each successful write test should use a unique request UUID. For retry cases, reuse that UUID exactly; for cross-action reuse, use the same UUID with a different action/payload and expect rejection.

## Result grid

Record PASS / FAIL / SKIP for each case before cleanup. Capture IDs and numeric results only; do not log personal data or tokens.

| Case | Action | Expected result |
|---|---|---|
| Received document creation | Create a synthetic Received Parchi for the authorized Broker | Parchi document exists; no money event, principal balance, vehicle payment or Cashbook row is created by the document action. |
| Broker linkage | Open the same Broker account | The Parchi appears in the separate Parchi account section from authorized Parchi statement data; no corresponding `broker_transactions` row is created. |
| Explicit arithmetic | Fund principal 100,000; withheld commission 4,000 | Actual cash is 96,000; net principal payable remains 100,000. The Broker Parchi account shows principal/commission/cash separately. |
| Partial funding | Post two agreed funding events with explicit principal and commission values | Net funding is the sum of event principals; each event retains its own commission, actual cash and route. The document cannot be overfunded. |
| Commission validation | Try negative, non-finite, excess/equal-to-principal, or more-than-two-decimal commission | Request is rejected; no event, vehicle effect or Cashbook row persists. |
| Through Adda, not linked | Fund through Adda without vehicle settlement | One Cashbook IN for actual cash only; no Cashbook OUT or vehicle payment. Reversal adds the opposite actual-cash movement. |
| Through Adda, linked | Fund through Adda and explicitly link the saved Booking/optional Loading | Cashbook IN from Broker and Cashbook OUT to vehicle each equal actual cash (96,000 in the example); `bilty_payments.amount` equals 96,000; Parchi vehicle settlement separately contributes 4,000 noncash commission, so linked vehicle credit is 100,000. No fictitious 100,000 cash row is present. |
| Direct to vehicle, linked | Fund direct to vehicle and explicitly link the saved Booking | The linked `bilty_payments` amount is actual cash, noncash commission is separate, and no Adda Cashbook movement is created. |
| Direct to vehicle, unlinked | Fund directly without selecting vehicle settlement | No Adda Cashbook rows or vehicle-payment rows are created; Parchi principal/commission/cash remain visible in Parchi/Broker views. |
| Incompatible existing settlement | Link funding that would exceed the protected adjusted vehicle entitlement, including existing advances/payments/Parchi credits | Rejected with the vehicle settlement conflict; no new Parchi/vehicle/Cashbook rows commit. No existing settlement is silently changed. |
| Same request retry | Repeat an identical funding request | Original event ID/result is returned; no duplicate Parchi, vehicle payment, or Cashbook event is added. |
| Idempotency mismatch | Reuse the request UUID with a changed amount, route, commission, Booking/Loading, or action | Rejected. Existing event and derived rows stay unchanged. |
| Repayment | Partially repay a Received Parchi | Existing protected settlement RPC reduces principal outstanding; repayment is not inferred from generic Broker transactions. |
| Funding reversal | Reverse one linked funding event as an authorized Adda Admin/Super Admin | Exactly one Parchi reversal is appended; linked cash payment is removed from active vehicle cash settlements; through-Adda Cashbook gets one opposite entry per original cash movement; direct route adds none. A second reversal is rejected or identical retry returns its original reversal. |
| Unauthorized role | Attempt posting as inactive/unauthorized user; attempt amend/cancel/reverse as Operator | Denied by the existing Parchi authorization guard; no rows persist. Operator posting remains allowed where current policy authorizes it. |
| Cross-tenant references | Use another Adda's Broker, Booking, Loading, Vehicle or Parchi | Denied; no event, vehicle or Cashbook side effect persists. Super Admin must explicitly select the target Adda. |
| Source forgery | Authenticated user attempts direct INSERT/UPDATE/DELETE or Cashbook source forgery/relabel | Direct settlement-table DML is denied; protected trigger guards reject linked vehicle payment/Cashbook edits, deletes and relabeling. |
| Existing Issued workflow | Create/fund/settle/reverse an Issued Parchi with the existing path | Existing behavior and ACLs remain unchanged; no Received commission fields or rule are applied. |
| Print/detail | Open Parchi detail, event history, Parchi print and Broker Parchi account | Saved principal, commission, actual cash, route and linked reference display accurately in English/Urdu. Printing/preview causes no writes. |

## Cleanup

After recording the result grid, roll back the test transaction or remove only the clearly tagged synthetic staging fixtures through their authorized test path. Verify the synthetic Cashbook, vehicle-payment, Parchi-event and settlement source counts return to baseline. This cleanup must never target historical or production rows.

## Not established by a single-session run

Concurrent overfunding and concurrent identical requests require two independent authenticated sessions against staging. Confirm row/advisory-lock behavior with parallel requests and verify exactly one event/source set is committed. No concurrency test is claimed by this plan.

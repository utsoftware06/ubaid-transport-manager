# Parchi backend runtime test plan

Run against a disposable/staging database after the migration and both verifiers pass. Use separate sessions for concurrency cases. Do not run these writes against production while validating the foundation.

## Access and references

- As an active `operator`, `adda_admin`, and `super_admin`, create/read a Parchi for an authorized Adda. Confirm a normal operator cannot amend, cancel, or reverse.
- As a user from another Adda, try each RPC using another tenant's Broker/Other Adda and optional Party, Vehicle, Driver, Bilty, movement group, and Voucher references. Each mismatch must be denied. Confirm Super Admin can act across Addas only by naming the target Adda.
- Confirm Received requires a same-tenant Broker and no Other Adda; Issued requires a same-tenant active Other Adda and no Broker. The optional Party remains a trip reference only.
- Confirm `authenticated` can SELECT only rows admitted by tenant RLS and cannot INSERT/UPDATE/DELETE either Parchi table or consume the numbering sequence directly. Confirm `anon` cannot read or execute any Parchi RPC/helper.

## Document and dates

- Create a Received and an Issued document with no funding event. Confirm each has a unique `PCH-YYYY-########` number, a creation audit event, no principal balance, and no Cashbook row.
- Verify `funding_due_date` is presented as **Funding expected by**. Present `settlement_due_date` as **Repayment due** for Received and **Recovery due** for Issued. Never label either date simply as the other obligation.
- Amend amount and either/both due dates as `adda_admin` and `super_admin`; verify before/after values and reason in the amendment event. Reject an amount below net funded, a date before document date, and amendment after cancellation.
- Cancel an unfunded Parchi and confirm all later writes are rejected. Attempt cancellation after a funding event and after a fully reversed funding event; both must be rejected because money history exists.

## Money posting and derived statuses

- Received: post partial and final funding. Confirm Cashbook IN rows with `reference_type='parchi_event'`, each event UUID as `reference_id`, the Broker/Adda/date/method/amount, and no Broker transaction, expense, Bilty payment, or vehicle settlement posting. Verify funding statuses Unfunded → Partially Funded → Fully Funded.
- Received: post partial and final repayment. Confirm Cashbook OUT rows; settlement status Unpaid → Partially Settled → Settled and funded outstanding decreases by the net settlement amount.
- Issued: post partial and final funding/disbursement. Confirm Cashbook OUT rows and no Other Adda transaction/payment, expense, Bilty payment, or vehicle settlement posting.
- Issued: post partial and final recovery. Confirm Cashbook IN rows and settlement status changes only against net funded principal.
- Reject zero, negative, NaN/infinite, and more-than-two-decimal amounts. Reject money dates before the document date.

## Idempotency, limits, and reversals

- Retry each successful RPC with the identical tenant/request UUID and payload; it must return the original Parchi/event ID and produce no extra event or Cashbook row.
- Reuse that request UUID with changed payload, another Parchi, or a different action in the same Adda; it must fail with an idempotency mismatch. The same UUID in another Adda is a separate tenant scope.
- Submit concurrent funding requests whose combined amount is exactly at, then above, the document cap. The parent lock must allow only the amount within the cap. Repeat with concurrent settlements at and above net funded outstanding.
- Reverse an original funding event and an original settlement event. Confirm one reversal per original, exact original amount, same Parchi/Adda, reversal date not before the original, and an opposite-direction Cashbook event. Reject a second reversal, reversal of a reversal, cross-Parchi target, and funding reversal that would leave net funded below net settled.
- Confirm net funded and net settled never become negative and net settled never exceeds net funded after any allowed reversal sequence.

## Cashbook protection

- Confirm each posted funding/settlement/reversal has exactly one Cashbook row and that the unique source index rejects a second row for the same event UUID.
- Attempt direct INSERT with a fabricated Parchi event ID, a real event with wrong Adda/amount/date/direction/person/method/description, or a client-set GUC. Each must fail or be rejected by the unique source rule; a GUC alone must not authorize posting.
- Attempt UPDATE changing a Parchi row's `reference_id`, `reference_type`, or financial fields; attempt relabeling a non-Parchi row into `parchi_event` (including case/whitespace variants); attempt DELETE. All Parchi source edits/deletes must fail. Other existing Cashbook source flows must still pass their prior regression tests.

## Statement verification

- Call `get_parchi_statement` for own Adda as each permitted role and as Super Admin for an explicitly selected Adda. Verify direction-specific counterparty, document/due dates, event history, net funded, funding status, net settled, funded outstanding, and settlement status. Verify cross-tenant reads are denied.
- Compare totals against only Parchi events and their linked Parchi Cashbook entries. Confirm historical Broker/Other Adda transactions are untouched and are not converted or double-counted.

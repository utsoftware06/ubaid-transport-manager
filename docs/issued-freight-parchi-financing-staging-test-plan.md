# Issued Freight-Financing Parchi — staging runtime plan

This package is prepared for a disposable staging database only. It has not been executed. Do not run these cases against production or reuse historical financial rows. Create synthetic records through authorized application paths and remove only those tagged fixtures through the same staging test boundary.

## Preconditions and test identities

- Deploy `supabase/migrations/202611010002_issued_freight_parchi_financing.sql` to staging, then run the post-verifier and summary verifier.
- Use an active Operator, Adda Admin, Super Admin, and an inactive profile. Include a second Adda for tenant-denial tests.
- Create synthetic tenant-scoped Party and Other Adda payers, a vehicle, a second vehicle, and optional Booking/Loading references tied to the first vehicle. Keep one standalone case with no Booking or Loading.
- Use real authenticated JWT/application requests for authorization tests. `SET ROLE` alone does not prove tenant or active-profile enforcement.
- Use a fresh UUID request ID for every distinct action. Reuse it only for exact retry or explicit cross-action/payload-reuse rejection tests.
- Capture IDs, amounts and result codes only; do not put names, phone numbers, tokens or credentials into test logs.

## Result grid

Record PASS / FAIL / SKIP and the returned event IDs before cleanup.

| Case | Staging action | Expected result |
|---|---|---|
| Ordinary Issued regression | Create, fund, recover and reverse an ordinary Issued Parchi through its existing RPCs | Existing rows/RPC behavior is unchanged; no new freight-financing rows are created. |
| Document creation | Create freight-financing Parchi with Party primary payer, named secondary responsible person, vehicle, due dates and no Booking/Loading | Document and one `created` audit event only. No principal, Cashbook or Adda Account entry is posted. |
| Other Adda payer | Create a second financing Parchi with an authorized Other Adda as primary payer | Same standalone financing path; payer identity is stored on the Parchi and no generic Other Adda transaction/payment is inserted. |
| Commission example | Fund principal 100,000 with explicit commission 4,000 | Funding event principal=100,000, actual cash=96,000. One Cash Out of 96,000. One source-owned Adda Account income row of 4,000, no Cashbook commission row. Outstanding principal=100,000. |
| Partial funding | Post multiple partial events whose principal sum reaches the document amount | Each event keeps its own principal/commission/cash; net funded principal is the sum of principals; the aggregate cannot exceed document amount. Commission is recognized once per posted funding event. |
| Commission input validation | Try negative, non-finite, >2-decimal, equal-to-principal and greater-than-principal fees, plus a zero fee | Invalid values are rejected without writes. Zero fee is accepted and records actual cash equal to principal, with no Adda Account commission row. |
| Primary recovery | Recover part of outstanding from the selected Party or Other Adda | One Cash In equal to the actual receipt; payer identity saved; same principal outstanding decreases. No Party/Other Adda generic ledger principal row is created. |
| Secondary recovery | Recover from the identified vehicle-side responsible person | One Cash In equal to the receipt; the same Parchi outstanding decreases. Primary payer balance is not duplicated or separately maintained. |
| Shared balance | Alternate partial receipts from primary payer and secondary person | Both reduce one outstanding amount. No automatic recourse/liability transfer occurs. |
| Due dates and status | Compare funding and settlement deadlines before/after partial funding and recovery, including date equal to today | Funding status depends only on unfunded document amount; settlement status depends only on funded principal outstanding. Fully funded/settled items are not overdue for the completed stage. Due-today is not overdue. |
| Exact optional references | Link a Booking and/or Loading whose Adda and vehicle match the Parchi; separately try a foreign-tenant or different-vehicle reference | Exact same-tenant links are accepted. Inconsistent or foreign links are rejected without vehicle settlement or any other accounting write. |
| Standalone isolation | Fund a Parchi with no Booking/Loading reference | Actual Cash Out and source-owned commission are posted; no vehicle payable, Bilty payment, expense, margin, Loading brokerage or generic transaction changes. |
| Funding replay | Retry identical create/funding request UUID and payload | Original document/event result returned; exactly one event, Cashbook source and commission source row remain. |
| Idempotency mismatch | Reuse a tenant request UUID for a different action or changed payer/date/amount/fee/reference | Rejected; original event remains unchanged. |
| Concurrent limit | In two independent authenticated sessions, race funding requests whose combined principal exceeds the remaining amount; repeat with identical request UUID | At most one valid serialized result; no overfunding or duplicate effects. Repeat an equivalent race with recoveries against current outstanding; never over-recover. |
| Funding reversal ordering | Attempt funding reversal while recoveries remain, then reverse recoveries and retry | First attempt rejected. Once dependent recoveries are reversed, one coordinated reversal posts opposite Cashbook movement and one commission expense reversal. No second reversal is allowed. |
| Recovery reversal | Reverse a recovery as Adda Admin/Super Admin | One opposite Cashbook movement; net outstanding returns by the reversed receipt amount. Retry behavior remains idempotent. |
| Document amendment/cancel | Operator attempts amendment/cancel; admin amends amount above funded principal; admin tries reducing below funded amount; admin cancels unfunded vs funded document | Operator is denied. Safe admin amendment is audited. Amount below funded is rejected. Unfunded document can be cancelled; any document with money history cannot. Cancelled document rejects later mutations. |
| Explicit recourse | Record a recourse action with a reason as admin; repeat as Operator | Admin action is appended to event history without moving the balance. Operator is denied. No automatic recourse occurs from date/overdue status. |
| Cross-tenant / inactive user | Try reading and mutating another Adda Parchi and try all writes with inactive profile; Super Admin without explicit Adda | Denied without side effects. Super Admin succeeds only with explicit valid Adda context. |
| Direct DML / forged source | As authenticated, try direct table DML and direct source Cashbook/Adda Account insertion, edit, delete and relabel the event ID through either `reference_type` or `reference_id` | Table access is denied; guards reject forgery, mutation, deletion and old/new identity relabeling, including when the type is changed. A client GUC alone cannot authorize a write. |
| Unset transaction marker | Against a disposable fixture, verify an unapproved or unset `ut.issued_freight_parchi_action` cannot create the source-owned commission row | Null action markers are rejected explicitly before the event/actor evidence checks; there is no implicit authorization through SQL NULL behavior. |
| Projection checks | Open Party, Other Adda, Parchi and Adda Account views | Primary payer account shows the principal once. Secondary Party view labels the same shared principal and does not add it to Party totals. Adda Account shows net financing commission separately from Bilty margin/Loading brokerage and has no commission settlement/Cashbook entry. |
| Generic Adda settlement is blocked | As an authorized user, call `settle_adda_account_entry` for a source-owned `issued_parchi_financing_commission` entry | The protected generic RPC rejects the entry because it only settles `manual_adda_expense` and `manual_other_income`; no `adda_finance_settlements` or Cashbook row is created. This validates the existing allow-list boundary without changing the frozen RPC. |
| Print/voice | Detail, preview and print in English and Urdu; enter names/remarks via voice and review before save | Saved names/remarks remain text-safe; Urdu labels render RTL. Printing/preview does not save, post, settle or change balances. |
| Reversal and all views | After reversals, refresh Parchi, account projections, due summaries and prints | Reversed events remain visible; net funding, commission and receipts restore once; outstanding/status return to the correct balance with no duplicate ledger or Cashbook effect. |

## Cleanup and evidence

Use a fresh disposable staging database. Reverse posted money events through the protected RPCs where the tests require it; do not delete append-only Parchi events, Cashbook rows or Adda Account entries. After collecting evidence, discard the entire disposable database. Do not delete or mutate production/historical rows. Keep a run record containing test case, PASS/FAIL/SKIP, action response, event IDs and numeric balance snapshots.

Concurrency, authenticated role checks, trigger behavior and browser rendering require live staging execution. Catalog verifiers do not prove those runtime behaviors.

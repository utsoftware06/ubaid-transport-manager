# Phase 5: Vehicle Monthly Commission Runtime Test Plan

Run these checks only after the Phase 5 migration and single-grid post-verifier pass. Use a non-production test Adda unless the business owner has explicitly authorized the production runtime tests. Record the Adda, vehicle, accounting month, request IDs, event IDs, journal IDs, Owner/Gari transaction IDs, and before/after balances.

## Deployment verification

1. Run `20261007_vehicle_commission_preflight.sql` before deployment. The previously reviewed live result had no mandatory failures; re-run it if the live schema may have changed.
2. Apply `202610070001_vehicle_monthly_commission_integration.sql` once.
3. Run `20261007_vehicle_commission_post_verify.sql`, then `20261007_vehicle_commission_summary_verify.sql`. Continue only if `PHASE_5_OVERALL` is `PASS` (or `WARN` solely for its documented advisory row-count observation).
4. Confirm the settings, events, Owner/Gari transaction source link, functions, RLS, grants, append-only guards, and exact-once indexes match the verifier.

## Runtime cases

| Case | Action | Expected result |
| --- | --- | --- |
| Configure a vehicle | As Adda Admin, save LES123 with amount Rs. 10,000, active, effective October 2026. | One setting for the selected Adda/vehicle; `effective_from` is stored as `2026-10-01`. An Operator cannot save it. A vehicle from another Adda is rejected. |
| Preview October | Preview `2026-10`. | LES123 appears `Ready`, with owner/vehicle display, amount Rs. 10,000, first-of-month date, and no event ID. Preview creates no rows. |
| Generate October | Generate with a fresh request UUID. | One commission event; one Adda Account income entry of Rs. 10,000 with `source_type='vehicle_monthly_commission'` and `source_id=event.id::text`; one Owner/Gari transaction of `-10000` with `transaction_type='monthly_adda_commission'` linked to the same event; no Cashbook row and no Adda settlement. |
| Retry generation | Retry October using the same request UUID, then a different request UUID. | The original event and projections are reused/validated. No extra event, Adda journal row, Owner/Gari transaction, or Cashbook row appears. The result reports the vehicle as already generated. |
| Owner/Gari balance | Compare balance before and after generating Rs. 10,000 commission. | A prior Rs. 50,000 balance becomes Rs. 40,000 under the existing signed ledger convention. The statement labels the commission as a debit and includes its month/event ID. |
| Second vehicle | Configure a different same-Adda vehicle and generate October. | Independent event and one pair of projections for the second vehicle; first vehicle remains unchanged. |
| Inactive setting | Mark a setting inactive and preview/generate a later month. | It is `Not Eligible`; no new event or projections are written. Previously posted history remains unchanged. |
| Future effective date | Set effective month to November and preview October. | October is `Not Eligible`; November can be `Ready` if active and otherwise valid. |
| No inferred vehicle status | Use a same-Adda vehicle without an active/archive field. | Eligibility depends on Adda ownership, active commission setting, positive amount, effective date, and rollout cutoff only. No archive status is inferred. |
| Pre-rollout month | Preview and attempt generation for September 2026 or earlier. | Preview reports `Not Eligible`; generation rejects the request. No historical event or projection is created. |
| Reversal | Reverse the original event with a date on/after its accounting month and a reason. | One append-only reversal event, one opposite Adda Account expense entry linked to the original journal row, and one positive Owner/Gari `monthly_adda_commission_reversal` credit linked to the reversal event. No Cashbook row. Original rows remain intact. |
| Owner/Gari net after reversal | Inspect statement after reversal. | Running/closing balance includes the positive reversal credit; net monthly commission summary is reduced by the reversal and becomes zero for a fully reversed event. Original and reversal rows show month/source/reversal details. |
| Duplicate reversal | Retry with the same request UUID and same parameters; then try a different request against the same original. | Exact retry returns the existing reversal ID and creates nothing further. A second reversal request is rejected. |
| Reversal bounds | Try a reversal date before the accounting month, blank reason, wrong Adda, or a non-original event. | Each invalid request is rejected without partial journal/account changes. |
| Operator access | Preview/history as Operator; attempt setting save, generation, and reversal. | Read-only RPCs work for the Operator’s authorized Adda; write RPCs reject. UI hides management actions. |
| Super Admin scope | Read/write with explicit Adda selection; then attempt a cross-Adda vehicle. | Selected-Adda operations succeed; cross-Adda vehicle/source linkage is rejected. |
| No direct writes | Attempt direct browser DML to commission settings/events or Owner/Gari transactions. | Direct INSERT/UPDATE/DELETE remain denied; all changes go through protected RPCs. |
| Commission projection append-only | In a non-production test environment, attempt to update/delete an original and reversal Owner/Gari commission row through a trusted test path and attempt table truncation. | The commission-specific guard rejects all three operations, including when the general Owner/Gari synchronization context is enabled. The normal withdrawal reversal continues to affect only withdrawal rows. |
| No cash boundary change | Compare Cashbook before/after setting, generation, retry, and reversal. | No commission-related Cashbook rows are created. Actual owner payments continue through their existing separate flows. |
| Accounting reconciliation | Compare Adda Account summary/ledger and Owner/Gari statement. | Adda income equals the event amount; Owner/Gari debit is the same amount with opposite sign; after reversal Adda net income and Owner/Gari net debit both return to zero. Cashbook remains unchanged. |

## Expected source identity

For each original event, the same `adda_vehicle_commission_events.id` links the Adda journal row (`source_type='vehicle_monthly_commission'`, `source_id=event.id::text`) and Owner/Gari transaction (`source_commission_event_id=event.id`). The reversal event gets its own UUID; its Owner/Gari credit points to that reversal event, while the Adda compensating journal row references the original journal through `reverses_entry_id`.

## Rollout boundary and scope

Generation is manual and prospective from October 2026 onward. The migration performs no historical backfill. Preview and generation do not filter by vehicle active/archive status because the deployed `vehicles` schema has no such field. The active commission setting and its effective month define eligibility. Monthly commission recognition never writes Cashbook rows.

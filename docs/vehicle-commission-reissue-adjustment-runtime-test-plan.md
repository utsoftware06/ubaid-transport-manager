# Phase 5B — Vehicle Commission Re-issue and Adjustment Runtime Tests

Run only after applying `202610070002_vehicle_commission_reissue_adjustment.sql`, then run the post-verifier and summary verifier. Use an authorized Adda Admin or Super Admin with explicit Adda context. No test case creates or expects a Cashbook row.

## Setup and lineage

Use the already reversed October 2026 commission for AKK 2178:

- Original commission: `+Rs. 10,000` Adda income and `-Rs. 10,000` Owner/Gari debit.
- Original reversal: `-Rs. 10,000` Adda compensation and `+Rs. 10,000` Owner/Gari credit.
- The original and reversal rows remain unchanged throughout the tests.

## Re-issue

1. Re-issue from the valid reversal with a reason. The RPC derives the new amount from the reversed charge, so the event is `reissue`, amount Rs. 10,000, parent is the reversal event, and root is the original commission.
2. Confirm one new Adda income of Rs. 10,000, one Owner/Gari debit of Rs. 10,000, effective root commission Rs. 10,000, and zero Cashbook rows.
3. Retry with the same request ID and same inputs. It returns the same event and both existing projections; no rows are added.
4. Try a second re-issue from the same reversal using a new request ID. It is rejected by the one-reissue-per-reversal index.
5. Try re-issuing a non-reversed commission, an unrelated reversal, a reversal of an adjustment, and a cross-Adda reversal. Each is rejected.
6. If the reversed charge still has an active adjustment, re-issue is rejected. Reverse that adjustment first, then re-issue is allowed.

## Adjustments and effective amount

Starting from the re-issued Rs. 10,000 charge:

1. Increase by Rs. 2,000. Expected: `adjustment_increase`, Adda income +Rs. 2,000, Owner/Gari debit -Rs. 2,000, effective amount Rs. 12,000.
2. Decrease by Rs. 1,000. Expected: `adjustment_decrease`, Adda expense Rs. 1,000 under the system-only Vehicle Commission Adjustment category, Owner/Gari credit +Rs. 1,000, effective amount Rs. 11,000.
3. Attempt a decrease of Rs. 20,000. It is rejected because the current effective amount cannot fall below zero.
4. Attempt zero, negative, non-finite, or sub-cent amounts; blank/overlong reasons; invalid directions; and a cross-Adda target. All are rejected.
5. Retry a successful increase/decrease with the same request ID and exact inputs. It returns the same event without adding projections. Reuse that request ID with different inputs; it is rejected.
6. Verify the root history still shows every original, reversal, re-issue, increase, and decrease. Signed effects are `+10,000 -10,000 +10,000 +2,000 -1,000`, for effective Rs. 11,000.

## Reversing corrections

1. Reverse the Rs. 2,000 increase. Expected: append a reversal event, Adda expense compensation Rs. 2,000, Owner/Gari credit Rs. 2,000, effective root amount Rs. 9,000 at that point in the sequence.
2. Reverse the Rs. 1,000 decrease. Expected: append a reversal event, Adda income Rs. 1,000, Owner/Gari debit Rs. 1,000, restoring that decrease in the effective total.
3. Reverse the re-issue only after all adjustments on it are reversed. Expected: Adda expense compensation and Owner/Gari credit equal to the re-issue amount.
4. Try reversing a correction twice. The second reversal is rejected; each target has at most one reversal.
5. Retry with the original request ID and exact values; no additional event or projection appears. Retry with altered values under the same request ID; it is rejected.
6. Confirm correction reversals preserve their parent/root/reversed-event links and all existing original/reversal rows.

## Security, exact-once, and reconciliation

1. An Operator may read history and cannot execute any Phase 5B write RPC.
2. Adda Admin can write only within the profile Adda. Super Admin must pass the selected Adda explicitly. Cross-Adda event/vehicle/link attempts are rejected.
3. Direct event, journal, or Owner/Gari UPDATE/DELETE/TRUNCATE attempts remain blocked by append-only protections; browser DML remains unavailable.
4. Attempt duplicate monthly original, duplicate request ID, duplicate re-issue parent, duplicate event projection, and duplicate reversal. Each is blocked by a constraint or protected RPC validation.
5. For each lineage, sum event signed effects and reconcile to Adda Account net P&L and the exact opposite Owner/Gari signed balance effect.
6. Verify no commission correction, re-issue, or reversal wrote to Cashbook.
7. Verify existing withdrawal, Chakkar, opening, unrelated adjustment, Phase 3C, employee, and Bilty behavior is unchanged.
8. Verify old commission/reversal events retain NULL lineage columns and are interpreted through the read-time root derivation. No migration backfill should populate them.

## Expected UI behavior

- A reversed commission reversal row offers **Re-issue** only when the server reports `can_reissue`.
- An active original/re-issued charge offers **Adjust** and **Reverse** according to the server-provided flags.
- An active adjustment offers **Reverse** only.
- Re-issue displays the reversed amount as read-only and requires a reason.
- Adjustment previews the signed difference and effective amount; a decrease below zero cannot be submitted and is also rejected server-side.
- Every successful action refreshes commission history and the Adda Account summary/ledger.
- Errors display the backend message and remain visible; successful actions leave the full event history auditable.

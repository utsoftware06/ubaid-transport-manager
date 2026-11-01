# Adda Account Vehicle Commission Summary Runtime Notes

Run after applying `202610080001_adda_account_vehicle_commission_summary_fix.sql`. Do not use a Cashbook query as commission receipt evidence. This migration changes summary reads only; it does not create or repair financial rows.

## Existing AKK 2178 October 2026 lineage

Current events are original commission Rs. 10,000, reversal Rs. 10,000, re-issue Rs. 10,000, and adjustment increase Rs. 2,000. The effective Phase 5B root amount is Rs. 12,000.

With the stated existing Bilty and manual-income balances, verify the summary returns:

- Total Adda Income: Rs. 72,000
- Bilty Margin (Earned): Rs. 30,000
- Vehicle Commission (effective): Rs. 12,000
- Other Income: Rs. 30,000
- Pending Income: Rs. 0
- Total Adda Expenses: Rs. 30,000
- Net Adda Profit: Rs. 42,000

The Vehicle Commission card is an informational net lineage metric, not an extra amount to add to Total Adda Income. Total Income, Total Expenses, and Net Profit continue to come unchanged from the journal-backed Phase 4 summary.

## Settlement classification

1. Confirm active vehicle commission journal income with no Adda Finance settlement does not contribute to `pending_income`.
2. Confirm manual Other Income unpaid or partially settled remains pending by its `adda_finance_settlements` balance.
3. Confirm Bilty Margin pending remains driven by the Phase 4 authoritative Bilty/Other Adda receipt projection.
4. Confirm vehicle commission leaves `settled_income` and `pending_income` alone unless a valid source-specific rule is introduced later.

## Adjustment decrease treatment

Starting from effective commission Rs. 12,000, append a Rs. 1,000 Phase 5B decrease using the existing protected correction RPC. Expected effective commission is Rs. 11,000. Existing Phase 5B journal behavior records the decrease as a positive Adda expense, so Total Income remains Rs. 72,000, Total Expenses rise by Rs. 1,000, and Net Profit falls by Rs. 1,000. The Vehicle Commission card reads Rs. 11,000 as the net lineage metric and must not be added again to the P&L totals. No Adda Finance settlement or Cashbook row is created by the summary or commission correction.

## Regression checks

- Total Income, Total Expense, Net Profit, Bilty Margin earned/realized/pending, manual settlement balances, and ledger rows match the v2 values except `pending_income` excludes active source-managed commission income.
- Operators can read within existing policy but cannot write through this summary RPC.
- Adda Admin remains limited to the profile Adda; Super Admin must supply an explicit Adda.
- No migration statement writes to event, journal, Owner/Gari, settlement, or Cashbook history.

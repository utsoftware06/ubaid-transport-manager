# Owner/Gari Monthly Closing Runtime Test Plan

This Phase 6 change is a read-only report over the signed Owner/Gari ledger. It creates no closing snapshot and posts no Owner/Gari, Adda Account, or Cashbook rows.

Deploy `supabase/migrations/202610080002_owner_gari_monthly_closing.sql`, then run the detailed post-verifier and the single-grid summary verifier. Run these tests in a non-production or approved runtime environment with Adda-scoped AKK 2178 data.

## Monthly balances

1. Select AKK 2178 and October 2026. Confirm the RPC normalizes any date in October to `2026-10-01` and uses the half-open transaction-date range `2026-10-01 <= transaction_date < 2026-11-01`.
2. Reconcile Opening Balance to the sum of all signed Owner/Gari transaction amounts dated before October 1. Include any `opening_seed` row naturally.
3. Reconcile Total Credits to all positive signed October rows and Total Debits to the absolute value of all negative signed October rows. Confirm both and transaction count cover the complete month, independent of table filters.
4. Confirm Period Net Change equals the signed sum of October rows and Closing Balance equals Opening Balance plus Period Net Change, equivalently Opening Balance + Credits - Debits.
5. Confirm Current Balance is separately calculated from all signed rows dated through the current date and may differ from the selected October closing balance.

## Source breakdown and commission

6. Reconcile Chakkar credits/debits, owner withdrawals, gari withdrawals, voucher adjustment expense, and manual adjustment credit/debit against their signed source rows.
7. Confirm `voucher_adjustment_expense` appears in the Debit column. A negative `chakkar_net_credit` must appear in Debit; a positive Chakkar row appears in Credit regardless of its transaction-type label.
8. Include every Phase 5/5B transaction type: original commission, original reversal, reissue, adjustment increase/decrease, and both correction-reversal types. Verify Owner/Gari Net Commission Charge is the negative of the signed commission-row sum for October.
9. Reconcile same-period Adda Account commission journal income less commission journal expense against Owner/Gari Net Commission Charge. The difference should be zero when projections are complete. Use the two sides' transaction/entry dates in the selected calendar month, not current lineage state.

## Filters, print, and security

10. Change search/type filters on the on-screen ledger. Rows may change, but monthly opening, credits, debits, closing, commission reconciliation, and full-month transaction count must not change.
11. Print the monthly closing while the table is filtered. The printout must still contain every transaction for the selected month, with its own full-month totals and running balance.
12. Verify row ordering for same-day rows is deterministic by transaction date, creation time, and transaction ID, and the monthly running balance begins at opening balance.
13. As an Adda Admin, read only the profile Adda. As Operator, read access is allowed by the existing role contract. As Super Admin, an explicit Adda is required. A vehicle belonging to another Adda must be rejected.
14. Confirm monthly report calls create no Adda journal, Owner/Gari transaction, Cashbook entry, or persisted monthly closing record.

## Expected implementation behavior

- The existing `get_owner_gari_account_statement_v3` remains available for the interactive filtered ledger.
- `get_owner_gari_monthly_closing_v1` returns full-month totals and running balances; optional transaction-type/search inputs filter only its returned rows.
- UI/print credit and debit display follows the actual signed amount. A negative Chakkar net is therefore shown as a debit rather than being forced into credits.
- `current_balance` includes posted transactions through `CURRENT_DATE`; it is labeled separately from the selected month's closing balance.
